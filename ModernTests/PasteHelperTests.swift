//
//  PasteHelperTests.swift
//  iTerm2 ModernTests
//
//  Ported from iTermPasteHelperTest.m. Covers +[iTermPasteHelper sanitizePasteEvent:encoding:]
//  and the paste queue: chunking, bracketing, queued keystrokes and the multi-line paste
//  warning. Timers are captured instead of scheduled so the tests drive the paste to
//  completion synchronously and can measure the total delay the helper asked for.
//

import XCTest
@testable import iTerm2SharedARC

/// Captures the timers the helper would schedule, without adding them to a run loop, so a
/// test can fire them by hand and sum the requested delays.
private final class InstrumentedPasteHelper: iTermPasteHelper {
    var timer: Timer?
    var duration: TimeInterval = 0

    override func scheduledTimer(withTimeInterval ti: TimeInterval,
                                 target aTarget: Any!,
                                 selector aSelector: Selector!,
                                 userInfo: Any!,
                                 repeats yesOrNo: Bool) -> Timer! {
        duration += ti
        let timer = Timer(timeInterval: ti,
                          target: aTarget as Any,
                          selector: aSelector,
                          userInfo: userInfo,
                          repeats: yesOrNo)
        self.timer = timer
        return timer
    }

    func fireTimer() {
        let pending = timer
        timer = nil
        pending?.fire()
    }
}

final class PasteHelperTests: XCTestCase, iTermPasteHelperDelegate, iTermWarningHandler {
    private typealias WarningBlock = (NSAlert?, String?) -> NSApplication.ModalResponse

    // Exercises newline sanitizing, control-code removal and unicode punctuation conversion.
    // The dashes are written as escapes: an en dash then an em dash.
    private let testString = "a (\t\r\r\n\u{16}“”‘’\u{2013}\u{2014}b"
    private let helloWorld = "Hello World"
    private let tolerance = 0.00001

    private var writeBuffer = ""
    private var shouldBracket = false
    private var isAtShellPrompt = false
    private var helper: InstrumentedPasteHelper!
    private var warningBlock: WarningBlock?

    private var multilineWarningIdentifier: String {
        return iTermAdvancedSettingsModel.noSyncDoNotWarnBeforeMultilinePasteUserDefaultsKey()
    }

    override func setUp() {
        super.setUp()
        // Pin every setting the paste path consults so the machine's advanced settings and
        // any leftover chunk-size overrides cannot change the outcome.
        pinAdvancedSetting("PromptForPasteWhenNotAtPrompt", to: false)
        pinAdvancedSetting("SuppressMultilinePasteWarningWhenNotAtShellPrompt", to: false)
        pinAdvancedSetting("SuppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline", to: false)
        pinAdvancedSetting("AlwaysWarnBeforePastingOverSize", to: -1)
        pinAdvancedSetting("StripZeroWidthFormatCharactersOnPaste", to: false)
        // Otherwise history is not recorded while secure keyboard entry is on.
        pinAdvancedSetting("SaveToPasteHistoryWhenSecureInputEnabled", to: true)
        for key in ["QuickPasteBytesPerCall", "QuickPasteDelayBetweenCalls",
                    "SlowPasteBytesPerCall", "SlowPasteDelayBetweenCalls"] {
            pinAdvancedSetting(key, to: nil)
        }

        writeBuffer = ""
        shouldBracket = false
        isAtShellPrompt = false
        helper = InstrumentedPasteHelper()
        helper.delegate = self
        iTermWarning.setWarningHandler(self)
        PasteboardHistory.sharedInstance().clear()
        warningBlock = { [weak self] _, identifier in
            guard let self else { return .alertFirstButtonReturn }
            XCTAssertEqual(identifier, self.multilineWarningIdentifier,
                           "Unexpected warning \(identifier ?? "nil")")
            return .alertFirstButtonReturn
        }
    }

    override func tearDown() {
        Self.resetWarningHandler()
        PasteboardHistory.sharedInstance().clear()
        helper?.delegate = nil
        helper = nil
        warningBlock = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// +[iTermWarning setWarningHandler:] is declared nonnull but nil is the documented way to
    /// go back to showing real alerts, so send the message with a nil argument.
    private static func resetWarningHandler() {
        _ = (iTermWarning.self as AnyObject).perform(#selector(iTermWarning.setWarningHandler(_:)), with: nil)
    }

    private func runTimer() {
        while helper.timer != nil {
            helper.fireTimer()
        }
    }

    private func paste(_ string: String,
                       slowly: Bool = false,
                       escapeShellChars: Bool = false,
                       tabTransform: iTermTabTransformTags = .tabTransformNone,
                       spacesPerTab: Int32 = 0) {
        helper.paste(string,
                           slowly: slowly,
                           escapeShellChars: escapeShellChars,
                           isUpload: false,
                           allowBracketing: true,
                           tabTransform: tabTransform,
                           spacesPerTab: spacesPerTab)
    }

    private func sanitized(_ string: String,
                           flags: iTermPasteFlags,
                           tabTransform: iTermTabTransformTags = .tabTransformNone,
                           spacesPerTab: Int32 = 0,
                           file: StaticString = #filePath,
                           line: UInt = #line) -> String? {
        guard let event = PasteEvent(string: string,
                                     flags: flags,
                                     defaultChunkSize: 1,
                                     chunkKey: nil,
                                     defaultDelay: 1,
                                     delayKey: nil,
                                     tabTransform: tabTransform,
                                     spacesPerTab: spacesPerTab,
                                     regex: nil,
                                     substitution: nil,
                                     shouldPasteNewlinesOutsideBrackets: false) else {
            XCTFail("Could not create paste event", file: file, line: line)
            return nil
        }
        iTermPasteHelper.sanitizePasteEvent(event, encoding: String.Encoding.utf8.rawValue)
        return event.string
    }

    private func historyEntry(_ index: Int, file: StaticString = #filePath, line: UInt = #line) -> String? {
        let entries = PasteboardHistory.sharedInstance().entries() ?? []
        guard index < entries.count else {
            XCTFail("Pasteboard history has \(entries.count) entries, wanted index \(index)", file: file, line: line)
            return nil
        }
        return entries[index].mainValue
    }

    /// Installs a warning block that records whether the multi-line warning was shown and
    /// answers it with the first button (Paste).
    private func recordMultilineWarnings() -> () -> Bool {
        var warned = false
        warningBlock = { [weak self] _, identifier in
            XCTAssertEqual(identifier, self?.multilineWarningIdentifier)
            warned = true
            return .alertFirstButtonReturn
        }
        return { warned }
    }

    // MARK: - Sanitizing

    func testSanitizeIdentity() {
        XCTAssertEqual(sanitized(testString, flags: []), testString)
    }

    func testSanitizeEscapeSpecialCharacters() {
        XCTAssertEqual(sanitized(testString, flags: .pasteFlagsEscapeSpecialCharacters),
                       "a\\ \\(\\\t\r\r\n\u{16}“”‘’\u{2013}\u{2014}b")
    }

    func testSanitizeSanitizingNewlines() {
        XCTAssertEqual(sanitized(testString, flags: .pasteFlagsSanitizingNewlines),
                       "a (\t\r\r\u{16}“”‘’\u{2013}\u{2014}b")
    }

    func testSanitizeRemovingUnsafeControlCodes() {
        XCTAssertEqual(sanitized(testString, flags: .pasteFlagsRemovingUnsafeControlCodes),
                       "a (\t\r\r\n“”‘’\u{2013}\u{2014}b")
    }

    // Bracketing is not part of sanitizing, so the bracket flag alone changes nothing here.
    func testSanitizeBracketFlagAloneLeavesStringUnchanged() {
        XCTAssertEqual(sanitized(testString, flags: .pasteFlagsBracket), testString)
    }

    func testSanitizeBase64Encode() {
        XCTAssertEqual(sanitized("Hello", flags: .pasteFlagsBase64Encode), "SGVsbG8=\r")
    }

    func testSanitizeQuotes() {
        XCTAssertEqual(sanitized("a“”‘’\u{2013}\u{2014}b", flags: .pasteFlagsConvertUnicodePunctuation),
                       "a\"\"''--b")
    }

    func testSanitizeAllFlagsOn() {
        let expectedString = "a\\ \\(\\\t\r\r\\\"\\\"\\'\\'--b"
        let expected = (expectedString.data(using: .utf8)! as NSData).stringWithBase64Encoding(withLineBreak: "\r")
        let flags: iTermPasteFlags = [.pasteFlagsEscapeSpecialCharacters,
                                      .pasteFlagsSanitizingNewlines,
                                      .pasteFlagsRemovingUnsafeControlCodes,
                                      .pasteFlagsBracket,
                                      .pasteFlagsBase64Encode,
                                      .pasteFlagsConvertUnicodePunctuation]
        XCTAssertEqual(sanitized(testString, flags: flags), expected)
    }

    func testSanitizeTabsToSpaces() {
        XCTAssertEqual(sanitized("a\tb", flags: [], tabTransform: .tabTransformConvertToSpaces, spacesPerTab: 4),
                       "a    b")
    }

    func testSanitizeEscapeTabsCtrlV() {
        XCTAssertEqual(sanitized("a\tb", flags: [], tabTransform: .tabTransformEscapeWithCtrlV, spacesPerTab: 4),
                       "a\u{16}\tb")
    }

    // MARK: - Pasting

    func testBasicPasteStringWritesString() {
        paste(helloWorld)
        runTimer()
        XCTAssertEqual(writeBuffer, helloWorld)
    }

    func testBasicPasteStringFitsInOneChunk() {
        paste(helloWorld)
        runTimer()
        XCTAssertEqual(helper.duration, 0)
    }

    func testBasicPasteStringIsSavedToHistory() {
        paste(helloWorld)
        runTimer()
        XCTAssertEqual(historyEntry(0), helloWorld)
    }

    func testDefaultFlagsOnPasteStringSanitizeNewlinesAndRemoveControlCodes() {
        paste(testString)
        runTimer()
        XCTAssertEqual(writeBuffer, "a (\t\r\r“”‘’\u{2013}\u{2014}b")
    }

    func testExpandTabsBeforeEscaping() {
        paste("\t", escapeShellChars: true, tabTransform: .tabTransformConvertToSpaces, spacesPerTab: 4)
        runTimer()
        XCTAssertEqual(writeBuffer, "\\ \\ \\ \\ ")
    }

    func testEscapeDoesNotEscapeCarriageReturn() {
        paste("\r", escapeShellChars: true, tabTransform: .tabTransformConvertToSpaces, spacesPerTab: 4)
        runTimer()
        XCTAssertEqual(writeBuffer, "\r")
    }

    func testPasteStringWithFlagsAndConvertToSpacesTabTransform() {
        paste(testString, escapeShellChars: true, tabTransform: .tabTransformConvertToSpaces, spacesPerTab: 4)
        runTimer()
        XCTAssertEqual(writeBuffer, "a\\ \\(\\ \\ \\ \\ \r\r“”‘’\u{2013}\u{2014}b")
    }

    func testDoNotEscapeNonAscii() {
        paste("“", escapeShellChars: true, tabTransform: .tabTransformEscapeWithCtrlV)
        runTimer()
        XCTAssertEqual(writeBuffer, "“")
    }

    func testStripControlV() {
        paste("\u{16}", escapeShellChars: true, tabTransform: .tabTransformEscapeWithCtrlV)
        runTimer()
        XCTAssertEqual(writeBuffer, "")
    }

    func testPasteStringWithFlagsAndCtrlVTabTransform() {
        paste(testString, escapeShellChars: true, tabTransform: .tabTransformEscapeWithCtrlV)
        runTimer()
        XCTAssertEqual(writeBuffer, "a\\ \\(\u{16}\t\r\r“”‘’\u{2013}\u{2014}b")
    }

    // MARK: - Multi-line warning

    func testMultilineWarningForCRWhenPromptingWhenNotAtPrompt() {
        pinAdvancedSetting("PromptForPasteWhenNotAtPrompt", to: true)
        let warned = recordMultilineWarnings()
        paste("line 1\rline 2")
        XCTAssertTrue(warned())
    }

    func testMultilineWarningForLFWhenPromptingWhenNotAtPrompt() {
        pinAdvancedSetting("PromptForPasteWhenNotAtPrompt", to: true)
        let warned = recordMultilineWarnings()
        paste("line 1\nline 2")
        XCTAssertTrue(warned())
    }

    func testMultilineWarningForCRLFWhenPromptingWhenNotAtPrompt() {
        pinAdvancedSetting("PromptForPasteWhenNotAtPrompt", to: true)
        let warned = recordMultilineWarnings()
        paste("line 1\r\nline 2")
        XCTAssertTrue(warned())
    }

    func testMultilineWarningAnsweredPasteStillPastes() {
        pinAdvancedSetting("PromptForPasteWhenNotAtPrompt", to: true)
        _ = recordMultilineWarnings()
        paste("line 1\nline 2")
        runTimer()
        XCTAssertEqual(writeBuffer, "line 1\rline 2")
    }

    func testNoMultilineWarningForCRWhenNotAtPromptByDefault() {
        let warned = recordMultilineWarnings()
        paste("line 1\rline 2")
        XCTAssertFalse(warned())
    }

    func testNoMultilineWarningForLFWhenNotAtPromptByDefault() {
        let warned = recordMultilineWarnings()
        paste("line 1\nline 2")
        XCTAssertFalse(warned())
    }

    func testNoMultilineWarningForCRLFWhenNotAtPromptByDefault() {
        let warned = recordMultilineWarnings()
        paste("line 1\r\nline 2")
        XCTAssertFalse(warned())
    }

    func testSingleLinePasteGivesNoWarning() {
        pinAdvancedSetting("PromptForPasteWhenNotAtPrompt", to: true)
        let warned = recordMultilineWarnings()
        paste("line 1")
        XCTAssertFalse(warned())
    }

    // MARK: - Bracketing

    func testBracketingOnPasteStringWrapsString() {
        shouldBracket = true
        paste(helloWorld)
        runTimer()
        XCTAssertEqual(writeBuffer, "\u{1b}[200~Hello World\u{1b}[201~")
    }

    func testBracketingOnPasteStringSavesUnbracketedStringToHistory() {
        shouldBracket = true
        paste(helloWorld)
        runTimer()
        XCTAssertEqual(historyEntry(0), helloWorld)
    }

    // You still get a close bracket even if you change your mind about wanting it, unless the
    // whole paste is queued.
    func testDelegateChangesItsMindAboutBracketingNoQueue() {
        let test = String(repeating: " ", count: 2000)
        shouldBracket = true
        paste(test)
        shouldBracket = false
        runTimer()
        XCTAssertEqual(writeBuffer, "\u{1b}[200~" + test + "\u{1b}[201~")
        XCTAssertEqual(helper.duration, 0.02, accuracy: tolerance)
    }

    func testDelegateChangesItsMindAboutBracketingWithQueue() {
        let test1 = String(repeating: "1", count: 2000)
        shouldBracket = true
        paste(test1)
        shouldBracket = false

        let test2 = String(repeating: "2", count: 2000)
        paste(test2)

        runTimer()
        XCTAssertEqual(writeBuffer, "\u{1b}[200~" + test1 + "\u{1b}[201~" + test2)
    }

    // MARK: - Chunking and queueing

    // 2000 bytes at the default 768 bytes per chunk is three chunks, so two delays of 0.01.
    func testTwoChunkPasteString() {
        let test = String(repeating: " ", count: 2000)
        paste(test)
        runTimer()
        XCTAssertEqual(writeBuffer, test)
        XCTAssertEqual(helper.duration, 0.02, accuracy: tolerance)
    }

    // 20 bytes at the slow default of 16 bytes per chunk is two chunks, so one delay of 0.125.
    func testSlowTwoChunkPasteString() {
        let test = String(repeating: " ", count: 20)
        paste(test, slowly: true)
        runTimer()
        XCTAssertEqual(writeBuffer, test)
        XCTAssertEqual(helper.duration, 0.125, accuracy: tolerance)
    }

    func testPasteQueuedWritesBothInOrder() {
        let test1 = String(repeating: "1", count: 2000)
        let test2 = String(repeating: "2", count: 2000)
        paste(test1)
        paste(test2)
        runTimer()
        XCTAssertEqual(writeBuffer, test1 + test2)
        XCTAssertEqual(helper.duration, 4 * 0.01, accuracy: tolerance)
    }

    func testPasteQueuedSavesBothToHistoryInOrder() {
        let test1 = String(repeating: "1", count: 2000)
        let test2 = String(repeating: "2", count: 2000)
        paste(test1)
        paste(test2)
        runTimer()
        XCTAssertEqual(historyEntry(0), test1)
        XCTAssertEqual(historyEntry(1), test2)
    }

    func testQueuedKeystrokeAndPaste() {
        let test1 = String(repeating: "1", count: 2000)
        paste(test1)
        guard let keyDown = NSEvent.keyEvent(with: .keyDown,
                                             location: .zero,
                                             modifierFlags: [],
                                             timestamp: 0,
                                             windowNumber: 0,
                                             context: nil,
                                             characters: "x",
                                             charactersIgnoringModifiers: "x",
                                             isARepeat: false,
                                             keyCode: 0) else {
            XCTFail("Could not synthesize key event")
            return
        }
        helper.enqueue(keyDown)
        let test2 = String(repeating: "2", count: 2000)
        paste(test2)
        runTimer()
        XCTAssertEqual(writeBuffer, test1 + "x" + test2)
        XCTAssertEqual(helper.duration, 4 * 0.01, accuracy: tolerance)
    }

    // MARK: - iTermPasteHelperDelegate

    func pasteHelperWrite(_ string: String) {
        writeBuffer += string
    }

    func pasteHelperKeyDown(_ event: NSEvent) {
        writeBuffer += event.characters ?? ""
    }

    func pasteHelperShouldBracket() -> Bool {
        return shouldBracket
    }

    func pasteHelperEncoding() -> UInt {
        return String.Encoding.utf8.rawValue
    }

    func pasteHelperViewForIndicator() -> NSView! {
        return nil
    }

    func pasteHelperStatusBarViewController() -> iTermStatusBarViewController! {
        return nil
    }

    func pasteHelperIsAtShellPrompt() -> Bool {
        return isAtShellPrompt
    }

    func pasteHelperShouldWaitForPrompt() -> Bool {
        return !isAtShellPrompt
    }

    func pasteHelperCanWaitForPrompt() -> Bool {
        return false
    }

    func pasteHelperPasteViewVisibilityDidChange() {
    }

    func pasteHelperScope() -> iTermVariableScope! {
        return nil
    }

    // MARK: - iTermWarningHandler

    func warningWouldShow(_ alert: NSAlert, identifier: String?) -> NSApplication.ModalResponse {
        guard let warningBlock else {
            XCTFail("Unexpected warning \(identifier ?? "nil")")
            return .alertFirstButtonReturn
        }
        return warningBlock(alert, identifier)
    }
}

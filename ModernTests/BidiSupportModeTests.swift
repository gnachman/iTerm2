//
//  BidiSupportModeTests.swift
//  ModernTests
//
//  BDSM (Bi-Directional Support Mode) is ECMA-48 ANSI mode 8 as revived by the
//  terminal-wg BiDi recommendation. CSI 8 h selects implicit mode, where the
//  terminal reorders right-to-left text itself. CSI 8 l selects explicit mode,
//  where the app has already laid its text out visually and the terminal must
//  leave it alone. A TUI whose layout falls apart under implicit reordering
//  (issue 13102) opts out with CSI 8 l.
//
//  SCP (Select Character Path, CSI Ps1 ; Ps2 SP k) sets the base direction the
//  terminal uses for lines it reorders: 1 is left-to-right, 2 is right-to-left,
//  and 0 (or no parameter) returns to the terminal default, which is the
//  paragraph-direction detection setting.
//
//  The implementation follows WezTerm rather than the full spec: terminal-level
//  values that each line records as right-to-left text is written to it. Text
//  written in explicit mode is never reordered, in the grid or after it scrolls
//  into history, and text written before a switch is untouched. Lines with no
//  right-to-left text are not affected by SCP. An advanced setting, on by
//  default, can turn both escapes off.
//
//  One class on purpose: the advanced settings live in user defaults shared by
//  every parallel test process, and these tests toggle the same key. Tests in
//  one class run serially in one process, so they cannot race each other.
//

import XCTest
@testable import iTerm2SharedARC

final class BidiSupportModeTests: XCTestCase {
    private static let settingKey = "HonorBidiSupportModeEscapeSequence"
    private static let detectKey = "DetectParagraphDirection"
    private static let ESC = "\u{1b}"
    private static let explicitMode = "\(ESC)[8l"
    private static let implicitMode = "\(ESC)[8h"
    private static let requestMode = "\(ESC)[8$p"
    private static let pathLTR = "\(ESC)[1 k"
    private static let pathRTL = "\(ESC)[2 k"
    private static let pathDefault = "\(ESC)[0 k"
    private static let hardReset = "\(ESC)c"

    private let hebrew = "שלום עולם"
    // Latin first, so first-strong detection would say left-to-right.
    private let latinFirst = "abc שלום"
    // Hebrew first, so first-strong detection would say right-to-left.
    private let hebrewFirst = "שלום abc"

    private var savedSetting: Any?
    private var savedDetect: Any?

    // [iTermPreferences bidiEnabled] is a fast-path cache updated via async
    // KVO dispatched to the main queue; pump the runloop until it lands.
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private func setAdvanced(_ key: String, _ on: Bool) {
        iTermUserDefaults.userDefaults().set(on, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }

    private func restore(_ key: String, _ value: Any?) {
        if let value {
            iTermUserDefaults.userDefaults().set(value, forKey: key)
        } else {
            iTermUserDefaults.userDefaults().removeObject(forKey: key)
        }
    }

    override func setUp() {
        super.setUp()
        savedSetting = iTermUserDefaults.userDefaults().object(forKey: Self.settingKey)
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: Self.detectKey)
        setBidiPreference(true)
        setAdvanced(Self.settingKey, true)
    }

    override func tearDown() {
        restore(Self.settingKey, savedSetting)
        restore(Self.detectKey, savedDetect)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidiPreference(false)
        super.tearDown()
    }

    // MARK: - Helpers

    // The harness terminal defaults to a non-UTF-8 encoding; Hebrew needs UTF-8.
    private func makeHarness(width: Int = 80, height: Int = 24) -> TerminalTestHarness {
        let harness = TerminalTestHarness(width: width, height: height)
        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal!.encoding = String.Encoding.utf8.rawValue
            terminal!.canonicalEncoding = String.Encoding.utf8.rawValue
        })
        return harness
    }

    // Runs the bytes through the real parser and terminal on the mutation
    // thread. After a reset, call settleAfterReset before feeding more.
    private func feed(_ harness: TerminalTestHarness, _ string: String) {
        let data = string.data(using: .utf8)!
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.inject(data)
        })
        harness.screen.performBlock(joinedThreads: { _, _, _ in })
    }

    // A reset pauses token execution until a side effect on the main queue
    // unpauses it. Let the main queue run to a sentinel (FIFO, so the side
    // effect has run too), then join the mutation queue. No fixed delays.
    private func settleAfterReset(_ harness: TerminalTestHarness,
                                  file: StaticString = #filePath, line: UInt = #line) {
        var sentinelRan = false
        DispatchQueue.main.async { sentinelRan = true }
        let deadline = Date().addingTimeInterval(10)
        while !sentinelRan && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(sentinelRan, "main queue never drained", file: file, line: line)
        harness.screen.performBlock(joinedThreads: { _, _, _ in })
    }

    // Populates RTL state the way the per-frame sync does before every draw.
    private func populate(_ harness: TerminalTestHarness) {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.populateRTLStateIfNeeded()
        })
    }

    private func gridBidiInfo(_ harness: TerminalTestHarness, line: Int32) -> BidiDisplayInfoObjc? {
        var info: BidiDisplayInfoObjc?
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            info = mutableState.currentGrid.bidiInfo(forLine: line)
        })
        return info
    }

    // Tokens fed while a reset's unpause is still in flight execute once it
    // lands, on the executor's own schedule. Wait for their effect rather than
    // for a fixed time: pump the main queue, join the mutation queue, populate,
    // and check, until the line has bidi info or the deadline passes.
    private func waitForGridBidiInfo(_ harness: TerminalTestHarness, line: Int32) -> BidiDisplayInfoObjc? {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            populate(harness)
            if let info = gridBidiInfo(harness, line: line) {
                return info
            }
        }
        return nil
    }

    private func gridRTLFound(_ harness: TerminalTestHarness, line: Int32) -> Bool {
        var found = false
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            found = mutableState.currentGrid.lineInfo(atLineNumber: line).rtlFound()
        })
        return found
    }

    private func bidiSupportMode(_ harness: TerminalTestHarness) -> Bool {
        var mode = false
        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            mode = terminal!.bidiSupportMode
        })
        return mode
    }

    private func hint(_ harness: TerminalTestHarness) -> iTermBidiDirection {
        var value = iTermBidiDirection.default
        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            value = terminal!.bidiDirectionHint
        })
        return value
    }

    private func lastReport(_ harness: TerminalTestHarness) -> String? {
        guard let data = harness.delegate.sentReports.last else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func stateDictionary(_ harness: TerminalTestHarness) -> [AnyHashable: Any] {
        var dict: [AnyHashable: Any] = [:]
        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            dict = terminal!.stateDictionary
        })
        return dict
    }

    // MARK: - BDSM mode tracking

    func testImplicitModeIsTheDefault() {
        let harness = makeHarness()
        XCTAssertTrue(bidiSupportMode(harness))
        feed(harness, hebrew + "\r\n")
        populate(harness)
        XCTAssertNotNil(gridBidiInfo(harness, line: 0), "implicit mode must reorder RTL text")
    }

    func testExplicitModeLeavesNewTextUnreordered() {
        let harness = makeHarness()
        feed(harness, Self.explicitMode + hebrew + "\r\n")
        XCTAssertFalse(bidiSupportMode(harness))
        populate(harness)
        XCTAssertFalse(gridRTLFound(harness, line: 0),
                       "a line written in explicit mode must not be flagged as containing RTL")
        XCTAssertNil(gridBidiInfo(harness, line: 0),
                     "a line written in explicit mode must not be reordered")
    }

    func testSetModeRestoresReorderingForSubsequentText() {
        let harness = makeHarness()
        feed(harness, Self.explicitMode + hebrew + "\r\n" + Self.implicitMode + hebrew + "\r\n")
        XCTAssertTrue(bidiSupportMode(harness))
        populate(harness)
        XCTAssertNil(gridBidiInfo(harness, line: 0), "the explicit-mode line keeps its snapshot")
        XCTAssertNotNil(gridBidiInfo(harness, line: 1), "the implicit-mode line is reordered")
    }

    // A line written in implicit mode keeps reordering even if the mode changes
    // afterwards: the mode is recorded per line as it is written.
    func testSwitchingToExplicitModeDoesNotAffectExistingText() {
        let harness = makeHarness()
        feed(harness, hebrew + "\r\n" + Self.explicitMode)
        populate(harness)
        XCTAssertNotNil(gridBidiInfo(harness, line: 0))
    }

    func testHardResetRestoresImplicitMode() {
        let harness = makeHarness()
        feed(harness, Self.explicitMode)
        XCTAssertFalse(bidiSupportMode(harness))
        feed(harness, Self.hardReset)
        settleAfterReset(harness)
        XCTAssertTrue(bidiSupportMode(harness))
        feed(harness, hebrew + "\r\n")
        XCTAssertNotNil(waitForGridBidiInfo(harness, line: 0))
    }

    // MARK: - Issue 13102, the reported TUI row

    // The visual (drawn) order of a grid line, read through the bidi reorder
    // map the way the renderer does. With no map the line draws as written.
    private func visualOrder(_ harness: TerminalTestHarness, line: Int32) -> String {
        let sca = harness.screen.screenCharArray(forLine: line)
        let logical = Array(sca.stringValue)
        guard let bidi = gridBidiInfo(harness, line: line) else { return sca.stringValue }
        var s = ""
        for v in 0..<Int(bidi.numberOfCells) {
            let lg = Int(bidi.logicalForVisual(Int32(v)))
            if lg >= 0 && lg < logical.count { s.append(logical[lg]) }
        }
        return s
    }

    // A Ratatui screen row from the report: a sidebar item that is entirely
    // Hebrew, two vertical borders, and a numbered popup entry. Treated as one
    // paragraph, the bidi algorithm pulls the borders and the digit into the
    // Hebrew run (rule N1: neutrals between an R and a digit resolve to R), so
    // the digit lands left of the Hebrew and the borders shift.
    private let reportedRow = "    ■ שלם      │   │       │ 5 : Deck        │"

    // Characterizes the reported bug under the default, implicit mode: the row
    // is scrambled. If reordering ever stops treating a TUI row as a paragraph,
    // this assertion is the one to update.
    func testReportedRowIsScrambledInImplicitMode() {
        let harness = makeHarness()
        feed(harness, reportedRow + "\r\n")
        populate(harness)
        let visual = visualOrder(harness, line: 0)
        XCTAssertNotEqual(visual, reportedRow)
        // The popup's "5" is drawn to the left of the Hebrew word.
        let digit = visual.firstIndex(of: "5")!
        let hebrew = visual.firstIndex(of: "ש")!
        XCTAssertLessThan(digit, hebrew, "the digit jumps out of the popup: \(visual)")
    }

    // The fix the reporter's app can apply: explicit mode draws the row as written.
    func testReportedRowIsIntactInExplicitMode() {
        let harness = makeHarness()
        feed(harness, Self.explicitMode + reportedRow + "\r\n")
        populate(harness)
        XCTAssertEqual(visualOrder(harness, line: 0), reportedRow)
    }

    // MARK: - Explicit mode clears stale RTL state

    // The per-line RTL flag is sticky: erasing or overwriting a line does not
    // reset it. So a line that held RTL text in implicit mode must have the flag
    // cleared when an app writes to it in explicit mode, or the app's visually
    // laid out text is still reordered. The per-cell RTL status that the last
    // analysis wrote must go too, or the renderer still forces a right-to-left
    // writing direction on those cells with no reorder table behind it.

    private func gridHasRTLCell(_ harness: TerminalTestHarness, line: Int32) -> Bool {
        var found = false
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            guard let sca = mutableState.currentGrid.screenCharArray(atLine: line) else { return }
            let cells = sca.line
            for i in 0..<Int(sca.length) where cells[i].rtlStatus == .RTL {
                found = true
            }
        })
        return found
    }

    private func historyHasRTLCell(_ harness: TerminalTestHarness, line: Int32) -> Bool {
        let sca = harness.screen.screenCharArray(forLine: line)
        let cells = sca.line
        for i in 0..<Int(sca.length) where cells[i].rtlStatus == .RTL {
            return true
        }
        return false
    }

    // Leaves the cursor on line 0, which holds Hebrew analyzed in implicit mode.
    private func harnessWithAnalyzedHebrewOnLine0(width: Int = 80, height: Int = 24) -> TerminalTestHarness {
        let harness = makeHarness(width: width, height: height)
        feed(harness, hebrew)
        populate(harness)
        XCTAssertTrue(gridRTLFound(harness, line: 0), "precondition")
        XCTAssertNotNil(gridBidiInfo(harness, line: 0), "precondition")
        XCTAssertTrue(gridHasRTLCell(harness, line: 0), "precondition")
        return harness
    }

    private func assertLine0HasNoRTLState(_ harness: TerminalTestHarness,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(gridRTLFound(harness, line: 0), "stale RTL flag", file: file, line: line)
        XCTAssertNil(gridBidiInfo(harness, line: 0), "line is still reordered", file: file, line: line)
        XCTAssertFalse(gridHasRTLCell(harness, line: 0), "stale per-cell RTL status", file: file, line: line)
    }

    // The inline TUI case: erase the line and write pre-ordered text.
    func testExplicitModeEraseAndRewriteClearsStaleRTL() {
        let harness = harnessWithAnalyzedHebrewOnLine0()
        feed(harness, Self.explicitMode + "\r\(Self.ESC)[2Kabc םולש")
        populate(harness)
        assertLine0HasNoRTLState(harness)
    }

    // A partial ASCII overwrite: the Hebrew cells that remain must be reset too.
    func testExplicitModePartialOverwriteClearsStaleRTL() {
        let harness = harnessWithAnalyzedHebrewOnLine0()
        feed(harness, Self.explicitMode + "\rab")
        populate(harness)
        assertLine0HasNoRTLState(harness)
    }

    // A lone combining mark edits the predecessor in place without going
    // through the grid's append.
    func testExplicitModeCombiningMarkClearsStaleRTL() {
        let harness = harnessWithAnalyzedHebrewOnLine0()
        feed(harness, Self.explicitMode + "\u{05B0}")
        populate(harness)
        assertLine0HasNoRTLState(harness)
    }

    // The line scrolls into history before the next analysis pass runs, so
    // nothing but the write itself gets a chance to reset the cells.
    func testStaleRTLDoesNotFollowAnExplicitlyRewrittenLineIntoHistory() {
        let harness = harnessWithAnalyzedHebrewOnLine0(width: 40, height: 3)
        feed(harness, Self.explicitMode + "\rab\r\n\r\n\r\n\r\n")
        populate(harness)
        XCTAssertNil(harness.screen.bidiInfo(forLine: 0))
        XCTAssertFalse(historyHasRTLCell(harness, line: 0), "stale per-cell RTL status in history")
    }

    // The analysis pass itself must reset the cells when it drops a line's
    // bidi info, whatever cleared the flag. Clear the flag behind its back so
    // the write-time reset is not what makes this pass.
    func testAnalysisPassResetsCellStatusWhenItDropsBidiInfo() {
        let harness = harnessWithAnalyzedHebrewOnLine0()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            grid.lineInfo(atLineNumber: 0).setRTLFound(false)
            grid.markLineDidChange(0)
        })
        XCTAssertTrue(gridHasRTLCell(harness, line: 0), "precondition: only the flag was cleared")
        populate(harness)
        XCTAssertNil(gridBidiInfo(harness, line: 0))
        XCTAssertFalse(gridHasRTLCell(harness, line: 0), "stale per-cell RTL status")
    }

    // Control: in implicit mode an ASCII overwrite must NOT clear the flag,
    // because the Hebrew that remains on the line still needs reordering.
    func testImplicitModeOverwriteKeepsRTLState() {
        let harness = harnessWithAnalyzedHebrewOnLine0()
        feed(harness, "\rab")
        populate(harness)
        XCTAssertTrue(gridRTLFound(harness, line: 0))
        XCTAssertNotNil(gridBidiInfo(harness, line: 0))
    }

    // MARK: - BDSM scrollback

    func testExplicitModeTextStaysUnreorderedAfterScrollingIntoHistory() {
        let harness = makeHarness(width: 40, height: 3)
        feed(harness, Self.explicitMode)
        for _ in 0..<5 {
            feed(harness, hebrew + "\r\n")
        }
        populate(harness)
        // Line 0 is now in the line buffer, not the grid.
        XCTAssertNil(harness.screen.bidiInfo(forLine: 0),
                     "explicit-mode text must not be reordered once it scrolls into history")
    }

    // The control for the test above: the same writes in implicit mode do
    // reorder in history, so a nil there is meaningful.
    func testImplicitModeTextIsReorderedAfterScrollingIntoHistory() {
        let harness = makeHarness(width: 40, height: 3)
        for _ in 0..<5 {
            feed(harness, hebrew + "\r\n")
        }
        populate(harness)
        XCTAssertNotNil(harness.screen.bidiInfo(forLine: 0))
    }

    // MARK: - BDSM advanced setting gate and DECRQM

    func testEscapeIsIgnoredWhenSettingIsOff() {
        setAdvanced(Self.settingKey, false)
        let harness = makeHarness()
        feed(harness, Self.explicitMode + hebrew + "\r\n")
        XCTAssertTrue(bidiSupportMode(harness), "the mode must not change while the setting is off")
        populate(harness)
        XCTAssertNotNil(gridBidiInfo(harness, line: 0))
    }

    func testRequestModeReportsCurrentState() {
        let harness = makeHarness()
        feed(harness, Self.requestMode)
        XCTAssertEqual(lastReport(harness), "\(Self.ESC)[8;1$y", "implicit mode reports as set")
        feed(harness, Self.explicitMode + Self.requestMode)
        XCTAssertEqual(lastReport(harness), "\(Self.ESC)[8;2$y", "explicit mode reports as reset")
    }

    func testRequestModeReportsPermanentlyResetWhenSettingIsOff() {
        setAdvanced(Self.settingKey, false)
        let harness = makeHarness()
        feed(harness, Self.requestMode)
        XCTAssertEqual(lastReport(harness), "\(Self.ESC)[8;4$y",
                       "with the setting off mode 8 reports permanently reset, as before")
    }

    func testRequestModeReportsPermanentlyResetWhenBidiIsOff() {
        setBidiPreference(false)
        let harness = makeHarness()
        feed(harness, Self.requestMode)
        XCTAssertEqual(lastReport(harness), "\(Self.ESC)[8;4$y",
                       "with right-to-left support off nothing is reordered, so mode 8 reports permanently reset")
    }

    func testStateDictionaryRoundTripsExplicitMode() {
        let harness = makeHarness()
        feed(harness, Self.explicitMode)
        let restored = VT100Terminal()
        restored.setStateFrom(stateDictionary(harness))
        XCTAssertFalse(restored.bidiSupportMode)
    }

    // MARK: - SCP direction

    func testDefaultIsLeftToRightWhenDetectionIsOff() {
        setAdvanced(Self.detectKey, false)
        defer {
            restore(Self.detectKey, savedDetect)
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        let harness = makeHarness()
        XCTAssertEqual(hint(harness), .default)
        feed(harness, hebrewFirst + "\r\n")
        populate(harness)
        let info = gridBidiInfo(harness, line: 0)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.paragraphIsRTL, false)
    }

    func testRightToLeftPathForcesRTLParagraph() {
        let harness = makeHarness()
        feed(harness, Self.pathRTL + latinFirst + "\r\n")
        XCTAssertEqual(hint(harness), .rightToLeft)
        populate(harness)
        let info = gridBidiInfo(harness, line: 0)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.paragraphIsRTL, true,
                       "SCP 2 must make the paragraph right-to-left even when it starts with Latin")
    }

    // Other bidi test classes toggle the same shared detection key, so set it
    // only in the tests whose outcome depends on it and keep that window short.
    func testLeftToRightPathOverridesDetection() {
        setAdvanced(Self.detectKey, true)
        defer {
            restore(Self.detectKey, savedDetect)
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        let harness = makeHarness()
        // Control: with detection on and no SCP, a Hebrew-first line detects as RTL.
        feed(harness, hebrewFirst + "\r\n")
        feed(harness, Self.pathLTR + hebrewFirst + "\r\n")
        populate(harness)
        XCTAssertEqual(gridBidiInfo(harness, line: 0)?.paragraphIsRTL, true, "control: detection says RTL")
        XCTAssertEqual(gridBidiInfo(harness, line: 1)?.paragraphIsRTL, false, "SCP 1 overrides detection")
    }

    func testDefaultPathRestoresTerminalDefault() {
        let harness = makeHarness()
        feed(harness, Self.pathRTL + Self.pathDefault + latinFirst + "\r\n")
        XCTAssertEqual(hint(harness), .default)
        populate(harness)
        XCTAssertEqual(gridBidiInfo(harness, line: 0)?.paragraphIsRTL, false)
    }

    func testNoParameterMeansDefault() {
        let harness = makeHarness()
        feed(harness, Self.pathRTL + "\(Self.ESC)[ k")
        XCTAssertEqual(hint(harness), .default)
    }

    func testSecondParameterIsAccepted() {
        let harness = makeHarness()
        feed(harness, "\(Self.ESC)[2;0 k")
        XCTAssertEqual(hint(harness), .rightToLeft)
    }

    func testUnknownValueIsIgnored() {
        let harness = makeHarness()
        feed(harness, Self.pathRTL + "\(Self.ESC)[7 k")
        XCTAssertEqual(hint(harness), .rightToLeft)
    }

    // MARK: - SCP per-line snapshot

    func testDirectionIsRecordedPerLine() {
        let harness = makeHarness()
        feed(harness, Self.pathRTL + latinFirst + "\r\n" + Self.pathLTR + latinFirst + "\r\n")
        populate(harness)
        XCTAssertEqual(gridBidiInfo(harness, line: 0)?.paragraphIsRTL, true)
        XCTAssertEqual(gridBidiInfo(harness, line: 1)?.paragraphIsRTL, false)
    }

    func testDirectionSurvivesScrollingIntoHistory() {
        let harness = makeHarness(width: 40, height: 3)
        feed(harness, Self.pathRTL)
        for _ in 0..<5 {
            feed(harness, latinFirst + "\r\n")
        }
        populate(harness)
        // Line 0 is now in the line buffer, not the grid.
        let info = harness.screen.bidiInfo(forLine: 0)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.paragraphIsRTL, true,
                       "a line's recorded direction must survive the move into history")
    }

    // MARK: - SCP with BDSM, the setting, and reset

    func testExplicitModeStillLeavesTextUnreorderedWithPath() {
        let harness = makeHarness()
        feed(harness, Self.explicitMode + Self.pathRTL + latinFirst + "\r\n")
        populate(harness)
        XCTAssertNil(gridBidiInfo(harness, line: 0), "the direction hint does not reorder in explicit mode")
    }

    func testPathIsIgnoredWhenSettingIsOff() {
        setAdvanced(Self.settingKey, false)
        let harness = makeHarness()
        feed(harness, Self.pathRTL + latinFirst + "\r\n")
        XCTAssertEqual(hint(harness), .default)
        populate(harness)
        XCTAssertEqual(gridBidiInfo(harness, line: 0)?.paragraphIsRTL, false)
    }

    func testHardResetRestoresDefaultPath() {
        let harness = makeHarness()
        feed(harness, Self.pathRTL)
        XCTAssertEqual(hint(harness), .rightToLeft)
        feed(harness, Self.hardReset)
        settleAfterReset(harness)
        XCTAssertEqual(hint(harness), .default)
    }

    func testStateDictionaryRoundTripsPath() {
        let harness = makeHarness()
        feed(harness, Self.pathRTL)
        let restored = VT100Terminal()
        restored.setStateFrom(stateDictionary(harness))
        XCTAssertEqual(restored.bidiDirectionHint, .rightToLeft)
    }
}

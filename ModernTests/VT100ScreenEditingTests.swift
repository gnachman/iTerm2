//
//  VT100ScreenEditingTests.swift
//  iTerm2
//
//  Ported from the second half of the legacy iTerm2XCTests/VT100ScreenTest.m
//  (testScrollingInAltScreen through the end of the file): dirty tracking,
//  DVR frames, terminal-delegate driven editing (backspace, tab stops, cursor
//  movement, scroll regions, erase, insert and delete), window size reports,
//  resizing with a selection and assorted regressions.
//

import XCTest
@testable import iTerm2SharedARC

/// Delegate stub that records the calls these tests observe.
private class VT100ScreenEditingSession: FakeSession {
    var allowTitleSetting = true
    var windowTitles = [String]()
    var iconNames = [String]()
    var cursorVisible = true
    var printedStrings = [String]()
    var printVisibleAreaCount = 0
    var contentsChangedNotification = false
    var pasteboardName: String?
    var pasteboardData = Data()
    var copiedBufferToPasteboard = false
    var sentReports = [Data]()
    var resizePermission = PTYSessionResizePermission.allowed
    var fullscreen = false
    var resizeRequests = [VT100GridSize]()
    var pointSizeRequests = [NSSize]()
    var workingDirectoryLog = [(absLine: Int64, directory: String?)]()
    var polledWorkingDirectory: String? = "/"

    override func screenAllowTitleSetting() -> Bool {
        allowTitleSetting
    }

    override func screenSetWindowTitle(_ title: String) {
        windowTitles.append(title)
    }

    override func screenSetIconName(_ name: String) {
        iconNames.append(name)
    }

    override func screenSetCursorVisible(_ visible: Bool) {
        cursorVisible = visible
    }

    override func screenPrintStringIfAllowed(_ printBuffer: String, completion: @escaping () -> Void) {
        printedStrings.append(printBuffer)
        completion()
    }

    override func screenPrintVisibleAreaIfAllowed() {
        printVisibleAreaCount += 1
    }

    override func screenShouldSendContentsChangedNotification() -> Bool {
        contentsChangedNotification
    }

    override func screenSetPasteboard(_ value: String) {
        pasteboardName = value
    }

    override func screenAppendData(toPasteboard data: Data) {
        pasteboardData.append(data)
    }

    override func screenCopyBufferToPasteboard() {
        copiedBufferToPasteboard = true
    }

    override func screenSendReport(_ data: Data) {
        sentReports.append(data)
    }

    override func screenShouldInitiateWindowResize() -> PTYSessionResizePermission {
        resizePermission
    }

    override func screenWindowIsFullscreen() -> Bool {
        fullscreen
    }

    override func screenResize(toWidth width: Int32, height: Int32) {
        resizeRequests.append(VT100GridSizeMake(width, height))
    }

    override func screenSetPointSize(_ proposedSize: NSSize) {
        pointSizeRequests.append(proposedSize)
    }

    override func screenGetWorkingDirectory(completion: @escaping (String?) -> Void) {
        completion(polledWorkingDirectory)
    }

    override func screenLogWorkingDirectory(onAbsoluteLine absLine: Int64,
                                            remoteHost: (any VT100RemoteHostReading)?,
                                            withDirectory directory: String?,
                                            pushType: VT100ScreenWorkingDirectoryPushType,
                                            accepted: Bool) {
        workingDirectoryLog.append((absLine: absLine, directory: directory))
    }
}

private extension VT100ScreenMutableState {
    // VT100ScreenState.cursorX/cursorY are 1-based (grid.cursorX + 1), like the legacy
    // VT100Screen.cursorX/cursorY the old tests read. These aliases make that explicit.
    var oneBasedCursorX: Int32 {
        cursorX
    }

    var oneBasedCursorY: Int32 {
        cursorY
    }
}

class VT100ScreenEditingTests: XCTestCase {
    private var session = VT100ScreenEditingSession()

    override func setUp() {
        super.setUp()
        session = VT100ScreenEditingSession()
    }

    // MARK: - Helpers

    private func makeScreen(width: Int32,
                            height: Int32,
                            maxScrollbackLines: Int32 = 1000,
                            printingAllowed: Bool = true,
                            saveToScrollbackInAlternateScreen: Bool = false) -> VT100Screen {
        session.configuration.unicodeVersion = 9
        session.configuration.maxScrollbackLines = maxScrollbackLines
        session.configuration.printingAllowed = printingAllowed
        session.configuration.saveToScrollbackInAlternateScreen = saveToScrollbackInAlternateScreen
        session.configuration.isDirty = true
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    private func sync(_ screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    private func mutate(_ screen: VT100Screen,
                        _ block: (VT100Terminal?, VT100ScreenMutableState) -> Void) {
        screen.performBlock(joinedThreads: { terminal, mutableState, _ in
            block(terminal, mutableState)
        })
    }

    /// Feeds a string through the real parser and executes the resulting tokens.
    private func feed(_ screen: VT100Screen, _ string: String) {
        screen.inject(Data(string.utf8))
        sync(screen)
    }

    /// Syncs and spins the run loop until `condition` holds. Used for work that hops through
    /// the mutation queue asynchronously (reports, working directory fetches).
    private func waitUntil(_ screen: VT100Screen,
                           timeout: TimeInterval = 10,
                           file: StaticString = #filePath,
                           line: UInt = #line,
                           _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            sync(screen)
            if condition() {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private func appendLines(_ lines: [String], to screen: VT100Screen) {
        mutate(screen) { _, mutableState in
            for line in lines {
                mutableState.appendString(atCursor: line)
                mutableState.terminalCarriageReturn()
                mutableState.terminalLineFeed()
            }
        }
    }

    private func appendLinesNoNewline(_ lines: [String], to screen: VT100Screen) {
        mutate(screen) { _, mutableState in
            for (i, line) in lines.enumerated() {
                mutableState.appendString(atCursor: line)
                if i + 1 != lines.count {
                    mutableState.terminalCarriageReturn()
                    mutableState.terminalLineFeed()
                }
            }
        }
    }

    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    // Cursor at first col of last row.
    private func fiveByFourScreenWithThreeLinesOneWrapped() -> VT100Screen {
        let screen = makeScreen(width: 5, height: 4)
        appendLines(["abcdefgh", "ijkl"], to: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       ".....")
        return screen
    }

    /// Builds a screen from lines like "abcD-fghij+" where '.' is null, '-' is DWC_RIGHT and the
    /// trailing character is the continuation mark: '!' hard EOL, '+' soft EOL, '>' DWC EOL.
    private func screenFromCompactLinesWithContinuationMarks(_ compactLines: String) -> VT100Screen {
        let lines = compactLines.components(separatedBy: "\n")
        let width = Int32(lines[0].utf16.count - 1)
        let screen = makeScreen(width: width, height: Int32(lines.count))
        mutate(screen) { _, mutableState in
            for (i, line) in lines.enumerated() {
                let chars = Array(line.utf16)
                guard let s = mutableState.currentGrid.screenChars(atLineNumber: Int32(i)) else {
                    XCTFail("No line \(i)")
                    return
                }
                let last = chars.count - 1
                for j in 0..<last {
                    var c = chars[j]
                    if c == UInt16(UInt8(ascii: ".")) {
                        c = 0
                    }
                    if c == UInt16(UInt8(ascii: "-")) {
                        c = unichar(DWC_RIGHT)
                        mutableState.linebuffer.mayHaveDoubleWidthCharacter = true
                    }
                    s[j].code = c
                }
                switch chars[last] {
                case UInt16(UInt8(ascii: "!")):
                    s[last].code = unichar(EOL_HARD)
                case UInt16(UInt8(ascii: "+")):
                    s[last].code = unichar(EOL_SOFT)
                case UInt16(UInt8(ascii: ">")):
                    mutableState.linebuffer.mayHaveDoubleWidthCharacter = true
                    s[last].code = unichar(EOL_DWC)
                default:
                    XCTFail("Bogus continuation mark in \(line)")
                }
            }
            mutableState.currentGrid.markAllCharsDirty(true, updateTimestamps: false)
        }
        return screen
    }

    private func lineString(_ screen: VT100Screen, _ line: Int32) -> String {
        let sca = screen.screenCharArray(forLine: line)
        return ScreenCharArrayToStringDebug(sca.line, sca.length)
    }

    /// Returns the 0-based columns of the tab stops reachable from the start of the current line.
    private func tabStops(in mutableState: VT100ScreenMutableState) -> [Int32] {
        var actual = [Int32]()
        mutableState.terminalCarriageReturn()
        var lastX = mutableState.cursorX
        while true {
            mutableState.terminalAppendTab(atCursor: false)
            if mutableState.cursorX == lastX {
                return actual
            }
            actual.append(mutableState.cursorX - 1)
            lastX = mutableState.cursorX
        }
    }

    private func tabStops(in screen: VT100Screen) -> [Int32] {
        var result = [Int32]()
        mutate(screen) { _, mutableState in
            result = tabStops(in: mutableState)
        }
        return result
    }

    private func showAltAndUppercase(_ screen: VT100Screen) {
        mutate(screen) { _, mutableState in
            guard let temp = mutableState.currentGrid.copy() else {
                XCTFail("Could not copy grid")
                return
            }
            mutableState.showAltBuffer()
            let w = Int(mutableState.width)
            for y in 0..<mutableState.height {
                guard let lineIn = temp.screenChars(atLineNumber: y),
                      let lineOut = mutableState.currentGrid.screenChars(atLineNumber: y) else {
                    XCTFail("No line \(y)")
                    return
                }
                for x in 0..<w {
                    lineOut[x] = lineIn[x]
                    var c = lineIn[x].code
                    if isalpha(Int32(c)) != 0 {
                        c -= 32
                    }
                    lineOut[x].code = c
                }
                lineOut[w] = lineIn[w]
            }
            mutableState.currentGrid.markAllCharsDirty(true, updateTimestamps: false)
        }
    }

    // MARK: - Dirty tracking

    func testScrollingInAltScreenWithScrollbackSavesScrolledLine() {
        let screen = makeScreen(width: 2, height: 3, maxScrollbackLines: 3, saveToScrollbackInAlternateScreen: true)
        appendLines(["0", "1", "2", "3", "4"], to: screen)
        showAltAndUppercase(screen)
        var overflow = Int32(-1)
        var dirtyDump = ""
        mutate(screen) { _, mutableState in
            mutableState.currentGrid.markAllCharsDirty(false, updateTimestamps: false)
            mutableState.terminalLineFeed()
            overflow = mutableState.scrollbackOverflow
            dirtyDump = mutableState.currentGrid.compactDirtyDump()
        }
        XCTAssertEqual(overflow, 1)
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "1.\n" +
                       "2.\n" +
                       "3.\n" +
                       "4.\n" +
                       "..\n" +
                       "..")
        // Dirty state is tracked per line now (VT100LineInfo keeps one flag for the whole
        // line), so the row that held the cursor is entirely dirty rather than just the cursor
        // cell as the legacy test expected ("dc"). The row that scrolled up unchanged stays clean.
        XCTAssertEqual(dirtyDump,
                       "cc\n" +
                       "dd\n" +
                       "dd")
    }

    func testScrollingInAltScreenWithoutScrollbackMarksWholeScreenDirty() {
        // When in alt screen and scrolling and not saving to scrollback, the whole screen must be
        // marked dirty.
        let screen = makeScreen(width: 2, height: 3, maxScrollbackLines: 3, saveToScrollbackInAlternateScreen: false)
        appendLines(["0", "1", "2", "3", "4"], to: screen)
        showAltAndUppercase(screen)
        var overflow = Int32(-1)
        var dirtyDump = ""
        mutate(screen) { _, mutableState in
            mutableState.resetScrollbackOverflow()
            mutableState.currentGrid.markAllCharsDirty(false, updateTimestamps: false)
            mutableState.terminalLineFeed()
            overflow = mutableState.scrollbackOverflow
            dirtyDump = mutableState.currentGrid.compactDirtyDump()
        }
        XCTAssertEqual(overflow, 0)
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "0.\n" +
                       "1.\n" +
                       "2.\n" +
                       "4.\n" +
                       "..\n" +
                       "..")
        XCTAssertEqual(dirtyDump,
                       "dd\n" +
                       "dd\n" +
                       "dd")
    }

    func testAllDirtyIsSetInitiallyAndClearedByMarkingClean() {
        let screen = makeScreen(width: 2, height: 3)
        mutate(screen) { _, mutableState in
            XCTAssertTrue(mutableState.currentGrid.isAllDirty)
            mutableState.currentGrid.markAllCharsDirty(false, updateTimestamps: false)
            XCTAssertFalse(mutableState.currentGrid.isAllDirty)
        }
    }

    func testLineFeedDoesNotMarkAllDirty() {
        let screen = makeScreen(width: 2, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.currentGrid.markAllCharsDirty(false, updateTimestamps: false)
            mutableState.terminalLineFeed()
            XCTAssertFalse(mutableState.currentGrid.isAllDirty)
        }
    }

    func testNeedsRedrawMarksAllDirty() {
        let screen = makeScreen(width: 2, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.currentGrid.markAllCharsDirty(false, updateTimestamps: false)
            mutableState.terminalNeedsRedraw()
            XCTAssertTrue(mutableState.currentGrid.isAllDirty)
        }
    }

    func testAppendingMarksCharDirtyAtCursor() {
        let screen = makeScreen(width: 2, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.currentGrid.markAllCharsDirty(false, updateTimestamps: false)
            XCTAssertFalse(mutableState.currentGrid.isCharDirty(at: VT100GridCoordMake(0, 0)))
            mutableState.appendString(atCursor: "x")
            XCTAssertTrue(mutableState.currentGrid.isCharDirty(at: VT100GridCoordMake(0, 0)))
        }
    }

    func testClearBufferMarksEverythingDirty() {
        let screen = makeScreen(width: 2, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.appendString(atCursor: "x")
            mutableState.currentGrid.markAllCharsDirty(false, updateTimestamps: false)
            mutableState.clearBufferSavingPrompt(true)
            XCTAssertTrue(mutableState.currentGrid.isCharDirty(at: VT100GridCoordMake(1, 1)))
        }
    }

    // MARK: - DVR

    func testSaveToDvrRecordsFrames() throws {
        let screen = makeScreen(width: 20, height: 3)
        appendLines(["Line 1", "Line 2"], to: screen)
        screen.save(toDvr: IndexSet())

        appendLines(["Line 3"], to: screen)
        screen.save(toDvr: IndexSet())

        let dvr = try XCTUnwrap(screen.dvr)
        let decoder = try XCTUnwrap(dvr.getDecoder())
        XCTAssertTrue(decoder.seek(0))
        let firstFrame = try XCTUnwrap(decoder.decodedFrame())
        let firstLine = UnsafeRawPointer(firstFrame).assumingMemoryBound(to: screen_char_t.self)
        XCTAssertEqual(ScreenCharArrayToStringDebug(firstLine, screen.width()), "Line 1")

        XCTAssertTrue(decoder.next())
        let secondFrame = try XCTUnwrap(decoder.decodedFrame())
        let secondLine = UnsafeRawPointer(secondFrame).assumingMemoryBound(to: screen_char_t.self)
        XCTAssertEqual(ScreenCharArrayToStringDebug(secondLine, screen.width()), "Line 2")
    }

    func testShouldSendContentsChangedNotificationComesFromDelegate() {
        session.contentsChangedNotification = false
        let screen = makeScreen(width: 20, height: 3)
        XCTAssertFalse(screen.shouldSendContentsChangedNotification())
        session.contentsChangedNotification = true
        XCTAssertTrue(screen.shouldSendContentsChangedNotification())
    }

    // MARK: - Printing

    func testPrintBufferIsSentToDelegateWhenPrintingAllowed() {
        let screen = makeScreen(width: 20, height: 3, printingAllowed: true)
        mutate(screen) { _, mutableState in
            mutableState.terminalBeginRedirectingToPrintBuffer()
            mutableState.terminalAppend("test")
            mutableState.terminalLineFeed()
            mutableState.terminalPrintBuffer()
        }
        XCTAssertEqual(session.printedStrings, ["test\n"])
    }

    func testPrintBufferRedirectIsIgnoredWhenPrintingDisallowed() {
        let screen = makeScreen(width: 20, height: 3, printingAllowed: false)
        mutate(screen) { _, mutableState in
            mutableState.terminalBeginRedirectingToPrintBuffer()
            mutableState.terminalAppend("test")
            mutableState.terminalLineFeed()
            mutableState.terminalPrintBuffer()
        }
        XCTAssertTrue(session.printedStrings.isEmpty)
        XCTAssertEqual(lineString(screen, 0), "test")
    }

    func testPrintScreenAsksDelegateToPrintVisibleArea() {
        let screen = makeScreen(width: 20, height: 3, printingAllowed: true)
        mutate(screen) { _, mutableState in
            mutableState.terminalPrintScreen()
        }
        XCTAssertEqual(session.printVisibleAreaCount, 1)
        XCTAssertTrue(session.printedStrings.isEmpty)
    }

    // MARK: - Backspace

    func testBackspaceMovesCursorLeft() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.appendString(atCursor: "Hello")
            mutableState.terminalMoveCursorTo(x: 5, y: 1)
            mutableState.terminalBackspace()
            XCTAssertEqual(mutableState.oneBasedCursorX, 4)
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
        }
    }

    func testBackspaceReverseWrapsOverSoftEOL() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.appendString(atCursor: "12345678901234567890Hello")
            mutableState.terminalMoveCursorTo(x: 1, y: 2)
            mutableState.terminalBackspace()
            XCTAssertEqual(mutableState.oneBasedCursorX, 20)
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
        }
    }

    func testBackspaceDoesNotWrapOverHardEOL() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 2)
            mutableState.terminalBackspace()
            XCTAssertEqual(mutableState.oneBasedCursorX, 1)
            XCTAssertEqual(mutableState.oneBasedCursorY, 2)
        }
    }

    func testBackspaceDoesNotWrapWithColumnScrollRegion() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(2, rightMargin: 10)
            mutableState.terminalMoveCursorTo(x: 3, y: 2)
            mutableState.terminalBackspace()
            XCTAssertEqual(mutableState.oneBasedCursorX, 3)
            XCTAssertEqual(mutableState.oneBasedCursorY, 2)
        }
    }

    func testBackspaceReverseWrapsOverDWCSkip() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.appendString(atCursor: "1234567890123456789Ｗ")
            mutableState.terminalMoveCursorTo(x: 1, y: 2)
            mutableState.terminalBackspace()
            XCTAssertEqual(mutableState.oneBasedCursorX, 20)
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
        }
    }

    // MARK: - Tab stops

    func testDefaultTabStops() {
        let screen = makeScreen(width: 20, height: 3)
        XCTAssertEqual(tabStops(in: screen), [8, 16, 19])
    }

    func testSetTabStopAtCursor() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 10, y: 1)
            mutableState.terminalSetTabStopAtCursor()
            XCTAssertEqual(tabStops(in: mutableState), [8, 9, 16, 19])
        }
    }

    func testRemoveTabStopAtCursor() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 10, y: 1)
            mutableState.terminalSetTabStopAtCursor()
            mutableState.terminalMoveCursorTo(x: 9, y: 1)
            mutableState.terminalRemoveTabStopAtCursor()
            XCTAssertEqual(tabStops(in: mutableState), [9, 16, 19])
        }
    }

    func testTabRespectsColumnScrollRegion() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 1)
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(0, rightMargin: 7)
            mutableState.terminalAppendTab(atCursor: false)
            XCTAssertEqual(mutableState.oneBasedCursorX, 8)
        }
    }

    func testTabbingOverTextDoesNotChangeIt() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.appendString(atCursor: "0123456789")
            mutableState.terminalMoveCursorTo(x: 1, y: 1)
            mutableState.terminalAppendTab(atCursor: false)
        }
        XCTAssertEqual(lineString(screen, 0), "0123456789")
    }

    func testTabbingOverNullsInsertsTabFillersAndTab() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalAppendTab(atCursor: false)
            guard let line = mutableState.currentGrid.screenChars(atLineNumber: 0) else {
                XCTFail("No line 0")
                return
            }
            for i in 0..<7 {
                XCTAssertEqual(line[i].code, unichar(TAB_FILLER), "column \(i)")
            }
            XCTAssertEqual(line[7].code, unichar(UInt8(ascii: "\t")))
        }
    }

    func testTabbingOverPartiallyFilledLineOnlyMovesCursor() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 3, y: 1)
            mutableState.appendString(atCursor: "x")
            mutableState.terminalMoveCursorTo(x: 1, y: 1)
            mutableState.terminalAppendTab(atCursor: false)
            XCTAssertEqual(mutableState.oneBasedCursorX, 9)
        }
        XCTAssertEqual(lineString(screen, 0), "x")
    }

    func testTabDoesNotWrapAround() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalAppendTab(atCursor: false)  // 9
            mutableState.terminalAppendTab(atCursor: false)  // 17
            mutableState.terminalAppendTab(atCursor: false)  // 20
            XCTAssertEqual(mutableState.oneBasedCursorX, 20)
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
        }
    }

    func testBackTabMovesToPreviousTabStopWithoutWrapping() {
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 2)
            mutableState.terminalAppendTab(atCursor: false)
            mutableState.terminalAppendTab(atCursor: false)
            XCTAssertEqual(mutableState.oneBasedCursorX, 17)
            mutableState.terminalBackTab(1)
            XCTAssertEqual(mutableState.oneBasedCursorX, 9)
            mutableState.terminalBackTab(1)
            XCTAssertEqual(mutableState.oneBasedCursorX, 1)
            mutableState.terminalBackTab(1)
            XCTAssertEqual(mutableState.oneBasedCursorX, 1)
            XCTAssertEqual(mutableState.oneBasedCursorY, 2)
        }
    }

    func testBackTabIgnoresColumnScrollRegion() {
        // Back tab does not yet respect left-right margins (see the TODO in -backTab:). This
        // documents the current behavior: the cursor crosses the left margin to the previous
        // tab stop instead of stopping at the margin.
        let screen = makeScreen(width: 20, height: 3)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(10, rightMargin: 19)
            mutableState.terminalMoveCursorTo(x: 11, y: 1)
            mutableState.terminalBackTab(1)
            XCTAssertEqual(mutableState.oneBasedCursorX, 9)
        }
    }

    // MARK: - Cursor movement

    private func twentyByTwentyScreenWithRegions() -> VT100Screen {
        let screen = makeScreen(width: 20, height: 20)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(5, rightMargin: 15)
            mutableState.terminalSetScrollRegionTop(5, bottom: 15)
        }
        return screen
    }

    func testMoveCursorIgnoresScrollRegionsOutsideOriginMode() {
        let screen = twentyByTwentyScreenWithRegions()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 1)
            XCTAssertEqual(mutableState.oneBasedCursorX, 1)
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
        }
    }

    func testMoveCursorClampsToScreenOutsideOriginMode() {
        let screen = twentyByTwentyScreenWithRegions()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 100, y: 100)
            XCTAssertEqual(mutableState.oneBasedCursorX, 21)
            XCTAssertEqual(mutableState.oneBasedCursorY, 20)
        }
    }

    func testMoveCursorIsRelativeToScrollRegionInOriginMode() {
        let screen = twentyByTwentyScreenWithRegions()
        feed(screen, "\u{1b}[?6h")  // enter origin mode
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 1)
            XCTAssertEqual(mutableState.oneBasedCursorX, 6)
            XCTAssertEqual(mutableState.oneBasedCursorY, 6)
        }
    }

    func testMoveCursorClampsToScrollRegionInOriginMode() {
        let screen = twentyByTwentyScreenWithRegions()
        feed(screen, "\u{1b}[?6h")  // enter origin mode
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 100, y: 100)
            XCTAssertEqual(mutableState.oneBasedCursorX, 16)
            XCTAssertEqual(mutableState.oneBasedCursorY, 16)
        }
    }

    // MARK: - Save and restore cursor

    func testSaveAndRestoreCursorAndCharset() {
        let screen = makeScreen(width: 20, height: 20)
        mutate(screen) { terminal, mutableState in
            mutableState.terminalMoveCursorTo(x: 4, y: 5)
            mutableState.terminalSetCharset(1, toLineDrawingMode: true)
            mutableState.terminalSetCharset(3, toLineDrawingMode: true)
            terminal?.saveCursor()
            mutableState.terminalMoveCursorTo(x: 1, y: 1)
            mutableState.terminalSetCharset(1, toLineDrawingMode: false)
            mutableState.terminalSetCharset(3, toLineDrawingMode: false)
        }
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())

        mutate(screen) { terminal, mutableState in
            terminal?.restoreCursor()
            XCTAssertEqual(mutableState.oneBasedCursorX, 4)
            XCTAssertEqual(mutableState.oneBasedCursorY, 5)
        }
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())

        mutate(screen) { _, mutableState in
            mutableState.terminalSetCharset(1, toLineDrawingMode: false)
        }
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())

        mutate(screen) { _, mutableState in
            mutableState.terminalSetCharset(3, toLineDrawingMode: false)
        }
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())
    }

    func testRestoreCursorWithoutSaveMovesToOriginWithDefaultCharsets() {
        // Restore without saving. Should use default charsets and move cursor to origin, which is
        // what xterm does. (The legacy test asserted the charsets came back non-default because the
        // terminal's zero-initialized saved state happened to have line drawing on; today the
        // unsaved cursor state is explicitly reset to the defaults.)
        let screen = makeScreen(width: 20, height: 20)
        mutate(screen) { terminal, mutableState in
            for i in 0..<4 {
                mutableState.terminalSetCharset(Int32(i), toLineDrawingMode: false)
            }
            mutableState.terminalSetCharset(1, toLineDrawingMode: true)
            mutableState.terminalMoveCursorTo(x: 5, y: 5)
            terminal?.restoreCursor()
            XCTAssertEqual(mutableState.oneBasedCursorX, 1)
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
        }
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())
    }

    // MARK: - Top/bottom scroll region

    func testSetTopBottomScrollRegionScrollsWithinRegion() {
        let screen = makeScreen(width: 20, height: 20)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(5, bottom: 15)
            XCTAssertEqual(mutableState.oneBasedCursorX, 1)
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
            mutableState.terminalMoveCursorTo(x: 5, y: 16)
            mutableState.terminalAppend("Hello")
        }
        XCTAssertEqual(lineString(screen, 15), "Hello")
        mutate(screen) { _, mutableState in
            mutableState.terminalLineFeed()
        }
        XCTAssertEqual(lineString(screen, 14), "Hello")
    }

    func testSetTopBottomScrollRegionMovesCursorToRegionOriginInOriginMode() {
        let screen = makeScreen(width: 20, height: 20)
        feed(screen, "\u{1b}[?6h")  // enter origin mode
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(5, bottom: 15)
            XCTAssertEqual(mutableState.oneBasedCursorX, 1)
            XCTAssertEqual(mutableState.oneBasedCursorY, 6)
            mutableState.terminalMoveCursorTo(x: 2, y: 2)
            XCTAssertEqual(mutableState.oneBasedCursorX, 2)
            XCTAssertEqual(mutableState.oneBasedCursorY, 7)
        }
    }

    func testSetTopBottomScrollRegionWithColumnRegionInOriginMode() {
        let screen = makeScreen(width: 20, height: 20)
        feed(screen, "\u{1b}[?6h")  // enter origin mode
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(5, rightMargin: 15)
            mutableState.terminalSetScrollRegionTop(5, bottom: 15)
            XCTAssertEqual(mutableState.oneBasedCursorX, 6)
            XCTAssertEqual(mutableState.oneBasedCursorY, 6)
            mutableState.terminalMoveCursorTo(x: 2, y: 2)
            XCTAssertEqual(mutableState.oneBasedCursorX, 7)
            XCTAssertEqual(mutableState.oneBasedCursorY, 7)
        }
    }

    // MARK: - Erase in display

    private func screenForEraseInDisplay() -> VT100Screen {
        let screen = makeScreen(width: 10, height: 4)
        appendLines(["abcdefghij",
                     "klmnopqrst",
                     "0123456789"], to: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "klmnopqrst\n" +
                       "0123456789\n" +
                       "..........")
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 2)  // over the 'o'
        }
        return screen
    }

    // NOTE: The char the cursor is on always gets erased.

    func testEraseInDisplayBeforeAndAfterCursorMovesNonemptyLinesIntoHistory() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseInDisplay(beforeCursor: true, afterCursor: true)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "abcdefghij\n" +
                       "klmnopqrst\n" +
                       "0123456789\n" +
                       "..........\n" +
                       "..........\n" +
                       "..........\n" +
                       "..........")
    }

    func testEraseInDisplayBeforeCursorErasesFromOriginToCursorInclusive() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseInDisplay(beforeCursor: true, afterCursor: false)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "..........\n" +
                       ".....pqrst\n" +
                       "0123456789\n" +
                       "..........")
    }

    func testEraseInDisplayBeforeCursorWithCursorInRightMargin() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 11, y: 2)
            mutableState.terminalEraseInDisplay(beforeCursor: true, afterCursor: false)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "..........\n" +
                       "..........\n" +
                       "0123456789\n" +
                       "..........")
    }

    func testEraseInDisplayAfterCursorErasesFromCursorInclusiveToEnd() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseInDisplay(beforeCursor: false, afterCursor: true)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "klmn......\n" +
                       "..........\n" +
                       "..........")
    }

    func testEraseInDisplayNeitherBeforeNorAfterDoesNothing() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseInDisplay(beforeCursor: false, afterCursor: false)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "klmnopqrst\n" +
                       "0123456789\n" +
                       "..........")
    }

    // MARK: - Erase line

    func testEraseLineBeforeAndAfterCursorClearsWholeLine() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseLine(beforeCursor: true, afterCursor: true)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "..........\n" +
                       "0123456789\n" +
                       "..........")
    }

    func testEraseLineBeforeCursorErasesFromStartOfLineToCursorInclusive() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseLine(beforeCursor: true, afterCursor: false)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       ".....pqrst\n" +
                       "0123456789\n" +
                       "..........")
    }

    func testEraseLineBeforeCursorWithCursorInRightMargin() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 11, y: 2)
            mutableState.terminalEraseLine(beforeCursor: true, afterCursor: false)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "..........\n" +
                       "0123456789\n" +
                       "..........")
    }

    func testEraseLineAfterCursorErasesFromCursorInclusiveToEndOfLine() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseLine(beforeCursor: false, afterCursor: true)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "klmn......\n" +
                       "0123456789\n" +
                       "..........")
    }

    func testEraseLineNeitherBeforeNorAfterDoesNothing() {
        let screen = screenForEraseInDisplay()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseLine(beforeCursor: false, afterCursor: false)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "klmnopqrst\n" +
                       "0123456789\n" +
                       "..........")
    }

    // MARK: - Index and reverse index

    // Index is not implemented separately from linefeed; both respect vsplits.

    private func tenByFourScreenWithThreeLines() -> VT100Screen {
        let screen = makeScreen(width: 10, height: 4)
        appendLines(["abcdefghij",
                     "klmnopqrst",
                     "0123456789"], to: screen)
        return screen
    }

    func testLineFeedScrollsScreen() {
        let screen = tenByFourScreenWithThreeLines()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 3)
            mutableState.terminalLineFeed()
            mutableState.terminalLineFeed()
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "klmnopqrst\n" +
                       "0123456789\n" +
                       "..........\n" +
                       "..........")
    }

    func testLineFeedRespectsScrollRegions() {
        let screen = tenByFourScreenWithThreeLines()
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(1, bottom: 2)
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(2, rightMargin: 5)
            mutableState.terminalMoveCursorTo(x: 3, y: 2)
            XCTAssertEqual(mutableState.oneBasedCursorY, 2)
            // top-left is c, bottom-right is p
            mutableState.terminalLineFeed()
            XCTAssertEqual(mutableState.oneBasedCursorY, 3)
            mutableState.terminalLineFeed()
            XCTAssertEqual(mutableState.oneBasedCursorY, 3)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "kl2345qrst\n" +
                       "01....6789\n" +
                       "..........")
    }

    func testReverseIndexScrollsDownAtTop() {
        let screen = tenByFourScreenWithThreeLines()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 2)
            mutableState.terminalReverseIndex()
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "klmnopqrst\n" +
                       "0123456789\n" +
                       "..........")
        mutate(screen) { _, mutableState in
            mutableState.terminalReverseIndex()
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "..........\n" +
                       "abcdefghij\n" +
                       "klmnopqrst\n" +
                       "0123456789")
    }

    func testReverseIndexRespectsScrollRegions() {
        let screen = tenByFourScreenWithThreeLines()
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(1, bottom: 2)
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(2, rightMargin: 5)
            mutableState.terminalMoveCursorTo(x: 3, y: 3)
            // top-left is c, bottom-right is p
            XCTAssertEqual(mutableState.oneBasedCursorY, 3)
            mutableState.terminalReverseIndex()
            XCTAssertEqual(mutableState.oneBasedCursorY, 2)
            mutableState.terminalReverseIndex()
            XCTAssertEqual(mutableState.oneBasedCursorY, 2)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefghij\n" +
                       "kl....qrst\n" +
                       "01mnop6789\n" +
                       "..........")
    }

    // MARK: - Reset

    func testResetPreservingPromptKeepsPromptLine() {
        let screen = makeScreen(width: 10, height: 4)
        appendLines(["abcdefghijklm"], to: screen)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 4, y: 2)
            mutableState.terminalResetPreservingPrompt(true, modifyContent: true)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "klm.......\n" +
                       "..........\n" +
                       "..........\n" +
                       "..........")
    }

    func testResetWithoutPreservingPromptClearsScreen() {
        let screen = makeScreen(width: 10, height: 4)
        appendLines(["abcdefghijklm"], to: screen)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 4, y: 2)
            mutableState.terminalResetPreservingPrompt(false, modifyContent: true)
        }
        XCTAssertEqual(screen.compactLineDump(),
                       "..........\n" +
                       "..........\n" +
                       "..........\n" +
                       "..........")
    }

    func testResetRestoresDefaultTabStops() {
        let screen = makeScreen(width: 20, height: 4)
        let defaultTabStops: [Int32] = [8, 16, 19]
        let augmentedTabStops: [Int32] = [3, 8, 16, 19]
        XCTAssertEqual(tabStops(in: screen), defaultTabStops)

        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 4, y: 1)
            mutableState.terminalSetTabStopAtCursor()
        }
        XCTAssertEqual(tabStops(in: screen), augmentedTabStops)

        mutate(screen) { _, mutableState in
            mutableState.terminalResetPreservingPrompt(true, modifyContent: false)
        }
        sync(screen)
        XCTAssertEqual(tabStops(in: screen), defaultTabStops)
    }

    func testFullResetClearsSavedCursor() {
        let screen = makeScreen(width: 10, height: 4)
        mutate(screen) { terminal, mutableState in
            mutableState.terminalMoveCursorTo(x: 4, y: 3)
            terminal?.saveCursor()
        }
        feed(screen, "\u{1b}c")  // RIS
        mutate(screen) { terminal, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 2)
            terminal?.restoreCursor()
            XCTAssertEqual(mutableState.oneBasedCursorX, 1)
            XCTAssertEqual(mutableState.oneBasedCursorY, 1)
        }
    }

    func testResetClearsCharsetFlags() {
        let screen = makeScreen(width: 10, height: 4)
        mutate(screen) { _, mutableState in
            for i in 0..<4 {
                mutableState.terminalSetCharset(Int32(i), toLineDrawingMode: true)
            }
        }
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())
        mutate(screen) { _, mutableState in
            mutableState.terminalResetPreservingPrompt(true, modifyContent: false)
        }
        sync(screen)
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())
    }

    func testResetDoesNotClearSavedCharsetFlags() {
        // Saved charset flags get restored, not reset blindly.
        let screen = makeScreen(width: 10, height: 4)
        mutate(screen) { terminal, mutableState in
            for i in 0..<4 {
                mutableState.terminalSetCharset(Int32(i), toLineDrawingMode: true)
            }
            terminal?.saveCursor()
            mutableState.terminalResetPreservingPrompt(true, modifyContent: false)
        }
        sync(screen)
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())
        mutate(screen) { terminal, _ in
            terminal?.restoreCursor()
        }
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())
    }

    func testResetMakesCursorVisible() {
        let screen = makeScreen(width: 10, height: 4)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetCursorVisible(false)
        }
        XCTAssertFalse(session.cursorVisible)
        mutate(screen) { _, mutableState in
            mutableState.terminalResetPreservingPrompt(true, modifyContent: false)
        }
        sync(screen)
        XCTAssertTrue(session.cursorVisible)
    }

    // MARK: - Set width

    private func requestWidth(_ width: Int32, on screen: VT100Screen) {
        let done = expectation(description: "set width completed")
        mutate(screen) { _, mutableState in
            mutableState.terminalSetWidth(width,
                                          preserveScreen: true,
                                          updateRegions: false,
                                          moveCursorTo: VT100GridCoordMake(-1, -1),
                                          completion: {
                done.fulfill()
            })
        }
        wait(for: [done], timeout: 10)
    }

    func testSetWidthAsksDelegateToResizeWhenAllowed() {
        session.resizePermission = .allowed
        session.fullscreen = false
        let screen = makeScreen(width: 10, height: 4)
        requestWidth(6, on: screen)
        XCTAssertEqual(session.resizeRequests.count, 1)
        XCTAssertEqual(session.resizeRequests.first?.width, 6)
        XCTAssertEqual(session.resizeRequests.first?.height, 4)
    }

    func testSetWidthDoesNothingWhenResizeDenied() {
        session.resizePermission = .denied
        session.fullscreen = false
        let screen = makeScreen(width: 10, height: 4)
        requestWidth(6, on: screen)
        XCTAssertTrue(session.resizeRequests.isEmpty)
    }

    func testSetWidthDoesNothingWhenFullscreen() {
        session.resizePermission = .allowed
        session.fullscreen = true
        let screen = makeScreen(width: 10, height: 4)
        requestWidth(6, on: screen)
        XCTAssertTrue(session.resizeRequests.isEmpty)
    }

    // MARK: - Erase characters after cursor

    private func tenByThreeScreenWithWrappedLine() -> VT100Screen {
        let screen = makeScreen(width: 10, height: 3)
        appendLines(["abcdefghijklm"], to: screen)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 1)  // 'e'
        }
        return screen
    }

    func testEraseZeroCharactersAfterCursorDoesNothing() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseCharacters(afterCursor: 0)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcdefghij+\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testEraseTwoCharactersAfterCursor() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseCharacters(afterCursor: 2)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd..ghij+\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testEraseCharactersToEndOfLineChangesSoftEOLToHard() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseCharacters(afterCursor: 6)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd......!\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testEraseMoreCharactersThanFitOnLine() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalEraseCharacters(afterCursor: 100)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd......!\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testEraseCharactersBreaksDWCBeforeCursor() {
        let screen = screenFromCompactLinesWithContinuationMarks(
            "abcD-fghij+\n" +
            "klm.......!")
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 1)  // '-'
            mutableState.terminalEraseCharacters(afterCursor: 2)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abc...ghij+\n" +
                       "klm.......!")
    }

    func testEraseCharactersBreaksDWCAfterCursor() {
        let screen = screenFromCompactLinesWithContinuationMarks(
            "abcdeF-hij+\n" +
            "klm.......!")
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 1)  // 'e'
            mutableState.terminalEraseCharacters(afterCursor: 2)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd...hij+\n" +
                       "klm.......!")
    }

    func testEraseCharactersBreaksSplitDWC() {
        let screen = screenFromCompactLinesWithContinuationMarks(
            "abcdefghi>>\n" +
            "J-klm.....!")
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 1)  // 'e'
            mutableState.terminalEraseCharacters(afterCursor: 6)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd......!\n" +
                       "J-klm.....!")
    }

    // MARK: - Titles

    func testSetWindowTitle() {
        let screen = makeScreen(width: 80, height: 25)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetWindowTitle("test")
        }
        XCTAssertEqual(session.windowTitles, ["test"])
        mutate(screen) { _, mutableState in
            mutableState.terminalSetWindowTitle("test2")
        }
        XCTAssertEqual(session.windowTitles, ["test", "test2"])
    }

    func testSetIconTitle() {
        let screen = makeScreen(width: 80, height: 25)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetIconTitle("test3")
        }
        XCTAssertEqual(session.iconNames, ["test3"])
        mutate(screen) { _, mutableState in
            mutableState.terminalSetIconTitle("test4")
        }
        XCTAssertEqual(session.iconNames, ["test3", "test4"])
    }

    func testSetIconTitleDoesNotLogWorkingDirectory() {
        let screen = makeScreen(width: 10, height: 10, maxScrollbackLines: 20)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetIconTitle("test")
        }
        sync(screen)
        XCTAssertTrue(session.workingDirectoryLog.isEmpty)
    }

    func testSetWindowTitleLogsWorkingDirectoryOnCursorLine() {
        // The absolute cursor line number gets logged along with the polled directory.
        let screen = makeScreen(width: 10, height: 10, maxScrollbackLines: 20)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 5)
            mutableState.terminalSetWindowTitle("test")
        }
        waitUntil(screen) { session.workingDirectoryLog.count == 1 }
        XCTAssertEqual(session.workingDirectoryLog.first?.absLine, 4)
        XCTAssertEqual(session.workingDirectoryLog.first?.directory, "/")
    }

    func testSetWindowTitleLogsWorkingDirectoryIncludingScrollback() {
        let screen = makeScreen(width: 10, height: 10, maxScrollbackLines: 20)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 5)
            for _ in 0..<10 {
                mutableState.terminalLineFeed()
            }
            mutableState.terminalSetWindowTitle("test")
        }
        waitUntil(screen) { session.workingDirectoryLog.count == 1 }
        // Five lines scrolled into history and the cursor is on the last row.
        XCTAssertEqual(session.workingDirectoryLog.first?.absLine, 14)
        XCTAssertEqual(session.workingDirectoryLog.first?.directory, "/")
    }

    func testSetWindowTitleLogsWorkingDirectoryIncludingScrollbackOverflow() {
        let screen = makeScreen(width: 10, height: 10, maxScrollbackLines: 20)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 1, y: 5)
            for _ in 0..<110 {
                mutableState.terminalLineFeed()
            }
            mutableState.terminalSetWindowTitle("test")
        }
        waitUntil(screen) { session.workingDirectoryLog.count == 1 }
        // 105 lines were pushed into a 20-line scrollback, so 85 overflowed. The absolute line is
        // 85 (overflow) + 20 (scrollback) + 9 (last row of the display).
        XCTAssertEqual(session.workingDirectoryLog.first?.absLine, 114)
        XCTAssertEqual(session.workingDirectoryLog.first?.directory, "/")
    }

    // MARK: - Insert empty chars at cursor

    func testInsertZeroEmptyCharsDoesNothing() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalInsertEmptyChars(atCursor: 0)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcdefghij+\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testInsertOneEmptyChar() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalInsertEmptyChars(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd.efghi+\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testInsertTwoEmptyChars() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalInsertEmptyChars(atCursor: 2)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd..efgh+\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testInsertEmptyCharsToEndOfLineBreaksSoftEOL() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalInsertEmptyChars(atCursor: 6)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd......!\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testInsertMoreEmptyCharsThanFit() {
        let screen = tenByThreeScreenWithWrappedLine()
        mutate(screen) { _, mutableState in
            mutableState.terminalInsertEmptyChars(atCursor: 100)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd......!\n" +
                       "klm.......!\n" +
                       "..........!")
    }

    func testInsertEmptyCharBreaksDWCSkip() {
        let screen = screenFromCompactLinesWithContinuationMarks(
            "abcdefghi>>\n" +
            "J-k.......!\n" +
            "..........!")
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 1)  // 'e'
            mutableState.terminalInsertEmptyChars(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd.efghi+\n" +
                       "J-k.......!\n" +
                       "..........!")
    }

    func testInsertEmptyCharBreaksDWCThatWouldEndAtEndOfLine() {
        let screen = screenFromCompactLinesWithContinuationMarks(
            "abcdefghI-+\n" +
            "jkl.......!\n" +
            "..........!")
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 1)  // 'e'
            mutableState.terminalInsertEmptyChars(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd.efgh.!\n" +
                       "jkl.......!\n" +
                       "..........!")
    }

    func testInsertEmptyCharBreaksDWCWhenCursorOnLeftHalf() {
        let screen = screenFromCompactLinesWithContinuationMarks(
            "abcdE-fghi+\n" +
            "jkl.......!\n" +
            "..........!")
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 6, y: 1)  // 'E'
            mutableState.terminalInsertEmptyChars(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd...fgh+\n" +
                       "jkl.......!\n" +
                       "..........!")
    }

    func testInsertEmptyCharBreaksDWCWhenCursorOnRightHalf() {
        let screen = screenFromCompactLinesWithContinuationMarks(
            "abcD-efghi+\n" +
            "jkl.......!\n" +
            "..........!")
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 1)  // '-'
            mutableState.terminalInsertEmptyChars(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abc...efgh+\n" +
                       "jkl.......!\n" +
                       "..........!")
    }

    func testInsertEmptyCharRespectsColumnScrollRegion() {
        let screen = makeScreen(width: 10, height: 3)
        appendLines(["abcdefghijklm"], to: screen)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(2, rightMargin: 8)
            mutableState.terminalMoveCursorTo(x: 5, y: 1)  // 'e'
            mutableState.terminalInsertEmptyChars(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd.efghj+\n" +
                       "klm.......!\n" +
                       "..........!")
        // There are a few more tests of insertChar in VT100GridTests, no sense duplicating them.
    }

    // MARK: - Insert blank lines after cursor

    private func fourByFourScreenWithTwoLinesOneWrapped() -> VT100Screen {
        let screen = makeScreen(width: 4, height: 4)
        appendLines(["abcdefg", "hij"], to: screen)
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!")
        return screen
    }

    func testInsertZeroBlankLinesDoesNothing() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 2)  // 'f'
            mutableState.terminalInsertBlankLines(afterCursor: 0)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!")
    }

    func testInsertOneBlankLineBreaksSoftEOL() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 2)  // 'f'
            mutableState.terminalInsertBlankLines(afterCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd!\n" +
                       "....!\n" +
                       "efg.!\n" +
                       "hij.!")
    }

    func testInsertBlankLinesOutsideScrollRegionDoesNothing() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(2, bottom: 3)
            mutableState.terminalMoveCursorTo(x: 1, y: 1)  // outside region
            mutableState.terminalInsertBlankLines(afterCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!")
    }

    func testInsertBlankLinesOutsideColumnScrollRegionDoesNothing() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(2, rightMargin: 3)
            mutableState.terminalMoveCursorTo(x: 1, y: 1)  // outside region
            mutableState.terminalInsertBlankLines(afterCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!")
    }

    // MARK: - Delete lines at cursor

    func testDeleteZeroLinesDoesNothing() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 2)  // 'f'
            mutableState.terminalDeleteLines(atCursor: 0)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!")
    }

    func testDeleteOneLine() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 5, y: 2)  // 'f'
            mutableState.terminalDeleteLines(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd!\n" +
                       "hij.!\n" +
                       "....!\n" +
                       "....!")
    }

    func testDeleteLinesOutsideScrollRegionDoesNothing() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(2, bottom: 3)
            mutableState.terminalMoveCursorTo(x: 1, y: 1)  // outside region
            mutableState.terminalDeleteLines(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!")
    }

    func testDeleteLinesOutsideColumnScrollRegionDoesNothing() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(2, rightMargin: 3)
            mutableState.terminalMoveCursorTo(x: 1, y: 1)  // outside region
            mutableState.terminalDeleteLines(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!")
    }

    func testDeleteOneLineInsideScrollRegion() {
        let screen = makeScreen(width: 4, height: 5)
        appendLines(["abcdefg", "hij", "klm"], to: screen)
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "klm.!\n" +
                       "....!")
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(1, bottom: 2)
            mutableState.terminalMoveCursorTo(x: 2, y: 2)  // 'f'
            mutableState.terminalDeleteLines(atCursor: 1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd!\n" +
                       "hij.!\n" +
                       "....!\n" +
                       "klm.!\n" +
                       "....!")
    }

    // MARK: - Pixel size

    func testSetPixelSizeForwardsRequestedSizeToDelegate() {
        // The delegate (PTYSession) is responsible for interpreting -1 (current size) and 0
        // (screen size); the screen just forwards the request.
        let screen = makeScreen(width: 80, height: 25)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetPixelWidth(-1, height: -1)
        }
        XCTAssertEqual(session.pointSizeRequests, [NSSize(width: -1, height: -1)])

        mutate(screen) { _, mutableState in
            mutableState.terminalSetPixelWidth(0, height: 0)
        }
        XCTAssertEqual(session.pointSizeRequests.last, NSSize(width: 0, height: 0))

        mutate(screen) { _, mutableState in
            mutableState.terminalSetPixelWidth(50, height: 60)
        }
        XCTAssertEqual(session.pointSizeRequests.last, NSSize(width: 50, height: 60))
        XCTAssertEqual(session.pointSizeRequests.count, 3)
    }

    // MARK: - Scroll up

    func testScrollUpByZeroDoesNothing() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalScrollUp(0)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!")
    }

    func testScrollUpByOne() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalScrollUp(1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!\n" +
                       "....!")
    }

    func testScrollUpByTwo() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalScrollUp(2)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "efg.!\n" +
                       "hij.!\n" +
                       "....!\n" +
                       "....!\n" +
                       "....!")
    }

    func testScrollUpWithinScrollRegion() {
        let screen = fourByFourScreenWithTwoLinesOneWrapped()
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(1, rightMargin: 2)
            mutableState.terminalSetScrollRegionTop(1, bottom: 2)
            mutableState.terminalScrollUp(1)
        }
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcd+\n" +
                       "eij.!\n" +
                       "h...!\n" +
                       "....!")
    }

    // MARK: - Regression tests

    func testCopyToClipboardEscapeSequenceAppendsToPasteboard() {
        let screen = makeScreen(width: 80, height: 25)
        feed(screen, "\u{1b}]1337;CopyToClipboard=general\u{07}Hello world\u{1b}]1337;EndCopy\u{07}")
        XCTAssertEqual(session.pasteboardName, "general")
        XCTAssertEqual(String(data: session.pasteboardData, encoding: .utf8), "Hello world")
        XCTAssertTrue(session.copiedBufferToPasteboard)
    }

    private func firstReport(_ screen: VT100Screen) -> String? {
        waitUntil(screen) { !session.sentReports.isEmpty }
        return session.sentReports.first.flatMap { String(data: $0, encoding: .utf8) }
    }

    func testCursorPositionReport() {
        let screen = makeScreen(width: 20, height: 20)
        mutate(screen) { _, mutableState in
            mutableState.terminalMoveCursorTo(x: 2, y: 3)
        }
        screen.inject(Data("\u{1b}[6n".utf8))
        XCTAssertEqual(firstReport(screen), "\u{1b}[3;2R")
    }

    func testReportWindowSize() {
        let screen = makeScreen(width: 30, height: 20)
        screen.inject(Data("\u{1b}[18t".utf8))
        XCTAssertEqual(firstReport(screen), "\u{1b}[8;20;30t")
    }

    func testNoteTruncatedOnSwitchingToAlt() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        appendLinesNoNewline(["hello world"], to: screen)
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "abcde\n" +   // history
                       "fgh..\n" +   // history
                       "ijkl.\n" +
                       "hello\n" +
                       " worl\n" +
                       "d....")
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 1, 5, 3), focus: true, visible: true)  // fgh\nijkl\nhello
        mutate(screen) { _, mutableState in
            mutableState.terminalShowAltBuffer()
        }
        mutate(screen) { _, mutableState in
            mutableState.terminalShowPrimaryBuffer()
        }

        guard let notes = screen.annotations(in: VT100GridCoordRangeMake(0, 0, 8, 3)) else {
            XCTFail("No annotations")
            return
        }
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes.first?.progenitor === note)
        // The note is truncated to end just before the screen: -hideOnScreenNotesAndTruncateSpanners
        // shortens the interval by one cell, so the range ends at the end of the last history
        // line (5, 1) rather than at the start of the screen (0, 2) as the legacy test expected.
        // Both denote the same extent, "fgh".
        let range = screen.coordRange(ofAnnotation: note)
        XCTAssertEqual(range.start.x, 0)
        XCTAssertEqual(range.start.y, 1)
        XCTAssertEqual(range.end.x, 5)
        XCTAssertEqual(range.end.y, 1)
    }

    func testEmptyLineRestoresBackgroundColor() {
        let lineBuffer = LineBuffer()
        var line = [screen_char_t](repeating: screen_char_t(), count: 1)
        var continuation = screen_char_t()
        continuation.backgroundColor = 5
        lineBuffer.appendLine(&line,
                              length: 0,
                              partial: false,
                              width: 80,
                              metadata: iTermImmutableMetadataDefault(),
                              continuation: continuation)
        var buffer = [screen_char_t](repeating: screen_char_t(), count: 3)
        _ = lineBuffer.copyLine(toBuffer: &buffer, width: 3, lineNum: 0, continuation: &continuation)

        XCTAssertEqual(buffer[0].backgroundColor, 5)
        XCTAssertEqual(buffer[1].backgroundColor, 5)
        XCTAssertEqual(buffer[2].backgroundColor, 5)
    }

    // Issue 4261
    func testRemoteHostOnTrailingEmptyLineNotLostDuringResize() {
        // Append some text, then a newline, then set a remote host, then resize. Ensure the
        // remote host is still there.
        let screen = makeScreen(width: 5, height: 4)
        appendLines(["Hi"], to: screen)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetRemoteHost("example.com")
        }
        screen.size = VT100GridSizeMake(6, 4)
        let remoteHost = screen.remoteHost(onLine: 2)
        XCTAssertEqual(remoteHost?.hostname, "example.com")
    }

    // Issue 7323
    func testWrappedLinesFromIndexAtBoundary() {
        let blockSize = 8192
        let lineBuffer = LineBuffer(blockSize: Int32(blockSize))
        let linesPerBlock = 50
        let n = blockSize / linesPerBlock
        var line = [screen_char_t](repeating: screen_char_t(), count: n)
        for i in 0..<n {
            line[i].code = unichar(UInt8(ascii: "x"))
        }
        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)
        let wrapWidth = Int32(200)
        let zero = unichar(UInt8(ascii: "0"))
        for i in 0..<(linesPerBlock * 2) {
            line[0].code = zero + unichar(i)
            lineBuffer.appendLine(&line,
                                  length: Int32(n),
                                  partial: false,
                                  width: wrapWidth,
                                  metadata: iTermImmutableMetadataDefault(),
                                  continuation: continuation)
        }
        // This tests the regression.
        let lines = lineBuffer.wrappedLines(from: Int32(linesPerBlock),
                                            width: Int32(n * 2),
                                            count: 2)
        XCTAssertEqual(lines.count, 2)

        var buffer = [screen_char_t](repeating: screen_char_t(), count: Int(wrapWidth))
        _ = lineBuffer.copyLine(toBuffer: &buffer,
                                width: wrapWidth,
                                lineNum: Int32(linesPerBlock),
                                continuation: &continuation)
        for i in 0..<(linesPerBlock * 2) {
            let lines = lineBuffer.wrappedLines(from: Int32(i),
                                                width: Int32(n * 2),
                                                count: 1)
            XCTAssertEqual(lines.count, 1)
            guard let array = lines.first else {
                continue
            }
            XCTAssertEqual(array.line[0].code, zero + unichar(i), "line \(i)")
        }
    }

    func testEnumerateWrappedLines() {
        let screen = makeScreen(width: 5, height: 2)
        let lines = ["abcdefgh", "ijkl", "mnopqrstuv", "wxyz", "", "1234", "9876543210"]
        let expected = ["abcde",
                        "fgh",
                        "ijkl",
                        "mnopq",
                        "rstuv",
                        "wxyz",
                        "",
                        "1234",
                        "98765",
                        "43210"]
        // Line timestamps are rounded to the nearest millisecond (see VT100LineInfo), so allow
        // for that when comparing against the time the lines were appended.
        let minExpectedTimestamp = Date.timeIntervalSinceReferenceDate - 0.001
        appendLines(lines, to: screen)
        var count = 0
        screen.enumerateLines(in: NSRange(location: 0, length: lines.count)) { _, array, metadata, _ in
            let string = ScreenCharArrayToStringDebug(array.line, array.length)
            XCTAssertEqual(string, expected[count])
            XCTAssertGreaterThanOrEqual(metadata.timestamp, minExpectedTimestamp)
            count += 1
        }
        XCTAssertEqual(count, lines.count)
    }

    // MARK: - CSI CUD

    // Cursor Down Ps Times (default = 1) (CUD)
    // This control function moves the cursor down a specified number of lines in the same column.
    // The cursor stops at the bottom margin. If the cursor is already below the bottom margin,
    // then the cursor stops at the bottom line.

    private func cursor(_ screen: VT100Screen) -> VT100GridCoord {
        var result = VT100GridCoordMake(-1, -1)
        mutate(screen) { _, mutableState in
            result = mutableState.currentGrid.cursor
        }
        return result
    }

    private func setCursor(_ screen: VT100Screen, x: Int32, y: Int32) {
        mutate(screen) { _, mutableState in
            mutableState.currentGrid.cursorX = x
            mutableState.currentGrid.cursorY = y
        }
    }

    func testCUDDefaultParameterMovesDownOne() {
        let screen = makeScreen(width: 3, height: 5)
        setCursor(screen, x: 1, y: 1)
        feed(screen, "\u{1b}[B")
        XCTAssertEqual(cursor(screen).x, 1)
        XCTAssertEqual(cursor(screen).y, 2)
    }

    func testCUDExplicitParameter() {
        let screen = makeScreen(width: 3, height: 5)
        setCursor(screen, x: 1, y: 1)
        feed(screen, "\u{1b}[2B")
        XCTAssertEqual(cursor(screen).x, 1)
        XCTAssertEqual(cursor(screen).y, 3)
    }

    func testCUDStopsAtBottomMarginWhenStartingInsideScrollRegion() {
        let screen = makeScreen(width: 3, height: 5)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(2, bottom: 4)
        }
        setCursor(screen, x: 1, y: 2)
        feed(screen, "\u{1b}[99B")
        XCTAssertEqual(cursor(screen).x, 1)
        XCTAssertEqual(cursor(screen).y, 4)
    }

    func testCUDStopsAtBottomMarginWhenStartingAboveScrollRegion() {
        let screen = makeScreen(width: 3, height: 5)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(2, bottom: 3)
        }
        setCursor(screen, x: 1, y: 0)
        feed(screen, "\u{1b}[99B")
        XCTAssertEqual(cursor(screen).x, 1)
        XCTAssertEqual(cursor(screen).y, 3)
    }

    func testCUDStopsAtBottomOfScreenWhenStartingBelowScrollRegion() {
        let screen = makeScreen(width: 3, height: 5)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetScrollRegionTop(1, bottom: 2)
        }
        setCursor(screen, x: 1, y: 3)
        feed(screen, "\u{1b}[99B")
        XCTAssertEqual(cursor(screen).x, 1)
        XCTAssertEqual(cursor(screen).y, 4)
    }

    // MARK: - CSI CUF

    // Cursor Forward Ps Times (default = 1) (CUF)
    // This control function moves the cursor to the right by a specified number of columns. The
    // cursor stops at the right border of the page.

    func testCUFDefaultParameterMovesRightOne() {
        let screen = makeScreen(width: 5, height: 5)
        setCursor(screen, x: 1, y: 1)
        feed(screen, "\u{1b}[C")
        XCTAssertEqual(cursor(screen).x, 2)
        XCTAssertEqual(cursor(screen).y, 1)
    }

    func testCUFExplicitParameter() {
        let screen = makeScreen(width: 5, height: 5)
        setCursor(screen, x: 1, y: 1)
        feed(screen, "\u{1b}[2C")
        XCTAssertEqual(cursor(screen).x, 3)
        XCTAssertEqual(cursor(screen).y, 1)
    }

    func testCUFStopsOnRightBorder() {
        let screen = makeScreen(width: 5, height: 5)
        setCursor(screen, x: 1, y: 1)
        feed(screen, "\u{1b}[99C")
        XCTAssertEqual(cursor(screen).x, 4)
        XCTAssertEqual(cursor(screen).y, 1)
    }

    func testCUFRespectsColumnScrollRegionWhenStartingInsideIt() {
        let screen = makeScreen(width: 5, height: 5)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(1, rightMargin: 3)
        }
        setCursor(screen, x: 2, y: 1)
        feed(screen, "\u{1b}[99C")
        XCTAssertEqual(cursor(screen).x, 3)
        XCTAssertEqual(cursor(screen).y, 1)
    }

    func testCUFIgnoresColumnScrollRegionWhenStartingOutsideIt() {
        let screen = makeScreen(width: 5, height: 5)
        mutate(screen) { _, mutableState in
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(1, rightMargin: 2)
        }
        setCursor(screen, x: 3, y: 1)
        feed(screen, "\u{1b}[99C")
        XCTAssertEqual(cursor(screen).x, 4)
        XCTAssertEqual(cursor(screen).y, 1)
    }

    // MARK: - LineBuffer metadata

    func testAppendExternalAttributeToExistingLineNotFirstLine() {
        let lineBuffer = LineBuffer(blockSize: 10000)

        let n = 5
        var line = [screen_char_t](repeating: screen_char_t(), count: n)
        for i in 0..<n {
            line[i].code = unichar(UInt8(ascii: "x"))
        }
        var continuation = screen_char_t()

        // Append an empty line
        continuation.code = unichar(EOL_HARD)
        lineBuffer.appendLine(&line,
                              length: Int32(n),
                              partial: false,
                              width: 80,
                              metadata: iTermImmutableMetadataDefault(),
                              continuation: continuation)

        var redColor = VT100TerminalColorValue()
        redColor.red = 1
        redColor.green = 2
        redColor.blue = 3
        redColor.mode = ColorModeNormal
        let red = iTermExternalAttribute(underlineColor: redColor, url: nil, blockIDList: nil, controlCode: nil)

        var magentaColor = VT100TerminalColorValue()
        magentaColor.red = 5
        magentaColor.green = 6
        magentaColor.blue = 7
        magentaColor.mode = ColorModeNormal
        let magenta = iTermExternalAttribute(underlineColor: magentaColor, url: nil, blockIDList: nil, controlCode: nil)

        // Append a line of 5 'x' with underline color and no newline at the end
        let redIndex = iTermExternalAttributeIndex()
        redIndex.setAttributes(red, at: 0, count: Int32(n))
        var redMetadata = iTermMetadata()
        iTermMetadataInit(&redMetadata, 123, false, redIndex, .singleWidth)
        continuation.code = unichar(EOL_SOFT)
        lineBuffer.appendLine(&line,
                              length: Int32(n),
                              partial: true,
                              width: 80,
                              metadata: iTermMetadataMakeImmutable(redMetadata),
                              continuation: continuation)

        // Append again but with different underline color
        let magentaIndex = iTermExternalAttributeIndex()
        magentaIndex.setAttributes(magenta, at: 0, count: Int32(n))
        var magentaMetadata = iTermMetadata()
        iTermMetadataInit(&magentaMetadata, 123, false, magentaIndex, .singleWidth)
        continuation.code = unichar(EOL_SOFT)
        lineBuffer.appendLine(&line,
                              length: Int32(n),
                              partial: true,
                              width: 80,
                              metadata: iTermMetadataMakeImmutable(magentaMetadata),
                              continuation: continuation)

        let actual = lineBuffer.metadataForRawLine(withWrappedLineNumber: 1, width: 80)
        guard let eaIndex = iTermImmutableMetadataGetExternalAttributesIndex(actual) else {
            XCTFail("No external attribute index")
            return
        }
        for i in 0..<5 {
            XCTAssertEqual(eaIndex.attribute(at: Int32(i)), red, "index \(i)")
        }
        for i in 5..<10 {
            XCTAssertEqual(eaIndex.attribute(at: Int32(i)), magenta, "index \(i)")
        }
    }
}

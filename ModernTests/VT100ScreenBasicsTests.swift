//
//  VT100ScreenBasicsTests.swift
//  iTerm2
//
//  Ported from the first half of the legacy iTerm2XCTests/VT100ScreenTest.m
//  (init, sizing, appending, history, alt screen, tmux state, DVR frame
//  restore, PTYTextViewDataSource accessors, and find).
//

import XCTest
@testable import iTerm2SharedARC

// Records the delegate callbacks the legacy tests asserted on. Everything else
// is inherited from FakeSession.
private class BasicsScreenDelegate: FakeSession {
    var cursorVisible = true
    var updateCount = 0
    var highlightsCleared = false

    override func screenSetCursorVisible(_ visible: Bool) {
        cursorVisible = visible
    }

    override func screenUpdateDisplay(_ redraw: Bool) {
        updateCount += 1
    }

    override func screenClearHighlights() {
        highlightsCleared = true
    }

    override func screenRemoveSelection() {
        selection.clear()
    }
}

// The legacy test was the selection's delegate. Only the null range matters: iTermSelection
// extends a committed range past trailing nulls using it, and returning (INT_MAX, 0) means
// "no trailing nulls" so the range is kept as given.
private class BasicsSelectionDelegate: NSObject, iTermSelectionDelegate {
    private func emptyRange() -> VT100GridAbsWindowedRange {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, 0, 0, 0), 0, 0)
    }
    func selectionDidChange(_ selection: iTermSelection!) {}
    func liveSelectionDidEnd() {}
    func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange {
        return VT100GridRangeMake(Int32.max, 0)
    }
    func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord {
        XCTFail("Unexpected call to selectionPredecessorOfAbsCoord")
        return absCoord
    }
    func selectionViewportWidth() -> Int32 { 80 }
    func selectionTotalScrollbackOverflow() -> Int64 { 0 }
    func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet { IndexSet() }
    func selectionParagraphIsRTL(onAbsoluteLine line: Int64) -> Bool { false }
    func selectionLogicalIndexes(forVisualRange visualRange: NSRange, onAbsoluteLine line: Int64) -> IndexSet {
        return IndexSet(integersIn: Range(visualRange) ?? 0..<0)
    }
}

class VT100ScreenBasicsTests: XCTestCase {
    private var session = BasicsScreenDelegate()
    private let selectionDelegate = BasicsSelectionDelegate()

    override func setUp() {
        super.setUp()
        session = BasicsScreenDelegate()
        session.selection.delegate = selectionDelegate
    }

    // MARK: - Screen construction

    private func makeScreen() -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
        })
        return screen
    }

    private func screen(width: Int32, height: Int32) -> VT100Screen {
        let screen = makeScreen()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    private func appendLines(_ lines: [String], screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for line in lines {
                mutableState.appendString(atCursor: line)
                mutableState.terminalCarriageReturn()
                mutableState.terminalLineFeed()
            }
        })
    }

    // Mirrors what VT100ScreenMutableState.setConfig does when the profile's scrollback changes.
    private func setMaxScrollbackLines(_ screen: VT100Screen, _ n: UInt32) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.maxScrollbackLines = n
            mutableState.linebuffer.setMaxLines(Int32(n))
        })
    }

    // Moves the cursor with CUP, which VT100Terminal routes to terminalMoveCursorToX:y:.
    private func moveCursor(_ screen: VT100Screen, toX x: Int32, y: Int32) {
        feed(screen, "\u{1b}[\(y);\(x)H")
    }

    // Run raw bytes through the real parser, as the pty would.
    private func feed(_ screen: VT100Screen, _ string: String) {
        guard let data = string.data(using: .utf8) else {
            XCTFail("Could not encode \(string)")
            return
        }
        screen.inject(data)
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    // Cursor at first col of last row.
    private func fiveByFourScreenWithThreeLinesOneWrapped() -> VT100Screen {
        let screen = self.screen(width: 5, height: 4)
        appendLines(["abcdefgh", "ijkl"], screen: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       ".....")
        return screen
    }

    private func fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer() -> VT100Screen {
        let screen = self.screen(width: 5, height: 4)
        appendLines(["abcdefgh", "ijkl", "mnopqrst"], screen: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "ijkl.\n" +
                       "mnopq\n" +
                       "rst..\n" +
                       ".....")
        return screen
    }

    private func showAltAndUppercase(_ screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            guard let temp = mutableState.currentGrid.copy() as? VT100Grid else {
                XCTFail("Could not copy grid")
                return
            }
            mutableState.terminalShowAltBuffer()
            let width = Int(screen.width())
            for y in 0..<screen.height() {
                guard let lineIn = temp.screenChars(atLineNumber: y),
                      let lineOut = mutableState.currentGrid.screenChars(atLineNumber: y) else {
                    XCTFail("Missing line \(y)")
                    return
                }
                for x in 0..<width {
                    lineOut[x] = lineIn[x]
                    let c = lineIn[x].code
                    if c >= 0x61 && c <= 0x7a {
                        lineOut[x].code = c - 0x20
                    }
                }
                lineOut[width] = lineIn[width]
            }
        })
    }

    private func setSelectionRange(_ range: VT100GridCoordRange, width: Int32) {
        session.selection.clear()
        let windowedRange = VT100GridWindowedRangeMake(range, 0, 0)
        let sub = iTermSubSelection(absRange: VT100GridAbsWindowedRangeFromRelative(windowedRange, 0),
                                    mode: .kiTermSelectionModeCharacter,
                                    width: width)
        session.selection.add(sub)
    }

    // '.' is null, '-' is DWC_RIGHT, and a trailing '>' is DWC_SKIP with EOL_DWC.
    private func screenFromCompactLines(_ compactLines: String) -> VT100Screen {
        let lines = compactLines.components(separatedBy: "\n")
        let screen = self.screen(width: Int32(lines[0].utf16.count), height: Int32(lines.count))
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var mayHaveDWC = false
            for (i, line) in lines.enumerated() {
                guard let s = mutableState.currentGrid.screenChars(atLineNumber: Int32(i)) else {
                    XCTFail("Missing line \(i)")
                    return
                }
                let chars = Array(line.utf16)
                for (j, ch) in chars.enumerated() {
                    let isLast = (j == chars.count - 1)
                    if isLast {
                        s[j + 1].code = UInt16(ch == 0x3e ? EOL_DWC : EOL_HARD)
                    }
                    switch ch {
                    case 0x2e:  // .
                        s[j].code = 0
                    case 0x2d:  // -
                        ScreenCharSetDWC_RIGHT(&s[j])
                        mayHaveDWC = true
                    case 0x3e where isLast:  // >
                        ScreenCharSetDWC_SKIP(&s[j])
                        mayHaveDWC = true
                    default:
                        s[j].code = ch
                    }
                }
            }
            if mayHaveDWC {
                mutableState.linebuffer.mayHaveDoubleWidthCharacter = true
            }
            // The cells were written behind the grid's back.
            mutableState.currentGrid.resetDWCFreeCount()
            mutableState.currentGrid.markAllCharsDirty(true, updateTimestamps: false)
        })
        return screen
    }

    // Like screenFromCompactLines but the last character of each line is a
    // continuation mark: '!' hard, '+' soft, '>' DWC.
    private func screenFromCompactLinesWithContinuationMarks(_ compactLines: String) -> VT100Screen {
        let lines = compactLines.components(separatedBy: "\n")
        let screen = self.screen(width: Int32(lines[0].utf16.count - 1), height: Int32(lines.count))
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var mayHaveDWC = false
            for (i, line) in lines.enumerated() {
                guard let s = mutableState.currentGrid.screenChars(atLineNumber: Int32(i)) else {
                    XCTFail("Missing line \(i)")
                    return
                }
                let chars = Array(line.utf16)
                let last = chars.count - 1
                for j in 0..<last {
                    switch chars[j] {
                    case 0x2e:  // .
                        s[j].code = 0
                    case 0x2d:  // -
                        ScreenCharSetDWC_RIGHT(&s[j])
                        mayHaveDWC = true
                    case 0x3e where j == last - 1:  // >
                        ScreenCharSetDWC_SKIP(&s[j])
                        mayHaveDWC = true
                    default:
                        s[j].code = chars[j]
                    }
                }
                switch chars[last] {
                case 0x21:  // !
                    s[last].code = UInt16(EOL_HARD)
                case 0x2b:  // +
                    s[last].code = UInt16(EOL_SOFT)
                case 0x3e:  // >
                    mayHaveDWC = true
                    s[last].code = UInt16(EOL_DWC)
                default:
                    XCTFail("Bogus continuation mark in \(line)")
                }
            }
            if mayHaveDWC {
                mutableState.linebuffer.mayHaveDoubleWidthCharacter = true
            }
            // The cells were written behind the grid's back.
            mutableState.currentGrid.resetDWCFreeCount()
            mutableState.currentGrid.markAllCharsDirty(true, updateTimestamps: false)
        })
        return screen
    }

    private func selectedString(in screen: VT100Screen) -> String? {
        guard session.selection.hasSelection else {
            return nil
        }
        var result = ""
        let width = screen.width()
        session.selection.enumerateSelectedAbsoluteRanges { range, _, eol in
            var sx = range.coordRange.start.x
            var y = range.coordRange.start.y
            while y <= range.coordRange.end.y {
                let sca = screen.screenCharArray(forLine: Int32(y))
                let line = sca.line
                let ex = (y == range.coordRange.end.y) ? range.coordRange.end.x : width
                var newline = false
                var x = sx
                while x < ex {
                    if line[Int(x)].code != 0 {
                        result += ScreenCharArrayToStringDebug(line + Int(x), 1) ?? ""
                    } else {
                        newline = true
                        result += "\n"
                        break
                    }
                    x += 1
                }
                if sca.eol == EOL_HARD && !newline && y != range.coordRange.end.y {
                    result += "\n"
                }
                sx = 0
                y += 1
            }
            if eol {
                result += "\n"
            }
        }
        return result
    }

    private func screenLine(_ screen: VT100Screen, _ index: Int32) -> String {
        let sca = screen.screenCharArray(atScreenIndex: index)
        return ScreenCharArrayToStringDebug(sca.line, screen.width()) ?? ""
    }

    private func historyLine(_ screen: VT100Screen, _ line: Int32) -> String {
        let sca = screen.screenCharArray(forLine: line)
        return ScreenCharArrayToStringDebug(sca.line, screen.width()) ?? ""
    }

    private func screenCharLine(_ string: String, terminal: VT100Terminal) -> Data {
        var buffer = [screen_char_t](repeating: screen_char_t(), count: string.utf16.count * 3 + 1)
        var length: Int32 = 0
        StringToScreenChars(string,
                            &buffer,
                            terminal.foregroundColorCode,
                            terminal.backgroundColorCode,
                            &length,
                            false,
                            nil,
                            nil,
                            .none,
                            9,
                            false,
                            nil)
        return Data(bytes: buffer, count: Int(length) * MemoryLayout<screen_char_t>.size)
    }

    private func assertInitialTabStopsAreSet(in screen: VT100Screen,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalCarriageReturn()
        })
        let row = screen.cursorY()
        var expected: Int32 = 9
        while expected < screen.width() {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.terminalAppendTab(atCursor: false)
            })
            XCTAssertEqual(screen.cursorX(), expected, file: file, line: line)
            XCTAssertEqual(screen.cursorY(), row, file: file, line: line)
            expected += 8
        }
    }

    // MARK: - Init

    func testInitHasPositiveSizeAndCursorAtOrigin() {
        let screen = makeScreen()
        XCTAssertGreaterThan(screen.width(), 0)
        XCTAssertGreaterThan(screen.height(), 0)
        XCTAssertGreaterThan(screen.maxScrollbackLines, 0)
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 1)
    }

    func testInitScreenIsEmpty() {
        let screen = makeScreen()
        for i in 0..<screen.height() {
            XCTAssertEqual(screenLine(screen, i), "")
        }
    }

    func testInitAppendedLinesCanBeRetrieved() {
        let screen = makeScreen()
        let lines = (0..<(screen.height() - 1)).map { "Line \($0)" }
        appendLines(lines, screen: screen)
        XCTAssertEqual(screenLine(screen, 0), "Line 0")
        XCTAssertEqual(screen.numberOfLines(), screen.height())
    }

    func testInitHasFunctioningLineBuffer() {
        let screen = makeScreen()
        let lines = (0..<(screen.height() - 1)).map { "Line \($0)" }
        appendLines(lines, screen: screen)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
        })
        XCTAssertEqual(screen.numberOfLines(), screen.height() + 1)
        XCTAssertEqual(screenLine(screen, 0), "Line 1")
        XCTAssertEqual(historyLine(screen, 0), "Line 0")
    }

    func testInitHasDVR() {
        let screen = makeScreen()
        XCTAssertNotNil(screen.dvr)
    }

    func testInitSetsDefaultTabStops() {
        let screen = makeScreen()
        assertInitialTabStopsAreSet(in: screen)
    }

    // MARK: - Destructive resize

    func testDestructivelySetScreenWidthHeightChangesSize() {
        let screen = makeScreen()
        let w = screen.width() + 1
        let h = screen.height() + 1
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            screen.destructivelySetScreenWidth(w, height: h, mutableState: mutableState)
        })
        XCTAssertEqual(screen.width(), w)
        XCTAssertEqual(screen.height(), h)
    }

    func testDestructivelySetScreenWidthHeightClearsContents() {
        let screen = makeScreen()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowTestPattern()
        })
        // Make sure it's full.
        for i in 0..<screen.height() {
            XCTAssertEqual(screenLine(screen, i).count, Int(screen.width()))
        }
        let w = screen.width() + 1
        let h = screen.height() + 1
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            screen.destructivelySetScreenWidth(w, height: h, mutableState: mutableState)
        })
        // Make sure it's empty.
        for i in 0..<screen.height() {
            XCTAssertEqual(screenLine(screen, i), "")
        }
    }

    func testDestructivelySetScreenWidthHeightIsAsLargeAsItClaims() {
        let screen = makeScreen()
        let w = screen.width() + 1
        let h = screen.height() + 1
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            screen.destructivelySetScreenWidth(w, height: h, mutableState: mutableState)
        })
        moveCursor(screen, toX: 1, y: 1)
        let letters = Array("123456")
        var expected = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<Int(w) {
                let toAppend = String(letters[i % letters.count])
                expected += toAppend
                mutableState.appendString(atCursor: toAppend)
            }
        })
        XCTAssertEqual(screenLine(screen, 0), expected)
    }

    // MARK: - Continuations

    func testSetSizeRespectsContinuations() {
        let screen = self.screen(width: 5, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            guard let line = mutableState.currentGrid.screenChars(atLineNumber: 0) else {
                XCTFail("Missing line")
                return
            }
            line[5].backgroundColor = 5
        })
        screen.size = VT100GridSizeMake(6, 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            guard let line = mutableState.currentGrid.screenChars(atLineNumber: 0) else {
                XCTFail("Missing line")
                return
            }
            XCTAssertEqual(line[0].backgroundColor, 5)
        })
    }

    func testAppendingWithWraparoundOffSetsContinuation() {
        let screen = self.screen(width: 5, height: 5)
        screen.performBlock(joinedThreads: { terminal, mutableState, _ in
            terminal?.wraparoundMode = false
            terminal?.setBackgroundColor(5, alternateSemantics: false)
            mutableState.appendString(atCursor: "0123456789Z")  // Should become 0123Z
            guard let line = mutableState.currentGrid.screenChars(atLineNumber: 0) else {
                XCTFail("Missing line")
                return
            }
            XCTAssertEqual(line[5].backgroundColor, 0)
        })
    }

    // MARK: - Resize in primary screen

    func testResizeNoChangeIsNoOp() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        screen.size = VT100GridSizeMake(5, 4)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
    }

    func testResizeShrinkWidthEverythingStillFits() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcd\n" +
                       "efgh\n" +
                       "ijkl\n" +
                       "....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
    }

    func testResizeGrowWidthWithEmptyLineBuffer() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        screen.size = VT100GridSizeMake(9, 4)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefgh.\n" +
                       "ijkl.....\n" +
                       ".........\n" +
                       ".........")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
    }

    func testResizeGrowHeightOnly() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        screen.size = VT100GridSizeMake(5, 5)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
    }

    func testResizeGrowPullsLinesOutOfLineBuffer() {
        let screen = fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer()
        screen.size = VT100GridSizeMake(6, 5)
        XCTAssertEqual(screen.compactLineDump(),
                       "gh....\n" +
                       "ijkl..\n" +
                       "mnopqr\n" +
                       "st....\n" +
                       "......")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 5)
    }

    func testResizeShrinkPushesLinesIntoLineBuffer() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(screen.compactLineDump(),
                       "ijk\n" +
                       "l..\n" +
                       "...")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
        XCTAssertEqual(historyLine(screen, 0), "abc")
    }

    // MARK: - Resize in alternate screen

    func testResizeInAltNoChangeIsNoOp() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        screen.size = VT100GridSizeMake(5, 4)
        XCTAssertEqual(screen.compactLineDump(),
                       "ABCDE\n" +
                       "FGH..\n" +
                       "IJKL.\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
    }

    func testResizeInAltShrinkWidthEverythingStillFits() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertEqual(screen.compactLineDump(),
                       "ABCD\n" +
                       "EFGH\n" +
                       "IJKL\n" +
                       "....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "abcd\n" +
                       "efgh\n" +
                       "ijkl\n" +
                       "....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
    }

    func testResizeInAltGrowWidthWithEmptyLineBuffer() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        screen.size = VT100GridSizeMake(9, 4)
        XCTAssertEqual(screen.compactLineDump(),
                       "ABCDEFGH.\n" +
                       "IJKL.....\n" +
                       ".........\n" +
                       ".........")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefgh.\n" +
                       "ijkl.....\n" +
                       ".........\n" +
                       ".........")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
    }

    func testResizeInAltGrowHeightOnly() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        screen.size = VT100GridSizeMake(5, 5)
        XCTAssertEqual(screen.compactLineDump(),
                       "ABCDE\n" +
                       "FGH..\n" +
                       "IJKL.\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       ".....\n" +
                       ".....")
    }

    func testResizeInAltGrowDoesNotPullLinesOutOfLineBuffer() {
        let screen = fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer()
        showAltAndUppercase(screen)
        screen.size = VT100GridSizeMake(6, 5)
        XCTAssertEqual(screen.compactLineDump(),
                       "IJKL..\n" +
                       "MNOPQR\n" +
                       "ST....\n" +
                       "......\n" +
                       "......")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "ijkl..\n" +
                       "mnopqr\n" +
                       "st....\n" +
                       "......\n" +
                       "......")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 4)
    }

    func testResizeInAltShrinkPushesPrimaryIntoLineBuffer() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(screen.compactLineDump(),
                       "IJK\n" +
                       "L..\n" +
                       "...")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "ijk\n" +
                       "l..\n" +
                       "...")
        XCTAssertEqual(historyLine(screen, 0), "abc")
        XCTAssertEqual(historyLine(screen, 1), "def")
        XCTAssertEqual(historyLine(screen, 2), "gh")
        XCTAssertEqual(historyLine(screen, 3), "ijk")
    }

    // MARK: - Resize with a selection

    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    func testResizeShrinkKeepsSelectionOnScreen() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        // select "jk"
        setSelectionRange(VT100GridCoordRangeMake(1, 2, 3, 2), width: screen.width())
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(screen.compactLineDump(),
                       "ijk\n" +
                       "l..\n" +
                       "...")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
        XCTAssertEqual(selectedString(in: screen), "jk")
    }

    func testResizeShrinkSelectionPushedOffTopCompletelyStaysInHistory() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        // select "abcd"
        setSelectionRange(VT100GridCoordRangeMake(0, 0, 4, 0), width: screen.width())
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(screen.compactLineDump(),
                       "ijk\n" +
                       "l..\n" +
                       "...")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
        XCTAssertEqual(selectedString(in: screen), "abcd")
    }

    func testResizeShrinkSelectionPushedOffTopPartially() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        // select "gh\nij"
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(screen.compactLineDump(),
                       "ijk\n" +
                       "l..\n" +
                       "...")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
        XCTAssertEqual(selectedString(in: screen), "gh\nij")
    }

    func testResizeGrowKeepsSelection() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        // select "gh\nij"
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        screen.size = VT100GridSizeMake(9, 4)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcdefgh.\n" +
                       "ijkl.....\n" +
                       ".........\n" +
                       ".........")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
        XCTAssertEqual(selectedString(in: screen), "gh\nij")
    }

    func testResizeInAltShrinkKeepsSelectionOnScreen() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        // select "GH\nIJ"
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertEqual(screen.compactLineDump(),
                       "ABCD\n" +
                       "EFGH\n" +
                       "IJKL\n" +
                       "....")
        XCTAssertEqual(selectedString(in: screen), "GH\nIJ")
    }

    func testResizeInAltSelectionPushedOffTopPartially() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        // select "GH\nIJ"
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "GH\nIJ")
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(screen.compactLineDump(),
                       "IJK\n" +
                       "L..\n" +
                       "...")
        XCTAssertEqual(selectedString(in: screen), "IJ")
    }

    func testResizeInAltSelectionPushedOffTopCompletelyIsLost() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        // select "ABC"
        setSelectionRange(VT100GridCoordRangeMake(0, 0, 3, 0), width: screen.width())
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(screen.compactLineDump(),
                       "IJK\n" +
                       "L..\n" +
                       "...")
        XCTAssertNil(selectedString(in: screen))
    }

    func testResizeInAltGrowKeepsSelection() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        showAltAndUppercase(screen)
        // select "GH\nIJ"
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "GH\nIJ")
        screen.size = VT100GridSizeMake(6, 5)
        XCTAssertEqual(screen.compactLineDump(),
                       "ABCDEF\n" +
                       "GH....\n" +
                       "IJKL..\n" +
                       "......\n" +
                       "......")
        XCTAssertEqual(selectedString(in: screen), "GH\nIJ")
    }

    // abcde
    // fgh..
    // ijkl.
    // mnopq  <- top of screen
    // rst..
    // uvwxy
    // z....
    private func fiveByFiveScreenWithTwoLinesInHistoryShowingAlt() -> VT100Screen {
        let screen = self.screen(width: 5, height: 5)
        appendLines(["abcdefgh", "ijkl", "mnopqrst", "uvwxyz"], screen: screen)
        showAltAndUppercase(screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "MNOPQ\n" +
                       "RST..\n" +
                       "UVWXY\n" +
                       "Z....\n" +
                       ".....")
        return screen
    }

    func testResizeInAltGrowPullsLinesOutOfLineBufferIntoPrimary() {
        let screen = fiveByFiveScreenWithTwoLinesInHistoryShowingAlt()
        // select everything
        setSelectionRange(VT100GridCoordRangeMake(0, 0, 1, 6), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "abcdefgh\nijkl\nMNOPQRST\nUVWXYZ")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertEqual(screen.compactLineDump(),
                       "MNOPQR\n" +
                       "ST....\n" +
                       "UVWXYZ\n" +
                       "......\n" +
                       "......\n" +
                       "......")
        XCTAssertEqual(selectedString(in: screen), "abcdefgh\nMNOPQRST\nUVWXYZ")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "ijkl..\n" +
                       "mnopqr\n" +
                       "st....\n" +
                       "uvwxyz\n" +
                       "......\n" +
                       "......")
    }

    func testResizeInAltDropsExcessLinesPushedIntoLineBuffer() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        setMaxScrollbackLines(screen, 1)
        showAltAndUppercase(screen)
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(screen.compactLineDump(),
                       "IJK\n" +
                       "L..\n" +
                       "...")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 3)
        XCTAssertEqual(historyLine(screen, 0), "gh")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "ijk\n" +
                       "l..\n" +
                       "...")
    }

    func testResizeResetsScrollRegions() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetScrollRegionTop(1, bottom: 2)
            mutableState.terminalSetLeftMargin(1, rightMargin: 2)
        })
        showAltAndUppercase(screen)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetScrollRegionTop(0, bottom: 1)
            mutableState.terminalSetLeftMargin(0, rightMargin: 1)
        })
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertTrue(VT100GridRectEquals(screen.currentGrid().scrollRegionRect(),
                                          VT100GridRectMake(0, 0, 3, 3)))
    }

    func testResizeSelectionEndingAtLineWithTrailingNulls() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        // select "efgh.."
        setSelectionRange(VT100GridCoordRangeMake(4, 0, 5, 1), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "efgh\n")
        screen.size = VT100GridSizeMake(3, 3)
        XCTAssertEqual(selectedString(in: screen), "efgh\n")
    }

    func testResizeSelectionStartingAtBeginningOfLineOfAllNulls() {
        let screen = self.screen(width: 5, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
        })
        appendLines(["abcdefgh", "ijkl"], screen: screen)
        // .....
        // abcde
        // fgh..
        // ijkl.
        setSelectionRange(VT100GridCoordRangeMake(0, 0, 1, 2), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "\nabcdef")
        screen.size = VT100GridSizeMake(13, 4)
        XCTAssertEqual(selectedString(in: screen), "\nabcdef")
    }

    // abcde
    // fgh..
    // ijklm
    // nopqr  <- top line of screen
    // st...
    // uvwxy
    // z....
    // .....
    private func fiveByFiveScreenWithThreeLinesInHistory() -> VT100Screen {
        let screen = self.screen(width: 5, height: 5)
        appendLines(["abcdefgh", "ijklmnopqrst", "uvwxyz"], screen: screen)
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijklm\n" +
                       "nopqr\n" +
                       "st...\n" +
                       "uvwxy\n" +
                       "z....\n" +
                       ".....")
        return screen
    }

    // In alt screen with selection that begins in history and ends in history just above the
    // visible screen. The screen grows, moving lines from history into the primary screen. The end
    // of the selection has to move back because some of the selected text is no longer around in
    // the alt screen.
    func testResizeInAltGrowMovesSelectionEndBackWhenSelectedHistoryIsPulledIntoPrimary() {
        let screen = fiveByFiveScreenWithThreeLinesInHistory()
        showAltAndUppercase(screen)
        setSelectionRange(VT100GridCoordRangeMake(0, 0, 2, 2), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "abcdefgh\nij")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "abcdef\n" +
                       "NOPQRS\n" +
                       "T.....\n" +
                       "UVWXYZ\n" +
                       "......\n" +
                       "......\n" +
                       "......")
        XCTAssertEqual(selectedString(in: screen), "abcdef")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "abcdef\n" +
                       "gh....\n" +
                       "ijklmn\n" +
                       "opqrst\n" +
                       "uvwxyz\n" +
                       "......\n" +
                       "......")
    }

    // Selection begins in history just above the visible screen and ends onscreen. The start of
    // the selection has to move forward because some of the selected text is no longer around in
    // the alt screen.
    func testResizeInAltGrowMovesSelectionStartForwardWhenSelectedHistoryIsPulledIntoPrimary() {
        let screen = fiveByFiveScreenWithThreeLinesInHistory()
        showAltAndUppercase(screen)
        setSelectionRange(VT100GridCoordRangeMake(1, 2, 2, 3), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "jklmNO")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertEqual(selectedString(in: screen), "NO")
    }

    // Selection begins and ends onscreen. The screen is grown and some history is deleted.
    func testResizeInAltGrowKeepsOnscreenSelectionWhenHistoryIsPulledIntoPrimary() {
        let screen = fiveByFiveScreenWithThreeLinesInHistory()
        showAltAndUppercase(screen)
        setSelectionRange(VT100GridCoordRangeMake(0, 4, 2, 4), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "ST")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertEqual(selectedString(in: screen), "ST")
    }

    // Selection begins and ends in history just above the visible screen. The selection is lost
    // because none of its characters still exist.
    func testResizeInAltGrowLosesSelectionWhoseCharactersWerePulledIntoPrimary() {
        let screen = fiveByFiveScreenWithThreeLinesInHistory()
        showAltAndUppercase(screen)
        setSelectionRange(VT100GridCoordRangeMake(0, 2, 2, 2), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "ij")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertNil(selectedString(in: screen))
    }

    // The end of the selection is exactly at the last character before those that are lost.
    func testResizeInAltGrowSelectionEndingJustBeforeLostCharacters() {
        let screen = fiveByFiveScreenWithThreeLinesInHistory()
        showAltAndUppercase(screen)
        setSelectionRange(VT100GridCoordRangeMake(0, 0, 1, 1), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "abcdef")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertEqual(selectedString(in: screen), "abcdef")
    }

    func testResizeInAltGrowSelectionEndingOneBeforeLostCharacters() {
        let screen = fiveByFiveScreenWithThreeLinesInHistory()
        showAltAndUppercase(screen)
        setSelectionRange(VT100GridCoordRangeMake(0, 0, 5, 0), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "abcde")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertEqual(selectedString(in: screen), "abcde")
    }

    func testResizeInAltGrowSelectionEndingOneAfterLostCharacters() {
        let screen = fiveByFiveScreenWithThreeLinesInHistory()
        showAltAndUppercase(screen)
        setSelectionRange(VT100GridCoordRangeMake(0, 0, 2, 1), width: screen.width())
        XCTAssertEqual(selectedString(in: screen), "abcdefg")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertEqual(selectedString(in: screen), "abcdef")
    }

    func testResizeInAltRestoresPrimaryContentProperly() {
        let screen = self.screen(width: 5, height: 5)
        appendLines(["abcdefgh", "ijklmnopqrst", "uvwxyz"], screen: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "nopqr\n" +
                       "st...\n" +
                       "uvwxy\n" +
                       "z....\n" +
                       ".....")
        showAltAndUppercase(screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "NOPQR\n" +
                       "ST...\n" +
                       "UVWXY\n" +
                       "Z....\n" +
                       ".....")
        screen.size = VT100GridSizeMake(6, 6)
        XCTAssertEqual(screen.compactLineDump(),
                       "NOPQRS\n" +
                       "T.....\n" +
                       "UVWXYZ\n" +
                       "......\n" +
                       "......\n" +
                       "......")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowPrimaryBuffer()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "gh....\n" +
                       "ijklmn\n" +
                       "opqrst\n" +
                       "uvwxyz\n" +
                       "......\n" +
                       "......")
    }

    // MARK: - Reset

    private func screenForResetTest() -> VT100Screen {
        let screen = self.screen(width: 5, height: 3)
        session.cursorVisible = false
        setMaxScrollbackLines(screen, 1)
        appendLines(["abcdefgh", "ijkl"], screen: screen)
        moveCursor(screen, toX: 5, y: 2)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetCharset(0, toLineDrawingMode: true)
        })
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())
        return screen
    }

    func testTerminalResetPreservingPrompt() {
        let screen = screenForResetTest()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalResetPreservingPrompt(true, modifyContent: true)
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "ijkl.\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "fgh..\n" +
                       "ijkl.\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 5)
        XCTAssertEqual(screen.cursorY(), 1)
        assertInitialTabStopsAreSet(in: screen)
        XCTAssertTrue(VT100GridRectEquals(screen.currentGrid().scrollRegionRect(),
                                          VT100GridRectMake(0, 0, 5, 3)))
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())
    }

    func testTerminalResetNotPreservingPrompt() {
        let screen = screenForResetTest()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalResetPreservingPrompt(false, modifyContent: true)
        })
        XCTAssertEqual(screen.compactLineDump(),
                       ".....\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "ijkl.\n" +
                       ".....\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 1)
        assertInitialTabStopsAreSet(in: screen)
        XCTAssertTrue(VT100GridRectEquals(screen.currentGrid().scrollRegionRect(),
                                          VT100GridRectMake(0, 0, 5, 3)))
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())
    }

    func testAllCharacterSetPropertiesHaveDefaultValues() {
        let screen = self.screen(width: 5, height: 3)
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetCharset(0, toLineDrawingMode: true)
        })
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())

        // Switch to charset 1 with shift out.
        feed(screen, "\u{0e}")
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetCharset(1, toLineDrawingMode: true)
        })
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())

        // Reset clears line drawing mode but leaves charset 1 selected.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalResetPreservingPrompt(false, modifyContent: false)
        })
        XCTAssertFalse(screen.allCharacterSetPropertiesHaveDefaultValues())

        // Shift in restores charset 0.
        feed(screen, "\u{0f}")
        XCTAssertTrue(screen.allCharacterSetPropertiesHaveDefaultValues())
    }

    // MARK: - Clear buffer

    func testClearBufferResetsScrollRegionsSavedCursorAndContents() {
        let screen = self.screen(width: 5, height: 4)
        screen.performBlock(joinedThreads: { terminal, mutableState, _ in
            mutableState.terminalSetScrollRegionTop(1, bottom: 2)
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(1, rightMargin: 2)
            terminal?.setSavedCursorPosition(mutableState.currentGrid.cursor)
        })
        appendLines(["abcdefgh", "ijkl", "mnopqrstuvwxyz"], screen: screen)
        session.updateCount = 0
        screen.clearBuffer()
        XCTAssertEqual(session.updateCount, 1)
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       ".....\n" +
                       ".....\n" +
                       ".....\n" +
                       ".....")
        XCTAssertTrue(VT100GridRectEquals(screen.currentGrid().scrollRegionRect(),
                                          VT100GridRectMake(0, 0, 5, 4)))
        screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertEqual(terminal?.savedCursorPosition().x, 0)
            XCTAssertEqual(terminal?.savedCursorPosition().y, 0)
        })
    }

    func testClearBufferWithCursorOnLastNonemptyLine() {
        let screen = self.screen(width: 5, height: 4)
        appendLines(["abcdefgh", "ijkl", "mnopqrstuvwxyz"], screen: screen)
        moveCursor(screen, toX: 4, y: 3)
        session.updateCount = 0
        screen.clearBuffer()
        XCTAssertEqual(session.updateCount, 1)
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "wxyz.\n" +
                       ".....\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 4)
        XCTAssertEqual(screen.cursorY(), 1)
    }

    func testClearBufferWithCursorInMiddleOfContent() {
        let screen = self.screen(width: 5, height: 4)
        appendLines(["abcdefgh", "ijkl", "mnopqrstuvwxyz"], screen: screen)
        moveCursor(screen, toX: 4, y: 2)
        screen.clearBuffer()
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "rstuv\n" +
                       ".....\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.cursorX(), 4)
        XCTAssertEqual(screen.cursorY(), 1)
    }

    func testClearScrollbackBuffer() {
        let screen = self.screen(width: 5, height: 4)
        appendLines(["abcdefgh", "ijkl", "mnopqrstuvwxyz"], screen: screen)
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 1, 1), width: screen.width())
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       "mnopq\n" +
                       "rstuv\n" +
                       "wxyz.\n" +
                       ".....")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.clearScrollbackBuffer()
        })
        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       "mnopq\n" +
                       "rstuv\n" +
                       "wxyz.\n" +
                       ".....")
        XCTAssertTrue(session.highlightsCleared)
        XCTAssertFalse(session.selection.hasSelection)
        XCTAssertTrue(screen.isAllDirty())
    }

    // MARK: - Appending

    private func screenWithColorsAndAttributes(width: Int32, height: Int32) -> VT100Screen {
        let screen = self.screen(width: width, height: height)
        screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.setForegroundColor(5, alternateSemantics: false)
            terminal?.setBackgroundColor(6, alternateSemantics: false)
        })
        // Bold, italic, underline, blink, strikethrough
        feed(screen, "\u{1b}[1m\u{1b}[3m\u{1b}[4m\u{1b}[5m\u{1b}[9m")
        return screen
    }

    private func assertFirstCellHasColorsAndAttributes(_ screen: VT100Screen,
                                                       file: StaticString = #filePath,
                                                       line: UInt = #line) {
        let sca = screen.screenCharArray(atScreenIndex: 0)
        let c = sca.line[0]
        XCTAssertEqual(c.foregroundColor, 5, file: file, line: line)
        XCTAssertEqual(c.foregroundColorMode, ColorModeNormal.rawValue, file: file, line: line)
        XCTAssertNotEqual(c.bold, 0, file: file, line: line)
        XCTAssertNotEqual(c.italic, 0, file: file, line: line)
        XCTAssertNotEqual(c.blink, 0, file: file, line: line)
        XCTAssertNotEqual(c.underline, 0, file: file, line: line)
        XCTAssertNotEqual(c.strikethrough, 0, file: file, line: line)
        XCTAssertEqual(c.backgroundColor, 6, file: file, line: line)
        XCTAssertEqual(c.backgroundColorMode, ColorModeNormal.rawValue, file: file, line: line)
    }

    // Most of the work is done by VT100Grid's appendCharsAtCursor, which is heavily tested
    // already. This only tests the extra work not included therein.
    func testAppendStringAtCursorAsciiSetsColorsAndAttributes() {
        let screen = screenWithColorsAndAttributes(width: 5, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "Hello world")
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "Hello\n" +
                       " worl\n" +
                       "d....\n" +
                       ".....")
        assertFirstCellHasColorsAndAttributes(screen)
    }

    // The legacy test's delegate reported unicode version 8 for appends, under which emoji are
    // single width.
    private func useUnicodeVersion(_ version: Int) {
        session.configuration.unicodeVersion = version
        session.configuration.maxScrollbackLines = 1000
        session.configuration.isDirty = true
    }

    private func appendCodePointsPiecewise(_ codePoints: [unichar], screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for c in codePoints {
                mutableState.appendString(atCursor: String(utf16CodeUnits: [c], count: 1))
            }
        })
    }

    private func firstTwoCells(_ screen: VT100Screen) -> (String, screen_char_t) {
        let sca = screen.screenCharArray(atScreenIndex: 0)
        return (ScreenCharToStr(sca.line) ?? "", sca.line[1])
    }

    func testAppendComposedCharacterPiecewiseCombinesAccent() {
        useUnicodeVersion(8)
        let screen = self.screen(width: 20, height: 2)
        appendCodePointsPiecewise([0x61, 0x301], screen: screen)  // a + accent
        let (string, next) = firstTwoCells(screen)
        XCTAssertEqual(string, String(utf16CodeUnits: [0x61, 0x301], count: 2))
        XCTAssertEqual(next.code, 0)
    }

    func testAppendComposedCharacterPiecewiseJoinsSurrogatePair() {
        useUnicodeVersion(8)
        let screen = self.screen(width: 20, height: 2)
        appendCodePointsPiecewise([0xd800, 0xdd50], screen: screen)
        let (string, next) = firstTwoCells(screen)
        XCTAssertEqual(string, "𐅐")
        XCTAssertEqual(next.code, 0)
    }

    func testAppendComposedCharacterPiecewiseDoubleWidthWithAccent() {
        useUnicodeVersion(8)
        let screen = self.screen(width: 20, height: 2)
        appendCodePointsPiecewise([0xff25, 0x301], screen: screen)  // double-width E + accent
        let (string, next) = firstTwoCells(screen)
        XCTAssertEqual(string, "Ｅ́")
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(next))
    }

    func testAppendComposedCharacterPiecewiseZeroWidthNoBreakSpaceThenSkinTone() {
        useUnicodeVersion(8)
        let screen = self.screen(width: 20, height: 2)
        appendCodePointsPiecewise([0xfeff, 0xd83c, 0xdffe], screen: screen)
        let (string, next) = firstTwoCells(screen)
        XCTAssertEqual(string, "🏾")
        XCTAssertEqual(next.code, 0)
    }

    func testUnicode12Emoji() {
        useUnicodeVersion(12)
        let codePoints: [UInt32] = [0x1F468, 0x1F3FF, 0x200D, 0x1F91D, 0x200D, 0x1F468, 0x1F3FB]
        let expectedData = codePoints.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let expectedString = String(data: expectedData, encoding: .utf32LittleEndian) else {
            XCTFail("Could not decode expected string")
            return
        }
        let screen = self.screen(width: 20, height: 2)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: expectedString)
        })
        let sca = screen.screenCharArray(atScreenIndex: 0)
        let actualString = (ScreenCharToStr(sca.line) ?? "").decomposedStringWithCompatibilityMapping
        XCTAssertEqual(expectedString, actualString)
        XCTAssertEqual(expectedData, actualString.data(using: .utf32LittleEndian))
    }

    func testAppendStringAtCursorNonAscii() {
        useUnicodeVersion(8)
        let screen = screenWithColorsAndAttributes(width: 20, height: 2)
        let chars: [unichar] = [
            // x=0
            0x301,  // standalone
            // x=1
            0x61,
            0x301,  // a+accent
            // x=2
            0x61,
            0x301,
            0x327,  // a+accent+cedilla
            // x=3
            0xd800,  // surrogate pair giving 𐅐
            0xdd50,
            // x=4,5
            0xff25,  // dwc E
            0x0004,  // DWC_RIGHT (item private)
            // x=6
            0xfeff,  // zw-no-break space
            // x=7
            0x200b,  // zw-space (its own cell: the zeroWidthSpaceAdvancesCursor advanced setting)
            // x=8
            0x200c,  // zw-non-joiner
            0x200d,
            // x=9
            0x67,
            // x=10
            0x142,  // ambiguous width
            // x=11,12
            0xd83d,  // High surrogate for 1F595 (middle finger)
            0xdd95,  // Low surrogate for 1F595
            0xd83c,  // High surrogate for 1F3FE (dark skin tone)
            0xdffe,  // Low surrogate for 1F3FE
            // x=13
            0x67,
            // x=14,15
            0xd83c,  // High surrogate for 1F3FE (dark skin tone)
            0xdffe,  // Low surrogate for 1F3FE
        ]
        let string = String(utf16CodeUnits: chars, count: chars.count)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: string)
        })
        assertFirstCellHasColorsAndAttributes(screen)

        let sca = screen.screenCharArray(atScreenIndex: 0)
        let line = sca.line
        func str(_ i: Int) -> String {
            return ScreenCharToStr(line + i) ?? ""
        }
        XCTAssertEqual(str(0).decomposedStringWithCompatibilityMapping,
                       "´".decomposedStringWithCompatibilityMapping)
        XCTAssertEqual(str(1).decomposedStringWithCompatibilityMapping,
                       "á".decomposedStringWithCompatibilityMapping)
        XCTAssertEqual(str(2).decomposedStringWithCompatibilityMapping,
                       "á̧".decomposedStringWithCompatibilityMapping)
        XCTAssertEqual(str(3), "𐅐")
        XCTAssertEqual(str(4), "Ｅ")
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(line[5]))
        XCTAssertEqual(str(6), "\u{fffd}")  // The zero-width no-break space becomes U+FFFD
        // The legacy test dropped U+200B. Today the zeroWidthSpaceAdvancesCursor advanced setting
        // (on by default) gives it a cell of its own.
        XCTAssertEqual(str(7), "\u{200b}")
        XCTAssertEqual(str(8), "\u{200c}\u{200d}")
        XCTAssertEqual(str(9), "g")
        XCTAssertEqual(str(10), "ł")
        // Emoji are double width today even under unicode version 8; the legacy test predates
        // that.
        XCTAssertEqual(str(11), "🖕🏾")
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(line[12]))
        XCTAssertEqual(str(13), "g")
        XCTAssertEqual(str(14), "🏾")  // Skin tone modifier only combines with certain emoji
        XCTAssertEqual(line[15].code, 0)  // A lone modifier is single width
    }

    // MARK: - Linefeed

    func testLinefeedRespectsScrollRegion() {
        let screen = self.screen(width: 5, height: 5)
        appendLines(["abcdefgh", "ijkl", "mnop"], screen: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       "mnop.\n" +
                       ".....")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetScrollRegionTop(1, bottom: 3)
            mutableState.terminalSetUseColumnScrollRegion(true)
            mutableState.terminalSetLeftMargin(1, rightMargin: 3)
        })
        moveCursor(screen, toX: 4, y: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendLineFeed()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fjkl.\n" +
                       "inop.\n" +
                       "m....\n" +
                       ".....")
        XCTAssertEqual(screen.scrollbackOverflow(), 0)
        XCTAssertEqual(screen.totalScrollbackOverflow(), 0)
        XCTAssertEqual(screen.cursorX(), 4)
    }

    func testLinefeedScrollbackOverflow() {
        let screen = self.screen(width: 5, height: 5)
        setMaxScrollbackLines(screen, 1)
        appendLines(["abcdefgh", "ijkl", "mnop"], screen: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       "mnop.\n" +
                       ".....")
        moveCursor(screen, toX: 4, y: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendLineFeed()
            mutableState.appendLineFeed()
        })
        XCTAssertEqual(screen.compactLineDump(),
                       "ijkl.\n" +
                       "mnop.\n" +
                       ".....\n" +
                       ".....\n" +
                       ".....")
        XCTAssertEqual(screen.scrollbackOverflow(), 1)
        XCTAssertEqual(screen.totalScrollbackOverflow(), 1)
        XCTAssertEqual(screen.cursorX(), 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.resetScrollbackOverflow()
        })
        XCTAssertEqual(screen.scrollbackOverflow(), 0)
        XCTAssertEqual(screen.totalScrollbackOverflow(), 1)
    }

    // MARK: - Alt screen restoration (tmux)

    func testSetAltScreen() {
        let screen = self.screen(width: 6, height: 4)
        screen.performBlock(joinedThreads: { terminal, mutableState, _ in
            guard let terminal else {
                XCTFail("No terminal")
                return
            }
            let lines = ["abcdefghijkl",
                         "mnop",
                         "qrstuvwxyz",
                         "0123456  ",
                         "ABC   ",
                         "DEFGHIJKL   ",
                         "MNOP  "].map { self.screenCharLine($0, terminal: terminal) }
            mutableState.terminalShowAltBuffer()
            mutableState.setAltScreen(lines)
        })
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcdef+\n" +
                       "ghijkl!\n" +
                       "mnop..!\n" +
                       "qrstuv+")
    }

    func testSetTmuxState() {
        let screen = self.screen(width: 10, height: 10)
        session.cursorVisible = true
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setTmux([
                kStateDictCursorX: 4,
                kStateDictCursorY: 5,
                kStateDictScrollRegionUpper: 6,
                kStateDictScrollRegionLower: 7,
                kStateDictCursorMode: false,
                kStateDictTabstops: [4, 8]
            ])
        })
        XCTAssertEqual(screen.cursorX(), 5)
        XCTAssertEqual(screen.cursorY(), 6)
        XCTAssertEqual(screen.currentGrid().topMargin, 6)
        XCTAssertEqual(screen.currentGrid().bottomMargin, 7)
        XCTAssertFalse(session.cursorVisible)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalCarriageReturn()
            mutableState.terminalAppendTab(atCursor: false)
        })
        XCTAssertEqual(screen.cursorX(), 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalAppendTab(atCursor: false)
        })
        XCTAssertEqual(screen.cursorX(), 9)
    }

    // MARK: - DVR

    private func frameData(from source: VT100Screen) -> [screen_char_t] {
        var cells = [screen_char_t]()
        let stride = Int(source.width()) + 1
        source.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<source.height() {
                guard let line = mutableState.currentGrid.screenChars(atLineNumber: i) else {
                    XCTFail("Missing line \(i)")
                    return
                }
                cells.append(contentsOf: UnsafeBufferPointer(start: line, count: stride))
            }
        })
        return cells
    }

    private func setFromFrame(_ cells: [screen_char_t], info: DVRFrameInfo, metadata: [[Any]], screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            cells.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else {
                    XCTFail("Empty frame")
                    return
                }
                mutableState.setFromFrame(base,
                                          len: Int32(buffer.count * MemoryLayout<screen_char_t>.size),
                                          metadata: metadata,
                                          info: info)
            }
        })
    }

    private var keyFrameInfo: DVRFrameInfo {
        return DVRFrameInfo(width: 5,
                            height: 4,
                            cursorX: 1,  // zero based
                            cursorY: 2,
                            timestamp: 0,
                            frameType: Int32(DVRFrameTypeKeyFrame.rawValue))
    }

    func testSetFromFrame() {
        let cells = frameData(from: fiveByFourScreenWithThreeLinesOneWrapped())
        let screen = self.screen(width: 5, height: 4)
        setFromFrame(cells, info: keyFrameInfo, metadata: [[], [], [], []], screen: screen)
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "abcde+\n" +
                       "fgh..!\n" +
                       "ijkl.!\n" +
                       ".....!")
        XCTAssertEqual(screen.cursorX(), 2)
        XCTAssertEqual(screen.cursorY(), 3)
    }

    func testSetFromFrameIntoScreenSmallerThanFrame() {
        let cells = frameData(from: fiveByFourScreenWithThreeLinesOneWrapped())
        let screen = self.screen(width: 2, height: 2)
        setFromFrame(cells, info: keyFrameInfo, metadata: [[], []], screen: screen)
        XCTAssertEqual(screen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "ij!\n" +
                       "..!")
        XCTAssertEqual(screen.cursorX(), 2)
        XCTAssertEqual(screen.cursorY(), 1)
    }

    // MARK: - PTYTextViewDataSource accessors

    func testNumberOfLines() {
        let screen = self.screen(width: 5, height: 2)
        XCTAssertEqual(screen.numberOfLines(), 2)
        appendLines(["abcdefgh", "ijkl", "mnopqrstuvwxyz", "012"], screen: screen)
        // abcde
        // fgh..
        // ijkl.
        // mnopq
        // rstuv
        // wxyz.
        // 012..
        // .....
        XCTAssertEqual(screen.numberOfLines(), 8)
    }

    func testCursorXY() {
        let screen = self.screen(width: 5, height: 5)
        XCTAssertEqual(screen.cursorX(), 1)
        XCTAssertEqual(screen.cursorY(), 1)
        moveCursor(screen, toX: 2, y: 3)
        XCTAssertEqual(screen.cursorX(), 2)
        XCTAssertEqual(screen.cursorY(), 3)
    }

    func testNumberOfScrollbackLines() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        setMaxScrollbackLines(screen, 2)
        XCTAssertEqual(screen.numberOfScrollbackLines(), 0)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
        })
        XCTAssertEqual(screen.numberOfScrollbackLines(), 1)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
        })
        XCTAssertEqual(screen.numberOfScrollbackLines(), 2)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
        })
        XCTAssertEqual(screen.numberOfScrollbackLines(), 2)
    }

    func testScrollbackOverflow() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        setMaxScrollbackLines(screen, 0)
        XCTAssertEqual(screen.scrollbackOverflow(), 0)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
            mutableState.terminalLineFeed()
        })
        XCTAssertEqual(screen.scrollbackOverflow(), 2)
        XCTAssertEqual(screen.totalScrollbackOverflow(), 2)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.resetScrollbackOverflow()
        })
        XCTAssertEqual(screen.scrollbackOverflow(), 0)
        XCTAssertEqual(screen.totalScrollbackOverflow(), 2)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
        })
        XCTAssertEqual(screen.scrollbackOverflow(), 1)
        XCTAssertEqual(screen.totalScrollbackOverflow(), 3)
    }

    func testAbsoluteLineNumberOfCursor() {
        let screen = fiveByFourScreenWithThreeLinesOneWrapped()
        XCTAssertEqual(screen.cursorY(), 4)
        XCTAssertEqual(screen.absoluteLineNumberOfCursor(), 3)
        setMaxScrollbackLines(screen, 1)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
        })
        XCTAssertEqual(screen.absoluteLineNumberOfCursor(), 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalLineFeed()
        })
        XCTAssertEqual(screen.absoluteLineNumberOfCursor(), 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.resetScrollbackOverflow()
        })
        XCTAssertEqual(screen.absoluteLineNumberOfCursor(), 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.clearScrollbackBuffer()
        })
        XCTAssertEqual(screen.absoluteLineNumberOfCursor(), 4)
    }

    // MARK: - Find

    private func drainSearchResults(_ engine: iTermSearchEngine) -> [SearchResult] {
        var results = [SearchResult]()
        var rangeSearched = VT100GridAbsCoordRange()
        var lineRange = NSRange()
        var finished = ObjCBool(false)
        while !finished.boolValue {
            guard let partial = engine.consume(rangeSearched: &rangeSearched,
                                               lineRange: &lineRange,
                                               finished: &finished,
                                               block: true) else {
                break
            }
            results.append(contentsOf: partial)
        }
        return results
    }

    private func search(_ screen: VT100Screen,
                        for pattern: String,
                        forward: Bool,
                        mode: iTermFindMode,
                        startX: Int32,
                        startY: Int32,
                        offset: Int32,
                        startPosition: LineBufferPosition? = nil) -> [SearchResult] {
        guard let engine = screen.searchEngine() else {
            XCTFail("No search engine")
            return []
        }
        engine.setFind(pattern,
                       forwardDirection: forward,
                       mode: mode,
                       startingAtX: startX,
                       startingAtY: startY,
                       withOffset: offset,
                       multipleResults: true,
                       absLineRange: NSRange(location: 0, length: 0),
                       forceMainScreen: false,
                       startPosition: startPosition,
                       extendResultsAcrossSoftBoundaries: false)
        return drainSearchResults(engine)
    }

    private func result(_ x: Int32, _ y: Int64, _ endX: Int32, _ endY: Int64) -> SearchResult {
        guard let result = SearchResult(fromX: x, y: y, toX: endX, y: endY) else {
            it_fatalError("SearchResult init failed")
        }
        return result
    }

    private func assertResults(_ actual: [SearchResult],
                               _ expected: [SearchResult],
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count,
                       "Expected \(expected) but got \(actual)", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertTrue(e.isEqual(to: a), "Expected \(e) but got \(a)", file: file, line: line)
        }
    }

    private func assertSearch(in screen: VT100Screen,
                              for pattern: String,
                              forward: Bool,
                              mode: iTermFindMode,
                              startX: Int32,
                              startY: Int32,
                              offset: Int32,
                              matches expected: [SearchResult],
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        screen.size = VT100GridSizeMake(screen.width(), 2)
        let actual = search(screen,
                            for: pattern,
                            forward: forward,
                            mode: mode,
                            startX: startX,
                            startY: startY,
                            offset: offset)
        assertResults(actual, expected, file: file, line: line)
    }

    private func assertSearchInLines(_ compactLines: String,
                                     for pattern: String,
                                     forward: Bool,
                                     mode: iTermFindMode,
                                     startX: Int32,
                                     startY: Int32,
                                     offset: Int32,
                                     matches expected: [SearchResult],
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        let screen = screenFromCompactLinesWithContinuationMarks(compactLines)
        assertSearch(in: screen,
                     for: pattern,
                     forward: forward,
                     mode: mode,
                     startX: startX,
                     startY: startY,
                     offset: offset,
                     matches: expected,
                     file: file,
                     line: line)
    }

    private let findLines =
        "abcd+\n" +
        "efgc!\n" +
        "de..!\n" +
        "fgx>>\n" +
        "Y-z.!"

    private var cdeResults: [SearchResult] {
        return [result(2, 0, 0, 1)]
    }

    func testFind_ForwardWithWrapFromFirstChar() {
        // Search forward, wraps around a line, beginning from first char onscreen
        assertSearchInLines(findLines,
                            for: "cde",
                            forward: true,
                            mode: .caseSensitiveSubstring,
                            startX: 0,
                            startY: 0,
                            offset: 0,
                            matches: cdeResults)
    }

    func testFind_Backward() {
        assertSearchInLines(findLines,
                            for: "cde",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 2,
                            startY: 4,
                            offset: 0,
                            matches: cdeResults)
    }

    func testFind_FromNullAfterLastChar() {
        assertSearchInLines(findLines,
                            for: "cde",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 3,
                            startY: 4,
                            offset: 0,
                            matches: cdeResults)
    }

    func testFind_FromMiddleOfScreen() {
        assertSearchInLines(findLines,
                            for: "cde",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 3,
                            startY: 2,
                            offset: 0,
                            matches: cdeResults)
    }

    // The legacy engine stopped at the start of the buffer and found nothing. The current engine
    // wraps around to the end and keeps searching until it reaches the starting point.
    func testFind_FromSecondCharBackwardWrapsAround() {
        assertSearchInLines(findLines,
                            for: "cde",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 1,
                            startY: 0,
                            offset: 0,
                            matches: cdeResults)
    }

    func testFind_WrongCase() {
        assertSearchInLines(findLines,
                            for: "CDE",
                            forward: true,
                            mode: .caseSensitiveSubstring,
                            startX: 0,
                            startY: 0,
                            offset: 0,
                            matches: [])
    }

    func testFind_IgnoringCase() {
        assertSearchInLines(findLines,
                            for: "CDE",
                            forward: true,
                            mode: .caseInsensitiveSubstring,
                            startX: 0,
                            startY: 0,
                            offset: 0,
                            matches: cdeResults)
    }

    func testFind_Regex() {
        assertSearchInLines(findLines,
                            for: "c.e",
                            forward: true,
                            mode: .caseSensitiveRegex,
                            startX: 0,
                            startY: 0,
                            offset: 0,
                            matches: cdeResults)
    }

    func testFind_RegexIgnoringCase() {
        assertSearchInLines(findLines,
                            for: "C.E",
                            forward: true,
                            mode: .caseInsensitiveRegex,
                            startX: 0,
                            startY: 0,
                            offset: 0,
                            matches: cdeResults)
    }

    func testFind_Offset0() {
        assertSearchInLines(findLines,
                            for: "de",
                            forward: true,
                            mode: .caseSensitiveSubstring,
                            startX: 3,
                            startY: 0,
                            offset: 0,
                            matches: [result(3, 0, 0, 1),
                                      result(0, 2, 1, 2)])
    }

    func testFind_Offset1() {
        assertSearchInLines(findLines,
                            for: "de",
                            forward: true,
                            mode: .caseSensitiveSubstring,
                            startX: 3,
                            startY: 0,
                            offset: 1,
                            matches: [result(0, 2, 1, 2)])
    }

    // With an offset of 1 the match at the starting point is skipped, then the search wraps
    // around from the end and finds it last.
    func testFind_BackwardOffset1WrapsAround() {
        assertSearchInLines(findLines,
                            for: "de",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 0,
                            startY: 2,
                            offset: 1,
                            matches: [result(3, 0, 0, 1),
                                      result(0, 2, 1, 2)])
    }

    func testFind_MatchingDWC() {
        assertSearchInLines(findLines,
                            for: "Yz",
                            forward: true,
                            mode: .caseSensitiveSubstring,
                            startX: 0,
                            startY: 0,
                            offset: 0,
                            matches: [result(0, 4, 2, 4)])
    }

    func testFind_MatchOverDwcSkip() {
        // Search matching text before DWC_SKIP and after it
        assertSearchInLines(findLines,
                            for: "xYz",
                            forward: true,
                            mode: .caseSensitiveSubstring,
                            startX: 0,
                            startY: 0,
                            offset: 0,
                            matches: [result(2, 3, 2, 4)])
    }

    func testFind_MultipleBlocks() {
        let screen = self.screen(width: 5, height: 2)
        // Seal the line buffer's current block between groups so the search must cross block
        // boundaries, as the legacy test's 10-byte block size did. A seal is only legal when the
        // buffer's last raw line is complete, and the two-row grid always holds the last row of
        // the most recent line, so each seal happens one line after the block's last line.
        let groups = [["abcdefghij", "spam"],  // Block 0: abcdefghij
                      ["bacon", "eggs"],       // Block 1: spam, bacon
                      ["spam"],                // Block 2: eggs
                      ["0123def456789", "hello def world"]]  // Block 3: the rest
        for (i, group) in groups.enumerated() {
            appendLines(group, screen: screen)
            if i + 1 < groups.count {
                screen.performBlock(joinedThreads: { _, mutableState, _ in
                    mutableState.linebuffer.forceSeal()
                })
            }
        }
        // abcde  0
        // fghij  1
        // spam   2
        // bacon  3
        // eggs   4
        // spam   5
        // 0123d  6
        // ef456  7
        // 789    8
        // hello  9
        // def   10
        // world  11
        //        12
        assertSearch(in: screen,
                     for: "def",
                     forward: false,
                     mode: .caseSensitiveSubstring,
                     startX: 0,
                     startY: 12,
                     offset: 0,
                     matches: [result(1, 10, 3, 10),
                               result(4, 6, 1, 7),
                               result(3, 0, 0, 1)])
    }

    // MARK: - Tail find

    // abcde
    // fgh..
    // ijkl.
    // mnopq
    // rstuv
    // wxyz.
    // 012..
    // .....
    private func tailFindScreen() -> VT100Screen {
        let screen = self.screen(width: 5, height: 2)
        appendLines(["abcdefgh", "ijkl", "mnopqrstuvwxyz", "012"], screen: screen)
        return screen
    }

    func testFindForwardFindsMatchInHistory() {
        let screen = tailFindScreen()
        let results = search(screen,
                             for: "wxyz",
                             forward: true,
                             mode: .caseSensitiveSubstring,
                             startX: 0,
                             startY: 0,
                             offset: 0)
        assertResults(results, [result(0, 5, 3, 5)])
    }

    // Save the end of scrollback history, append some stuff, and search forward from the saved
    // position, finding only the match in the stuff that was appended. This is what PTYSession
    // does for tail-find.
    func testTailFindFromSavedPositionFindsOnlyAppendedContent() {
        let screen = tailFindScreen()
        let saved = screen.positionForTailSearchOfScreen()
        appendLines(["0123", "wxyz"], screen: screen)
        // TailFindController starts tail finds at (0, 0) with an explicit start position. The
        // search wraps around until it reaches its starting coordinate, so starting anywhere else
        // would also re-find the old match.
        let results = search(screen,
                             for: "wxyz",
                             forward: true,
                             mode: .caseSensitiveSubstring,
                             startX: 0,
                             startY: 0,
                             offset: 0,
                             startPosition: saved)
        assertResults(results, [result(0, 8, 3, 8)])
    }

    // Search backwards from the end. This is slower than searching forwards, but most searches are
    // reverse searches begun at the end, so it will get a result sooner.
    func testFindBackwardFromEnd() {
        let screen = tailFindScreen()
        let results = search(screen,
                             for: "mnop",
                             forward: false,
                             mode: .caseSensitiveSubstring,
                             startX: 0,
                             startY: screen.numberOfLines() + 1 + Int32(screen.totalScrollbackOverflow()),
                             offset: 0)
        assertResults(results, [result(0, 3, 3, 3)])
    }

    // A tail find begins at the position where the backward search started. It finds nothing until
    // a matching line is appended after that position.
    func testTailFindAfterBackwardSearchOnlyFindsAppendedContent() {
        let screen = tailFindScreen()
        _ = search(screen,
                   for: "mnop",
                   forward: false,
                   mode: .caseSensitiveSubstring,
                   startX: 0,
                   startY: screen.numberOfLines() + 1 + Int32(screen.totalScrollbackOverflow()),
                   offset: 0)
        guard let savedPosition = screen.searchEngine()?.lastStartPosition else {
            XCTFail("Backward search did not record a start position")
            return
        }

        var results = search(screen,
                             for: "rst",
                             forward: true,
                             mode: .caseSensitiveSubstring,
                             startX: 0,
                             startY: 0,
                             offset: 0,
                             startPosition: savedPosition)
        assertResults(results, [])

        // The cursor was on line 7, so that is where the new line lands.
        setMaxScrollbackLines(screen, 8)
        appendLines(["rst"], screen: screen)
        results = search(screen,
                         for: "rst",
                         forward: true,
                         mode: .caseSensitiveSubstring,
                         startX: 0,
                         startY: 0,
                         offset: 0,
                         startPosition: savedPosition)
        assertResults(results, [result(0, 7, 2, 7)])
    }
    // MARK: - Regression tests for production bugs found while porting VT100ScreenTest.m

    // Regression test for issue 9852. Appending with the cursor on the DWC_RIGHT of its
    // predecessor must skip the merged buffer's spacer (the grid already has it at the cursor)
    // so the appended text replaces the spacer, erases the orphaned left half and leaves the
    // following character intact. The original fix (commit f0ed6987f) was lost when commit
    // 4c8d54a8d rewrote the predecessor merge in appendStringAtCursorSlowly: and only
    // consulted predecessorIsDoubleWidth, which coordinateBefore:movedBackOverDoubleWidth:
    // leaves NO when the cursor is on the spacer itself. It used to produce
    // [null][DWC_RIGHT][|][DWC_RIGHT] with the cursor at column 4.
    func testIssue9852AppendingOverDWCRightErasesLeftHalfAndKeepsFollowingCharacter() {
        useUnicodeVersion(9)
        let screen = self.screen(width: 4, height: 1)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "😃😃")
        })
        // [smile][rhs][smile][rhs][^]
        moveCursor(screen, toX: 2, y: 1)
        // [smile][^rhs][smile][rhs]
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "|")
        })
        // [null][|][^smile][rhs]
        let line = screen.screenCharArray(forLine: 0).line
        XCTAssertEqual(line[0].code, 0)
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(line[3]))
        XCTAssertEqual(line[1].code, unichar(UInt8(ascii: "|")))
        XCTAssertEqual(ScreenCharToStr(line + 2), "😃")
        XCTAssertEqual(screen.cursorX(), 3)
    }

    // Regression test for -[ScreenCharArray paddedToLength:eligibleForDWC:] in
    // sources/ScreenChar/ScreenCharArray.m. Commit ca0dd907f started copying the continuation
    // cell into the padding for its colors, but the continuation's code is the EOL type, so
    // for a soft-wrapped history line every padding cell got code EOL_SOFT (which equals
    // DWC_SKIP) and the `buffer[length - 1].code == 0 && eligibleForDWC` check that restores
    // DWC_SKIP + EOL_DWC on the last history line before a grid starting with a DWC never
    // fired. The padding now keeps the continuation's colors with a null code.
    func testScreenCharArrayForLastHistoryLineBeforeGridStartingWithDWC() {
        let screen = self.screen(width: 6, height: 3)
        appendLines(["abcdeＦghi"], screen: screen)
        // compactLineDump prints any code above 127 as a question mark.
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde>\n" +
                       "?-ghi.\n" +
                       "......")
        var sca = screen.screenCharArray(forLine: 0)
        XCTAssertEqual(sca.line[0].code, unichar(UInt8(ascii: "a")))
        XCTAssertTrue(ScreenCharIsDWC_SKIP(sca.line[5]))
        XCTAssertEqual(sca.eol, Int32(EOL_DWC))

        // Scroll the split line into history. The line buffer does not store DWC_SKIP/EOL_DWC,
        // so screenCharArrayForLine: has to restore them for the last history line.
        appendLines(["jkl"], screen: screen)
        XCTAssertEqual(screen.numberOfScrollbackLines(), 1)
        XCTAssertEqual(screen.compactLineDump(),
                       "?-ghi.\n" +
                       "jkl...\n" +
                       "......")
        sca = screen.screenCharArray(forLine: 0)
        XCTAssertEqual(sca.line[0].code, unichar(UInt8(ascii: "a")))
        XCTAssertTrue(ScreenCharIsDWC_SKIP(sca.line[5]))
        XCTAssertEqual(sca.eol, Int32(EOL_DWC))
    }

    // Regression test for the backward wrap-around in SearchRequest.stopPosition
    // (sources/SearchingFiltering/SearchEngine.swift). -[LineBuffer findSubstring:stopAt:]
    // keeps a backward match that starts exactly at the stop, and the wrapped pass used the
    // initial start as its stop regardless of the offset, so with offset 0 the match at the
    // starting coordinate (already reported by the first pass) was reported a second time.
    // The forward equivalent (testFind_Offset0) never duplicated.
    func testFind_BackwardOffset0WrapsAroundWithoutDuplicatingStartMatch() {
        assertSearchInLines(findLines,
                            for: "de",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 0,
                            startY: 2,
                            offset: 0,
                            matches: [result(0, 2, 1, 2),
                                      result(3, 0, 0, 1)])
    }

    // Regression tests for a selection of nothing but nulls surviving a resize. Since commit
    // 5e401d357, -[VT100ScreenMutableState runByTrimmingNullsFromRun:] in
    // sources/VT100Screen/VT100ScreenMutableState+Resizing.m only trims nulls on the run's
    // first and last lines, so an all-null multi-line selection trimmed to a null cell,
    // positionRangeForCoordRange: succeeded, and didResizeToSize: re-added a phantom
    // sub-selection with no content, leaving hasSelection YES. The resize now drops any
    // sub-selection that contains no non-null character before converting it.
    func testResizeWithSelectionOfJustNullsInMainScreenClearsSelection() {
        let screen = self.screen(width: 5, height: 4)
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        XCTAssertTrue(session.selection.hasSelection)
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertFalse(session.selection.hasSelection)
    }

    func testResizeWithSelectionOfJustNullsInAltScreenClearsSelection() {
        let screen = self.screen(width: 5, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowAltBuffer()
        })
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        XCTAssertTrue(session.selection.hasSelection)
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertFalse(session.selection.hasSelection)
    }

    // A selection whose first and last lines are nulls but whose middle line holds text must
    // still survive the resize.
    func testResizeWithSelectionOfNullsAroundTextKeepsSelection() {
        let screen = self.screen(width: 5, height: 4)
        moveCursor(screen, toX: 1, y: 2)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "ab")
        })
        setSelectionRange(VT100GridCoordRangeMake(1, 0, 2, 3), width: screen.width())
        XCTAssertTrue(session.selection.hasSelection)
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertTrue(session.selection.hasSelection)
    }
}

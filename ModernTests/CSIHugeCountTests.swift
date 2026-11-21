//
//  CSIHugeCountTests.swift
//  iTerm2
//
//  Control sequences whose parameter is a count or a position, sent with the
//  largest parameter the CSI parser accepts. Each one must end in the same
//  state as the same sequence with a count just large enough to reach the
//  edge of the screen or margin: the arithmetic must not overflow, and a loop
//  driven by the count must not run once per unit of it.
//

import XCTest
@testable import iTerm2SharedARC

final class CSIHugeCountTests: XCTestCase {
    /// The largest parameter VT100CSIParser stores: it stops accumulating digits before
    /// (INT_MAX - 10) / 10 would be exceeded, so 214748363 * 10 + 9.
    private static let huge = 2147483639
    /// Large counts the parser can produce: around 2^30, where doubling a count for a
    /// double-width line first overflows, and just below the maximum.
    private static let largeCounts = [1073741824, 1073741825, 2147483630, 2147483638, huge]
    private static let width: Int32 = 20
    private static let height: Int32 = 15

    private var session = FakeSession()

    override func setUp() {
        super.setUp()
        session = FakeSession()
    }

    // MARK: - Helpers

    private struct Outcome: Equatable, CustomStringConvertible {
        var x: Int32
        var y: Int32
        var dump: String

        var description: String {
            return "cursor=(\(x), \(y))\n\(dump)"
        }
    }

    private func makeScreen() -> VT100Screen {
        session.configuration.unicodeVersion = 9
        session.configuration.maxScrollbackLines = 1000
        session.configuration.isDirty = true
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            mutableState.terminal?.encoding = String.Encoding.utf8.rawValue
            screen.destructivelySetScreenWidth(Self.width,
                                               height: Self.height,
                                               mutableState: mutableState)
        })
        return screen
    }

    /// Feeds a string through the real parser and executes the resulting tokens.
    private func feed(_ screen: VT100Screen, _ string: String) {
        screen.inject(Data(string.utf8))
        screen.waitForQueuedTokensForTesting()
    }

    private func esc(_ s: String) -> String {
        return "\u{1b}" + s
    }

    private func csi(_ s: String) -> String {
        return "\u{1b}[" + s
    }

    /// Row r (0-based) holds 20 consecutive letters starting at the r-th letter of the
    /// alphabet, so every cell is distinguishable from its neighbors.
    private var filledScreen: String {
        var s = ""
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for row in 0..<Int(Self.height) {
            s += csi("\(row + 1);1H")
            for col in 0..<Int(Self.width) {
                s.append(letters[(row + col) % letters.count])
            }
        }
        return s
    }

    private func outcome(_ setup: String, _ sequence: String) -> Outcome {
        let screen = makeScreen()
        feed(screen, setup)
        feed(screen, sequence)
        var result = Outcome(x: -1, y: -1, dump: "")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result.x = mutableState.currentGrid.cursor.x
            result.y = mutableState.currentGrid.cursor.y
        })
        result.dump = screen.compactLineDump()
        return result
    }

    /// Asserts that `make(count)` ends in the same state as `make(edge)` for every count in
    /// `largeCounts`, and that the edge state is `expected` when given.
    private func assertHugeMatchesEdge(setup: String,
                                       edge: Int,
                                       expectedX: Int32? = nil,
                                       expectedY: Int32? = nil,
                                       file: StaticString = #filePath,
                                       line: UInt = #line,
                                       _ make: (Int) -> String) {
        let atEdge = outcome(setup, make(edge))
        for count in Self.largeCounts {
            let atLarge = outcome(setup, make(count))
            XCTAssertEqual(atLarge, atEdge, "count \(count)", file: file, line: line)
        }
        if let expectedX {
            XCTAssertEqual(atEdge.x, expectedX, "edge x", file: file, line: line)
        }
        if let expectedY {
            XCTAssertEqual(atEdge.y, expectedY, "edge y", file: file, line: line)
        }
    }

    private func row(_ outcome: Outcome, _ index: Int) -> String {
        return outcome.dump.components(separatedBy: "\n")[index]
    }

    // MARK: - Cursor movement

    func testCursorDownWithHugeCountStopsAtBottom() {
        // CUD, CNL and VPR all go through -[VT100Grid moveCursorDown:].
        let setup = csi("12;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 11, expectedY: 14) {
            csi("\($0)B")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 0, expectedY: 14) {
            csi("\($0)E")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 11, expectedY: 14) {
            csi("\($0)e")
        }
        let inRange = outcome(setup, csi("2B"))
        XCTAssertEqual(inRange.y, 13)
        XCTAssertEqual(inRange.x, 11)
    }

    func testCursorDownWithHugeCountStopsAtBottomMargin() {
        // Scroll region rows 3 through 14 (0-based 2 through 13). The cursor starts on 0-based row
        // 11, where 11 + 2147483639 overflows.
        let setup = csi("3;14r") + csi("12;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 11, expectedY: 13) {
            csi("\($0)B")
        }
        XCTAssertEqual(outcome(setup, csi("1B")).y, 12)
    }

    func testCursorForwardWithHugeCountStopsAtRightEdge() {
        let setup = csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 19, expectedY: 2) {
            csi("\($0)C")
        }
        XCTAssertEqual(outcome(setup, csi("3C")).x, 14)
    }

    func testCursorForwardOnDoubleWidthLineWithHugeCountStopsAtRightEdge() {
        let setup = csi("3;1H") + esc("#6") + csi("3;3H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 18, expectedY: 2) {
            csi("\($0)C")
        }
        // On a double-width line each column is two cells.
        XCTAssertEqual(outcome(setup, csi("2C")).x, 8)
    }

    func testCursorBackwardOnDoubleWidthLineWithHugeCountStopsAtLeftEdge() {
        let setup = csi("3;1H") + esc("#6") + csi("3;7H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 0, expectedY: 2) {
            csi("\($0)D")
        }
        XCTAssertEqual(outcome(setup, csi("1D")).x, 10)
    }

    func testCursorBackwardOnDoubleWidthLineInColumnScrollRegionWithHugeCountStopsAtLeftMargin() {
        // DECLRMM on, margins at columns 3 through 20 (0-based 2 through 19).
        let setup = csi("?69h") + csi("3;20s") + csi("3;1H") + esc("#6") + csi("3;7H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedY: 2) {
            csi("\($0)D")
        }
        XCTAssertEqual(outcome(setup, csi("20D")).x, 2)
        XCTAssertEqual(outcome(setup, csi("1D")).x, 10)
    }

    func testCursorBackwardWithHugeCount() {
        // Not an overflow on a single-width line, but checked for symmetry with CUF.
        let setup = csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 0, expectedY: 2) {
            csi("\($0)D")
        }
        XCTAssertEqual(outcome(setup, csi("3D")).x, 8)
    }

    func testCharacterPositionRelativeWithHugeCountStopsAtRightEdge() {
        let setup = csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 19, expectedY: 2) {
            csi("\($0)a")
        }
        XCTAssertEqual(outcome(setup, csi("3a")).x, 14)
    }

    // MARK: - Absolute positions in origin mode

    func testCursorPositionInOriginModeWithHugeRowStopsAtBottomMargin() {
        // Scroll region rows 11 through 15 (0-based 10 through 14), origin mode on.
        let setup = csi("11;15r") + csi("?6h")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 0, expectedY: 14) {
            csi("\($0);1H")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 0, expectedY: 14) {
            csi("\($0);1f")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 0, expectedY: 14) {
            csi("\($0)d")
        }
        XCTAssertEqual(outcome(setup, csi("2;1H")).y, 11)
        XCTAssertEqual(outcome(setup, csi("3d")).y, 12)
    }

    func testCursorPositionInOriginModeWithHugeColumnStopsAtRightMargin() {
        // Left-right margins at columns 11 through 18 (0-based 10 through 17), origin mode on.
        let setup = csi("?69h") + csi("11;18s") + csi("?6h")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 17, expectedY: 0) {
            csi("1;\($0)H")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 17, expectedY: 0) {
            csi("\($0)G")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 17, expectedY: 0) {
            csi("\($0)`")
        }
        XCTAssertEqual(outcome(setup, csi("1;3H")).x, 12)
        XCTAssertEqual(outcome(setup, csi("4G")).x, 13)
    }

    // MARK: - Erase, insert and delete

    func testEraseCharactersWithHugeCountErasesToEndOfLine() {
        let setup = filledScreen + csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)X") }
        XCTAssertEqual(row(outcome(setup, csi("\(Self.width)X")), 2), "cdefghijklm.........")
        XCTAssertEqual(row(outcome(setup, csi("2X")), 2), "cdefghijklm..pqrstuv")
    }

    func testEraseCharactersOnDoubleWidthLineWithHugeCountErasesToEndOfLine() {
        let setup = filledScreen + csi("3;1H") + esc("#6") + csi("3;3H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)X") }
        let atEdge = outcome(setup, csi("\(Self.width)X"))
        let inRange = outcome(setup, csi("1X"))
        XCTAssertNotEqual(atEdge.dump, inRange.dump)
    }

    func testInsertCharactersWithHugeCountClearsToEndOfLine() {
        let setup = filledScreen + csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)@") }
        XCTAssertEqual(row(outcome(setup, csi("\(Self.width)@")), 2), "cdefghijklm.........")
        XCTAssertEqual(row(outcome(setup, csi("2@")), 2), "cdefghijklm..nopqrst")
    }

    func testInsertCharactersOnDoubleWidthLineWithHugeCount() {
        let setup = filledScreen + csi("3;1H") + esc("#6") + csi("3;3H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)@") }
        XCTAssertNotEqual(outcome(setup, csi("\(Self.width)@")).dump,
                          outcome(setup, csi("1@")).dump)
    }

    func testDeleteCharactersWithHugeCountClearsToEndOfLine() {
        let setup = filledScreen + csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)P") }
        XCTAssertEqual(row(outcome(setup, csi("\(Self.width)P")), 2), "cdefghijklm.........")
        XCTAssertEqual(row(outcome(setup, csi("2P")), 2), "cdefghijklmpqrstuv..")
    }

    func testDeleteCharactersOnDoubleWidthLineWithHugeCount() {
        let setup = filledScreen + csi("3;1H") + esc("#6") + csi("3;3H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)P") }
        XCTAssertNotEqual(outcome(setup, csi("\(Self.width)P")).dump,
                          outcome(setup, csi("1P")).dump)
    }

    func testInsertAndDeleteCharactersAtColumnTenWithHugeCount() {
        // Column 10 (0-based 9) is the first where 9 + 2147483639 overflows.
        let setup = filledScreen + csi("10G")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)@") }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)P") }
        XCTAssertEqual(row(outcome(setup, csi("\(Self.width)@")), 14), "opqrstuvw...........")
        XCTAssertEqual(row(outcome(setup, csi("1@")), 14), "opqrstuvw.xyzabcdefg")
        XCTAssertEqual(row(outcome(setup, csi("1P")), 14), "opqrstuvwyzabcdefgh.")
    }

    func testInsertAndDeleteCharactersAtRightEdgeWithHugeCount() {
        let setup = filledScreen + csi("3;20H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)@") }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)P") }
        XCTAssertEqual(row(outcome(setup, csi("1@")), 2), "cdefghijklmnopqrstu.")
        // As in xterm, DCH on the last column deletes the character under the cursor.
        XCTAssertEqual(row(outcome(setup, csi("1P")), 2), "cdefghijklmnopqrstu.")
        XCTAssertEqual(row(outcome(setup, csi("\(Self.width)P")), 2), "cdefghijklmnopqrstu.")
    }

    func testInsertAndDeleteCharactersInsideLeftRightMarginsWithHugeCount() {
        // Margins at columns 3 through 18 (0-based 2 through 17); cursor at 0-based column 11.
        let setup = filledScreen + csi("?69h") + csi("3;18s") + csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)@") }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)P") }
        XCTAssertEqual(row(outcome(setup, csi("\(Self.width)@")), 2), "cdefghijklm.......uv")
        XCTAssertEqual(row(outcome(setup, csi("1@")), 2), "cdefghijklm.nopqrsuv")
        XCTAssertEqual(row(outcome(setup, csi("1P")), 2), "cdefghijklmopqrst.uv")
    }

    func testInsertAndDeleteCharactersAtRightMarginWithHugeCount() {
        // Margins at columns 3 through 18 (0-based 2 through 17); cursor on the right margin.
        let setup = filledScreen + csi("?69h") + csi("3;18s") + csi("3;18H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)@") }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)P") }
        XCTAssertEqual(row(outcome(setup, csi("1@")), 2), "cdefghijklmnopqrs.uv")
        // DCH on the right margin deletes the character under the cursor, as in xterm.
        XCTAssertEqual(row(outcome(setup, csi("1P")), 2), "cdefghijklmnopqrs.uv")
    }

    func testCursorMovesFromRowAndColumnTenWithHugeCount() {
        let setup = csi("10;10H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 9, expectedY: 14) {
            csi("\($0)B")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 19, expectedY: 9) {
            csi("\($0)C")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 0, expectedY: 9) {
            csi("\($0)D")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height), expectedX: 9, expectedY: 0) {
            csi("\($0)A")
        }
    }

    func testInsertLinesWithHugeCountClearsToBottom() {
        let setup = filledScreen + csi("12;5H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height)) { csi("\($0)L") }
        let atEdge = outcome(setup, csi("\(Self.height)L"))
        for i in 11..<Int(Self.height) {
            XCTAssertEqual(row(atEdge, i), "....................", "row \(i)")
        }
        XCTAssertEqual(row(atEdge, 10), "klmnopqrstuvwxyzabcd")
        let inRange = outcome(setup, csi("1L"))
        XCTAssertEqual(row(inRange, 11), "....................")
        XCTAssertEqual(row(inRange, 12), "lmnopqrstuvwxyzabcde")
    }

    func testDeleteLinesWithHugeCountClearsToBottom() {
        let setup = filledScreen + csi("12;5H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height)) { csi("\($0)M") }
        let atEdge = outcome(setup, csi("\(Self.height)M"))
        for i in 11..<Int(Self.height) {
            XCTAssertEqual(row(atEdge, i), "....................", "row \(i)")
        }
        let inRange = outcome(setup, csi("1M"))
        XCTAssertEqual(row(inRange, 11), "mnopqrstuvwxyzabcdef")
    }

    func testShiftLeftAndRightInColumnScrollRegionWithHugeCount() {
        // Margins at columns 11 through 20 (0-based 10 through 19); the cursor is inside them,
        // so SL and SR shift from the left margin.
        let setup = filledScreen + csi("?69h") + csi("11;20s") + csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0) @") }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0) A") }
        XCTAssertEqual(row(outcome(setup, csi("\(Self.width) @")), 2), "cdefghijkl..........")
        XCTAssertEqual(row(outcome(setup, csi("1 @")), 2), "cdefghijklnopqrstuv.")
        XCTAssertEqual(row(outcome(setup, csi("1 A")), 2), "cdefghijkl.mnopqrstu")
    }

    func testInsertAndDeleteColumnsWithHugeCount() {
        let setup = filledScreen + csi("3;12H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)'}") }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width)) { csi("\($0)'~") }
        XCTAssertEqual(row(outcome(setup, csi("\(Self.width)'}")), 0), "abcdefghijk.........")
        XCTAssertEqual(row(outcome(setup, csi("1'}")), 0), "abcdefghijk.lmnopqrs")
        XCTAssertEqual(row(outcome(setup, csi("1'~")), 0), "abcdefghijkmnopqrst.")
    }

    // MARK: - Rectangles in origin mode

    /// Margins at rows 11 through 15 and columns 11 through 20 (0-based 10 through 14 and
    /// 10 through 19), origin mode on, so every coordinate is offset by 10.
    private var originModeMargins: String {
        return filledScreen + csi("?69h") + csi("11;20s") + csi("11;15r") + csi("?6h")
    }

    func testFillRectangleInOriginModeWithHugeCorner() {
        let setup = originModeMargins
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height)) { csi("88;1;1;\($0);\($0)$x") }
        let atEdge = outcome(setup, csi("88;1;1;\(Self.height);\(Self.height)$x"))
        XCTAssertEqual(row(atEdge, 9), "jklmnopqrstuvwxyzabc")
        XCTAssertEqual(row(atEdge, 10), "klmnopqrstXXXXXXXXXX")
        XCTAssertEqual(row(atEdge, 14), "opqrstuvwxXXXXXXXXXX")
        XCTAssertEqual(row(outcome(setup, csi("88;1;1;1;2$x")), 10), "klmnopqrstXXwxyzabcd")
    }

    func testEraseRectangleInOriginModeWithHugeCorner() {
        let setup = originModeMargins
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height)) { csi("1;1;\($0);\($0)$z") }
        let atEdge = outcome(setup, csi("1;1;\(Self.height);\(Self.height)$z"))
        XCTAssertEqual(row(atEdge, 10), "klmnopqrst          ")
        XCTAssertEqual(row(outcome(setup, csi("1;1;1;2$z")), 10), "klmnopqrst  wxyzabcd")
    }

    func testSelectiveEraseRectangleInOriginModeWithHugeCorner() {
        let setup = originModeMargins
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height)) { csi("1;1;\($0);\($0)${") }
        XCTAssertNotEqual(outcome(setup, csi("1;1;\(Self.height);\(Self.height)${")).dump,
                          outcome(setup, csi("1;1;1;2${")).dump)
    }

    func testCopyRectangleToHugeDestination() {
        // DECCRA is CSI Pts;Pls;Pbs;Prs;Pps;Ptd;Pld;Ppd $ v: the destination's top row comes
        // before its left column.
        let setup = filledScreen
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.height) + 1) {
            csi("1;1;2;2;1;\($0);5;1$v")
        }
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width) + 1) {
            csi("1;1;2;2;1;5;\($0);1$v")
        }
        // A destination below or right of the screen copies nothing.
        XCTAssertEqual(outcome(setup, csi("1;1;2;2;1;\(Self.height + 1);5;1$v")).dump,
                       outcome(setup, "").dump)
        XCTAssertEqual(outcome(setup, csi("1;1;2;2;1;5;\(Self.width + 1);1$v")).dump,
                       outcome(setup, "").dump)
    }

    func testCopyRectangleReadsDestinationTopBeforeLeft() {
        // Copy the top-left block of one row and two columns to row 5, column 10 (0-based 4
        // and 9).
        let copied = outcome(filledScreen, csi("1;1;1;2;1;5;10;1$v"))
        XCTAssertEqual(row(copied, 4), "efghijklmabpqrstuvwx")
        XCTAssertEqual(row(copied, 9), "jklmnopqrstuvwxyzabc")
    }

    func testFillRectangleRejectsCharacterCodesAboveTheByteRange() {
        // 65601 is 65 (A) plus 65536. It used to be truncated to 16 bits before the range checks.
        let unchanged = outcome(filledScreen, "")
        XCTAssertEqual(outcome(filledScreen, csi("65601;1;1;1;3$x")).dump, unchanged.dump)
        XCTAssertEqual(outcome(filledScreen, csi("65568;1;1;1;3$x")).dump, unchanged.dump)
        XCTAssertEqual(row(outcome(filledScreen, csi("65;1;1;1;3$x")), 0), "AAAdefghijklmnopqrst")
    }

    // MARK: - Rectangle reports

    /// Rows 0 through 9 plain, rows 10 through 14 bold, every cell nonblank.
    private func screenWithBoldBottomRows() -> VT100Screen {
        let screen = makeScreen()
        var s = ""
        for row in 0..<Int(Self.height) {
            s += csi("\(row + 1);1H")
            s += row >= 10 ? csi("1m") : csi("0m")
            s += String(repeating: "x", count: Int(Self.width))
        }
        s += csi("0m")
        feed(screen, s)
        return screen
    }

    private func sgrCodes(_ screen: VT100Screen, _ rect: VT100GridRect) -> [String] {
        var result = [String]()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.terminalSGRCodes(inRectangle: rect)
        })
        return result
    }

    private func checksum(_ screen: VT100Screen, _ rect: VT100GridRect) -> Int32 {
        var result = Int32(0)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.terminalChecksum(inRectangle: rect)
        })
        return result
    }

    func testSGRReportIgnoresRowsBelowTheScreen() {
        // Rows past the bottom used to wrap around onto the top of the screen, and a huge
        // height looped once per row.
        let screen = screenWithBoldBottomRows()
        let onScreen = sgrCodes(screen, VT100GridRectMake(0, 10, Self.width, 5))
        XCTAssertTrue(onScreen.contains("1"), "\(onScreen)")
        XCTAssertEqual(sgrCodes(screen, VT100GridRectMake(0, 10, Self.width, 20)), onScreen)
        XCTAssertEqual(sgrCodes(screen, VT100GridRectMake(0, 10, Self.width, Int32(Self.huge))), onScreen)
        XCTAssertEqual(sgrCodes(screen, VT100GridRectMake(0, 10, Int32(Self.huge), 5)), onScreen)
        XCTAssertEqual(sgrCodes(screen, VT100GridRectMake(0, Int32(Self.huge) - 1, Self.width, 1)), [])
        XCTAssertFalse(sgrCodes(screen, VT100GridRectMake(0, 0, Self.width, 15)).contains("1"))
    }

    func testChecksumSkipsPrivateCodes() {
        // The right half of a wide character and the cells a tab skips hold iTerm2-private
        // codes. They were meant to be left out of the checksum, but the range test could never
        // be true.
        let screen = makeScreen()
        feed(screen, "\u{4E2D}")
        XCTAssertEqual(checksum(screen, VT100GridRectMake(0, 0, 2, 1)), 0x4E2D)
        feed(screen, "\r\n\tX")
        XCTAssertEqual(checksum(screen, VT100GridRectMake(0, 1, Self.width, 1)),
                       Int32(UInt8(ascii: "\t")) + Int32(UInt8(ascii: "X")))
    }

    func testChecksumOfALargeScreenWrapsAsSixteenBits() {
        // 34,000 cells of U+FF71 (a narrow character) sum to more than Int32.max.
        let wide: Int32 = 200
        let tall: Int32 = 170
        session.configuration.unicodeVersion = 9
        session.configuration.isDirty = true
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            screen.destructivelySetScreenWidth(wide, height: tall, mutableState: mutableState)
            var c = mutableState.currentGrid.defaultChar
            c.code = 0xFF71
            mutableState.currentGrid.setCharsFrom(VT100GridCoord(x: 0, y: 0),
                                                  to: VT100GridCoord(x: wide - 1, y: tall - 1),
                                                  to: c,
                                                  externalAttributes: nil)
        })
        let total = UInt64(wide) * UInt64(tall) * 0xFF71
        XCTAssertGreaterThan(total, UInt64(Int32.max))
        XCTAssertEqual(checksum(screen, VT100GridRectMake(0, 0, wide, tall)), Int32(total & 0xFFFF))
    }

    func testChecksumIgnoresRowsBelowTheScreen() {
        let screen = screenWithBoldBottomRows()
        let onScreen = checksum(screen, VT100GridRectMake(0, 10, Self.width, 5))
        XCTAssertEqual(onScreen, 5 * Self.width * Int32(UInt8(ascii: "x")))
        XCTAssertEqual(checksum(screen, VT100GridRectMake(0, 10, Self.width, 20)), onScreen)
        XCTAssertEqual(checksum(screen, VT100GridRectMake(0, 10, Self.width, Int32(Self.huge))), onScreen)
        XCTAssertEqual(checksum(screen, VT100GridRectMake(0, 10, Int32(Self.huge), 5)), onScreen)
        XCTAssertEqual(checksum(screen, VT100GridRectMake(0, 0, Self.width, 1)),
                       Self.width * Int32(UInt8(ascii: "x")))
    }

    // MARK: - Tabs

    func testForwardTabWithHugeCountCompletesAtLastColumn() {
        let setup = csi("3;1H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 19, expectedY: 2) {
            csi("\($0)I")
        }
        XCTAssertEqual(outcome(setup, csi("1I")).x, 8)
        XCTAssertEqual(outcome(setup, csi("2I")).x, 16)
    }

    func testForwardTabWithWraparound() {
        // With tabs wrapping around, every tab can move the cursor, so the count is capped at
        // 65535 as REP's is. The cap itself is not exercised here: 65535 wrapping tabs take more
        // than five seconds in a test build, which trips the execution-permits watchdog.
        let key = "TabsWrapAround"
        let previous = iTermUserDefaults.userDefaults().object(forKey: key)
        iTermUserDefaults.userDefaults().set(true, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            iTermUserDefaults.userDefaults().set(previous, forKey: key)
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        XCTAssertTrue(iTermAdvancedSettingsModel.tabsWrapAround())
        // On a 10x3 screen the stops are at columns 8 and 9 (the last), so
        // after the first tab the cursor alternates between them, wrapping each time it leaves 9:
        // an odd count ends on 8 and an even one on 9.
        func cursorX(afterTabs count: Int) -> Int32 {
            let screen = VT100Screen()
            session.screen = screen
            screen.delegate = session
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.terminalEnabled = true
                mutableState.terminal?.termType = "xterm"
                screen.destructivelySetScreenWidth(10, height: 3, mutableState: mutableState)
            })
            feed(screen, csi("\(count)I"))
            var x = Int32(-1)
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                x = mutableState.currentGrid.cursor.x
            })
            return x
        }
        XCTAssertEqual(cursorX(afterTabs: 3), 8)
        XCTAssertEqual(cursorX(afterTabs: 4), 9)
        XCTAssertEqual(cursorX(afterTabs: 101), 8)
    }

    func testBackTabWithHugeCountCompletesAtFirstColumn() {
        let setup = csi("3;20H")
        assertHugeMatchesEdge(setup: setup, edge: Int(Self.width), expectedX: 0, expectedY: 2) {
            csi("\($0)Z")
        }
        XCTAssertEqual(outcome(setup, csi("1Z")).x, 16)
        XCTAssertEqual(outcome(setup, csi("2Z")).x, 8)
    }
}

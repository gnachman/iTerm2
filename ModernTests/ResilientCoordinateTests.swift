//
//  ResilientCoordinateTests.swift
//  ModernTests
//
//  Created by George Nachman on 3/26/26.
//

import XCTest
@testable import iTerm2SharedARC

/// Minimal Porthole implementation for testing porthole add/remove via the real screen API.
private class FakePorthole: NSObject, ObjCPorthole {
    let uniqueIdentifier: String
    var savedLines: [ScreenCharArray] = []
    var savedITOs: [SavedIntervalTreeObject] = []
    var view: NSView { NSView() }
    var dictionaryValue: [String: AnyObject] { [:] }
    var outerMargin: CGFloat { 0 }

    init(id: String = UUID().uuidString) {
        self.uniqueIdentifier = id
        super.init()
    }

    func fit(toWidth width: CGFloat) -> CGFloat { 0 }
    func removeSelection() {}
    func updateColors(useSelectedTextColor: Bool, deferUpdate: Bool) {}
}

class ResilientCoordinateTests: XCTestCase {
    private var session: PTYSession!
    private var screen: VT100Screen!

    private static let charPool = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    private func expectedChar(forLine line: Int) -> Character {
        Self.charPool[line % Self.charPool.count]
    }

    private func makeSession(width: Int32 = 80, height: Int32 = 24,
                             scrollback: Int32 = 1000,
                             setup: ((VT100ScreenMutableState) -> Void)? = nil) -> PTYSession {
        let s = PTYSession(synthetic: false)!
        let sc = s.screen!
        sc.delegate = s
        sc.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.terminalEnabled = true
            mutableState!.terminal!.termType = "xterm"
            sc.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
            mutableState!.maxScrollbackLines = UInt32(scrollback)
            setup?(mutableState!)
        })
        return s
    }

    override func setUp() {
        super.setUp()
        session = makeSession(setup: { [self] mutableState in
            for i in 0..<50 {
                let ch = expectedChar(forLine: i)
                mutableState.appendString(atCursor: String(repeating: ch, count: 80))
                mutableState.appendCarriageReturnLineFeed()
            }
        })
        screen = session.screen
    }

    override func tearDown() {
        session = nil
        screen = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCoord(x: Int32 = 0, absY: Int64) -> ResilientCoordinate {
        return ResilientCoordinate(dataSource: session,
                                  absCoord: VT100GridAbsCoordMake(x, absY))
    }

    private func readChar(at coord: VT100GridAbsCoord,
                          screen sc: VT100Screen? = nil) -> Character? {
        let sc = sc ?? screen!
        guard let dump = sc.compactLineDumpWithHistory() else { return nil }
        let lines = dump.components(separatedBy: "\n")
        let overflow = sc.totalScrollbackOverflow()
        let lineIndex = Int(coord.y - overflow)
        guard lineIndex >= 0, lineIndex < lines.count else { return nil }
        let line = lines[lineIndex]
        guard Int(coord.x) < line.count else { return nil }
        return line[line.index(line.startIndex, offsetBy: Int(coord.x))]
    }

    private func assertContent(_ rc: ResilientCoordinate, matchesLine expectedLine: Int,
                               file: StaticString = #file, line: UInt = #line) {
        let expected = expectedChar(forLine: expectedLine)
        guard let actual = readChar(at: rc.coord) else {
            XCTFail("Could not read character at \(rc.coord)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected,
                       "Expected '\(expected)' (line \(expectedLine)) but got '\(actual)' at coord (\(rc.coord.x), \(rc.coord.y))",
                       file: file, line: line)
    }

    private func assertChar(at rc: ResilientCoordinate, equals expected: Character,
                            screen sc: VT100Screen,
                            file: StaticString = #file, line: UInt = #line) {
        guard rc.status == .valid else {
            XCTFail("RC status is \(rc.status), expected .valid", file: file, line: line)
            return
        }
        guard let actual = readChar(at: rc.coord, screen: sc) else {
            XCTFail("Could not read character at \(rc.coord)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected,
                       "Expected '\(expected)' at (\(rc.coord.x), \(rc.coord.y)) but got '\(actual)'",
                       file: file, line: line)
    }

    @discardableResult
    private func fold(startLine: Int, endLine: Int,
                      screen sc: VT100Screen? = nil) -> NSRange {
        let sc = sc ?? screen!
        let range = NSRange(location: startLine, length: endLine - startLine)
        sc.foldAbsLineRange(range)
        sc.performBlock(joinedThreads: { _, _, _ in })
        return range
    }

    private func unfold(range: NSRange, screen sc: VT100Screen? = nil) {
        let sc = sc ?? screen!
        sc.removeFolds(in: range, completion: nil)
        sc.performBlock(joinedThreads: { _, _, _ in })
    }

    /// Add a porthole via the real screen API, replacing lines [startLine, endLine]
    /// with a porthole of `height` visible lines. Saves the original screen content
    /// into the porthole (as the real PTYTextView does) so round-trip restore works.
    @discardableResult
    private func addPorthole(startLine: Int, endLine: Int, height: Int = 1,
                             screen sc: VT100Screen? = nil) -> FakePorthole {
        let sc = sc ?? screen!
        let porthole = FakePorthole()
        let overflow = sc.totalScrollbackOverflow()
        let relStart = Int32(Int64(startLine) - overflow)
        let relEnd = Int32(Int64(endLine) - overflow)
        // Save original lines before the screen replaces them (mimics PTYTextView).
        porthole.savedLines = (relStart...relEnd).map { i in
            sc.screenCharArray(forLine: i).copy() as! ScreenCharArray
        }
        // Register with PortholeRegistry so PortholeMark.savedLines can find the
        // porthole's content (the converter needs it during reflow).
        PortholeRegistry.instance.add(porthole)
        let range = VT100GridAbsCoordRangeMake(0, Int64(startLine),
                                               sc.width(), Int64(endLine))
        sc.replace(range, with: porthole, ofHeight: Int32(height))
        sc.performBlock(joinedThreads: { _, _, _ in })
        return porthole
    }

    /// Remove a porthole by replacing its mark with its saved content.
    private func removePorthole(_ porthole: FakePorthole, screen sc: VT100Screen? = nil) {
        let sc = sc ?? screen!
        if let mark = PortholeRegistry.instance.mark(for: porthole.uniqueIdentifier) {
            sc.replace(mark, withLines: porthole.savedLines, savedITOs: porthole.savedITOs)
            sc.performBlock(joinedThreads: { _, _, _ in })
        }
    }

    /// Resize a porthole to a new height via the real screen API.
    private func resizePorthole(_ porthole: FakePorthole, toHeight newHeight: Int,
                                screen sc: VT100Screen? = nil) {
        let sc = sc ?? screen!
        guard let mark = PortholeRegistry.instance.mark(for: porthole.uniqueIdentifier) else {
            XCTFail("No mark registered for porthole \(porthole.uniqueIdentifier)")
            return
        }
        sc.changeHeight(of: mark, to: Int32(newHeight))
        sc.performBlock(joinedThreads: { _, _, _ in })
    }

    private func postSessionDealloc() {
        RCDataSourceDeallocNotification.post(guid: session.guid)
    }

    // MARK: - Basic Status

    func testValidCoord() {
        let rc = makeCoord(absY: 30)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
    }

    func testScrolledOffCoord() {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState!.appendString(atCursor: "x")
                mutableState!.appendCarriageReturnLineFeed()
            }
        })
        let rc = makeCoord(absY: 0)
        XCTAssertEqual(rc.status, .scrolledOff)
    }

    func testScrolledOffBoundary() {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState!.appendString(atCursor: "x")
                mutableState!.appendCarriageReturnLineFeed()
            }
        })
        let overflow = screen.totalScrollbackOverflow()
        XCTAssertGreaterThan(overflow, 0)
        XCTAssertEqual(makeCoord(absY: overflow - 1).status, .scrolledOff)
        XCTAssertEqual(makeCoord(absY: overflow).status, .valid)
    }

    func testTruncatedBelowCoord() {
        let totalLines = Int64(screen.numberOfLines()) + screen.totalScrollbackOverflow()
        XCTAssertEqual(makeCoord(absY: totalLines + 10).status, .truncatedBelow)
    }

    func testInvalidXCoord() {
        XCTAssertEqual(makeCoord(x: -1, absY: 30).status, .invalid)
        XCTAssertEqual(makeCoord(x: 80, absY: 30).status, .invalid)
    }

    func testValidCoordProperty() {
        let rc = makeCoord(x: 3, absY: 20)
        XCTAssertNotNil(rc.validCoord)
        XCTAssertEqual(rc.validCoord?.x, 3)
        XCTAssertEqual(rc.validCoord?.y, 20)
    }

    func testValidCoordNilWhenInvalid() {
        XCTAssertNil(makeCoord(x: -1, absY: 30).validCoord)
    }

    // MARK: - Fold: SavedIntervalTreeObject crash (issue #40)

    /// Regression test: folding a range that contains an interval tree object
    /// at the sentinel column (x == width) used to crash in
    /// SavedIntervalTreeObject.from because absCoordRangeForWidth: normalizes
    /// (width, Y) → (0, Y+1), pushing the array index one past the end of
    /// the screenCharArrays collected for the fold.
    func testFoldWithMarkAtSentinelColumnDoesNotCrash() {
        // Place a zero-length mark at (width, 24) — the sentinel column on
        // the last line of the range we are about to fold.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let mark = VT100ScreenMark()
            let w = mutableState!.width()
            // Create interval at (w, 24) — the sentinel position.
            let range = VT100GridAbsCoordRangeMake(w, 24, w, 24)
            let interval = mutableState!.interval(for: range)
            mutableState!.mutableIntervalTree().add(mark, with: interval)
        })

        // Fold lines 20–24.  foldAbsLineRange: builds the query interval
        // with end.x = self.width, so the mark at (width, 24) falls inside
        // the query.  Before the fix this crashes in
        // SavedIntervalTreeObject.from with an array-index-out-of-bounds.
        screen.foldAbsLineRange(NSRange(location: 20, length: 4))
        screen.performBlock(joinedThreads: { _, _, _ in })

        // If we get here without crashing, the bug is fixed.
    }

    // MARK: - Fold: Collapse

    func testFoldCoordBeforeFoldUnchanged() {
        let rc = makeCoord(absY: 10)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 10)
    }

    func testFoldCoordWithinFoldBecomesInFold() {
        let rc = makeCoord(absY: 22)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        XCTAssertNotNil(rc.foldInfo)
    }

    func testFoldCoordAtFirstLineOfFoldBecomesInFold() {
        let rc = makeCoord(absY: 20)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        XCTAssertEqual(rc.coordWithinFold?.y, 0)
    }

    func testFoldCoordAtLastLineOfFoldBecomesInFold() {
        let rc = makeCoord(absY: 24)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        XCTAssertEqual(rc.coordWithinFold?.y, 4)
    }

    func testFoldCoordAfterFoldShiftsUp() {
        let rc = makeCoord(absY: 30)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
    }

    func testFoldCoordJustAfterFoldShiftsUp() {
        let rc = makeCoord(absY: 25)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 25)
    }

    func testFoldInfoProperty() {
        let rc = makeCoord(x: 5, absY: 22)
        fold(startLine: 20, endLine: 24)
        let info = rc.foldInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info!.coord.y, 2)
        XCTAssertEqual(info!.coord.x, 5)
    }

    func testFoldPreservesXCoordinate() {
        let rc = makeCoord(x: 42, absY: 22)
        let range = fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        XCTAssertEqual(rc.coordWithinFold?.x, 42)
        unfold(range: range)
        XCTAssertEqual(rc.status, .valid)
        XCTAssertEqual(rc.coord.x, 42)
    }

    func testFoldNearEndOfContentShiftsCoordUp() {
        // Coord near the last line of content. A large fold that removes many
        // lines causes numberOfLines to drop below the coord's old y value.
        // This reproduces a bug where validCoord (called inside linesDidShift)
        // checks the coord against the *already-updated* screen state and
        // incorrectly reports .truncatedBelow, preventing the shift.
        let rc = makeCoord(absY: 49)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 49)

        // Fold a large range before the coord. After the fold, the coord
        // should shift up and still track line 49's content.
        fold(startLine: 10, endLine: 45)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 49)
    }

    // MARK: - Fold: Expand

    func testUnfoldCoordBeforeUnfoldUnchanged() {
        let rc = makeCoord(absY: 10)
        let range = fold(startLine: 20, endLine: 24)
        assertContent(rc, matchesLine: 10)
        unfold(range: range)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 10)
    }

    func testUnfoldCoordThatWasInFoldBecomesValid() {
        let rc = makeCoord(absY: 22)
        let range = fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        unfold(range: range)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 22)
    }

    func testUnfoldCoordAfterUnfoldShiftsDown() {
        let rc = makeCoord(absY: 30)
        let range = fold(startLine: 20, endLine: 24)
        assertContent(rc, matchesLine: 30)
        unfold(range: range)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
    }

    func testUnfoldDifferentMarkDoesNotRestoreOurFold() {
        let rc = makeCoord(absY: 22)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        unfold(range: NSRange(location: 30, length: 5))
        XCTAssertEqual(rc.status, .inFold)
    }

    // MARK: - Multiple Folds

    func testMultipleFoldsInSequence() {
        let rc = makeCoord(absY: 40)
        fold(startLine: 10, endLine: 14)
        assertContent(rc, matchesLine: 40)
        fold(startLine: 22, endLine: 26)
        assertContent(rc, matchesLine: 40)
    }

    // MARK: - Porthole: Add/Remove via real screen API

    func testPortholeAddedCoordBeforeUnchanged() {
        let rc = makeCoord(absY: 10)
        addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .valid)
        XCTAssertEqual(rc.coord.y, 10)
        assertContent(rc, matchesLine: 10)
    }

    func testPortholeAddedCoordWithinBecomesInPorthole() {
        let rc = makeCoord(absY: 22)
        let porthole = addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)
        let info = rc.portholeInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info!.1.y, 2)
        // Verify the mark is the real one created by the screen
        let registeredMark = PortholeRegistry.instance.mark(for: porthole.uniqueIdentifier)
        XCTAssertNotNil(registeredMark)
    }

    func testPortholeAddedCoordAtFirstLine() {
        let rc = makeCoord(absY: 20)
        addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)
        XCTAssertEqual(rc.portholeInfo!.1.y, 0)
    }

    func testPortholeAddedCoordAtLastLine() {
        let rc = makeCoord(absY: 24)
        addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)
        XCTAssertEqual(rc.portholeInfo!.1.y, 4)
    }

    func testPortholeAddRemove_CoordAfterPorthole() {
        let rc = makeCoord(absY: 30)
        let porthole = addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .valid)

        removePorthole(porthole)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
    }

    func testPortholeAddRemove_CoordWithinPorthole() {
        let rc = makeCoord(absY: 22)
        let porthole = addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)

        removePorthole(porthole)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 22)
    }

    func testPortholeAddRemove_CoordBeforePorthole() {
        let rc = makeCoord(absY: 10)
        let porthole = addPorthole(startLine: 20, endLine: 24)
        assertContent(rc, matchesLine: 10)

        removePorthole(porthole)
        assertContent(rc, matchesLine: 10)
    }

    // MARK: - Porthole: Resize via real screen API

    func testPortholeResizedCoordInPortholeStaysInPorthole() {
        let rc = makeCoord(absY: 22)
        let porthole = addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)
        XCTAssertEqual(rc.portholeInfo!.1.y, 2)

        resizePorthole(porthole, toHeight: 3)
        XCTAssertEqual(rc.status, .inPorthole)
        XCTAssertEqual(rc.portholeInfo!.1.y, 2)
    }

    func testPortholeResizedCoordAfterShifts() {
        let rc = makeCoord(absY: 30)
        let porthole = addPorthole(startLine: 20, endLine: 24)
        let coordAfterAdd = rc.coord.y

        resizePorthole(porthole, toHeight: 3)
        XCTAssertEqual(rc.status, .valid)
        // Porthole grew from 1 to 3, so coord shifts down by 2.
        XCTAssertEqual(rc.coord.y, coordAfterAdd + 2)
    }

    // MARK: - Porthole: Mark deallocation

    /// Tests the WeakBox mechanism: when the captured PortholeMark is deallocated,
    /// the RC reports .retired. Uses a synthetic notification because the real screen
    /// API keeps the mark alive in the interval tree.
    func testPortholeMarkDeallocatedReturnsRetired() {
        let rc = makeCoord(absY: 22)
        autoreleasepool {
            let mark = PortholeMark(UUID().uuidString, width: screen.width())
            let converter: @convention(block) (VT100GridCoord) -> VT100GridCoord = { $0 }
            NotificationCenter.default.post(
                name: LinesShiftedNotification.name,
                object: session.guid,
                userInfo: [
                    LinesShiftedNotification.absLineKey: NSNumber(value: Int64(20)),
                    LinesShiftedNotification.deltaKey: NSNumber(value: Int32(-4)),
                    LinesShiftedNotification.markKey: mark,
                    LinesShiftedNotification.reasonKey: NSNumber(value: iTermLinesShiftedReason.portholeAdded.rawValue),
                    LinesShiftedNotification.replacedRangeKey: NSValue(range: NSRange(location: 20, length: 5)),
                    LinesShiftedNotification.converterKey: converter
                ])
            XCTAssertEqual(rc.status, .inPorthole)
            PortholeRegistry.instance.remove(mark.uniqueIdentifier)
        }
        XCTAssertEqual(rc.status, .retired)
    }

    // MARK: - Multiple Portholes

    func testTwoPortholes_CoordBetween() {
        let rc = makeCoord(absY: 15)
        addPorthole(startLine: 5, endLine: 9)
        XCTAssertEqual(rc.status, .valid)
        // After first porthole (5 lines → 1), coord shifts up by 4.
        let afterFirst = rc.coord.y

        addPorthole(startLine: 20, endLine: 24)
        // Second porthole is after the coord, so coord should be unchanged.
        XCTAssertEqual(rc.status, .valid)
        XCTAssertEqual(rc.coord.y, afterFirst)
    }

    func testTwoPortholes_CoordAfterBoth() {
        let rc = makeCoord(absY: 30)
        let p1 = addPorthole(startLine: 5, endLine: 9)
        let afterFirst = rc.coord.y

        let p2 = addPorthole(startLine: 16, endLine: 20)
        let afterSecond = rc.coord.y
        XCTAssertLessThan(afterSecond, afterFirst)

        // Remove in reverse order, coord should restore.
        removePorthole(p2)
        XCTAssertEqual(rc.coord.y, afterFirst)

        removePorthole(p1)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
    }

    // MARK: - Resize

    func testResizeWithReflowMovesCoord() {
        let s = makeSession(width: 10, height: 10, scrollback: 100, setup: { mutableState in
            mutableState.appendString(atCursor: "abcdefghijklmnopqrst")
            mutableState.appendCarriageReturnLineFeed()
        })
        let sc = s.screen!

        // RC at (5, 1) → 'p'
        let rc = ResilientCoordinate(dataSource: s, absCoord: VT100GridAbsCoordMake(5, 1))
        XCTAssertEqual(rc.status, .valid)
        assertChar(at: rc, equals: "p", screen: sc)

        // Widen to 20. The wrapped line unwraps: "abcdefghijklmnopqrst"
        // fits on one line, so 'p' moves from (5, 1) to (15, 0).
        sc.size = VT100GridSizeMake(20, 10)

        XCTAssertEqual(rc.status, .valid)
        assertChar(at: rc, equals: "p", screen: sc)
    }

    func testResizeWidenReducesLineCountBelowCoord() {
        // At width 5 with height 10 and scrollback 100, write 10 lines of
        // 20 chars each. Each wraps to 4 screen lines → 40 total.
        // Place the coord on the last wrapped line (y=39).
        // Widen to 40: each 20-char line fits in 1 line → 10 total.
        // The old y=39 is now beyond numberOfLines, so validCoord would
        // return nil and the converter would never run.
        let s = makeSession(width: 5, height: 10, scrollback: 100, setup: { mutableState in
            for _ in 0..<10 {
                mutableState.appendString(atCursor: "abcdefghijklmnopqrst")
                mutableState.appendCarriageReturnLineFeed()
            }
        })
        let sc = s.screen!

        // 't' is the last char of each 20-char line. At width 5 it's at x=4, y=3
        // of each 4-line group. The last group starts at y=36, so 't' is at (4, 39).
        let rc = ResilientCoordinate(dataSource: s, absCoord: VT100GridAbsCoordMake(4, 39))
        XCTAssertEqual(rc.status, .valid)
        assertChar(at: rc, equals: "t", screen: sc)

        // Widen to 40. 20-char lines unwrap to 1 line each → 10 lines total.
        // The converter should map (4, 39) → (19, 9).
        sc.size = VT100GridSizeMake(40, 10)

        XCTAssertEqual(rc.status, .valid)
        assertChar(at: rc, equals: "t", screen: sc)
    }

    func testResizeNarrowScreenContentVerification() {
        // Use short lines so narrowing doesn't reflow.
        let s = makeSession(setup: { [self] mutableState in
            for i in 0..<50 {
                mutableState.appendString(atCursor: String(repeating: expectedChar(forLine: i), count: 10))
                mutableState.appendCarriageReturnLineFeed()
            }
        })
        session = s
        screen = s.screen

        let rc = makeCoord(absY: 30)
        XCTAssertEqual(readChar(at: rc.coord), expectedChar(forLine: 30))

        screen.size = VT100GridSizeMake(40, 24)
        XCTAssertEqual(rc.status, .valid)
        XCTAssertEqual(readChar(at: rc.coord), expectedChar(forLine: 30))
    }

    func testResizeInvalidatesCoordWhenConverterFails() {
        let rc = makeCoord(absY: 30)
        let converter: @convention(block) (VT100GridAbsCoord) -> VT100GridAbsCoord = { _ in
            VT100GridAbsCoordInvalid
        }
        RCResizeNotification.post(guid: session.guid, converter: converter)
        XCTAssertEqual(rc.status, .invalid)
    }

    // MARK: - Clear/Truncate

    func testClearFromLineCoordBeforeUnchanged() {
        let rc = makeCoord(absY: 10)
        session.screenDidClearFromAbsoluteLine(toEnd: 40)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 10)
    }

    func testClearFromLineCoordAtOrAfterBecomesInvalid() {
        let rc = makeCoord(absY: 40)
        session.screenDidClearFromAbsoluteLine(toEnd: 40)
        XCTAssertEqual(rc.status, .invalid)
    }

    func testEraseWholeBufferInvalidatesCoord() {
        let rc = makeCoord(absY: 30)
        session.screenDidClearFromAbsoluteLine(toEnd: 0)
        XCTAssertEqual(rc.status, .invalid)
    }

    func testClearWhileInPorthole() {
        let rc = makeCoord(absY: 22)
        addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)
        // Clear from line 15 encompasses the porthole.
        session.screenDidClearFromAbsoluteLine(toEnd: 15)
        XCTAssertEqual(rc.status, .invalid)
    }

    func testClearBeforePortholePreservesPorthole() {
        let rc = makeCoord(absY: 22)
        addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)
        // Clear from line 30 — porthole is before.
        session.screenDidClearFromAbsoluteLine(toEnd: 30)
        XCTAssertEqual(rc.status, .inPorthole)
    }

    // MARK: - Session Dealloc

    func testSessionDeallocMakesInvalid() {
        let rc = makeCoord(absY: 30)
        postSessionDealloc()
        XCTAssertEqual(rc.status, .invalid)
    }

    func testSessionDeallocStopsObservingNotifications() {
        let rc = makeCoord(absY: 30)
        postSessionDealloc()
        XCTAssertEqual(rc.status, .invalid)
        fold(startLine: 10, endLine: 14)
        XCTAssertEqual(rc.status, .invalid)
    }

    // MARK: - Weak Session Reference

    func testRetiredWhenSessionDeallocated() {
        var tempSession: PTYSession? = makeSession()
        let tempGuid = tempSession!.guid!
        tempSession!.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<10 {
                mutableState!.appendString(atCursor: "line")
                mutableState!.appendCarriageReturnLineFeed()
            }
        })

        let rc = ResilientCoordinate(dataSource: tempSession!, absCoord: VT100GridAbsCoordMake(0, 5))
        XCTAssertEqual(rc.status, .valid)

        // Simulate session teardown: the dealloc notification sets location = .invalid.
        RCDataSourceDeallocNotification.post(guid: tempGuid)
        XCTAssertEqual(rc.status, .invalid)

        // After releasing the last strong reference, the weak ref may be zeroed
        // immediately or deferred to the next autorelease pool drain.
        // .invalid (session still alive) and .retired (session gone) are both correct.
        tempSession = nil
        let status = rc.status
        XCTAssertTrue(status == .invalid || status == .retired,
                      "Expected .invalid or .retired after session teardown, got \(status)")
    }

    // MARK: - Scrollback Overflow

    func testScrollbackOverflowMakesScrolledOff() {
        let rc = makeCoord(absY: 5)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState!.appendString(atCursor: "overflow")
                mutableState!.appendCarriageReturnLineFeed()
            }
        })
        XCTAssertEqual(rc.status, .scrolledOff)
    }

    func testFoldThenScrollbackOverflow() {
        let rc = makeCoord(absY: 5)
        fold(startLine: 3, endLine: 7)
        XCTAssertEqual(rc.status, .inFold)
        // Overflow the scrollback so the fold region scrolls off.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState!.appendString(atCursor: "overflow")
                mutableState!.appendCarriageReturnLineFeed()
            }
        })
        // The fold mark should be gone or the RC should be retired/invalid.
        let status = rc.status
        XCTAssertTrue(status == .retired || status == .invalid || status == .inFold,
                      "Expected .retired, .invalid, or .inFold (mark survived), got \(status)")
    }

    func testPortholeThenScrollbackOverflow() {
        let rc = makeCoord(absY: 5)
        addPorthole(startLine: 3, endLine: 7)
        XCTAssertEqual(rc.status, .inPorthole)
        // Overflow the scrollback so the porthole region scrolls off.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState!.appendString(atCursor: "overflow")
                mutableState!.appendCarriageReturnLineFeed()
            }
        })
        let status = rc.status
        XCTAssertTrue(status == .retired || status == .invalid || status == .inPorthole,
                      "Expected .retired, .invalid, or .inPorthole (mark survived), got \(status)")
    }

    // MARK: - Accessor edge cases

    func testCoordWithinFoldNilWhenNotInFold() {
        XCTAssertNil(makeCoord(absY: 30).coordWithinFold)
    }

    func testFoldInfoNilWhenNotInFold() {
        XCTAssertNil(makeCoord(absY: 30).foldInfo)
    }

    func testPortholeInfoNilWhenNotInPorthole() {
        XCTAssertNil(makeCoord(absY: 30).portholeInfo)
    }

    // MARK: - Multiple fold/unfold round-trips

    func testFoldUnfoldFoldUnfoldContentStillCorrect() {
        let rc = makeCoord(absY: 22)
        let range1 = fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        unfold(range: range1)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 22)

        let range2 = fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        unfold(range: range2)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 22)
    }

    // MARK: - Fold then clear

    func testFoldThenClearInvalidatesFoldInClearedRegion() {
        let rc = makeCoord(absY: 22)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        // Fold is at line 20, clear from 15 encompasses it.
        session.screenDidClearFromAbsoluteLine(toEnd: 15)
        XCTAssertEqual(rc.status, .invalid)
    }

    func testFoldThenClearBeforeFoldPreservesFold() {
        let rc = makeCoord(absY: 22)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        // Clear from line 30 — fold at 20 is before the clear range.
        session.screenDidClearFromAbsoluteLine(toEnd: 30)
        XCTAssertEqual(rc.status, .inFold)
    }

    // MARK: - Resize while in fold

    func testResizeWhileInFold() {
        let rc = makeCoord(absY: 22)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold)
        screen.size = VT100GridSizeMake(40, 24)
        XCTAssertEqual(rc.status, .inFold)
    }

    func testCoordJustBeforeFoldRangeStaysValid() {
        let rc = makeCoord(absY: 19)
        fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 19)
    }

    // MARK: - Porthole then fold

    func testPortholeCoordIgnoresUnrelatedFold() {
        let rc = makeCoord(absY: 22)
        addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)
        fold(startLine: 5, endLine: 9)
        XCTAssertEqual(rc.status, .inPorthole)
    }

    // MARK: - Nested Folds

    func testNestedFold_CoordBeforeBothFolds() {
        let rc = makeCoord(absY: 10)
        fold(startLine: 15, endLine: 19)
        assertContent(rc, matchesLine: 10)
        fold(startLine: 13, endLine: 17)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 10)
    }

    func testNestedFold_CoordInInnerFoldStaysInInnerFold() {
        let rc = makeCoord(absY: 17)
        fold(startLine: 15, endLine: 19)
        XCTAssertEqual(rc.status, .inFold)
        fold(startLine: 13, endLine: 17)
        XCTAssertEqual(rc.status, .inFold)
    }

    func testNestedFold_CoordBetweenFoldsEntersOuterFold() {
        let rc = makeCoord(absY: 20)
        fold(startLine: 15, endLine: 19)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 20)
        fold(startLine: 13, endLine: 17)
        XCTAssertEqual(rc.status, .inFold)
    }

    func testNestedFold_CoordAfterBothFoldsShifts() {
        let rc = makeCoord(absY: 30)
        fold(startLine: 15, endLine: 19)
        assertContent(rc, matchesLine: 30)
        fold(startLine: 13, endLine: 17)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
    }

    func testNestedFold_UnfoldOuter_InnerStillFolded() {
        let rcInner = makeCoord(absY: 17)
        let rcBetween = makeCoord(absY: 20)
        let rcAfter = makeCoord(absY: 30)

        let fold1Range = fold(startLine: 15, endLine: 19)
        let fold2Range = fold(startLine: 13, endLine: 17)

        unfold(range: fold2Range)
        XCTAssertEqual(rcBetween.status, .valid)
        assertContent(rcBetween, matchesLine: 20)
        XCTAssertEqual(rcInner.status, .inFold)
        XCTAssertEqual(rcAfter.status, .valid)
        assertContent(rcAfter, matchesLine: 30)

        unfold(range: fold1Range)
        XCTAssertEqual(rcInner.status, .valid)
        assertContent(rcInner, matchesLine: 17)
        assertContent(rcAfter, matchesLine: 30)
    }

    func testNestedFold_UnfoldInnerFirst_ThenOuter() {
        let rcInner = makeCoord(absY: 17)
        let rcAfter = makeCoord(absY: 30)

        let fold1Range = fold(startLine: 15, endLine: 19)
        let fold2Range = fold(startLine: 13, endLine: 17)

        // fold1's mark is saved inside fold2 — unfold is a no-op.
        unfold(range: fold1Range)
        XCTAssertEqual(rcInner.status, .inFold)

        unfold(range: fold2Range)
        XCTAssertEqual(rcInner.status, .inFold) // still in fold1

        unfold(range: fold1Range)
        XCTAssertEqual(rcInner.status, .valid)
        assertContent(rcInner, matchesLine: 17)
        assertContent(rcAfter, matchesLine: 30)
    }

    func testNestedFold_ThreeLevels() {
        let rcDeep = makeCoord(absY: 17)
        let rcAfter = makeCoord(absY: 40)

        let fold1Range = fold(startLine: 15, endLine: 19)
        XCTAssertEqual(rcDeep.status, .inFold)
        let fold2Range = fold(startLine: 13, endLine: 17)
        let fold3Range = fold(startLine: 10, endLine: 14)

        XCTAssertEqual(rcDeep.status, .inFold)
        assertContent(rcAfter, matchesLine: 40)

        unfold(range: fold3Range)
        unfold(range: fold2Range)
        unfold(range: fold1Range)

        XCTAssertEqual(rcDeep.status, .valid)
        assertContent(rcDeep, matchesLine: 17)
        assertContent(rcAfter, matchesLine: 40)
    }

    func testNestedFold_CoordAtOuterBoundaryEntersFold() {
        let rc = makeCoord(absY: 13)
        fold(startLine: 15, endLine: 19)
        assertContent(rc, matchesLine: 13)
        fold(startLine: 13, endLine: 17)
        XCTAssertEqual(rc.status, .inFold)
        XCTAssertEqual(rc.coordWithinFold?.y, 0)
    }

    func testNestedFold_CoordJustOutsideOuterBoundary() {
        let rc = makeCoord(absY: 12)
        fold(startLine: 15, endLine: 19)
        assertContent(rc, matchesLine: 12)
        fold(startLine: 13, endLine: 17)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 12)
    }

    // MARK: - Fold / resize / unfold with reflow

    func testFoldResizeUnfold_WrappedLine() {
        let localSession = makeSession(width: 10, height: 10, scrollback: 100, setup: { mutableState in
            mutableState.appendString(atCursor: "abcdefghijklmnopqrstuvwxy")
            mutableState.appendCarriageReturnLineFeed()
            mutableState.appendString(atCursor: "ZZZZZZZZZZ")
            mutableState.appendCarriageReturnLineFeed()
        })
        let localScreen = localSession.screen!

        let dump0 = localScreen.compactLineDumpWithHistory()!.components(separatedBy: "\n")
        XCTAssertEqual(dump0[0], "abcdefghij")
        XCTAssertTrue(dump0[2].hasPrefix("uvwxy"))

        // RC at (4, 2) — 'y', the last char of the wrapped line.
        let rc = ResilientCoordinate(dataSource: localSession, absCoord: VT100GridAbsCoordMake(4, 2))
        XCTAssertEqual(rc.status, .valid)

        // 1. Fold lines 0-2.
        localScreen.foldAbsLineRange(NSRange(location: 0, length: 2))
        localScreen.performBlock(joinedThreads: { _, _, _ in })
        XCTAssertEqual(rc.status, .inFold)
        XCTAssertEqual(rc.coordWithinFold, VT100GridCoordMake(4, 2))

        // 2. Widen 10 → 12.
        localScreen.size = VT100GridSizeMake(12, 10)
        XCTAssertEqual(rc.status, .inFold)

        // 3. Unfold. At width 12, 'y' reflows to (0, 2).
        localScreen.removeFolds(in: NSRange(location: 0, length: 1), completion: nil)
        localScreen.performBlock(joinedThreads: { _, _, _ in })

        assertChar(at: rc, equals: "y", screen: localScreen)
    }

    // MARK: - Porthole add/remove via real screen API with content verification

    func testPortholeResizeUnfold_WrappedLine() {
        let s = makeSession(width: 10, height: 10, scrollback: 100, setup: { mutableState in
            mutableState.appendString(atCursor: "abcdefghijklmnopqrstuvwxy")
            mutableState.appendCarriageReturnLineFeed()
            mutableState.appendString(atCursor: "ZZZZZZZZZZ")
            mutableState.appendCarriageReturnLineFeed()
        })
        let sc = s.screen!

        let rc = ResilientCoordinate(dataSource: s, absCoord: VT100GridAbsCoordMake(4, 2))
        XCTAssertEqual(rc.status, .valid)

        // Add porthole replacing lines 0-2, saving original lines first.
        let porthole = addPorthole(startLine: 0, endLine: 2, screen: sc)
        XCTAssertEqual(rc.status, .inPorthole)

        // Widen 10 → 12.
        sc.size = VT100GridSizeMake(12, 10)
        XCTAssertEqual(rc.status, .inPorthole)

        // Remove porthole. Content reflows at width 12: 'y' should still be findable.
        removePorthole(porthole, screen: sc)

        assertChar(at: rc, equals: "y", screen: sc)
    }

    // MARK: - Cross-nesting: porthole within fold

    func testPortholeWithinFold_CoordInPorthole() {
        // RC at line 22, porthole replaces lines 20-24, then fold encompasses it all.
        let rc = makeCoord(absY: 22)

        let porthole = addPorthole(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inPorthole)

        // Fold a range that includes the porthole's visible line.
        // After porthole (5→1), the porthole line is at position 20.
        // Fold lines 18-22 (which includes the porthole at 20).
        fold(startLine: 18, endLine: 22)

        // RC stays in porthole (fold handler skips because validCoord is nil).
        XCTAssertEqual(rc.status, .inPorthole)

        // Unfold.
        unfold(range: NSRange(location: 18, length: 4))

        // RC should still be in porthole (porthole mark is restored).
        XCTAssertEqual(rc.status, .inPorthole)

        // Remove porthole.
        removePorthole(porthole)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 22)
    }

    func testPortholeWithinFold_CoordAfterBoth() {
        let rc = makeCoord(absY: 30)

        let porthole = addPorthole(startLine: 20, endLine: 24) // 5→1, delta=-4
        assertContent(rc, matchesLine: 30)

        fold(startLine: 18, endLine: 22) // encompasses porthole line
        assertContent(rc, matchesLine: 30)

        unfold(range: NSRange(location: 18, length: 4))
        assertContent(rc, matchesLine: 30)

        removePorthole(porthole)
        assertContent(rc, matchesLine: 30)
    }

    // MARK: - Cross-nesting: fold within porthole

    func testFoldWithinPorthole_CoordInFold() {
        // RC at line 22, fold lines 20-24, then porthole encompasses the fold.
        let rc = makeCoord(absY: 22)

        fold(startLine: 20, endLine: 24) // 5→1
        XCTAssertEqual(rc.status, .inFold)

        // Porthole replaces a range including the fold line (at position 20).
        let porthole = addPorthole(startLine: 18, endLine: 22)

        // RC stays in fold (porthole handler skips it).
        XCTAssertEqual(rc.status, .inFold)

        // Remove porthole — fold is restored.
        removePorthole(porthole)
        XCTAssertEqual(rc.status, .inFold)

        // Unfold — RC restores.
        unfold(range: NSRange(location: 20, length: 4))
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 22)
    }

    func testFoldWithinPorthole_CoordAfterBoth() {
        let rc = makeCoord(absY: 30)

        fold(startLine: 20, endLine: 24)
        assertContent(rc, matchesLine: 30)

        let porthole = addPorthole(startLine: 18, endLine: 22)
        assertContent(rc, matchesLine: 30)

        removePorthole(porthole)
        assertContent(rc, matchesLine: 30)

        unfold(range: NSRange(location: 20, length: 4))
        assertContent(rc, matchesLine: 30)
    }

    // MARK: - Resize causing scrollback overflow

    func testResizeNarrowCausesScrollbackOverflow() {
        // Create a session with minimal scrollback so narrowing overflows it.
        // Write 25 full-width lines. Each wraps to 8 lines at width 5,
        // totalling 200 lines — well above the 30-line capacity (20+10).
        let s = makeSession(width: 40, height: 10, scrollback: 20, setup: { mutableState in
            for _ in 0..<25 {
                mutableState.appendString(atCursor: String(repeating: "x", count: 40))
                mutableState.appendCarriageReturnLineFeed()
            }
        })
        let sc = s.screen!
        let rc = ResilientCoordinate(dataSource: s, absCoord: VT100GridAbsCoordMake(0, 0))
        XCTAssertEqual(rc.status, .valid)

        // Narrow dramatically so lines reflow and overflow the scrollback.
        sc.size = VT100GridSizeMake(5, 10)
        // The resize converter remaps coords before excess lines are dropped,
        // so the RC might land on .valid, .scrolledOff, or .invalid depending
        // on timing. The key invariant: the RC must NOT silently report .valid
        // with stale content pointing at a totally different line.
        let status = rc.status
        XCTAssertTrue(status == .scrolledOff || status == .invalid || status == .valid,
                      "Unexpected status \(status)")
        if status == .valid {
            // If the converter mapped to a valid coord, it must be above the overflow
            // threshold — i.e., the coord was adjusted to survive the reflow.
            let overflow = sc.totalScrollbackOverflow()
            XCTAssertGreaterThanOrEqual(rc.coord.y, overflow,
                                        "Coord \(rc.coord.y) is below overflow \(overflow)")
        }
    }
}

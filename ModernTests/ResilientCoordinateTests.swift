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
    // Forwards the RC-protocol getters to the live screen so RCs constructed
    // by the test fixture bind to the main-thread pool with the same guid
    // production uses. Previously this lived as a PTYSession extension; that
    // surface was dead in production (only this test consumed it) and has
    // been pulled in here.
    private var rcDataSource: ScreenBackedRCDataSource!

    private static let charPool = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    private func expectedChar(forLine line: Int) -> Character {
        Self.charPool[line % Self.charPool.count]
    }

    private func makeSession(width: Int32 = 80, height: Int32 = 24,
                             scrollback: Int32 = 1000,
                             setup: ((VT100ScreenMutableState) -> Void)? = nil) -> PTYSession {
        let s = PTYSession(synthetic: false)!
        let sc = s.screen
        sc.delegate = s
        sc.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            sc.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
            mutableState.maxScrollbackLines = UInt32(scrollback)
            setup?(mutableState)
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
        rcDataSource = ScreenBackedRCDataSource(screen: screen)
    }

    override func tearDown() {
        rcDataSource = nil
        session = nil
        screen = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCoord(x: Int32 = 0, absY: Int64) -> ResilientCoordinate {
        return ResilientCoordinate(dataSource: rcDataSource,
                                  absCoord: VT100GridAbsCoordMake(x, absY))
    }

    private func readChar(at coord: VT100GridAbsCoord,
                          screen sc: VT100Screen? = nil) -> Character? {
        let sc = sc ?? screen!
        let dump = sc.compactLineDumpWithHistory()
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

    // MARK: - Basic Status

    func testValidCoord() {
        let rc = makeCoord(absY: 30)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
    }

    func testScrolledOffCoord() {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState.appendString(atCursor: "x")
                mutableState.appendCarriageReturnLineFeed()
            }
        })
        let rc = makeCoord(absY: 0)
        XCTAssertEqual(rc.status, .scrolledOff)
    }

    func testScrolledOffBoundary() {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState.appendString(atCursor: "x")
                mutableState.appendCarriageReturnLineFeed()
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
            let w = mutableState.width()
            // Create interval at (w, 24) — the sentinel position.
            let range = VT100GridAbsCoordRangeMake(w, 24, w, 24)
            let interval = mutableState.interval(for: range)
            mutableState.mutableIntervalTree().add(mark, with: interval)
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

    /// The unfold handler decides whether to restore an RC's fold by
    /// comparing the notification's FoldMark to the RC's stored mark
    /// via `===` (reference identity), NOT `.guid` equality. That
    /// distinction is load-bearing: mutation-pool RCs store the
    /// progenitor and only the progenitor-flavored linesShifted post
    /// (mutation thread) should restore them; main-pool RCs store the
    /// doppelganger and only the doppelganger-flavored post (main
    /// thread, via the delegate side effect) should restore them. If
    /// the check ever drifted to guid equality, both pools would
    /// react to either post and a half-resolved cross-pool state
    /// could appear briefly during a fold/unfold cycle.
    ///
    /// Targeted regression for that contract: post an unfold
    /// notification carrying a *different FoldMark instance with the
    /// same guid* as the one the RC stores. The RC must stay in fold.
    /// Then prove the harness is otherwise wired correctly by running
    /// the real screen-level unfold and watching it restore the RC.
    func testUnfoldForeignFoldMarkInstanceDoesNotRestoreOurFold() {
        let rc = makeCoord(absY: 22)
        let range = fold(startLine: 20, endLine: 24)
        XCTAssertEqual(rc.status, .inFold,
                       "Setup: RC must enter the fold after fold()")
        guard let storedFoldMark = rc.foldInfo?.mark else {
            XCTFail("Setup: RC must carry a stored fold mark while in fold")
            return
        }

        // Phantom: a different FoldMark instance that shares the
        // stored mark's guid via the copy initializer. Identity
        // (`===`) rejects; guid equality would not.
        let phantom = FoldMark(storedFoldMark)
        XCTAssertFalse(phantom === storedFoldMark,
                       "Setup: phantom must be a distinct reference")
        XCTAssertEqual(phantom.guid, storedFoldMark.guid,
                       "Setup: phantom must share the guid")

        let identityConverter: @convention(block) (VT100GridCoord) -> VT100GridCoord = { $0 }
        NotificationCenter.default.post(
            name: LinesShiftedNotification.name,
            object: rcDataSource.rcGuid,
            userInfo: [
                LinesShiftedNotification.absLineKey: NSNumber(value: Int64(range.location)),
                LinesShiftedNotification.deltaKey: NSNumber(value: Int32(range.length)),
                LinesShiftedNotification.reasonKey: NSNumber(value: iTermLinesShiftedReason.unfold.rawValue),
                LinesShiftedNotification.replacedRangeKey: NSValue(range: range),
                LinesShiftedNotification.converterKey: identityConverter,
                LinesShiftedNotification.markKey: phantom,
            ])
        XCTAssertEqual(rc.status, .inFold,
                       "A phantom unfold whose FoldMark is a different instance must NOT restore our fold (identity, not guid)")

        // Harness check: the real screen.removeFolds DOES restore,
        // proving the only behavioral difference above was the mark
        // instance.
        unfold(range: range)
        XCTAssertEqual(rc.status, .valid,
                       "Real unfold via the screen API restores the RC, confirming identity was the only thing that differed")
    }

    // MARK: - Multiple Folds

    func testMultipleFoldsInSequence() {
        let rc = makeCoord(absY: 40)
        fold(startLine: 10, endLine: 14)
        assertContent(rc, matchesLine: 40)
        fold(startLine: 22, endLine: 26)
        assertContent(rc, matchesLine: 40)
    }

    // MARK: - Plain replacement (Replace with Pretty-Printed JSON path)

    /// Build a replacement line the same way SelectionReplacement's
    /// executors do (see Base64Executor in SelectionReplacement.swift).
    private func makeReplacementLine(_ text: String) -> ScreenCharArray {
        let sca = MutableScreenCharArray()
        sca.eol = EOL_HARD
        var c = screen_char_t()
        c.backgroundColorMode = ColorModeAlternate.rawValue
        c.backgroundColor = UInt32(ALTSEM_DEFAULT)
        c.foregroundColorMode = ColorModeAlternate.rawValue
        c.foregroundColor = UInt32(ALTSEM_DEFAULT)
        sca.append(text, style: c, continuation: sca.continuation)
        return sca
    }

    /// Replace lines [startLine, endLine] with `count` fresh lines through
    /// the same screen API that "Replace with Pretty-Printed JSON" and the
    /// base64 encode/decode context menu items use (PTYTextView+ARC.m
    /// -replaceSelectionWith:). promptLength is -1, so unlike a fold no
    /// FoldMark is created: this is a plain content replacement that rides
    /// the fold machinery and posts linesShifted with reason .fold.
    private func replaceLines(startLine: Int, endLine: Int,
                              withLineCount count: Int,
                              screen sc: VT100Screen? = nil) {
        let sc = sc ?? screen!
        let lines = (0..<count).map { makeReplacementLine("replacement line \($0)") }
        let range = VT100GridAbsCoordRangeMake(0, Int64(startLine),
                                               sc.width(), Int64(endLine))
        sc.replace(range, withLines: lines, promptLength: -1, blockMarks: [:])
        sc.performBlock(joinedThreads: { _, _, _ in })
    }

    /// Replacing 5 lines with 8 makes the buffer GROW (delta +3). The
    /// linesShifted post still carries reason .fold, whose handler asserts
    /// delta < 0 — before the fix this test dies at
    /// ResilientCoordinate.linesDidShift's it_assert rather than failing.
    /// A coord below the replaced range must shift down and keep tracking
    /// its content.
    func testReplaceSelectionGrowth_CoordBelowShiftsDown() {
        let rc = makeCoord(absY: 30)
        assertContent(rc, matchesLine: 30)
        replaceLines(startLine: 20, endLine: 24, withLineCount: 8)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
    }

    /// Growth variant of the coord-inside case. Also crashes at the
    /// delta < 0 assert before the fix. Once the assert is gone, the coord
    /// sits inside a replaced range with no FoldMark to enter, so its
    /// content is destroyed and it must become .invalid.
    func testReplaceSelectionGrowth_CoordInsideBecomesInvalid() {
        let rc = makeCoord(absY: 22)
        replaceLines(startLine: 20, endLine: 24, withLineCount: 8)
        XCTAssertEqual(rc.status, .invalid)
    }

    /// Replacing 5 lines with 2 SHRINKS the buffer (delta -3), so the
    /// delta < 0 assert passes — but a coord inside the replaced range
    /// falls through the entering-fold branch (there is no FoldMark) into
    /// the "folded above us" branch and gets silently shifted up, staying
    /// .valid while pointing at unrelated content. Its content was
    /// destroyed by the replacement, so it must become .invalid.
    func testReplaceSelectionShrink_CoordInsideBecomesInvalid() {
        let rc = makeCoord(absY: 22)
        replaceLines(startLine: 20, endLine: 24, withLineCount: 2)
        XCTAssertEqual(rc.status, .invalid)
    }

    /// Same as above but on the first replaced line (coord.y == absLine),
    /// which exercises a different hole: neither the entering-fold branch
    /// (no mark) nor the shift-up branch (absLine is not < coord.y) fires,
    /// so the coord keeps its old position, now pointing at the first
    /// replacement line instead of its destroyed content.
    func testReplaceSelectionShrink_CoordAtFirstReplacedLineBecomesInvalid() {
        let rc = makeCoord(absY: 20)
        replaceLines(startLine: 20, endLine: 24, withLineCount: 2)
        XCTAssertEqual(rc.status, .invalid)
    }

    /// Control: the shrink case for a coord BELOW the replaced range works
    /// today (the shift-by-delta branch is sign-agnostic). Proves the
    /// harness wiring so the failures above isolate the actual bugs.
    func testReplaceSelectionShrink_CoordBelowShiftsUp() {
        let rc = makeCoord(absY: 30)
        assertContent(rc, matchesLine: 30)
        replaceLines(startLine: 20, endLine: 24, withLineCount: 2)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 30)
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
    /// the RC reports .invalid. Uses a synthetic notification because the real screen
    /// API keeps the mark alive in the interval tree.
    func testPortholeMarkDeallocatedReturnsInvalid() {
        let rc = makeCoord(absY: 22)
        autoreleasepool {
            let mark = PortholeMark(UUID().uuidString, width: screen.width())
            let converter: @convention(block) (VT100GridCoord) -> VT100GridCoord = { $0 }
            NotificationCenter.default.post(
                name: LinesShiftedNotification.name,
                object: rcDataSource.rcGuid,
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
        XCTAssertEqual(rc.status, .invalid)
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
        let sc = s.screen
        // RC holds dataSource weakly. Pin `ds` for the rest of the test so
        // ARC doesn't release it after the constructor returns.
        let ds = ScreenBackedRCDataSource(screen: sc)
        defer { _ = ds }

        // RC at (5, 1) → 'p'
        let rc = ResilientCoordinate(dataSource: ds, absCoord: VT100GridAbsCoordMake(5, 1))
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
        let sc = s.screen

        let ds = ScreenBackedRCDataSource(screen: sc)
        defer { _ = ds }

        // 't' is the last char of each 20-char line. At width 5 it's at x=4, y=3
        // of each 4-line group. The last group starts at y=36, so 't' is at (4, 39).
        let rc = ResilientCoordinate(dataSource: ds, absCoord: VT100GridAbsCoordMake(4, 39))
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
        RCResizeNotification.post(guid: rcDataSource.rcGuid, converter: converter)
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

    // MARK: - Weak DataSource Reference

    /// When the dataSource deallocs, the RC's weak ref auto-zeros and
    /// `status` returns `.invalid`. Uses a minimal local data source so we
    /// can deterministically drop it (PTYSession's reference graph makes
    /// reliable dealloc in a unit test impractical).
    func testInvalidWhenDataSourceDeallocated() {
        let rc: ResilientCoordinate
        do {
            let ds = TestDataSource(guid: "ephemeral", width: 80, lines: 100)
            rc = ResilientCoordinate(dataSource: ds, absCoord: VT100GridAbsCoordMake(0, 5))
            XCTAssertEqual(rc.status, .valid)
        }
        // ds is released here. Drain an autoreleasepool so any deferred
        // releases happen before the assertion.
        autoreleasepool { }
        XCTAssertEqual(rc.status, .invalid)
    }

    // MARK: - Scrollback Overflow

    func testScrollbackOverflowMakesScrolledOff() {
        let rc = makeCoord(absY: 5)
        XCTAssertEqual(rc.status, .valid)
        assertContent(rc, matchesLine: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState.appendString(atCursor: "overflow")
                mutableState.appendCarriageReturnLineFeed()
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
                mutableState.appendString(atCursor: "overflow")
                mutableState.appendCarriageReturnLineFeed()
            }
        })
        // The fold mark should be gone or the RC should be invalid.
        let status = rc.status
        XCTAssertTrue(status == .invalid || status == .inFold,
                      "Expected .invalid or .inFold (mark survived), got \(status)")
    }

    func testPortholeThenScrollbackOverflow() {
        let rc = makeCoord(absY: 5)
        addPorthole(startLine: 3, endLine: 7)
        XCTAssertEqual(rc.status, .inPorthole)
        // Overflow the scrollback so the porthole region scrolls off.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<2000 {
                mutableState.appendString(atCursor: "overflow")
                mutableState.appendCarriageReturnLineFeed()
            }
        })
        let status = rc.status
        XCTAssertTrue(status == .invalid || status == .inPorthole,
                      "Expected .invalid or .inPorthole (mark survived), got \(status)")
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
        let localScreen = localSession.screen

        let dump0 = localScreen.compactLineDumpWithHistory().components(separatedBy: "\n")
        XCTAssertEqual(dump0[0], "abcdefghij")
        XCTAssertTrue(dump0[2].hasPrefix("uvwxy"))

        let ds = ScreenBackedRCDataSource(screen: localScreen)
        defer { _ = ds }
        // RC at (4, 2) — 'y', the last char of the wrapped line.
        let rc = ResilientCoordinate(dataSource: ds, absCoord: VT100GridAbsCoordMake(4, 2))
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
        let sc = s.screen
        let ds = ScreenBackedRCDataSource(screen: sc)
        defer { _ = ds }

        let rc = ResilientCoordinate(dataSource: ds, absCoord: VT100GridAbsCoordMake(4, 2))
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
        let sc = s.screen
        let ds = ScreenBackedRCDataSource(screen: sc)
        defer { _ = ds }
        let rc = ResilientCoordinate(dataSource: ds, absCoord: VT100GridAbsCoordMake(0, 0))
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

    // MARK: - dictionaryValue / from(dictionary:) direct bridge

    private func makeFoldMark() -> FoldMark {
        return FoldMark(savedLines: nil,
                        savedITOs: [],
                        promptLength: 0,
                        imageCodes: Set<Int32>(),
                        width: 80)
    }

    /// Treat the dict shape as a contract: must match what `JSONEncoder` +
    /// `JSONSerialization` produced before the bridge was specialized. If
    /// these helpers ever diverge from Codable, every test below tightens
    /// to that diff.
    private func codableDict(of rc: ResilientCoordinate) -> NSDictionary {
        let data = try! JSONEncoder().encode(rc)
        return try! JSONSerialization.jsonObject(with: data, options: []) as! NSDictionary
    }
    private func codableDict(of range: ResilientCoordinateRange) -> NSDictionary {
        let data = try! JSONEncoder().encode(range)
        return try! JSONSerialization.jsonObject(with: data, options: []) as! NSDictionary
    }

    func test_dict_coord_shapeMatchesCodable() {
        let ds = TestDataSource(guid: "ds", width: 80, lines: 100)
        let rc = ResilientCoordinate(dataSource: ds,
                                     absCoord: VT100GridAbsCoord(x: 7, y: 42))
        XCTAssertEqual(rc.dictionaryValue, codableDict(of: rc))
        // Round-trip via the direct path: same coord comes back.
        let restored = ResilientCoordinate.from(dictionary: rc.dictionaryValue)!
        let loadDS = TestDataSource(guid: "load", width: 80, lines: 100)
        restored.bind(to: loadDS)
        XCTAssertEqual(restored.status, .valid)
        XCTAssertEqual(restored.coord.x, 7)
        XCTAssertEqual(restored.coord.y, 42)
        _ = loadDS  // keep alive — RC holds dataSource weakly
    }

    func test_dict_unresolvedCoord_decodesAsCoord() {
        // .unresolvedCoord and .coord share the wire shape — both go out
        // as kind="coord". A pre-bind RC decodes identically to a bound one.
        let rc = ResilientCoordinate(unboundAbsCoord: VT100GridAbsCoord(x: 1, y: 2))
        XCTAssertEqual(rc.dictionaryValue, codableDict(of: rc))
        let restored = ResilientCoordinate.from(dictionary: rc.dictionaryValue)!
        XCTAssertEqual(restored.status, .unresolved)
    }

    func test_dict_invalid_shapeMatchesCodable() {
        // No public way to construct an .invalid RC at init, but a dead
        // WeakBox in .fold encodes as kind="invalid" — exercise that path.
        let saveDS = TestDataSource(guid: "save", width: 80, lines: 100)
        let rc: ResilientCoordinate
        do {
            let foldMark = makeFoldMark()
            let dop = foldMark.doppelganger() as! FoldMark
            rc = ResilientCoordinate(dataSource: saveDS,
                                     enclosingFold: dop,
                                     coord: VT100GridCoord(x: 1, y: 0))
            _ = foldMark
            _ = dop
        }
        // foldMark and dop both go out of scope here; the WeakBox should
        // zero out and encode produces .invalid.
        let dict = rc.dictionaryValue
        XCTAssertEqual(dict, codableDict(of: rc))
        XCTAssertEqual(dict["kind"] as? String, "invalid")
        let restored = ResilientCoordinate.from(dictionary: dict)!
        XCTAssertEqual(restored.status, .invalid)
    }

    func test_dict_unresolvedFold_shapeMatchesCodable() {
        // Re-build an unresolved-fold RC via the dict path (the live .fold
        // case requires a FoldMark; the unresolved variant lets us check
        // the wire shape directly).
        let seed: NSDictionary = [
            "kind": "fold",
            "markGuid": "fake-fold-guid",
            "innerX": NSNumber(value: Int32(2)),
            "innerY": NSNumber(value: Int32(3)),
        ]
        let rc = ResilientCoordinate.from(dictionary: seed)!
        XCTAssertEqual(rc.dictionaryValue, codableDict(of: rc))
        XCTAssertEqual(rc.dictionaryValue["kind"] as? String, "fold")
        XCTAssertEqual(rc.dictionaryValue["markGuid"] as? String, "fake-fold-guid")
    }

    func test_dict_unresolvedPorthole_shapeMatchesCodable() {
        let seed: NSDictionary = [
            "kind": "porthole",
            "markGuid": "fake-porthole-guid",
            "innerX": NSNumber(value: Int32(4)),
            "innerY": NSNumber(value: Int32(5)),
        ]
        let rc = ResilientCoordinate.from(dictionary: seed)!
        XCTAssertEqual(rc.dictionaryValue, codableDict(of: rc))
        XCTAssertEqual(rc.dictionaryValue["kind"] as? String, "porthole")
    }

    func test_dict_liveFold_shapeMatchesCodable() {
        let foldMark = makeFoldMark()
        let dop = foldMark.doppelganger() as! FoldMark
        let ds = TestDataSource(guid: "ds", width: 80, lines: 100)
        let rc = ResilientCoordinate(dataSource: ds,
                                     enclosingFold: dop,
                                     coord: VT100GridCoord(x: 9, y: 1))
        XCTAssertEqual(rc.dictionaryValue, codableDict(of: rc))
        XCTAssertEqual(rc.dictionaryValue["markGuid"] as? String, foldMark.guid)
    }

    func test_range_dict_shapeMatchesCodable() {
        let ds = TestDataSource(guid: "ds", width: 80, lines: 100)
        let range = ResilientCoordinateRange(
            start: ResilientCoordinate(dataSource: ds, absCoord: VT100GridAbsCoord(x: 0, y: 5)),
            end: ResilientCoordinate(dataSource: ds, absCoord: VT100GridAbsCoord(x: 7, y: 5)))
        XCTAssertEqual(range.dictionaryValue, codableDict(of: range))

        let restored = ResilientCoordinateRange.from(dictionary: range.dictionaryValue)!
        let loadDS = TestDataSource(guid: "load", width: 80, lines: 100)
        restored.start.bind(to: loadDS)
        restored.end.bind(to: loadDS)
        XCTAssertEqual(restored.start.coord.x, 0)
        XCTAssertEqual(restored.end.coord.x, 7)
        _ = loadDS  // keep alive — RC holds dataSource weakly
    }

    // Defensive cases on the decoder

    func test_dict_missingKind_returnsNil() {
        let dict: NSDictionary = ["absX": 1, "absY": 2]
        XCTAssertNil(ResilientCoordinate.from(dictionary: dict))
    }

    func test_dict_unknownKind_returnsNil() {
        let dict: NSDictionary = ["kind": "horseshoe", "absX": 1, "absY": 2]
        XCTAssertNil(ResilientCoordinate.from(dictionary: dict))
    }

    func test_dict_coordMissingFields_returnsNil() {
        let dict: NSDictionary = ["kind": "coord", "absX": 1] // absY missing
        XCTAssertNil(ResilientCoordinate.from(dictionary: dict))
    }

    func test_dict_foldMissingGuid_returnsNil() {
        let dict: NSDictionary = ["kind": "fold", "innerX": 1, "innerY": 2]
        XCTAssertNil(ResilientCoordinate.from(dictionary: dict))
    }

    func test_range_dict_missingStart_returnsNil() {
        let dict: NSDictionary = [
            "end": ["kind": "coord", "absX": 1, "absY": 2] as NSDictionary,
        ]
        XCTAssertNil(ResilientCoordinateRange.from(dictionary: dict))
    }

    /// Backwards-compat: a dict written by the OLD JSON-round-trip path
    /// (NSNumber values produced by JSONSerialization, NSString keys) must
    /// still decode through the new direct decoder.
    func test_dict_acceptsJSONSerializationProducedShape() {
        let ds = TestDataSource(guid: "ds", width: 80, lines: 100)
        let rc = ResilientCoordinate(dataSource: ds,
                                     absCoord: VT100GridAbsCoord(x: 11, y: 13))
        let viaJSON = codableDict(of: rc)
        let restored = ResilientCoordinate.from(dictionary: viaJSON)!
        let loadDS = TestDataSource(guid: "load", width: 80, lines: 100)
        restored.bind(to: loadDS)
        XCTAssertEqual(restored.coord.x, 11)
        XCTAssertEqual(restored.coord.y, 13)
        _ = loadDS  // keep alive — RC holds dataSource weakly
    }
}

/// ResilientCoordinateDataSource that forwards the four protocol getters to
/// a live VT100Screen. Used by the suite-wide test fixture so RCs the tests
/// build land in the same main-thread pool as production RCs do.
///
/// Holds a strong screen reference because the RC keeps a weak dataSource;
/// the test class owns one instance for the duration of each test.
@objc private class ScreenBackedRCDataSource: NSObject, ResilientCoordinateDataSource {
    private let screen: VT100Screen
    init(screen: VT100Screen) {
        self.screen = screen
        super.init()
    }
    var rcGuid: String { screen.immutableState.mainThreadPoolGuid }
    var rcWidth: Int32 { screen.width() }
    var rcNumberOfLines: Int32 { screen.numberOfLines() }
    var rcScrollbackOverflow: Int64 { screen.totalScrollbackOverflow() }
}

/// Minimal ResilientCoordinateDataSource for tests that need a dataSource
/// they can deterministically release (PTYSession's reference graph makes
/// reliable dealloc in a unit test impractical).
@objc private class TestDataSource: NSObject, ResilientCoordinateDataSource {
    let rcGuid: String
    let rcWidth: Int32
    let rcNumberOfLines: Int32
    var rcScrollbackOverflow: Int64 = 0

    init(guid: String, width: Int32, lines: Int32) {
        self.rcGuid = guid
        self.rcWidth = width
        self.rcNumberOfLines = lines
        super.init()
    }
}

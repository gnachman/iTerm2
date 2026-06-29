//
//  CurrentCommandSubSelectionsTests.swift
//  iTerm2
//
//  Direct tests for
//  iTermSubSelection.subSelections(in:excluding:width:) (Swift extension).
//  Verifies the disjoint-clipping logic that "Select Current Command" uses
//  to subtract PS2 prefix cells and right-prompt cells from the selection
//  without dragging them into the clipboard. The helper itself is generic
//  — it knows nothing about "command ranges".
//

import XCTest
@testable import iTerm2SharedARC

final class CurrentCommandSubSelectionsTests: XCTestCase {

    private let width: Int32 = 80

    /// Build a resilient excluded subrange against a fake data source so it
    /// reports .valid status without needing a real screen.
    private func excluded(_ ds: FakeRCSelectionDataSource,
                          _ sx: Int, _ sy: Int, _ ex: Int, _ ey: Int) -> ResilientCoordinateRange {
        return ResilientCoordinateRange(dataSource: ds,
                                        absRange: VT100GridAbsCoordRangeMake(Int32(sx), Int64(sy),
                                                                             Int32(ex), Int64(ey)))
    }

    private func range(_ sx: Int, _ sy: Int, _ ex: Int, _ ey: Int) -> VT100GridAbsCoordRange {
        return VT100GridAbsCoordRangeMake(Int32(sx), Int64(sy), Int32(ex), Int64(ey))
    }

    private func absRanges(_ subs: [iTermSubSelection]) -> [VT100GridAbsCoordRange] {
        return subs.map { $0.absRange.coordRange }
    }

    // MARK: - Trivial paths

    func test_invalidOuterRange_returnsEmpty() {
        let invalid = VT100GridAbsCoordRangeMake(-1, -1, -1, -1)
        let subs = iTermSubSelection.subSelections(in: invalid,
                                                   excluding: nil,
                                                   width: width)
        XCTAssertEqual(subs.count, 0)
    }

    func test_noExclusions_returnsOneSubCoveringOuter() {
        let outer = range(0, 5, 10, 5)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: nil,
                                                   width: width)
        XCTAssertEqual(subs.count, 1)
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(subs[0].absRange.coordRange, outer))
    }

    func test_emptyExclusionsArray_isNoOp() {
        let outer = range(0, 5, 10, 5)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [],
                                                   width: width)
        XCTAssertEqual(subs.count, 1)
    }

    func test_singleExclusionMidRange_yieldsTwoSubs() {
        let ds = FakeRCSelectionDataSource()
        let outer = range(0, 0, 10, 0)
        let ex = excluded(ds, 4, 0, 7, 0)  // exclude cols 4..7
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [ex],
                                                   width: width)
        let ranges = absRanges(subs)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[0], range(0, 0, 4, 0)))
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[1], range(7, 0, 10, 0)))
    }

    func test_exclusionCoversEntireOuter_returnsEmpty() {
        let ds = FakeRCSelectionDataSource()
        let outer = range(2, 0, 8, 0)
        // Keep both endpoints inside the data source's rcWidth (80) so the
        // RC's status reports .valid; ResilientCoordinate treats x == width
        // as out-of-bounds.
        let ex = excluded(ds, 0, 0, 10, 0)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [ex],
                                                   width: width)
        XCTAssertEqual(subs.count, 0)
    }

    // MARK: - Boundary handling

    func test_exclusionAtOuterStart_clipsLeading() {
        let ds = FakeRCSelectionDataSource()
        let outer = range(2, 0, 10, 0)
        // Exclusion starts before outer.start (col 0 < col 2) and ends at col 5.
        let ex = excluded(ds, 0, 0, 5, 0)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [ex],
                                                   width: width)
        let ranges = absRanges(subs)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[0], range(5, 0, 10, 0)))
    }

    func test_exclusionAtOuterEnd_clipsTrailing() {
        let ds = FakeRCSelectionDataSource()
        let outer = range(0, 0, 10, 0)
        // Exclusion starts at col 7 and extends past outer.end (col 20).
        let ex = excluded(ds, 7, 0, 20, 0)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [ex],
                                                   width: width)
        let ranges = absRanges(subs)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[0], range(0, 0, 7, 0)))
    }

    func test_exclusionFullyOutsideOuter_isIgnored() {
        let ds = FakeRCSelectionDataSource()
        let outer = range(0, 5, 10, 5)
        let before = excluded(ds, 0, 0, 5, 0)
        let after = excluded(ds, 0, 9, 5, 9)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [before, after],
                                                   width: width)
        XCTAssertEqual(subs.count, 1)
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(subs[0].absRange.coordRange, outer))
    }

    // MARK: - Sorting + unresolved RCs

    func test_outOfOrderExclusions_sortedInternally() {
        let ds = FakeRCSelectionDataSource()
        let outer = range(0, 0, 20, 0)
        let later = excluded(ds, 12, 0, 14, 0)
        let earlier = excluded(ds, 4, 0, 6, 0)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [later, earlier],
                                                   width: width)
        let ranges = absRanges(subs)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[0], range(0, 0, 4, 0)))
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[1], range(6, 0, 12, 0)))
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[2], range(14, 0, 20, 0)))
    }

    func test_unresolvedExclusion_silentlySkipped() {
        let outer = range(0, 0, 10, 0)
        let unresolvedStart = ResilientCoordinate(unboundAbsCoord: VT100GridAbsCoordMake(2, 0))
        let unresolvedEnd = ResilientCoordinate(unboundAbsCoord: VT100GridAbsCoordMake(5, 0))
        let rc = ResilientCoordinateRange(start: unresolvedStart, end: unresolvedEnd)
        XCTAssertEqual(rc.start.status, .unresolved)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [rc],
                                                   width: width)
        XCTAssertEqual(subs.count, 1, "Unresolved RC must not clip anything")
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(subs[0].absRange.coordRange, outer))
    }

    // MARK: - Connected (inter-piece newline) flag

    func test_sameRowPieces_areConnected() {
        // Outer spans one row; an excluded subrange splits it in two.
        // The two subs share a row, so the first one must be `connected`
        // so the copied text gets no \n between them.
        let ds = FakeRCSelectionDataSource()
        let outer = range(0, 0, 20, 0)
        let ex = excluded(ds, 8, 0, 12, 0)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [ex],
                                                   width: width)
        XCTAssertEqual(subs.count, 2)
        XCTAssertTrue(subs[0].connected, "same-row sibling must be connected")
        XCTAssertFalse(subs[1].connected, "last sub never carries connected forward")
    }

    func test_rowSpanningPieces_areNotConnected() {
        // PS2 shape: outer spans two rows; exclusion is the PS2 prefix on
        // row 1. The two surviving subs cross the row boundary, so the
        // first must NOT be `connected` — the copied text needs a \n
        // between rows so it reproduces the user's typed input.
        let ds = FakeRCSelectionDataSource()
        let outer = range(0, 0, 4, 1)
        let ps2 = excluded(ds, 0, 1, 2, 1)
        let subs = iTermSubSelection.subSelections(in: outer,
                                                   excluding: [ps2],
                                                   width: width)
        let ranges = absRanges(subs)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[0], range(0, 0, 0, 1)),
                      "first piece spans row 0 entirely up to row-1 col-0")
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(ranges[1], range(2, 1, 4, 1)),
                      "second piece picks up after the PS2 prefix on row 1")
        XCTAssertFalse(subs[0].connected, "row-spanning siblings must NOT be connected")
    }
}

@objc private class FakeRCSelectionDataSource: NSObject, ResilientCoordinateDataSource {
    let rcGuid: String = "selection-test"
    let rcWidth: Int32 = 80
    let rcNumberOfLines: Int32 = 200
    var rcScrollbackOverflow: Int64 = 0
}

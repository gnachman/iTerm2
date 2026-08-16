//
//  iTermTabGroupOrderingTests.swift
//  iTerm2XCTests
//
//  The canonical tab order must satisfy the pinned-prefix invariant FIRST and
//  group contiguity second. The regression this pins down: pinning a tab used
//  to be undone by the contiguity repair, which compacted group runs with no
//  regard for pinning and left a pinned tab stranded right of unpinned ones.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabGroupOrderingTests: XCTestCase {

    private func canonical(_ groupIDs: [String?], _ pinned: [Bool]) -> [Int] {
        return iTermTabGroupOrdering.canonicalOrder(groupIDs: groupIDs, pinned: pinned)
    }

    // The pin-action scenario: tabs A(G, pinned), C(pinned), B(G, unpinned).
    // A naive group compaction yields [A, B, C], stranding pinned C after
    // unpinned B. The canonical order must keep the pinned prefix [A, C].
    func testPinnedPrefixBeatsGroupContiguity() {
        XCTAssertEqual(canonical(["G", nil, "G"], [true, true, false]), [0, 1, 2])
    }

    // With no pinning, a split group compacts to its first member's position.
    func testSplitGroupCompacts() {
        XCTAssertEqual(canonical([nil, "G", nil, "G"], [false, false, false, false]),
                       [0, 1, 3, 2])
    }

    // An already-valid order is untouched (identity permutation).
    func testValidOrderIsIdentity() {
        XCTAssertEqual(canonical(["G", "G", nil], [false, false, false]), [0, 1, 2])
        XCTAssertEqual(canonical([nil, nil], [true, false]), [0, 1])
    }

    // Unpinned tabs ahead of pinned ones get partitioned behind them, without
    // reordering within either class.
    func testStablePartition() {
        // U, P, U, P -> P(1), P(3), U(0), U(2)
        XCTAssertEqual(canonical([nil, nil, nil, nil], [false, true, false, true]),
                       [1, 3, 0, 2])
    }

    // Dropping an unpinned group at the front of a bar whose first tab is
    // pinned: the group slides in right after the pinned prefix.
    func testGroupDroppedBeforePinnedTabLandsAfterIt() {
        // G1, G2, P -> P, G1, G2
        XCTAssertEqual(canonical(["G", "G", nil], [false, false, true]), [2, 0, 1])
    }

    // A group with pinned and unpinned members spans the boundary as two runs;
    // no tab crosses the pinned boundary.
    func testMixedPinnedGroupSpansBoundary() {
        // P(plain), G(pinned), G(unpinned), U(plain)
        XCTAssertEqual(canonical([nil, "G", "G", nil], [true, true, false, false]),
                       [0, 1, 2, 3])
    }

    // Groups compact independently within the pinned and unpinned classes.
    func testCompactionWithinEachClass() {
        // Pinned: G, x, G (split) / Unpinned: H, y, H (split)
        // -> pinned [G G x] wait: anchored at first member: G(0), G(2), x(1)
        XCTAssertEqual(canonical(["G", nil, "G", "H", nil, "H"],
                                 [true, true, true, false, false, false]),
                       [0, 2, 1, 3, 5, 4])
    }

    // The canonical order is idempotent: applying it to an already-canonical
    // arrangement returns the identity.
    func testIdempotent() {
        let groupIDs: [String?] = ["G", nil, "G", "H", "H", nil]
        let pinned = [true, true, false, false, false, false]
        let once = canonical(groupIDs, pinned)
        let reorderedIDs = once.map { groupIDs[$0] }
        let reorderedPinned = once.map { pinned[$0] }
        XCTAssertEqual(canonical(reorderedIDs, reorderedPinned),
                       Array(0..<groupIDs.count))
    }

    // ObjC bridge round-trip with NSNull for ungrouped.
    func testObjCBridge() {
        let result = iTermTabGroupOrdering.canonicalOrder(
            groupIDs: ["G", NSNull(), "G"] as [Any],
            pinned: [true, true, false] as [NSNumber])
        XCTAssertEqual(result, [0, 1, 2])
    }

    // MARK: - Nearest tab outside a group (collapse move-out)

    private func nearestOutside(_ order: [String?], _ gid: String) -> Int? {
        return iTermTabGroupOrdering.indexOfNearestTabOutsideGroup(order: order, group: gid)
    }

    // A group in the middle: the tab right after the group's last member wins.
    func testNearestOutsideMiddlePicksAfter() {
        XCTAssertEqual(nearestOutside([nil, "G", "G", nil], "G"), 3)
    }

    // A group at the right edge: fall back to the tab before its first member.
    func testNearestOutsideRightEdgePicksBefore() {
        XCTAssertEqual(nearestOutside([nil, nil, "G", "G"], "G"), 1)
    }

    // A group that is the whole window: no tab outside it -> nil (refuse policy).
    func testNearestOutsideWholeWindowIsNil() {
        XCTAssertNil(nearestOutside(["G", "G", "G"], "G"))
    }

    // A one-tab group in the middle still finds the tab after it.
    func testNearestOutsideOneTabGroup() {
        XCTAssertEqual(nearestOutside([nil, "G", nil], "G"), 2)
    }

    // A one-tab group that is the whole window is nil.
    func testNearestOutsideOneTabWholeWindowIsNil() {
        XCTAssertNil(nearestOutside(["G"], "G"))
    }

    // Unknown group id -> nil.
    func testNearestOutsideUnknownGroupIsNil() {
        XCTAssertNil(nearestOutside([nil, "G", nil], "H"))
    }

    // ObjC bridge for the nearest-outside helper (NSNull for ungrouped).
    func testNearestOutsideObjCBridge() {
        XCTAssertEqual(
            iTermTabGroupOrdering.indexOfNearestTabOutsideGroup(
                order: [NSNull(), "G", "G", NSNull()] as [Any],
                collapsed: [false, false, false, false].map { NSNumber(value: $0) },
                group: "G"),
            NSNumber(value: 3))
        XCTAssertNil(
            iTermTabGroupOrdering.indexOfNearestTabOutsideGroup(
                order: ["G", "G"] as [Any],
                collapsed: [false, false].map { NSNumber(value: $0) },
                group: "G"))
    }

    // Collapsing a group must land on the nearest VISIBLE tab, skipping hidden
    // members of another collapsed group (selecting one would auto-expand it and
    // steal focus).
    private func nearestOutsideCollapsed(_ order: [String?], _ collapsed: [Bool], _ gid: String) -> Int? {
        return iTermTabGroupOrdering.indexOfNearestTabOutsideGroup(order: order, collapsed: collapsed, group: gid)
    }

    func testNearestOutsideSkipsCollapsedNeighborAfter() {
        // [G, G, H, H, nil] with H collapsed: skip H1/H2, land on the visible tab.
        XCTAssertEqual(
            nearestOutsideCollapsed(["G", "G", "H", "H", nil],
                                    [false, false, true, true, false], "G"),
            4)
    }

    func testNearestOutsideSkipsCollapsedNeighborBefore() {
        // Group at the right edge; the tabs before it are a collapsed group, so
        // skip them and land on the visible tab at 0.
        XCTAssertEqual(
            nearestOutsideCollapsed([nil, "H", "H", "G", "G"],
                                    [false, true, true, false, false], "G"),
            0)
    }

    func testNearestOutsideAllNeighborsHiddenIsNil() {
        // Only other tabs are a collapsed group -> nothing visible outside -> nil.
        XCTAssertNil(
            nearestOutsideCollapsed(["G", "G", "H", "H"],
                                    [false, false, true, true], "G"))
    }

    // With no collapsed neighbors the behavior is unchanged (default all-visible).
    func testNearestOutsideCollapsedFlagsAllFalseMatchesPlain() {
        XCTAssertEqual(
            nearestOutsideCollapsed([nil, "G", "G", nil], [false, false, false, false], "G"),
            3)
    }

    // A group whose members straddle a non-member (non-contiguous, e.g. it spans
    // the pinned boundary): the tab in the gap is a valid landing spot and must be
    // found, not refused. Members at 0 and 2, gap tab at 1.
    func testNearestOutsideStraddlingGroupPicksGapTab() {
        XCTAssertEqual(nearestOutside(["G", nil, "G"], "G"), 1)
    }

    // A wide straddle with only gap tabs between the members: the old outward-only
    // scan returned nil here (refusing collapse); now it lands on the nearest gap
    // tab. Members at 0 and 4; gap tabs 1,2,3 -> nearest are 1 and 3 (distance 1),
    // prefer-after picks 3.
    func testNearestOutsideWideStraddleFindsGapTab() {
        XCTAssertEqual(nearestOutside(["G", nil, nil, nil, "G"], "G"), 3)
    }

    // MARK: - Invariant predicate

    private func invariantHolds(_ groupIDs: [String?], _ collapsed: [Bool], _ active: Int) -> Bool {
        return iTermTabGroupOrdering.activeTabNotInCollapsedGroup(
            groupIDs: groupIDs, collapsed: collapsed, activeIndex: active)
    }

    func testInvariantActiveInCollapsedGroupViolates() {
        XCTAssertFalse(invariantHolds([nil, "G", "G"], [false, true, true], 1))
    }

    func testInvariantActiveOutsideCollapsedGroupHolds() {
        XCTAssertTrue(invariantHolds([nil, "G", "G"], [false, true, true], 0))
    }

    func testInvariantActiveInExpandedGroupHolds() {
        XCTAssertTrue(invariantHolds(["G", "G"], [false, false], 0))
    }

    func testInvariantUngroupedActiveHolds() {
        XCTAssertTrue(invariantHolds([nil, nil], [false, false], 1))
    }
}

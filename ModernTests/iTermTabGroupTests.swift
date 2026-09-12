//
//  iTermTabGroupTests.swift
//  iTerm2XCTests
//
//  Created by George Nachman on 8/7/26.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabGroupTests: XCTestCase {
    // MARK: - Dropped-tab membership (resolve from landing position)

    private func resolve(_ index: Int, _ order: [String?]) -> String? {
        return iTermTabGroupContiguity.resolvedGroup(forTabAt: index, order: order)
    }

    func testDropInsideRunJoins() {
        // Ungrouped tab dropped between two A tabs joins A.
        XCTAssertEqual(resolve(1, ["A", nil, "A"]), "A")
    }

    func testDropInsideRunFromAnotherGroupJoins() {
        // A B-group tab dropped strictly inside A's run joins A (leaves B).
        XCTAssertEqual(resolve(1, ["A", "B", "A"]), "A")
    }

    func testMemberDraggedToEdgeLeaves() {
        // George's case: E (member of a 3-tab group) dropped before the run's
        // first tab is at the edge, not strictly inside -> leaves the group.
        // order after drop: [C(nil), E(A), D(A), F(A)], E is index 1.
        XCTAssertNil(resolve(1, [nil, "A", "A", "A"]))
    }

    func testMemberDraggedToEndLeaves() {
        XCTAssertNil(resolve(4, ["A", "A", nil, nil, "A"]))
    }

    func testBystanderIsNeverAbsorbed() {
        // Only the dropped tab is resolved; C at index 1 here is not the dropped
        // tab, and resolving the dropped tab (E at index 0) must not pull C in.
        // [E(A), C(nil), D(A), F(A)] with E just dropped at index 0.
        XCTAssertNil(resolve(0, ["A", nil, "A", "A"]))
    }

    func testDraggingSoleMemberOutDissolvesGroup() {
        // Dragging a one-tab group's sole member somewhere that is not inside
        // another group dissolves the group. (An in-place drop keeps it, but
        // that is signalled by the drop landing on the tab's own gid-carrying
        // slot, not by this order rule.)
        XCTAssertNil(resolve(1, [nil, "A", nil]))
    }

    func testDropAtGroupFrontEdgeLeaves() {
        // Between two different groups (not inside either run): ungrouped.
        XCTAssertNil(resolve(1, ["A", nil, "B"]))
    }

    func testDropWithNoNeighborsUngrouped() {
        XCTAssertNil(resolve(0, [nil]))
        XCTAssertNil(resolve(0, ["A"]))  // dragged out alone: group dissolves
    }

    func testObjCBridgeResolves() {
        let out = iTermTabGroupContiguity.resolvedGroup(forTabAt: 1, order: ["A", NSNull(), "A"])
        XCTAssertEqual(out, "A")
        XCTAssertNil(iTermTabGroupContiguity.resolvedGroup(forTabAt: 0, order: [NSNull(), "A", "A"]))
    }

    // MARK: - iTermTabGroup value type

    // The group definition (id/name/color) now rides the member tabs and there
    // is no registry or per-group arrangement; iTermTabGroup is just the value
    // the window controller builds on demand to answer the tab bar. Persistence
    // is covered end to end at the PTYTab-arrangement level.
    func testValueTypeHoldsIdentifierNameAndColor() {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
        let group = iTermTabGroup(uniqueIdentifier: "grp-1", name: "phpvms", color: color)
        XCTAssertEqual(group.uniqueIdentifier, "grp-1")
        XCTAssertEqual(group.name, "phpvms")
        XCTAssertEqual(group.color.dictionaryValue as NSDictionary,
                       color.dictionaryValue as NSDictionary)
    }

    // MARK: - Scriptable-API invariants
    //
    // The API's create/assign/remove operations (PseudoTerminal
    // -createTabGroupWithTabs:name:color:, -addTab:toExistingTabGroupWithID:,
    // -removeTabFromItsGroup:) all mutate a tab's gid and then repair layout
    // through -tabsDidReorder, i.e. iTermTabGroupOrdering.canonicalOrder. These
    // pin the layer the API depends on: whatever tabs the API stamps with a gid,
    // the reorder pass must gather into one contiguous block, and removing a
    // member must leave the rest contiguous.

    private func order(_ groupIDs: [String?], pinned: [Bool]? = nil) -> [Int] {
        return iTermTabGroupOrdering.canonicalOrder(
            groupIDs: groupIDs,
            pinned: pinned ?? Array(repeating: false, count: groupIDs.count))
    }

    func testApiCreateFromScatteredTabsCompactsIntoOneBlock() {
        // create(tabs: [t0, t2, t4]) stamps gid "G" on the scattered members;
        // the reorder pass must pull them together into one run anchored at the
        // first member, leaving the ungrouped tabs otherwise in place.
        let result = order(["G", nil, "G", nil, "G"])
        XCTAssertEqual(result, [0, 2, 4, 1, 3])
    }

    func testApiCreateSingleTabGroupIsNoMove() {
        // A one-tab group (create with a single tab) is already contiguous.
        XCTAssertEqual(order([nil, "G", nil]), [0, 1, 2])
    }

    func testApiRemoveMiddleMemberLeavesRemainderContiguous() {
        // removeTabFromItsGroup: clears the middle member's gid (index 1 -> nil).
        // The reorder pass must keep the two remaining members adjacent and let
        // the now-ungrouped tab fall after the block.
        let result = order(["G", nil, "G"])
        XCTAssertEqual(result, [0, 2, 1])
    }

    func testApiAssignScatteredTabJoinsGroupBlock() {
        // assign(tab: t3, to: "G") stamps gid "G" on a far tab; the reorder pass
        // must fold it into G's existing block rather than leave it stranded.
        let result = order(["G", "G", nil, "G"])
        XCTAssertEqual(result, [0, 1, 3, 2])
    }

    func testApiCollapseFindsLandingSpotOutsideGroup() {
        // Collapsing a group that holds the active tab must first move selection
        // to a visible tab outside the group. With an ungrouped tab present,
        // there is a landing spot (so collapse is allowed, not COLLAPSE_IMPOSSIBLE).
        let landing = iTermTabGroupOrdering.indexOfNearestTabOutsideGroup(
            order: ["G", "G", nil], group: "G")
        XCTAssertEqual(landing, 2)
    }

    func testApiCollapseWholeWindowHasNoLandingSpot() {
        // A group that is the whole window has nowhere to move selection, so the
        // API returns COLLAPSE_IMPOSSIBLE. That maps to no tab outside the group.
        let landing = iTermTabGroupOrdering.indexOfNearestTabOutsideGroup(
            order: ["G", "G", "G"], group: "G")
        XCTAssertNil(landing)
    }
}

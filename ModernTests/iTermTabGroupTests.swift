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
}

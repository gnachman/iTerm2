//
//  PSMTabGroupDropResolutionTests.swift
//  iTerm2XCTests
//
//  Drop-membership resolution and mid-drag slot layout. The subtle case: the
//  dragged cell's own drop slot is a placeholder that carries the dragged
//  tab's group id (to keep the chip anchored). Dropping back onto it must
//  keep the tab's membership (a no-move drop changes nothing), and the slot
//  itself must not sprout a second, conflicting “join group” end slot.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupDropResolutionTests: XCTestCase {
    private var control: PSMTabBarControl!
    private var assistant: PSMTabDragAssistant!

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        assistant = PSMTabDragAssistant.shared()
    }

    override func tearDown() {
        // Do not leak drag state (dragged/target cells) into other tests.
        assistant.finishDrag()
        assistant = nil
        control = nil
        super.tearDown()
    }

    private func tabCell(_ groupID: String?) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        return cell
    }

    private func chipCell(_ groupID: String) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isTabGroupChip = true
        cell.tabGroupIdentifier = groupID
        return cell
    }

    private func placeholder(gid: String? = nil, joins: String? = nil) -> PSMTabBarCell {
        let cell = PSMTabBarCell(placeholderWithFrame: NSRect(x: 0, y: 0, width: 0, height: 24),
                                 expanded: false,
                                 inControlView: control)!
        cell.tabGroupIdentifier = gid
        cell.joinsTabGroupIdentifier = joins
        return cell
    }

    // MARK: - groupContainingDropOfCell

    // Dropping a group's LAST member back onto its own slot (a no-move drop)
    // must keep it in the group. The bracket test alone would look at the
    // ungrouped right neighbor and eject it.
    func testNoMoveDropOfLastMemberKeepsMembership() {
        let dragged = tabCell("A")
        let ownSlot = placeholder(gid: "A")
        // Mid-drag bar: [chip A][member A][own slot (gid A)][loner]
        control.cells().setArray([chipCell("A"), tabCell("A"), ownSlot, tabCell(nil)])
        assistant.setDraggedCell(dragged)
        assistant.setTargetCell(ownSlot)
        XCTAssertEqual(assistant.groupContainingDrop(of: dragged, inTabBar: control), "A")
    }

    // Dropping the member on the ordinary slot past the loner really does
    // leave the group.
    func testDropPastUngroupedNeighborLeavesGroup() {
        let dragged = tabCell("A")
        let farSlot = placeholder()
        control.cells().setArray([chipCell("A"), tabCell("A"), tabCell(nil), farSlot])
        assistant.setDraggedCell(dragged)
        assistant.setTargetCell(farSlot)
        XCTAssertNil(assistant.groupContainingDrop(of: dragged, inTabBar: control))
    }

    // An explicit “join group” end slot still joins.
    func testJoinSlotJoinsGroup() {
        let dragged = tabCell(nil)
        let joinSlot = placeholder(joins: "B")
        control.cells().setArray([chipCell("B"), tabCell("B"), joinSlot, tabCell(nil)])
        assistant.setDraggedCell(dragged)
        assistant.setTargetCell(joinSlot)
        XCTAssertEqual(assistant.groupContainingDrop(of: dragged, inTabBar: control), "B")
    }

    // A drop between two members stays inside the group (bracket test).
    func testDropBetweenMembersJoins() {
        let dragged = tabCell(nil)
        let between = placeholder()
        control.cells().setArray([chipCell("A"), tabCell("A"), between, tabCell("A")])
        assistant.setDraggedCell(dragged)
        assistant.setTargetCell(between)
        XCTAssertEqual(assistant.groupContainingDrop(of: dragged, inTabBar: control), "A")
    }

    // MARK: - reinsertDragChipsInTabBar slot layout

    // While dragging the last member of a group, its gid-carrying drop slot
    // must NOT be treated as a member: exactly one “join group” end slot per
    // run, not one per member plus one per placeholder.
    func testSingleJoinSlotWhenDraggingLastMember() {
        // Chips-stripped, placeholder-laden state for dragging m2 out of
        // G = [m1, m2] with an ungrouped loner after:
        // [ph][m1 A][ph][own slot (gid A)][ph][loner][ph]
        let ownSlot = placeholder(gid: "A")
        control.cells().setArray([placeholder(), tabCell("A"), placeholder(), ownSlot,
                                  placeholder(), tabCell(nil), placeholder()])
        assistant.reinsertDragChips(inTabBar: control)
        let joinSlots = (control.cells() as! [PSMTabBarCell]).filter {
            ($0.joinsTabGroupIdentifier ?? "").isEmpty == false
        }
        XCTAssertEqual(joinSlots.count, 1,
                       "one join slot per group run; the dragged tab's own slot must not sprout another")
    }
}

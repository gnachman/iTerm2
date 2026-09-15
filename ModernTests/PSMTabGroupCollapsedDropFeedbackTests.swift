//
//  PSMTabGroupCollapsedDropFeedbackTests.swift
//  iTerm2XCTests
//
//  Drag feedback for dropping a tab into a COLLAPSED group. A collapsed group
//  draws no member cells, so the usual "a drop slot opens a gap" affordance is
//  invisible and, worse, an ordinary slot opening just past the pill reads as
//  "drop beside the group." The fix marks the collapsed group's front/end join
//  slots as `isCollapsedGroupJoinSlot`: the drag animation keeps them closed (no
//  misleading gap) and the group's chip is highlighted as the drop target
//  instead. These tests lock in the marking and the "stays closed" behavior.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupCollapsedDropFeedbackTests: XCTestCase {
    private var control: PSMTabBarControl!
    private var assistant: PSMTabDragAssistant!

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        assistant = PSMTabDragAssistant.shared()
    }

    override func tearDown() {
        assistant.finishDrag()
        assistant = nil
        control = nil
        super.tearDown()
    }

    private func tabCell(_ groupID: String?, collapsed: Bool = false) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        cell.isCollapsedHidden = collapsed
        return cell
    }

    private func placeholder() -> PSMTabBarCell {
        return PSMTabBarCell(placeholderWithFrame: NSRect(x: 0, y: 0, width: 0, height: 24),
                             expanded: false,
                             inControlView: control)!
    }

    // The cell immediately after a re-inserted chip is that group's front-of-group
    // drop slot. For a COLLAPSED group it must be flagged as a collapsed join slot
    // and carry the group id, so the animation keeps it closed and the drop still
    // resolves to a join.
    func testCollapsedGroupFrontSlotIsMarkedAsCollapsedJoinSlot() {
        // Chips-stripped, placeholder-laden mid-drag layout: group A = [m0, m1]
        // both collapsed, then a loner (the tab being dragged in from elsewhere).
        control.cells().setArray([placeholder(),
                                  tabCell("A", collapsed: true), placeholder(),
                                  tabCell("A", collapsed: true), placeholder(),
                                  tabCell(nil), placeholder()])
        assistant.reinsertDragChips(inTabBar: control)

        let cells = control.cells() as! [PSMTabBarCell]
        guard let chipIndex = cells.firstIndex(where: { $0.isTabGroupChip }) else {
            XCTFail("no chip was re-inserted for the group")
            return
        }
        let frontSlot = cells[chipIndex + 1]
        XCTAssertTrue(frontSlot.isPlaceholder, "the cell after the chip must be the front-of-group slot")
        XCTAssertTrue(frontSlot.isCollapsedGroupJoinSlot,
                      "a collapsed group's front slot must be marked so the chip-hover logic detects the group")
        // The mark is only a detector: the join comes from hovering the pill, not
        // from this slot, so it must NOT carry a join id (otherwise the slot that
        // opens once you advance past the pill would join with no highlight).
        XCTAssertNil(frontSlot.joinsTabGroupIdentifier,
                     "the collapsed front slot must not itself be a join slot")
    }

    // An EXPANDED group's front slot must NOT be marked: it opens a real gap (the
    // normal join-at-front affordance) since its members are visible.
    func testExpandedGroupFrontSlotIsNotMarked() {
        control.cells().setArray([placeholder(),
                                  tabCell("A"), placeholder(),
                                  tabCell("A"), placeholder(),
                                  tabCell(nil), placeholder()])
        assistant.reinsertDragChips(inTabBar: control)

        let cells = control.cells() as! [PSMTabBarCell]
        guard let chipIndex = cells.firstIndex(where: { $0.isTabGroupChip }) else {
            XCTFail("no chip was re-inserted for the group")
            return
        }
        XCTAssertTrue(cells[chipIndex + 1].isPlaceholder)
        XCTAssertFalse(cells[chipIndex + 1].isCollapsedGroupJoinSlot,
                       "an expanded group's front slot must open a gap, so it is not a collapsed join slot")
        XCTAssertTrue((control.cells() as! [PSMTabBarCell]).allSatisfy { !$0.isCollapsedGroupJoinSlot })
    }
}

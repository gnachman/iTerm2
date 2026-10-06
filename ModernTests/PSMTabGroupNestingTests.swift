//
//  PSMTabGroupNestingTests.swift
//  ModernTests
//
//  The tab bar side of nested tab groups (one level deep): a sub-group gets its
//  own chip inside its parent's run, the parent's run spans the sub-group, each
//  level collapses on its own, and a drop joins the deepest group it lands in.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupNestingTests: XCTestCase {
    private var control: PSMTabBarControl!
    private var assistant: PSMTabDragAssistant!
    private var items: [NSTabViewItem] = []

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        assistant = PSMTabDragAssistant.shared()
        items = []
    }

    override func tearDown() {
        assistant.finishDrag()
        assistant = nil
        control = nil
        items = []
        super.tearDown()
    }

    // A tab cell in `groupID`, which is a sub-group of `parent` when given.
    private func tabCell(_ groupID: String?, parent: String? = nil, label: String = "Tab") -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        cell.tabGroupParentIdentifier = parent
        let item = NSTabViewItem(identifier: label as NSString)
        item.label = label
        items.append(item)
        cell.representedObject = item
        return cell
    }

    private func chipCell(_ groupID: String, parent: String? = nil) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isTabGroupChip = true
        cell.tabGroupIdentifier = groupID
        cell.tabGroupParentIdentifier = parent
        return cell
    }

    private func placeholder() -> PSMTabBarCell {
        return PSMTabBarCell(placeholderWithFrame: NSRect(x: 0, y: 0, width: 0, height: 24),
                             expanded: false,
                             inControlView: control)!
    }

    // "-" ungrouped tab, "P" a tab in P, "P/C" a tab in sub-group C of P,
    // "chip:P" / "chip:P/C" chips, "ph" a placeholder.
    private func tokens(_ cells: [PSMTabBarCell]) -> [String] {
        return cells.map { cell in
            if cell.isPlaceholder {
                return "ph"
            }
            var name = cell.tabGroupIdentifier ?? "-"
            if let parent = cell.tabGroupParentIdentifier {
                name = "\(parent)/\(name)"
            }
            return cell.isTabGroupChip ? "chip:\(name)" : name
        }
    }

    private func normalized(_ cells: [PSMTabBarCell]) -> [String] {
        return tokens(PSMTabBarControl.cellsByInsertingTabGroupChips(into: cells, controlView: control))
    }

    // MARK: - Chips

    func testSubgroupGetsChipInsideParentRun() {
        XCTAssertEqual(normalized([tabCell("P"), tabCell("C", parent: "P"), tabCell("C", parent: "P"),
                                   tabCell("P"), tabCell(nil)]),
                       ["chip:P", "P", "chip:P/C", "P/C", "P/C", "P", "-"])
    }

    // A parent whose tabs are all in sub-groups still gets its chip, first.
    func testParentWithoutDirectMembersGetsChip() {
        XCTAssertEqual(normalized([tabCell("C", parent: "P"), tabCell("D", parent: "P")]),
                       ["chip:P", "chip:P/C", "P/C", "chip:P/D", "P/D"])
    }

    // Leaving a sub-group back into the parent continues the parent's run
    // without a second parent chip.
    func testReturningToParentAddsNoChip() {
        let out = normalized([tabCell("C", parent: "P"), tabCell("P"), tabCell("P")])
        XCTAssertEqual(out.filter { $0 == "chip:P" }.count, 1)
        XCTAssertEqual(out, ["chip:P", "chip:P/C", "P/C", "P", "P"])
    }

    // A sub-group's chip is hidden when its parent is collapsed.
    func testSubgroupChipHiddenWhenParentCollapsed() {
        let member = tabCell("C", parent: "P")
        member.isCollapsedHidden = true
        member.isTabGroupParentCollapsed = true
        let out = PSMTabBarControl.cellsByInsertingTabGroupChips(into: [member], controlView: control)
        XCTAssertEqual(tokens(out), ["chip:P", "chip:P/C", "P/C"])
        XCTAssertFalse(out[0].isCollapsedHidden)
        XCTAssertTrue(out[1].isCollapsedHidden)
    }

    // MARK: - Push

    // Parent identifiers pushed alongside membership re-derive the chips.
    func testParentIdentifiersPushDerivesSubgroupChip() {
        let a = tabCell(nil, label: "a")
        let b = tabCell(nil, label: "b")
        control.cells().setArray([a, b])
        control.setTabGroupIdentifiers(["P", "C"], parentIdentifiers: [NSNull(), "P"], for: items)
        XCTAssertEqual(tokens(control.cells() as! [PSMTabBarCell]), ["chip:P", "P", "chip:P/C", "P/C"])
    }

    // Collapsing the parent hides the sub-group's chip; expanding shows it.
    func testParentCollapseFlagsHideSubgroupChip() {
        control.cells().setArray([tabCell("P", label: "p"), tabCell("C", parent: "P", label: "c")])
        control.normalizeTabGroupChipCells()
        control.setTabGroupCollapsedFlags([true, true], parentCollapsedFlags: [false, true], for: items)
        let chip = (control.cells() as! [PSMTabBarCell]).first { $0.isTabGroupChip && $0.tabGroupIdentifier == "C" }!
        XCTAssertTrue(chip.isCollapsedHidden)
        control.setTabGroupCollapsedFlags([false, false], parentCollapsedFlags: [false, false], for: items)
        XCTAssertFalse(chip.isCollapsedHidden)
    }

    // MARK: - Runs

    func testParentRunSpansSubgroup() {
        let chipP = chipCell("P")
        chipP.frame = NSRect(x: 0, y: 0, width: 40, height: 24)
        let p1 = tabCell("P", label: "p1")
        p1.frame = NSRect(x: 40, y: 0, width: 100, height: 24)
        let chipC = chipCell("C", parent: "P")
        chipC.frame = NSRect(x: 140, y: 0, width: 40, height: 24)
        let c1 = tabCell("C", parent: "P", label: "c1")
        c1.frame = NSRect(x: 180, y: 0, width: 100, height: 24)
        let loner = tabCell(nil, label: "loner")
        loner.frame = NSRect(x: 280, y: 0, width: 100, height: 24)
        control.cells().setArray([chipP, p1, chipC, c1, loner])

        var runs: [String: NSRect] = [:]
        control.enumerateTabGroupRuns(rectForCell: nil) { _, rect, _, gid in
            runs[gid] = rect
        }
        XCTAssertEqual(runs["P"]?.minX, 40)
        XCTAssertEqual(runs["P"]?.maxX, 280, "the parent's run must enclose its sub-group")
        XCTAssertEqual(runs["C"]?.minX, 180)
        XCTAssertEqual(runs["C"]?.maxX, 280)
    }

    // Each level collapses on its own: a collapsed sub-group inside an expanded
    // parent shows its own collapsed chip, not the parent's.
    func testCollapsedSubgroupInsideExpandedParent() {
        let c1 = tabCell("C", parent: "P", label: "c1")
        c1.isCollapsedHidden = true
        control.cells().setArray([chipCell("P"), tabCell("P", label: "p1"), chipCell("C", parent: "P"), c1])
        var collapsed: [String: Int] = [:]
        control.enumerateCollapsedTabGroupChips { _, count, gid in
            collapsed[gid] = count
        }
        XCTAssertEqual(collapsed, ["C": 1])
    }

    // A collapsed parent shows one collapsed chip counting every tab inside it.
    func testCollapsedParentCountsSubgroupTabs() {
        let p1 = tabCell("P", label: "p1")
        p1.isCollapsedHidden = true
        let c1 = tabCell("C", parent: "P", label: "c1")
        c1.isCollapsedHidden = true
        c1.isTabGroupParentCollapsed = true
        let chipC = chipCell("C", parent: "P")
        chipC.isCollapsedHidden = true
        control.cells().setArray([chipCell("P"), p1, chipC, c1, tabCell(nil, label: "loner")])
        var collapsed: [String: Int] = [:]
        control.enumerateCollapsedTabGroupChips { _, count, gid in
            collapsed[gid] = count
        }
        XCTAssertEqual(collapsed, ["P": 2])
    }

    // MARK: - Drops

    private func dropGroup(_ cells: [PSMTabBarCell], target: PSMTabBarCell) -> String? {
        let dragged = tabCell(nil, label: "dragged")
        control.cells().setArray(cells)
        assistant.setDraggedCell(dragged)
        assistant.setTargetCell(target)
        return assistant.groupContainingDrop(of: dragged, inTabBar: control)
    }

    func testDropBetweenSubgroupMembersJoinsSubgroup() {
        let slot = placeholder()
        XCTAssertEqual(dropGroup([chipCell("P"), chipCell("C", parent: "P"), tabCell("C", parent: "P"),
                                  slot, tabCell("C", parent: "P")], target: slot), "C")
    }

    // Just before a sub-group's chip, after a direct member: inside the parent.
    func testDropBeforeSubgroupChipJoinsParent() {
        let slot = placeholder()
        XCTAssertEqual(dropGroup([chipCell("P"), tabCell("P"), slot, chipCell("C", parent: "P"),
                                  tabCell("C", parent: "P")], target: slot), "P")
    }

    // Between the parent's chip and its leading sub-group's chip: the parent.
    func testDropBetweenParentChipAndSubgroupChipJoinsParent() {
        let slot = placeholder()
        XCTAssertEqual(dropGroup([chipCell("P"), slot, chipCell("C", parent: "P"),
                                  tabCell("C", parent: "P")], target: slot), "P")
    }

    // After the sub-group, before a direct member: the parent.
    func testDropAfterSubgroupBeforeParentMemberJoinsParent() {
        let slot = placeholder()
        XCTAssertEqual(dropGroup([chipCell("P"), chipCell("C", parent: "P"), tabCell("C", parent: "P"),
                                  slot, tabCell("P")], target: slot), "P")
    }

    // Before a top-level chip: outside every group.
    func testDropBeforeTopLevelChipLeaves() {
        let slot = placeholder()
        XCTAssertNil(dropGroup([tabCell(nil), slot, chipCell("P"), tabCell("P")], target: slot))
    }
}

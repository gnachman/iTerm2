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

    // MARK: - Whole-group drops

    private func groupDropParent(_ cells: [PSMTabBarCell], target: PSMTabBarCell) -> String? {
        return assistant.parentGroupForGroupDrop(at: target, in: cells, excluding: [])
    }

    func testGroupDropBetweenMembersNestsInGroup() {
        let slot = placeholder()
        XCTAssertEqual(groupDropParent([chipCell("P"), tabCell("P"), slot, tabCell("P")], target: slot), "P")
    }

    func testGroupDropRightAfterChipNestsInGroup() {
        let slot = placeholder()
        XCTAssertEqual(groupDropParent([chipCell("P"), slot, tabCell("P")], target: slot), "P")
    }

    func testGroupDropInsideSubgroupNestsInItsParent() {
        let slot = placeholder()
        XCTAssertEqual(groupDropParent([chipCell("P"), chipCell("C", parent: "P"), tabCell("C", parent: "P"),
                                        slot, tabCell("C", parent: "P")], target: slot), "P")
    }

    func testGroupDropAfterLastMemberIsTopLevel() {
        let slot = placeholder()
        XCTAssertNil(groupDropParent([chipCell("P"), tabCell("P"), slot, tabCell(nil)], target: slot))
    }

    func testGroupDropOnEndSlotNestsInGroup() {
        let slot = placeholder()
        slot.joinsTabGroupIdentifier = "P"
        XCTAssertEqual(groupDropParent([chipCell("P"), tabCell("P"), slot, placeholder(), tabCell(nil)],
                                       target: slot), "P")
    }

    func testLastMemberEndsTopLevelRun() {
        let cells = [chipCell("P"), tabCell("P"), tabCell("P"), placeholder(), tabCell(nil)]
        XCTAssertNil(assistant.topLevelTabGroupEndingRun(at: 1, in: cells))
        XCTAssertEqual(assistant.topLevelTabGroupEndingRun(at: 2, in: cells), "P")
        XCTAssertNil(assistant.topLevelTabGroupEndingRun(at: 4, in: cells))
    }

    func testSubgroupTabEndingParentRunEndsParent() {
        let cells = [chipCell("P"), tabCell("P"), chipCell("C", parent: "P"), tabCell("C", parent: "P")]
        XCTAssertNil(assistant.topLevelTabGroupEndingRun(at: 1, in: cells))
        XCTAssertEqual(assistant.topLevelTabGroupEndingRun(at: 3, in: cells), "P")
    }

    func testCollapsedGroupHasNoEndSlot() {
        let member = tabCell("P")
        member.isCollapsedHidden = true
        XCTAssertNil(assistant.topLevelTabGroupEndingRun(at: 1, in: [chipCell("P"), member]))
    }

    private func slot(x: CGFloat, width: CGFloat, joins: String? = nil, joinsParent: String? = nil) -> PSMTabBarCell {
        let cell = PSMTabBarCell(placeholderWithFrame: NSRect(x: x, y: 0, width: width, height: 24),
                                 expanded: false,
                                 inControlView: control)!
        // A collapsed placeholder starts with no width; give it the open one.
        cell.frame = NSRect(x: x, y: 0, width: width, height: 24)
        cell.joinsTabGroupIdentifier = joins
        cell.joinsTabGroupParentIdentifier = joinsParent
        return cell
    }

    // The end of sub-group C, which also ends P: join C, join P, or leave.
    func testGapAtEndOfSubgroupAndParentHasThreeZones() {
        let joinC = slot(x: 100, width: 90, joins: "C", joinsParent: "P")
        let joinP = slot(x: 190, width: 0, joins: "P")
        let after = slot(x: 190, width: 0)
        let cells = [chipCell("P"), chipCell("C", parent: "P"), tabCell("C", parent: "P"),
                     joinC, joinP, after, tabCell(nil)]
        func pick(_ x: CGFloat) -> PSMTabBarCell {
            return assistant.slotInGap(around: joinC, in: cells, atMouse: NSPoint(x: x, y: 5), horizontal: true)
        }
        XCTAssertTrue(pick(110) === joinC)
        XCTAssertTrue(pick(145) === joinP)
        XCTAssertTrue(pick(180) === after)
    }

    // Opening the chosen slot shifts the gap under a still mouse. The choice
    // must hold, or the two slots flap open and shut.
    func testGapChoiceHoldsWhileMouseIsStill() {
        let joinC = slot(x: 100, width: 90, joins: "C", joinsParent: "P")
        let joinP = slot(x: 190, width: 0, joins: "P")
        let after = slot(x: 190, width: 0)
        let cells = [chipCell("P"), chipCell("C", parent: "P"), tabCell("C", parent: "P"),
                     joinC, joinP, after, tabCell(nil)]
        let mouse = NSPoint(x: 135, y: 5)
        let first = assistant.slotInGap(around: joinC, in: cells, atMouse: mouse, horizontal: true)
        XCTAssertTrue(first === joinP)
        assistant.setTargetCell(first)

        // The parent's slot opens further right, outside the sub-group's padding.
        joinC.frame = NSRect(x: 100, y: 0, width: 0, height: 24)
        joinP.frame = NSRect(x: 115, y: 0, width: 90, height: 24)
        XCTAssertTrue(assistant.slotInGap(around: joinP, in: cells, atMouse: mouse, horizontal: true) === joinP)

        // Once the mouse moves, the zones apply again.
        XCTAssertTrue(assistant.slotInGap(around: joinP, in: cells, atMouse: NSPoint(x: 120, y: 5),
                                          horizontal: true) === joinC)
    }

    // A gap with one join slot keeps whichever slot is under the mouse.
    func testGapWithOneJoinSlotIsUnsplit() {
        let joinP = slot(x: 100, width: 90, joins: "P")
        let after = slot(x: 190, width: 0)
        let cells = [chipCell("P"), tabCell("P"), joinP, after, tabCell(nil)]
        XCTAssertTrue(assistant.slotInGap(around: joinP, in: cells, atMouse: NSPoint(x: 180, y: 5),
                                          horizontal: true) === joinP)
    }

    private func target(_ cells: [PSMTabBarCell], proposed: PSMTabBarCell, parent: String? = nil, canNest: Bool) -> PSMTabBarCell {
        // Every cell has a zero frame, so the mouse is past the run's midpoint.
        return assistant.groupDropTarget(forProposedTarget: proposed,
                                         in: cells,
                                         atMouse: NSPoint(x: 10, y: 0),
                                         horizontal: true,
                                         draggedParentID: parent,
                                         canNest: canNest)
    }

    func testNestableGroupMayLandInsideTopLevelGroup() {
        let inside = placeholder()
        let cells = [chipCell("P"), tabCell("P"), inside, tabCell("P"), placeholder()]
        XCTAssertTrue(target(cells, proposed: inside, canNest: true) === inside)
    }

    func testGroupWithSubgroupsSnapsOutOfOtherGroups() {
        let inside = placeholder()
        let after = placeholder()
        let cells = [chipCell("P"), tabCell("P"), inside, tabCell("P"), after]
        XCTAssertTrue(target(cells, proposed: inside, canNest: false) === after)
    }

    func testNestableGroupSnapsOutOfSubgroups() {
        let inside = placeholder()
        let afterSubgroup = placeholder()
        let cells = [chipCell("P"), chipCell("C", parent: "P"), tabCell("C", parent: "P"), inside,
                     tabCell("C", parent: "P"), afterSubgroup, tabCell("P"), placeholder()]
        XCTAssertTrue(target(cells, proposed: inside, canNest: true) === afterSubgroup)
    }
}


// Drives the real drag entry and -calculateDragAnimationForTabBar: loop over many
// ticks without resetting frames (as PSMTabGroupCollapsedDropScrollableTests
// does), so each tick's relayout feeds the next tick's targeting. A group whose
// last member is a sub-group has three slots in one gap (end of the sub-group,
// end of the parent, after the group) that open at slightly different places.
// Under a still mouse the open slots must settle, never flap.
final class PSMTabGroupNestedDropSettlingTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var source: PSMTabBarControl!
    private var assistant: PSMTabDragAssistant!
    private var items: [NSTabViewItem] = []

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.wantsLayer = true
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 800, height: 24))
        control.style = PSMYosemiteTabStyle()
        window.contentView?.addSubview(control)
        source = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 800, height: 24))
        window.contentView?.addSubview(source)
        assistant = PSMTabDragAssistant.shared()
    }

    override func tearDown() {
        assistant.finishDrag()
        assistant = nil
        items = []
        control = nil
        source = nil
        window = nil
        super.tearDown()
    }

    private func tab(_ groupID: String?, parent: String? = nil, x: CGFloat, w: CGFloat) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        cell.tabGroupParentIdentifier = parent
        let item = NSTabViewItem(identifier: "\(items.count)" as NSString)
        items.append(item)
        cell.representedObject = item
        cell.frame = NSRect(x: x, y: 0, width: w, height: 24)
        cell.dragBaseWidth = w
        return cell
    }

    private func chip(_ groupID: String, parent: String? = nil, x: CGFloat, w: CGFloat) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isTabGroupChip = true
        cell.tabGroupIdentifier = groupID
        cell.tabGroupParentIdentifier = parent
        cell.frame = NSRect(x: x, y: 0, width: w, height: 24)
        return cell
    }

    // [chip P][P][chip C][C][C][-], with a tab dragged in from another window and
    // entering at `entryX`.
    private func beginDrag(entryX: CGFloat) {
        control.cells().setArray([chip("P", x: 0, w: 40),
                                  tab("P", x: 40, w: 140),
                                  chip("C", parent: "P", x: 180, w: 40),
                                  tab("C", parent: "P", x: 220, w: 140),
                                  tab("C", parent: "P", x: 360, w: 140),
                                  tab(nil, x: 500, w: 140)])
        let dragged = PSMTabBarCell(controlView: source)!
        let item = NSTabViewItem(identifier: "dragged" as NSString)
        items.append(item)
        dragged.representedObject = item
        dragged.frame = NSRect(x: 0, y: 0, width: 140, height: 24)
        source.cells().setArray([dragged])
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(source)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 140)
        assistant.draggingEnteredTabBar(control, at: NSPoint(x: entryX, y: 12))
    }

    private func openSlotSteps() -> [Int] {
        return (control.cells() as! [PSMTabBarCell])
            .filter { $0.isPlaceholder && $0.currentStep > 0 }
            .map { Int($0.currentStep) }
            .sorted()
    }

    private func targetDescription() -> String {
        guard let t = assistant.targetCell() else { return "nil" }
        let index = (control.cells() as! [PSMTabBarCell]).firstIndex { $0 === t } ?? -1
        return "\(index):\(t.joinsTabGroupIdentifier ?? "-")"
    }

    func testStillMouseAtEndOfSubgroupAndParentSettles() {
        // Every still position from the sub-group's last tab through the tab
        // after the group, approached from the right as in the recording.
        var failures: [String] = []
        for x in stride(from: CGFloat(300), through: CGFloat(640), by: 2) {
            assistant.finishDrag()
            items = []
            beginDrag(entryX: 700)
            // Sweep in from the right, then hold.
            for i in 0...10 {
                assistant.setCurrentMouseLoc(NSPoint(x: 700 + (x - 700) * CGFloat(i) / 10, y: 12))
                assistant.calculateDragAnimation(forTabBar: control)
            }
            var trace: [String] = []
            var steps: [[Int]] = []
            for _ in 0..<40 {
                assistant.setCurrentMouseLoc(NSPoint(x: x, y: 12))
                assistant.calculateDragAnimation(forTabBar: control)
                steps.append(openSlotSteps())
                trace.append(targetDescription())
            }
            let tail = Array(steps.suffix(12))
            let targets = Array(trace.suffix(12))
            if !tail.allSatisfy({ $0 == tail.first }) || !targets.allSatisfy({ $0 == targets.first }) {
                failures.append("x=\(Int(x)) targets=\(targets) steps=\(tail)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "the drop gap flapped under a still mouse:\n\(failures.joined(separator: "\n"))")
    }

    // Creeping through the gap a point per tick, each slot must be reached and
    // the choice may only advance, never go back and forth.
    func testSlowMoveThroughEndOfSubgroupAndParentNeverReverses() {
        for (from, to) in [(CGFloat(640), CGFloat(300)), (CGFloat(300), CGFloat(640))] {
            assistant.finishDrag()
            items = []
            beginDrag(entryX: from)
            var choices: [String] = []
            let step: CGFloat = from < to ? 1 : -1
            for x in stride(from: from, through: to, by: step) {
                assistant.setCurrentMouseLoc(NSPoint(x: x, y: 12))
                assistant.calculateDragAnimation(forTabBar: control)
                let choice = assistant.targetCell()?.joinsTabGroupIdentifier ?? "-"
                if choice != choices.last {
                    choices.append(choice)
                }
            }
            // An a, b, a run is a flap. The ordinary slots on either side of
            // the gap may begin and end the sequence.
            let flaps = choices.indices.dropFirst(2).filter { choices[$0] == choices[$0 - 2] }
            XCTAssertTrue(flaps.isEmpty, "moving \(from > to ? "left" : "right") flapped: \(choices)")
            XCTAssertTrue(choices.contains("P") && choices.contains("C"),
                          "moving \(from > to ? "left" : "right") missed a slot: \(choices)")
        }
    }

    // [chip P][P][pill C][T]: a parent ending with a collapsed sub-group. A tab
    // can't join C's tabs (they're hidden) but must still be able to land as
    // P's last tab, after the pill. Approached from the right: moving right,
    // the open slot before the pill shoves it along until the mouse reaches it,
    // and then it slides back past the mouse.
    func testParentEndingWithCollapsedSubgroupKeepsItsEndSlot() {
        let c1 = tab("C", parent: "P", x: 300, w: 0)
        let c2 = tab("C", parent: "P", x: 300, w: 0)
        c1.isCollapsedHidden = true
        c2.isCollapsedHidden = true
        control.cells().setArray([chip("P", x: 0, w: 40),
                                  tab("P", x: 40, w: 140),
                                  chip("C", parent: "P", x: 180, w: 120), c1, c2,
                                  tab(nil, x: 300, w: 140)])
        let dragged = PSMTabBarCell(controlView: source)!
        let item = NSTabViewItem(identifier: "dragged" as NSString)
        items.append(item)
        dragged.representedObject = item
        dragged.frame = NSRect(x: 0, y: 0, width: 140, height: 24)
        source.cells().setArray([dragged])
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(source)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 140)
        assistant.draggingEnteredTabBar(control, at: NSPoint(x: 500, y: 12))

        // Whether the target is P's end slot: it joins P and comes after the
        // pill (the drag rebuilds chip cells, so look the pill up by group).
        func targetsEndOfP() -> Bool {
            let cells = control.cells() as! [PSMTabBarCell]
            guard let target = assistant.targetCell(),
                  target.joinsTabGroupIdentifier == "P",
                  let index = cells.firstIndex(where: { $0 === target }),
                  let pillIndex = cells.firstIndex(where: { $0.isTabGroupChip && $0.tabGroupIdentifier == "C" }) else {
                return false
            }
            return index > pillIndex
        }
        var reachedAt: CGFloat?
        for x in stride(from: CGFloat(500), through: CGFloat(20), by: -1) {
            for _ in 0..<3 {
                assistant.setCurrentMouseLoc(NSPoint(x: x, y: 12))
                assistant.calculateDragAnimation(forTabBar: control)
            }
            if targetsEndOfP() {
                reachedAt = x
                break
            }
        }
        guard let x = reachedAt else {
            XCTFail("never offered P's end slot")
            return
        }
        // A still mouse keeps it.
        for _ in 0..<30 {
            assistant.setCurrentMouseLoc(NSPoint(x: x, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        XCTAssertTrue(targetsEndOfP(), "P's end slot didn't hold under a still mouse at x=\(Int(x))")
    }
}

// A collapsed sub-group's chip is drawn inset inside its parent's outline, so its
// width must reserve that inset or the label is truncated.
final class PSMTabGroupNestedCollapsedChipWidthTests: XCTestCase {
    func testNestedCollapsedChipReservesSubgroupInset() {
        let control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 800, height: 24))
        control.style = PSMYosemiteTabStyle()
        let topLevel = control.widthOfTabGroupChipCell(forIdentifier: "S", collapsed: true, memberCount: 2, nested: false)
        let nested = control.widthOfTabGroupChipCell(forIdentifier: "S", collapsed: true, memberCount: 2, nested: true)
        XCTAssertEqual(nested - topLevel, 3, accuracy: 0.001)
        let expanded = control.widthOfTabGroupChipCell(forIdentifier: "S", collapsed: false, memberCount: 2, nested: true)
        XCTAssertEqual(expanded, control.widthOfTabGroupChipCell(forIdentifier: "S", collapsed: false, memberCount: 2, nested: false))
    }

    // The method is optional, so a style left on an old selector compiles fine
    // and silently gets a name-only width with no room for the count and
    // chevron.
    func testEveryBuiltInStyleSizesCollapsedChips() {
        // Some are Objective-C classes Swift can't see, so look them up by name.
        var styles: [AnyClass?] = ["PSMYosemiteTabStyle", "PSMDarkTabStyle", "PSMDarkHighContrastTabStyle",
                                   "PSMLightHighContrastTabStyle", "PSMMinimalTabStyle"].map { NSClassFromString($0) }
        if #available(macOS 26, *) {
            styles += [PSMTahoeTabStyle.self, PSMTahoeDarkTabStyle.self, PSMTahoeDarkHighContrastTabStyle.self,
                       PSMTahoeLightHighContrastTabStyle.self]
        }
        let selector = #selector(PSMTabStyle.tabGroupCollapsedChipCellWidth(forName:memberCount:nested:))
        for style in styles {
            guard let style = style as? NSObject.Type else {
                XCTFail("missing style class")
                continue
            }
            XCTAssertTrue(style.instancesRespond(to: selector), "\(style) doesn't size collapsed chips")
        }
    }
}

//
//  PSMTabGroupDragTests.swift
//  iTerm2XCTests
//
//  Live drag-start tests for the group-block drag path. Unlike
//  PSMTabGroupCellTests (which exercises pure cell-list helpers), these drive
//  the real -[PSMTabDragAssistant startDraggingGroupWithChip:members:...]
//  entry point end to end, so they catch crashes in the setup + snapshot +
//  placeholder-distribution path that the helper tests cannot reach. Run under
//  the ModernTests ASan build to surface memory corruption precisely.
//

import XCTest
@testable import iTerm2SharedARC

// A chip cell that records whether its -frame was ever read while it was no
// longer in the control's cell list. The field crash was exactly that: the
// base -distributePlaceholdersInTabBar: strips chips (freeing a chip the MRR
// drag code holds unretained), and the group variant then read [chip frame].
// By holding a strong ref to this subclass the test avoids the use-after-free
// itself and instead asserts the ordering the fix guarantees, deterministically
// (no reliance on freed-memory state, so it is not flaky).
private final class ObservingChipCell: PSMTabBarCell {
    weak var observedControl: PSMTabBarControl?
    var frameReadAfterStrip = false
    override var frame: NSRect {
        get {
            if let control = observedControl, !control.cells().contains(self) {
                frameReadAfterStrip = true
            }
            return super.frame
        }
        set { super.frame = newValue }
    }
}

final class PSMTabGroupDragTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var dragDriver: FakeTabDragSessionDriver!
    private var savedDragDriver: PSMTabDragSessionDriver!

    override func setUp() {
        super.setUp()
        // Never let a test arm a real NSDraggingSession: it would not start
        // here, it would start inside whatever later test first pumps the run
        // loop, and hang that test forever in AppKit's modal drag loop.
        savedDragDriver = PSMTabDragAssistant.shared().dragSessionDriver
        dragDriver = FakeTabDragSessionDriver()
        PSMTabDragAssistant.shared().dragSessionDriver = dragDriver
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        // Mirror the real tab bar: iTerm2 windows are layer-backed, which routes
        // -cacheDisplayInRect: (the group drag-image snapshot) down a different
        // path than a plain view.
        window.contentView?.wantsLayer = true
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 600, height: 24))
        window.contentView?.addSubview(control)
    }

    override func tearDown() {
        // Make sure a failed/aborted drag doesn't leak assistant state into the
        // next test.
        PSMTabDragAssistant.shared().finishDrag()
        PSMTabDragAssistant.shared().dragSessionDriver = savedDragDriver
        savedDragDriver = nil
        dragDriver = nil
        control = nil
        window = nil
        super.tearDown()
    }

    // Keep strong refs to the bound tab view items for the test's lifetime.
    private var items: [NSTabViewItem] = []

    // Build a bar whose member cells carry the two live-cell traits the drag
    // snapshot touches: the KVO "title <- label" binding and an indicator
    // subview parented to the control. Cells are hand-built (there is no public
    // -addTabViewItem:) and framed by hand since there's no live layout pass.
    private func makeGroupedBar() -> (chip: PSMTabBarCell, members: [PSMTabBarCell]) {
        let cells = NSMutableArray()
        var x: CGFloat = 0
        func makeTab(_ groupID: String?, _ label: String) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: control)!
            cell.tabGroupIdentifier = groupID
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            cell.bind(NSBindingName("title"), to: item, withKeyPath: "label", options: nil)
            control.addSubview(cell.indicator)  // live cells park their indicator here
            cell.frame = NSRect(x: x, y: 0, width: 120, height: 24)
            x += 120
            cells.add(cell)
            return cell
        }

        let chip = ObservingChipCell(controlView: control)!
        chip.observedControl = control
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "A"
        chip.frame = NSRect(x: x, y: 0, width: 40, height: 24)
        x += 40
        cells.insert(chip, at: 0)

        let m0 = makeTab("A", "Member 0")
        let m1 = makeTab("A", "Member 1")
        _ = makeTab(nil, "Loner")

        control.cells().setArray(cells as [AnyObject])
        return (chip, [m0, m1])
    }

    private func mouseDownEvent(at point: NSPoint) -> NSEvent {
        let inWindow = control.convert(point, to: nil)
        return NSEvent.mouseEvent(with: .leftMouseDown,
                                  location: inWindow,
                                  modifierFlags: [],
                                  timestamp: 0,
                                  windowNumber: window.windowNumber,
                                  context: nil,
                                  eventNumber: 0,
                                  clickCount: 1,
                                  pressure: 1)!
    }

    // Drives the full group-drag start (snapshot + placeholder distribution).
    //
    // NOTE ON COVERAGE: the field crash here was a use-after-free -- the base
    // -distributePlaceholdersInTabBar: strips chip cells from the control, which
    // (PSMTabBarCell being ARC) deallocated the `chip` argument because the MRR
    // drag callers hold it unretained; the group variant then read [chip frame].
    // This ARC (Swift) test cannot reproduce that specific UAF: passing `chip` as
    // an argument retains it for the call's duration, masking the dangling ref.
    // It still guards the path against crashes and, via the width assertion below,
    // locks in that the group placeholder spans the whole run -- which only holds
    // if runFrame is computed from a live chip frame.
    func testStartDraggingGroupSpansTheWholeRun() {
        let (chip, members) = makeGroupedBar()
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))  // over the chip
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)
        XCTAssertTrue(PSMTabDragAssistant.shared().isDragging())
        // The drop-slot placeholder for the group is the drag's target cell; it
        // must span the run: chip leading edge (0) through the last member's
        // trailing edge (chip 40 + member 120 + member 120 = 280).
        guard let target = PSMTabDragAssistant.shared().targetCell() else {
            XCTFail("no target cell after starting a group drag")
            return
        }
        XCTAssertTrue(target.isPlaceholder)
        // The slot opened to the whole group's width (chip 40 + 120 + 120 = 280),
        // not a single tab's (120). Layout applies a small leading inset, so
        // compare loosely rather than to an exact frame.
        XCTAssertGreaterThan(target.frame.width, 200)
    }

    // [chip P][chip S][S 1][S 2][P 1][Loner]: P's first content is sub-group S.
    private func makeNestedBar() -> (subgroupChip: PSMTabBarCell, subgroupMembers: [PSMTabBarCell]) {
        var x: CGFloat = 0
        var cells: [PSMTabBarCell] = []
        func add(_ cell: PSMTabBarCell, width: CGFloat) {
            cell.frame = NSRect(x: x, y: 0, width: width, height: 24)
            x += width
            cells.append(cell)
        }
        func makeChip(_ groupID: String, parent: String?) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: control)!
            cell.isTabGroupChip = true
            cell.tabGroupIdentifier = groupID
            cell.tabGroupParentIdentifier = parent
            add(cell, width: 40)
            return cell
        }
        func makeTab(_ groupID: String?, parent: String?, _ label: String) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: control)!
            cell.tabGroupIdentifier = groupID
            cell.tabGroupParentIdentifier = parent
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            add(cell, width: 100)
            return cell
        }
        _ = makeChip("P", parent: nil)
        let subgroupChip = makeChip("S", parent: "P")
        let s1 = makeTab("S", parent: "P", "S 1")
        let s2 = makeTab("S", parent: "P", "S 2")
        _ = makeTab("P", parent: nil, "P 1")
        _ = makeTab(nil, parent: nil, "Loner")
        control.cells().setArray(cells)
        return (subgroupChip, [s1, s2])
    }

    // Dragging a sub-group leaves its slot inside the parent: the parent's chip
    // stays before it, and dropping it back there keeps it nested. The slot
    // before the parent's chip is outside the parent.
    func testDraggedSubgroupSlotStaysInsideParent() {
        let (chip, members) = makeNestedBar()
        let assistant = PSMTabDragAssistant.shared()!
        assistant.startDraggingGroup(withChip: chip,
                                     members: members,
                                     fromTabBar: control,
                                     withMouseDownEvent: mouseDownEvent(at: NSPoint(x: 60, y: 12)))
        let cells = control.cells() as! [PSMTabBarCell]
        guard let slot = assistant.targetCell(),
              let slotIndex = cells.firstIndex(where: { $0 === slot }),
              let parentChipIndex = cells.firstIndex(where: { $0.isTabGroupChip && $0.tabGroupIdentifier == "P" }) else {
            XCTFail("missing own slot or parent chip: \(cells)")
            return
        }
        XCTAssertLessThan(parentChipIndex, slotIndex, "the parent's chip must stay before the sub-group's slot")
        XCTAssertEqual(assistant.parentGroupForGroupDrop(at: slot, in: cells, excluding: members), "P")
        guard let outside = cells[..<parentChipIndex].last(where: { $0.isPlaceholder }) else {
            XCTFail("no slot before the parent's chip: \(cells)")
            return
        }
        XCTAssertNil(assistant.parentGroupForGroupDrop(at: outside, in: cells, excluding: members))
        XCTAssertNil(control.onlyTabGroupRunDecorationIdentifier, "the drag image filter must be cleared")
    }

    // [chip P][chip S, collapsed][P 1][P 2][P 3][Loner][chip Q, collapsed]:
    // S is P's first item. Collapsed members have zero frames, as in the app.
    private func makeBarWithCollapsedSubgroupFirst() -> (subgroupChip: PSMTabBarCell, subgroupMembers: [PSMTabBarCell]) {
        var x: CGFloat = 0
        var cells: [PSMTabBarCell] = []
        func add(_ cell: PSMTabBarCell, width: CGFloat) {
            cell.frame = NSRect(x: x, y: 0, width: width, height: 24)
            x += width
            cells.append(cell)
        }
        func makeChip(_ groupID: String, parent: String?, width: CGFloat) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: control)!
            cell.isTabGroupChip = true
            cell.tabGroupIdentifier = groupID
            cell.tabGroupParentIdentifier = parent
            add(cell, width: width)
            return cell
        }
        func makeTab(_ groupID: String?, parent: String?, _ label: String, hidden: Bool) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: control)!
            cell.tabGroupIdentifier = groupID
            cell.tabGroupParentIdentifier = parent
            cell.isCollapsedHidden = hidden
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            add(cell, width: hidden ? 0 : 250)
            if hidden {
                cell.frame = NSRect(x: cell.frame.minX, y: 0, width: 0, height: 0)
            } else {
                cell.dragBaseWidth = 250
            }
            return cell
        }
        _ = makeChip("P", parent: nil, width: 29)
        let subgroupChip = makeChip("S", parent: "P", width: 61)
        let s1 = makeTab("S", parent: "P", "S 1", hidden: true)
        let s2 = makeTab("S", parent: "P", "S 2", hidden: true)
        _ = makeTab("P", parent: nil, "P 1", hidden: false)
        _ = makeTab("P", parent: nil, "P 2", hidden: false)
        _ = makeTab("P", parent: nil, "P 3", hidden: false)
        _ = makeTab(nil, parent: nil, "Loner", hidden: false)
        _ = makeChip("Q", parent: nil, width: 50)
        _ = makeTab("Q", parent: nil, "Q 1", hidden: true)
        control.cells().setArray(cells)
        return (subgroupChip, [s1, s2])
    }

    // Dragging a collapsed sub-group to just before its parent's chip must
    // settle under a still mouse. Opening the slot before the parent slides the
    // parent's chip off the mouse, which is then over the slot. A collapsed
    // group's members have zero frames; slots sized from them had no height,
    // so the mouse missed the slot and targeting fell back to the slot past the
    // chip, closing the slot and sliding the chip back.
    func testStillMouseBeforeParentChipSettlesWhenDraggingCollapsedSubgroup() {
        let assistant = PSMTabDragAssistant.shared()!
        let savedScrollable = useFieldBar()
        defer { iTermPreferences.setBool(savedScrollable, forKey: kPreferenceKeyScrollableSideTabBar) }
        var failures: [String] = []
        for x in stride(from: CGFloat(130), through: CGFloat(200), by: 0.5) {
            assistant.finishDrag()
            items = []
            let (chip, members) = makeBarWithCollapsedSubgroupFirst()
            let grab = NSMidX(chip.frame) + 136
            assistant.startDraggingGroup(withChip: chip,
                                         members: members,
                                         fromTabBar: control,
                                         withMouseDownEvent: mouseDownEvent(at: NSPoint(x: grab, y: 12)))
            for i in 0...20 {
                assistant.setCurrentMouseLoc(NSPoint(x: grab + (x - grab) * CGFloat(i) / 20, y: 12))
                assistant.calculateDragAnimation(forTabBar: control)
            }
            var targets: [Int] = []
            for _ in 0..<40 {
                assistant.setCurrentMouseLoc(NSPoint(x: x, y: 12))
                assistant.calculateDragAnimation(forTabBar: control)
                let cells = control.cells() as! [PSMTabBarCell]
                targets.append(assistant.targetCell().flatMap { t in cells.firstIndex { $0 === t } } ?? -1)
            }
            let tail = Array(targets.suffix(12))
            if !tail.allSatisfy({ $0 == tail.first }) {
                failures.append("x=\(x) targets=\(tail)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "the drop slot flapped under a still mouse:\n\(failures.joined(separator: "\n"))")
    }

    // Match the bar in the field: scrollable, 1007pt wide, minimal style, with the
    // window buttons in the bar. Returns the scrollable setting to restore.
    private func useFieldBar() -> Bool {
        let savedScrollable = iTermPreferences.bool(forKey: kPreferenceKeyScrollableSideTabBar)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyScrollableSideTabBar)
        window.setContentSize(NSSize(width: 1007, height: 400))
        control.frame = NSRect(x: 0, y: 376, width: 1007, height: 24)
        control.style = PSMYosemiteTabStyle()
        // Compact windows put the window buttons in the tab bar.
        control.insets = NSEdgeInsets(top: 0, left: 136, bottom: 0, right: 0)
        return savedScrollable
    }

    // [chip S, collapsed][chip P][P 1][P 2][P 3], laid out from x=136.
    private func makeBarWithCollapsedGroupBeforeExpandedGroup() -> (chip: PSMTabBarCell, members: [PSMTabBarCell]) {
        var x: CGFloat = 136
        var cells: [PSMTabBarCell] = []
        func add(_ cell: PSMTabBarCell, width: CGFloat) {
            cell.frame = NSRect(x: x, y: 0, width: width, height: width > 0 ? 24 : 0)
            x += width
            cells.append(cell)
        }
        func makeChip(_ groupID: String, width: CGFloat) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: control)!
            cell.isTabGroupChip = true
            cell.tabGroupIdentifier = groupID
            add(cell, width: width)
            return cell
        }
        func makeTab(_ groupID: String?, _ label: String, hidden: Bool) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: control)!
            cell.tabGroupIdentifier = groupID
            cell.isCollapsedHidden = hidden
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            add(cell, width: hidden ? 0 : 255)
            if !hidden {
                cell.dragBaseWidth = 255
            }
            return cell
        }
        _ = makeChip("S", width: 52)
        _ = makeTab("S", "S 1", hidden: true)
        _ = makeTab("S", "S 2", hidden: true)
        let chip = makeChip("P", width: 30)
        let p1 = makeTab("P", "P 1", hidden: false)
        let p2 = makeTab("P", "P 2", hidden: false)
        let p3 = makeTab("P", "P 3", hidden: false)
        control.cells().setArray(cells)
        return (chip, [p1, p2, p3])
    }

    private func targetIndex() -> Int {
        let cells = control.cells() as! [PSMTabBarCell]
        return PSMTabDragAssistant.shared().targetCell().flatMap { t in cells.firstIndex { $0 === t } } ?? -1
    }

    // Picking up a group right after a collapsed group must not open the slot
    // before the collapsed group, even for a tick: that shoves it aside and
    // back. Hovering over the leading part of the collapsed group's chip must
    // then open that slot, so the group can be dropped before it.
    func testDraggingGroupPastCollapsedGroup() {
        let assistant = PSMTabDragAssistant.shared()!
        let savedScrollable = useFieldBar()
        defer { iTermPreferences.setBool(savedScrollable, forKey: kPreferenceKeyScrollableSideTabBar) }
        let (chip, members) = makeBarWithCollapsedGroupBeforeExpandedGroup()
        let collapsedChip = (control.cells() as! [PSMTabBarCell]).first { $0.tabGroupIdentifier == "S" && $0.isTabGroupChip }!
        let collapsedChipFrame = collapsedChip.frame
        let grab = NSMidX(chip.frame)
        assistant.startDraggingGroup(withChip: chip,
                                     members: members,
                                     fromTabBar: control,
                                     withMouseDownEvent: mouseDownEvent(at: NSPoint(x: grab, y: 12)))
        func slotBeforeCollapsedGroup() -> PSMTabBarCell? {
            let cells = control.cells() as! [PSMTabBarCell]
            guard let ci = cells.firstIndex(where: { $0.isTabGroupChip && $0.tabGroupIdentifier == "S" }) else { return nil }
            return cells[..<ci].last(where: { $0.isPlaceholder })
        }
        var jumped: [String] = []
        // The mouse path from the field log: a little left, then right, never
        // pausing.
        let path: [CGFloat] = (0..<10).map { grab - 11 + CGFloat($0) * 2 }
        for (tick, mouseX) in path.enumerated() {
            assistant.setCurrentMouseLoc(NSPoint(x: mouseX, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
            if let before = slotBeforeCollapsedGroup(), assistant.targetCell() === before || before.currentStep > 0 {
                jumped.append("tick \(tick): target=\(targetIndex()) step=\(before.currentStep)")
            }
            // The slot the group left must stay open, or everything after it
            // shifts and comes back.
            if let own = assistant.targetCell(), own.currentStep < Int32(kPSMTabDragAnimationSteps - 1) {
                jumped.append("tick \(tick): own slot step=\(own.currentStep)")
            }
        }
        XCTAssertTrue(jumped.isEmpty, "picking up the group moved the collapsed group: \(jumped)")

        // Move over the leading quarter of the collapsed chip and hold. (The
        // drag rebuilds chip cells, so look it up by group.)
        let x = collapsedChipFrame.minX + collapsedChipFrame.width / 4
        for i in 0...20 {
            assistant.setCurrentMouseLoc(NSPoint(x: grab + (x - grab) * CGFloat(i) / 20, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        for _ in 0..<30 {
            assistant.setCurrentMouseLoc(NSPoint(x: x, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        let before = slotBeforeCollapsedGroup()
        XCTAssertNotNil(before)
        XCTAssertTrue(assistant.targetCell() === before,
                      "hovering the collapsed group's leading part must target the slot before it; target=\(targetIndex())")
        XCTAssertGreaterThan(before?.frame.width ?? 0, 0, "the slot before the collapsed group must open")
    }

    // With the filter set, only that group's run and its sub-groups' runs are
    // decorated, so a sub-group's drag image leaves out its parent's outline
    // and a parent's drag image keeps its sub-groups'.
    func testDecorationFilterKeepsOnlyThatGroup() {
        _ = makeNestedBar()
        var decorated: [String] = []
        control.onlyTabGroupRunDecorationIdentifier = "S"
        control.enumerateTabGroupRuns(rectForCell: nil) { _, _, _, gid in decorated.append(gid) }
        control.onlyTabGroupRunDecorationIdentifier = nil
        XCTAssertEqual(decorated, ["S"])
        decorated = []
        control.onlyTabGroupRunDecorationIdentifier = "P"
        control.enumerateTabGroupRuns(rectForCell: nil) { _, _, _, gid in decorated.append(gid) }
        control.onlyTabGroupRunDecorationIdentifier = nil
        XCTAssertEqual(Set(decorated), ["P", "S"], "the parent's drag image lost its sub-group")
        decorated = []
        control.enumerateTabGroupRuns(rectForCell: nil) { _, _, _, gid in decorated.append(gid) }
        XCTAssertEqual(Set(decorated), ["P", "S"])
    }

    // Dragging a group into ANOTHER bar and hovering past its last tab (or
    // past its trailing group) must target the trailing drop slot and open it,
    // so the user sees where the group will land before releasing.
    func testGroupDragIntoOtherBarOpensTrailingSlot() {
        let (chip, members) = makeGroupedBar()
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)

        // A second tab bar (as in another window) holding group C = [c1, c2].
        let other = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 600, height: 24))
        window.contentView?.addSubview(other)
        var x: CGFloat = 0
        func otherTab(_ gid: String?, _ label: String) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: other)!
            cell.tabGroupIdentifier = gid
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            cell.frame = NSRect(x: x, y: 0, width: 120, height: 24)
            x += 120
            return cell
        }
        let otherChip = PSMTabBarCell(controlView: other)!
        otherChip.isTabGroupChip = true
        otherChip.tabGroupIdentifier = "C"
        otherChip.frame = NSRect(x: 0, y: 0, width: 40, height: 24)
        x = 40
        let c1 = otherTab("C", "c1")
        let c2 = otherTab("C", "c2")
        other.cells().setArray([otherChip, c1, c2])

        // Enter the other bar hovering well past its last tab.
        let pastEnd = NSPoint(x: 500, y: 12)
        PSMTabDragAssistant.shared().draggingEnteredTabBar(other, at: pastEnd)
        PSMTabDragAssistant.shared().draggingUpdated(inTabBar: other, at: pastEnd)

        // Drive a few animation ticks; the trailing placeholder must become
        // the target and start opening.
        for _ in 0..<5 {
            PSMTabDragAssistant.shared().calculateDragAnimation(forTabBar: other)
        }
        guard let target = PSMTabDragAssistant.shared().targetCell() else {
            XCTFail("no target when hovering past the end of the destination bar")
            return
        }
        XCTAssertTrue(target.isPlaceholder, "target must be a drop slot, not a tab/chip")
        let cells = other.cells() as! [PSMTabBarCell]
        XCTAssertTrue(target === cells.last,
                      "hovering past the end must target the trailing slot (got index \(cells.firstIndex(where: { $0 === target }) ?? -1) of \(cells.count))")
        XCTAssertGreaterThan(target.currentStep, 0,
                             "the trailing slot never started opening")
    }

    // The drop-slot animation must advance while the run loop is in the
    // event-tracking mode, because that is the mode an NSDraggingSession
    // holds the main run loop in for the whole drag. A timer scheduled only
    // for the default mode starves there: the gap in the destination bar
    // never opens even though the target slot is correct (field bug: group
    // dragged into another window's bar, no gap, silent append).
    func testAADropSlotOpensWhileRunLoopIsInEventTrackingMode() {
        // Arm the assistant the way entering a bar mid-drag does, but without
        // a live NSDraggingSession: pumping the run loop would end a headless
        // session and tear the drag down. The behavior under test is only
        // “does the animation timer tick in the event-tracking mode”.
        let other = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 600, height: 24))
        window.contentView?.addSubview(other)
        let t1 = PSMTabBarCell(controlView: other)!
        let item = NSTabViewItem(identifier: "dest" as NSString)
        item.label = "dest"
        items.append(item)
        t1.representedObject = item
        t1.frame = NSRect(x: 20, y: 0, width: 120, height: 24)
        other.cells().setArray([t1])

        PSMTabDragAssistant.shared().startAnimation(with: .horizontalOrientation,
                                                    width: 120)
        let pastEnd = NSPoint(x: 500, y: 12)
        PSMTabDragAssistant.shared().draggingEnteredTabBar(other, at: pastEnd)
        PSMTabDragAssistant.shared().draggingUpdated(inTabBar: other, at: pastEnd)

        // Pump a PRIVATE common mode instead of .eventTracking itself: the
        // timer is registered via NSRunLoopCommonModes so it fires in any
        // common mode (which is what makes it fire in the tracking mode during
        // a live drag), while stale performSelectors queued for the tracking/
        // default modes by other tests do not fire here (one of them once
        // blocked this test for minutes; it also runs FIRST -- the AA prefix --
        // so no zombie NSDraggingSession from a prior test can stall the
        // pump). A timer scheduled only for the
        // default mode (the old bug) does NOT fire in this mode, so the red
        // case is preserved. Do not call calculateDragAnimation ourselves;
        // the assistant's timer must do it.
        let mode = CFRunLoopMode("PSMDragTimerTestMode" as CFString)
        CFRunLoopAddCommonMode(CFRunLoopGetCurrent(), mode)
        let deadline = Date(timeIntervalSinceNow: 0.5)
        while Date() < deadline {
            CFRunLoopRunInMode(mode, 0.05, false)
            if let target = PSMTabDragAssistant.shared().targetCell(), target.currentStep > 0 {
                break
            }
        }
        guard let target = PSMTabDragAssistant.shared().targetCell() else {
            XCTFail("no target cell in the destination bar")
            return
        }
        XCTAssertTrue(target.isPlaceholder)
        XCTAssertGreaterThan(target.currentStep, 0,
                             "the drop slot never opened: the animation timer is starved in the event-tracking run-loop mode")
    }

    // The drop slot must be sized to what the dragged unit will occupy in the
    // DESTINATION bar, not its size in the source bar: dragging a group from a
    // wide window into a narrow stretch-to-fit window must open a slot at the
    // destination's (much smaller) on-drop size.
    func testDropSlotSizedForDestinationNotSource() {
        let (chip, members) = makeGroupedBar()   // source unit ≈ 280pt wide
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)

        // Narrow destination: 400pt bar, three stretched tabs.
        let other = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 400, height: 24))
        other.stretchCellsToFit = true
        window.contentView?.addSubview(other)
        var tabs: [PSMTabBarCell] = []
        for (i, label) in ["one", "two", "three"].enumerated() {
            let cell = PSMTabBarCell(controlView: other)!
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            cell.frame = NSRect(x: CGFloat(i) * 125, y: 0, width: 122, height: 24)
            tabs.append(cell)
        }
        other.cells().setArray(tabs)

        let pastEnd = NSPoint(x: 390, y: 12)
        PSMTabDragAssistant.shared().draggingEnteredTabBar(other, at: pastEnd)
        PSMTabDragAssistant.shared().draggingUpdated(inTabBar: other, at: pastEnd)
        for _ in 0..<15 {
            PSMTabDragAssistant.shared().calculateDragAnimation(forTabBar: other)
        }

        guard let target = PSMTabDragAssistant.shared().targetCell() else {
            XCTFail("no target cell")
            return
        }
        XCTAssertTrue(target.isPlaceholder)
        // Two incoming tabs among three existing in a crowded 400pt bar get
        // the minimum tab width each plus a chip (the bar is too full for
        // more): clearly less than the source unit's ~280pt. Anything close
        // to the source size means the slot was sized from the wrong bar.
        XCTAssertGreaterThan(target.frame.width, 60, "the slot never opened")
        XCTAssertLessThan(target.frame.width, 250,
                          "slot sized from the SOURCE bar; it must use the destination's on-drop size")
    }

    // A SCROLLABLE bar does not squeeze its tabs; a slot opening past the last
    // tab lies beyond the visible viewport, so the bar must auto-scroll to
    // reveal it (field bug: “a slot did open but almost all of it was not
    // visible because the tabbar would have to scroll to reveal it”).
    func testScrollableBarAutoScrollsToRevealDropSlot() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyScrollableSideTabBar)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyScrollableSideTabBar) }

        let (chip, members) = makeGroupedBar()
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)

        // Destination: three tabs whose natural widths nearly fill the
        // scroll viewport, so an opening slot must extend past it.
        let other = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 600, height: 24))
        window.contentView?.addSubview(other)
        var tabs: [PSMTabBarCell] = []
        for (i, label) in ["one", "two", "three"].enumerated() {
            let cell = PSMTabBarCell(controlView: other)!
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            cell.frame = NSRect(x: CGFloat(i) * 180, y: 0, width: 175, height: 24)
            tabs.append(cell)
        }
        other.cells().setArray(tabs)

        let pastEnd = NSPoint(x: 590, y: 12)
        PSMTabDragAssistant.shared().draggingEnteredTabBar(other, at: pastEnd)
        PSMTabDragAssistant.shared().draggingUpdated(inTabBar: other, at: pastEnd)
        for _ in 0..<15 {
            PSMTabDragAssistant.shared().calculateDragAnimation(forTabBar: other)
        }

        guard let target = PSMTabDragAssistant.shared().targetCell() else {
            XCTFail("no target cell")
            return
        }
        XCTAssertTrue(target.isPlaceholder)
        XCTAssertGreaterThan(target.frame.width, 100, "the drop slot never opened")
        // The slot must be REVEALED: its trailing edge inside the viewport,
        // which requires the bar to have scrolled (first tab shifted left).
        XCTAssertLessThanOrEqual(target.frame.maxX, other.scrollViewportLength + 0.5,
                                 "the open slot lies beyond the viewport; the bar must auto-scroll to reveal it")
        XCTAssertLessThan(tabs[0].frame.minX, 0,
                          "revealing the trailing slot requires scrolling earlier tabs off the leading edge")

        // Now target the LEADING slot: the auto-scroll must give the shift
        // back, or the slot opens off-screen left (field bug: hover the right
        // side of a tab, then the left side -- no slot appears).
        PSMTabDragAssistant.shared().draggingUpdated(inTabBar: other, at: NSPoint(x: 2, y: 12))
        for _ in 0..<30 {
            PSMTabDragAssistant.shared().calculateDragAnimation(forTabBar: other)
        }
        guard let leadingTarget = PSMTabDragAssistant.shared().targetCell() else {
            XCTFail("no target at the leading edge")
            return
        }
        XCTAssertTrue(leadingTarget.isPlaceholder)
        XCTAssertGreaterThan(leadingTarget.frame.width, 100, "the leading-side slot never opened")
        XCTAssertGreaterThanOrEqual(leadingTarget.frame.minX, -0.5,
                                    "the targeted slot opened off-screen left; the auto-scroll must shrink back to reveal it")
    }

    // A stretch-to-fill bar has NO slack: its tabs occupy the whole width, so
    // an expanding drop slot must carve room by shrinking the real tabs, or
    // the slot grows past the trailing edge where it is invisible (field bug:
    // dragging a group into another window's full bar showed no gap at all).
    func testForeignDragIntoFullBarShrinksTabsToOpenGap() {
        let (chip, members) = makeGroupedBar()
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)

        // Destination: two tabs stretched to fill the whole 600pt bar.
        let other = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 600, height: 24))
        window.contentView?.addSubview(other)
        var tabs: [PSMTabBarCell] = []
        for (i, label) in ["one", "two"].enumerated() {
            let cell = PSMTabBarCell(controlView: other)!
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            cell.frame = NSRect(x: CGFloat(i) * 290, y: 0, width: 285, height: 24)
            tabs.append(cell)
        }
        other.cells().setArray(tabs)

        let pastEnd = NSPoint(x: 590, y: 12)
        PSMTabDragAssistant.shared().draggingEnteredTabBar(other, at: pastEnd)
        PSMTabDragAssistant.shared().draggingUpdated(inTabBar: other, at: pastEnd)
        for _ in 0..<12 {
            PSMTabDragAssistant.shared().calculateDragAnimation(forTabBar: other)
        }

        guard let target = PSMTabDragAssistant.shared().targetCell() else {
            XCTFail("no target cell")
            return
        }
        XCTAssertTrue(target.isPlaceholder)
        XCTAssertGreaterThan(target.frame.width, 40, "the drop slot never opened")
        // The gap must be INSIDE the bar: everything (shrunken tabs + slot)
        // fits the bar's width instead of overflowing the trailing edge.
        let cells = other.cells() as! [PSMTabBarCell]
        let maxRight = cells.map { $0.frame.maxX }.max() ?? 0
        XCTAssertLessThanOrEqual(maxRight, other.frame.width + 0.5,
                                 "the slot overflowed the bar instead of shrinking the tabs to make room")
        for tab in tabs {
            XCTAssertLessThan(tab.frame.width, 285,
                              "full-width tabs must shrink to make the gap visible")
        }
    }

    // Entering a bar mid-drag must distribute drop slots even when a stale
    // placeholder (left by an earlier aborted drag) sits at index 0. The old
    // guard keyed on cells[0].isPlaceholder and skipped distribution entirely:
    // no slot ever opened in that bar and drops fell back to appending.
    func testEnteringBarWithStalePlaceholderStillDistributesSlots() {
        let (chip, members) = makeGroupedBar()
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)

        let other = PSMTabBarControl(frame: NSRect(x: 0, y: 300, width: 600, height: 24))
        window.contentView?.addSubview(other)
        let t1 = PSMTabBarCell(controlView: other)!
        let item = NSTabViewItem(identifier: "stale" as NSString)
        item.label = "stale"
        items.append(item)
        t1.representedObject = item
        t1.frame = NSRect(x: 20, y: 0, width: 120, height: 24)
        let stale = PSMTabBarCell(placeholderWithFrame: .zero, expanded: false, inControlView: other)!
        other.cells().setArray([stale, t1])

        PSMTabDragAssistant.shared().draggingEnteredTabBar(other, at: NSPoint(x: 500, y: 12))
        let cells = other.cells() as! [PSMTabBarCell]
        let placeholders = cells.filter { $0.isPlaceholder }
        // One real tab distributes to [ph, t1, ph]: two live slots, stale one gone.
        XCTAssertEqual(placeholders.count, 2,
                       "expected fresh drop slots around the tab; a stale placeholder must not suppress distribution")
        XCTAssertTrue(cells.last!.isPlaceholder, "the trailing drop slot must exist")
    }

    // Regression guard for the field use-after-free: the group drag must read the
    // chip's frame (to size the run's drop slot) BEFORE the base placeholder
    // distribution strips chip cells from the control. If that order is reversed,
    // the chip has been removed from the cell list (and, in production, freed) by
    // the time its frame is read.
    func testChipFrameIsReadBeforeChipsAreStripped() {
        let (chip, members) = makeGroupedBar()
        let observing = chip as! ObservingChipCell
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)
        XCTAssertFalse(observing.frameReadAfterStrip,
                       "chip.frame was read after the chip was stripped from the control -- this is the use-after-free")
    }

    // MARK: - Simulated drag session

    // Starting a group drag must hand the driver exactly one dragging session,
    // for the source bar, and start pointer tracking. Production wires these to
    // NSDraggingSession and a CVDisplayLink; the point of the seam is that the
    // assistant asks for them rather than reaching for AppKit itself.
    func testStartingGroupDragOpensOneSessionAndStartsTracking() {
        let (chip, members) = makeGroupedBar()
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: mouseDownEvent(at: NSPoint(x: 20, y: 12)))

        XCTAssertEqual(dragDriver.startedSessionCount, 1)
        XCTAssertTrue(dragDriver.lastTabBar === control)
        XCTAssertEqual(dragDriver.lastDraggingItems.count, 1)
        XCTAssertTrue(dragDriver.isTrackingMouse,
                      "the drag image cannot follow the pointer if nothing is polling it")
    }

    // Finishing a drag must stop the polling. The real driver leaks a running
    // CVDisplayLink otherwise.
    func testFinishDragStopsMouseTracking() {
        let (chip, members) = makeGroupedBar()
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: mouseDownEvent(at: NSPoint(x: 20, y: 12)))
        XCTAssertTrue(dragDriver.isTrackingMouse)

        PSMTabDragAssistant.shared().finishDrag()

        XCTAssertFalse(dragDriver.isTrackingMouse)
        XCTAssertGreaterThanOrEqual(dragDriver.stopMouseTrackingCount, 1)
    }

    // The whole point of simulating rather than stubbing: a pointer update fed
    // through the driver must move the floating drag image, along the same code
    // path a CVDisplayLink tick takes during a real drag.
    func testSimulatedPointerMoveDragsTheTabImage() {
        let (chip, members) = makeGroupedBar()
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: mouseDownEvent(at: NSPoint(x: 20, y: 12)))
        // Arm the drag-window origin the way AppKit's drag-began callback does;
        // until then the assistant ignores pointer updates.
        PSMTabDragAssistant.shared().draggingBegan(at: NSPoint(x: 200, y: 200))
        let start = PSMTabDragAssistant.shared().dragTabWindowFrame
        XCTAssertFalse(NSEqualRects(start, .zero), "no drag image window to move")

        dragDriver.simulateMouseMove(to: NSPoint(x: 360, y: 200))

        let moved = PSMTabDragAssistant.shared().dragTabWindowFrame
        XCTAssertEqual(moved.origin.x - start.origin.x, 160, accuracy: 1.0,
                       "the drag image did not follow the pointer's 160pt travel")
    }

    // Successive updates keep tracking, and a repeat of the same position is
    // ignored (the real display link fires ~60x/sec whether or not the pointer
    // moved, so this dedupe is what keeps it cheap).
    func testRepeatedPointerPositionIsIgnored() {
        let (chip, members) = makeGroupedBar()
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: mouseDownEvent(at: NSPoint(x: 20, y: 12)))
        PSMTabDragAssistant.shared().draggingBegan(at: NSPoint(x: 200, y: 200))

        dragDriver.simulateMouseDrag(through: [NSPoint(x: 260, y: 200),
                                               NSPoint(x: 320, y: 200)])
        let afterDrag = PSMTabDragAssistant.shared().dragTabWindowFrame
        dragDriver.simulateMouseMove(to: NSPoint(x: 320, y: 200))

        XCTAssertEqual(PSMTabDragAssistant.shared().dragTabWindowFrame, afterDrag)
    }

    // Regression guard for the suite-wide hang: these tests must never arm a
    // real NSCoreDragManager session. One that is armed here does not start
    // here -- it starts inside whatever later test first pumps the run loop,
    // and blocks it forever waiting for a mouse-up that never comes.
    func testDragTestsNeverArmARealDraggingSession() {
        let (chip, members) = makeGroupedBar()
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: mouseDownEvent(at: NSPoint(x: 20, y: 12)))

        XCTAssertTrue(PSMTabDragAssistant.shared().dragSessionDriver === dragDriver,
                      "something replaced the fake driver; a real drag session would hang a later test")
    }

}

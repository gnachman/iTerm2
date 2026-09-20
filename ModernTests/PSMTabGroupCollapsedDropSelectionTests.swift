//
//  PSMTabGroupCollapsedDropSelectionTests.swift
//  iTerm2XCTests
//
//  Selection handling when a single tab is dropped into a COLLAPSED tab group.
//  A collapsed group can never hold the active tab (PseudoTerminal enforces that
//  invariant by expanding a group the moment the active tab lands in it). So the
//  rule after an in-bar drop is:
//
//    * the dragged tab WAS the active tab  -> select it, which expands the group
//    * the dragged tab was a background tab -> restore the previously-active tab
//      so the group stays collapsed (the dropped tab becomes a hidden member)
//
//  -keepCollapsedByRestoringSelectionAfterInBarDropOf: makes exactly that
//  decision, using the pre-drag active tab captured by -mouseDown:. These tests
//  drive the real -mouseDown: capture (so the "was it active" bit is produced the
//  way production produces it) and then exercise the decision.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupCollapsedDropSelectionTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var tabView: NSTabView!
    private var items: [NSTabViewItem] = []

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.contentView?.wantsLayer = true
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 600, height: 24))
        control.selectsTabsOnMouseDown = true
        window.contentView?.addSubview(control)
        tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 600, height: 350))
        window.contentView?.addSubview(tabView)
        control.tabView = tabView
    }

    func testProjectFilterPreservesTabsAndGroupCollapseState() {
        let bar = buildBar()
        let count = tabView.numberOfTabViewItems
        control.projectTabViewItems = Set([bar.solo])
        XCTAssertTrue(bar.draggedCell.isHiddenInBar)
        XCTAssertFalse((control.cells() as! [PSMTabBarCell]).first { $0.representedObject as? NSTabViewItem === bar.solo }!.isHiddenInBar)
        XCTAssertEqual(tabView.numberOfTabViewItems, count)
        let chips = (control.cells() as! [PSMTabBarCell]).filter { $0.isTabGroupChip }
        XCTAssertTrue(chips.allSatisfy { $0.isProjectHidden })
        XCTAssertEqual(bar.draggedCell.frame.width, 0)
        XCTAssertFalse(bar.draggedCell.isCollapsedHidden)
        bar.draggedCell.isCollapsedHidden = true
        control.projectTabViewItems = nil
        XCTAssertTrue(bar.draggedCell.isCollapsedHidden)
        XCTAssertTrue(bar.draggedCell.isHiddenInBar)
        bar.draggedCell.isCollapsedHidden = false
        XCTAssertFalse(bar.draggedCell.isHiddenInBar)
    }

    override func tearDown() {
        PSMTabDragAssistant.shared().finishDrag()
        items = []
        tabView = nil
        control = nil
        window = nil
        super.tearDown()
    }

    // Build a bar: one ungrouped tab "solo", the tab "dragged" that the test
    // moves, then a two-member group "G". Every tab gets a real NSTabViewItem in
    // the tab view (so selection works) and a matching cell (so -cellForPoint:
    // and -tabViewItemIsHiddenInBar: work). The group's chip has no tab view item.
    private func buildBar() -> (solo: NSTabViewItem, dragged: NSTabViewItem, m0: NSTabViewItem, m1: NSTabViewItem, draggedCell: PSMTabBarCell) {
        let cells = NSMutableArray()
        var x: CGFloat = 0
        func makeTab(_ groupID: String?, _ label: String) -> (NSTabViewItem, PSMTabBarCell) {
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            tabView.addTabViewItem(item)
            items.append(item)
            let cell = PSMTabBarCell(controlView: control)!
            cell.tabGroupIdentifier = groupID
            cell.representedObject = item
            cell.frame = NSRect(x: x, y: 0, width: 120, height: 24)
            x += 120
            cells.add(cell)
            return (item, cell)
        }

        let (solo, _) = makeTab(nil, "solo")
        let (dragged, draggedCell) = makeTab(nil, "dragged")

        let chip = PSMTabBarCell(controlView: control)!
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "G"
        chip.frame = NSRect(x: x, y: 0, width: 40, height: 24)
        x += 40
        cells.add(chip)

        let (m0, _) = makeTab("G", "m0")
        let (m1, _) = makeTab("G", "m1")

        control.cells().setArray(cells as [AnyObject])
        return (solo, dragged, m0, m1, draggedCell)
    }

    private func mouseDown(on cell: PSMTabBarCell) {
        let center = NSPoint(x: cell.frame.midX, y: cell.frame.midY)
        let inWindow = control.convert(center, to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                       location: inWindow,
                                       modifierFlags: [],
                                       timestamp: 0,
                                       windowNumber: window.windowNumber,
                                       context: nil,
                                       eventNumber: 0,
                                       clickCount: 1,
                                       pressure: 1)!
        control.mouseDown(with: event)
    }

    // Mark `hidden` items' cells as collapsed-hidden (as a group collapse would),
    // leaving the rest drawn. Mirrors the post-drop model state the reselect
    // decision reads.
    private func setCollapsed(_ hiddenItems: [NSTabViewItem]) {
        for cell in control.cells() as! [PSMTabBarCell] {
            guard let object = cell.representedObject as? NSTabViewItem else { continue }
            cell.isCollapsedHidden = hiddenItems.contains(object)
        }
    }

    // A BACKGROUND tab dropped into a collapsed group keeps the group collapsed:
    // the previously-active tab is restored, not the dropped one.
    func testBackgroundTabDroppedIntoCollapsedGroupRestoresPreviousSelection() {
        let (solo, dragged, m0, m1, draggedCell) = buildBar()
        tabView.selectTabViewItem(solo)  // "solo" is the active tab

        // Grab the background tab to drag it (production selects it on mouse-down
        // and records that "solo" was the pre-drag active tab).
        mouseDown(on: draggedCell)
        XCTAssertEqual(tabView.selectedTabViewItem, dragged,
                       "mouse-down on a background tab should switch to it")

        // It landed as a hidden member of the now-joined collapsed group.
        setCollapsed([m0, m1, dragged])

        let restored = control.keepCollapsed(afterInBarDropOf: dragged, draggedFromBar: control, destinationPreDropSelection: nil)
        XCTAssertTrue(restored, "a background tab dropped into a collapsed group must restore the pre-drag selection")
        XCTAssertEqual(tabView.selectedTabViewItem, solo,
                       "the previously-active tab must be reselected so the group stays collapsed")
    }

    // The ACTIVE tab dropped into a collapsed group is NOT kept collapsed: the
    // caller selects it, which expands the group.
    func testActiveTabDroppedIntoCollapsedGroupIsNotRestored() {
        let (_, dragged, m0, m1, draggedCell) = buildBar()
        tabView.selectTabViewItem(dragged)  // the dragged tab IS the active tab
        draggedCell.state = .on

        mouseDown(on: draggedCell)

        setCollapsed([m0, m1, dragged])

        let restored = control.keepCollapsed(afterInBarDropOf: dragged, draggedFromBar: control, destinationPreDropSelection: nil)
        XCTAssertFalse(restored, "the active tab must not be kept collapsed; the caller selects it and the group expands")
    }

    // A background tab dropped OUTSIDE any collapsed group behaves as before: the
    // caller selects the dropped tab (no restore).
    func testBackgroundTabDroppedOutsideCollapsedGroupIsNotRestored() {
        let (solo, dragged, _, _, draggedCell) = buildBar()
        tabView.selectTabViewItem(solo)

        mouseDown(on: draggedCell)

        // The dropped tab is still drawn in the bar (it joined no collapsed group).
        setCollapsed([])

        let restored = control.keepCollapsed(afterInBarDropOf: dragged, draggedFromBar: control, destinationPreDropSelection: nil)
        XCTAssertFalse(restored, "a drop that did not land in a collapsed group must select the dropped tab as before")
    }

    // Same as the first test but with select-on-mouse-down OFF: mouse-down does not
    // switch to the dragged tab, so the pre-drag active tab stays selected. A
    // background tab dropped into a collapsed group must STILL keep it collapsed --
    // the behavior must not silently depend on that advanced setting.
    func testBackgroundTabDroppedIntoCollapsedGroupKeepsCollapsedWithSelectOnMouseDownOff() {
        control.selectsTabsOnMouseDown = false
        let (solo, dragged, m0, m1, draggedCell) = buildBar()
        tabView.selectTabViewItem(solo)  // "solo" active; mouse-down won't change it

        mouseDown(on: draggedCell)
        XCTAssertEqual(tabView.selectedTabViewItem, solo,
                       "with select-on-mouse-down off, mouse-down must not change the selection")

        setCollapsed([m0, m1, dragged])

        let kept = control.keepCollapsed(afterInBarDropOf: dragged, draggedFromBar: control, destinationPreDropSelection: nil)
        XCTAssertTrue(kept, "a background tab dropped into a collapsed group must keep it collapsed even with select-on-mouse-down off")
        XCTAssertEqual(tabView.selectedTabViewItem, solo,
                       "the active tab must remain selected so the group stays collapsed")
    }

    // A second bar/tab view standing in for another window's tab bar.
    private func makeDestinationBar() -> (bar: PSMTabBarControl, tabView: NSTabView, active: NSTabViewItem, chip: PSMTabBarCell) {
        let destTabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 600, height: 350))
        window.contentView?.addSubview(destTabView)
        let destBar = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 600, height: 24))
        destBar.selectsTabsOnMouseDown = true
        window.contentView?.addSubview(destBar)
        destBar.tabView = destTabView

        let cells = NSMutableArray()
        let ownItem = NSTabViewItem(identifier: "destOwn" as NSString)
        ownItem.label = "destOwn"
        destTabView.addTabViewItem(ownItem)
        items.append(ownItem)
        let ownCell = PSMTabBarCell(controlView: destBar)!
        ownCell.representedObject = ownItem
        ownCell.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        cells.add(ownCell)

        let chip = PSMTabBarCell(controlView: destBar)!
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "H"
        chip.frame = NSRect(x: 120, y: 0, width: 40, height: 24)
        cells.add(chip)

        destBar.cells().setArray(cells as [AnyObject])
        destTabView.selectTabViewItem(ownItem)   // the destination's own active tab
        return (destBar, destTabView, ownItem, chip)
    }

    // Move `dragged` from the source bar into the destination bar's collapsed group
    // "H" as a hidden member (mirrors what the drop machinery does before
    // keepCollapsed runs). Crucially this mirrors production by SELECTING the dropped
    // tab in the destination (as -reallyPerformDragOperation:'s cross-window move
    // does), so the keep-collapsed logic is exercised against the real selection
    // state -- not a friendlier one that hides the bug.
    private func landInDestination(_ dragged: NSTabViewItem, _ draggedCell: PSMTabBarCell,
                                   dest: PSMTabBarControl, destTabView: NSTabView) {
        tabView.removeTabViewItem(dragged)
        destTabView.addTabViewItem(dragged)
        draggedCell.tabGroupIdentifier = "H"
        draggedCell.isCollapsedHidden = true
        let cells = dest.cells().mutableCopy() as! NSMutableArray
        cells.add(draggedCell)
        dest.cells().setArray(cells as [AnyObject])
        destTabView.selectTabViewItem(dragged)   // production selects the dropped tab here
    }

    // THE CROSS-WINDOW BUG: dragging a BACKGROUND tab from window A into a collapsed
    // group in window B must keep B's group collapsed -- the same as same-window.
    // The decision must read the SOURCE bar's pre-drag selection, and restore the
    // DESTINATION's own active tab (the drop already selected the dropped tab there).
    func testBackgroundTabDroppedCrossWindowKeepsGroupCollapsed() {
        let (solo, dragged, _, _, draggedCell) = buildBar()
        tabView.selectTabViewItem(solo)          // source active = solo (not dragged)
        mouseDown(on: draggedCell)               // grab the background tab in the source
        XCTAssertEqual(tabView.selectedTabViewItem, dragged)

        let dest = makeDestinationBar()
        let destPreDrop = dest.tabView.selectedTabViewItem   // capture BEFORE the drop selects
        landInDestination(dragged, draggedCell, dest: dest.bar, destTabView: dest.tabView)
        XCTAssertEqual(dest.tabView.selectedTabViewItem, dragged,
                       "precondition: production selects the dropped tab in the destination")

        let kept = dest.bar.keepCollapsed(afterInBarDropOf: dragged, draggedFromBar: control,
                                          destinationPreDropSelection: destPreDrop)
        XCTAssertTrue(kept, "a background tab dropped cross-window into a collapsed group must keep it collapsed")
        XCTAssertEqual(dest.tabView.selectedTabViewItem, dest.active,
                       "the destination's own active tab must be restored (dropped tab must not stay selected)")
    }

    // Mirror: dragging the SOURCE's ACTIVE tab cross-window into a collapsed group
    // must NOT keep it collapsed (the caller selects it, expanding the group).
    func testActiveTabDroppedCrossWindowExpands() {
        let (_, dragged, _, _, draggedCell) = buildBar()
        tabView.selectTabViewItem(dragged)       // the dragged tab IS the source active
        draggedCell.state = .on
        mouseDown(on: draggedCell)               // pre-drag active == dragged -> nil capture

        let dest = makeDestinationBar()
        let destPreDrop = dest.tabView.selectedTabViewItem
        landInDestination(dragged, draggedCell, dest: dest.bar, destTabView: dest.tabView)

        let kept = dest.bar.keepCollapsed(afterInBarDropOf: dragged, draggedFromBar: control,
                                          destinationPreDropSelection: destPreDrop)
        XCTAssertFalse(kept, "dragging the active tab cross-window into a collapsed group must expand it (caller selects the dropped tab)")
    }
}

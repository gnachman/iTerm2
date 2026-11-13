//
//  PSMTabMultiSelectionTests.swift
//  iTerm2XCTests
//
//  Shift-clicking tabs selects a range, as in Chrome: every tab from the
//  anchor (the tab that was active when the selection began) through the
//  clicked tab is selected, and the clicked tab becomes active. Later
//  Shift-clicks move the far end of the range and keep the anchor. A click
//  without Shift, or any other change of the active tab, ends the selection.
//  These tests drive the real -mouseDown:/-mouseUp: handlers on a bar laid out
//  from a real NSTabView.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabMultiSelectionTests: XCTestCase {
    private var window: NSWindow!
    private var tabView: NSTabView!
    private var control: PSMTabBarControl!
    private var items: [NSTabViewItem] = []

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.contentView?.wantsLayer = true
        tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 1000, height: 376))
        tabView.tabViewType = .noTabsNoBorder
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 1000, height: 24))
        control.selectsTabsOnMouseDown = true
        control.tabView = tabView
        tabView.delegate = control
        window.contentView?.addSubview(tabView)
        window.contentView?.addSubview(control)
        for i in 0..<5 {
            let item = NSTabViewItem(identifier: "tab \(i)" as NSString)
            item.label = "Tab \(i)"
            item.view = NSView()
            tabView.addTabViewItem(item)
            items.append(item)
        }
        control.updateWithoutAnimation()
    }

    override func tearDown() {
        items = []
        control = nil
        tabView = nil
        window = nil
        super.tearDown()
    }

    private func cell(for item: NSTabViewItem) -> PSMTabBarCell {
        let cells = control.cells().compactMap { $0 as? PSMTabBarCell }
        return cells.first { $0.representedObject as? NSTabViewItem === item && !$0.isTabGroupChip }!
    }

    // A complete click (down and up) in the middle of `item`'s tab. The keys in
    // `modifiers` are held for the whole click unless `upModifiers` says which
    // are still held when the button comes up.
    private func click(_ item: NSTabViewItem,
                       modifiers: NSEvent.ModifierFlags = [],
                       upModifiers: NSEvent.ModifierFlags? = nil) {
        control.updateWithoutAnimation()
        let frame = cell(for: item).frame
        XCTAssertFalse(frame.isEmpty, "\(item.label) has no frame to click")
        let location = control.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            return NSEvent.mouseEvent(with: type,
                                      location: location,
                                      modifierFlags: flags,
                                      timestamp: 0,
                                      windowNumber: window.windowNumber,
                                      context: nil,
                                      eventNumber: 0,
                                      clickCount: 1,
                                      pressure: 1)!
        }
        control.mouseDown(with: event(.leftMouseDown, modifiers))
        control.mouseUp(with: event(.leftMouseUp, upModifiers ?? modifiers))
    }

    private func shiftClick(_ item: NSTabViewItem) {
        click(item, modifiers: .shift)
    }

    private var selectedLabels: [String] {
        return control.multiSelectedTabViewItems.map { $0.label }
    }

    // MARK: - Making a range

    func testShiftClickSelectsRangeFromActiveTabAndActivatesClickedTab() {
        tabView.selectTabViewItem(items[1])
        shiftClick(items[3])
        XCTAssertEqual(selectedLabels, ["Tab 1", "Tab 2", "Tab 3"])
        XCTAssertTrue(tabView.selectedTabViewItem === items[3])
    }

    func testShiftClickToTheLeftSelectsRangeInBarOrder() {
        tabView.selectTabViewItem(items[3])
        shiftClick(items[1])
        XCTAssertEqual(selectedLabels, ["Tab 1", "Tab 2", "Tab 3"])
        XCTAssertTrue(tabView.selectedTabViewItem === items[1])
    }

    func testLaterShiftClickKeepsTheAnchor() {
        tabView.selectTabViewItem(items[2])
        shiftClick(items[4])
        XCTAssertEqual(selectedLabels, ["Tab 2", "Tab 3", "Tab 4"])
        // The range now runs from the anchor (Tab 2), not from the active tab
        // (Tab 4), to the newly clicked tab.
        shiftClick(items[0])
        XCTAssertEqual(selectedLabels, ["Tab 0", "Tab 1", "Tab 2"])
        XCTAssertTrue(tabView.selectedTabViewItem === items[0])
    }

    func testShiftClickOnTheActiveTabSelectsOnlyIt() {
        tabView.selectTabViewItem(items[2])
        shiftClick(items[2])
        XCTAssertEqual(selectedLabels, [])
        XCTAssertTrue(tabView.selectedTabViewItem === items[2])
    }

    func testShiftClickOnTheAnchorEndsTheSelection() {
        tabView.selectTabViewItem(items[1])
        shiftClick(items[3])
        shiftClick(items[1])
        XCTAssertEqual(selectedLabels, [])
        XCTAssertTrue(tabView.selectedTabViewItem === items[1])
    }

    func testShiftClickWorksWhenTabsAreSelectedOnMouseUp() {
        control.selectsTabsOnMouseDown = false
        tabView.selectTabViewItem(items[0])
        shiftClick(items[2])
        XCTAssertEqual(selectedLabels, ["Tab 0", "Tab 1", "Tab 2"])
        XCTAssertTrue(tabView.selectedTabViewItem === items[2])
    }

    func testLettingGoOfShiftBeforeTheButtonStillExtendsTheSelection() {
        // Shift is read when the button goes down, whichever of mouse-down or
        // mouse-up selects the tab.
        for selectsOnMouseDown in [true, false] {
            control.selectsTabsOnMouseDown = selectsOnMouseDown
            click(items[0])
            click(items[2], modifiers: .shift, upModifiers: [])
            XCTAssertEqual(selectedLabels, ["Tab 0", "Tab 1", "Tab 2"],
                           "selectsTabsOnMouseDown=\(selectsOnMouseDown)")
            XCTAssertTrue(tabView.selectedTabViewItem === items[2])
        }
    }

    // MARK: - Ending a range

    func testPlainClickOnAnotherSelectedTabEndsTheSelection() {
        tabView.selectTabViewItem(items[1])
        shiftClick(items[3])
        click(items[2])
        XCTAssertEqual(selectedLabels, [])
        XCTAssertTrue(tabView.selectedTabViewItem === items[2])
    }

    func testPlainClickOnTheActiveTabEndsTheSelection() {
        // The tab view does not report re-selecting the active tab, so this is
        // ended by the click itself.
        tabView.selectTabViewItem(items[1])
        shiftClick(items[3])
        click(items[3])
        XCTAssertEqual(selectedLabels, [])
        XCTAssertTrue(tabView.selectedTabViewItem === items[3])
    }

    func testSelectingATabAnotherWayEndsTheSelection() {
        tabView.selectTabViewItem(items[1])
        shiftClick(items[3])
        tabView.selectTabViewItem(items[0])
        XCTAssertEqual(selectedLabels, [])
    }

    func testAfterTheSelectionEndsTheNextShiftClickAnchorsAtTheActiveTab() {
        tabView.selectTabViewItem(items[0])
        shiftClick(items[1])
        click(items[3])
        shiftClick(items[4])
        XCTAssertEqual(selectedLabels, ["Tab 3", "Tab 4"])
    }

    func testMovingATabEndsTheSelection() {
        // Moving the active tab and moving one of the others behave the same.
        for moved in [3, 2] {
            tabView.selectTabViewItem(items[1])
            shiftClick(items[3])
            XCTAssertEqual(selectedLabels.count, 3)
            control.moveTab(at: tabView.indexOfTabViewItem(items[moved]), to: 4)
            XCTAssertEqual(selectedLabels, [], "moved Tab \(moved)")
            control.moveTab(at: 4, to: moved)
        }
    }

    func testClosingASelectedTabLeavesTheRestSelected() {
        tabView.selectTabViewItem(items[0])
        shiftClick(items[2])
        tabView.removeTabViewItem(items[1])
        control.updateWithoutAnimation()
        XCTAssertEqual(selectedLabels, ["Tab 0", "Tab 2"])
    }

    func testClearTabMultiSelection() {
        tabView.selectTabViewItem(items[1])
        shiftClick(items[3])
        control.clearTabMultiSelection()
        XCTAssertEqual(selectedLabels, [])
        XCTAssertTrue(tabView.selectedTabViewItem === items[3])
    }

    // MARK: - Hidden tabs

    func testRangeLeavesOutTabsHiddenInACollapsedGroup() {
        cell(for: items[1]).isCollapsedHidden = true
        cell(for: items[2]).isCollapsedHidden = true
        let range = control.selectableTabCells(from: cell(for: items[0]), to: cell(for: items[3]))
        XCTAssertEqual(range.map { ($0.representedObject as! NSTabViewItem).label }, ["Tab 0", "Tab 3"])
    }

    func testTabThatBecomesHiddenDropsOutOfTheSelection() {
        tabView.selectTabViewItem(items[0])
        shiftClick(items[2])
        cell(for: items[1]).isCollapsedHidden = true
        XCTAssertEqual(selectedLabels, ["Tab 0", "Tab 2"])
        // With only one tab left in view it is no longer a multiple selection.
        cell(for: items[0]).isCollapsedHidden = true
        XCTAssertEqual(selectedLabels, [])
    }

    func testCollapsingAGroupDeselectsItsTabsForGood() {
        tabView.selectTabViewItem(items[0])
        shiftClick(items[3])
        let hidden = [items[1], items[2]]
        control.setTabGroupCollapsedFlags([NSNumber(value: true), NSNumber(value: true)], for: hidden)
        control.updateWithoutAnimation()
        XCTAssertEqual(selectedLabels, ["Tab 0", "Tab 3"])
        // Expanding the group shows its tabs again but does not reselect them.
        control.setTabGroupCollapsedFlags([NSNumber(value: false), NSNumber(value: false)], for: hidden)
        control.updateWithoutAnimation()
        XCTAssertEqual(selectedLabels, ["Tab 0", "Tab 3"])
    }

    func testRangeIsEmptyForACellNotInTheBar() {
        let stranger = PSMTabBarCell(controlView: control)!
        XCTAssertEqual(control.selectableTabCells(from: cell(for: items[0]), to: stranger).count, 0)
    }
}

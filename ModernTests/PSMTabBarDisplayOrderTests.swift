//
//  PSMTabBarDisplayOrderTests.swift
//  ModernTests
//
//  A tab bar can show tabs in an order other than the tab view's, as a
//  vertical bar sorted by status or working directory does. Only where cells
//  go changes: the tab view's order is untouched.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabBarDisplayOrderTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var tabView: NSTabView!

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        control.style.tabBar = control
        control.orientation = .verticalOrientation
        window.contentView?.addSubview(control)
        tabView = NSTabView(frame: NSRect(x: 200, y: 0, width: 400, height: 400))
        window.contentView?.addSubview(tabView)
        control.tabView = tabView
        tabView.delegate = control
    }

    override func tearDown() {
        tabView = nil
        control = nil
        window = nil
        super.tearDown()
    }

    @discardableResult
    private func addTabs(_ labels: [String]) -> [NSTabViewItem] {
        return labels.map { label in
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            tabView.addTabViewItem(item)
            return item
        }
    }

    // What the bar shows, top to bottom: a tab's label, or a chip's group.
    private var shown: [String] {
        let cells = control.cells() as? [PSMTabBarCell] ?? []
        return cells.map { cell in
            if cell.isTabGroupChip {
                return "[\(cell.tabGroupIdentifier ?? "")]"
            }
            return (cell.representedObject as? NSTabViewItem)?.label ?? "?"
        }
    }

    private var tabOrder: [String] {
        return tabView.tabViewItems.map(\.label)
    }

    private func items(_ labels: [String]) -> [NSTabViewItem] {
        return labels.map { label in tabView.tabViewItems.first { $0.label == label }! }
    }

    func testCellsFollowTheDisplayOrder() {
        addTabs(["a", "b", "c"])
        XCTAssertEqual(shown, ["a", "b", "c"])
        control.displayOrder = items(["c", "a", "b"])
        XCTAssertEqual(shown, ["c", "a", "b"])
        XCTAssertEqual(tabOrder, ["a", "b", "c"], "the tab view's order is unchanged")
        control.displayOrder = nil
        XCTAssertEqual(shown, ["a", "b", "c"])
    }

    func testCellsAreLaidOutInTheDisplayOrder() {
        addTabs(["a", "b", "c"])
        control.displayOrder = items(["c", "a", "b"])
        control.updateWithoutAnimation()
        let cells = control.cells() as? [PSMTabBarCell] ?? []
        let ys = cells.map(\.frame.minY)
        XCTAssertEqual(ys, ys.sorted(), "top to bottom in the display order")
        XCTAssertEqual(cells.map { ($0.representedObject as? NSTabViewItem)?.label }, ["c", "a", "b"])
    }

    // Adding or removing a tab matches cells to tabs by position, in tab view
    // order. The display order must survive it.
    func testAddingATabKeepsTheDisplayOrder() {
        addTabs(["a", "b", "c"])
        control.displayOrder = items(["c", "a", "b"])
        addTabs(["d"])
        XCTAssertEqual(shown, ["c", "a", "b", "d"], "an unlisted tab goes after the rest")
        control.displayOrder = items(["d", "c", "a", "b"])
        XCTAssertEqual(shown, ["d", "c", "a", "b"])
    }

    func testInsertingATabInTheMiddleMatchesCellsToTheRightTabs() {
        addTabs(["a", "b", "c"])
        control.displayOrder = items(["c", "b", "a"])
        let inserted = NSTabViewItem(identifier: "x" as NSString)
        inserted.label = "x"
        tabView.insertTabViewItem(inserted, at: 1)
        XCTAssertEqual(tabOrder, ["a", "x", "b", "c"])
        XCTAssertEqual(shown, ["c", "b", "a", "x"])
        let cells = control.cells() as? [PSMTabBarCell] ?? []
        XCTAssertEqual(Set(cells.compactMap { $0.representedObject as? NSTabViewItem }.map(\.label)),
                       ["a", "x", "b", "c"], "one cell per tab")
    }

    func testRemovingATabKeepsTheDisplayOrder() {
        addTabs(["a", "b", "c", "d"])
        control.displayOrder = items(["d", "b", "c", "a"])
        tabView.removeTabViewItem(items(["b"])[0])
        XCTAssertEqual(shown, ["d", "c", "a"])
    }

    func testMovingATabInTheTabViewKeepsTheDisplayOrder() {
        addTabs(["a", "b", "c"])
        control.displayOrder = items(["c", "a", "b"])
        control.moveTab(at: 0, to: 2)
        XCTAssertEqual(tabOrder, ["b", "c", "a"])
        XCTAssertEqual(shown, ["c", "a", "b"])
    }

    // Sections are drawn as groups, so chips must head runs in the display
    // order.
    func testGroupChipsHeadRunsInTheDisplayOrder() {
        let all = addTabs(["a", "b", "c", "d"])
        control.displayOrder = items(["b", "d", "a", "c"])
        control.setTabGroupIdentifiers(["s2", "s1", "s2", "s1"], for: all)
        XCTAssertEqual(shown, ["[s1]", "b", "d", "[s2]", "a", "c"])
        control.setTabGroupIdentifiers([NSNull(), NSNull(), NSNull(), NSNull()], for: all)
        control.displayOrder = nil
        XCTAssertEqual(shown, ["a", "b", "c", "d"])
    }
}

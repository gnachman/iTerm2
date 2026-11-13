//
//  TabMultiSelectionGroupingTests.swift
//  ModernTests
//
//  After Shift-clicking several tabs, the tab group items in the context menu
//  of one of them act on all of them: Add Tabs to Group puts every selected tab
//  in the chosen group (each taking on the group's pinned state, as a single
//  tab does), and Remove Tabs from Group takes them all out. A menu opened on a
//  tab outside the selection still acts on that one tab.
//

import XCTest
@testable import iTerm2SharedARC

final class TabMultiSelectionGroupingTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        for _ in 0..<3 {
            fixture.addTab()
        }
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    private var terminal: PseudoTerminal {
        return fixture.terminal
    }

    private var tabs: [PTYTab] {
        return terminal.tabs() ?? []
    }

    private var tabBar: PSMTabBarControl {
        guard let tabBar = terminal.tabBarControl() else {
            it_fatalError("No tab bar")
        }
        return tabBar
    }

    // A complete click (down and up) in the middle of `tab`'s cell in the tab bar.
    private func click(_ tab: PTYTab, modifiers: NSEvent.ModifierFlags = []) {
        let bar = tabBar
        bar.updateWithoutAnimation()
        let cells = bar.cells().compactMap { $0 as? PSMTabBarCell }
        guard let cell = cells.first(where: {
            ($0.representedObject as? NSTabViewItem) === tab.tabViewItem && !$0.isTabGroupChip
        }) else {
            XCTFail("No cell for tab")
            return
        }
        XCTAssertFalse(cell.frame.isEmpty, "The tab to click has no frame")
        let location = bar.convert(NSPoint(x: cell.frame.midX, y: cell.frame.midY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            return NSEvent.mouseEvent(with: type,
                                      location: location,
                                      modifierFlags: modifiers,
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: fixture.window.windowNumber,
                                      context: nil,
                                      eventNumber: 0,
                                      clickCount: 1,
                                      pressure: 1)!
        }
        bar.mouseDown(with: event(.leftMouseDown))
        bar.mouseUp(with: event(.leftMouseUp))
    }

    // Select `tabs[first]` through `tabs[last]` the way a user does: click the
    // first, then Shift-click the last.
    private func select(_ first: Int, through last: Int) {
        let all = tabs
        click(all[first])
        click(all[last], modifiers: .shift)
        XCTAssertEqual(tabBar.multiSelectedTabViewItems.count, abs(last - first) + 1)
    }

    private func contextMenu(for tab: PTYTab) -> NSMenu {
        guard let item = tab.tabViewItem,
              let tabView = item.tabView,
              let menu = terminal.tabView(tabView, menuFor: item) else {
            it_fatalError("No context menu")
        }
        return menu
    }

    // Menu titles are localized, so items are found by their action.
    private func items(in menu: NSMenu, action: String) -> [NSMenuItem] {
        var result = [NSMenuItem]()
        for item in menu.items {
            if item.action == NSSelectorFromString(action) {
                result.append(item)
            }
            if let submenu = item.submenu {
                result.append(contentsOf: items(in: submenu, action: action))
            }
        }
        return result
    }

    private func perform(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target as? NSObject else {
            XCTFail("Menu item has no action or target")
            return
        }
        _ = target.perform(action, with: item)
    }

    // New Group… first asks for a name in a modal dialog. These run what it
    // does once a name has been given.
    private func makeNewGroup(from item: NSMenuItem, named name: String) {
        _ = terminal.perform(NSSelectorFromString("addSelectedTabs:toNewGroupNamed:"),
                             with: item.representedObject,
                             with: name)
    }

    private func makeNewGroup(with tab: PTYTab, named name: String) {
        _ = terminal.perform(NSSelectorFromString("addTab:toNewGroupNamed:"), with: tab, with: name)
    }

    private func newGroupItem(in menu: NSMenu) -> NSMenuItem? {
        let found = items(in: menu, action: "addSelectedTabsToNewGroup:")
        XCTAssertEqual(found.count, 1)
        return found.first
    }

    private func groupAll(_ tabs: [PTYTab], id: String) {
        for tab in tabs {
            terminal.addTab(tab,
                            toTabGroupWithID: id,
                            name: "Old",
                            color: .systemBlue,
                            collapsed: false,
                            deferringExpansion: false)
        }
    }

    private func groupItem(in menu: NSMenu, groupID: String) -> NSMenuItem? {
        return items(in: menu, action: "addSelectedTabsToExistingGroup:").first {
            ($0.representedObject as? [String: Any])?["group"] as? String == groupID
        }
    }

    // MARK: - Tests

    func testMenuOnASelectedTabActsOnTheSelection() {
        select(1, through: 3)
        let menu = contextMenu(for: tabs[2])
        XCTAssertEqual(items(in: menu, action: "addSelectedTabsToNewGroup:").count, 1)
        XCTAssertEqual(items(in: menu, action: "addTabToNewGroup:").count, 0)
    }

    func testMenuOnATabOutsideTheSelectionActsOnThatTab() {
        select(1, through: 2)
        let menu = contextMenu(for: tabs[3])
        XCTAssertEqual(items(in: menu, action: "addTabToNewGroup:").count, 1)
        XCTAssertEqual(items(in: menu, action: "addSelectedTabsToNewGroup:").count, 0)
    }

    func testNewGroupFromTheSelection() {
        let all = tabs
        select(1, through: 3)
        guard let item = newGroupItem(in: contextMenu(for: all[2])) else {
            return
        }
        makeNewGroup(from: item, named: "Work")

        guard let groupID = all[2].tabGroupID else {
            XCTFail("The right-clicked tab is not in a group")
            return
        }
        XCTAssertEqual(tabs.map { $0.tabGroupID }, [nil, groupID, groupID, groupID])
        XCTAssertTrue(tabs.elementsEqual(all, by: ===))
        XCTAssertEqual(all[1].tabGroupName, "Work")
        XCTAssertEqual(all[3].tabGroupName, "Work")
        XCTAssertEqual(all[1].tabGroupColor, all[2].tabGroupColor)
        XCTAssertEqual(tabBar.multiSelectedTabViewItems.count, 0)
    }

    func testNewGroupFromPartOfAGroupKeepsTheOldGroupTogether() {
        let all = tabs
        groupAll(all, id: "G")
        select(1, through: 2)
        guard let item = newGroupItem(in: contextMenu(for: all[1])) else {
            return
        }
        makeNewGroup(from: item, named: "New")

        guard let newID = all[1].tabGroupID, newID != "G" else {
            XCTFail("The selected tabs did not get a new group")
            return
        }
        // The old group closes up around the tabs that left it.
        XCTAssertEqual(tabs.map { $0.tabGroupID }, ["G", "G", newID, newID])
        XCTAssertTrue(tabs[0] === all[0])
        XCTAssertTrue(tabs[1] === all[3])
        XCTAssertTrue(tabs[2] === all[1])
        XCTAssertTrue(tabs[3] === all[2])
    }

    func testNewGroupForOneTabKeepsItsOldGroupTogether() {
        // The single-tab New Group… shares the code above, so it also repairs
        // the order of the group the tab leaves.
        let all = tabs
        groupAll(all, id: "G")
        makeNewGroup(with: all[1], named: "New")

        guard let newID = all[1].tabGroupID, newID != "G" else {
            XCTFail("The tab did not get a new group")
            return
        }
        XCTAssertEqual(all[1].tabGroupName, "New")
        XCTAssertEqual(tabs.map { $0.tabGroupID }, ["G", "G", "G", newID])
        XCTAssertTrue(tabs[0] === all[0])
        XCTAssertTrue(tabs[1] === all[2])
        XCTAssertTrue(tabs[2] === all[3])
        XCTAssertTrue(tabs[3] === all[1])
    }

    func testAddSelectedTabsToExistingGroup() {
        let all = tabs
        terminal.addTab(all[0],
                        toTabGroupWithID: "G",
                        name: "Work",
                        color: .systemBlue,
                        collapsed: false,
                        deferringExpansion: false)
        select(2, through: 3)
        guard let item = groupItem(in: contextMenu(for: all[3]), groupID: "G") else {
            XCTFail("No menu item for group G")
            return
        }
        XCTAssertEqual(item.state, .off)
        perform(item)

        XCTAssertEqual(tabs.map { $0.tabGroupID }, ["G", "G", "G", nil])
        XCTAssertTrue(tabs[0] === all[0])
        XCTAssertTrue(tabs[1] === all[2])
        XCTAssertTrue(tabs[2] === all[3])
        XCTAssertTrue(tabs[3] === all[1])
        XCTAssertEqual(all[2].tabGroupName, "Work")
        XCTAssertEqual(all[3].tabGroupName, "Work")
        XCTAssertEqual(tabBar.multiSelectedTabViewItems.count, 0)
    }

    func testGroupItemIsMixedWhenSomeSelectedTabsAreMembers() {
        let all = tabs
        terminal.addTab(all[1],
                        toTabGroupWithID: "G",
                        name: "Work",
                        color: .systemBlue,
                        collapsed: false,
                        deferringExpansion: false)
        select(1, through: 2)
        XCTAssertEqual(groupItem(in: contextMenu(for: all[2]), groupID: "G")?.state, .mixed)
    }

    func testRemoveSelectedTabsFromGroup() {
        let all = tabs
        groupAll(all, id: "G")
        select(0, through: 1)
        let removeItems = items(in: contextMenu(for: all[0]), action: "removeSelectedTabsFromGroup:")
        XCTAssertEqual(removeItems.count, 1)
        perform(removeItems[0])

        XCTAssertNil(all[0].tabGroupID)
        XCTAssertNil(all[1].tabGroupID)
        XCTAssertNil(all[0].tabGroupName)
        XCTAssertEqual(all[2].tabGroupID, "G")
        XCTAssertEqual(all[3].tabGroupID, "G")
        XCTAssertEqual(tabBar.multiSelectedTabViewItems.count, 0)
    }

    func testTabsJoiningAPinnedGroupArePinnedAndKeepTheirOrder() {
        let all = tabs
        all[0].isPinned = true
        terminal.addTab(all[0],
                        toTabGroupWithID: "G",
                        name: "Work",
                        color: .systemBlue,
                        collapsed: false,
                        deferringExpansion: false)
        select(1, through: 2)
        guard let item = groupItem(in: contextMenu(for: all[1]), groupID: "G") else {
            XCTFail("No menu item for group G")
            return
        }
        perform(item)

        XCTAssertEqual(tabs.map { $0.isPinned }, [true, true, true, false])
        XCTAssertTrue(tabs[0] === all[0])
        XCTAssertTrue(tabs[1] === all[1])
        XCTAssertTrue(tabs[2] === all[2])
        XCTAssertEqual(tabs.map { $0.tabGroupID }, ["G", "G", "G", nil])
    }

    func testTabsJoiningAnUnpinnedGroupAreUnpinnedAndKeepTheirOrder() {
        let all = tabs
        all[0].isPinned = true
        all[1].isPinned = true
        terminal.addTab(all[2],
                        toTabGroupWithID: "G",
                        name: "Work",
                        color: .systemBlue,
                        collapsed: false,
                        deferringExpansion: false)
        select(0, through: 1)
        guard let item = groupItem(in: contextMenu(for: all[0]), groupID: "G") else {
            XCTFail("No menu item for group G")
            return
        }
        perform(item)

        XCTAssertEqual(tabs.map { $0.isPinned }, [false, false, false, false])
        XCTAssertTrue(tabs[0] === all[0])
        XCTAssertTrue(tabs[1] === all[1])
        XCTAssertTrue(tabs[2] === all[2])
        XCTAssertEqual(tabs.map { $0.tabGroupID }, ["G", "G", "G", nil])
    }
}

//
//  TabGroupRestoreValidationTests.swift
//  ModernTests
//
//  A tab restored after the fact (undo close, or a workgroup reverting its
//  entry tab) brings back the group it was in then. Things may have changed
//  since: its parent may now be nested in another group or live in another
//  window, its group may have moved to another window, or its parent may have
//  been renamed. The restore keeps only what's still valid.
//

import XCTest
@testable import iTerm2SharedARC

final class TabGroupRestoreValidationTests: XCTestCase {
    private var fixtures: [TerminalWindowTestFixture] = []

    override func tearDown() {
        for fixture in fixtures {
            fixture.close()
        }
        fixtures = []
        super.tearDown()
    }

    private func makeWindow(tabs: Int) -> PseudoTerminal {
        let fixture = TerminalWindowTestFixture(engageLayoutEngine: false)
        fixtures.append(fixture)
        for _ in 1..<tabs {
            fixture.addTab()
        }
        return fixture.terminal
    }

    private func put(_ tab: PTYTab, inGroup groupID: String, name: String? = nil, parent parentID: String? = nil, parentName: String? = nil) {
        tab.tabGroupID = groupID
        tab.tabGroupName = name ?? groupID
        tab.tabGroupColor = .systemBlue
        if let parentID {
            tab.tabGroupParentID = parentID
            tab.tabGroupParentName = parentName ?? parentID
            tab.tabGroupParentColor = .systemRed
        }
    }

    // The tab comes back as the only tab of sub-group S of P.
    private func makeStale(_ tab: PTYTab, parentName: String = "P") {
        put(tab, inGroup: "S", parent: "P", parentName: parentName)
    }

    // [P: a] [Q: q] t, then P is nested in Q.
    private func makeWindowWithParentNestedInQ() -> (terminal: PseudoTerminal, a: PTYTab, t: PTYTab) {
        let terminal = makeWindow(tabs: 3)
        let tabs = terminal.tabs()!
        put(tabs[0], inGroup: "P")
        put(tabs[1], inGroup: "Q")
        terminal.tabsDidReorder()
        terminal.tabView(terminal.tabView(),
                         dropGroupWithID: "P",
                         members: [tabs[0].tabViewItem],
                         inTabBar: terminal.tabBarControl(),
                         before: tabs[2].tabViewItem,
                         parentGroupID: "Q")
        XCTAssertEqual(tabs[0].tabGroupParentID, "Q", "setup: P wasn't nested in Q")
        return (terminal, tabs[0], tabs[2])
    }

    func testParentSinceNestedElsewhereIsDropped() {
        let (terminal, _, t) = makeWindowWithParentNestedInQ()
        makeStale(t)
        terminal.validateRestoredTabGroup(of: t)
        XCTAssertEqual(t.tabGroupID, "S")
        XCTAssertNil(t.tabGroupParentID, "restoring made a group two levels deep")
    }

    func testParentSinceMovedToAnotherWindowIsDropped() {
        let terminal = makeWindow(tabs: 2)
        let other = makeWindow(tabs: 1)
        put(other.tabs()![0], inGroup: "P")
        other.tabsDidReorder()
        let t = terminal.tabs()![1]
        makeStale(t)
        terminal.validateRestoredTabGroup(of: t)
        XCTAssertEqual(t.tabGroupID, "S")
        XCTAssertNil(t.tabGroupParentID, "the parent's id now lives in two windows")
    }

    func testGroupSinceMovedToAnotherWindowIsDropped() {
        let terminal = makeWindow(tabs: 2)
        let other = makeWindow(tabs: 1)
        put(other.tabs()![0], inGroup: "G")
        other.tabsDidReorder()
        let t = terminal.tabs()![1]
        put(t, inGroup: "G")
        terminal.validateRestoredTabGroup(of: t)
        XCTAssertNil(t.tabGroupID, "the group's id now lives in two windows")
    }

    func testRenamedParentDefinitionIsAdopted() {
        let terminal = makeWindow(tabs: 2)
        let tabs = terminal.tabs()!
        put(tabs[0], inGroup: "P", name: "New Name")
        terminal.tabsDidReorder()
        makeStale(tabs[1], parentName: "Old Name")
        terminal.validateRestoredTabGroup(of: tabs[1])
        XCTAssertEqual(tabs[1].tabGroupParentID, "P")
        XCTAssertEqual(tabs[1].tabGroupParentName, "New Name")
    }

    func testValidParentIsKept() {
        let terminal = makeWindow(tabs: 2)
        let tabs = terminal.tabs()!
        put(tabs[0], inGroup: "P")
        terminal.tabsDidReorder()
        makeStale(tabs[1])
        terminal.validateRestoredTabGroup(of: tabs[1])
        XCTAssertEqual(tabs[1].tabGroupID, "S")
        XCTAssertEqual(tabs[1].tabGroupParentID, "P")
    }

    func testSnapshotParentSinceNestedElsewhereIsDropped() {
        let (terminal, _, t) = makeWindowWithParentNestedInQ()
        makeStale(t)
        let snapshot = terminal.tabGroupSnapshot(for: t)
        terminal.restoreTabGroupSnapshot(snapshot, for: t)
        XCTAssertEqual(t.tabGroupID, "S")
        XCTAssertNil(t.tabGroupParentID, "restoring made a group two levels deep")
    }
}

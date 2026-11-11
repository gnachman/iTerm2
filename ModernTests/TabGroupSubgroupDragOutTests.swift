//
//  TabGroupSubgroupDragOutTests.swift
//  ModernTests
//
//  Dragging a sub-group's chip out of its parent moves just the sub-group:
//  it becomes a top-level group, whether it lands elsewhere in the same
//  window, in another window, or torn off into a new one. That holds even
//  when the sub-group is its parent's only content, which leaves the parent
//  with no tabs, so it dissolves. Dragging the parent's chip in that shape
//  moves both, keeping the nesting.
//

import XCTest
@testable import iTerm2SharedARC

final class TabGroupSubgroupDragOutTests: XCTestCase {
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

    private func put(_ tab: PTYTab, inGroup groupID: String, parent parentID: String? = nil) {
        tab.tabGroupID = groupID
        tab.tabGroupName = groupID
        tab.tabGroupColor = .systemBlue
        if let parentID {
            tab.tabGroupParentID = parentID
            tab.tabGroupParentName = parentID
            tab.tabGroupParentColor = .systemRed
        }
    }

    // [P: [S: s1 s2]] x: S is P's only content.
    private func makeLoneSubgroupWindow() -> (terminal: PseudoTerminal, subgroup: [PTYTab], loner: PTYTab) {
        let terminal = makeWindow(tabs: 3)
        let tabs = terminal.tabs()!
        put(tabs[0], inGroup: "S", parent: "P")
        put(tabs[1], inGroup: "S", parent: "P")
        terminal.tabsDidReorder()
        return (terminal, Array(tabs[0...1]), tabs[2])
    }

    private func drop(_ subgroup: [PTYTab],
                      groupID: String = "S",
                      from source: PseudoTerminal,
                      into destination: PseudoTerminal,
                      before anchor: PTYTab?) {
        source.tabView(source.tabView(),
                       dropGroupWithID: groupID,
                       members: subgroup.map { $0.tabViewItem },
                       inTabBar: destination.tabBarControl(),
                       before: anchor?.tabViewItem,
                       parentGroupID: nil)
    }

    private func assertTopLevel(_ subgroup: [PTYTab], file: StaticString = #filePath, line: UInt = #line) {
        for tab in subgroup {
            XCTAssertEqual(tab.tabGroupID, "S", file: file, line: line)
            XCTAssertNil(tab.tabGroupParentID, "the sub-group kept its parent", file: file, line: line)
        }
    }

    private func assertStillNested(_ subgroup: [PTYTab], file: StaticString = #filePath, line: UInt = #line) {
        for tab in subgroup {
            XCTAssertEqual(tab.tabGroupID, "S", file: file, line: line)
            XCTAssertEqual(tab.tabGroupParentID, "P", "the parent was dropped", file: file, line: line)
        }
    }

    private func tearOff(_ groupID: String, members: [PTYTab], from terminal: PseudoTerminal) -> PseudoTerminal? {
        terminal.tabView(terminal.tabView(),
                         tearOffGroupWithID: groupID,
                         members: members.map { $0.tabViewItem },
                         atScreenPoint: NSPoint(x: 200, y: 600))
        return iTermController.sharedInstance()?.terminal(with: members[0])
    }

    private func closeIfNew(_ window: PseudoTerminal?, other: PseudoTerminal) {
        if let window, window !== other {
            window.window?.close()
        }
    }

    func testDropOutsideParentInSameWindow() {
        let (terminal, subgroup, loner) = makeLoneSubgroupWindow()
        drop(subgroup, from: terminal, into: terminal, before: nil)
        XCTAssertEqual(terminal.tabs()!, [loner] + subgroup)
        assertTopLevel(subgroup)
    }

    func testDropInAnotherWindow() {
        let (source, subgroup, loner) = makeLoneSubgroupWindow()
        let destination = makeWindow(tabs: 1)
        drop(subgroup, from: source, into: destination, before: nil)
        XCTAssertEqual(source.tabs()!, [loner])
        XCTAssertEqual(Array(destination.tabs()!.suffix(2)), subgroup)
        assertTopLevel(subgroup)
    }

    func testTearOff() {
        let (terminal, subgroup, loner) = makeLoneSubgroupWindow()
        let newWindow = tearOff("S", members: subgroup, from: terminal)
        defer { closeIfNew(newWindow, other: terminal) }
        XCTAssertNotNil(newWindow)
        XCTAssertFalse(newWindow === terminal, "the sub-group wasn't torn off")
        XCTAssertEqual(terminal.tabs()!, [loner])
        assertTopLevel(subgroup)
    }

    // [P: [S: s1 s2] p1] x: P's first tab is in S. Moving P past x is a plain
    // reorder of a top-level group that keeps S nested.
    func testReorderParentWhoseFirstTabIsInSubgroup() {
        let terminal = makeWindow(tabs: 4)
        let tabs = terminal.tabs()!
        put(tabs[0], inGroup: "S", parent: "P")
        put(tabs[1], inGroup: "S", parent: "P")
        put(tabs[2], inGroup: "P")
        terminal.tabsDidReorder()
        let members = Array(tabs[0...2])
        drop(members, groupID: "P", from: terminal, into: terminal, before: nil)
        XCTAssertEqual(terminal.tabs()!, [tabs[3]] + members)
        assertStillNested(Array(tabs[0...1]))
        XCTAssertEqual(tabs[2].tabGroupID, "P")
        XCTAssertNil(tabs[2].tabGroupParentID)
    }

    // The parent's tabs are the same tabs as its lone sub-group's, so only the
    // dragged group's id says which chip moved.
    func testParentDroppedInAnotherWindowKeepsSubgroup() {
        let (source, subgroup, loner) = makeLoneSubgroupWindow()
        let destination = makeWindow(tabs: 1)
        drop(subgroup, groupID: "P", from: source, into: destination, before: nil)
        XCTAssertEqual(source.tabs()!, [loner])
        XCTAssertEqual(Array(destination.tabs()!.suffix(2)), subgroup)
        assertStillNested(subgroup)
    }

    func testParentTearOffKeepsSubgroup() {
        let (terminal, subgroup, loner) = makeLoneSubgroupWindow()
        let newWindow = tearOff("P", members: subgroup, from: terminal)
        defer { closeIfNew(newWindow, other: terminal) }
        XCTAssertFalse(newWindow === terminal, "the parent wasn't torn off")
        XCTAssertEqual(terminal.tabs()!, [loner])
        assertStillNested(subgroup)
    }
}

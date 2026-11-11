//
//  TabGroupNewGroupColorTests.swift
//  ModernTests
//
//  A new group takes a palette color no other group in the window uses. The
//  color is picked before any tab moves, and a group the moving tabs are about
//  to empty doesn't count.
//

import XCTest
@testable import iTerm2SharedARC

final class TabGroupNewGroupColorTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func tearDown() {
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    private func makeWindow(tabs: Int) -> PseudoTerminal {
        fixture = TerminalWindowTestFixture(engageLayoutEngine: false)
        for _ in 1..<tabs {
            fixture.addTab()
        }
        return fixture.terminal
    }

    private func assertColor(_ tab: PTYTab, _ expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(tab.tabGroupColor?.it_colorInDefaultColorSpace().hexString(),
                       expected.it_colorInDefaultColorSpace().hexString(),
                       file: file, line: line)
    }

    func testFirstGroupFromUngroupedTabIsBlue() {
        let terminal = makeWindow(tabs: 2)
        let tab = terminal.tabs()![0]
        terminal.addTab(tab, toNewGroupWithName: "G")
        assertColor(tab, .systemBlue)
    }

    func testTabLeavingItsGroupEmptyFreesThatColor() {
        let terminal = makeWindow(tabs: 2)
        let tab = terminal.tabs()![0]
        terminal.addTab(tab, toNewGroupWithName: "G")
        terminal.addTab(tab, toNewGroupWithName: "H")
        assertColor(tab, .systemBlue)
    }

    func testTabsLeavingTheirGroupEmptyFreeThatColor() {
        let terminal = makeWindow(tabs: 3)
        let tabs = Array(terminal.tabs()![0...1])
        terminal.groupTabs(tabs, withName: "G")
        terminal.groupTabs(tabs, withName: "H")
        assertColor(tabs[0], .systemBlue)
    }

    func testGroupWithOtherTabsKeepsItsColor() {
        let terminal = makeWindow(tabs: 3)
        let tabs = terminal.tabs()!
        terminal.groupTabs(Array(tabs[0...1]), withName: "G")
        terminal.addTab(tabs[0], toNewGroupWithName: "H")
        assertColor(tabs[1], .systemBlue)
        assertColor(tabs[0], .systemGreen)
    }
}

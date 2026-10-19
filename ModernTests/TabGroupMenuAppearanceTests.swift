//
//  TabGroupMenuAppearanceTests.swift
//  ModernTests
//
//  The tab group pill’s context menu must use the same appearance as a tab’s
//  context menu, so it matches the window rather than the system when the two
//  differ.
//

import XCTest
@testable import iTerm2SharedARC

final class TabGroupMenuAppearanceTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    private func checkGroupMenuMatchesTabMenu(windowAppearance: NSAppearance.Name) {
        let terminal = fixture.terminal
        fixture.window.appearance = NSAppearance(named: windowAppearance)
        guard let tab = terminal.currentTab(),
              let item = tab.tabViewItem,
              let tabView = item.tabView else {
            XCTFail("No tab")
            return
        }
        tab.tabGroupID = "group"

        let tabMenu = terminal.tabView(tabView, menuFor: item)
        let groupMenu = terminal.tabView(tabView, menuForTabGroup: "group")
        XCTAssertNotNil(groupMenu)
        XCTAssertNotNil(tabMenu?.appearance)
        XCTAssertEqual(groupMenu?.appearance?.name, tabMenu?.appearance?.name)
    }

    func testGroupMenuMatchesDarkWindow() {
        checkGroupMenuMatchesTabMenu(windowAppearance: .darkAqua)
    }

    func testGroupMenuMatchesLightWindow() {
        checkGroupMenuMatchesTabMenu(windowAppearance: .aqua)
    }
}

//
//  SettingPopupDefaultTitleTests.swift
//  iTerm2
//
//  Regression test for QA finding F-407: the Toggle Setting and Select Menu
//  Item pickers in the key binding editor were blank until something was
//  chosen, because SearchableComboView only showed its default title after a
//  failed selection.
//

import XCTest
import SearchableComboListView
@testable import iTerm2SharedARC

final class SettingPopupDefaultTitleTests: XCTestCase {
    func testSettingPopupShowsPlaceholderBeforeSelection() {
        let view = SettingPopupView(frame: NSRect(x: 0, y: 0, width: 200, height: 25))
        XCTAssertNil(view.selectedIdentifier)
        XCTAssertEqual(view.comboView?.title, "Select Setting…")
    }

    func testSettingPopupShowsPlaceholderAfterReload() {
        let view = SettingPopupView(frame: NSRect(x: 0, y: 0, width: 200, height: 25))
        view.reloadData()
        XCTAssertEqual(view.comboView?.title, "Select Setting…")
    }

    func testMenuItemPopupShowsPlaceholderBeforeSelection() {
        let view = MenuItemPopupView(frame: NSRect(x: 0, y: 0, width: 200, height: 25))
        XCTAssertNil(view.selectedIdentifier)
        XCTAssertEqual(view.comboView?.title, "Select Menu Item…")
    }
}

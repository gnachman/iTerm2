//
//  SearchableComboViewSelectionTests.swift
//  iTerm2
//
//  Regression test for a bug where a programmatically selected item was
//  forgotten unless the user opened the popup and clicked a row. That caused
//  editing only the keystroke of a Select Menu Item key binding to erase the
//  menu item.
//

import XCTest
import SearchableComboListView

class SearchableComboViewSelectionTests: XCTestCase {
    private func makeComboView() -> SearchableComboView {
        let group = SearchableComboViewGroup("Window > Tab", items: [
            SearchableComboViewItem("Edit Tab Title", tag: 1, identifier: "Edit Tab Title"),
            SearchableComboViewItem("Select Next Tab", tag: 2, identifier: "Select Next Tab")
        ])
        return SearchableComboView([group], defaultTitle: "Select Menu Item…")
    }

    func testSelectedItemReflectsProgrammaticSelectionByIdentifier() {
        let comboView = makeComboView()
        XCTAssertTrue(comboView.selectItem(withIdentifier: NSUserInterfaceItemIdentifier("Edit Tab Title")))
        XCTAssertEqual(comboView.selectedItem?.title, "Edit Tab Title")
        XCTAssertEqual(comboView.selectedItem?.identifier?.rawValue, "Edit Tab Title")
    }

    func testSelectedItemReflectsProgrammaticSelectionByTitle() {
        let comboView = makeComboView()
        comboView.selectItem(withTitle: "Select Next Tab")
        XCTAssertEqual(comboView.selectedItem?.title, "Select Next Tab")
        XCTAssertEqual(comboView.selectedItem?.identifier?.rawValue, "Select Next Tab")
    }

    func testSelectedItemIsNilWhenNothingIsSelected() {
        let comboView = makeComboView()
        XCTAssertNil(comboView.selectedItem)
    }

    func testFailedSelectionClearsSelection() {
        let comboView = makeComboView()
        XCTAssertTrue(comboView.selectItem(withIdentifier: NSUserInterfaceItemIdentifier("Edit Tab Title")))
        XCTAssertFalse(comboView.selectItem(withIdentifier: NSUserInterfaceItemIdentifier("Nonexistent")))
        XCTAssertNil(comboView.selectedItem)
    }
}

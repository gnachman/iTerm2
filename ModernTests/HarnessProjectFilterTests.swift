//
//  HarnessProjectFilterTests.swift
//  iTerm2
//
//  Tests for the tab set shown while a harness project is selected.
//

import XCTest
@testable import iTerm2SharedARC

final class HarnessProjectFilterTests: XCTestCase {
    private let items = ["a", "b", "c", "d"]

    private func apply(matching: Set<String>,
                       selected: String?,
                       reselect: Bool) -> (visible: Set<String>?, select: String?) {
        var toSelect: AnyObject?
        let visible = iTermLayoutCalculator.harnessProjectVisibleItems(orderedItems: items,
                                                                       matchingItems: Set<AnyHashable>(matching.map { AnyHashable($0) }),
                                                                       selectedItem: selected,
                                                                       reselect: reselect,
                                                                       itemToSelect: &toSelect)
        return (visible.map { Set($0.compactMap { $0 as? String }) }, toSelect as? String)
    }

    func testNoMatchingTabsDisablesFilter() {
        let result = apply(matching: [], selected: "a", reselect: true)
        XCTAssertNil(result.visible)
        XCTAssertNil(result.select)
    }

    func testRefreshNeverMovesSelectionAndKeepsSelectedTabVisible() {
        let result = apply(matching: ["b", "d"], selected: "a", reselect: false)
        XCTAssertEqual(result.visible, ["a", "b", "d"])
        XCTAssertNil(result.select)
    }

    func testProjectChangeSelectsFirstProjectTabInTabOrder() {
        let result = apply(matching: ["d", "b"], selected: "a", reselect: true)
        XCTAssertEqual(result.visible, ["b", "d"])
        XCTAssertEqual(result.select, "b")
    }

    func testProjectChangeKeepsSelectionAlreadyInProject() {
        let result = apply(matching: ["b", "d"], selected: "d", reselect: true)
        XCTAssertEqual(result.visible, ["b", "d"])
        XCTAssertNil(result.select)
    }

    func testNoSelectedTabShowsOnlyProjectTabs() {
        let result = apply(matching: ["c"], selected: nil, reselect: false)
        XCTAssertEqual(result.visible, ["c"])
        XCTAssertNil(result.select)
    }

    func testReselectWithMatchesOutsideTabViewKeepsSelectedTabVisible() {
        let result = apply(matching: ["z"], selected: "a", reselect: true)
        XCTAssertEqual(result.visible, ["a", "z"])
        XCTAssertNil(result.select)
    }
}

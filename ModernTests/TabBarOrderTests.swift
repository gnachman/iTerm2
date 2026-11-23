//
//  TabBarOrderTests.swift
//  ModernTests
//
//  The order a vertical tab bar shows tabs in: manual, by status, or by
//  working directory.
//

import XCTest
@testable import iTerm2SharedARC

final class TabBarOrderTests: XCTestCase {
    private let none = Int.max

    private func tab(_ priority: Int = Int.max,
                     snoozed: Bool = false,
                     pinned: Bool = false,
                     directory: String? = nil,
                     atPrompt: Bool = false,
                     group: String? = nil) -> TabBarOrderTab {
        return TabBarOrderTab(pinned: pinned,
                              statusPriority: priority,
                              snoozed: snoozed,
                              directory: directory,
                              atPrompt: atPrompt,
                              group: group)
    }

    // MARK: - Manual

    func testManualKeepsTheWindowsOrder() {
        let result = TabBarOrder.apply(mode: .manual, tabs: [tab(3), tab(0), tab()])
        XCTAssertEqual(result.order, [0, 1, 2])
        XCTAssertTrue(result.sections.isEmpty)
        XCTAssertTrue(result.sectionIdentifiers.allSatisfy { $0 is NSNull })
    }

    // MARK: - Status

    func testStatusSortsByPriorityThenManualOrder() {
        let result = TabBarOrder.apply(mode: .status, tabs: [tab(2), tab(0), tab(none), tab(0), tab(1)])
        XCTAssertEqual(result.order, [1, 3, 4, 0, 2])
        XCTAssertTrue(result.sections.isEmpty)
    }

    func testSnoozedTabsGoLast() {
        let result = TabBarOrder.apply(mode: .status, tabs: [tab(0, snoozed: true), tab(none), tab(3)])
        XCTAssertEqual(result.order, [2, 1, 0])
    }

    func testPinnedTabsStayFirstInManualOrder() {
        let result = TabBarOrder.apply(mode: .status, tabs: [tab(0), tab(5, pinned: true), tab(1), tab(0, pinned: true)])
        XCTAssertEqual(result.order, [1, 3, 0, 2])
    }

    // MARK: - Working Directory

    func testDirectoriesGetSectionsInManualOrderOfTheirFirstTab() {
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(directory: "/a/b"),
                                              tab(directory: "/c"),
                                              tab(directory: "/a/b/"),
                                              tab(directory: "/c")])
        XCTAssertEqual(result.order, [0, 2, 1, 3])
        XCTAssertEqual(result.sections.map(\.name), ["b", "c"])
        XCTAssertEqual(result.sections.map(\.toolTip), ["/a/b", "/c"])
        XCTAssertEqual(result.sectionIdentifiers as? [String],
                       [result.sections[0].identifier, result.sections[1].identifier,
                        result.sections[0].identifier, result.sections[1].identifier])
    }

    func testTabsAtAPromptGoInALastSection() {
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(directory: "/y", atPrompt: true),
                                              tab(directory: "/x"),
                                              tab(directory: "/x", atPrompt: true)])
        XCTAssertEqual(result.order, [1, 0, 2])
        XCTAssertEqual(result.sections.map(\.identifier),
                       [result.sectionIdentifiers[1] as? String, TabBarOrder.promptSectionIdentifier])
        XCTAssertNil(result.sections.last?.toolTip)
    }

    // A tab whose directory isn't known, such as a web browser tab, isn't
    // at a prompt either.
    func testTabsWithNoDirectoryGetTheirOwnSectionBeforeThePromptSection() {
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(directory: nil),
                                              tab(directory: "/x", atPrompt: true),
                                              tab(directory: "/x")])
        XCTAssertEqual(result.order, [2, 0, 1])
        XCTAssertEqual(result.sections.map(\.identifier).suffix(2),
                       [TabBarOrder.unknownSectionIdentifier, TabBarOrder.promptSectionIdentifier])
        XCTAssertEqual(result.sectionIdentifiers[0] as? String, TabBarOrder.unknownSectionIdentifier)
    }

    func testTheHomeDirectoryIsNamedWithATilde() {
        let result = TabBarOrder.apply(mode: .workingDirectory, tabs: [tab(directory: NSHomeDirectory())])
        XCTAssertEqual(result.sections.map(\.name), ["~"])
    }

    func testPinnedTabsHaveNoSection() {
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(directory: "/x"), tab(pinned: true, directory: "/y")])
        XCTAssertEqual(result.order, [1, 0])
        XCTAssertTrue(result.sectionIdentifiers[1] is NSNull)
        XCTAssertEqual(result.sections.map(\.name), ["x"])
    }

    func testSectionIdentifiersAreRecognizable() {
        let result = TabBarOrder.apply(mode: .workingDirectory, tabs: [tab(directory: "/x"), tab()])
        for section in result.sections {
            XCTAssertTrue(TabBarOrder.isSectionIdentifier(section.identifier))
        }
        XCTAssertFalse(TabBarOrder.isSectionIdentifier(UUID().uuidString))
        XCTAssertFalse(TabBarOrder.isSectionIdentifier(nil))
    }

    // MARK: - Moving

    private func move(_ result: TabBarOrderResult, _ index: Int, by offset: Int, visible: [Bool]? = nil) -> [Int]? {
        let count = result.order.count
        return TabBarOrder.moveOrder(result: result,
                                     visible: visible ?? Array(repeating: true, count: count),
                                     selectedIndex: index,
                                     offset: offset)
    }

    func testAMoveTradesPlacesWithinASection() {
        // Shown: [0 2] [1 3]
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(directory: "/a"), tab(directory: "/b"),
                                              tab(directory: "/a"), tab(directory: "/b")])
        XCTAssertEqual(move(result, 0, by: 1), [2, 1, 0, 3])
        XCTAssertEqual(move(result, 3, by: -1), [0, 3, 2, 1])
    }

    func testAMoveWrapsAroundWithinASection() {
        // Sections [0 2 4] [1]. Moving 4 right wraps it to the front of its
        // section, so the others shift along.
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(directory: "/a"), tab(directory: "/b"), tab(directory: "/a"),
                                              tab(directory: "/c"), tab(directory: "/a")])
        XCTAssertEqual(move(result, 4, by: 1), [4, 1, 0, 3, 2])
        XCTAssertEqual(move(result, 0, by: -1), [2, 1, 4, 3, 0])
    }

    func testATabAloneInItsSectionCantMove() {
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(directory: "/a"), tab(directory: "/b")])
        XCTAssertNil(move(result, 0, by: 1))
    }

    func testAMoveSkipsHiddenTabs() {
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(directory: "/a"), tab(directory: "/a"), tab(directory: "/a")])
        XCTAssertEqual(move(result, 0, by: 1, visible: [true, false, true]), [2, 1, 0])
        XCTAssertNil(move(result, 1, by: 1, visible: [true, false, true]), "a hidden tab can't move")
    }

    func testInStatusOrderAMoveStaysAmongTabsWithTheSameStatus() {
        // Shown: 1 3 (priority 0), 0 2 (priority 1).
        let result = TabBarOrder.apply(mode: .status, tabs: [tab(1), tab(0), tab(1), tab(0)])
        XCTAssertEqual(result.order, [1, 3, 0, 2])
        XCTAssertEqual(move(result, 3, by: 1), [0, 3, 2, 1], "wraps among the priority 0 tabs")
        XCTAssertEqual(move(result, 0, by: 1), [2, 1, 0, 3])
    }

    // The window keeps a group's tabs together, so a move that took a tab
    // out of its group would be undone. Moves stay among the group's tabs.
    func testAMoveStaysInTheTabsGroup() {
        // Manual order [g:0, g:1, 2], all the same status.
        let result = TabBarOrder.apply(mode: .status, tabs: [tab(1, group: "g"), tab(1, group: "g"), tab(1)])
        XCTAssertEqual(move(result, 1, by: 1), [1, 0, 2], "wraps within the group instead of passing 2")
        XCTAssertNil(move(result, 2, by: -1), "nothing outside the group to trade with")
    }

    func testPinnedTabsMoveAmongThemselves() {
        let result = TabBarOrder.apply(mode: .workingDirectory,
                                       tabs: [tab(pinned: true), tab(directory: "/a"), tab(pinned: true)])
        XCTAssertEqual(move(result, 0, by: 1), [2, 1, 0])
    }

    // MARK: - Next and previous

    func testNextAndPreviousGoByWhatTheBarShows() {
        let order = [2, 0, 3, 1]
        let visible = [false, true, true, true]
        XCTAssertEqual(TabBarOrder.adjacentVisibleIndex(order: order, visible: visible, selectedIndex: 2, offset: 1), 3,
                       "0 is hidden")
        XCTAssertEqual(TabBarOrder.adjacentVisibleIndex(order: order, visible: visible, selectedIndex: 1, offset: 1), 2,
                       "wraps around")
        XCTAssertEqual(TabBarOrder.adjacentVisibleIndex(order: order, visible: visible, selectedIndex: 2, offset: -1), 1)
    }
}

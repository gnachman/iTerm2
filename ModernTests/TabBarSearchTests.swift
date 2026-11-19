//
//  TabBarSearchTests.swift
//  ModernTests
//
//  Searching a vertical tab bar hides tabs that don't match. A group with a
//  match stays, expanded, showing only its matches. A group without one goes
//  away.
//

import XCTest
@testable import iTerm2SharedARC

final class TabBarSearchTests: XCTestCase {
    private func tab(_ texts: [String],
                     group: String? = nil,
                     parent: String? = nil,
                     hidden: Bool = false,
                     parentCollapsed: Bool = false) -> TabBarSearchTab {
        return TabBarSearchTab(texts: texts,
                               groupID: group,
                               parentGroupID: parent,
                               hidden: hidden,
                               parentCollapsed: parentCollapsed)
    }

    // A group's name, or its parent group's, matching shows all its tabs.
    func testAGroupNameMatchShowsTheGroup() {
        let tabs = [
            TabBarSearchTab(texts: ["zsh"], groupNames: ["backend"], groupID: "G", parentGroupID: nil,
                            hidden: false, parentCollapsed: false),
            TabBarSearchTab(texts: ["vim"], groupNames: ["backend"], groupID: "G", parentGroupID: nil,
                            hidden: false, parentCollapsed: false),
            TabBarSearchTab(texts: ["logs"], groupNames: ["db", "backend"], groupID: "S", parentGroupID: "G",
                            hidden: false, parentCollapsed: false),
            TabBarSearchTab(texts: ["top"], groupNames: ["frontend"], groupID: "F", parentGroupID: nil,
                            hidden: false, parentCollapsed: false),
            tab(["backend notes"]),
        ]
        let result = TabBarSearch.apply(query: "backend", tabs: tabs)
        XCTAssertEqual(result.hidden, [false, false, false, true, false])
        XCTAssertEqual(groups(result), ["G", "G", "S", nil, nil])
        XCTAssertEqual(TabBarSearch.apply(query: "db", tabs: tabs).hidden, [true, true, false, true, true])
    }

    private func groups(_ result: TabBarSearchResult) -> [String?] {
        return result.groupIDs.map { $0 as? String }
    }

    private func parents(_ result: TabBarSearchResult) -> [String?] {
        return result.parentGroupIDs.map { $0 as? String }
    }

    func testMatchingIgnoresCaseAndDiacritics() {
        XCTAssertTrue(TabBarSearch.matches(query: "API", texts: ["~/git/api-server"]))
        XCTAssertTrue(TabBarSearch.matches(query: "cafe", texts: ["Café"]))
        XCTAssertTrue(TabBarSearch.matches(query: "job", texts: ["title", "a job line"]))
        XCTAssertFalse(TabBarSearch.matches(query: "web", texts: ["api", "server"]))
    }

    // Leading and trailing spaces don't count, and blank is no search.
    func testBlankQueryChangesNothing() {
        let tabs = [tab(["a"], group: "G", hidden: true),
                    tab(["b"], group: "S", parent: "G", hidden: true, parentCollapsed: true)]
        let result = TabBarSearch.apply(query: "  ", tabs: tabs)
        XCTAssertEqual(groups(result), ["G", "S"])
        XCTAssertEqual(parents(result), [nil, "G"])
        XCTAssertEqual(result.hidden, [true, true])
        XCTAssertEqual(result.parentCollapsed, [false, true])
        XCTAssertEqual(result.matches, [true, true])
        XCTAssertFalse(result.isSearching)
    }

    func testTabsThatDontMatchAreHidden() {
        let result = TabBarSearch.apply(query: "api", tabs: [tab(["api"]), tab(["web"]), tab([" API docs"])])
        XCTAssertEqual(result.hidden, [false, true, false])
        XCTAssertEqual(result.matches, [true, false, true])
        XCTAssertTrue(result.isSearching)
    }

    // A collapsed group with a match opens, so the match shows. Its other
    // members stay hidden, and stay in the group so it is still one run.
    func testGroupWithAMatchIsShownExpanded() {
        let tabs = [tab(["api"], group: "G", hidden: true),
                    tab(["web"], group: "G", hidden: true),
                    tab(["api 2"], group: "G", hidden: true)]
        let result = TabBarSearch.apply(query: "api", tabs: tabs)
        XCTAssertEqual(result.hidden, [false, true, false])
        XCTAssertEqual(groups(result), ["G", "G", "G"])
    }

    // A group without a match has no chip: its tabs leave it.
    func testGroupWithoutAMatchGoesAway() {
        let tabs = [tab(["api"]),
                    tab(["web"], group: "G"),
                    tab(["docs"], group: "G")]
        let result = TabBarSearch.apply(query: "api", tabs: tabs)
        XCTAssertEqual(groups(result), [nil, nil, nil])
        XCTAssertEqual(result.hidden, [false, true, true])
    }

    // A match in a sub-group keeps the parent too, expanded.
    func testMatchInSubgroupKeepsParent() {
        let tabs = [tab(["web"], group: "P"),
                    tab(["api"], group: "S", parent: "P", hidden: true, parentCollapsed: true)]
        let result = TabBarSearch.apply(query: "api", tabs: tabs)
        XCTAssertEqual(groups(result), ["P", "S"])
        XCTAssertEqual(parents(result), [nil, "P"])
        XCTAssertEqual(result.hidden, [true, false])
        XCTAssertEqual(result.parentCollapsed, [false, false])
    }

    // A sub-group without a match goes away, but its tabs stay in the parent,
    // which has a match, so the parent remains one run.
    func testSubgroupWithoutAMatchLeavesParentIntact() {
        let tabs = [tab(["api"], group: "P"),
                    tab(["web"], group: "S", parent: "P"),
                    tab(["api 2"], group: "P")]
        let result = TabBarSearch.apply(query: "api", tabs: tabs)
        XCTAssertEqual(groups(result), ["P", "P", "P"])
        XCTAssertEqual(parents(result), [nil, nil, nil])
        XCTAssertEqual(result.hidden, [false, true, false])
    }

    func testFirstMatch() {
        let result = TabBarSearch.apply(query: "api", tabs: [tab(["web"]), tab(["api"]), tab(["api 2"])])
        XCTAssertEqual(result.firstMatchIndex, 1)
        XCTAssertEqual(TabBarSearch.apply(query: "zzz", tabs: [tab(["web"])]).firstMatchIndex, NSNotFound)
    }

    // MARK: - Moving a tab while some are hidden

    private func swapTarget(_ keys: [String?], visible: [Bool], selected: Int, offset: Int) -> Int? {
        let index = TabBarSearch.swapIndex(groupKeys: keys.map { $0 ?? "" },
                                           visible: visible,
                                           selectedIndex: selected,
                                           offset: offset)
        return index == NSNotFound ? nil : index
    }

    // Hidden tabs are skipped: the tab trades places with the next visible one.
    func testMoveSkipsHiddenTabs() {
        let keys: [String?] = [nil, nil, nil, nil]
        XCTAssertEqual(swapTarget(keys, visible: [true, false, true, true], selected: 2, offset: -1), 0)
        XCTAssertEqual(swapTarget(keys, visible: [true, false, true, true], selected: 0, offset: 1), 2)
    }

    // Only within the group the bar shows it in.
    func testMoveStaysInItsGroup() {
        let keys: [String?] = [nil, "G", "G", nil]
        XCTAssertEqual(swapTarget(keys, visible: [true, true, true, true], selected: 2, offset: -1), 1)
        XCTAssertNil(swapTarget(keys, visible: [true, true, true, true], selected: 2, offset: 1),
                     "the next visible tab is outside the group")
        XCTAssertNil(swapTarget(keys, visible: [true, true, true, true], selected: 1, offset: -1))
    }

    // An ungrouped tab passes over a group rather than joining it.
    func testUngroupedTabSkipsOverAGroup() {
        let keys: [String?] = [nil, "G", "G", nil]
        XCTAssertEqual(swapTarget(keys, visible: [true, true, true, true], selected: 0, offset: 1), 3)
    }

    // swapIndex alone finds no neighbor at the ends; moveOrder wraps there.
    func testNoNeighborAtTheEnds() {
        let keys: [String?] = [nil, nil]
        XCTAssertNil(swapTarget(keys, visible: [true, true], selected: 0, offset: -1))
        XCTAssertNil(swapTarget(keys, visible: [true, true], selected: 1, offset: 1))
    }

    private func moveOrder(_ keys: [String?], visible: [Bool], selected: Int, offset: Int) -> [Int]? {
        return TabBarSearch.moveOrder(groupKeys: keys.map { $0 ?? "" },
                                      visible: visible,
                                      selectedIndex: selected,
                                      offset: offset)
    }

    // Away from the ends, a move trades places with the next shown peer.
    func testMoveOrderSwaps() {
        let keys: [String?] = [nil, nil, nil, nil]
        XCTAssertEqual(moveOrder(keys, visible: [true, false, true, true], selected: 2, offset: -1), [2, 1, 0, 3])
    }

    // At the last shown peer it wraps to before the first, as a move with no
    // search wraps at the ends. Hidden tabs keep their places.
    func testMoveOrderWrapsForward() {
        let keys: [String?] = [nil, nil, nil, nil]
        XCTAssertEqual(moveOrder(keys, visible: [false, true, true, true], selected: 3, offset: 1), [0, 3, 1, 2])
    }

    func testMoveOrderWrapsBackward() {
        let keys: [String?] = [nil, nil, nil, nil]
        XCTAssertEqual(moveOrder(keys, visible: [true, true, true, false], selected: 0, offset: -1), [1, 2, 0, 3])
    }

    // Wrapping: an ungrouped tab goes past a group, and a sub-group's tab
    // stays in its sub-group.
    func testMoveOrderWrapsWithinItsKey() {
        let keys = [key(), key(parent: "P", group: "S"), key(parent: "P", group: "S"), key()]
        let visible = [true, true, true, true]
        func order(_ selected: Int, _ offset: Int) -> [Int]? {
            return TabBarSearch.moveOrder(groupKeys: keys, visible: visible, selectedIndex: selected, offset: offset)
        }
        XCTAssertEqual(order(0, -1), [1, 2, 3, 0])
        XCTAssertEqual(order(2, 1), [0, 2, 1, 3])
        XCTAssertEqual(order(1, -1), [0, 2, 1, 3])
    }

    // Nothing to trade with: a hidden tab, no offset, or out of range.
    func testMoveOrderWithNothingToDo() {
        XCTAssertNil(moveOrder([nil, nil], visible: [false, true], selected: 0, offset: 1))
        XCTAssertNil(moveOrder([nil, nil], visible: [true, true], selected: 0, offset: 0))
        XCTAssertNil(moveOrder([nil, nil], visible: [true, true], selected: 5, offset: 1))
    }

    private func key(pinned: Bool = false, parent: String = "", group: String = "") -> String {
        return "\(pinned ? "pinned" : "unpinned")\u{1}\(parent)\u{1}\(group)"
    }

    // An ungrouped tab with no shown peer moves past the next shown group as
    // a whole, hidden members included, as it would without a search.
    func testALoneUngroupedTabMovesPastAGroup() {
        let keys = [key(), key(group: "G"), key(group: "G"), key(group: "G")]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: keys, visible: [true, true, false, true],
                                              selectedIndex: 0, offset: 1),
                       [1, 2, 3, 0])
        let back = [key(group: "G"), key(group: "G"), key()]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: back, visible: [false, true, true],
                                              selectedIndex: 2, offset: -1),
                       [2, 0, 1])
    }

    // With a shown peer behind it but none ahead, an ungrouped tab still
    // moves past the next group rather than wrapping around.
    func testAnUngroupedTabMovesPastAGroupBeforeWrapping() {
        let keys = [key(), key(), key(group: "G"), key(group: "G")]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: keys, visible: [true, true, true, true],
                                              selectedIndex: 1, offset: 1),
                       [0, 2, 3, 1])
    }

    // Moving past a group is one step whether or not a shown peer lies
    // beyond it: the peer isn't dragged to the other side.
    func testAnUngroupedTabMovesPastAGroupNotSwappingBeyondIt() {
        let keys = [key(), key(), key(group: "G"), key(group: "G"), key()]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: keys, visible: [true, true, true, true, true],
                                              selectedIndex: 1, offset: 1),
                       [0, 2, 3, 1, 4])
    }

    // At the end, an ungrouped tab wraps to the start of its section, as a
    // move does without a search, even past a group.
    func testAnUngroupedTabWrapsToTheStartOfItsSection() {
        let keys = [key(group: "G"), key(group: "G"), key(), key()]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: keys, visible: [true, true, true, true],
                                              selectedIndex: 3, offset: 1),
                       [3, 0, 1, 2])
        let back = [key(), key(), key(group: "G"), key(group: "G")]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: back, visible: [true, true, true, true],
                                              selectedIndex: 0, offset: -1),
                       [1, 2, 3, 0])
        // Not into the pinned tabs.
        let pinned = [key(pinned: true), key(group: "G"), key()]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: pinned, visible: [true, true, true],
                                              selectedIndex: 2, offset: 1),
                       [0, 2, 1])
    }

    // A group's direct tab moves past one of its sub-groups.
    func testADirectMemberMovesPastASubgroup() {
        let keys = [key(group: "P"), key(parent: "P", group: "S"), key(parent: "P", group: "S")]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: keys, visible: [true, true, false],
                                              selectedIndex: 0, offset: 1),
                       [1, 2, 0])
    }

    // A group's direct tab at the end wraps to the other end of the group's
    // shown tabs, past a sub-group but not into it.
    func testADirectMemberWrapsPastASubgroup() {
        let keys = [key(parent: "P", group: "S"), key(parent: "P", group: "S"), key(group: "P")]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: keys, visible: [true, true, true],
                                              selectedIndex: 2, offset: 1),
                       [2, 0, 1])
    }

    // Backward too, and with hidden tabs at the far edge.
    func testADirectMemberWrapsInBothDirections() {
        let p = key(group: "P"), s = key(parent: "P", group: "S")
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: [p, s, s], visible: [true, true, true],
                                              selectedIndex: 0, offset: -1),
                       [1, 2, 0])
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: [s, s, p], visible: [false, true, true],
                                              selectedIndex: 2, offset: 1),
                       [2, 0, 1], "out to the sub-group's hidden first tab")
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: [p, p, p], visible: [false, true, true],
                                              selectedIndex: 2, offset: 1),
                       [0, 2, 1], "before the first shown tab; the hidden one keeps its place")
    }

    // A sub-group is part of its parent's run.
    func testALoneUngroupedTabMovesPastAGroupWithASubgroup() {
        let keys = [key(), key(group: "P"), key(parent: "P", group: "S"), key(group: "P")]
        XCTAssertEqual(TabBarSearch.moveOrder(groupKeys: keys, visible: [true, false, true, false],
                                              selectedIndex: 0, offset: 1),
                       [1, 2, 3, 0])
    }

    // It doesn't cross into the pinned tabs, leave a group, or move with
    // nothing shown in that direction.
    func testALoneTabThatCannotMove() {
        XCTAssertNil(TabBarSearch.moveOrder(groupKeys: [key(pinned: true), key()], visible: [true, true],
                                            selectedIndex: 1, offset: -1))
        XCTAssertNil(TabBarSearch.moveOrder(groupKeys: [key(group: "G"), key()], visible: [true, true],
                                            selectedIndex: 0, offset: 1),
                     "a group's only shown tab stays in its group")
        XCTAssertNil(TabBarSearch.moveOrder(groupKeys: [key(), key(group: "G")], visible: [true, false],
                                            selectedIndex: 0, offset: 1))
    }

    func testHiddenTabDoesNotMove() {
        XCTAssertNil(swapTarget([nil, nil], visible: [false, true], selected: 0, offset: 1))
    }

    // The key a tab is grouped by while searching: what the bar shows, and
    // whether it's pinned.
    func testGroupKeys() {
        let result = TabBarSearch.apply(query: "api",
                                        tabs: [tab(["api"], group: "G"),
                                               tab(["api"], group: "G"),
                                               tab(["api"], group: "G"),
                                               tab(["api"], group: "S", parent: "G")])
        let keys = result.groupKeys(pinned: [false, false, true, false])
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertNotEqual(keys[0], keys[2], "pinned differs")
        XCTAssertNotEqual(keys[0], keys[3], "a sub-group is its own group")
    }

    // A direct member of a group passes over a visible sub-group, and the
    // sub-group's tab can't leave it.
    func testMovePastAVisibleSubgroup() {
        let tabs = [tab(["api one"], group: "P"),
                    tab(["api sub"], group: "S", parent: "P"),
                    tab(["api two"], group: "P")]
        let result = TabBarSearch.apply(query: "api", tabs: tabs)
        let keys = result.groupKeys(pinned: [false, false, false])
        let visible = result.hidden.map { !$0 }
        XCTAssertEqual(TabBarSearch.swapIndex(groupKeys: keys, visible: visible, selectedIndex: 0, offset: 1), 2)
        XCTAssertEqual(TabBarSearch.swapIndex(groupKeys: keys, visible: visible, selectedIndex: 1, offset: 1), NSNotFound)
    }

    // A sub-group without a match goes away and its hidden tabs join the
    // parent's run, where moves skip them as any hidden tab.
    func testMovePastASubgroupWithoutAMatch() {
        let tabs = [tab(["api one"], group: "P"),
                    tab(["web sub"], group: "S", parent: "P"),
                    tab(["docs sub"], group: "S", parent: "P"),
                    tab(["api two"], group: "P")]
        let result = TabBarSearch.apply(query: "api", tabs: tabs)
        XCTAssertEqual(groups(result), ["P", "P", "P", "P"])
        let keys = result.groupKeys(pinned: [false, false, false, false])
        let visible = result.hidden.map { !$0 }
        XCTAssertEqual(TabBarSearch.swapIndex(groupKeys: keys, visible: visible, selectedIndex: 0, offset: 1), 3)
        XCTAssertEqual(TabBarSearch.swapIndex(groupKeys: keys, visible: visible, selectedIndex: 3, offset: -1), 0)
    }

    // MARK: - Next and previous tab while searching

    private func adjacent(_ visible: [Bool], _ selected: Int, _ offset: Int) -> Int? {
        let index = TabBarSearch.adjacentVisibleIndex(visible: visible, selectedIndex: selected, offset: offset)
        return index == NSNotFound ? nil : index
    }

    // Next and previous go among the tabs shown, wrapping around.
    func testNextAndPreviousSkipHiddenTabsAndWrap() {
        let visible = [true, false, true, false]
        XCTAssertEqual(adjacent(visible, 0, 1), 2)
        XCTAssertEqual(adjacent(visible, 2, 1), 0)
        XCTAssertEqual(adjacent(visible, 0, -1), 2)
        XCTAssertEqual(adjacent(visible, 2, -1), 0)
    }

    // From a hidden tab, the nearest shown one in that direction.
    func testNextFromAHiddenTab() {
        let visible = [true, false, false, true]
        XCTAssertEqual(adjacent(visible, 1, 1), 3)
        XCTAssertEqual(adjacent(visible, 1, -1), 0)
    }

    func testNothingShownOrOnlyItself() {
        XCTAssertNil(adjacent([false, false], 0, 1))
        XCTAssertNil(adjacent([false, true, false], 1, 1), "already the only one shown")
    }

    // MARK: - What a tab is searched by

    // What the tab draws: its rich lines when it has them, otherwise its title
    // and subtitle. A pinned tab draws only its title.
    func testSearchedTextIsWhatTheTabDraws() {
        XCTAssertEqual(TabBarSearch.searchedTexts(label: "title\nsub", richLines: ["dir", "job"], pinned: false),
                       ["dir", "job"])
        XCTAssertEqual(TabBarSearch.searchedTexts(label: "title\nsub", richLines: [], pinned: false),
                       ["title\nsub"])
        XCTAssertEqual(TabBarSearch.searchedTexts(label: "title", richLines: ["dir"], pinned: true),
                       ["title"])
        XCTAssertEqual(TabBarSearch.searchedTexts(label: nil, richLines: [], pinned: false), [])
    }

    // MARK: - The selected tab

    func testReplacementForAClosingTab() {
        let visible = [true, false, true, false, true]
        XCTAssertEqual(TabBarSearch.replacementIndex(visible: visible, closingIndex: 2, preferLeft: false), 4)
        XCTAssertEqual(TabBarSearch.replacementIndex(visible: visible, closingIndex: 2, preferLeft: true), 0)
        XCTAssertEqual(TabBarSearch.replacementIndex(visible: visible, closingIndex: 4, preferLeft: false), 2,
                       "no wrapping: the other way")
        XCTAssertEqual(TabBarSearch.replacementIndex(visible: [false, true, false], closingIndex: 1, preferLeft: false),
                       NSNotFound)
        XCTAssertEqual(TabBarSearch.replacementIndex(visible: [true, false, true], closingIndex: 0, preferLeft: true), 2,
                       "nothing to the left, so the right")
        XCTAssertEqual(TabBarSearch.replacementIndex(visible: [true], closingIndex: 3, preferLeft: false), NSNotFound)
        XCTAssertEqual(TabBarSearch.replacementIndex(visible: [], closingIndex: 0, preferLeft: false), NSNotFound)
    }

    // Only matches are shown; there is no exception for any tab.
    func testOnlyMatchesAreShown() {
        let result = TabBarSearch.apply(query: "api",
                                        tabs: [tab(["web"]), tab(["api"]), tab(["new tab"])])
        XCTAssertEqual(result.hidden, [true, false, true])
        XCTAssertEqual(result.matches, [false, true, false])
    }
}

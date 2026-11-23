//
//  TabBarOrderWindowTests.swift
//  ModernTests
//
//  The order control under a vertical tab bar's search field, in a real
//  window: Status and Working Directory change only how the bar shows tabs,
//  never the window's order.
//

import XCTest
@testable import iTerm2SharedARC

final class TabBarOrderWindowTests: XCTestCase {
    private var savedTabPosition: Int32 = 0
    private var savedShowStatus = false
    private var savedPriorities = [StatusPriorityEntry]()
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        savedTabPosition = iTermPreferences.int(forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setInt(2 /* PSMTab_LeftTab */, forKey: kPreferenceKeyTabPosition)
        savedShowStatus = iTermUserDefaults.showSessionStatusInTabSubtitle
        iTermUserDefaults.showSessionStatusInTabSubtitle = true
        _ = SessionStatusController.instance
        // Known priorities, so “Waiting” is the most urgent.
        savedPriorities = StatusPrioritySettings.shared.entries
        StatusPrioritySettings.shared.restoreEntries(["wait", "done", "error", "work", "idle"].map {
            StatusPriorityEntry(pattern: $0)
        })
        fixture = TerminalWindowTestFixture()
        if let bar = try? tabBar {
            bar.pointerIsInsideForTesting = NSNumber(value: false)
        }
    }

    override func tearDown() {
        for session in fixture.terminal.allSessions() ?? [] {
            session.clearTabStatus()
        }
        fixture.close()
        fixture = nil
        iTermPreferences.setInt(savedTabPosition, forKey: kPreferenceKeyTabPosition)
        iTermUserDefaults.showSessionStatusInTabSubtitle = savedShowStatus
        StatusPrioritySettings.shared.restoreEntries(savedPriorities)
        super.tearDown()
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let done = expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)
        done.expectationDescription = description
        wait(for: [done], timeout: 5)
    }

    private func findTabBar(in view: NSView) -> PSMTabBarControl? {
        if let bar = view as? PSMTabBarControl {
            return bar
        }
        for subview in view.subviews {
            if let bar = findTabBar(in: subview) {
                return bar
            }
        }
        return nil
    }

    private var tabBar: PSMTabBarControl {
        get throws {
            return try XCTUnwrap(findTabBar(in: try XCTUnwrap(fixture.window.contentView?.superview)))
        }
    }

    private func orderControl() throws -> NSSegmentedControl {
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let accessory = try XCTUnwrap(try tabBar.topAccessoryView)
        return try XCTUnwrap(accessory.subviews.compactMap { $0 as? NSSegmentedControl }.first)
    }

    private func searchField() throws -> NSSearchField {
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let accessory = try XCTUnwrap(try tabBar.topAccessoryView)
        return try XCTUnwrap(accessory.subviews.compactMap { $0 as? NSSearchField }.first)
    }

    private func pick(_ mode: TabBarOrderMode) throws {
        let control = try orderControl()
        control.selectedSegment = mode.rawValue
        control.sendAction(control.action, to: control.target)
    }

    // Tabs titled a, b, c, d.
    private func makeTabs(_ count: Int = 4) throws -> [PTYTab] {
        for _ in 1..<count {
            _ = fixture.addTab()
        }
        let tabs = try XCTUnwrap(fixture.terminal.tabs())
        let titles = ["a", "b", "c", "d", "e"].prefix(count)
        for (tab, title) in zip(tabs, titles) {
            tab.titleOverride = title
        }
        waitUntil("titles shown") {
            zip(tabs, titles).allSatisfy { $0.tabViewItem?.label.hasPrefix($1) == true }
        }
        return tabs
    }

    private func setStatus(_ text: String, on tab: PTYTab) {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = text
        update.indicatorPresence = .set
        update.indicator = iTermSRGBColor(r: 0, g: 0, b: 1)
        tab.activeSession.screenSetTabStatus(update)
    }

    private func setDirectory(_ path: String, on tab: PTYTab) {
        tab.activeSession.genericScope.setValue(path, forVariableNamed: iTermVariableKeySessionPath)
    }

    // What the bar shows, top to bottom: tabs by their index in `tabs`, and
    // section headings by name in brackets. Hidden tabs are left out.
    private func shown(_ tabs: [PTYTab]) throws -> [String] {
        let cells = try tabBar.cells() as? [PSMTabBarCell] ?? []
        return try cells.compactMap { cell -> String? in
            if cell.isTabGroupChip {
                let group = try tabBar.tabGroupDataSource?.tabGroup(withIdentifier: cell.tabGroupIdentifier ?? "")
                return "[\(group?.name ?? "?")]"
            }
            if cell.isCollapsedHidden {
                return nil
            }
            let index = tabs.firstIndex { $0.tabViewItem === cell.representedObject as? NSTabViewItem }
            return index.map(String.init) ?? "?"
        }
    }

    private func windowOrder(_ tabs: [PTYTab]) throws -> [Int] {
        let current = try XCTUnwrap(fixture.terminal.tabs())
        return try current.map { tab in try XCTUnwrap(tabs.firstIndex { $0 === tab }) }
    }

    // MARK: - The control

    func testTheBarHasAnOrderControlUnderTheSearchField() throws {
        let control = try orderControl()
        let field = try searchField()
        XCTAssertEqual(control.segmentCount, 3)
        XCTAssertEqual(control.selectedSegment, TabBarOrderMode.manual.rawValue)
        XCTAssertLessThan(control.frame.maxY, field.frame.minY, "below the field")
        XCTAssertGreaterThanOrEqual(try tabBar.insets.top, TabBarSearchController.bandHeight)
    }

    // MARK: - Status

    func testStatusSortsByPriorityAndLeavesTheWindowsOrder() throws {
        let tabs = try makeTabs()
        setStatus("Working", on: tabs[0])
        setStatus("Waiting", on: tabs[2])
        setStatus("Done", on: tabs[3])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["2", "3", "0", "1"])
        XCTAssertEqual(try windowOrder(tabs), [0, 1, 2, 3])

        try pick(.manual)
        XCTAssertEqual(try shown(tabs), ["0", "1", "2", "3"])
    }

    func testAStatusChangeResorts() throws {
        let tabs = try makeTabs(3)
        setStatus("Working", on: tabs[0])
        setStatus("Working", on: tabs[1])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["0", "1", "2"])
        setStatus("Waiting", on: tabs[1])
        XCTAssertEqual(try shown(tabs), ["1", "0", "2"])
    }

    func testSnoozedTabsGoLast() throws {
        let tabs = try makeTabs(3)
        setStatus("Waiting", on: tabs[0])
        setStatus("Working", on: tabs[1])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["0", "1", "2"])
        SessionStatusController.instance.setSnoozed(true, sessionIDs: [tabs[0].activeSession.guid])
        XCTAssertEqual(try shown(tabs), ["1", "2", "0"])
    }

    // Nothing moves under the pointer; changes wait for it to leave.
    func testNothingMovesUnderThePointer() throws {
        let tabs = try makeTabs(4)
        try pick(.status)
        let bar = try tabBar
        bar.pointerIsInsideForTesting = NSNumber(value: true)
        setStatus("Waiting", on: tabs[2])
        XCTAssertEqual(try shown(tabs), ["0", "1", "2", "3"], "waits for the pointer")
        // Anything else refreshing the bar keeps the places too.
        fixture.terminal.updateTabColors()
        XCTAssertEqual(try shown(tabs), ["0", "1", "2", "3"])
        // Next Tab goes by what the bar shows: 2 follows 1 there, but 3
        // would follow it in the new order.
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])

        bar.pointerIsInsideForTesting = NSNumber(value: false)
        bar.delegate?.tabViewPointerDidLeaveTabBar?(fixture.terminal.tabView())
        XCTAssertEqual(try shown(tabs), ["2", "0", "1", "3"])
    }

    // MARK: - Working Directory

    func testWorkingDirectoryShowsASectionForEachDirectory() throws {
        let tabs = try makeTabs()
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/two", on: tabs[1])
        setDirectory("/tmp/one", on: tabs[2])
        setDirectory("/tmp/two", on: tabs[3])
        try pick(.workingDirectory)
        XCTAssertEqual(try shown(tabs), ["[one]", "0", "2", "[two]", "1", "3"])
        XCTAssertEqual(try windowOrder(tabs), [0, 1, 2, 3])
    }

    func testASectionHeadingShowsTheFullPathAsItsToolTip() throws {
        let tabs = try makeTabs(2)
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/one", on: tabs[1])
        try pick(.workingDirectory)
        let chip = try XCTUnwrap((try tabBar.cells() as? [PSMTabBarCell])?.first { $0.isTabGroupChip })
        let group = try XCTUnwrap(try tabBar.tabGroupDataSource?.tabGroup(withIdentifier: chip.tabGroupIdentifier ?? ""))
        XCTAssertEqual(group.toolTip, "/tmp/one")
    }

    func testMoveTabStaysInItsSection() throws {
        let tabs = try makeTabs()
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/two", on: tabs[1])
        setDirectory("/tmp/one", on: tabs[2])
        setDirectory("/tmp/two", on: tabs[3])
        try pick(.workingDirectory)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        fixture.terminal.moveTabRight(nil)
        XCTAssertEqual(try shown(tabs), ["[one]", "2", "0", "[two]", "1", "3"])
        XCTAssertEqual(try windowOrder(tabs), [2, 1, 0, 3], "trades places with 2 in the window too")
        // At the end of its section it wraps around.
        fixture.terminal.moveTabRight(nil)
        XCTAssertEqual(try shown(tabs), ["[one]", "0", "2", "[two]", "1", "3"])
    }

    func testNextTabGoesInTheOrderTheBarShows() throws {
        let tabs = try makeTabs(3)
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/two", on: tabs[1])
        setDirectory("/tmp/one", on: tabs[2])
        try pick(.workingDirectory)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1])
        fixture.terminal.previousTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
    }

    // A swipe goes in the order the bar shows, like Next Tab.
    func testSwipingGoesInTheOrderTheBarShows() throws {
        let tabs = try makeTabs(3)
        setStatus("Waiting", on: tabs[2])
        try pick(.status)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        let handler = try XCTUnwrap((fixture.terminal as AnyObject) as? iTermSwipeHandler)
        let params = handler.swipeHandlerParameters()
        XCTAssertEqual(params.count, 3)
        XCTAssertEqual(params.currentIndex, 1, "tab 0 is second in the bar")
        let session = handler.swipeHandlerBeginSession(atOffset: 0, identifier: "test" as NSString)
        handler.swipeHandlerEndSession(session, at: 0)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2], "the first tab the bar shows")
    }

    // MARK: - Groups, search, drags

    func testGroupsAreNotShownInASortedOrder() throws {
        let tabs = try makeTabs(3)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        for tab in tabs[1...] {
            tab.tabGroupID = "G"
            tab.tabGroupCollapsed = true
        }
        fixture.terminal.updateTabColors()
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["0", "1", "2"], "no chip, nothing collapsed")
        XCTAssertEqual(tabs[1].tabGroupID, "G", "the group is unchanged")
        try pick(.manual)
        let cells = try tabBar.cells() as? [PSMTabBarCell] ?? []
        XCTAssertEqual(cells.filter(\.isTabGroupChip).count, 1, "the group is back")
        XCTAssertTrue(cells.filter { !$0.isTabGroupChip }.dropFirst().allSatisfy(\.isCollapsedHidden),
                      "still collapsed")
    }

    func testSearchingASortedBarHidesTabsThatDontMatch() throws {
        let tabs = try makeTabs(3)
        setStatus("Waiting", on: tabs[2])
        try pick(.status)
        let field = try searchField()
        field.stringValue = "b"
        field.sendAction(field.action, to: field.target)
        XCTAssertEqual(try shown(tabs), ["1"])
        field.stringValue = ""
        field.sendAction(field.action, to: field.target)
        XCTAssertEqual(try shown(tabs), ["2", "0", "1"])
    }

    // A section with no match goes away, as a group does.
    func testSearchingByDirectoryHidesSectionsWithoutMatches() throws {
        let tabs = try makeTabs()
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/two", on: tabs[1])
        setDirectory("/tmp/one", on: tabs[2])
        setDirectory("/tmp/two", on: tabs[3])
        try pick(.workingDirectory)
        let field = try searchField()
        field.stringValue = "b"
        field.sendAction(field.action, to: field.target)
        XCTAssertEqual(try shown(tabs), ["[two]", "1"])
    }

    // A section with a match keeps its hidden tabs, so its heading shows
    // once even when a hidden tab is between two matches.
    func testASectionWithAHiddenTabBetweenMatchesHasOneHeading() throws {
        let tabs = try makeTabs(3)
        tabs[0].titleOverride = "match one"
        tabs[2].titleOverride = "match two"
        waitUntil("titles shown") {
            tabs[0].tabViewItem?.label.hasPrefix("match one") == true &&
            tabs[2].tabViewItem?.label.hasPrefix("match two") == true
        }
        for tab in tabs {
            setDirectory("/tmp/one", on: tab)
        }
        try pick(.workingDirectory)
        let field = try searchField()
        field.stringValue = "match"
        field.sendAction(field.action, to: field.target)
        XCTAssertEqual(try shown(tabs), ["[one]", "0", "2"])
    }

    // Close Tabs Below closes the tabs after it in the window, which a sorted
    // bar may show above it.
    func testCloseTabsBelowIsDisabledInASortedBar() throws {
        let tabs = try makeTabs(3)
        let item = NSMenuItem(title: "", action: NSSelectorFromString("closeTabsToTheRight:"), keyEquivalent: "")
        item.representedObject = tabs[0].tabViewItem
        // Not visible to Swift.
        func validate() -> Bool {
            typealias Validate = @convention(c) (AnyObject, Selector, NSMenuItem) -> Bool
            let selector = NSSelectorFromString("validateMenuItem:")
            return unsafeBitCast(fixture.terminal.method(for: selector), to: Validate.self)(fixture.terminal, selector, item)
        }
        XCTAssertTrue(validate(), "precondition")
        try pick(.status)
        XCTAssertFalse(validate())
        fixture.terminal.perform(NSSelectorFromString("closeTabsToTheRight:"), with: item)
        XCTAssertEqual(fixture.terminal.tabs()?.count, 3)
    }

    // Pinning acts on the tab's whole group, which a sorted bar doesn't show,
    // so its tabs would jump to the top for no visible reason.
    func testPinningIsDisabledInASortedBar() throws {
        let tabs = try makeTabs(3)
        for tab in tabs[1...] {
            tab.tabGroupID = "G"
        }
        fixture.terminal.updateTabColors()
        try pick(.status)
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        fixture.terminal.togglePinTab(nil)
        XCTAssertFalse(tabs[1].isPinned)
        XCTAssertFalse(tabs[2].isPinned)
    }

    func testTabsCantBeDraggedInASortedBar() throws {
        let tabs = try makeTabs(2)
        let bar = try tabBar
        let delegate = try XCTUnwrap(bar.delegate)
        XCTAssertEqual(delegate.tabView?(fixture.terminal.tabView(), shouldDrag: tabs[0].tabViewItem, fromTabBar: bar), true,
                       "precondition")
        try pick(.status)
        XCTAssertEqual(delegate.tabView?(fixture.terminal.tabView(), shouldDrag: tabs[0].tabViewItem, fromTabBar: bar), false)
    }

    // MARK: - Saving

    func testTheOrderIsSavedWithTheWindow() throws {
        try pick(.workingDirectory)
        let arrangement = try XCTUnwrap(fixture.terminal.arrangementExcludingTmuxTabs(false, includingContents: false))
        XCTAssertEqual(arrangement["Tab Bar Order"] as? Int, TabBarOrderMode.workingDirectory.rawValue)

        try pick(.manual)
        let restore = NSSelectorFromString("restoreTabBarOrderFromArrangement:")
        fixture.terminal.perform(restore, with: arrangement)
        XCTAssertEqual(try orderControl().selectedSegment, TabBarOrderMode.workingDirectory.rawValue)
    }

    // Moving the bar to the top puts the window's order and groups back by
    // itself. The selected tab may be in a collapsed group, which a sorted
    // bar doesn't expand, so its group expands then.
    func testMovingTheBarToTheTopRestoresGroupsAndExpandsTheSelectedTabs() throws {
        let tabs = try makeTabs(3)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        for tab in tabs[1...] {
            tab.tabGroupID = "G"
            tab.tabGroupCollapsed = true
        }
        fixture.terminal.updateTabColors()
        setStatus("Waiting", on: tabs[2])
        try pick(.status)
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        XCTAssertTrue(tabs[2].tabGroupCollapsed, "precondition: a sorted bar doesn't expand it")

        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        // A resize lays out the bar, which asks for its insets.
        var frame = fixture.window.frame
        frame.size.width += 10
        fixture.window.setFrame(frame, display: false)
        waitUntil("the group expands") { !tabs[2].tabGroupCollapsed }
        XCTAssertEqual(try shown(tabs), ["0", "[]", "1", "2"], "the unnamed group's chip, then its tabs")
    }

    // Settings change the tab position and refresh the window, which updates
    // the groups before the bar is laid out.
    func testMovingTheBarToTheTopInSettingsExpandsTheSelectedTabsGroup() throws {
        let tabs = try makeTabs(3)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        for tab in tabs[1...] {
            tab.tabGroupID = "G"
            tab.tabGroupCollapsed = true
        }
        fixture.terminal.updateTabColors()
        try pick(.status)
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        XCTAssertTrue(tabs[2].tabGroupCollapsed, "precondition")

        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        fixture.terminal.updateTabColors()
        XCTAssertFalse(tabs[2].tabGroupCollapsed)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
    }

    // Restoring tmux tabs settles groups, which mustn't move the selection
    // out of a group the sorted bar doesn't show.
    func testSettlingGroupsLeavesTheSelectionWhileSorted() throws {
        let tabs = try makeTabs(3)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        for tab in tabs[1...] {
            tab.tabGroupID = "G"
            tab.tabGroupCollapsed = true
        }
        fixture.terminal.updateTabColors()
        try pick(.status)
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        fixture.terminal.perform(NSSelectorFromString("settleTabGroupsAfterDeferredExpansion"))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2], "the selection stays")
        XCTAssertTrue(tabs[1].tabGroupCollapsed, "groups are unchanged underneath")
    }

    // The bar can become able to show its order again by layout alone, as
    // when it moves back to the side or reappears in full screen.
    func testMovingTheBarBackToTheSideShowsTheOrderAgain() throws {
        let tabs = try makeTabs(3)
        setStatus("Waiting", on: tabs[2])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["2", "0", "1"])
        func resize() {
            var frame = fixture.window.frame
            frame.size.width += 10
            fixture.window.setFrame(frame, display: false)
        }
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        resize()
        waitUntil("the window's order") { (try? self.shown(tabs)) == ["0", "1", "2"] }
        iTermPreferences.setInt(2 /* PSMTab_LeftTab */, forKey: kPreferenceKeyTabPosition)
        resize()
        waitUntil("sorted again") { (try? self.shown(tabs)) == ["2", "0", "1"] }
    }

    // A sorted bar shows no groups, so collapsing one wouldn't show, but
    // would move the selection out of it.
    func testCollapsingAGroupIsIgnoredWhileSorted() throws {
        let tabs = try makeTabs(3)
        for tab in tabs[1...] {
            tab.tabGroupID = "G"
        }
        fixture.terminal.updateTabColors()
        try pick(.status)
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        let collapse = NSSelectorFromString("collapseTabGroup:animated:")
        typealias Collapse = @convention(c) (AnyObject, Selector, NSString, Bool) -> Void
        unsafeBitCast(fixture.terminal.method(for: collapse), to: Collapse.self)(fixture.terminal, collapse, "G", false)
        XCTAssertFalse(tabs[1].tabGroupCollapsed)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1], "the selection stays")
    }

    // Moves stay among a group's tabs, which the window keeps together.
    func testMoveTabStaysInItsGroup() throws {
        let tabs = try makeTabs(3)
        for tab in tabs[0...1] {
            tab.tabGroupID = "G"
        }
        fixture.terminal.updateTabColors()
        try pick(.status)
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        fixture.terminal.moveTabRight(nil)
        XCTAssertEqual(try windowOrder(tabs), [1, 0, 2], "wraps within the group")
        XCTAssertEqual(try shown(tabs), ["1", "0", "2"])
    }

    // A horizontal bar has no control, so it shows the window's order.
    func testAHorizontalBarShowsTheWindowsOrder() throws {
        let tabs = try makeTabs(3)
        setStatus("Waiting", on: tabs[2])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["2", "0", "1"])
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        fixture.terminal.updateTabColors()
        XCTAssertEqual(try shown(tabs), ["0", "1", "2"])
    }
}

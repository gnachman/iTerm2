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
            bar.pointerIsHoldingTabsForTesting = NSNumber(value: false)
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

    private func orderButton() throws -> NSButton {
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let accessory = try XCTUnwrap(try tabBar.topAccessoryView)
        return try XCTUnwrap(accessory.subviews.first { $0 is NSButton && !($0 is NSSearchField) } as? NSButton)
    }

    private var orderMenu: NSMenu {
        get throws {
            return try XCTUnwrap(fixture.terminal.tabBarSearchController?.orderMenu)
        }
    }

    // The order the menu shows as chosen.
    private func checkedOrder() throws -> Int? {
        return try orderMenu.items.first { $0.state == .on }?.tag
    }

    private func searchField() throws -> NSSearchField {
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let accessory = try XCTUnwrap(try tabBar.topAccessoryView)
        return try XCTUnwrap(accessory.subviews.compactMap { $0 as? NSSearchField }.first)
    }

    private func pick(_ mode: TabBarOrderMode) throws {
        let menu = try orderMenu
        let index = menu.indexOfItem(withTag: mode.rawValue)
        XCTAssertNotEqual(index, -1)
        menu.performActionForItem(at: index)
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

    func testTheBarHasAnOrderButtonBesideTheSearchField() throws {
        let button = try orderButton()
        let field = try searchField()
        XCTAssertEqual(try orderMenu.items.map(\.tag),
                       [TabBarOrderMode.manual, .status, .workingDirectory].map(\.rawValue))
        XCTAssertEqual(try checkedOrder(), TabBarOrderMode.manual.rawValue)
        XCTAssertGreaterThanOrEqual(button.frame.minX, field.frame.maxX, "after the field")
        XCTAssertGreaterThanOrEqual(try tabBar.insets.top, TabBarSearchController.bandHeight)
    }

    // So it's clear the bar isn't in the usual order.
    func testTheOrderButtonIsTintedWhileSorted() throws {
        _ = try makeTabs(2)
        try pick(.status)
        XCTAssertEqual(try orderButton().contentTintColor, .controlAccentColor)
        XCTAssertEqual(try checkedOrder(), TabBarOrderMode.status.rawValue)
        try pick(.manual)
        XCTAssertEqual(try orderButton().contentTintColor, .secondaryLabelColor)
    }

    // MARK: - Status

    func testStatusSortsByPriorityAndLeavesTheWindowsOrder() throws {
        let tabs = try makeTabs()
        setStatus("Working", on: tabs[0])
        setStatus("Waiting", on: tabs[2])
        setStatus("Done", on: tabs[3])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "2", "[Done]", "3", "[Working]", "0", "[No Status]", "1"])
        XCTAssertEqual(try windowOrder(tabs), [0, 1, 2, 3])

        try pick(.manual)
        XCTAssertEqual(try shown(tabs), ["0", "1", "2", "3"])
    }

    func testAStatusChangeResorts() throws {
        let tabs = try makeTabs(3)
        setStatus("Working", on: tabs[0])
        setStatus("Working", on: tabs[1])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["[Working]", "0", "1", "[No Status]", "2"])
        setStatus("Waiting", on: tabs[1])
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "1", "[Working]", "0", "[No Status]", "2"])
        // Where they're drawn, not only the order of the cells.
        XCTAssertEqual(try drawnTopToBottom(tabs), ["1", "0", "2"])
    }

    // Tabs by their index in `tabs`, sorted by where the bar draws them.
    private func drawnTopToBottom(_ tabs: [PTYTab]) throws -> [String] {
        let cells = (try tabBar.cells() as? [PSMTabBarCell] ?? []).filter {
            !$0.isTabGroupChip && !$0.isCollapsedHidden
        }
        return cells.sorted { $0.frame.minY < $1.frame.minY }.compactMap { cell in
            tabs.firstIndex { $0.tabViewItem === cell.representedObject as? NSTabViewItem }.map(String.init)
        }
    }

    func testSnoozedTabsGoLast() throws {
        let tabs = try makeTabs(3)
        setStatus("Waiting", on: tabs[0])
        setStatus("Working", on: tabs[1])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "0", "[Working]", "1", "[No Status]", "2"])
        SessionStatusController.instance.setSnoozed(true, sessionIDs: [tabs[0].activeSession.guid])
        XCTAssertEqual(try shown(tabs), ["[Working]", "1", "[No Status]", "2", "[Snoozed]", "0"])
    }

    // Nothing moves under the pointer; changes wait for it to leave.
    func testNothingMovesUnderThePointer() throws {
        let tabs = try makeTabs(4)
        try pick(.status)
        let bar = try tabBar
        bar.pointerIsHoldingTabsForTesting = NSNumber(value: true)
        setStatus("Waiting", on: tabs[2])
        XCTAssertEqual(try shown(tabs), ["[No Status]", "0", "1", "2", "3"], "waits for the pointer")
        // Anything else refreshing the bar keeps the places too.
        fixture.terminal.updateTabColors()
        XCTAssertEqual(try shown(tabs), ["[No Status]", "0", "1", "2", "3"])
        // Next Tab goes by what the bar shows: 2 follows 1 there, but 3
        // would follow it in the new order.
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])

        bar.pointerIsHoldingTabsForTesting = NSNumber(value: false)
        bar.delegate?.tabViewPointerDidReleaseTabBar?(fixture.terminal.tabView())
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "2", "[No Status]", "0", "1", "3"])
    }

    // A pointer resting over the bar stops holding tabs, and what waited for
    // it is applied without the pointer leaving.
    func testChangesApplyWhenThePointerRestsOverTheBar() throws {
        let tabs = try makeTabs(4)
        try pick(.status)
        let bar = try tabBar
        var now: TimeInterval = 1000
        bar.pointerIsHoldingTabsForTesting = nil
        bar.pointerIsInsideForTesting = NSNumber(value: true)
        bar.pressedMouseButtonsForTesting = NSNumber(value: 0)
        bar.pointerClockForTesting = { now }
        bar.pointerIdleTimerSchedulerForTesting = { _ in }
        defer {
            bar.pointerIsInsideForTesting = nil
            bar.pressedMouseButtonsForTesting = nil
            bar.pointerClockForTesting = nil
            bar.pointerIdleTimerSchedulerForTesting = nil
            bar.pointerIsHoldingTabsForTesting = NSNumber(value: false)
        }

        bar.pointerDidMove()
        setStatus("Waiting", on: tabs[2])
        XCTAssertEqual(try shown(tabs), ["[No Status]", "0", "1", "2", "3"], "waits while the pointer moves")

        now += PSMTabBarPointerHoldInterval
        bar.pointerIdleTimerDidFire()
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "2", "[No Status]", "0", "1", "3"])
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

    // A restored session without shell integration has no path variable,
    // but its directory is known.
    func testATabWithNoPathVariableGoesUnderItsLastKnownDirectory() throws {
        let tabs = try makeTabs(2)
        setDirectory("/tmp/one", on: tabs[1])
        // The tracker learns the directory, as from a restored arrangement,
        // but the variable doesn't have it.
        tabs[0].activeSession.screenLogWorkingDirectory(onAbsoluteLine: 0,
                                                        remoteHost: nil,
                                                        withDirectory: "/tmp/two",
                                                        pushType: .strongPush,
                                                        locality: .unverified,
                                                        accepted: true)
        tabs[0].activeSession.genericScope.setValue(nil, forVariableNamed: iTermVariableKeySessionPath)
        XCTAssertNil(tabs[0].activeSession.genericScope.value(forVariableName: iTermVariableKeySessionPath))
        try pick(.workingDirectory)
        waitUntil("placed under a directory") {
            let shown = (try? self.shown(tabs)) ?? []
            return shown == ["[two]", "0", "[one]", "1"]
        }
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

    // A heading is a quiet line of text, not a group: the styles don't
    // decorate it, and it says where the directory is.
    func testSectionHeadingsAreNotDecoratedAsGroups() throws {
        let tabs = try makeTabs(2)
        setDirectory(NSHomeDirectory() + "/git/one", on: tabs[0])
        setDirectory("/tmp/two", on: tabs[1])
        try pick(.workingDirectory)
        let bar = try tabBar
        let chips = (try bar.cells() as? [PSMTabBarCell] ?? []).filter { $0.isTabGroupChip }
        XCTAssertEqual(chips.count, 2)
        let groups = try chips.map { try XCTUnwrap(bar.tabGroupDataSource?.tabGroup(withIdentifier: $0.tabGroupIdentifier ?? "")) }
        XCTAssertEqual(groups.map { $0.isSectionHeading }, [true, true])
        XCTAssertEqual(groups.map { $0.detail }, ["~/git/", "/tmp/"])
        var decorated = [String]()
        bar.enumerateTabGroupRuns(rectForCell: nil) { _, _, _, gid in
            decorated.append(gid)
        }
        XCTAssertEqual(decorated, [])
        XCTAssertTrue(bar.hasSectionHeadings)

        try pick(.manual)
        XCTAssertFalse(bar.hasSectionHeadings)
    }

    // A heading is one short line, much shorter than a tab, so it reads as
    // a label for the tabs under it rather than an empty row.
    func testSectionHeadingsAreAsTallAsOneLineOfText() throws {
        let tabs = try makeTabs(2)
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/two", on: tabs[1])
        try pick(.workingDirectory)
        let bar = try tabBar
        bar.layoutSubtreeIfNeeded()
        let cells = try bar.cells() as? [PSMTabBarCell] ?? []
        // The room a cell takes is from its top to the next cell's.
        func room(_ i: Int) -> CGFloat {
            return cells[i + 1].frame.minY - cells[i].frame.minY
        }
        let chipIndexes = cells.indices.filter { cells[$0].isTabGroupChip }
        guard chipIndexes == [0, 2], cells.count == 4 else {
            XCTFail("Expected a heading over each tab, got chips at \(chipIndexes) of \(cells.count) cells")
            return
        }
        for i in chipIndexes {
            XCTAssertEqual(room(i), bar.sectionHeadingHeight)
        }
        XCTAssertLessThan(bar.sectionHeadingHeight, room(1))
    }

    // A heading's text is as big as the tab titles under it.
    func testSectionHeadingsAreAsBigAsTabTitles() throws {
        let tabs = try makeTabs(2)
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/two", on: tabs[1])
        try pick(.workingDirectory)
        let bar = try tabBar
        XCTAssertEqual(bar.sectionHeadingFontSize, try XCTUnwrap(bar.style.fontSize))
    }

    // Tabs under a heading are indented, so the heading reads as their
    // parent. Tabs that aren't in a section aren't.
    func testTabsUnderAHeadingAreIndented() throws {
        let tabs = try makeTabs(2)
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/two", on: tabs[1])
        let bar = try tabBar
        func tabFrames() -> [NSRect] {
            bar.layoutSubtreeIfNeeded()
            let cells = (try? bar.cells() as? [PSMTabBarCell]) ?? []
            return cells.filter { !$0.isTabGroupChip }.map(\.frame)
        }
        let manual = tabFrames()
        let unindented = try XCTUnwrap(manual.first?.minX)
        XCTAssertEqual(manual.map(\.minX), [unindented, unindented])

        try pick(.workingDirectory)
        let sorted = tabFrames()
        XCTAssertGreaterThan(bar.sectionTabIndent, 0)
        let indented = unindented + bar.sectionTabIndent
        XCTAssertEqual(sorted.map(\.minX), [indented, indented])
        XCTAssertEqual(sorted.map(\.maxX), manual.map(\.maxX), "the right edge stays put")

        try pick(.manual)
        XCTAssertEqual(tabFrames().map(\.minX), [unindented, unindented])
    }

    // The strip beside an indented tab looks like part of its row, so a
    // click there goes to the tab.
    func testAClickBesideAnIndentedTabHitsIt() throws {
        let tabs = try makeTabs(2)
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/one", on: tabs[1])
        try pick(.workingDirectory)
        let bar = try tabBar
        bar.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap((try bar.cells() as? [PSMTabBarCell])?.first { !$0.isTabGroupChip })
        let point = NSPoint(x: cell.frame.minX - bar.sectionTabIndent / 2, y: cell.frame.midY)
        XCTAssertTrue(bar.cell(for: point, cellFrame: nil) as? PSMTabBarCell === cell)
    }

    // Also when tabs are selected on mouse-up, which checks the click ended
    // where it started.
    func testAClickBesideAnIndentedTabSelectsItOnMouseUp() throws {
        let tabs = try makeTabs(2)
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/one", on: tabs[1])
        try pick(.workingDirectory)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        let bar = try tabBar
        let saved = bar.selectsTabsOnMouseDown
        bar.selectsTabsOnMouseDown = false
        defer { bar.selectsTabsOnMouseDown = saved }
        bar.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap((try bar.cells() as? [PSMTabBarCell])?.first {
            $0.representedObject as? NSTabViewItem === tabs[1].tabViewItem
        })
        let point = bar.convert(NSPoint(x: cell.frame.minX - bar.sectionTabIndent / 2, y: cell.frame.midY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            return NSEvent.mouseEvent(with: type,
                                      location: point,
                                      modifierFlags: [],
                                      timestamp: 0,
                                      windowNumber: fixture.window.windowNumber,
                                      context: nil,
                                      eventNumber: 0,
                                      clickCount: 1,
                                      pressure: 1)!
        }
        bar.mouseDown(with: event(.leftMouseDown))
        bar.mouseUp(with: event(.leftMouseUp))
        XCTAssertTrue(fixture.terminal.tabView().selectedTabViewItem === tabs[1].tabViewItem)
    }

    // Tahoe's selected tab is a rounded pill that would cover a guide line at
    // its edge, so its tabs sit a little to the right of the line. A style
    // whose tabs are flat fills keeps the line at the tab's edge.
    func testTahoeTabsLeaveRoomForTheGuide() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let bar = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        bar.style = PSMYosemiteTabStyle()
        XCTAssertEqual(bar.sectionTabIndent, bar.sectionGuideOffset)
        bar.style = PSMTahoeDarkTabStyle()
        XCTAssertGreaterThanOrEqual(bar.sectionTabIndent - bar.sectionGuideOffset, 4)
    }

    // A section coming or going slides the rows into place. The slide keeps
    // headings where they belong and tabs under them indented.
    func testRowsKeepTheirIndentWhileSliding() throws {
        let tabs = try makeTabs(2)
        setDirectory("/tmp/one", on: tabs[0])
        setDirectory("/tmp/one", on: tabs[1])
        try pick(.workingDirectory)
        let bar = try tabBar
        bar.layoutSubtreeIfNeeded()
        func chipsAndTabs() -> (chips: [CGFloat], tabs: [CGFloat]) {
            let cells = (try? bar.cells() as? [PSMTabBarCell]) ?? []
            return (cells.filter { $0.isTabGroupChip }.map(\.frame.minX),
                    cells.filter { !$0.isTabGroupChip }.map(\.frame.minX))
        }
        let settled = chipsAndTabs()
        let headingX = try XCTUnwrap(settled.chips.first)
        let tabX = try XCTUnwrap(settled.tabs.first)
        XCTAssertEqual(tabX, headingX + bar.sectionTabIndent, "precondition")

        // A new section appears without the window settling the bar.
        setDirectory("/tmp/two", on: tabs[1])
        fixture.terminal.updateTabColors()
        XCTAssertTrue(bar.collapseAnimating, "precondition: sliding")
        let sliding = chipsAndTabs()
        XCTAssertEqual(sliding.chips.count, 2)
        XCTAssertEqual(sliding.chips, sliding.chips.map { _ in headingX })
        XCTAssertEqual(sliding.tabs, sliding.tabs.map { _ in tabX })
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
        XCTAssertEqual(try shown(tabs), ["[No Status]", "0", "1", "2"], "no group chip, nothing collapsed")
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
        XCTAssertEqual(try shown(tabs), ["[No Status]", "1"])
        field.stringValue = ""
        field.sendAction(field.action, to: field.target)
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "2", "[No Status]", "0", "1"])
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
        XCTAssertEqual(try checkedOrder(), TabBarOrderMode.workingDirectory.rawValue)
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
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "2", "[No Status]", "0", "1"])
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
        waitUntil("sorted again") { (try? self.shown(tabs)) == ["[Waiting]", "2", "[No Status]", "0", "1"] }
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
        XCTAssertEqual(try shown(tabs), ["[No Status]", "1", "0", "2"])
    }

    // The headings name the priority patterns, so editing the list in
    // Settings renames and re-sorts them.
    func testEditingThePriorityListUpdatesTheHeadings() throws {
        let tabs = try makeTabs(2)
        setStatus("Waiting", on: tabs[1])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "1", "[No Status]", "0"])
        StatusPrioritySettings.shared.restoreEntries([StatusPriorityEntry(pattern: "for input")])
        XCTAssertEqual(try shown(tabs), ["[Other]", "1", "[No Status]", "0"])
        StatusPrioritySettings.shared.restoreEntries([StatusPriorityEntry(pattern: "waiting")])
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "1", "[No Status]", "0"], "named by the custom pattern")
    }

    // A horizontal bar has no control, so it shows the window's order.
    func testAHorizontalBarShowsTheWindowsOrder() throws {
        let tabs = try makeTabs(3)
        setStatus("Waiting", on: tabs[2])
        try pick(.status)
        XCTAssertEqual(try shown(tabs), ["[Waiting]", "2", "[No Status]", "0", "1"])
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        fixture.terminal.updateTabColors()
        XCTAssertEqual(try shown(tabs), ["0", "1", "2"])
    }
}

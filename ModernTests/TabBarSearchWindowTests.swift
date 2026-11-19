//
//  TabBarSearchWindowTests.swift
//  ModernTests
//
//  The search field atop a vertical tab bar, in a real window: typing hides
//  tabs that don't match, Esc puts them back, Return goes to the first match.
//

import XCTest
@testable import iTerm2SharedARC

final class TabBarSearchWindowTests: XCTestCase {
    private var savedTabPosition: Int32 = 0
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        savedTabPosition = iTermPreferences.int(forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setInt(2 /* PSMTab_LeftTab */, forKey: kPreferenceKeyTabPosition)
        fixture = TerminalWindowTestFixture()
        // Wherever the real pointer is, tests start with it off the bar, so
        // text changes apply. Tests about the pointer set it themselves.
        if let bar = findTabBar(in: fixture.window.contentView?.superview ?? NSView()) {
            bar.pointerIsInsideForTesting = NSNumber(value: false)
        }
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        iTermPreferences.setInt(savedTabPosition, forKey: kPreferenceKeyTabPosition)
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

    // Three tabs titled alpha, beta and alphabet.
    private func makeTabs() throws -> [PTYTab] {
        _ = fixture.addTab()
        _ = fixture.addTab()
        let tabs = try XCTUnwrap(fixture.terminal.tabs())
        XCTAssertEqual(tabs.count, 3)
        for (tab, title) in zip(tabs, ["alpha", "beta", "alphabet"]) {
            tab.titleOverride = title
        }
        waitUntil("titles shown") {
            zip(tabs, ["alpha", "beta", "alphabet"]).allSatisfy { $0.tabViewItem?.label.contains($1) == true }
        }
        return tabs
    }

    private func searchField() throws -> NSSearchField {
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        return try XCTUnwrap(try tabBar.topAccessoryView as? NSSearchField)
    }

    private func type(_ text: String) throws {
        let field = try searchField()
        field.stringValue = text
        field.sendAction(field.action, to: field.target)
    }

    private func press(_ command: Selector) throws {
        let field = try searchField()
        let delegate = try XCTUnwrap(field.delegate as? NSControlTextEditingDelegate)
        XCTAssertEqual(delegate.control?(field, textView: NSTextView(), doCommandBy: command), true)
    }

    private func hidden(_ tabs: [PTYTab]) throws -> [Bool] {
        let cells = try tabBar.cells() as? [PSMTabBarCell] ?? []
        return try tabs.map { tab in
            let cell = try XCTUnwrap(cells.first { $0.representedObject as? NSTabViewItem === tab.tabViewItem },
                                     "no cell for \(tab)")
            return cell.isCollapsedHidden
        }
    }

    func testTheBarHasASearchField() throws {
        let field = try searchField()
        XCTAssertFalse(field.isHidden)
        let bar = try tabBar
        XCTAssertGreaterThanOrEqual(bar.insets.top, TabBarSearchController.bandHeight)
    }

    // A window takes its tab style when it opens.
    private func reopenInMinimalStyle() throws {
        iTermPreferences.setInt(5 /* TAB_STYLE_MINIMAL */, forKey: kPreferenceKeyTabStyle)
        fixture.close()
        fixture = TerminalWindowTestFixture()
        try tabBar.pointerIsInsideForTesting = NSNumber(value: false)
        XCTAssertNotNil(try tabBar.style.accessoryAppearance, "precondition: the Minimal style")
    }

    // In the Minimal style the bar takes the terminal's background color, so
    // the field follows it from light to dark and back.
    func testTheFieldFollowsTheBackgroundInTheMinimalStyle() throws {
        let savedTabStyle = iTermPreferences.int(forKey: kPreferenceKeyTabStyle)
        defer {
            iTermPreferences.setInt(savedTabStyle, forKey: kPreferenceKeyTabStyle)
        }
        try reopenInMinimalStyle()
        let session = try XCTUnwrap(fixture.terminal.currentSession())
        let field = try searchField()
        func appearanceName() -> NSAppearance.Name? {
            return field.appearance?.bestMatch(from: [.aqua, .darkAqua])
        }

        _ = session.screenSetColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                                   profileKey: KEY_BACKGROUND_COLOR)
        XCTAssertEqual(appearanceName(), .darkAqua)

        _ = session.screenSetColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                   profileKey: KEY_BACKGROUND_COLOR)
        XCTAssertEqual(appearanceName(), .aqua)
    }

    // Light or dark is judged as the bar judges it for its own buttons, so
    // the field never disagrees with the bar it sits on.
    func testTheFieldMatchesTheBarsButtonsInTheMinimalStyle() throws {
        let savedTabStyle = iTermPreferences.int(forKey: kPreferenceKeyTabStyle)
        defer {
            iTermPreferences.setInt(savedTabStyle, forKey: kPreferenceKeyTabStyle)
        }
        try reopenInMinimalStyle()
        let session = try XCTUnwrap(fixture.terminal.currentSession())
        let field = try searchField()
        // Magenta: dark by one common brightness formula, light by another.
        _ = session.screenSetColor(NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1),
                                   profileKey: KEY_BACKGROUND_COLOR)
        let barAppearance = try XCTUnwrap(try tabBar.style.accessoryAppearance)
        XCTAssertNotNil(field.appearance)
        XCTAssertEqual(field.appearance?.name, barAppearance.name)
    }

    func testTypingHidesTabsThatDontMatch() throws {
        let tabs = try makeTabs()
        try type("alpha")
        XCTAssertEqual(try hidden(tabs), [false, true, false])
        // A match can be dragged out to another window, but not dropped
        // back among hidden tabs.
        XCTAssertTrue(fixture.terminal.tabView(fixture.terminal.tabView(),
                                               shouldDrag: tabs[0].tabViewItem,
                                               fromTabBar: try tabBar))
        var moveWindow = ObjCBool(false)
        XCTAssertFalse(fixture.terminal.tabView(fixture.terminal.tabView(),
                                                shouldDrop: try XCTUnwrap(tabs[0].tabViewItem),
                                                inTabBar: try tabBar,
                                                moveSourceWindow: &moveWindow))
    }

    func testEscapePutsThemBack() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("beta")
        XCTAssertEqual(try hidden(tabs), [true, false, true])
        try press(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(try searchField().stringValue, "")
        XCTAssertEqual(try hidden(tabs), [false, false, false])
    }

    func testReturnGoesToTheFirstMatch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("bet")
        try press(#selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1])
        XCTAssertEqual(try searchField().stringValue, "")
        XCTAssertEqual(try hidden(tabs), [false, false, false])
    }

    // Tabs 1 and 2 in a collapsed group G, with tab 0, outside it, selected,
    // as the app requires.
    private func collapsedGroup(_ tabs: [PTYTab]) throws {
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        // Each member records the group's collapsed state.
        for tab in tabs[1...] {
            tab.tabGroupID = "G"
            tab.tabGroupCollapsed = true
        }
        fixture.terminal.updateTabColors()
        XCTAssertEqual(try hidden(tabs), [false, true, true], "precondition: collapsed")
    }

    // A group stays if it has a match, even collapsed, and shows only that.
    func testCollapsedGroupWithAMatchOpens() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alphabet")
        // Tab 0 doesn't match, so it's hidden though it's selected.
        XCTAssertEqual(try hidden(tabs), [true, true, false])
        try press(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(try hidden(tabs), [false, true, true], "collapsed again")
    }

    // Clicking a chip would change the group's real state, which the search
    // hides, so it does nothing until the search ends.
    func testChipClickDuringSearchChangesNothing() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alphabet")
        fixture.terminal.tabView(fixture.terminal.tabView(), toggleCollapseOfTabGroup: "G")
        XCTAssertTrue(tabs[1].tabGroupCollapsed)
        try press(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(try hidden(tabs), [false, true, true], "still collapsed")
    }

    // Group drags stay off during a search. A tab from another window can be
    // dropped in; this bar's own tabs can't (see testTypingHidesTabsThatDontMatch).
    func testNoGroupDragsDuringSearchButOtherWindowsTabsDrop() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        let terminal = fixture.terminal
        let bar = try tabBar
        // A tab from somewhere else.
        let stranger = NSTabViewItem(identifier: nil)
        var moveWindow = ObjCBool(false)
        XCTAssertTrue(terminal.tabView(terminal.tabView(), shouldDragTabGroup: "G"))
        XCTAssertTrue(terminal.tabView(terminal.tabView(), shouldDrop: stranger, inTabBar: bar, moveSourceWindow: &moveWindow))

        try type("alphabet")
        XCTAssertFalse(terminal.tabView(terminal.tabView(), shouldDragTabGroup: "G"))
        XCTAssertTrue(terminal.tabView(terminal.tabView(), shouldDrop: stranger, inTabBar: bar, moveSourceWindow: &moveWindow))
    }

    // Each keystroke would otherwise restart the collapse animation, so
    // hidden tabs would pop back and shrink again while typing.
    func testSearchDoesNotAnimate() throws {
        let tabs = try makeTabs()
        try type("alpha")
        XCTAssertFalse(try tabBar.collapseAnimating)
        XCTAssertEqual(try hidden(tabs), [false, true, false])
        try type("alphab")
        XCTAssertFalse(try tabBar.collapseAnimating)
    }

    // A horizontal bar has no field, so the search ends rather than coming
    // back when the bar is vertical again.
    func testMovingTheBarToTheTopEndsTheSearch() throws {
        let tabs = try makeTabs()
        try type("beta")
        let field = try searchField()
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        // A resize lays out the bar, which asks for its insets.
        var frame = fixture.window.frame
        frame.size.width += 10
        fixture.window.setFrame(frame, display: false)
        waitUntil("search ended") { field.stringValue.isEmpty }
        // The window shows every tab again by itself.
        waitUntil("tabs shown") { (try? self.hidden(tabs)) == [false, false, false] }
    }

    // The field is hidden on a horizontal bar, so focus goes back to the
    // terminal rather than nowhere, even with nothing typed.
    func testMovingTheBarToTheTopWhileTheFieldHasFocusFocusesTheTerminal() throws {
        let field = try searchField()
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let session = try XCTUnwrap(fixture.terminal.currentSession())
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        var frame = fixture.window.frame
        frame.size.width += 10
        fixture.window.setFrame(frame, display: false)
        waitUntil("the terminal has focus") {
            self.fixture.window.firstResponder === session.textview
        }
    }

    private func order(_ tabs: [PTYTab]) throws -> [Int] {
        let current = try XCTUnwrap(fixture.terminal.tabs())
        return try current.map { tab in try XCTUnwrap(tabs.firstIndex { $0 === tab }) }
    }

    // Move Tab Left and Right go by what the bar shows: past hidden tabs.
    func testMoveSkipsHiddenTabs() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("alpha")
        fixture.terminal.moveTabLeft(nil)
        XCTAssertEqual(try order(tabs), [2, 1, 0])
        XCTAssertEqual(try hidden(tabs), [false, true, false])
        // At the edge of what's shown it wraps around, as it does without a
        // search, and the hidden tab keeps its place.
        fixture.terminal.moveTabLeft(nil)
        XCTAssertEqual(try order(tabs), [1, 0, 2])
    }

    // An ungrouped tab passes over a group rather than joining it.
    func testMovePassesOverAGroup() throws {
        let tabs = try makeTabs()
        _ = fixture.addTab()
        let all = try XCTUnwrap(fixture.terminal.tabs())
        all[3].titleOverride = "alpha four"
        waitUntil("title shown") { all[3].tabViewItem?.label.contains("alpha four") == true }
        tabs[1].tabGroupID = "G"
        tabs[2].tabGroupID = "G"
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        // One step: past the group, leaving alpha four where it is.
        fixture.terminal.moveTabRight(nil)
        XCTAssertEqual(try order(all), [1, 2, 0, 3])
        XCTAssertNil(tabs[0].tabGroupID, "still ungrouped")
        XCTAssertEqual(tabs[1].tabGroupID, "G")
        XCTAssertEqual(tabs[2].tabGroupID, "G")
        XCTAssertEqual(try hidden(all), [false, true, false, false])
        fixture.terminal.moveTabRight(nil)
        XCTAssertEqual(try order(all), [1, 2, 3, 0])
        // At the right edge it wraps around to the top, past the group.
        fixture.terminal.moveTabRight(nil)
        XCTAssertEqual(try order(all), [0, 1, 2, 3])
        XCTAssertNil(tabs[0].tabGroupID)
        XCTAssertEqual(tabs[1].tabGroupID, "G")
    }

    // Whether any pixel of the bar, as drawn, is the highlight color.
    private func barShowsHighlight() throws -> Bool {
        let bar = try tabBar
        bar.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(bar.bitmapImageRepForCachingDisplay(in: bar.bounds))
        bar.cacheDisplay(in: bar.bounds, to: rep)
        // Clearly yellow. Drawing shifts the exact color a little.
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if color.redComponent > 0.85 && color.greenComponent > 0.75 && color.blueComponent < 0.6 {
                    return true
                }
            }
        }
        return false
    }

    // Matches are drawn highlighted while searching, and only then.
    func testMatchesAreHighlighted() throws {
        _ = try makeTabs()
        XCTAssertFalse(try barShowsHighlight(), "precondition")
        try type("alpha")
        XCTAssertEqual(try tabBar.searchHighlightQuery, "alpha")
        XCTAssertTrue(try barShowsHighlight())
        try press(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertNil(try tabBar.searchHighlightQuery)
        XCTAssertFalse(try barShowsHighlight())
    }

    // Next and previous tab go among the matches.
    func testNextAndPreviousTabGoAmongMatches() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0], "wraps around")
        fixture.terminal.previousTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
    }

    // The Select Next Tab and Select Previous Tab menu items send their
    // actions up the responder chain, where the tab view comes before the
    // window controller.
    func testMenuItemsGoAmongMatches() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        let tabView = try XCTUnwrap(fixture.terminal.tabView())
        tabView.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        tabView.previousTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0])
        tabView.previousTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2], "wraps around")
    }

    // Without a search, they still visit every tab and wrap around.
    func testMenuItemsWithoutASearch() throws {
        let tabs = try makeTabs()
        let tabView = try XCTUnwrap(fixture.terminal.tabView())
        tabView.selectTabViewItem(tabs[2].tabViewItem)
        tabView.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0])
        tabView.previousTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        tabView.previousTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1])
    }

    // Only matches are shown, the selected tab included. Selecting a shown
    // tab never changes what's shown, so nothing moves under the mouse.
    func testTheSelectedTabIsHiddenIfItDoesNotMatch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        XCTAssertEqual(try hidden(tabs), [false, true, false])
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        XCTAssertEqual(try hidden(tabs), [false, true, false])
        try type("alph")
        XCTAssertEqual(try hidden(tabs), [false, true, false])
    }

    // Going to a hidden tab some other way, as Cmd-number, Open Quickly or a
    // notification can, ends the search rather than leaving the selected tab
    // invisible.
    func testSelectingAHiddenTabEndsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1])
        XCTAssertEqual(try searchField().stringValue, "")
        XCTAssertEqual(try hidden(tabs), [false, false, false])
    }

    // A search started while the selected tab doesn't match hides it, and
    // that alone doesn't end the search.
    func testStartingASearchThatHidesTheSelectedTabKeepsIt() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1])
        XCTAssertEqual(try searchField().stringValue, "alpha")
        XCTAssertEqual(try hidden(tabs), [false, true, false])
    }

    // Moving the hidden selected tab, as a group change's tidying can,
    // reselects it, which isn't going to a hidden tab.
    func testMovingTheHiddenSelectedTabKeepsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        try tabBar.moveTab(at: 1, to: 0)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1])
        XCTAssertEqual(try searchField().stringValue, "alpha")
    }

    // A tab opened in the background ends the search too, unless the user is
    // typing a query: whether it matches isn't known yet, since its title
    // comes later.
    func testABackgroundTabEndsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        fixture.terminal.automaticallySelectNewTabs = false
        _ = fixture.addTab()
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0], "opened in the background")
        XCTAssertEqual(try searchField().stringValue, "")
        let all = try XCTUnwrap(fixture.terminal.tabs())
        XCTAssertEqual(try hidden(all), [false, false, false, false])
    }

    // Acting on the current tab when the search hides it, here moving it,
    // ends the search first, so the user sees the tab it acts on.
    func testMovingAHiddenCurrentTabEndsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        fixture.terminal.moveTabRight(nil)
        XCTAssertEqual(try searchField().stringValue, "")
        XCTAssertTrue(try XCTUnwrap(fixture.terminal.tabs())[2] === tabs[1], "moved")
    }

    // While the user types a query, a tab opened in the background leaves
    // the search alone. It shows only if it matches.
    func testABackgroundTabWhileTypingKeepsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        XCTAssertTrue(fixture.window.makeFirstResponder(try searchField()))
        fixture.terminal.automaticallySelectNewTabs = false
        _ = fixture.addTab()
        XCTAssertEqual(try searchField().stringValue, "alpha")
        let all = try XCTUnwrap(fixture.terminal.tabs())
        XCTAssertEqual(try hidden(all), [false, true, false, true])
    }

    // A group's name is searched, so typing it shows the group's tabs, with
    // the name highlighted on its chip.
    func testSearchingForAGroupNameShowsItsTabs() throws {
        let tabs = try makeTabs()
        for tab in [tabs[1], tabs[2]] {
            tab.tabGroupID = "G"
            tab.tabGroupName = "backend"
        }
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("backend")
        XCTAssertEqual(try hidden(tabs), [true, false, false])
        XCTAssertTrue(try barShowsHighlight(), "the chip's name")
    }

    // Renaming a group during a search applies the search to the new name.
    func testRenamingAGroupDuringASearchReappliesIt() throws {
        let tabs = try makeTabs()
        for tab in [tabs[1], tabs[2]] {
            tab.tabGroupID = "G"
            tab.tabGroupName = "backend"
        }
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("front")
        XCTAssertEqual(try hidden(tabs), [true, true, true])
        fixture.terminal.apiSetTabGroupName(completion: { _, _ in }, group_id: "G", name: "frontend")
        waitUntil("the group shows") { (try? self.hidden(tabs)) == [true, false, false] }
    }

    // Dragging the only shown tab out of the window leaves its neighbor
    // selected but hidden. The search ends once the drag is over.
    func testDraggingTheLastShownTabOutEndsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("beta")
        let assistant: PSMTabDragAssistant = PSMTabDragAssistant.shared()
        assistant.setValue(true, forKey: "isDragging")
        defer { assistant.setValue(false, forKey: "isDragging") }
        fixture.terminal.tabView().removeTabViewItem(try XCTUnwrap(tabs[1].tabViewItem))
        XCTAssertEqual(try searchField().stringValue, "beta", "not mid-drag")
        assistant.setValue(false, forKey: "isDragging")
        NotificationCenter.default.post(name: NSNotification.Name.PSMTabDragDidEnd, object: nil)
        XCTAssertEqual(try searchField().stringValue, "")
        XCTAssertEqual(try hidden([tabs[0], tabs[2]]), [false, false])
    }

    // The window moving the selected tab, as its tidying of groups does,
    // reselects it, which leaves focus in the field.
    func testMovingTheSelectedTabKeepsFocusInTheField() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        XCTAssertTrue(fixture.window.makeFirstResponder(try searchField()))
        fixture.terminal.moveTab(at: 0, to: 2)
        XCTAssertTrue(try XCTUnwrap(fixture.terminal.tabs())[2] === tabs[0], "precondition: moved")
        XCTAssertTrue(fixture.terminal.tabBarSearchFieldHasFocus())
        // Order is beta, alphabet, alpha. Grouping beta and alpha splits
        // the group, and tidying it moves alpha, the selected tab, next to
        // beta.
        tabs[1].tabGroupID = "G"
        tabs[0].tabGroupID = "G"
        fixture.terminal.tabsDidReorder()
        let order = try XCTUnwrap(fixture.terminal.tabs())
        let alphaIndex = try XCTUnwrap(order.firstIndex { $0 === tabs[0] })
        let betaIndex = try XCTUnwrap(order.firstIndex { $0 === tabs[1] })
        XCTAssertEqual(betaIndex, 0, "precondition: tidied")
        XCTAssertEqual(alphaIndex, 1, "precondition: alpha moved next to beta")
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0])
        XCTAssertTrue(fixture.terminal.tabBarSearchFieldHasFocus())
    }

    // Closing the hidden current tab keeps the search: the tab is leaving,
    // and the nearest shown tab takes over.
    func testClosingAHiddenCurrentTabKeepsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        fixture.terminal.closeCurrentTab(nil)
        XCTAssertEqual(fixture.terminal.tabs()?.count, 2, "closed")
        XCTAssertEqual(try searchField().stringValue, "alpha")
        XCTAssertFalse(try hidden([try XCTUnwrap(fixture.terminal.currentTab())])[0])
    }

    // A tab that matched by its group's name stops matching once it leaves
    // the group. The search ends so the user sees where it went.
    func testRemovingATabFromAGroupItMatchedByEndsTheSearch() throws {
        let tabs = try makeTabs()
        for tab in [tabs[1], tabs[2]] {
            tab.tabGroupID = "G"
            tab.tabGroupName = "api"
        }
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("api")
        XCTAssertEqual(try hidden(tabs), [true, false, false])
        let item = NSMenuItem(title: "", action: NSSelectorFromString("removeTabFromGroup:"), keyEquivalent: "")
        item.representedObject = tabs[1].tabViewItem
        _ = fixture.terminal.perform(NSSelectorFromString("removeTabFromGroup:"), with: item)
        XCTAssertNil(tabs[1].tabGroupID, "precondition: removed")
        XCTAssertEqual(try searchField().stringValue, "")
    }

    // One that still matches leaves the search alone.
    func testRemovingAMatchingTabFromAGroupKeepsTheSearch() throws {
        let tabs = try makeTabs()
        for tab in [tabs[0], tabs[1]] {
            tab.tabGroupID = "G"
            tab.tabGroupName = "team"
        }
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        let item = NSMenuItem(title: "", action: NSSelectorFromString("removeTabFromGroup:"), keyEquivalent: "")
        item.representedObject = tabs[0].tabViewItem
        _ = fixture.terminal.perform(NSSelectorFromString("removeTabFromGroup:"), with: item)
        XCTAssertNil(tabs[0].tabGroupID, "precondition: removed")
        XCTAssertEqual(try searchField().stringValue, "alpha")
        XCTAssertEqual(try hidden(tabs), [false, true, false])
    }

    // A rename that hides nothing new keeps the search, though a member the
    // search already hid stays hidden.
    func testRenamingAGroupWithAHiddenMemberKeepsTheSearch() throws {
        let tabs = try makeTabs()
        for tab in [tabs[0], tabs[1]] {
            tab.tabGroupID = "G"
            tab.tabGroupName = "work"
        }
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        XCTAssertEqual(try hidden(tabs), [false, true, false], "precondition")
        _ = fixture.terminal.perform(NSSelectorFromString("userRenamedTabGroup:toName:"), with: "G", with: "work2")
        XCTAssertEqual(tabs[0].tabGroupName, "work2", "precondition: renamed")
        XCTAssertEqual(try searchField().stringValue, "alpha")
        XCTAssertEqual(try hidden(tabs), [false, true, false])
    }

    // Moving a tab that matched by its group's name into another group ends
    // the search, so it doesn't vanish.
    func testAddingATabToAnotherGroupSoItDoesNotMatchEndsTheSearch() throws {
        let tabs = try makeTabs()
        tabs[0].tabGroupID = "H"
        tabs[0].tabGroupName = "other"
        for tab in [tabs[1], tabs[2]] {
            tab.tabGroupID = "G"
            tab.tabGroupName = "api"
        }
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("api")
        XCTAssertEqual(try hidden(tabs), [true, false, false], "precondition")
        let item = NSMenuItem(title: "", action: NSSelectorFromString("addTabToExistingGroup:"), keyEquivalent: "")
        item.representedObject = ["tab": try XCTUnwrap(tabs[1].tabViewItem), "group": "H"]
        _ = fixture.terminal.perform(NSSelectorFromString("addTabToExistingGroup:"), with: item)
        XCTAssertEqual(tabs[1].tabGroupID, "H", "precondition: moved")
        XCTAssertEqual(try searchField().stringValue, "")
    }

    // Edit Tab Title on a hidden current tab ends the search only on OK, so
    // Cancel keeps the query.
    func testCancellingEditTabTitleKeepsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        _ = fixture.terminal.perform(NSSelectorFromString("editTabTitle:"), with: nil)
        let sheet = try XCTUnwrap(fixture.window.attachedSheet)
        XCTAssertEqual(try searchField().stringValue, "alpha", "not before the answer")
        fixture.window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        XCTAssertEqual(try searchField().stringValue, "alpha")
        _ = fixture.terminal.perform(NSSelectorFromString("editTabTitle:"), with: nil)
        fixture.window.endSheet(try XCTUnwrap(fixture.window.attachedSheet), returnCode: .alertFirstButtonReturn)
        XCTAssertEqual(try searchField().stringValue, "")
    }

    // With the layout locked, Move Tab does nothing, so it leaves the search.
    func testMovingAHiddenTabWithTheLayoutLockedKeepsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        _ = fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        defer { _ = fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil) }
        XCTAssertTrue(fixture.terminal.layoutLocked, "precondition")
        fixture.terminal.moveTabRight(nil)
        XCTAssertEqual(try searchField().stringValue, "alpha")
    }

    // A new title format that comes out the same isn't a rename, so a later
    // title change from elsewhere just hides the tab.
    func testARenameToTheSameTitleDoesNotEndTheSearchLater() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        _ = fixture.terminal.perform(NSSelectorFromString("setCurrentTabTitle:"), with: "\\(\"alpha\")")
        tabs[0].titleOverride = "zzz"
        waitUntil("hidden") { (try? self.hidden(tabs)) == [true, true, false] }
        XCTAssertEqual(try searchField().stringValue, "alpha")
    }

    // A script removing a tab from its group isn't the user acting on it, so
    // the search stays, as for a script's other group changes.
    func testAScriptRemovingATabFromAGroupKeepsTheSearch() throws {
        let tabs = try makeTabs()
        for tab in [tabs[1], tabs[2]] {
            tab.tabGroupID = "G"
            tab.tabGroupName = "api"
        }
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("api")
        // The API's path.
        _ = fixture.terminal.perform(NSSelectorFromString("removeTabFromGroup:label:"), with: tabs[1], with: "beta")
        XCTAssertNil(tabs[1].tabGroupID, "precondition: removed")
        XCTAssertEqual(try searchField().stringValue, "api")
    }

    // Pressing OK with the title unchanged isn't a rename, so a later title
    // change from elsewhere just hides the tab, as it would otherwise.
    func testAnUnchangedRenameDoesNotEndTheSearchLater() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        _ = fixture.terminal.perform(NSSelectorFromString("setCurrentTabTitle:"), with: "alpha")
        tabs[0].titleOverride = "zzz"
        waitUntil("hidden") { (try? self.hidden(tabs)) == [true, true, false] }
        XCTAssertEqual(try searchField().stringValue, "alpha")
    }

    // Renaming the current tab so it no longer matches ends the search.
    func testRenamingTheCurrentTabSoItDoesNotMatchEndsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        _ = fixture.terminal.perform(NSSelectorFromString("setCurrentTabTitle:"), with: "zzz")
        waitUntil("the search ends") { (try? self.searchField().stringValue) == "" }
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0])
    }

    // A new title that still matches keeps the search.
    func testRenamingTheCurrentTabSoItStillMatchesKeepsTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        _ = fixture.terminal.perform(NSSelectorFromString("setCurrentTabTitle:"), with: "alpha two")
        waitUntil("title shown") { tabs[0].tabViewItem?.label.contains("alpha two") == true }
        XCTAssertEqual(try searchField().stringValue, "alpha")
        XCTAssertEqual(try hidden(tabs), [false, true, false])
    }

    // Renaming a group whose tabs matched by its name ends the search.
    func testRenamingAGroupItsTabsMatchedByEndsTheSearch() throws {
        let tabs = try makeTabs()
        for tab in [tabs[1], tabs[2]] {
            tab.tabGroupID = "G"
            tab.tabGroupName = "api"
        }
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("api")
        XCTAssertEqual(try hidden(tabs), [true, false, false], "precondition: matched by the group's name")
        _ = fixture.terminal.perform(NSSelectorFromString("userRenamedTabGroup:toName:"), with: "G", with: "web")
        XCTAssertEqual(tabs[1].tabGroupName, "web", "precondition: renamed")
        XCTAssertEqual(try searchField().stringValue, "")
    }

    // Runs everything already queued on the main queue, such as a pending
    // re-filter.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    // While the pointer is over the bar, text changes don't add or remove
    // tabs, so nothing moves under it. They apply when it leaves. Navigation
    // and selection go by what the bar shows meanwhile.
    func testTextChangesWaitWhileThePointerIsOverTheBar() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        let bar = try tabBar
        bar.pointerIsInsideForTesting = NSNumber(value: true)
        defer { bar.pointerIsInsideForTesting = NSNumber(value: false) }
        tabs[1].titleOverride = "alpha beta"
        tabs[2].titleOverride = "zzz"
        waitUntil("titles shown") {
            tabs[1].tabViewItem?.label.contains("alpha beta") == true &&
            tabs[2].tabViewItem?.label.contains("zzz") == true
        }
        drainMainQueue()
        XCTAssertEqual(try hidden(tabs), [false, true, false], "frozen")
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2], "as shown, not as matched now")
        XCTAssertEqual(try searchField().stringValue, "alpha", "selecting a shown tab keeps the search")
        bar.pointerIsInsideForTesting = NSNumber(value: false)
        fixture.terminal.tabViewPointerDidLeaveTabBar(fixture.terminal.tabView())
        XCTAssertEqual(try hidden(tabs), [false, false, true])
    }

    // Renaming a tab with the pointer over the bar keeps that tab in step
    // with what the bar shows, so a later change to it waits like any other.
    func testARenamedTabStaysFrozenWithTheRest() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        let bar = try tabBar
        bar.pointerIsInsideForTesting = NSNumber(value: true)
        defer { bar.pointerIsInsideForTesting = NSNumber(value: false) }
        _ = fixture.terminal.perform(NSSelectorFromString("setCurrentTabTitle:"), with: "alpha two")
        waitUntil("title shown") { tabs[0].tabViewItem?.label.contains("alpha two") == true }
        XCTAssertEqual(try searchField().stringValue, "alpha", "still matches")
        tabs[0].titleOverride = "zzz"
        waitUntil("title shown") { tabs[0].tabViewItem?.label.contains("zzz") == true }
        drainMainQueue()
        XCTAssertEqual(try hidden(tabs), [false, true, false], "frozen")
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        XCTAssertEqual(try searchField().stringValue, "alpha", "selecting a shown tab keeps the search")
    }

    // Typing a new query applies right away, pointer or not.
    func testANewQueryAppliesWhileThePointerIsOverTheBar() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        let bar = try tabBar
        bar.pointerIsInsideForTesting = NSNumber(value: true)
        defer { bar.pointerIsInsideForTesting = NSNumber(value: false) }
        tabs[1].titleOverride = "zzz"
        waitUntil("title shown") { tabs[1].tabViewItem?.label.contains("zzz") == true }
        drainMainQueue()
        // By the text it had when the pointer arrived, beta wouldn't match.
        try type("zzz")
        XCTAssertEqual(try hidden(tabs), [true, false, true])
    }

    // Pinning acts on a whole group, hidden members included, and a pinned
    // tab is searched by its label alone, so it could vanish. It's disabled.
    func testPinningIsDisabledDuringSearch() throws {
        let tabs = try makeTabs()
        try type("alpha")
        let terminal = fixture.terminal
        let item = NSMenuItem(title: "", action: NSSelectorFromString("togglePinTab:"), keyEquivalent: "")
        item.representedObject = tabs[0].tabViewItem
        item.target = terminal
        XCTAssertFalse(validate(item))
        terminal.togglePinTab(item)
        XCTAssertFalse(tabs[0].isPinned)
        try press(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertTrue(validate(item), "enabled again after the search")
    }

    // A hidden tab's selection stays current, for accessibility too: a tab
    // that was selected and is hidden doesn't still read as selected.
    func testAHiddenTabStopsReadingAsSelected() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try tabBar.updateWithoutAnimation()
        let cells = try tabBar.cells() as? [PSMTabBarCell] ?? []
        let beta = try XCTUnwrap(cells.first { $0.representedObject as? NSTabViewItem === tabs[1].tabViewItem })
        XCTAssertTrue(beta.isCollapsedHidden, "precondition")
        XCTAssertEqual(beta.state, .off)
        XCTAssertEqual(Int(beta.tabState) & PSMTab_SelectedMask, 0)
    }

    // A new tab might not match, so opening one ends the search rather than
    // leaving it selected but invisible.
    func testNewTabEndsTheSearch() throws {
        let tabs = try makeTabs()
        try type("alpha")
        _ = fixture.addTab()
        let all = try XCTUnwrap(fixture.terminal.tabs())
        let newTab = try XCTUnwrap(all.first { tab in !tabs.contains { $0 === tab } })
        XCTAssertTrue(fixture.terminal.currentTab() === newTab)
        XCTAssertEqual(try searchField().stringValue, "")
        XCTAssertEqual(try hidden(all), [false, false, false, false])
    }

    // Ending the search for a new tab happens once the new tab is selected,
    // so the group of a tab only browsed to during the search stays
    // collapsed.
    func testANewTabDoesNotExpandTheGroupOfTheTabItReplaces() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        _ = fixture.addTab()
        let newTab = try XCTUnwrap(fixture.terminal.currentTab())
        XCTAssertFalse(tabs.contains { $0 === newTab })
        XCTAssertNil(newTab.tabGroupID, "precondition: a plain new tab")
        XCTAssertEqual(try searchField().stringValue, "")
        XCTAssertTrue(tabs[1].tabGroupCollapsed, "still collapsed")
    }

    // -validateMenuItem: isn't declared where Swift can see it.
    private func validate(_ item: NSMenuItem) -> Bool {
        typealias Validate = @convention(c) (AnyObject, Selector, NSMenuItem) -> Bool
        let selector = NSSelectorFromString("validateMenuItem:")
        let terminal: PseudoTerminal = fixture.terminal
        return unsafeBitCast(terminal.method(for: selector), to: Validate.self)(terminal, selector, item)
    }

    // Closing several tabs would close ones the search hides, so those menu
    // items are disabled and do nothing.
    func testBulkCloseIsDisabledDuringSearch() throws {
        let tabs = try makeTabs()
        tabs[1].tabGroupID = "G"
        tabs[2].tabGroupID = "G"
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("alphabet")
        let terminal = fixture.terminal
        for action in ["closeOtherTabs:", "closeTabsToTheRight:"] {
            let item = NSMenuItem(title: "", action: NSSelectorFromString(action), keyEquivalent: "")
            item.representedObject = tabs[2].tabViewItem
            item.target = terminal
            XCTAssertFalse(validate(item), action)
            _ = terminal.perform(NSSelectorFromString(action), with: item)
        }
        XCTAssertEqual(terminal.tabs()?.count, 3, "nothing closed")
        // The group's menu: closing, or moving, duplicating, saving or
        // ungrouping the group would act on members the search hides.
        let menu = try XCTUnwrap(terminal.tabView(terminal.tabView(), menuForTabGroup: "G"))
        for action in ["closeTabGroup:", "closeTabsOutsideGroup:", "moveTabGroupToNewWindow:",
                       "duplicateTabGroup:", "saveTabGroupAsWindowArrangement:", "ungroupTabGroup:"] {
            let item = try XCTUnwrap(menu.items.first { $0.action == NSSelectorFromString(action) }, action)
            XCTAssertFalse(item.isEnabled, action)
            // Saving asks for a name, which would wait here if it weren't
            // guarded, so it's only checked for being disabled.
            if action != "saveTabGroupAsWindowArrangement:" {
                _ = terminal.perform(NSSelectorFromString(action), with: item)
            }
        }
        // Not in this menu, since the group ends the bar, but guarded too.
        let right = NSMenuItem(title: "", action: NSSelectorFromString("closeTabsRightOfGroup:"), keyEquivalent: "")
        right.representedObject = "G"
        XCTAssertFalse(validate(right))
        for action in ["moveTabGroupIntoGroupFromMenu:", "moveTabGroupOutOfParentFromMenu:"] {
            let item = NSMenuItem(title: "", action: NSSelectorFromString(action), keyEquivalent: "")
            XCTAssertFalse(validate(item), action)
        }
        XCTAssertEqual(terminal.tabs()?.count, 3, "nothing closed or moved")
        XCTAssertEqual(tabs[1].tabGroupID, "G", "still grouped")
        try press(#selector(NSResponder.cancelOperation(_:)))
        let item = NSMenuItem(title: "", action: NSSelectorFromString("closeOtherTabs:"), keyEquivalent: "")
        item.representedObject = tabs[2].tabViewItem
        XCTAssertTrue(validate(item), "enabled again after the search")
    }

    // Next and Previous Tab Group go among the tabs shown, like Next Tab,
    // stepping over a group as a whole.
    func testNextTabGroupFollowsTheSearch() throws {
        let tabs = try makeTabs()
        _ = fixture.addTab()
        _ = fixture.addTab()
        let all = try XCTUnwrap(fixture.terminal.tabs())
        // alpha, [beta, alphabet] in G, alpha four, delta
        all[3].titleOverride = "alpha four"
        all[4].titleOverride = "delta"
        waitUntil("titles shown") { all[4].tabViewItem?.label.contains("delta") == true }
        tabs[1].tabGroupID = "G"
        tabs[2].tabGroupID = "G"
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(all[0].tabViewItem)
        try type("alpha")
        XCTAssertEqual(try hidden(all), [false, true, false, false, true])
        _ = fixture.terminal.perform(NSSelectorFromString("nextTabGroup:"), with: nil)
        XCTAssertTrue(fixture.terminal.currentTab() === all[2], "into the group, at its shown tab")
        _ = fixture.terminal.perform(NSSelectorFromString("nextTabGroup:"), with: nil)
        XCTAssertTrue(fixture.terminal.currentTab() === all[3], "past the group, skipping the hidden one")
        _ = fixture.terminal.perform(NSSelectorFromString("nextTabGroup:"), with: nil)
        XCTAssertTrue(fixture.terminal.currentTab() === all[0], "wraps around past the hidden last tab")
    }

    // Closing the selected tab selects a shown one, not a hidden neighbor,
    // which would also expand that neighbor's collapsed group for good.
    func testClosingTheSelectedTabSelectsAShownTab() throws {
        let tabs = try makeTabs()
        _ = fixture.addTab()
        let all = try XCTUnwrap(fixture.terminal.tabs())
        all[3].titleOverride = "alpha four"
        waitUntil("title shown") { all[3].tabViewItem?.label.contains("alpha four") == true }
        // beta is alone in a collapsed group.
        tabs[1].tabGroupID = "G"
        tabs[1].tabGroupCollapsed = true
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        fixture.terminal.updateTabColors()
        try type("alpha")
        fixture.terminal.close(tabs[0])
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertTrue(tabs[1].tabGroupCollapsed, "still collapsed")
    }

    // Any way the selected tab leaves the window, such as burying its session
    // or moving it to another window, goes through the tab view, which picks
    // a shown tab during a search.
    func testRemovingTheSelectedTabSelectsAShownTab() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        let item = try XCTUnwrap(tabs[0].tabViewItem)
        fixture.terminal.tabView().removeTabViewItem(item)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertEqual(try hidden([tabs[1], tabs[2]]), [true, false])
    }

    // Removing a tab that isn't selected leaves the selection alone.
    func testRemovingAnotherTabKeepsTheSelection() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("alpha")
        fixture.terminal.tabView().removeTabViewItem(try XCTUnwrap(tabs[0].tabViewItem))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
    }

    // With no other shown tab, the usual neighbor is selected. The search
    // hides it, so the search ends rather than leave it invisible.
    func testRemovingTheOnlyShownTabSelectsTheNeighbor() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("beta")
        XCTAssertEqual(try hidden(tabs), [true, false, true])
        fixture.terminal.tabView().removeTabViewItem(try XCTUnwrap(tabs[1].tabViewItem))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertEqual(try searchField().stringValue, "")
        XCTAssertEqual(try hidden([tabs[0], tabs[2]]), [false, false])
    }

    // With the setting to move left after closing a tab, the nearest shown
    // tab to the left.
    func testClosingMovesLeftWhenSetToDuringSearch() throws {
        try withAdvancedSetting("MoveLeftAfterClosingTab", true) {
            let tabs = try makeTabs()
            _ = fixture.addTab()
            let all = try XCTUnwrap(fixture.terminal.tabs())
            all[3].titleOverride = "alpha four"
            waitUntil("title shown") { all[3].tabViewItem?.label.contains("alpha four") == true }
            // alpha, beta, alphabet, alpha four: close alphabet.
            fixture.terminal.tabView().selectTabViewItem(all[2].tabViewItem)
            try type("alpha")
            fixture.terminal.close(all[2])
            XCTAssertTrue(fixture.terminal.currentTab() === all[0], "past the hidden beta")
        }
    }

    // Return goes to the first match when the selected tab doesn't match.
    func testReturnIgnoresTheSelectedTabIfItDoesNotMatch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("alphabet")
        XCTAssertEqual(try hidden(tabs), [true, true, false])
        try press(#selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
    }

    // Browsing matches inside a collapsed group doesn't expand it. Only the
    // tab selected when the search ends has its group expanded, so the
    // selected tab is never in a collapsed group.
    func testBrowsingIntoACollapsedGroupDoesNotExpandIt() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertTrue(tabs[2].tabGroupCollapsed, "not expanded while searching")
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0])
        try press(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertTrue(tabs[1].tabGroupCollapsed, "still collapsed")
        XCTAssertEqual(try hidden(tabs), [false, true, true])
    }

    func testEscapeExpandsTheSelectedTabsGroup() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        try press(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertFalse(tabs[2].tabGroupCollapsed)
        XCTAssertEqual(try hidden(tabs), [false, false, false])
    }

    // Deleting the query ends the search too.
    func testClearingTheQueryExpandsTheSelectedTabsGroup() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        try type("")
        XCTAssertFalse(tabs[2].tabGroupCollapsed)
        XCTAssertEqual(try hidden(tabs), [false, false, false])
    }

    // The group of a tab only passed through stays collapsed when Return
    // ends the search on a match outside it.
    func testReturnExpandsOnlyTheMatchsGroup() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0])
        try press(#selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0])
        XCTAssertTrue(tabs[1].tabGroupCollapsed, "still collapsed")
        XCTAssertEqual(try hidden(tabs), [false, true, true])
    }

    // Moving the bar to the top ends the search, so the same applies.
    func testMovingTheBarToTheTopExpandsTheSelectedTabsGroup() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        var frame = fixture.window.frame
        frame.size.width += 10
        fixture.window.setFrame(frame, display: false)
        waitUntil("group expanded") { !tabs[2].tabGroupCollapsed }
    }

    // A search shows every kept group expanded, so the group menu doesn't
    // offer to expand or collapse it.
    func testGroupMenuHasNoExpandOrCollapseDuringSearch() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        let terminal = fixture.terminal
        let actions = ["expandTabGroupFromMenu:", "collapseTabGroupFromMenu:"].map { NSSelectorFromString($0) }
        let before = try XCTUnwrap(terminal.tabView(terminal.tabView(), menuForTabGroup: "G"))
        XCTAssertTrue(before.items.contains { $0.action.map(actions.contains) == true }, "precondition")
        try type("alphabet")
        let menu = try XCTUnwrap(terminal.tabView(terminal.tabView(), menuForTabGroup: "G"))
        XCTAssertFalse(menu.items.contains { $0.action.map(actions.contains) == true })
        for (a, b) in zip(menu.items, menu.items.dropFirst()) {
            XCTAssertFalse(a.isSeparatorItem && b.isSeparatorItem, "no doubled separator")
        }
    }

    // Dropping a split pane on the bar makes a new tab where it's dropped,
    // which is unclear with tabs hidden, as for a dropped tab.
    func testPaneDropsAreRefusedDuringSearch() throws {
        _ = try makeTabs()
        let terminal = fixture.terminal
        let info = DraggingInfoStub()
        XCTAssertEqual(terminal.tabView(terminal.tabView(), draggingEnteredTabBarForSender: info), .move)
        XCTAssertTrue(terminal.tabView(terminal.tabView(), shouldAcceptDragFromSender: info))
        try type("alpha")
        XCTAssertEqual(terminal.tabView(terminal.tabView(), draggingEnteredTabBarForSender: info), [])
        XCTAssertFalse(terminal.tabView(terminal.tabView(), shouldAcceptDragFromSender: info))
    }

    // The bar itself refuses a pane dragged over a tab during a search,
    // rather than selecting the tab under it and offering to copy.
    func testPaneDraggedOverATabDuringSearchIsRefused() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("alpha")
        let bar = try tabBar
        bar.layoutSubtreeIfNeeded()
        let cells = bar.cells() as? [PSMTabBarCell] ?? []
        let cell = try XCTUnwrap(cells.first { $0.representedObject as? NSTabViewItem === tabs[0].tabViewItem })
        let point = bar.convert(NSPoint(x: cell.frame.midX, y: cell.frame.midY), to: nil)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TabBarSearchWindowTests.pane"))
        pasteboard.clearContents()
        pasteboard.declareTypes([NSPasteboard.PasteboardType("iTermDragPanePBType")], owner: nil)
        let info = DraggingInfoStub(location: point, pasteboard: pasteboard)
        XCTAssertEqual(bar.draggingUpdated(info), [])
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2], "the tab under it isn't selected")
        // Cancel any spring-load the real mouse position armed.
        bar.draggingEnded(info)
    }

    // A tab drag ending, in any window, settles collapsed groups. During a
    // search that leaves the selected tab's group collapsed, since the
    // search's end expands it.
    func testADragEndingDuringSearchLeavesTheGroupCollapsed() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        NotificationCenter.default.post(name: NSNotification.Name.PSMTabDragDidEnd, object: nil)
        XCTAssertTrue(tabs[2].tabGroupCollapsed)
        XCTAssertTrue(tabs[1].tabGroupCollapsed)
        try press(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(tabs[2].tabGroupCollapsed, "expanded when the search ends")
    }

    // The same goes for the other places that keep the selected tab out of a
    // collapsed group, such as after a tab joins a group.
    func testExpandingForTheSelectedTabWaitsForTheSearchToEnd() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        _ = fixture.terminal.perform(NSSelectorFromString("expandTabGroupIfSelectedTabIsCollapsed"))
        XCTAssertTrue(tabs[2].tabGroupCollapsed)
    }

    // A script collapsing a group that's already collapsed doesn't move the
    // selection out of it while the selected tab is in it during a search.
    func testCollapsingACollapsedGroupDuringSearchKeepsTheSelection() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        _ = fixture.terminal.perform(NSSelectorFromString("collapseTabGroup:"), with: "G")
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertTrue(tabs[2].tabGroupCollapsed)
    }

    // Nor does settling groups after a tmux attach.
    func testSettlingAfterDeferredExpansionDuringSearchKeepsTheSelection() throws {
        let tabs = try makeTabs()
        try collapsedGroup(tabs)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        _ = fixture.terminal.perform(NSSelectorFromString("settleTabGroupsAfterDeferredExpansion"))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertTrue(tabs[2].tabGroupCollapsed)
    }

    // Hiding the bar ends the search, as moving it to the top does, so it
    // doesn't come back with old tabs hidden.
    func testHidingTheBarEndsTheSearch() throws {
        let saved = iTermPreferences.bool(forKey: kPreferenceKeyHideTabBar)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyHideTabBar)
        defer { iTermPreferences.setBool(saved, forKey: kPreferenceKeyHideTabBar) }
        let tabs = try makeTabs()
        // alpha doesn't match, and is shown only because it's selected.
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("beta")
        let field = try searchField()
        fixture.terminal.close(tabs[2])
        fixture.terminal.close(tabs[1])
        waitUntil("search ended") { field.stringValue.isEmpty }
        // The new tab is selected, so alpha would be hidden if the search
        // had survived.
        _ = fixture.addTab()
        let all = try XCTUnwrap(fixture.terminal.tabs())
        XCTAssertEqual(all.count, 2)
        waitUntil("every tab shown") { (try? self.hidden(all)) == [false, false] }
    }

    // Native full screen can hide the bar, without the window counting it as
    // hidden. The search ends then too.
    func testHidingTheBarInNativeFullScreenEndsTheSearch() throws {
        let saved = iTermPreferences.bool(forKey: kPreferenceKeyShowFullscreenTabBar)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyShowFullscreenTabBar)
        let terminal: PseudoTerminal = fixture.terminal
        defer {
            terminal.setValue(false, forKey: "togglingLionFullScreen_")
            iTermPreferences.setBool(saved, forKey: kPreferenceKeyShowFullscreenTabBar)
        }
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("beta")
        let field = try searchField()
        // Stand in for entering native full screen.
        terminal.setValue(true, forKey: "togglingLionFullScreen_")
        var frame = fixture.window.frame
        frame.size.width += 10
        fixture.window.setFrame(frame, display: false)
        waitUntil("search ended") { field.stringValue.isEmpty }
    }

    // Return with nothing matching leaves the query, so a typo can be fixed.
    func testReturnWithNoMatchKeepsTheQuery() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[1].tabViewItem)
        try type("zzz")
        try press(#selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(try searchField().stringValue, "zzz")
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1])
        XCTAssertEqual(try hidden(tabs), [true, true, true], "still searching")
    }

    // A tab dragged out and back during a search can miss the search's
    // update while its cell is out of the bar. The end of any tab drag puts
    // the search right.
    func testTheEndOfADragReappliesTheSearch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("alpha")
        let bar = try tabBar
        let cells = bar.cells() as? [PSMTabBarCell] ?? []
        let beta = try XCTUnwrap(cells.first { $0.representedObject as? NSTabViewItem === tabs[1].tabViewItem })
        // Stand in for the cell having been out of the bar.
        beta.isCollapsedHidden = false
        NotificationCenter.default.post(name: NSNotification.Name.PSMTabDragDidEnd, object: nil)
        XCTAssertEqual(try hidden(tabs), [false, true, false])
    }

    // A tab dropped in from another window lands among hidden tabs: it joins
    // only a group the bar showed, stays between the shown tabs it was
    // dropped between, and ends the search so the user sees it.
    func testATabDroppedAmongHiddenTabsEndsTheSearchAndJoinsNoHiddenGroup() throws {
        _ = try makeTabs()
        _ = fixture.addTab()
        _ = fixture.addTab()
        var all = try XCTUnwrap(fixture.terminal.tabs())
        // alpha, beta, alphabet, beta two, newcomer
        all[3].titleOverride = "beta two"
        all[4].titleOverride = "zzz"
        waitUntil("titles shown") { all[4].tabViewItem?.label.contains("zzz") == true }
        // beta and beta two make a group with no match, and are adjacent.
        fixture.terminal.moveTab(at: 3, to: 2)
        all = try XCTUnwrap(fixture.terminal.tabs())
        let alpha = all[0], alphabet = all[3], newcomer = all[4]
        all[1].tabGroupID = "G"
        all[2].tabGroupID = "G"
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(alpha.tabViewItem)
        try type("alph")
        XCTAssertEqual(try hidden(all), [false, true, true, false, true])
        // Stand in for the drop: it lands between the group's hidden tabs.
        // The bar's own move skips the window's repairs, as a drop does
        // until the window hears about it.
        try tabBar.moveTab(at: 4, to: 2)
        XCTAssertTrue(try XCTUnwrap(fixture.terminal.tabs())[2] === newcomer, "precondition")
        let terminal = fixture.terminal
        terminal.tabView(terminal.tabView(),
                         didDrop: try XCTUnwrap(newcomer.tabViewItem),
                         inTabBar: try tabBar,
                         joiningGroupWithID: nil)
        XCTAssertNil(newcomer.tabGroupID, "didn't join the hidden group")
        let order = try XCTUnwrap(terminal.tabs())
        let index = try XCTUnwrap(order.firstIndex { $0 === newcomer })
        XCTAssertGreaterThan(index, try XCTUnwrap(order.firstIndex { $0 === alpha }))
        XCTAssertLessThan(index, try XCTUnwrap(order.firstIndex { $0 === alphabet }))
        XCTAssertEqual(try searchField().stringValue, "", "the search ended")
        XCTAssertEqual(try hidden([newcomer]), [false])
    }

    // A real drop from another window selects the tab before the window
    // hears about the drop. The search still applies when it resolves the
    // tab's group, so the tab joins no hidden group.
    func testASelectedDroppedTabJoinsNoHiddenGroup() throws {
        _ = try makeTabs()
        _ = fixture.addTab()
        _ = fixture.addTab()
        var all = try XCTUnwrap(fixture.terminal.tabs())
        all[3].titleOverride = "beta two"
        all[4].titleOverride = "zzz"
        waitUntil("titles shown") { all[4].tabViewItem?.label.contains("zzz") == true }
        fixture.terminal.moveTab(at: 3, to: 2)
        all = try XCTUnwrap(fixture.terminal.tabs())
        let alpha = all[0], newcomer = all[4]
        all[1].tabGroupID = "G"
        all[2].tabGroupID = "G"
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(alpha.tabViewItem)
        try type("alph")
        try tabBar.moveTab(at: 4, to: 2)
        XCTAssertTrue(try XCTUnwrap(fixture.terminal.tabs())[2] === newcomer, "precondition")
        let assistant: PSMTabDragAssistant = PSMTabDragAssistant.shared()
        assistant.setValue(true, forKey: "isDragging")
        defer { assistant.setValue(false, forKey: "isDragging") }
        fixture.terminal.tabView().selectTabViewItem(newcomer.tabViewItem)
        let terminal = fixture.terminal
        terminal.tabView(terminal.tabView(),
                         didDrop: try XCTUnwrap(newcomer.tabViewItem),
                         inTabBar: try tabBar,
                         joiningGroupWithID: nil)
        XCTAssertNil(newcomer.tabGroupID, "didn't join the hidden group")
        XCTAssertEqual(try searchField().stringValue, "", "the search ended")
    }

    // The same drop made from another window: the window it lands in tidies
    // its groups, so the hidden group stays in one piece and the tab goes
    // just after it, still before alphabet.
    func testATabDroppedFromAnotherWindowKeepsHiddenGroupsWhole() throws {
        _ = try makeTabs()
        _ = fixture.addTab()
        _ = fixture.addTab()
        var all = try XCTUnwrap(fixture.terminal.tabs())
        all[3].titleOverride = "beta two"
        all[4].titleOverride = "zzz"
        waitUntil("titles shown") { all[4].tabViewItem?.label.contains("zzz") == true }
        fixture.terminal.moveTab(at: 3, to: 2)
        all = try XCTUnwrap(fixture.terminal.tabs())
        let alpha = all[0], beta = all[1], betaTwo = all[2], alphabet = all[3], newcomer = all[4]
        beta.tabGroupID = "G"
        betaTwo.tabGroupID = "G"
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(alpha.tabViewItem)
        try type("alph")
        try tabBar.moveTab(at: 4, to: 2)
        // The window it came from tells this one about the drop.
        let source = TerminalWindowTestFixture()
        defer { source.close() }
        source.terminal.tabView(source.terminal.tabView(),
                                didDrop: try XCTUnwrap(newcomer.tabViewItem),
                                inTabBar: try tabBar,
                                joiningGroupWithID: nil)
        let order = try XCTUnwrap(fixture.terminal.tabs())
        XCTAssertTrue(order.elementsEqual([alpha, beta, betaTwo, newcomer, alphabet], by: ===),
                      "\(order.map { $0.tabViewItem?.label ?? "" })")
    }

    // A group's outline stops at the first cell after it. A tab the search
    // hides takes no room, so it isn't that cell: the outline still encloses
    // the group's last shown tab.
    func testAGroupOutlineIgnoresHiddenTabsAfterIt() throws {
        let tabs = try makeTabs()
        _ = fixture.addTab()
        _ = fixture.addTab()
        let all = try XCTUnwrap(fixture.terminal.tabs())
        all[3].titleOverride = "alpha zzz"
        all[4].titleOverride = "gamma"
        waitUntil("titles") { all[4].tabViewItem?.label.contains("gamma") == true }
        tabs[1].tabGroupID = "G"
        tabs[2].tabGroupID = "G"
        all[3].tabGroupID = "G"
        fixture.terminal.updateTabColors()
        // alpha zzz, the group's last tab, is shown; gamma, after it, is
        // hidden.
        fixture.terminal.tabView().selectTabViewItem(all[3].tabViewItem)
        try type("alph")
        XCTAssertEqual(try hidden(all), [false, true, false, false, true])
        let bar = try tabBar
        let cells = bar.cells() as? [PSMTabBarCell] ?? []
        let chip = try XCTUnwrap(cells.first { $0.isTabGroupChip && $0.tabGroupIdentifier == "G" })
        let next = bar.firstNonMemberCell(afterChip: chip, groupID: "G")
        XCTAssertFalse(next?.isCollapsedHidden ?? false, "a hidden tab isn't the cell after the group")
    }

    // Changing the selection while typing a query, as Next Tab or a tab
    // closing does, leaves focus in the field so typing goes on there.
    func testSelectingAnotherTabKeepsFocusInTheField() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        let field = try searchField()
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertTrue(fixture.terminal.tabBarSearchFieldHasFocus())
    }

    // The same with nothing typed yet.
    func testNextTabFromAnEmptyFieldKeepsFocusInTheField() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        let field = try searchField()
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1])
        XCTAssertTrue(fixture.terminal.tabBarSearchFieldHasFocus())
        fixture.terminal.previousTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0])
        XCTAssertTrue(fixture.terminal.tabBarSearchFieldHasFocus())
    }

    // A new tab opened from the field takes focus: the user wants to type in
    // it.
    func testANewTabFromTheFieldTakesFocus() throws {
        _ = try makeTabs()
        try type("alpha")
        let field = try searchField()
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let session = fixture.addTab()
        XCTAssertFalse(fixture.terminal.tabBarSearchFieldHasFocus())
        XCTAssertTrue(fixture.window.firstResponder === session.textview)
    }

    // The selected tab closing while the user types leaves focus in the field.
    func testClosingTheSelectedTabKeepsFocusInTheField() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        let field = try searchField()
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        fixture.terminal.tabView().removeTabViewItem(try XCTUnwrap(tabs[0].tabViewItem))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        XCTAssertTrue(fixture.terminal.tabBarSearchFieldHasFocus())
    }

    // Return keeps the selected tab when it matches, rather than going back
    // to the first match.
    func testReturnKeepsASelectedMatch() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[0].tabViewItem)
        try type("alpha")
        fixture.terminal.nextTab(nil)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
        try press(#selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
    }

    // A swipe between tabs goes among the shown ones, like Next Tab.
    func testSwipingGoesAmongShownTabs() throws {
        let tabs = try makeTabs()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("alpha")
        let handler = try XCTUnwrap((fixture.terminal as AnyObject) as? iTermSwipeHandler)
        let params = handler.swipeHandlerParameters()
        XCTAssertEqual(params.count, 2, "alpha and alphabet")
        XCTAssertEqual(params.currentIndex, 1)
        let session = handler.swipeHandlerBeginSession(atOffset: 0, identifier: "test" as NSString)
        handler.swipeHandlerEndSession(session, at: 0)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[0], "the first shown tab, not beta")
    }

    // Ctrl-Tab cycling, in recently used order, skips tabs the search hides,
    // and the tabs it passes don't stay shown.
    func testCyclingSkipsHiddenTabs() throws {
        let savedSwitcher = iTermPreferences.bool(forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        defer { iTermPreferences.setBool(savedSwitcher, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs) }
        do {
            let tabs = try makeTabs()
            _ = fixture.addTab()
            let all = try XCTUnwrap(fixture.terminal.tabs())
            all[3].titleOverride = "delta"
            waitUntil("title") { all[3].tabViewItem?.label.contains("delta") == true }
            let tabView = try XCTUnwrap(fixture.terminal.tabView() as? PTYTabView)
            // Recently used: alpha, alphabet, delta, beta.
            for tab in [tabs[1], all[3], tabs[2], tabs[0]] {
                tabView.selectTabViewItem(tab.tabViewItem)
            }
            try type("alph")
            let control = NSEvent.ModifierFlags.control.rawValue
            tabView.cycleKeyDown(withModifiers: control, forwards: true)
            XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
            tabView.cycleKeyDown(withModifiers: control, forwards: true)
            XCTAssertTrue(fixture.terminal.currentTab() === tabs[0], "past delta and beta, around to alpha")
            tabView.cycleFlagsChanged(0)
            XCTAssertEqual(try hidden(all), [false, true, false, true])
        }
    }

    // With the switcher overlay, Ctrl-Tab goes among the shown tabs too.
    func testTheSwitcherSkipsHiddenTabs() throws {
        let savedSwitcher = iTermPreferences.bool(forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        defer { iTermPreferences.setBool(savedSwitcher, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs) }
        let tabs = try makeTabs()
        _ = fixture.addTab()
        let all = try XCTUnwrap(fixture.terminal.tabs())
        all[3].titleOverride = "delta"
        waitUntil("title") { all[3].tabViewItem?.label.contains("delta") == true }
        let tabView = try XCTUnwrap(fixture.terminal.tabView() as? PTYTabView)
        // Recently used: alpha, delta, alphabet, beta.
        for tab in [tabs[1], tabs[2], all[3], tabs[0]] {
            tabView.selectTabViewItem(tab.tabViewItem)
        }
        try type("alph")
        let control = NSEvent.ModifierFlags.control.rawValue
        tabView.cycleKeyDown(withModifiers: control, forwards: true)
        XCTAssertTrue(tabView.isShowingSwitcher)
        tabView.cycleFlagsChanged(0)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2], "past delta to alphabet")
        XCTAssertEqual(try searchField().stringValue, "alph")
        XCTAssertEqual(try hidden(all), [false, true, false, true])
    }

    // The switcher follows the search if it changes while it's open.
    func testTheSwitcherFollowsTheSearchEnding() throws {
        let savedSwitcher = iTermPreferences.bool(forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        defer { iTermPreferences.setBool(savedSwitcher, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs) }
        let tabs = try makeTabs()
        let tabView = try XCTUnwrap(fixture.terminal.tabView() as? PTYTabView)
        // Recently used: alpha, beta, alphabet.
        for tab in [tabs[2], tabs[1], tabs[0]] {
            tabView.selectTabViewItem(tab.tabViewItem)
        }
        try type("alpha")
        let control = NSEvent.ModifierFlags.control.rawValue
        tabView.cycleKeyDown(withModifiers: control, forwards: true)
        XCTAssertTrue(tabView.isShowingSwitcher)
        // Alphabet is highlighted. With beta listed again, it's just before.
        try type("")
        tabView.cycleKeyDown(withModifiers: control, forwards: false)
        tabView.cycleFlagsChanged(0)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1], "beta, listed again")
    }

    // The switcher starts at the selected tab even when the search hides it,
    // and coming back around to it leaves the search alone.
    func testReturningToAHiddenTabInTheSwitcherKeepsTheSearch() throws {
        let savedSwitcher = iTermPreferences.bool(forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        defer { iTermPreferences.setBool(savedSwitcher, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs) }
        let tabs = try makeTabs()
        let tabView = try XCTUnwrap(fixture.terminal.tabView() as? PTYTabView)
        tabView.selectTabViewItem(tabs[1].tabViewItem)
        try type("alpha")
        let control = NSEvent.ModifierFlags.control.rawValue
        tabView.cycleKeyDown(withModifiers: control, forwards: true)
        XCTAssertTrue(tabView.isShowingSwitcher)
        tabView.cycleKeyDown(withModifiers: control, forwards: true)
        tabView.cycleKeyDown(withModifiers: control, forwards: true)
        tabView.cycleFlagsChanged(0)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[1], "around the shown tabs and back")
        XCTAssertEqual(try searchField().stringValue, "alpha")
    }

    // If the window stops being key while Ctrl is held, the release never
    // arrives here, so the cycle ends then.
    func testCyclingEndsWhenTheWindowResignsKey() throws {
        let savedSwitcher = iTermPreferences.bool(forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs)
        defer { iTermPreferences.setBool(savedSwitcher, forKey: kPreferenceKeyShowTabSwitcherWhenCyclingTabs) }
        _ = try makeTabs()
        let tabView = try XCTUnwrap(fixture.terminal.tabView() as? PTYTabView)
        tabView.cycleKeyDown(withModifiers: NSEvent.ModifierFlags.control.rawValue, forwards: true)
        XCTAssertTrue(tabView.isCyclingWithModifierPressed)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        XCTAssertFalse(tabView.isCyclingWithModifierPressed)
    }

    // A script can't collapse or expand a group during a search, as the UI
    // can't: the search shows groups expanded, and ending it restores them.
    func testTheAPICannotCollapseAGroupDuringASearch() throws {
        let tabs = try makeTabs()
        tabs[1].tabGroupID = "G"
        tabs[2].tabGroupID = "G"
        fixture.terminal.updateTabColors()
        fixture.terminal.tabView().selectTabViewItem(tabs[2].tabViewItem)
        try type("alph")
        var error: Error?
        fixture.terminal.apiSetTabGroupCollapsed(completion: { _, e in error = e }, group_id: "G", collapsed: true)
        XCTAssertNotNil(error)
        XCTAssertFalse(tabs[1].tabGroupCollapsed)
        XCTAssertTrue(fixture.terminal.currentTab() === tabs[2])
    }

    // While searching, a tab whose title changes to match appears.
    func testTitleChangeDuringSearchShowsTheTab() throws {
        let tabs = try makeTabs()
        try type("gamma")
        XCTAssertEqual(try hidden(tabs), [true, true, true])
        tabs[1].titleOverride = "gamma"
        waitUntil("the renamed tab appears") { (try? self.hidden(tabs)) == [true, false, true] }
    }
}

// Only the location and pasteboard matter to the tab bar's drag methods.
private final class DraggingInfoStub: NSObject, NSDraggingInfo {
    let draggingLocation: NSPoint
    let draggingPasteboard: NSPasteboard

    init(location: NSPoint = .zero,
         pasteboard: NSPasteboard = NSPasteboard(name: NSPasteboard.Name("TabBarSearchWindowTests"))) {
        draggingLocation = location
        draggingPasteboard = pasteboard
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [],
                                for view: NSView?,
                                classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

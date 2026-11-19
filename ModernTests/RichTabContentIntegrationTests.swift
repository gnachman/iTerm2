//
//  RichTabContentIntegrationTests.swift
//  ModernTests
//
//  A window shows rich tab content when the profile it was created with says
//  to: each tab gets evaluated lines from its active session. Turning it off
//  goes back to the classic title and subtitle. A window follows later edits
//  to its profile.
//

import XCTest
@testable import iTerm2SharedARC

final class RichTabContentIntegrationTests: XCTestCase {
    private var savedTabPosition: Int32 = 0
    private var savedTabStyle: Int32 = 0
    private var savedHideTabBar = false
    private var fixtures = [TerminalWindowTestFixture]()
    private var profileGUIDs = [String]()

    // The most recently opened window.
    private var fixture: TerminalWindowTestFixture? {
        return fixtures.last
    }

    override func setUp() {
        super.setUp()
        savedTabPosition = iTermPreferences.int(forKey: kPreferenceKeyTabPosition)
        savedTabStyle = iTermPreferences.int(forKey: kPreferenceKeyTabStyle)
        savedHideTabBar = iTermPreferences.bool(forKey: kPreferenceKeyHideTabBar)
    }

    override func tearDown() {
        for fixture in fixtures {
            fixture.close()
        }
        fixtures = []
        for guid in profileGUIDs {
            ProfileModel.sharedInstance().removeProfile(withGuid: guid)
        }
        profileGUIDs = []
        iTermPreferences.setInt(savedTabPosition, forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setInt(savedTabStyle, forKey: kPreferenceKeyTabStyle)
        iTermPreferences.setBool(savedHideTabBar, forKey: kPreferenceKeyHideTabBar)
        super.tearDown()
    }

    private func waitUntil(_ description: String,
                           file: StaticString = #filePath,
                           line: UInt = #line,
                           _ condition: @escaping () -> Bool) {
        let done = expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)
        done.expectationDescription = description
        wait(for: [done], timeout: 5)
    }

    // A profile of the test's own, so the default profile is never changed.
    // Returns its GUID.
    private func makeProfile(enabled: Bool, _ values: [String: Any] = [:]) -> String {
        var profile = ProfileModel.sharedInstance().defaultBookmark() ?? [:]
        let guid = ProfileModel.freshGuid()!
        profile[KEY_GUID] = guid
        profile[KEY_NAME] = "RichTabContentIntegrationTests \(guid)"
        profile.removeValue(forKey: KEY_ORIGINAL_GUID)
        for key in TabContentConfiguration.profileKeys {
            profile.removeValue(forKey: key)
        }
        profile[KEY_SHOW_RICH_TAB_CONTENT] = enabled
        for (key, value) in values {
            profile[key] = value
        }
        ProfileModel.sharedInstance().addBookmark(profile)
        profileGUIDs.append(guid)
        return guid
    }

    // Opens a window created with a new profile of the test's own.
    @discardableResult
    private func openWindow(enabled: Bool,
                            windowType: iTermWindowType = .WINDOW_TYPE_NORMAL,
                            _ values: [String: Any] = [:]) -> TerminalWindowTestFixture {
        let guid = makeProfile(enabled: enabled, values)
        let fixture = TerminalWindowTestFixture(windowType: windowType,
                                                profile: ProfileModel.sharedInstance().bookmark(withGuid: guid))
        fixtures.append(fixture)
        return fixture
    }

    // Edits the profile the most recent window was created with, as Settings
    // does.
    private func set(_ key: String, _ value: Any?, guid: String? = nil) {
        guard let guid = guid ?? profileGUIDs.last,
              let profile = ProfileModel.sharedInstance().bookmark(withGuid: guid) else {
            XCTFail("No profile")
            return
        }
        iTermProfilePreferences.setObject(value, forKey: key, inProfile: profile, model: ProfileModel.sharedInstance())
    }

    // The tab content editor's Cancel removes keys that weren't set, in the
    // same batch as its other changes, and open windows follow.
    func testBatchRemovalReachesOpenWindows() throws {
        let fixture = openWindow(enabled: true)
        set(KEY_TAB_CONTENT_MAXIMUM_LINES, 2)
        XCTAssertEqual(fixture.terminal.tabContentConfiguration.lineLimit, 2)
        let guid = try XCTUnwrap(profileGUIDs.last)
        let profile = try XCTUnwrap(ProfileModel.sharedInstance().bookmark(withGuid: guid))
        iTermProfilePreferences.setObjectsFrom([KEY_SUBTITLE: "changed"],
                                               removingKeys: [KEY_TAB_CONTENT_MAXIMUM_LINES],
                                               inProfile: profile,
                                               model: ProfileModel.sharedInstance())
        let updated = try XCTUnwrap(ProfileModel.sharedInstance().bookmark(withGuid: guid))
        XCTAssertNil(updated[KEY_TAB_CONTENT_MAXIMUM_LINES])
        XCTAssertEqual(updated[KEY_SUBTITLE] as? String, "changed")
        XCTAssertNil(fixture.terminal.tabContentConfiguration.lineLimit, "the window follows")
    }

    func testDisabledMeansNoRichLines() throws {
        let fixture = openWindow(enabled: false)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        XCTAssertNil(tab.psmTabRichLines())
    }

    func testEnablingGivesTabsLinesFromTheActiveSession() throws {
        let fixture = openWindow(enabled: false)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        let session = try XCTUnwrap(tab.activeSession)

        set(KEY_SHOW_RICH_TAB_CONTENT, true)
        waitUntil("rich lines appear") { tab.psmTabRichLines()?.count == TabContentLayout.defaultLayout.slots.count }

        // The directory line evaluates the session's path.
        session.genericScope.setValue("/tmp/rich-tabs", forVariableNamed: iTermVariableKeySessionPath)
        waitUntil("directory line shows the path") {
            tab.psmTabRichLines()?.map(\.text).contains("/tmp/rich-tabs") ?? false
        }

        set(KEY_SHOW_RICH_TAB_CONTENT, false)
        waitUntil("rich lines go away") { tab.psmTabRichLines() == nil }
    }

    // The profile's layout decides how many lines there are.
    func testLayoutChangeUpdatesLineCount() throws {
        let fixture = openWindow(enabled: true)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        waitUntil("default lines") { tab.psmTabRichLines()?.count == 4 }

        set(KEY_TAB_CONTENT_LAYOUT, TabContentLayout(slots: [
            TabContentSlot(identifier: TabContentSlot.titleID, size: .regular)]).propertyList)
        waitUntil("one line") { tab.psmTabRichLines()?.count == 1 }
    }

    // Every tab in a window uses the window's settings, including a tab
    // opened with a profile whose own settings differ.
    func testTabsUseTheWindowsProfile() throws {
        let fixture = openWindow(enabled: true)
        let otherGUID = makeProfile(enabled: false)
        let other = try XCTUnwrap(ProfileModel.sharedInstance().bookmark(withGuid: otherGUID))
        let session = fixture.addTab(profile: other)
        let tab = try XCTUnwrap(fixture.terminal.tab(for: session))
        waitUntil("the window's lines") { tab.psmTabRichLines()?.count == 4 }
    }

    // Windows created with different profiles each follow their own.
    func testWindowsFollowTheirOwnProfiles() throws {
        let first = openWindow(enabled: true)
        let firstGUID = try XCTUnwrap(profileGUIDs.last)
        let second = openWindow(enabled: false)
        let firstTab = try XCTUnwrap(first.terminal.tabs().first)
        let secondTab = try XCTUnwrap(second.terminal.tabs().first)
        waitUntil("first window's lines") { firstTab.psmTabRichLines() != nil }
        XCTAssertNil(secondTab.psmTabRichLines())

        set(KEY_SHOW_RICH_TAB_CONTENT, true)
        waitUntil("second window's lines") { secondTab.psmTabRichLines() != nil }
        set(KEY_SHOW_RICH_TAB_CONTENT, false, guid: firstGUID)
        waitUntil("first window's lines go away") { firstTab.psmTabRichLines() == nil }
        XCTAssertNotNil(secondTab.psmTabRichLines())
    }

    // A window whose profile is deleted keeps the settings it last had, and
    // saves them in its arrangement so a restored window looks the same.
    func testDeletedProfileKeepsTheLastSettings() throws {
        let fixture = openWindow(enabled: true)
        let guid = try XCTUnwrap(profileGUIDs.last)
        set(KEY_TAB_CONTENT_MAXIMUM_LINES, 2)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        waitUntil("two lines") { tab.psmTabRichLines()?.count == 2 }

        ProfileModel.sharedInstance().removeProfile(withGuid: guid)
        NotificationCenter.default.post(name: NSNotification.Name(kReloadAllProfiles), object: nil)
        XCTAssertEqual(tab.psmTabRichLines()?.count, 2)
        XCTAssertTrue(fixture.terminal.tabContentConfiguration.enabled)

        // Not in PseudoTerminal's header.
        let saved = try XCTUnwrap(fixture.terminal.value(forKey: "expurgatedInitialProfile") as? [AnyHashable: Any])
        XCTAssertEqual(saved[iTermTabContentFollowedProfileGUIDKey] as? String, guid)
        // Under its own key: a restored window's KEY_GUID decides where the
        // window positioner places it, which this mustn't change.
        XCTAssertNil(saved[KEY_GUID])
        XCTAssertEqual(saved[KEY_SHOW_RICH_TAB_CONTENT] as? Bool, true)
        XCTAssertEqual(saved[KEY_TAB_CONTENT_MAXIMUM_LINES] as? Int, 2)
        XCTAssertEqual(TabContentConfiguration(profile: saved), fixture.terminal.tabContentConfiguration)
    }

    // A window made for a revived or undone session has no profile, and one
    // restored from an arrangement saved before rich tab content was a window
    // setting doesn't say which to follow. It follows its first session's.
    func testWindowMadeWithoutAProfileFollowsItsFirstSession() throws {
        let guid = makeProfile(enabled: true)
        let fixture = TerminalWindowTestFixture(profile: ProfileModel.sharedInstance().bookmark(withGuid: guid),
                                                windowProfile: [:])
        fixtures.append(fixture)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        waitUntil("the session's profile's lines") { tab.psmTabRichLines() != nil }
        set(KEY_SHOW_RICH_TAB_CONTENT, false)
        waitUntil("follows that profile") { tab.psmTabRichLines() == nil }
    }

    // If the first session's profile is gone, the window takes its values,
    // as it would have when it was created with that profile.
    func testWindowMadeWithoutAProfileUsesAGoneProfilesValues() throws {
        var gone = ProfileModel.sharedInstance().defaultBookmark() ?? [:]
        gone[KEY_GUID] = ProfileModel.freshGuid()!
        gone.removeValue(forKey: KEY_ORIGINAL_GUID)
        gone[KEY_SHOW_RICH_TAB_CONTENT] = true
        gone[KEY_TAB_CONTENT_MAXIMUM_LINES] = 2
        let fixture = TerminalWindowTestFixture(profile: gone, windowProfile: [:])
        fixtures.append(fixture)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        waitUntil("the gone profile's lines") { tab.psmTabRichLines()?.count == 2 }
    }

    // A tab dragged out into a new window looks the same there, and the new
    // window follows the same profile.
    func testWindowForADraggedOutTabFollowsTheSameProfile() throws {
        let source = openWindow(enabled: true, [KEY_TAB_CONTENT_MAXIMUM_LINES: 2])
        let dragged = try XCTUnwrap(source.terminal.terminalDraggedFromAnotherWindow(at: NSPoint(x: 100, y: 100)) as? PseudoTerminal)
        defer { dragged.window?.close() }
        XCTAssertEqual(dragged.tabContentConfiguration, source.terminal.tabContentConfiguration)
        set(KEY_TAB_CONTENT_MAXIMUM_LINES, 1)
        XCTAssertEqual(dragged.tabContentConfiguration.lineLimit, 1)
    }

    // The default job line is HTML: values are escaped, and the status shows
    // in its program's color.
    func testJobLineShowsTheStatusInItsColor() throws {
        let fixture = openWindow(enabled: true)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        let scope = try XCTUnwrap(tab.activeSession).genericScope
        scope.setValue("<Working> & co", forVariableNamed: iTermVariableKeyStatus)
        scope.setValue("#00ff00", forVariableNamed: iTermVariableKeyStatusColor)
        func jobLine() -> PSMTabRichLine? {
            return tab.psmTabRichLines()?.last
        }
        waitUntil("job line") { jobLine()?.visibleText.hasSuffix("<Working> & co") ?? false }
        let line = try XCTUnwrap(jobLine())
        XCTAssertTrue(line.html)
        XCTAssertTrue(line.text.contains("<font color=\"#00ff00\">&lt;Working&gt; &amp; co</font>"), line.text)
    }

    // The limit cuts the lines themselves, not just the height, so a tab bar
    // that's taller for another reason (such as the classic Tahoe height)
    // still shows only that many.
    func testLineLimitCutsTheTabsLines() throws {
        let fixture = openWindow(enabled: true)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        waitUntil("default lines") { tab.psmTabRichLines()?.count == 4 }

        set(KEY_TAB_CONTENT_MAXIMUM_LINES, 1)
        waitUntil("one line") { tab.psmTabRichLines()?.count == 1 }
    }

    // A session asks its window each time, so one that isn't in a window, as
    // while it's closed and awaiting Undo Close, has no rich content.
    func testSessionOutsideAWindowHasNoRichContent() throws {
        let fixture = openWindow(enabled: true)
        let tab = try XCTUnwrap(fixture.terminal.tabs().first)
        let session = try XCTUnwrap(tab.activeSession)
        waitUntil("rich lines appear") { session.tabContentLines != nil }
        session.delegate = nil
        XCTAssertNil(session.tabContentLines)
        XCTAssertNil(session.tabContentSnapshot)
        session.delegate = tab
        XCTAssertNotNil(session.tabContentLines)
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

    // The tab bar grows to fit every line of the layout, and goes back to its
    // usual height when rich content is turned off.
    func testTabBarGrowsToFitTheLayout() throws {
        let fixture = openWindow(enabled: false)
        _ = fixture.addTab()
        let frameView = try XCTUnwrap(fixture.window.contentView?.superview)
        let tabBar = try XCTUnwrap(findTabBar(in: frameView))
        let classic = tabBar.height

        set(KEY_SHOW_RICH_TAB_CONTENT, true)
        let needed = fixture.terminal.tabContentConfiguration.minimumTabHeight
        XCTAssertGreaterThan(needed, classic, "precondition: the default layout needs a taller bar")
        waitUntil("tab bar grows") { tabBar.height >= needed }

        set(KEY_SHOW_RICH_TAB_CONTENT, false)
        waitUntil("tab bar shrinks back") { tabBar.height == classic }
    }

    private func textLines() -> [PSMTabRichLine] {
        return TabContentLayout.defaultLayout.slots.map {
            PSMTabRichLine(text: "x", scale: $0.size.scale, bold: false, italic: false, color: nil,
                           secondary: false, lineBreakMode: .byTruncatingTail, collapsesWhenEmpty: true)
        }
    }

    // Every line of the default layout must fit in a horizontal tab's cell,
    // which is the bar minus its insets, less the text shift the styles
    // apply (at most 1pt plus the vertical-orientation shift, which a
    // horizontal bar doesn't have).
    func testEveryDefaultLineFitsInAHorizontalCell() throws {
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        let fixture = openWindow(enabled: true)
        _ = fixture.addTab()
        let frameView = try XCTUnwrap(fixture.window.contentView?.superview)
        let tabBar = try XCTUnwrap(findTabBar(in: frameView))
        let needed = fixture.terminal.tabContentConfiguration.minimumTabHeight
        waitUntil("tab bar grows") { tabBar.height >= needed }
        let cellHeight = tabBar.height - tabBar.insets.top - tabBar.insets.bottom
        let textShift: CGFloat = 1
        let rects = PSMTabRichContentRenderer.layout(lines: textLines(),
                                                     in: NSRect(x: 0, y: 0, width: 200, height: cellHeight - textShift),
                                                     baseFont: NSFont.systemFont(ofSize: 11))
        XCTAssertFalse(rects.contains(.zero), "a line was dropped: cell \(cellHeight) rects \(rects)")
    }

    // A side tab bar's rows must be tall enough too. On macOS 26 their height
    // comes from the tab style and is reapplied whenever the bar's location is
    // set, which happens on every layout.
    func testLeftTabBarRowsGrowToFitTheLayout() throws {
        iTermPreferences.setInt(2 /* PSMTab_LeftTab */, forKey: kPreferenceKeyTabPosition)
        let fixture = openWindow(enabled: true)
        _ = fixture.addTab()
        let frameView = try XCTUnwrap(fixture.window.contentView?.superview)
        let tabBar = try XCTUnwrap(findTabBar(in: frameView))
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        fixture.window.contentView?.needsLayout = true
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let needed = fixture.terminal.tabContentConfiguration.minimumTabHeight
        waitUntil("rows grow") { tabBar.height >= needed }
        XCTAssertGreaterThanOrEqual(tabBar.height, needed)
    }

    // High contrast styles draw tab text larger than the other styles. The
    // tab height must be computed at the size the style actually draws.
    func testEveryLineFitsWithHighContrastStyle() throws {
        let layout = TabContentLayout(slots: [
            TabContentSlot(identifier: TabContentSlot.titleID, size: .large),
            TabContentSlot(identifier: TabContentSlot.directoryID, size: .regular),
            TabContentSlot(identifier: TabContentSlot.jobID, size: .regular)])
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setInt(3 /* TAB_STYLE_DARK_HIGH_CONTRAST */, forKey: kPreferenceKeyTabStyle)
        let fixture = openWindow(enabled: true, [KEY_TAB_CONTENT_LAYOUT: layout.propertyList])
        _ = fixture.addTab()
        let frameView = try XCTUnwrap(fixture.window.contentView?.superview)
        let tabBar = try XCTUnwrap(findTabBar(in: frameView))
        let fontSize = try XCTUnwrap(tabBar.style.fontSize, "style reports its font size")
        let cellHeight = tabBar.height - tabBar.insets.top - tabBar.insets.bottom
        let textShift: CGFloat = 1
        let lines = layout.slots.map {
            PSMTabRichLine(text: "x", scale: $0.size.scale, bold: false, italic: false, color: nil,
                           secondary: false, lineBreakMode: .byTruncatingTail, collapsesWhenEmpty: true)
        }
        let rects = PSMTabRichContentRenderer.layout(lines: lines,
                                                     in: NSRect(x: 0, y: 0, width: 200, height: cellHeight - textShift),
                                                     baseFont: NSFont.systemFont(ofSize: fontSize))
        XCTAssertFalse(rects.contains(.zero), "a line was dropped at \(fontSize)pt: cell \(cellHeight) rects \(rects)")
    }

    // desiredTabBarHeight isn't in PseudoTerminal's header; KVC reaches it.
    private func desiredTabBarHeight(_ terminal: PseudoTerminal) -> CGFloat {
        return CGFloat((terminal.value(forKey: "desiredTabBarHeight") as? NSNumber)?.doubleValue ?? -1)
    }

    // The height mustn't depend on whether the tab bar is showing. When a
    // second tab makes it appear, the window is fitted to the bar's height
    // before the bar is laid out, so a height that changed then would leave
    // the session short of room.
    func testHeightDoesNotDependOnTabBarVisibility() throws {
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyHideTabBar)
        let fixture = openWindow(enabled: true)
        let hidden = desiredTabBarHeight(fixture.terminal)
        _ = fixture.addTab()
        XCTAssertEqual(desiredTabBarHeight(fixture.terminal), hidden)
    }

    // A side bar's rows only need room for the layout's lines. They mustn't
    // pick up the (much taller) horizontal bar height along the way.
    func testShortLayoutDoesNotOverGrowSideBarRows() throws {
        iTermPreferences.setInt(2 /* PSMTab_LeftTab */, forKey: kPreferenceKeyTabPosition)
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: TabContentSlot.titleID, size: .regular)])
        let fixture = openWindow(enabled: false, [KEY_TAB_CONTENT_LAYOUT: layout.propertyList])
        _ = fixture.addTab()
        let frameView = try XCTUnwrap(fixture.window.contentView?.superview)
        let tabBar = try XCTUnwrap(findTabBar(in: frameView))
        let classicRow = tabBar.height

        set(KEY_SHOW_RICH_TAB_CONTENT, true)
        // The lines at the style's font size, and the style's chrome.
        let needed = fixture.terminal.tabContentConfiguration.minimumTabHeight(style: tabBar.style)
        let expected = max(classicRow, needed)
        waitUntil("rows settle") { tabBar.height == expected }
        XCTAssertEqual(tabBar.height, expected)
    }

    // A compact window with a hidden tab bar draws its title where the tab
    // bar would be. That fake title bar has nothing to do with tab content,
    // so it keeps its usual height, while the hidden tab bar keeps the
    // taller height it will need when it appears.
    func testCompactTitleInPlaceOfHiddenTabBarIgnoresRichContent() throws {
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyHideTabBar)
        // Other themes turn compact windows into normal ones.
        iTermPreferences.setInt(5 /* TAB_STYLE_MINIMAL */, forKey: kPreferenceKeyTabStyle)
        let fixture = openWindow(enabled: false, windowType: .WINDOW_TYPE_COMPACT)
        let terminal = fixture.terminal
        XCTAssertTrue(drawsTitleInPlaceOfTabBar(terminal),
                      "precondition: the window draws its title in place of the tab bar")
        let classicDecoration = decorationHeight(terminal)
        let classicTabBar = desiredTabBarHeight(fixture.terminal)

        set(KEY_SHOW_RICH_TAB_CONTENT, true)
        XCTAssertGreaterThan(desiredTabBarHeight(fixture.terminal), classicTabBar,
                             "precondition: rich content makes the tab bar taller")
        XCTAssertEqual(decorationHeight(terminal), classicDecoration)
        XCTAssertEqual(windowTitleHeight(terminal), classicTabBar)

        // When a second tab shows the tab bar, the window makes room for its
        // full height.
        _ = fixture.addTab()
        XCTAssertFalse(drawsTitleInPlaceOfTabBar(terminal))
        XCTAssertEqual(decorationHeight(terminal),
                       classicDecoration - classicTabBar + desiredTabBarHeight(terminal))
    }

    // What the user sees: the session keeps its rows when a second tab shows
    // the (taller) tab bar and when closing it hides the bar again.
    func testCompactWindowKeepsRowsWhenTabBarComesAndGoes() throws {
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyHideTabBar)
        iTermPreferences.setInt(5 /* TAB_STYLE_MINIMAL */, forKey: kPreferenceKeyTabStyle)
        let fixture = openWindow(enabled: true, windowType: .WINDOW_TYPE_COMPACT)
        let first = try XCTUnwrap(fixture.terminal.currentSession())
        XCTAssertTrue(drawsTitleInPlaceOfTabBar(fixture.terminal), "precondition")
        let rows = first.screen.height()
        XCTAssertGreaterThan(rows, 1, "precondition: the session has a real grid")

        let second = fixture.addTab()
        XCTAssertFalse(drawsTitleInPlaceOfTabBar(fixture.terminal), "precondition: tab bar shown")
        XCTAssertEqual(first.screen.height(), rows)

        fixture.terminal.close(try XCTUnwrap(fixture.terminal.tab(for: second)))
        XCTAssertTrue(drawsTitleInPlaceOfTabBar(fixture.terminal), "precondition: tab bar hidden again")
        XCTAssertEqual(first.screen.height(), rows)
    }

    // A tall top tab bar in a compact window has room for the window number
    // under the stoplight buttons, so the tabs can start right after them.
    func testWindowNumberMovesUnderStoplightsInTallCompactTabBar() throws {
        iTermPreferences.setInt(0 /* PSMTab_TopTab */, forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setInt(5 /* TAB_STYLE_MINIMAL */, forKey: kPreferenceKeyTabStyle)
        let savedShowNumber = iTermPreferences.bool(forKey: kPreferenceKeyShowWindowNumber)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyShowWindowNumber)
        defer { iTermPreferences.setBool(savedShowNumber, forKey: kPreferenceKeyShowWindowNumber) }
        let fixture = openWindow(enabled: false, windowType: .WINDOW_TYPE_COMPACT)
        _ = fixture.addTab()
        let root = try XCTUnwrap(fixture.window.contentView)
        let terminal = fixture.terminal
        func numberFrame() -> NSRect { rect(root, "frameForWindowNumberLabel") }
        func buttons() -> NSRect { rect(root, "frameForStandardWindowButtons") }
        func leftInset() -> CGFloat {
            typealias F = @convention(c) (AnyObject, Selector) -> NSEdgeInsets
            let selector = NSSelectorFromString("tabBarInsets")
            return unsafeBitCast(terminal.method(for: selector), to: F.self)(terminal, selector).left
        }

        XCTAssertGreaterThan(numberFrame().minX, buttons().maxX, "classic: beside the buttons")
        let classicInset = leftInset()

        set(KEY_SHOW_RICH_TAB_CONTENT, true)
        waitUntil("layout catches up") { numberFrame().maxY <= buttons().minY + 0.5 }
        XCTAssertLessThan(numberFrame().minX, buttons().maxX, "under the buttons")
        XCTAssertLessThan(leftInset(), classicInset, "tabs start sooner")
    }

    private func rect(_ view: NSView, _ name: String) -> NSRect {
        typealias F = @convention(c) (AnyObject, Selector) -> NSRect
        let selector = NSSelectorFromString(name)
        return unsafeBitCast(view.method(for: selector), to: F.self)(view, selector)
    }

    // These are private to PseudoTerminal.
    private func decorationHeight(_ terminal: PseudoTerminal) -> CGFloat {
        typealias F = @convention(c) (AnyObject, Selector) -> NSSize
        let selector = NSSelectorFromString("windowDecorationSize")
        return unsafeBitCast(terminal.method(for: selector), to: F.self)(terminal, selector).height
    }

    private func drawsTitleInPlaceOfTabBar(_ terminal: PseudoTerminal) -> Bool {
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        let selector = NSSelectorFromString("rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar")
        return unsafeBitCast(terminal.method(for: selector), to: F.self)(terminal, selector)
    }

    private func windowTitleHeight(_ terminal: PseudoTerminal) -> CGFloat {
        typealias F = @convention(c) (AnyObject, Selector, AnyObject?) -> CGFloat
        let selector = NSSelectorFromString("rootTerminalViewHeightOfWindowTitleInPlaceOfTabBar:")
        return unsafeBitCast(terminal.method(for: selector), to: F.self)(terminal, selector, nil)
    }

    // A collapsed group's chip combines its members' lines: the directory
    // shows when they agree, and statuses are counted. (The session's job
    // poller overwrites jobName, so this uses status.)
    func testGroupLinesCombineMembers() throws {
        let fixture = openWindow(enabled: true)
        _ = fixture.addTab()
        let tabs = try XCTUnwrap(fixture.terminal.tabs())
        tabs[0].tabGroupID = "G"
        tabs[1].tabGroupID = "G"
        for tab in tabs {
            let scope = try XCTUnwrap(tab.activeSession).genericScope
            scope.setValue("/tmp/same", forVariableNamed: iTermVariableKeySessionPath)
            scope.setValue("Working", forVariableNamed: iTermVariableKeyStatus)
        }
        // PseudoTerminal implements the data source without declaring it.
        let terminal: AnyObject = fixture.terminal
        XCTAssertTrue(terminal.tabGroupsShowRichContent?() ?? false)
        func texts(_ identifier: String) -> [String]? {
            // What a reader sees: the job line is HTML.
            return (terminal.tabGroupRichLines?(withIdentifier: identifier) ?? nil)?.map(\.visibleText)
        }
        waitUntil("combined lines") { texts("G") == ["/tmp/same", " 2 Working"] }
        XCTAssertEqual(texts("G"), ["/tmp/same", " 2 Working"])
        // The number of lines depends only on the layout.
        XCTAssertEqual(texts("other"), ["", ""])
        // The tab bar sizes chips with lines that match the combined ones
        // except for their text.
        let combined = try XCTUnwrap(terminal.tabGroupRichLines?(withIdentifier: "G") ?? nil)
        let sizing = try XCTUnwrap(terminal.tabGroupRichLinesForSizing?() ?? nil)
        XCTAssertEqual(sizing.map(\.text), ["", ""])
        XCTAssertEqual(sizing.map(\.scale), combined.map(\.scale))
        XCTAssertEqual(sizing.map(\.bold), combined.map(\.bold))
    }

    // Limiting tabs to fewer lines than the layout has makes tabs, and
    // collapsed groups' chips, only tall enough for that many.
    func testLineLimitShortensTabsAndChips() throws {
        let fixture = openWindow(enabled: true)
        // PseudoTerminal implements the data source without declaring it.
        let terminal: AnyObject = fixture.terminal
        func sizingLines() -> [PSMTabRichLine]? {
            return terminal.tabGroupRichLinesForSizing?() ?? nil
        }
        let unlimitedHeight = fixture.terminal.tabContentConfiguration.minimumTabHeight
        XCTAssertEqual(sizingLines()?.count, 2, "precondition: directory and job")
        // The default layout is title, subtitle, directory, job.
        set(KEY_TAB_CONTENT_MAXIMUM_LINES, 3)
        XCTAssertLessThan(fixture.terminal.tabContentConfiguration.minimumTabHeight, unlimitedHeight)
        XCTAssertEqual(sizingLines()?.count, 1, "only the directory fits")
        XCTAssertEqual((terminal.tabGroupRichLines?(withIdentifier: "none") ?? nil)?.count, 1,
                       "a chip draws the same lines it's sized for")
        // A limit that leaves a chip no lines of its own gives it the classic
        // look.
        set(KEY_TAB_CONTENT_MAXIMUM_LINES, 2)
        XCTAssertFalse(terminal.tabGroupsShowRichContent?() ?? true)
        XCTAssertNil(sizingLines())
    }
}

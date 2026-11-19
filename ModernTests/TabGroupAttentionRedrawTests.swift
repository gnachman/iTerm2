//
//  TabGroupAttentionRedrawTests.swift
//  ModernTests
//
//  A collapsed tab group's chip shows the icon of its most urgent member,
//  where statuses are ranked by iTermStatusPrioritySettings. Reordering those
//  priorities can change which member wins, so the tab bar has to redraw.
//

import XCTest
@testable import iTerm2SharedARC

final class TabGroupAttentionRedrawTests: XCTestCase {
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

    func testChangingStatusPrioritiesRedrawsTabBar() throws {
        // A window with one tab may hide its tab bar, and AppKit doesn't
        // mark a hidden view as needing display.
        _ = fixture.addTab()
        // The tab bar can live in the titlebar, outside the content view, so
        // search the whole frame view.
        let frameView = try XCTUnwrap(fixture.window.contentView?.superview)
        let tabBar = try XCTUnwrap(findTabBar(in: frameView))
        XCTAssertFalse(tabBar.isHidden, "precondition: tab bar is visible")
        tabBar.displayIfNeeded()
        XCTAssertFalse(tabBar.needsDisplay, "precondition: nothing pending")

        NotificationCenter.default.post(name: StatusPrioritySettings.didChangeNotification,
                                        object: StatusPrioritySettings.shared)

        XCTAssertTrue(tabBar.needsDisplay)
    }

    // PseudoTerminal implements the tab group data source without declaring
    // conformance, so call it dynamically.
    private func attentionImage(_ identifier: String) -> NSImage? {
        let terminal: AnyObject = fixture.terminal
        return terminal.tabGroupAttentionImage?(withIdentifier: identifier) ?? nil
    }

    // The window supplies the chip's icon: the icon of the most urgent tab in
    // that group, ignoring tabs outside it.
    func testAttentionImageComesFromMostUrgentMemberOfThatGroup() throws {
        _ = fixture.addTab()
        _ = fixture.addTab()
        _ = fixture.addTab()
        let tabs = try XCTUnwrap(fixture.terminal.tabs())
        XCTAssertEqual(tabs.count, 4)
        tabs[1].tabGroupID = "G"
        tabs[2].tabGroupID = "G"

        XCTAssertNil(attentionImage("G"),
                     "no member needs attention yet")

        // A bell outside the group must not count.
        tabs[3].setBell(true)
        XCTAssertNil(attentionImage("G"))

        tabs[2].setBell(true)
        let image = try XCTUnwrap(attentionImage("G"))
        XCTAssertEqual(image.tiffRepresentation, tabs[2].icon?.tiffRepresentation)
    }

    // From PTYTabDelegate.h.
    private let bellState: UInt = 1 << 0
    private let deadState: UInt = 1 << 3

    // -setState:reset: is private to PTYTab.
    private func setState(_ tab: PTYTab, set: UInt) {
        typealias SetState = @convention(c) (AnyObject, Selector, UInt, UInt) -> Void
        let selector = NSSelectorFromString("setState:reset:")
        let imp = tab.method(for: selector)
        unsafeBitCast(imp, to: SetState.self)(tab, selector, set, 0)
    }

    private func groupOfTwo() throws -> [PTYTab] {
        _ = fixture.addTab()
        _ = fixture.addTab()
        let tabs = try XCTUnwrap(fixture.terminal.tabs())
        tabs[1].tabGroupID = "G"
        tabs[2].tabGroupID = "G"
        return [tabs[1], tabs[2]]
    }

    // A snoozed member shows a moon, but when every member is dead the chip
    // reports death, so it must show the dead icon rather than the moon.
    func testSnoozedDeadMemberGivesTheDeadIcon() throws {
        let savedShowStatus = iTermUserDefaults.showSessionStatusInTabSubtitle
        iTermUserDefaults.showSessionStatusInTabSubtitle = true
        defer {
            iTermUserDefaults.showSessionStatusInTabSubtitle = savedShowStatus
        }
        let members = try groupOfTwo()
        let session = try XCTUnwrap(members[0].activeSession)
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "Working"
        update.indicatorPresence = .set
        update.indicator = iTermSRGBColor(r: 0, g: 0, b: 1)
        session.screenSetTabStatus(update)
        defer {
            session.clearTabStatus()
        }
        SessionStatusController.instance.setSnoozed(true, sessionIDs: [session.guid])
        XCTAssertTrue(members[0].isSnoozed, "precondition")

        setState(members[0], set: deadState)
        setState(members[1], set: deadState)
        let image = try XCTUnwrap(attentionImage("G"))
        XCTAssertEqual(image.tiffRepresentation, members[1].icon?.tiffRepresentation,
                       "the chip shows the dead icon, not the snoozed member's moon")
    }

    func testOneDeadMemberDoesNotFlagTheGroup() throws {
        let members = try groupOfTwo()
        setState(members[0], set: deadState)
        XCTAssertNotNil(members[0].icon, "precondition: the dead tab shows an icon")
        XCTAssertNil(attentionImage("G"))

        setState(members[1], set: deadState)
        let image = try XCTUnwrap(attentionImage("G"))
        XCTAssertEqual(image.tiffRepresentation, members[0].icon?.tiffRepresentation)
    }

    // A member that died after ringing the bell shows the dead icon itself,
    // but the group still has a bell to report, so the chip shows a bell.
    func testBellOfDeadMemberShowsBellOnChip() throws {
        let members = try groupOfTwo()
        setState(members[1], set: bellState | deadState)
        let bell = PTYTab.bellImage().tiffRepresentation
        XCTAssertNotEqual(members[1].icon?.tiffRepresentation, bell, "precondition: the tab's own icon isn't the bell")
        let image = try XCTUnwrap(attentionImage("G"))
        XCTAssertEqual(image.tiffRepresentation, bell)
    }
}

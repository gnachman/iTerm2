//
//  PTYTabSnoozeTests.swift
//  ModernTests
//
//  A tab whose sessions are all snoozed shows that it is, and stops asking
//  for attention in a collapsed group.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTabSnoozeTests: XCTestCase {
    private var savedShowStatus = false
    private var tabViewItems = [NSTabViewItem]()
    private var sessions = [PTYSession]()
    private var savedPriorities = [StatusPriorityEntry]()

    override func setUp() {
        super.setUp()
        savedShowStatus = iTermUserDefaults.showSessionStatusInTabSubtitle
        iTermUserDefaults.showSessionStatusInTabSubtitle = true
        // Create the controller before any status is set, so it hears of them.
        _ = SessionStatusController.instance
        // Known priorities, so “Waiting” is the most urgent.
        savedPriorities = StatusPrioritySettings.shared.entries
        StatusPrioritySettings.shared.restoreEntries(["wait", "done", "error", "work", "idle"].map {
            StatusPriorityEntry(pattern: $0)
        })
    }

    override func tearDown() {
        for session in sessions {
            session.clearTabStatus()
        }
        sessions.removeAll()
        tabViewItems.removeAll()
        iTermUserDefaults.showSessionStatusInTabSubtitle = savedShowStatus
        StatusPrioritySettings.shared.restoreEntries(savedPriorities)
        super.tearDown()
    }

    private func makeSession() -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.view = SessionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        sessions.append(session)
        return session
    }

    private func makeTab(_ session: PTYSession) -> PTYTab {
        let tab = PTYTab(session: session, parentWindow: nil)!
        let item = NSTabViewItem(identifier: tab)
        tabViewItems.append(item)
        tab.tabViewItem = item
        return tab
    }

    private func setStatus(_ text: String, on session: PTYSession) {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = text
        update.indicatorPresence = .set
        update.indicator = iTermSRGBColor(r: 0, g: 0, b: 1)
        session.screenSetTabStatus(update)
    }

    private var controller: SessionStatusController {
        return SessionStatusController.instance
    }

    func testSnoozingTheSessionSnoozesTheTab() {
        let session = makeSession()
        let tab = makeTab(session)
        setStatus("Working", on: session)
        XCTAssertFalse(tab.isSnoozed)
        let awakeIcon = tab.icon
        XCTAssertNotNil(awakeIcon)
        XCTAssertEqual(tab.attentionCandidate.kind, .status)

        controller.setSnoozed(true, sessionIDs: [session.guid])
        XCTAssertTrue(tab.isSnoozed)
        XCTAssertNotNil(tab.icon)
        // Compare what's drawn: every update makes a new image object.
        XCTAssertNotEqual(tab.icon?.tiffRepresentation, awakeIcon?.tiffRepresentation,
                          "a snoozed tab shows a different icon")
        XCTAssertEqual(tab.icon?.tiffRepresentation,
                       iTermSessionTabStatus.snoozedImage(color: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
                                                          size: 16).tiffRepresentation)
        XCTAssertEqual(tab.attentionCandidate.kind, TabIconKind.none,
                       "a snoozed tab doesn't ask for attention in a collapsed group")
    }

    func testAStatusChangeWakesTheTab() {
        let session = makeSession()
        let tab = makeTab(session)
        setStatus("Working", on: session)
        let dot = tab.icon?.tiffRepresentation
        controller.setSnoozed(true, sessionIDs: [session.guid])
        // Not a waiting status, which would draw a ring around the dot.
        setStatus("Idle", on: session)
        XCTAssertFalse(tab.isSnoozed)
        XCTAssertEqual(tab.attentionCandidate.kind, .status)
        XCTAssertEqual(tab.icon?.tiffRepresentation, dot, "the dot is back")
    }

    func testTabWithoutStatusIsNotSnoozed() {
        let tab = makeTab(makeSession())
        XCTAssertFalse(tab.isSnoozed)
    }

    // Split panes: the tab is snoozed only when every pane with a status is.
    func testEveryPaneWithAStatusMustBeSnoozed() {
        let first = makeSession()
        let tab = makeTab(first)
        let second = makeSession()
        tab.splitVertically(true, newSession: second, before: false, targetSession: first)
        let third = makeSession()
        tab.splitVertically(true, newSession: third, before: false, targetSession: first)
        setStatus("Working", on: first)
        setStatus("Working", on: second)

        controller.setSnoozed(true, sessionIDs: [first.guid])
        XCTAssertFalse(tab.isSnoozed)
        // The third pane has no status, so it doesn't keep the tab awake.
        controller.setSnoozed(true, sessionIDs: [second.guid])
        XCTAssertTrue(tab.isSnoozed)
    }

    // The focused pane's status usually wins, but not over an awake pane when
    // it's snoozed: the tab would show the status the user snoozed and hide
    // the one that's awake.
    func testAwakePaneWinsOverSnoozedFocusedPane() {
        let first = makeSession()
        let tab = makeTab(first)
        let second = makeSession()
        tab.splitVertically(true, newSession: second, before: false, targetSession: first)
        tab.activeSession = first
        setStatus("Waiting", on: first)
        setStatus("Working", on: second)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Waiting", "precondition: the focused pane wins")

        controller.setSnoozed(true, sessionIDs: [first.guid])
        XCTAssertFalse(tab.isSnoozed)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Working")

        // With every pane snoozed, the focused pane wins again.
        controller.setSnoozed(true, sessionIDs: [second.guid])
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Waiting")
    }

    // -tabStatusWaitingProminent is private.
    private func waitingRing(_ tab: PTYTab) -> Bool {
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let selector = NSSelectorFromString("tabStatusWaitingProminent")
        return unsafeBitCast(tab.method(for: selector), to: Getter.self)(tab, selector)
    }

    // Shows the reader below works.
    func testAStatusThatStartsWaitingRings() {
        let session = makeSession()
        let tab = makeTab(session)
        setStatus("Working", on: session)
        setStatus("Waiting", on: session)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Waiting")
        XCTAssertTrue(waitingRing(tab))
    }

    // The ring marks a status that just started waiting. Snoozing another
    // pane can bring an old waiting status forward, which isn't news.
    func testSnoozeDoesNotRingAnOldWaitingStatus() {
        let first = makeSession()
        let tab = makeTab(first)
        let second = makeSession()
        tab.splitVertically(true, newSession: second, before: false, targetSession: first)
        tab.activeSession = first
        setStatus("Working", on: first)
        setStatus("Waiting", on: second)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Working", "precondition")
        XCTAssertFalse(waitingRing(tab), "precondition")

        controller.setSnoozed(true, sessionIDs: [first.guid])
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Waiting")
        XCTAssertFalse(waitingRing(tab))
    }

    // Snooze lasts until the status next changes. A change to waiting is
    // news, so it rings, as it would had the session never been snoozed.
    func testAWaitingStatusThatWakesASnoozedSessionRings() {
        let session = makeSession()
        let tab = makeTab(session)
        setStatus("Working", on: session)
        controller.setSnoozed(true, sessionIDs: [session.guid])
        setStatus("Waiting", on: session)
        XCTAssertFalse(tab.isSnoozed)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Waiting")
        XCTAssertTrue(waitingRing(tab))
    }

    // The focused pane's status wins, so focusing another pane can change
    // the tab's status.
    func testFocusChangeUpdatesTheTabStatus() {
        let first = makeSession()
        let tab = makeTab(first)
        let second = makeSession()
        tab.splitVertically(true, newSession: second, before: false, targetSession: first)
        tab.activeSession = first
        setStatus("Working", on: first)
        setStatus("Idle", on: second)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Working", "precondition")

        tab.activeSession = second
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Idle")
        XCTAssertFalse(waitingRing(tab))
    }

    // A pane swapped in from another tab is news for this tab: its waiting
    // status rings here, unlike a focus change within the tab.
    func testSwappedInWaitingPaneRings() {
        let first = makeSession()
        let tab = makeTab(first)
        let other = makeSession()
        let otherTab = makeTab(other)
        setStatus("Working", on: first)
        setStatus("Waiting", on: other)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Working", "precondition")

        tab.swapSession(first, with: other)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Waiting")
        XCTAssertTrue(waitingRing(tab))
        XCTAssertEqual(otherTab.aggregatedTabStatus.statusText, "Working")
    }

    // The same when the pane swapped out isn't the focused one.
    func testWaitingPaneSwappedInForAnUnfocusedPaneRings() {
        let focused = makeSession()
        let tab = makeTab(focused)
        let unfocused = makeSession()
        tab.splitVertically(true, newSession: unfocused, before: false, targetSession: focused)
        tab.activeSession = focused
        let other = makeSession()
        _ = makeTab(other)
        setStatus("Working", on: focused)
        setStatus("Waiting", on: other)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Working", "precondition")

        tab.swapSession(unfocused, with: other)
        XCTAssertEqual(tab.aggregatedTabStatus.statusText, "Waiting")
        XCTAssertTrue(waitingRing(tab))
    }

    func testSnoozeTargetsAreThePanesWithAStatus() {
        let first = makeSession()
        let tab = makeTab(first)
        let second = makeSession()
        tab.splitVertically(true, newSession: second, before: false, targetSession: first)
        setStatus("Working", on: second)
        XCTAssertEqual(tab.snoozableSessionIDs, [second.guid])
    }
}

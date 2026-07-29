//
//  SessionTabStatusBroadcastTests.swift
//  ModernTests
//
//  Regression coverage for the workgroup peer-swap bug where switching
//  to a peer wiped the main session's Session Status. Root cause: the
//  tab-internal aggregate status (PTYTab._aggregatedTabStatus, built
//  via copyStatus()) borrows the winning session's sessionID, and its
//  clear() broadcast a per-session change that made
//  SessionStatusController drop the real session's still-live status.
//

import XCTest
@testable import iTerm2SharedARC

final class SessionTabStatusBroadcastTests: XCTestCase {
    private func working(_ status: iTermSessionTabStatus) {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "Working"
        _ = status.apply(update)
    }

    private func observe(_ object: iTermSessionTabStatus,
                         while body: () -> Void) -> Bool {
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: iTermSessionTabStatus.didChangeNotificationName,
            object: object,
            queue: nil) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }
        body()
        return fired
    }

    // A real per-session status broadcasts its changes (this is what
    // SessionStatusController tracks).
    func test_realStatusBroadcasts() {
        let status = iTermSessionTabStatus(sessionID: UUID().uuidString)
        XCTAssertTrue(observe(status) { working(status) },
                      "Setting a status must broadcast")
        XCTAssertTrue(observe(status) { status.clear() },
                      "Clearing a status must broadcast")
    }

    // The copyStatus() aggregate must NOT broadcast — it shares the
    // source session's sessionID, so a broadcast on clear would be
    // misread as the source session losing its status.
    func test_aggregateCopyDoesNotBroadcast() {
        let real = iTermSessionTabStatus(sessionID: UUID().uuidString)
        working(real)
        let aggregate = real.copyStatus()
        XCTAssertEqual(aggregate.sessionID, real.sessionID,
                       "The aggregate borrows the source sessionID (the hazard)")
        XCTAssertFalse(observe(aggregate) { aggregate.clear() },
                       "Clearing the aggregate must not broadcast a per-session change")
        XCTAssertFalse(observe(aggregate) { working(aggregate) },
                       "Mutating the aggregate must not broadcast either")
    }

    // End to end: clearing a tab aggregate (as a peer swap does when
    // the new active session has no status) must not evict the real
    // session's status from SessionStatusController.
    func test_clearingAggregateDoesNotDropRealSessionStatus() {
        let controller = SessionStatusController.instance
        let guid = UUID().uuidString
        let real = iTermSessionTabStatus(sessionID: guid)
        // The real status broadcasts, so the controller picks it up.
        working(real)
        XCTAssertNotNil(controller.statuses[guid],
                        "Precondition: the real status is tracked")
        // The tab rolls it into an aggregate, then the active session
        // changes to one with no status and the aggregate is cleared.
        let aggregate = real.copyStatus()
        aggregate.clear()
        XCTAssertNotNil(controller.statuses[guid],
                        "Clearing the tab aggregate must not drop the real session status")
        // Cleanup: clearing the real status removes it from the shared
        // controller so this test doesn't leak into others.
        real.clear()
        XCTAssertNil(controller.statuses[guid])
    }
}

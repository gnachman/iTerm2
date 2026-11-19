//
//  SessionStatusSnoozeTests.swift
//  ModernTests
//
//  Snooze is shared: the session status tool and the tab bar both read and
//  set it through SessionStatusController.
//

import XCTest
@testable import iTerm2SharedARC

final class SessionStatusSnoozeTests: XCTestCase {
    private let controller = SessionStatusController.instance
    private var statuses = [iTermSessionTabStatus]()

    override func tearDown() {
        for status in statuses {
            status.clear()
        }
        statuses.removeAll()
        super.tearDown()
    }

    private func set(_ text: String, on status: iTermSessionTabStatus) {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = text
        _ = status.apply(update)
    }

    // A session with a status, tracked by the controller.
    private func makeSession(_ text: String = "Working") -> iTermSessionTabStatus {
        let status = iTermSessionTabStatus(sessionID: UUID().uuidString)
        statuses.append(status)
        set(text, on: status)
        XCTAssertNotNil(controller.statuses[status.sessionID], "precondition")
        return status
    }

    private var wokenByStatusChange = [Bool]()

    private func snoozeNotifications(during body: () -> Void) -> [Set<String>] {
        var received = [Set<String>]()
        let token = NotificationCenter.default.addObserver(
            forName: SessionStatusController.snoozeDidChangeNotification,
            object: controller,
            queue: nil) { [weak self] notification in
                received.append(notification.userInfo?[SessionStatusController.sessionIDsKey] as? Set<String> ?? [])
                self?.wokenByStatusChange.append(notification.userInfo?[SessionStatusController.wokenByStatusChangeKey] as? Bool ?? false)
            }
        defer {
            NotificationCenter.default.removeObserver(token)
        }
        body()
        return received
    }

    func testSnoozeAndUnsnooze() {
        let status = makeSession()
        XCTAssertFalse(controller.isSnoozed(sessionID: status.sessionID))
        controller.setSnoozed(true, sessionIDs: [status.sessionID])
        XCTAssertTrue(controller.isSnoozed(sessionID: status.sessionID))
        controller.setSnoozed(false, sessionIDs: [status.sessionID])
        XCTAssertFalse(controller.isSnoozed(sessionID: status.sessionID))
    }

    func testChangesAreAnnounced() {
        let a = makeSession()
        let b = makeSession()
        let received = snoozeNotifications {
            controller.setSnoozed(true, sessionIDs: [a.sessionID, b.sessionID])
            // Already snoozed: nothing changes, so nothing is announced.
            controller.setSnoozed(true, sessionIDs: [a.sessionID])
        }
        XCTAssertEqual(received, [[a.sessionID, b.sessionID]])
    }

    // A session with no status has nothing to snooze, and nothing would ever
    // wake it.
    func testSessionWithoutStatusCannotBeSnoozed() {
        let id = UUID().uuidString
        let received = snoozeNotifications {
            controller.setSnoozed(true, sessionIDs: [id])
        }
        XCTAssertFalse(controller.isSnoozed(sessionID: id))
        XCTAssertEqual(received, [])
    }

    // The next status change wakes it. Observers of the statuses already see
    // it awake when they hear about the change.
    func testStatusChangeUnsnoozes() {
        let status = makeSession()
        controller.setSnoozed(true, sessionIDs: [status.sessionID])
        var snoozedWhenObserved: Bool?
        var token: NotifyingDictionaryObserverToken? = controller.addObserver { [controller] key, _, _ in
            if key == status.sessionID {
                snoozedWhenObserved = controller.isSnoozed(sessionID: key)
            }
        }
        let received = snoozeNotifications {
            set("Waiting", on: status)
        }
        // Releasing the token removes the observer.
        withExtendedLifetime(token) {}
        token = nil
        XCTAssertFalse(controller.isSnoozed(sessionID: status.sessionID))
        XCTAssertEqual(snoozedWhenObserved, false)
        XCTAssertEqual(received, [[status.sessionID]])
        // The status tool applies status changes after a short delay, and
        // leaves this wake to that update rather than redrawing twice.
        XCTAssertEqual(wokenByStatusChange, [true])
    }

    func testUserSnoozeIsNotAStatusChange() {
        let status = makeSession()
        _ = snoozeNotifications {
            controller.setSnoozed(true, sessionIDs: [status.sessionID])
            controller.setSnoozed(false, sessionIDs: [status.sessionID])
        }
        XCTAssertEqual(wokenByStatusChange, [false, false])
    }

    func testRemovingTheStatusUnsnoozes() {
        let status = makeSession()
        controller.setSnoozed(true, sessionIDs: [status.sessionID])
        status.clear()
        XCTAssertFalse(controller.isSnoozed(sessionID: status.sessionID))
        // A status that comes back starts awake.
        set("Working", on: status)
        XCTAssertFalse(controller.isSnoozed(sessionID: status.sessionID))
    }
}

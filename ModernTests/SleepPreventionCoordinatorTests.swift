//
//  SleepPreventionCoordinatorTests.swift
//  ModernTests
//
//  Tests for the pure count decision of the sleep-prevention coordinator: how many sessions keep
//  the machine awake, including exclusion of a terminating session (F1) and de-duplication of a
//  session that transiently appears in both the live and buried lists while being buried (F25).
//

import XCTest
@testable import iTerm2SharedARC

final class SleepPreventionCoordinatorTests: XCTestCase {
    private func count(_ guids: [String],
                       excluding: String? = nil,
                       onPower: Bool = true,
                       battery: Bool = false) -> Int {
        return SleepPreventionCoordinator.numberOfSessionsPreventingSleep(
            requesterGUIDs: guids, excludingGUID: excluding,
            connectedToPower: onPower, allowedOnBattery: battery)
    }

    // F1: the terminating session is still enumerated at WillTerminate time, so excluding the last
    // requester must drop the count to 0 (assertion released).
    func testLastRequesterTerminatingReleases() {
        XCTAssertEqual(count(["A"], excluding: "A"), 0)
    }

    func testOtherRequesterRemainsHolds() {
        XCTAssertEqual(count(["A", "B"], excluding: "A"), 1)
    }

    func testNoExclusionCounts() {
        XCTAssertEqual(count(["A"]), 1)
        XCTAssertEqual(count(["A", "B"]), 2)
    }

    func testNoRequestersIsZero() {
        XCTAssertEqual(count([]), 0)
    }

    // AC-only (allowedOnBattery == false) on battery: hold nothing.
    func testACOnlyOnBatteryIsZero() {
        XCTAssertEqual(count(["A"], onPower: false, battery: false), 0)
    }

    func testBatteryAllowedCounts() {
        XCTAssertEqual(count(["A"], onPower: false, battery: true), 1)
    }

    // F25: a session buried transiently appears in both allSessions() and buriedSessions(), so the
    // requester list contains its GUID twice. It must be counted once.
    func testDuplicateGuidsCountedOnce() {
        XCTAssertEqual(count(["G", "G"]), 1)
        XCTAssertEqual(count(["G", "G", "H"]), 2)
    }

    func testExcludingNonRequesterHolds() {
        XCTAssertEqual(count(["A", "B"], excluding: "Z"), 2)
    }

    // The ungated requester count (for the status label) ignores the power gate but still dedups
    // and honors exclusion. On battery with the default policy, holding==0 while requesting>0, which
    // is what lets the label say "would prevent sleep, but disabled on battery" instead of "none".
    func testRequesterCountIgnoresPowerGate() {
        func requesting(_ guids: [String], excluding: String? = nil) -> Int {
            return SleepPreventionCoordinator.numberOfSessionsRequestingPreventSleep(
                requesterGUIDs: guids, excludingGUID: excluding)
        }
        // On battery, gated count is 0 but requester count is not.
        XCTAssertEqual(count(["A"], onPower: false, battery: false), 0)
        XCTAssertEqual(requesting(["A"]), 1)
        XCTAssertEqual(requesting(["G", "G", "H"]), 2)   // dedup
        XCTAssertEqual(requesting(["A", "B"], excluding: "A"), 1)
    }
}

// Drives a coordinator instance with fake sessions, a private notification center, a manual
// scheduler, and a fake assertion so the restart and revive paths can be tested deterministically.
final class SleepPreventionCoordinatorLifecycleTests: XCTestCase {
    private final class Fixture {
        var requesters: [String] = []
        var pendingBlocks: [() -> Void] = []
        var heldAssertions = 0
        let center = NotificationCenter()
        lazy var coordinator: SleepPreventionCoordinator = {
            let environment = SleepPreventionCoordinator.Environment(
                requesterGUIDs: { [unowned self] in self.requesters },
                connectedToPower: { true },
                allowedOnBattery: { false },
                scheduleOnNextTurn: { [unowned self] block in self.pendingBlocks.append(block) },
                beginAssertion: { [unowned self] in
                    self.heldAssertions += 1
                    return NSObject()
                },
                endAssertion: { [unowned self] _ in self.heldAssertions -= 1 })
            return SleepPreventionCoordinator(environment: environment, notificationCenter: center)
        }()

        func runPendingBlocks() {
            let blocks = pendingBlocks
            pendingBlocks = []
            blocks.forEach { $0() }
        }
    }

    // F-003 / F-200: Restart Session clears the session's exited flag (brokenPipe already dropped it
    // from the requesters). The coordinator must recompute when that flips, without needing some
    // unrelated event.
    func testExitedDidChangeRecomputes() {
        let fixture = Fixture()
        _ = fixture.coordinator
        XCTAssertEqual(fixture.coordinator.numberOfSessionsPreventingSleep, 0)

        // The restarted session is a requester again.
        fixture.requesters = ["A"]
        fixture.center.post(name: .PTYSessionExitedDidChange, object: nil)

        XCTAssertEqual(fixture.coordinator.numberOfSessionsPreventingSleep, 1)
        XCTAssertEqual(fixture.heldAssertions, 1)
    }

    // The explicit recompute in brokenPipe was replaced by this notification, so a session whose
    // process exits must still release the assertion when it was the last requester.
    func testExitedDidChangeReleasesWhenLastRequesterExits() {
        let fixture = Fixture()
        fixture.requesters = ["A"]
        _ = fixture.coordinator
        XCTAssertEqual(fixture.heldAssertions, 1)

        fixture.requesters = []
        fixture.center.post(name: .PTYSessionExitedDidChange, object: nil)

        XCTAssertEqual(fixture.coordinator.numberOfSessionsPreventingSleep, 0)
        XCTAssertEqual(fixture.heldAssertions, 0)
    }

    // F-204: -revive posts PTYSessionRevived before its caller re-adds the session to a window, so a
    // recompute at that moment can't see it. The coordinator must recompute on a later turn.
    func testReviveRecomputesAfterSessionIsReAdded() {
        let fixture = Fixture()
        _ = fixture.coordinator
        fixture.runPendingBlocks()

        // -revive posts while the session is not yet enumerated.
        fixture.center.post(name: .PTYSessionRevived, object: nil)
        // Later in the same turn the caller adds it back to a window.
        fixture.requesters = ["A"]
        XCTAssertEqual(fixture.heldAssertions, 0)

        // Next main-queue turn.
        fixture.runPendingBlocks()

        XCTAssertEqual(fixture.coordinator.numberOfSessionsPreventingSleep, 1)
        XCTAssertEqual(fixture.heldAssertions, 1)
    }

    // Undo Close of several sessions at once posts PTYSessionRevived for each; one deferred
    // recompute is enough.
    func testMultipleRevivesCoalesce() {
        let fixture = Fixture()
        _ = fixture.coordinator
        fixture.center.post(name: .PTYSessionRevived, object: nil)
        fixture.center.post(name: .PTYSessionRevived, object: nil)
        XCTAssertEqual(fixture.pendingBlocks.count, 1)
    }

    // The coordinator relies on PTYSession posting PTYSessionExitedDidChange whenever its exited
    // state actually flips (Restart Session calls -setExited:NO in
    // -replaceTerminatedShellWithNewInstance), and not when it is set to its current value.
    func testSessionPostsExitedDidChangeOnlyWhenItFlips() {
        let session = PTYSession(synthetic: false)!
        var posts = 0
        let token = NotificationCenter.default.addObserver(forName: .PTYSessionExitedDidChange,
                                                           object: session,
                                                           queue: nil) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        XCTAssertFalse(session.exited)
        session.setValue(false, forKey: "exited")
        XCTAssertEqual(posts, 0)

        session.setValue(true, forKey: "exited")
        XCTAssertTrue(session.exited)
        XCTAssertEqual(posts, 1)

        session.setValue(true, forKey: "exited")
        XCTAssertEqual(posts, 1)

        session.setValue(false, forKey: "exited")
        XCTAssertFalse(session.exited)
        XCTAssertEqual(posts, 2)
    }
}

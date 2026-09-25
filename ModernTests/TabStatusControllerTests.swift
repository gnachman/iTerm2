//
//  TabStatusControllerTests.swift
//  ModernTests
//
//  The state machine behind a status that is scoped to an operation: which
//  operation an armed expiration belongs to, what counts as that operation
//  ending, and what may release or cancel it. The subtle cases are the ones
//  where something arrives during or after the head start, so most of these
//  drive the real timer with a short delay.
//

import XCTest
@testable import iTerm2SharedARC

final class TabStatusControllerTests: XCTestCase {
    private static let delay: TimeInterval = 0.01
    // Long enough that a slow machine still fires the timer, short enough to
    // keep the suite quick. Only used to wait for something that should
    // happen; the inverted waits below can only produce false passes, never
    // false failures.
    private static let timeout: TimeInterval = 5.0

    private var controller: TabStatusController!
    private var changes: [String?] = []
    /// The status the controller owns. Reading it creates one, the way a
    /// program setting a status would, so the test that cares about a session
    /// never having one checks `statusIfPresent` instead.
    private var status: iTermSessionTabStatus { controller.status }

    override func setUp() {
        super.setUp()
        changes = []
        controller = TabStatusController(
            sessionID: { "s" },
            didChange: { [weak self] previous in
                self?.changes.append(previous)
            },
            progressEndDelay: Self.delay)
    }

    private func makeController() -> TabStatusController {
        return controller
    }

    /// A controller with a head start long enough that the timer will not fire
    /// during the test, for checking what happens inside the window.
    private func makeController(progressEndDelay: TimeInterval) -> TabStatusController {
        controller = TabStatusController(
            sessionID: { "s" },
            didChange: { [weak self] previous in
                self?.changes.append(previous)
            },
            progressEndDelay: progressEndDelay)
        return controller
    }

    private func working(expiring: Bool, backgroundTasks: Int? = nil) -> VT100TabStatusUpdate {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "working"
        if expiring {
            let fallback = VT100TabStatusUpdate()
            fallback.statusPresence = .set
            fallback.status = "idle"
            update.expiresOn = .progressEnd
            update.expirationFallback = fallback
        }
        if let backgroundTasks {
            update.backgroundTasksPresence = .set
            update.backgroundTasks = backgroundTasks
        }
        return update
    }

    private func bookkeeping(backgroundTasks: Int) -> VT100TabStatusUpdate {
        let update = VT100TabStatusUpdate()
        update.backgroundTasksPresence = .set
        update.backgroundTasks = backgroundTasks
        return update
    }

    /// Waits for a status text to appear, failing if it does not.
    private func expectStatus(_ text: String?, _ controller: () -> Void) {
        let reached = expectation(description: "status becomes \(text ?? "nil")")
        var fulfilled = false
        let poll = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { [weak self] timer in
            if self?.status.statusText == text && !fulfilled {
                fulfilled = true
                timer.invalidate()
                reached.fulfill()
            }
        }
        controller()
        wait(for: [reached], timeout: Self.timeout)
        poll.invalidate()
    }

    /// Runs the main run loop well past the delay so anything that was going
    /// to happen has happened.
    private func settle() {
        let idle = expectation(description: "settle")
        idle.isInverted = true
        wait(for: [idle], timeout: Self.delay * 20 + 0.2)
    }

    // MARK: - The basic loop

    func testOperationEndExpiresTheStatus() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        XCTAssertEqual(status.statusText, "working")

        expectStatus("idle") {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(.stopped)
        }
    }

    func testAProgressOnlySessionSchedulesNothing() {
        // A program that reports progress but never sets a status must not
        // leave work behind, and in particular must not make the session
        // materialize a status object it never asked for.
        let controller = makeController()

        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)
        settle()

        XCTAssertNil(controller.statusIfPresent, "no status should have been created")
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(controller.hasArmedExpiration)
    }

    func testStopWithNoStartDoesNothing() {
        let controller = makeController()
        controller.apply(working(expiring: true))

        controller.progressProtocolDidReport(.stopped)
        settle()
        XCTAssertEqual(status.statusText, "working")
    }

    func testAssertionDuringTheHeadStartWins() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)

        let waiting = VT100TabStatusUpdate()
        waiting.statusPresence = .set
        waiting.status = "waiting"
        controller.apply(waiting)

        settle()
        XCTAssertEqual(status.statusText, "waiting")
    }

    func testProgressResumingDuringTheHeadStartCancels() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)
        controller.progressProtocolDidReport(.indeterminate)

        settle()
        XCTAssertEqual(status.statusText, "working")
    }

    // MARK: - What ends an operation

    func testErrorEndsTheOperation() {
        // A program that reports a failure has finished narrating, and may
        // never send a stop at all.
        let controller = makeController()
        controller.apply(working(expiring: true))

        expectStatus("idle") {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(.error)
        }
    }

    func testErrorWithPercentageEndsTheOperation() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        let errorAt50 = VT100ScreenProgress(rawValue: VT100ScreenProgress.errorBase.rawValue + 50)!

        expectStatus("idle") {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(errorAt50)
        }
    }

    func testPausedDoesNotEndTheOperation() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        let paused = VT100ScreenProgress(rawValue: VT100ScreenProgress.warningBase.rawValue + 50)!

        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(paused)
        settle()
        XCTAssertEqual(status.statusText, "working")
    }

    // MARK: - What supersedes an expiration

    func testAssertionWithoutAnExpirationDisarms() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        XCTAssertTrue(controller.hasArmedExpiration)

        controller.apply(working(expiring: false))
        XCTAssertFalse(controller.hasArmedExpiration)

        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)
        settle()
        XCTAssertEqual(status.statusText, "working")
    }

    func testLaterAssertionRearmsWithItsOwnFallback() {
        let controller = makeController()
        controller.apply(working(expiring: true))

        let waiting = VT100TabStatusUpdate()
        waiting.statusPresence = .set
        waiting.status = "waiting"
        let fallback = VT100TabStatusUpdate()
        fallback.statusPresence = .set
        fallback.status = "done"
        waiting.expiresOn = .progressEnd
        waiting.expirationFallback = fallback
        controller.apply(waiting)

        expectStatus("done") {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(.stopped)
        }
    }

    func testArmingHappensEvenWhenNothingVisibleChanges() {
        // A program that re-sends the status it already set must still arm, or
        // the no-change short circuit would silently lose the expiration.
        let controller = makeController()
        controller.apply(working(expiring: false))
        changes = []
        controller.apply(working(expiring: true))
        XCTAssertTrue(changes.isEmpty, "nothing visible changed")

        expectStatus("idle") {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(.stopped)
        }
    }

    func testBookkeepingDoesNotDisarm() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        controller.apply(bookkeeping(backgroundTasks: 3))

        XCTAssertTrue(controller.hasArmedExpiration)
        XCTAssertEqual(status.backgroundTasks, 3)
    }

    func testAnExpirationIsNotReusedAfterItFires() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        expectStatus("idle") {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(.stopped)
        }
        XCTAssertFalse(controller.hasArmedExpiration)

        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)
        settle()
        XCTAssertEqual(status.statusText, "idle")
    }

    func testFallbackWithNoFieldsClearsTheStatus() {
        let controller = makeController()
        let update = working(expiring: true)
        update.expirationFallback = VT100TabStatusUpdate.clear
        controller.apply(update)

        expectStatus(nil) {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(.stopped)
        }
        XCTAssertFalse(status.hasActiveStatus)
    }

    func testAnExpirationCanBeArmedWithNoVisibleField() {
        // clearTabStatus has to consult the controller rather than the status,
        // because an expiration can exist with nothing showing.
        let controller = makeController()
        let update = VT100TabStatusUpdate()
        update.expiresOn = .progressEnd
        update.expirationFallback = VT100TabStatusUpdate.clear
        controller.apply(update)

        XCTAssertFalse(status.hasActiveStatus)
        XCTAssertTrue(controller.hasArmedExpiration)
    }

    func testAssertsStatusDistinguishesBookkeepingFromAssertions() {
        XCTAssertFalse(bookkeeping(backgroundTasks: 1).assertsStatus)
        XCTAssertTrue(working(expiring: false).assertsStatus)
        XCTAssertTrue(VT100TabStatusUpdate.clear.assertsStatus)
    }

    // MARK: - Outstanding background work

    func testBackgroundWorkHoldsTheExpirationAndThenReleasesIt() {
        let controller = makeController()
        controller.apply(working(expiring: true, backgroundTasks: 2))
        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)
        settle()
        XCTAssertEqual(status.statusText, "working")

        // The program reports the last of it finished. No further wait: it
        // just spoke.
        controller.apply(bookkeeping(backgroundTasks: 0))
        XCTAssertEqual(status.statusText, "idle")
    }

    func testACountArrivingInsideTheHeadStartDoesNotCutItShort() {
        // Releasing a hold is not the same as skipping the wait. Until the
        // head start has elapsed, the pending timer is what decides, so a
        // count landing inside the window must not expire the status early.
        let controller = makeController(progressEndDelay: 3600)
        controller.apply(working(expiring: true))
        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)

        controller.apply(bookkeeping(backgroundTasks: 0))

        settle()
        XCTAssertEqual(status.statusText, "working")
        XCTAssertTrue(controller.hasArmedExpiration)
    }

    func testReassertingWhileHeldKeepsTheCountAbleToRelease() {
        // Two background tasks outstanding when the operation ends. The first
        // to finish makes the program restate its status with a fresh
        // expiration, which must inherit the ended operation: no stop is
        // coming for it, so the count reaching zero is the only thing left
        // that can release it.
        let controller = makeController()
        controller.apply(working(expiring: true, backgroundTasks: 2))
        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)
        settle()
        XCTAssertEqual(status.statusText, "working")

        controller.apply(working(expiring: true, backgroundTasks: 1))
        XCTAssertEqual(status.statusText, "working")

        controller.apply(bookkeeping(backgroundTasks: 0))
        XCTAssertEqual(status.statusText, "idle")
    }

    func testReassertingWhileHeldWithoutAnExpirationDisarms() {
        // The program's word still wins: restating the status without asking
        // for an expiration means it wants the status to stand.
        let controller = makeController()
        controller.apply(working(expiring: true, backgroundTasks: 2))
        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)
        settle()

        controller.apply(working(expiring: false, backgroundTasks: 1))
        controller.apply(bookkeeping(backgroundTasks: 0))
        XCTAssertEqual(status.statusText, "working")
        XCTAssertFalse(controller.hasArmedExpiration)
    }

    func testBookkeepingDoesNotReleaseAnExpirationArmedAfterTheOperationEnded() {
        // The regression: the operation-ended flag outlives the expiration it
        // was set for, so a count landing after the next turn started must not
        // be mistaken for that turn's end.
        let controller = makeController()
        controller.apply(working(expiring: true))
        expectStatus("idle") {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(.stopped)
        }

        // A new turn arms again, and its progress report has not arrived yet.
        controller.apply(working(expiring: true))
        controller.apply(bookkeeping(backgroundTasks: 0))

        settle()
        XCTAssertEqual(status.statusText, "working")
    }

    // MARK: - Lifecycle

    func testClearingSupersedesAPendingExpiration() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)

        XCTAssertTrue(controller.clearStatus())

        XCTAssertFalse(controller.hasArmedExpiration)
        settle()
        XCTAssertNil(status.statusText)
    }

    func testProgramExitDropsTheStatusAndAnyPendingExpiration() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        controller.progressProtocolDidReport(.indeterminate)
        controller.progressProtocolDidReport(.stopped)
        let publishedBefore = changes.count

        controller.programDidExit()
        XCTAssertNil(controller.statusIfPresent, "the dead program's status goes with it")
        XCTAssertFalse(controller.hasArmedExpiration)

        settle()
        XCTAssertEqual(changes.count, publishedBefore, "nothing published after the exit")
        XCTAssertNil(controller.statusIfPresent, "and no status conjured by a stale timer")
    }

    func testAfterProgramExitAStopCannotEndAnOperationThatNeverStarted() {
        let controller = makeController()
        controller.progressProtocolDidReport(.indeterminate)
        controller.programDidExit()

        // A fresh program's status, and a stop it never announced a start for.
        controller.apply(working(expiring: true))
        controller.progressProtocolDidReport(.stopped)

        settle()
        XCTAssertEqual(status.statusText, "working")
    }

    func testChangesArePublishedWithThePreviousText() {
        let controller = makeController()
        controller.apply(working(expiring: true))
        XCTAssertEqual(changes.count, 1)
        XCTAssertNil(changes[0])

        expectStatus("idle") {
            controller.progressProtocolDidReport(.indeterminate)
            controller.progressProtocolDidReport(.stopped)
        }
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[1], "working")
    }
}

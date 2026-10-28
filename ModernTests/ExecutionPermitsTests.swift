//
//  ExecutionPermitsTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class ExecutionPermitsTests: XCTestCase {
    // Stands in for a session's token executor. Records wakes instead of scheduling execution.
    private final class FakeSession {
        let name: String
        var paused = false
        var alive = true
        var wakes = 0
        // Runs when the session is woken.
        var onWake: (() -> Void)?
        var client: ExecutionPermits.Client!

        init(_ name: String, permits: ExecutionPermits, visible: Bool = false) {
            self.name = name
            client = permits.makeClient(isPaused: { [unowned self] in self.paused },
                                        wake: { [unowned self] in
                self.wakes += 1
                self.onWake?()
                return self.alive
            })
            permits.setVisible(client, visible)
        }
    }

    // MARK: - Capacity and handoff

    func testAcquireSucceedsUpToCapacityThenWaits() {
        let permits = ExecutionPermits(capacity: 2, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)

        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(c.client))
        XCTAssertEqual(permits.inUseForTesting, 2)
        XCTAssertEqual(permits.waitingCountForTesting, 1)
    }

    func testAcquireWhileHoldingSucceedsWithoutTakingAnotherPermit() {
        let permits = ExecutionPermits(capacity: 2, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertEqual(permits.inUseForTesting, 1)
    }

    func testWaitingTwiceDoesNotAddTheSessionTwice() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertEqual(permits.waitingCountForTesting, 1)
    }

    func testReleaseHandsThePermitToTheWaiterAndWakesIt() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertEqual(b.wakes, 0)

        permits.release(a.client, ran: 0.001, hasMoreWork: false)
        XCTAssertEqual(b.wakes, 1)
        XCTAssertEqual(permits.inUseForTesting, 1)
        // The permit was handed over, so b holds it when it runs.
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertEqual(permits.inUseForTesting, 1)
        XCTAssertEqual(permits.waitingCountForTesting, 0)
    }

    func testReleaseWithNoWaitersFreesThePermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        permits.release(a.client, ran: 0.001, hasMoreWork: false)
        XCTAssertEqual(permits.inUseForTesting, 0)
        XCTAssertEqual(a.wakes, 0)
    }

    // A session that gives up its permit with work left keeps it if nobody else is owed it. It
    // isn't woken: it carries on by itself.
    func testReleaseWithMoreWorkAndNoRivalsKeepsThePermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.release(a.client, ran: 0.005, hasMoreWork: true))
        XCTAssertEqual(a.wakes, 0)
        XCTAssertEqual(permits.inUseForTesting, 1)
        XCTAssertEqual(permits.waitingCountForTesting, 0)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertEqual(permits.virtualTimeForTesting(a.client), 0.005, accuracy: 1e-9)
    }

    // A session owed the permit gets it when the holder releases with work left, and the holder
    // waits.
    func testReleaseWithMoreWorkHandsThePermitToAWaiterAhead() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.release(a.client, ran: 0.005, hasMoreWork: true))
        XCTAssertEqual(b.wakes, 1)
        XCTAssertEqual(permits.waitingCountForTesting, 1)
    }

    // Waking a session schedules its execution, which can take a moment, so it happens after the
    // lock is released rather than holding up every other session.
    func testWakeIsCalledWithoutTheLockHeld() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        var lockWasFree = false
        b.onWake = {
            // Another thread takes the lock. It can only finish if the lock isn't held.
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = permits.inUseForTesting
                done.signal()
            }
            lockWasFree = done.wait(timeout: .now() + 10) == .success
        }
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.release(a.client, ran: 0.005, hasMoreWork: false)
        XCTAssertEqual(b.wakes, 1)
        XCTAssertTrue(lockWasFree)
    }

    func testHandoffGoesToTheWaiterWithTheLowestVirtualTime() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)

        // b runs for a second and waits again; then c starts waiting, behind b, having run nothing.
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.release(a.client, ran: 0, hasMoreWork: true)
        XCTAssertEqual(b.wakes, 1)
        XCTAssertTrue(permits.acquire(b.client))
        permits.release(b.client, ran: 1, hasMoreWork: true)
        XCTAssertEqual(a.wakes, 1)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(c.client))

        permits.release(a.client, ran: 0.5, hasMoreWork: false)
        XCTAssertEqual(c.wakes, 1)
        XCTAssertEqual(b.wakes, 1)
    }

    // Equal virtual times go first come, first served.
    func testTiesGoToTheEarliestWaiter() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(c.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.release(a.client, ran: 0, hasMoreWork: false)
        XCTAssertEqual(c.wakes, 1)
        XCTAssertEqual(b.wakes, 0)
    }

    // MARK: - Slices

    func testCheckpointWithNobodyWaitingDoesNotYield() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.checkpoint(a.client, ran: 0.005))
    }

    func testCheckpointYieldsToAWaiterThatIsNotAhead() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertTrue(permits.checkpoint(a.client, ran: 0.005))
    }

    func testCheckpointDoesNotYieldToAWaiterThatHasRunMore() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.release(a.client, ran: 0, hasMoreWork: true)
        XCTAssertTrue(permits.acquire(b.client))
        permits.release(b.client, ran: 1, hasMoreWork: true)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.checkpoint(a.client, ran: 0.005))
    }

    // MARK: - Fair sharing

    // Runs `sessions` (all always busy) for `slices` slices of `slice` seconds with the given number
    // of permits, the way token executors would, and returns how long each one ran.
    private func simulate(_ sessions: [FakeSession],
                          permits: ExecutionPermits,
                          slices: Int,
                          slice: TimeInterval = 0.005) -> [String: TimeInterval] {
        var ran = [String: TimeInterval]()
        var running = [FakeSession]()
        for session in sessions {
            if permits.acquire(session.client) {
                running.append(session)
            }
        }
        var wakesSeen = Dictionary(uniqueKeysWithValues: sessions.map { ($0.name, $0.wakes) })
        for i in 0..<slices {
            let session = running[i % running.count]
            ran[session.name, default: 0] += slice
            if permits.checkpoint(session.client, ran: slice) {
                running.removeAll { $0 === session }
                permits.release(session.client, ran: 0, hasMoreWork: true)
                for candidate in sessions where candidate.wakes != wakesSeen[candidate.name] {
                    wakesSeen[candidate.name] = candidate.wakes
                    XCTAssertTrue(permits.acquire(candidate.client))
                    running.append(candidate)
                }
            }
        }
        return ran
    }

    func testEqualWeightsShareEqually() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let sessions = (0..<3).map { FakeSession("s\($0)", permits: permits) }
        let ran = simulate(sessions, permits: permits, slices: 3000)
        for session in sessions {
            XCTAssertEqual(ran[session.name] ?? 0, 5, accuracy: 0.05, session.name)
        }
    }

    func testVisibleSessionGetsItsWeightTimesTheTimeOfABackgroundOne() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let visible = FakeSession("visible", permits: permits, visible: true)
        let background = (0..<2).map { FakeSession("bg\($0)", permits: permits) }
        let ran = simulate([visible] + background, permits: permits, slices: 6000)
        // 4 : 1 : 1 of 30 seconds.
        XCTAssertEqual(ran["visible"] ?? 0, 20, accuracy: 0.1)
        XCTAssertEqual(ran["bg0"] ?? 0, 5, accuracy: 0.1)
        XCTAssertEqual(ran["bg1"] ?? 0, 5, accuracy: 0.1)
    }

    func testBackgroundSessionIsNotStarvedByVisibleOnes() {
        let permits = ExecutionPermits(capacity: 2, visibleWeight: 4)
        let visible = (0..<3).map { FakeSession("v\($0)", permits: permits, visible: true) }
        let background = FakeSession("bg", permits: permits)
        let ran = simulate(visible + [background], permits: permits, slices: 1300)
        // Its share is 1 / 13 of the time.
        XCTAssertEqual(ran["bg"] ?? 0, 0.5, accuracy: 0.05)
    }

    func testVisibilitySetWhileHoldingAppliesFromTheNextAcquire() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        permits.setVisible(a.client, true)
        // Still charged at weight 1 for this hold.
        permits.release(a.client, ran: 0.004, hasMoreWork: false)
        XCTAssertEqual(permits.virtualTimeForTesting(a.client), 0.004, accuracy: 1e-9)

        // Now charged at weight 4.
        XCTAssertTrue(permits.acquire(a.client))
        permits.release(a.client, ran: 0.004, hasMoreWork: false)
        XCTAssertEqual(permits.virtualTimeForTesting(a.client), 0.005, accuracy: 1e-9)
    }

    // MARK: - Virtual time bookkeeping

    func testNewSessionStartsEvenWithTheSessionsThatAreRunning() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        permits.release(a.client, ran: 2, hasMoreWork: true)
        let b = FakeSession("b", permits: permits)
        XCTAssertEqual(permits.virtualTimeForTesting(b.client), 2, accuracy: 1e-9)
    }

    // A session that was idle while others ran can't take over to catch up.
    func testIdleSessionDoesNotBankCredit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let idle = FakeSession("idle", permits: permits)
        let busy = FakeSession("busy", permits: permits)
        XCTAssertTrue(permits.acquire(busy.client))
        XCTAssertTrue(permits.checkpoint(busy.client, ran: 10) == false)

        XCTAssertFalse(permits.acquire(idle.client))
        XCTAssertEqual(permits.virtualTimeForTesting(idle.client), 10, accuracy: 1e-9)
        let ran = simulate([busy, idle], permits: permits, slices: 400)
        XCTAssertEqual(ran["idle"] ?? 0, 1, accuracy: 0.02)
        XCTAssertEqual(ran["busy"] ?? 0, 1, accuracy: 0.02)
    }

    // An idle session sits at the floor, so the first tokens after a keystroke go to the front.
    func testSessionReturningFromIdleGetsTheNextTurn() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let busy = FakeSession("busy", permits: permits)
        let other = FakeSession("other", permits: permits)
        let typing = FakeSession("typing", permits: permits)
        XCTAssertTrue(permits.acquire(busy.client))
        XCTAssertFalse(permits.acquire(other.client))
        XCTAssertTrue(permits.checkpoint(busy.client, ran: 0.005))
        permits.release(busy.client, ran: 0, hasMoreWork: true)
        XCTAssertEqual(other.wakes, 1)
        XCTAssertTrue(permits.acquire(other.client))

        // busy has run 5 ms and waits. typing was idle, so it starts at the floor, ahead of busy.
        XCTAssertFalse(permits.acquire(typing.client))
        permits.release(other.client, ran: 0.006, hasMoreWork: true)
        XCTAssertEqual(typing.wakes, 1)
        XCTAssertEqual(busy.wakes, 0)
    }

    // Going idle doesn't reset a session that ran ahead of the others.
    func testGoingIdleDoesNotForgiveDebt() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.release(a.client, ran: 5, hasMoreWork: false)
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(a.client))
        XCTAssertEqual(permits.virtualTimeForTesting(a.client), 5, accuracy: 1e-9)
    }

    func testFloorNeverGoesDown() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        permits.release(a.client, ran: 3, hasMoreWork: false)
        // Nobody is runnable, so a new session starts where the last one left off, not at 0.
        let b = FakeSession("b", permits: permits)
        XCTAssertEqual(permits.virtualTimeForTesting(b.client), 3, accuracy: 1e-9)
        XCTAssertTrue(permits.acquire(b.client))
        permits.release(b.client, ran: 0, hasMoreWork: false)
        let c = FakeSession("c", permits: permits)
        XCTAssertEqual(permits.virtualTimeForTesting(c.client), 3, accuracy: 1e-9)
    }

    // MARK: - Paused sessions

    // A session paused for a join isn't handed a permit; it keeps its place for when it resumes.
    func testHandoffSkipsPausedWaitersWhoKeepTheirPlace() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(c.client))
        b.paused = true
        permits.release(a.client, ran: 0.005, hasMoreWork: false)
        XCTAssertEqual(b.wakes, 0)
        XCTAssertEqual(c.wakes, 1)
        XCTAssertEqual(permits.waitingCountForTesting, 1)

        b.paused = false
        XCTAssertTrue(permits.acquire(c.client))
        permits.release(c.client, ran: 0.005, hasMoreWork: true)
        XCTAssertEqual(b.wakes, 1)
    }

    func testPausedWaiterDoesNotMakeAHolderYield() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        b.paused = true
        XCTAssertFalse(permits.checkpoint(a.client, ran: 0.005))
    }

    // A waiter skipped while paused can take a free permit when it runs again.
    func testUnpausedWaiterTakesAFreePermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        b.paused = true
        permits.release(a.client, ran: 0.005, hasMoreWork: false)
        XCTAssertEqual(permits.inUseForTesting, 0)
        b.paused = false
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertEqual(permits.waitingCountForTesting, 0)
    }

    // A permit left free while the only waiter was paused goes to that waiter once it can run,
    // not to a session that asks for one later.
    func testNewcomerDoesNotTakeAFreePermitFromAWaiterAheadOfIt() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        b.paused = true
        permits.release(a.client, ran: 0.005, hasMoreWork: false)
        XCTAssertEqual(permits.inUseForTesting, 0)
        b.paused = false

        XCTAssertFalse(permits.acquire(c.client))
        XCTAssertEqual(b.wakes, 1)
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertEqual(permits.waitingCountForTesting, 1)
    }

    // A waiter asking again takes a free permit only if no waiter that can run is ahead of it.
    func testWaiterDoesNotTakeAFreePermitFromAWaiterAheadOfIt() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(c.client))
        b.paused = true
        c.paused = true
        permits.release(a.client, ran: 0.005, hasMoreWork: false)
        XCTAssertEqual(permits.inUseForTesting, 0)
        b.paused = false
        c.paused = false

        XCTAssertFalse(permits.acquire(c.client))
        XCTAssertEqual(b.wakes, 1)
        XCTAssertEqual(c.wakes, 0)
    }

    // MARK: - Idle holders

    // A holder with nothing to do keeps its permit, idle, so its next tokens don't need the lock.
    func testParkingWithNobodyWaitingKeepsThePermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.park(a.client, uncharged: 0.001))
        XCTAssertEqual(permits.inUseForTesting, 1)
        XCTAssertEqual(permits.idleHolderCountForTesting, 1)
        XCTAssertTrue(permits.resume(a.client))
        XCTAssertEqual(permits.idleHolderCountForTesting, 0)
    }

    // A holder that parks while someone waits gives the permit to the waiter instead.
    func testParkingWithAWaiterHandsThePermitOn() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.park(a.client, uncharged: 0.002))
        XCTAssertEqual(b.wakes, 1)
        XCTAssertEqual(permits.virtualTimeForTesting(a.client), 0.002, accuracy: 1e-9)
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(a.client))
    }

    // A session that needs a permit when none is free takes one from an idle holder, which is
    // charged for the time it ran and has to ask again.
    func testIdlePermitIsTakenBySomeoneWhoNeedsIt() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.park(a.client, uncharged: 0.003))
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertEqual(permits.inUseForTesting, 1)
        XCTAssertEqual(permits.idleHolderCountForTesting, 0)
        XCTAssertEqual(permits.virtualTimeForTesting(a.client), 0.003, accuracy: 1e-9)

        XCTAssertFalse(permits.resume(a.client))
        XCTAssertFalse(permits.acquire(a.client))
        XCTAssertEqual(permits.waitingCountForTesting, 1)
    }

    // A waiter that is paused can't use a permit, so a holder that runs out of tokens keeps its
    // permit idle. The waiter takes it once it can run.
    func testParkingWithOnlyAPausedWaiterKeepsThePermitIdle() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        b.paused = true
        XCTAssertTrue(permits.park(a.client, uncharged: 0))
        XCTAssertEqual(permits.idleHolderCountForTesting, 1)
        b.paused = false
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertFalse(permits.resume(a.client))
    }

    // A holder that runs out of tokens while a waiter that can run is in line gives the permit up,
    // even if a paused waiter is ahead of it.
    func testParkingWithARunnableWaiterBehindAPausedOneHandsThePermitOn() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(c.client))
        b.paused = true
        XCTAssertFalse(permits.park(a.client, uncharged: 0))
        XCTAssertEqual(c.wakes, 1)
        XCTAssertEqual(b.wakes, 0)
    }

    // Idle holders don't hold the floor down: they aren't running.
    func testIdleHolderDoesNotHoldTheFloorDown() {
        let permits = ExecutionPermits(capacity: 2, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertTrue(permits.park(a.client, uncharged: 0))
        XCTAssertFalse(permits.checkpoint(b.client, ran: 3))
        let c = FakeSession("c", permits: permits)
        XCTAssertEqual(permits.virtualTimeForTesting(c.client), 3, accuracy: 1e-9)
    }

    // A holder that resumes after being idle can't use the time it sat idle as credit: it is
    // raised to the floor when next charged.
    func testResumedHolderDoesNotBankCredit() {
        let permits = ExecutionPermits(capacity: 2, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertTrue(permits.park(a.client, uncharged: 0))
        XCTAssertFalse(permits.checkpoint(b.client, ran: 3))
        XCTAssertTrue(permits.resume(a.client))
        XCTAssertFalse(permits.checkpoint(a.client, ran: 0.001))
        XCTAssertEqual(permits.virtualTimeForTesting(a.client), 3.001, accuracy: 1e-9)
    }

    // Lowering the cap takes permits back from idle holders right away.
    func testLoweringTheCapTakesBackIdlePermits() {
        let permits = ExecutionPermits(capacity: 2, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertTrue(permits.park(a.client, uncharged: 0))
        permits.capacity = 1
        XCTAssertEqual(permits.inUseForTesting, 1)
        XCTAssertFalse(permits.resume(a.client))
    }

    // After the cap is lowered below the permits in use, a session that needs a permit takes idle
    // ones until fewer than the cap are in use, and waits if that isn't enough.
    func testNeedingAPermitAfterTheCapIsLoweredTakesIdlePermitsUntilUnderTheCap() {
        let permits = ExecutionPermits(capacity: 3, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        let d = FakeSession("d", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertTrue(permits.acquire(c.client))
        permits.capacity = 2
        XCTAssertTrue(permits.park(a.client, uncharged: 0))
        XCTAssertFalse(permits.acquire(d.client))
        XCTAssertEqual(permits.inUseForTesting, 2)
        XCTAssertFalse(permits.resume(a.client))

        // b runs out of tokens with d in line, so it gives its permit up, leaving fewer in use
        // than the cap. d gets it.
        XCTAssertFalse(permits.park(b.client, uncharged: 0))
        XCTAssertEqual(d.wakes, 1)
        XCTAssertTrue(permits.acquire(d.client))
        XCTAssertEqual(permits.inUseForTesting, 2)
    }

    // After the cap is lowered, a checkpoint takes idle permits back before deciding whether the
    // running holder is over the cap, so it doesn't stop for nothing.
    func testCheckpointTakesIdlePermitsBeforeYieldingForTheCap() {
        let permits = ExecutionPermits(capacity: 3, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertTrue(permits.acquire(c.client))
        permits.capacity = 2
        XCTAssertTrue(permits.park(c.client, uncharged: 0))
        XCTAssertFalse(permits.checkpoint(a.client, ran: 0.005))
        XCTAssertEqual(permits.inUseForTesting, 2)
        XCTAssertFalse(permits.resume(c.client))
    }

    // Removing an idle holder frees its permit.
    func testRemovingAnIdleHolderFreesItsPermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.park(a.client, uncharged: 0))
        permits.remove(a.client)
        XCTAssertEqual(permits.inUseForTesting, 0)
        XCTAssertEqual(permits.idleHolderCountForTesting, 0)
    }

    // MARK: - Closing

    func testRemovingAHolderHandsItsPermitOn() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.remove(a.client)
        XCTAssertEqual(b.wakes, 1)
        XCTAssertEqual(permits.inUseForTesting, 1)
    }

    func testRemovingAWaiterTakesItOutOfLine() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.remove(b.client)
        XCTAssertEqual(permits.waitingCountForTesting, 0)
        permits.release(a.client, ran: 0, hasMoreWork: false)
        XCTAssertEqual(b.wakes, 0)
        XCTAssertEqual(permits.inUseForTesting, 0)
    }

    func testRemovingTwiceIsHarmless() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        permits.remove(a.client)
        permits.remove(a.client)
        XCTAssertEqual(permits.inUseForTesting, 0)
    }

    // A session whose executor is gone can't use a permit, so it goes to the next waiter.
    func testWaiterThatIsGoneIsDroppedAndThePermitGoesOn() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(c.client))
        b.alive = false
        permits.release(a.client, ran: 0, hasMoreWork: false)
        XCTAssertEqual(b.wakes, 1)
        XCTAssertEqual(c.wakes, 1)
        XCTAssertEqual(permits.inUseForTesting, 1)
        XCTAssertEqual(permits.waitingCountForTesting, 0)
    }

    // MARK: - Relinquishing

    // A session that won't execute tokens gives up a permit it holds, including one handed to it
    // that it never took up.
    func testRelinquishingAHeldPermitHandsItOn() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(c.client))
        permits.release(a.client, ran: 0, hasMoreWork: false)
        XCTAssertEqual(b.wakes, 1)

        // b was handed the permit but won't use it.
        permits.relinquish(b.client, ran: 0)
        XCTAssertEqual(c.wakes, 1)
        XCTAssertEqual(permits.inUseForTesting, 1)
        XCTAssertEqual(permits.waitingCountForTesting, 0)
    }

    func testRelinquishingWhileWaitingLeavesTheLine() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.relinquish(b.client, ran: 0)
        XCTAssertEqual(permits.waitingCountForTesting, 0)
        // Nobody is owed the permit, so a keeps it at a checkpoint.
        XCTAssertFalse(permits.checkpoint(a.client, ran: 0.005))
        permits.release(a.client, ran: 0, hasMoreWork: false)
        XCTAssertEqual(b.wakes, 0)
    }

    func testRelinquishingWhenIdleDoesNothing() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        permits.relinquish(a.client, ran: 0)
        XCTAssertEqual(permits.inUseForTesting, 0)
        XCTAssertTrue(permits.acquire(a.client))
    }

    // A session that relinquished goes idle, so it can't keep a stale place in line while others
    // run; it rejoins at the floor.
    func testRelinquishedSessionRejoinsAtTheFloor() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        permits.relinquish(b.client, ran: 0)
        XCTAssertFalse(permits.checkpoint(a.client, ran: 2))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertEqual(permits.virtualTimeForTesting(b.client), 2, accuracy: 1e-9)
    }

    // MARK: - Changing the cap

    func testRaisingTheCapHandsOutPermitsToWaiters() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertFalse(permits.acquire(b.client))
        XCTAssertFalse(permits.acquire(c.client))
        permits.capacity = 3
        XCTAssertEqual(b.wakes, 1)
        XCTAssertEqual(c.wakes, 1)
        XCTAssertEqual(permits.inUseForTesting, 3)
    }

    func testLoweringTheCapMakesHoldersYieldAndHandsNothingOutUntilUnderIt() {
        let permits = ExecutionPermits(capacity: 3, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        let b = FakeSession("b", permits: permits)
        let c = FakeSession("c", permits: permits)
        let d = FakeSession("d", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        XCTAssertTrue(permits.acquire(b.client))
        XCTAssertTrue(permits.acquire(c.client))
        permits.capacity = 1

        // Over the cap, holders yield at their next checkpoint even with nobody waiting.
        XCTAssertTrue(permits.checkpoint(a.client, ran: 0.005))
        XCTAssertFalse(permits.acquire(d.client))
        permits.release(a.client, ran: 0, hasMoreWork: false)
        permits.release(b.client, ran: 0, hasMoreWork: false)
        XCTAssertEqual(d.wakes, 0)
        permits.release(c.client, ran: 0, hasMoreWork: false)
        XCTAssertEqual(d.wakes, 1)
        XCTAssertEqual(permits.inUseForTesting, 1)
    }

    func testCapIsAtLeastOne() {
        let permits = ExecutionPermits(capacity: 0, visibleWeight: 4)
        let a = FakeSession("a", permits: permits)
        XCTAssertTrue(permits.acquire(a.client))
        permits.capacity = -3
        XCTAssertEqual(permits.capacity, 1)
    }

    // MARK: - Setting

    func testConfiguredCapIsNeverBelowTwo() {
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 1, cores: 16), 2)
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: -5, cores: 16), 2)
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 6, cores: 16), 6)
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 64, cores: 16), 16)
    }

    func testAutomaticCapDependsOnCores() {
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 0, cores: 1), 2)
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 0, cores: 4), 2)
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 0, cores: 8), 2)
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 0, cores: 12), 3)
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 0, cores: 16), 4)
        XCTAssertEqual(ExecutionPermits.resolvedCapacity(configured: 0, cores: 32), 4)
    }

    // The value the setting's control shows and stores: any number is clamped, and 0 isn't
    // automatic here.
    func testClampedCapacity() {
        XCTAssertEqual(ExecutionPermits.clampedCapacity(0, cores: 8), ExecutionPermits.minimumCapacity)
        XCTAssertEqual(ExecutionPermits.clampedCapacity(5, cores: 8), 5)
        XCTAssertEqual(ExecutionPermits.clampedCapacity(12, cores: 8), 8)
    }

    // MARK: - Concurrency

    // Sessions on many threads take and give back permits. No more than the cap ever hold one at
    // once, and every waiter eventually gets one.
    func testNeverMoreHoldersThanTheCap() {
        let capacity = 3
        let permits = ExecutionPermits(capacity: capacity, visibleWeight: 4)
        let count = 24
        let rounds = 200
        let active = iTermAtomicInt64Create()
        let highWater = MutableAtomicObject<Int64>(0)
        defer { iTermAtomicInt64Free(active) }

        final class Session {
            let woken = DispatchSemaphore(value: 0)
            var client: ExecutionPermits.Client!
        }
        let sessions = (0..<count).map { _ in Session() }
        for session in sessions {
            session.client = permits.makeClient(isPaused: { false }, wake: { [session] in
                session.woken.signal()
                return true
            })
        }
        let timedOut = MutableAtomicObject(false)
        DispatchQueue.concurrentPerform(iterations: count) { i in
            let session = sessions[i]
            for round in 0..<rounds {
                if !permits.acquire(session.client) {
                    if session.woken.wait(timeout: .now() + 30) == .timedOut {
                        timedOut.set(true)
                        return
                    }
                    if !permits.acquire(session.client) {
                        timedOut.set(true)
                        return
                    }
                }
                let now = iTermAtomicInt64Add(active, 1)
                highWater.mutableAccess { $0 = max($0, now) }
                iTermAtomicInt64Add(active, -1)
                let keeps = permits.release(session.client, ran: 0.001, hasMoreWork: round + 1 < rounds)
                if round + 1 < rounds && !keeps {
                    // Released with more work and someone else was owed the permit, so it is
                    // woken when its turn comes.
                    if session.woken.wait(timeout: .now() + 30) == .timedOut {
                        timedOut.set(true)
                        return
                    }
                }
            }
        }
        XCTAssertFalse(timedOut.value)
        XCTAssertLessThanOrEqual(highWater.value, Int64(capacity))
        XCTAssertEqual(permits.inUseForTesting, 0)
        XCTAssertEqual(permits.waitingCountForTesting, 0)
    }

    // Sessions on many threads run, go idle holding their permits, and resume, while others take
    // idle permits away. No more than the cap ever run at once, and nobody is left waiting.
    func testParkingNeverStrandsAWaiterOrExceedsTheCap() {
        let capacity = 3
        let permits = ExecutionPermits(capacity: capacity, visibleWeight: 4)
        let count = 24
        let rounds = 300
        let active = iTermAtomicInt64Create()
        let highWater = MutableAtomicObject<Int64>(0)
        defer { iTermAtomicInt64Free(active) }

        final class Session {
            let woken = DispatchSemaphore(value: 0)
            var client: ExecutionPermits.Client!
        }
        let sessions = (0..<count).map { _ in Session() }
        for session in sessions {
            session.client = permits.makeClient(isPaused: { false }, wake: { [session] in
                session.woken.signal()
                return true
            })
        }
        let timedOut = MutableAtomicObject(false)
        DispatchQueue.concurrentPerform(iterations: count) { i in
            let session = sessions[i]
            var holding = false
            for _ in 0..<rounds {
                if !(holding && permits.resume(session.client)) {
                    if !permits.acquire(session.client) {
                        if session.woken.wait(timeout: .now() + 30) == .timedOut {
                            timedOut.set(true)
                            return
                        }
                        if !permits.acquire(session.client) {
                            timedOut.set(true)
                            return
                        }
                    }
                }
                let now = iTermAtomicInt64Add(active, 1)
                highWater.mutableAccess { $0 = max($0, now) }
                // Stay running for a little while, so sessions running at once overlap here.
                for _ in 0..<1000 {
                    highWater.mutableAccess { $0 = max($0, iTermAtomicInt64Get(active)) }
                }
                iTermAtomicInt64Add(active, -1)
                holding = permits.park(session.client, uncharged: 0.001)
            }
            if holding && permits.resume(session.client) {
                permits.relinquish(session.client, ran: 0)
            }
        }
        XCTAssertFalse(timedOut.value)
        XCTAssertLessThanOrEqual(highWater.value, Int64(capacity))
        XCTAssertEqual(permits.inUseForTesting, 0)
        XCTAssertEqual(permits.waitingCountForTesting, 0)
    }
}

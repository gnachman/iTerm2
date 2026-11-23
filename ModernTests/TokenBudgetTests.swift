//
//  TokenBudgetTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class TokenBudgetTests: XCTestCase {
    // Handlers run here. Calling sync on it waits for every handler dispatched so far.
    private let handlerQueue = DispatchQueue(label: "TokenBudgetTests.handlers")

    // Counts handler calls. Read it only after draining handlerQueue.
    private final class Counter {
        var value = 0
    }

    private func drainHandlers() {
        handlerQueue.sync {}
    }

    func testTryAcquireFailsWhenFull() {
        let budget = TokenBudget(capacity: 2)
        XCTAssertTrue(budget.hasCapacity)
        XCTAssertTrue(budget.tryAcquire())
        XCTAssertTrue(budget.tryAcquire())
        XCTAssertFalse(budget.hasCapacity)
        XCTAssertFalse(budget.tryAcquire())

        budget.release()
        XCTAssertTrue(budget.hasCapacity)
        XCTAssertTrue(budget.tryAcquire())
    }

    func testNonPositiveCapacityStillAllowsOne() {
        let budget = TokenBudget(capacity: 0)
        XCTAssertTrue(budget.tryAcquire())
        XCTAssertFalse(budget.tryAcquire())
    }

    // The handler fires as soon as a slot frees up, as a reader blocked in acquire() would wake.
    // Waiting for more room would make the reader stop for long stretches; a tmux gateway that
    // stops reading that long lets tmux queue a large backlog ahead of anything typed.
    func testHandlerFiresAsSoonAsASlotFrees() {
        let budget = TokenBudget(capacity: 4)
        for _ in 0..<4 {
            XCTAssertTrue(budget.tryAcquire())
        }
        let calls = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) { calls.value += 1 }
        drainHandlers()
        XCTAssertEqual(calls.value, 0)

        budget.release()  // 3 in use
        drainHandlers()
        XCTAssertEqual(calls.value, 1)
    }

    func testHandlerFiresOnlyOnce() {
        let budget = TokenBudget(capacity: 2)
        XCTAssertTrue(budget.tryAcquire())
        XCTAssertTrue(budget.tryAcquire())
        let calls = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) { calls.value += 1 }
        budget.release()
        budget.release()
        XCTAssertTrue(budget.tryAcquire())
        budget.release()
        drainHandlers()
        XCTAssertEqual(calls.value, 1)
    }

    // Registering after the budget has already drained must not lose the wakeup.
    func testHandlerFiresWhenAlreadyBelowWatermark() {
        let budget = TokenBudget(capacity: 4)
        XCTAssertTrue(budget.tryAcquire())
        let calls = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) { calls.value += 1 }
        drainHandlers()
        XCTAssertEqual(calls.value, 1)
    }

    // A handler may be registered again once the previous one has fired.
    func testHandlerCanBeRegisteredAgainAfterFiring() {
        let budget = TokenBudget(capacity: 2)
        let calls = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) { calls.value += 1 }
        drainHandlers()
        XCTAssertTrue(budget.tryAcquire())
        XCTAssertTrue(budget.tryAcquire())
        budget.notifyWhenCapacityAvailable(on: handlerQueue) { calls.value += 1 }
        budget.release()
        drainHandlers()
        XCTAssertEqual(calls.value, 2)
    }

    // A reader that stopped (for example, a session's previous task) can leave a handler pending.
    // Registering a new one replaces it and wakes the old one, so neither waiter is stranded.
    func testRegisteringAgainWakesThePreviousHandler() {
        let budget = TokenBudget(capacity: 2)
        XCTAssertTrue(budget.tryAcquire())
        XCTAssertTrue(budget.tryAcquire())
        let first = Counter()
        let second = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) { first.value += 1 }
        budget.notifyWhenCapacityAvailable(on: handlerQueue) { second.value += 1 }
        drainHandlers()
        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(second.value, 0)

        budget.release()
        drainHandlers()
        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(second.value, 1)
    }

    // The handler is never called inline: releases happen while the executor holds locks.
    func testHandlerIsNotCalledInline() {
        let budget = TokenBudget(capacity: 2)
        XCTAssertTrue(budget.tryAcquire())
        XCTAssertTrue(budget.tryAcquire())
        let calls = Counter()
        handlerQueue.sync {
            budget.notifyWhenCapacityAvailable(on: handlerQueue) { calls.value += 1 }
            budget.release()
            XCTAssertEqual(calls.value, 0)
        }
        drainHandlers()
        XCTAssertEqual(calls.value, 1)
    }

    // A handler that registered just as the last slot was released fires exactly once.
    //
    // This is a stress test of the budget's lock under real concurrency, not a deterministic race
    // test: which order a round takes is left to the scheduler, and in measurements all but at
    // most one round of 2000 took the same order, so a lost wakeup in another order is caught
    // only by chance. Both orders are covered deterministically by
    // testHandlerFiresAsSoonAsASlotFrees and testHandlerFiresWhenAlreadyBelowWatermark.
    //
    // Each round races one registration against two releases made on another thread. The
    // releases run on a thread of the test's own, not on a dispatch queue: a round used to block
    // a concurrentPerform worker on work sent to the global queue, which deadlocks once the
    // process has used up its dispatch threads, as a long test host had on 2026-11-22
    // (docs/swift-migration/bugs.md, "Dispatch threads pile up in a long-running test host").
    // Each round has its own budget, so running rounds at once raced nothing more.
    func testConcurrentRegisterAndReleaseNeverLosesOrDuplicatesAWakeup() {
        let iterations = 2000
        let calls = Counter()
        let releaser = RoundThread()
        defer { releaser.finish() }
        for _ in 0..<iterations {
            let budget = TokenBudget(capacity: 2)
            XCTAssertTrue(budget.tryAcquire())
            XCTAssertTrue(budget.tryAcquire())
            releaser.start {
                budget.release()
                budget.release()
            }
            budget.notifyWhenCapacityAvailable(on: handlerQueue) { calls.value += 1 }
            guard releaser.waitForRound() else {
                XCTFail("The releasing thread did not finish its round")
                return
            }
        }
        drainHandlers()
        XCTAssertEqual(calls.value, iterations)
    }

    // A thread that runs one block per round: start() hands it the block, waitForRound() waits
    // for it to finish. finish() ends the thread.
    private final class RoundThread {
        private let go = DispatchSemaphore(value: 0)
        private let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var block: (() -> Void)?
        private var finished = false

        init() {
            // The thread holds the object until finish() ends it.
            let thread = Thread { [self] in
                while true {
                    go.wait()
                    lock.lock()
                    let work = block
                    block = nil
                    let stop = finished
                    lock.unlock()
                    if stop {
                        done.signal()
                        return
                    }
                    work?()
                    done.signal()
                }
            }
            thread.name = "TokenBudgetTests releaser"
            // The test's thread is user-interactive and waits on a semaphore this thread signals;
            // semaphores donate no priority, so at a lower class each round waited for the
            // scheduler (6.1 and 1.3 seconds a run in the test host instead of 0.03).
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        func start(_ work: @escaping () -> Void) {
            lock.lock()
            block = work
            lock.unlock()
            go.signal()
        }

        func waitForRound() -> Bool {
            return done.wait(timeout: .now() + 30) == .success
        }

        func finish() {
            lock.lock()
            finished = true
            lock.unlock()
            go.signal()
            _ = done.wait(timeout: .now() + 30)
        }
    }

    // The legacy path blocks in acquire() until a slot is released.
    func testAcquireWaitsForRelease() {
        let budget = TokenBudget(capacity: 1)
        budget.acquire()
        let started = expectation(description: "started")
        let acquired = expectation(description: "acquired")
        DispatchQueue.global().async {
            started.fulfill()
            budget.acquire()
            acquired.fulfill()
        }
        wait(for: [started], timeout: 30)
        // The slot is still held, so the other thread can't have gotten past acquire().
        XCTAssertFalse(budget.tryAcquire())
        budget.release()
        wait(for: [acquired], timeout: 30)
        XCTAssertFalse(budget.hasCapacity)
    }

    // Every path that finishes a TokenArray releases its slot exactly once. Releasing twice would
    // assert, and never releasing would leave the budget full.
    func testTokenArrayReleasesItsSlotExactlyOnce() {
        let budget = TokenBudget(capacity: 1)

        func makeTokenArray() -> TokenArray {
            // tryAcquire so a missed release fails the test instead of hanging it.
            XCTAssertTrue(budget.tryAcquire())
            var vector = CVector()
            CVectorCreate(&vector, 2)
            for _ in 0..<2 {
                let token = VT100Token()
                token.type = VT100CSI_SET_MODIFIERS
                CVectorAppendVT100Token(&vector, token)
            }
            return TokenArray(vector, lengthTotal: 2, lengthExcludingInBandSignaling: 2, budget: budget)
        }

        // next() to the end, then didFinish, then cleanup.
        do {
            let array = makeTokenArray()
            XCTAssertNotNil(array.next())
            XCTAssertFalse(budget.hasCapacity)
            XCTAssertNotNil(array.next())
            XCTAssertTrue(budget.hasCapacity)
            array.didFinish()
            array.cleanup(asyncFree: false)
            XCTAssertTrue(budget.hasCapacity)
        }
        // consume() past the end, as a coalesced group does, then didFinish, then cleanup.
        do {
            let array = makeTokenArray()
            XCTAssertTrue(array.consume())
            XCTAssertFalse(array.consume())
            XCTAssertFalse(array.consume())
            array.didFinish()
            array.cleanup(asyncFree: false)
            XCTAssertTrue(budget.hasCapacity)
        }
        // Discarded without being executed.
        do {
            let array = makeTokenArray()
            array.cleanup(asyncFree: false)
            XCTAssertTrue(budget.hasCapacity)
            array.didFinish()
        }
        XCTAssertTrue(budget.tryAcquire())
        XCTAssertFalse(budget.tryAcquire())
    }
}

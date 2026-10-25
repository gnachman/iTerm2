//
//  ByteBudgetTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class ByteBudgetTests: XCTestCase {
    // Handlers run here. Calling sync on it waits for every handler dispatched so far.
    private let handlerQueue = DispatchQueue(label: "ByteBudgetTests.handlers")

    private final class Counter {
        var value = 0
    }

    private func drainHandlers() {
        handlerQueue.sync {}
    }

    func testTakingCanExceedCapacity() {
        let budget = ByteBudget(capacity: 10)
        XCTAssertTrue(budget.hasCapacity)
        budget.take(9)
        XCTAssertTrue(budget.hasCapacity)
        // Whoever produces the bytes can't wait, so taking never fails.
        budget.take(5)
        XCTAssertFalse(budget.hasCapacity)
        XCTAssertEqual(budget.inUse, 14)

        budget.give(4)
        XCTAssertFalse(budget.hasCapacity)
        budget.give(1)
        XCTAssertTrue(budget.hasCapacity)
    }

    func testHandlerRunsAtLowWatermark() {
        let budget = ByteBudget(capacity: 10)
        budget.take(12)
        let counter = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) {
            counter.value += 1
        }
        drainHandlers()
        XCTAssertEqual(counter.value, 0)

        // Below capacity but above the low watermark (half the capacity).
        budget.give(6)
        drainHandlers()
        XCTAssertEqual(counter.value, 0)

        budget.give(1)
        drainHandlers()
        XCTAssertEqual(counter.value, 1)

        // It runs once.
        budget.give(5)
        drainHandlers()
        XCTAssertEqual(counter.value, 1)
    }

    func testHandlerRunsRightAwayWhenThereIsRoom() {
        let budget = ByteBudget(capacity: 10)
        let counter = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) {
            counter.value += 1
        }
        drainHandlers()
        XCTAssertEqual(counter.value, 1)
    }

    // A reader that stopped can leave a handler behind. The next one runs it so it isn't stranded.
    func testRegisteringAnotherHandlerRunsThePendingOne() {
        let budget = ByteBudget(capacity: 10)
        budget.take(10)
        let first = Counter()
        let second = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) {
            first.value += 1
        }
        budget.notifyWhenCapacityAvailable(on: handlerQueue) {
            second.value += 1
        }
        drainHandlers()
        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(second.value, 0)

        budget.give(10)
        drainHandlers()
        XCTAssertEqual(second.value, 1)
    }

    // When something other than usage decides whether the reader may read (a gateway leaving tmux
    // mode), a waiting reader must be woken to check again.
    func testWakeRunsThePendingHandler() {
        let budget = ByteBudget(capacity: 10)
        budget.take(20)
        let counter = Counter()
        budget.notifyWhenCapacityAvailable(on: handlerQueue) {
            counter.value += 1
        }
        budget.wake()
        drainHandlers()
        XCTAssertEqual(counter.value, 1)

        // Nothing is pending now.
        budget.wake()
        drainHandlers()
        XCTAssertEqual(counter.value, 1)
    }

    // Giving back happens with locks held, so the handler must not run inline.
    func testHandlerIsNotRunInline() {
        let budget = ByteBudget(capacity: 10)
        budget.take(10)
        let blocked = DispatchQueue(label: "ByteBudgetTests.blocked")
        let gate = DispatchSemaphore(value: 0)
        blocked.async {
            gate.wait()
        }
        let counter = Counter()
        budget.notifyWhenCapacityAvailable(on: blocked) {
            counter.value += 1
        }
        budget.give(10)
        XCTAssertEqual(counter.value, 0)
        gate.signal()
        blocked.sync {}
        XCTAssertEqual(counter.value, 1)
    }
}

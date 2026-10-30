//
//  TaskReadCapacityTests.swift
//  iTerm2
//
//  A session's task stops reading while its token executor is full, and a tmux gateway also while
//  its panes' unread output is over budget.
//

import XCTest
@testable import iTerm2SharedARC

final class TaskReadCapacityTests: XCTestCase {
    // Stands in for the token executor's budget.
    private final class FakeTokens {
        private let mutex = Mutex()
        private var _hasRoom = true
        private var waiting = [(DispatchQueue, () -> Void)]()

        var hasRoom: Bool {
            get { mutex.sync { _hasRoom } }
            set { mutex.sync { _hasRoom = newValue } }
        }

        var waitingCount: Int {
            return mutex.sync { waiting.count }
        }

        func notifyWhenRoom(on queue: DispatchQueue, _ block: @escaping () -> Void) {
            mutex.sync { waiting.append((queue, block)) }
        }

        func free() {
            let handlers = mutex.sync {
                _hasRoom = true
                defer { waiting.removeAll() }
                return waiting
            }
            for (queue, block) in handlers {
                queue.async(execute: block)
            }
        }
    }

    private let tokens = FakeTokens()
    private let budget = ByteBudget(capacity: 4)
    private let gatewayLock = Mutex()
    private var _isGateway = true
    private var isGateway: Bool {
        get { gatewayLock.sync { _isGateway } }
        set { gatewayLock.sync { _isGateway = newValue } }
    }
    private let queue = DispatchQueue(label: "TaskReadCapacityTests")

    private lazy var capacity = TaskReadCapacity(
        tokenHasCapacity: { [tokens] in tokens.hasRoom },
        notifyWhenTokenCapacityAvailable: { [tokens] queue, block in tokens.notifyWhenRoom(on: queue, block) },
        gatewayBudget: { [unowned self] in self.isGateway ? self.budget : nil })

    override func tearDown() {
        budget.give(budget.inUse)
        super.tearDown()
    }

    private func notified() -> XCTestExpectation {
        let expectation = expectation(description: "Notified")
        capacity.notifyWhenCapacityAvailable(on: queue) {
            expectation.fulfill()
        }
        return expectation
    }

    // Drains `queue`, so anything it was asked to run has run.
    private func flush() {
        queue.sync {}
    }

    func testReadsWhenNothingIsFull() {
        XCTAssertTrue(capacity.hasCapacity)
    }

    func testAFullTokenExecutorStopsReading() {
        tokens.hasRoom = false
        XCTAssertFalse(capacity.hasCapacity)
    }

    func testAGatewayStopsReadingWhileItsPanesAreOverBudget() {
        budget.take(10)
        XCTAssertFalse(capacity.hasCapacity)
    }

    func testTheBudgetDoesNotLimitASessionThatIsNotAGateway() {
        isGateway = false
        budget.take(10)
        XCTAssertTrue(capacity.hasCapacity)
    }

    // With the token executor full, it waits for the executor, not for the budget.
    func testWaitsForTheTokenExecutorWhenItIsFull() {
        tokens.hasRoom = false
        budget.take(10)
        let expectation = notified()
        XCTAssertEqual(tokens.waitingCount, 1)
        budget.give(10)
        flush()
        tokens.free()
        wait(for: [expectation], timeout: 10)
    }

    func testWaitsForTheBudgetWhenOnlyItIsFull() {
        budget.take(10)
        let expectation = notified()
        XCTAssertEqual(tokens.waitingCount, 0)
        budget.give(10)
        wait(for: [expectation], timeout: 10)
    }

    // The token executor was full when the caller checked, but it has drained since. Waiting for
    // the budget would wait for its low watermark, which reading doesn't need.
    func testNotifiesRightAwayWhenTheTokenExecutorDrainedSinceTheCheck() {
        let expectation = notified()
        XCTAssertEqual(tokens.waitingCount, 0)
        wait(for: [expectation], timeout: 10)
    }

    // Both are full: the caller waits for the executor, checks again, and then waits for the
    // budget.
    func testWaitsForEachInTurnWhenBothAreFull() {
        tokens.hasRoom = false
        budget.take(10)
        let first = notified()
        tokens.free()
        wait(for: [first], timeout: 10)
        XCTAssertFalse(capacity.hasCapacity)
        let second = notified()
        XCTAssertEqual(tokens.waitingCount, 0)
        budget.give(10)
        wait(for: [second], timeout: 10)
        XCTAssertTrue(capacity.hasCapacity)
    }

    // Leaving gateway mode wakes the budget, but that wake can come after the caller checked and
    // before its block was registered. Then the block must still run.
    func testLeavingGatewayModeAfterTheCheckStillNotifies() {
        budget.take(10)
        var calls = 0
        let gatewayModeEndsDuringTheCall = TaskReadCapacity(
            tokenHasCapacity: { true },
            notifyWhenTokenCapacityAvailable: { _, _ in XCTFail("Waited for tokens") },
            gatewayBudget: { [budget] in
                calls += 1
                return calls == 1 ? budget : nil
            })
        let expectation = expectation(description: "Notified")
        gatewayModeEndsDuringTheCall.notifyWhenCapacityAvailable(on: queue) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
        XCTAssertTrue(gatewayModeEndsDuringTheCall.hasCapacity)
    }
}

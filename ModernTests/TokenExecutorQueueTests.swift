//
//  TokenExecutorQueueTests.swift
//  iTerm2
//
//  With per-session mutation queues, each executor must recognize only its own queue as the place
//  where it may run tasks synchronously.
//

import XCTest
@testable import iTerm2SharedARC

final class TokenExecutorQueueTests: XCTestCase {
    private let queueKey = DispatchSpecificKey<String>()

    private func makeExecutor(on queue: DispatchQueue) -> TokenExecutor {
        return TokenExecutor(VT100Terminal(), slownessDetector: SlownessDetector(), queue: queue)
    }

    // A high-priority task scheduled from another executor's queue must run on its own executor's
    // queue, not synchronously on the caller's.
    func testTaskScheduledFromAnotherExecutorsQueueRunsOnItsOwnQueue() {
        let queueA = iTermGCD.newMutationQueue()
        let queueB = iTermGCD.newMutationQueue()
        queueA.setSpecific(key: queueKey, value: "A")
        queueB.setSpecific(key: queueKey, value: "B")
        let executorA = makeExecutor(on: queueA)
        let executorB = makeExecutor(on: queueB)

        let ran = expectation(description: "Task ran")
        var ranOn: String?
        queueA.async { [queueKey] in
            executorB.scheduleHighPriorityTask {
                ranOn = DispatchQueue.getSpecific(key: queueKey)
                ran.fulfill()
            }
        }
        wait(for: [ran], timeout: 10)
        XCTAssertEqual(ranOn, "B")
        withExtendedLifetime(executorA) {}
    }

    // Executors that share a queue may run each other's tasks synchronously on it, as before.
    func testTaskScheduledOnASharedQueueRunsOnIt() {
        let queue = iTermGCD.newMutationQueue()
        queue.setSpecific(key: queueKey, value: "shared")
        let first = makeExecutor(on: queue)
        let second = makeExecutor(on: queue)

        var ranSynchronously = false
        queue.sync {
            second.scheduleHighPriorityTask {
                ranSynchronously = true
            }
        }
        XCTAssertTrue(ranSynchronously)
        withExtendedLifetime(first) {}
    }

    // Joining a session with a queue of its own pauses only that session's executor. Pausing every
    // executor is what made one session's joins wait for other sessions' output (issue 13141).
    func testJoiningAnExecutorWithItsOwnQueueDoesNotPauseOthers() {
        // With Maximize Throughput off, a join pauses right away instead of after a grace period.
        let saved = iTermPreferences.bool(forKey: kPreferenceKeyMaximizeThroughput)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyMaximizeThroughput)
        defer {
            iTermPreferences.setBool(saved, forKey: kPreferenceKeyMaximizeThroughput)
        }
        XCTAssertFalse(iTermPreferences.maximizeThroughput())
        let executor = makeExecutor(on: iTermGCD.newMutationQueue())
        var globalPauses: Int64 = -1
        executor.whilePaused {
            globalPauses = iTermAtomicInt64Get(TokenExecutor.globalPauseCount)
        }
        XCTAssertEqual(globalPauses, 0)
    }
}

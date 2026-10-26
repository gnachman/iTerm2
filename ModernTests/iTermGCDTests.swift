//
//  iTermGCDTests.swift
//  iTerm2
//
//  Join state and queue-safety markers for mutation queues. With task I/O monitors on, each session
//  has its own mutation queue; otherwise every session shares one. A join pauses one queue, so
//  "already joined" belongs to the queue, not to the session.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermGCDTests: XCTestCase {
    func testSessionsOnTheSharedQueueShareItsJoinState() {
        let shared = iTermGCD.mutationQueue()
        XCTAssertTrue(iTermGCD.joinState(for: shared) === iTermGCD.joinState(for: shared))
    }

    func testEachNewMutationQueueHasItsOwnJoinState() {
        let a = iTermGCD.newMutationQueue()
        let b = iTermGCD.newMutationQueue()
        let stateA = iTermGCD.joinState(for: a)
        let stateB = iTermGCD.joinState(for: b)
        XCTAssertFalse(stateA === stateB)
        XCTAssertFalse(stateA === iTermGCD.joinState(for: iTermGCD.mutationQueue()))

        XCTAssertFalse(stateA.setPerformingJoinedBlock(true))
        XCTAssertTrue(stateA.performingJoinedBlock)
        XCTAssertFalse(stateB.performingJoinedBlock)
        XCTAssertTrue(stateA.setPerformingJoinedBlock(false))
        XCTAssertFalse(stateA.performingJoinedBlock)
    }

    func testOnMutationQueueWithJoinStateMatchesOnlyThatQueue() {
        let a = iTermGCD.newMutationQueue()
        let b = iTermGCD.newMutationQueue()
        let stateA = iTermGCD.joinState(for: a)
        var onA = false
        var onAFromB = true
        a.sync { onA = iTermGCD.onMutationQueue(with: stateA) }
        b.sync { onAFromB = iTermGCD.onMutationQueue(with: stateA) }
        XCTAssertTrue(onA)
        XCTAssertFalse(onAFromB)
        XCTAssertFalse(iTermGCD.onMutationQueue(with: stateA))
    }

    // A session's mutable state may be used on its own queue, or on main while main has joined that
    // queue, but not on another session's queue or while main has joined another session.
    func testSafetyForAParticularMutationQueue() {
        let a = iTermGCD.newMutationQueue()
        let b = iTermGCD.newMutationQueue()
        var aOnA = false
        var aOnB = true
        a.sync { aOnA = iTermGCD.isSafe(forMutationQueue: a) }
        b.sync { aOnB = iTermGCD.isSafe(forMutationQueue: a) }
        XCTAssertTrue(aOnA)
        XCTAssertFalse(aOnB)

        XCTAssertFalse(iTermGCD.isSafe(forMutationQueue: a))
        iTermGCD.setMainQueueSafe(true, on: b)
        XCTAssertFalse(iTermGCD.isSafe(forMutationQueue: a), "Joined to b, not a")
        XCTAssertTrue(iTermGCD.isSafe(forMutationQueue: b))
        iTermGCD.setMainQueueSafe(false, on: b)
        XCTAssertFalse(iTermGCD.isSafe(forMutationQueue: b))
    }

    func testNewMutationQueuesAreMutationQueues() {
        let queue = iTermGCD.newMutationQueue()
        XCTAssertFalse(iTermGCD.onMutationQueue())
        var onIt = false
        queue.sync {
            onIt = iTermGCD.onMutationQueue()
        }
        XCTAssertTrue(onIt)
        var onShared = false
        iTermGCD.mutationQueue().sync {
            onShared = iTermGCD.onMutationQueue()
        }
        XCTAssertTrue(onShared)
    }

    // A join marks the joined queue as safe for main-queue state, and the main queue as safe for
    // mutation state. Nested joins of two queues keep the main queue marked until the outer one
    // ends, and each queue is marked only while it is joined.
    func testNestedJoinsKeepMarkersUntilTheOuterOneEnds() {
        let a = iTermGCD.newMutationQueue()
        let b = iTermGCD.newMutationQueue()
        XCTAssertFalse(iTermGCD.isMutationQueueSafe())

        iTermGCD.setMainQueueSafe(true, on: a)
        XCTAssertTrue(iTermGCD.isMutationQueueSafe())
        XCTAssertTrue(isMainQueueSafe(on: a))
        XCTAssertFalse(isMainQueueSafe(on: b))

        iTermGCD.setMainQueueSafe(true, on: b)
        XCTAssertTrue(isMainQueueSafe(on: b))
        iTermGCD.setMainQueueSafe(false, on: b)
        XCTAssertFalse(isMainQueueSafe(on: b))
        // Still inside a's join.
        XCTAssertTrue(iTermGCD.isMutationQueueSafe())
        XCTAssertTrue(isMainQueueSafe(on: a))

        iTermGCD.setMainQueueSafe(false, on: a)
        XCTAssertFalse(iTermGCD.isMutationQueueSafe())
        XCTAssertFalse(isMainQueueSafe(on: a))
    }

    private func isMainQueueSafe(on queue: DispatchQueue) -> Bool {
        var result = false
        queue.sync {
            result = iTermGCD.isMainQueueSafe()
        }
        return result
    }
}

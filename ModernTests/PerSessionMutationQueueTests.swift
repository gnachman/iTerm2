//
//  PerSessionMutationQueueTests.swift
//  iTerm2
//
//  With task I/O monitors on, each session's mutable state runs on a mutation queue of its own, so
//  joining one session doesn't stop another (issue 13141). Without them every session shares one
//  queue.
//

import XCTest
@testable import iTerm2SharedARC

final class PerSessionMutationQueueTests: XCTestCase {
    private var delegates = [FakeSession]()

    private func makeScreen(queue: DispatchQueue?) -> VT100Screen {
        let screen = queue.map { VT100Screen(mutationQueue: $0) } ?? VT100Screen()
        let delegate = FakeSession()
        delegates.append(delegate)
        delegate.screen = screen
        screen.delegate = delegate
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
        })
        return screen
    }

    private func mutableState(of screen: VT100Screen) -> VT100ScreenMutableState {
        var result: VT100ScreenMutableState!
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState
        })
        return result
    }

    // Joining one session doesn't make another look joined, and joining the other from inside the
    // first join really pauses it instead of taking the reentrancy shortcut.
    func testSessionsWithOwnQueuesJoinIndependently() {
        let a = makeScreen(queue: iTermGCD.newMutationQueue())
        let b = makeScreen(queue: iTermGCD.newMutationQueue())
        let stateA = mutableState(of: a)
        let stateB = mutableState(of: b)
        XCTAssertFalse(stateA.joinState === stateB.joinState)

        var bJoinedDuringA = true
        var bothJoinedInside = false
        var aStillJoinedAfter = false
        var mainSafeAfterInner = false
        a.performBlock(joinedThreads: { _, _, _ in
            bJoinedDuringA = stateB.performingJoinedBlock
            b.performBlock(joinedThreads: { _, _, _ in
                bothJoinedInside = stateA.performingJoinedBlock && stateB.performingJoinedBlock
            })
            aStillJoinedAfter = stateA.performingJoinedBlock && !stateB.performingJoinedBlock
            mainSafeAfterInner = iTermGCD.isMutationQueueSafe()
        })
        XCTAssertFalse(bJoinedDuringA)
        XCTAssertTrue(bothJoinedInside)
        XCTAssertTrue(aStillJoinedAfter)
        XCTAssertTrue(mainSafeAfterInner)
        XCTAssertFalse(stateA.performingJoinedBlock)
        XCTAssertFalse(iTermGCD.isMutationQueueSafe())
    }

    // On the shared queue, joining one session pauses the queue every session uses, so they all
    // count as joined.
    func testSessionsOnTheSharedQueueJoinTogether() {
        let a = makeScreen(queue: iTermGCD.mutationQueue())
        let b = makeScreen(queue: iTermGCD.mutationQueue())
        let stateB = mutableState(of: b)
        var bJoinedDuringA = false
        a.performBlock(joinedThreads: { _, _, _ in
            bJoinedDuringA = stateB.performingJoinedBlock
            // Must not deadlock.
            b.performBlock(joinedThreads: { _, _, _ in })
        })
        XCTAssertTrue(bJoinedDuringA)
    }

    // The default follows the task I/O monitor setting.
    func testDefaultQueueFollowsTheTaskIOMonitorSetting() {
        let screen = makeScreen(queue: nil)
        let shared = iTermGCD.joinState(for: iTermGCD.mutationQueue())
        let usesShared = mutableState(of: screen).joinState === shared
        XCTAssertEqual(usesShared, !TaskNotifier.usesTaskIOMonitors())
    }

    // Like VT100ScreenTests.testReentrantSafeJoinActuallyJoins, on a queue of its own.
    func testReentrantSafeJoinActuallyJoinsOnOwnQueue() {
        let screen = makeScreen(queue: iTermGCD.newMutationQueue())
        var joined = false
        screen.performBlock(joinedThreadsReentrantSafe: { _, mutableState, _ in
            joined = mutableState.performingJoinedBlock
        })
        XCTAssertTrue(joined)
    }
}

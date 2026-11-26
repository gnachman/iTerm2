//
//  GitPollerInFlightTests.swift
//  iTerm2 ModernTests
//
//  iTermGitPoller runs one poll at a time. In a large repository a poll
//  can outlast the poller's cadence, and overlapping polls joined the
//  same worker request, so a result couldn't be tied to the poll that
//  asked for it. The workgroup needs that to decide whether state is
//  current enough to launch a diff (issue 13243).
//

import XCTest
@testable import iTerm2SharedARC

final class GitPollerInFlightTests: XCTestCase {
    private final class AlwaysPoll: NSObject, iTermGitPollerDelegate {
        var asked = 0
        func gitPollerShouldPoll(_ poller: iTermGitPoller, after lastPoll: Date?) -> Bool {
            asked += 1
            return true
        }
    }

    // Holds each request until the test completes it.
    private final class ManualWorker: NSObject, iTermGitPollWorkerProtocol {
        var requests: [(path: String, completion: (iTermGitState?, Bool) -> Void)] = []

        func requestPath(_ path: String,
                         gitBase: String?,
                         includeDiffStats: Bool,
                         completion: @escaping (iTermGitState?, Bool) -> Void) {
            requests.append((path, completion))
        }

        func invalidateCache(forPath path: String) {}

        func complete(_ index: Int, branch: String, timedOut: Bool = false) {
            let state = iTermGitState()
            state.branch = branch
            requests[index].completion(state, timedOut)
        }
    }

    private var updates = 0
    private let delegate = AlwaysPoll()
    private let worker = ManualWorker()
    private var poller: iTermGitPoller!

    override func setUp() {
        super.setUp()
        updates = 0
        // A long cadence keeps the timer out of the way.
        poller = iTermGitPoller(cadence: 10_000) { [weak self] in
            self?.updates += 1
        }
        poller.delegate = delegate
        poller.enabled = true
        poller.worker = worker
        poller.currentDirectory = "/repo"
        XCTAssertEqual(worker.requests.count, 1, "Setting the directory polls")
    }

    func testOverlappingPollIsSkipped() {
        let askedBefore = delegate.asked
        let lastPollTime = poller.lastPollTime
        // A timer tick during the poll doesn't start another or move
        // lastPollTime.
        poller.perform(NSSelectorFromString("poll"))
        XCTAssertEqual(worker.requests.count, 1)
        XCTAssertEqual(delegate.asked, askedBefore, "The delegate isn't consulted while a poll is in flight")
        XCTAssertEqual(poller.lastPollTime, lastPollTime)

        worker.complete(0, branch: "main")
        XCTAssertEqual(poller.deliveryCount, 1)
        XCTAssertEqual(poller.state?.branch, "main")
        XCTAssertEqual(worker.requests.count, 1, "A skipped tick doesn't poll again afterward")
    }

    func testBumpDuringPollPollsAgainWhenItFinishes() {
        poller.bump()
        XCTAssertEqual(worker.requests.count, 1)

        worker.complete(0, branch: "before")
        XCTAssertEqual(poller.deliveryCount, 1)
        XCTAssertEqual(worker.requests.count, 2, "The bump's poll runs once the first finishes")

        worker.complete(1, branch: "after")
        XCTAssertEqual(poller.deliveryCount, 2)
        XCTAssertEqual(poller.state?.branch, "after")
        XCTAssertEqual(worker.requests.count, 2)
    }

    func testDirectoryChangeDuringPollStartsNewPollAndDropsOldResult() {
        poller.currentDirectory = "/other"
        XCTAssertEqual(worker.requests.count, 2, "A new directory doesn't wait for the old poll")
        XCTAssertEqual(worker.requests[1].path, "/other")

        worker.complete(0, branch: "old")
        XCTAssertEqual(poller.deliveryCount, 0, "The superseded poll's result is dropped")
        XCTAssertNil(poller.state)

        worker.complete(1, branch: "new")
        XCTAssertEqual(poller.deliveryCount, 1)
        XCTAssertEqual(poller.state?.branch, "new")
        XCTAssertEqual(poller.startedPollCount, 2)
        XCTAssertEqual(poller.deliveredPollNumber, 2, "Delivered by the second poll; the first never delivered")
    }

    func testUpdatesWithoutPollAreNotDeliveries() {
        worker.complete(0, branch: "main")
        XCTAssertEqual(poller.deliveryCount, 1)
        let updatesAfterDelivery = updates

        // Both run the update block with the state unchanged.
        poller.enabled = false
        poller.clearTimeoutFlagAndRetry()
        XCTAssertGreaterThan(updates, updatesAfterDelivery)
        XCTAssertEqual(poller.deliveryCount, 1)
    }

    func testHasPollInFlight() {
        XCTAssertTrue(poller.hasPollInFlight)
        worker.complete(0, branch: "main")
        XCTAssertFalse(poller.hasPollInFlight)
    }

    func testBaseChangeStartsOnePollForNewBase() {
        // The workgroup's git base fan-out relies on this poll's result to
        // launch or hold each Diff member, without asking for another.
        worker.complete(0, branch: "main")
        poller.gitBase = "origin/main"
        XCTAssertEqual(worker.requests.count, 2)
        XCTAssertTrue(poller.hasPollInFlight)
        worker.complete(1, branch: "main")
        XCTAssertEqual(worker.requests.count, 2, "No second poll follows")
    }

    func testTimedOutPollIsStillADelivery() {
        // The workgroup tells these apart with lastPollTimedOut.
        worker.complete(0, branch: "cached", timedOut: true)
        XCTAssertEqual(poller.deliveryCount, 1)
        XCTAssertTrue(poller.lastPollTimedOut)
    }
}

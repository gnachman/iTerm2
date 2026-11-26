//
//  GitPollWorkerInvalidationTests.swift
//  iTerm2 ModernTests
//
//  Invalidating a path while a request for it is in flight must still
//  answer that request's waiters. iTermGitPoller runs one poll at a time,
//  so a dropped answer would stop it from polling until it gave up on
//  the request (issue 13243).
//

import XCTest
@testable import iTerm2SharedARC

final class GitPollWorkerInvalidationTests: XCTestCase {
    // Holds each fetch until the test answers it.
    private final class Fetches {
        var pending: [(path: String, completion: (iTermGitState?, Bool) -> Void)] = []

        func answer(_ index: Int, branch: String) {
            let state = iTermGitState()
            state.branch = branch
            state.creationTime = NSDate.it_timeSinceBoot()
            pending[index].completion(state, false)
        }
    }

    private var fetches = Fetches()
    private var worker: iTermGitPollWorker!

    override func setUp() {
        super.setUp()
        fetches = Fetches()
        let fetches = self.fetches
        worker = iTermGitPollWorker { path, _, _, completion in
            fetches.pending.append((path, completion))
        }
    }

    func testInvalidatedRequestStillAnswersItsWaiters() {
        var answers: [String?] = []
        worker.requestPath("/repo", gitBase: nil, includeDiffStats: true) { state, _ in
            answers.append(state?.branch)
        }
        XCTAssertEqual(fetches.pending.count, 1)

        worker.invalidateCache(forPath: "/repo")

        // A request after the invalidation starts its own fetch rather
        // than joining the one already under way.
        worker.requestPath("/repo", gitBase: nil, includeDiffStats: true) { state, _ in
            answers.append(state?.branch)
        }
        XCTAssertEqual(fetches.pending.count, 2)

        fetches.answer(0, branch: "old")
        XCTAssertEqual(answers, ["old"], "The invalidated request's waiter still gets its answer")
        XCTAssertNil(worker.cachedBranch(forPath: "/repo"), "The invalidated answer isn't cached")

        fetches.answer(1, branch: "new")
        XCTAssertEqual(answers, ["old", "new"])
        XCTAssertEqual(worker.cachedBranch(forPath: "/repo"), "new")
    }

    private final class AlwaysPoll: NSObject, iTermGitPollerDelegate {
        func gitPollerShouldPoll(_ poller: iTermGitPoller, after lastPoll: Date?) -> Bool { true }
    }

    func testPollerKeepsPollingWhenItsRequestIsInvalidated() {
        let delegate = AlwaysPoll()
        let poller = iTermGitPoller(cadence: 10_000) {}
        poller.delegate = delegate
        poller.enabled = true
        poller.includeDiffStats = true
        poller.worker = worker
        poller.currentDirectory = "/repo"
        XCTAssertEqual(fetches.pending.count, 1)

        // Another poller moving to this repository invalidates its cache.
        worker.invalidateCache(forPath: "/repo")
        // Something wants current state while the poll is in flight.
        poller.bump()
        XCTAssertEqual(fetches.pending.count, 1, "The bump waits for the poll in flight")

        fetches.answer(0, branch: "main")
        XCTAssertEqual(poller.deliveryCount, 1, "The poll completes despite the invalidation")
        XCTAssertEqual(poller.state?.branch, "main")
        XCTAssertEqual(fetches.pending.count, 2, "The bump's poll runs right after")
    }

    func testFollowUpPollBypassesCache() {
        let delegate = AlwaysPoll()
        let poller = iTermGitPoller(cadence: 10_000) {}
        poller.delegate = delegate
        poller.enabled = true
        poller.worker = worker
        poller.currentDirectory = "/repo"
        // The tree changes while the poll is in flight, and something bumps.
        poller.bump()

        // The answer is brand new, so the worker's cache would serve it to
        // the follow-up.
        fetches.answer(0, branch: "before")
        XCTAssertEqual(fetches.pending.count, 2, "The follow-up fetches instead of reusing the cached answer")

        fetches.answer(1, branch: "after")
        XCTAssertEqual(poller.state?.branch, "after")
        XCTAssertEqual(poller.deliveryCount, 2)
    }
}

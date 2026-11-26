//
//  WorkgroupGitStateFreshnessTests.swift
//  iTerm2 ModernTests
//
//  When a workgroup's git state is current enough to launch a diff.
//  Launching from stale state runs difftool on a tree that has since
//  changed, which shows nothing and exits (issue 13243).
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupGitStateFreshnessTests: XCTestCase {
    private let context = "/repo"
    private var freshness = WorkgroupGitStateFreshness()
    // Mirror iTermGitPoller's counters.
    private var deliveries: UInt = 0
    private var started: UInt = 0
    private var delivered: UInt = 0
    private var now: TimeInterval = 1000

    override func setUp() {
        super.setUp()
        freshness = WorkgroupGitStateFreshness()
        deliveries = 0
        started = 0
        delivered = 0
        now = 1000
    }

    // Starts a poll and returns its number.
    @discardableResult
    private func start() -> UInt {
        started += 1
        return started
    }

    private func deliver(_ pollNumber: UInt, timedOut: Bool = false, context: String? = nil) {
        deliveries += 1
        delivered = pollNumber
        freshness.pollerDidUpdate(deliveryCount: deliveries,
                                  deliveredPollNumber: delivered,
                                  timedOut: timedOut,
                                  context: context ?? self.context,
                                  now: now)
    }

    // Starts a poll and delivers its result.
    private func poll(timedOut: Bool = false, context: String? = nil) {
        deliver(start(), timedOut: timedOut, context: context)
    }

    private func isFromLatestPoll(context: String? = nil) -> Bool {
        return freshness.isFromLatestPoll(deliveredPollNumber: delivered,
                                          hasState: true,
                                          context: context ?? self.context)
    }

    private func isFresh() -> Bool {
        return freshness.isFresh(deliveredPollNumber: delivered, hasState: true, context: context, now: now)
    }

    private func isSuperseded() -> Bool {
        return freshness.isSuperseded(deliveredPollNumber: delivered, context: context)
    }

    private func request() {
        freshness.freshStateRequested(startedPollCount: started, context: context)
    }

    func testDeliveryIsFreshThenAges() {
        XCTAssertFalse(isFromLatestPoll(), "Nothing delivered yet")
        poll()
        XCTAssertTrue(isFromLatestPoll())
        XCTAssertTrue(isFresh())
        now += WorkgroupGitStateFreshness.freshAge + 1
        XCTAssertFalse(isFresh())
        XCTAssertTrue(isFromLatestPoll(), "Still the latest poll's result, just not recent")
    }

    func testRequestDuringOrdinaryPollSupersedesItsResult() {
        // A timer poll is in flight. The user commits elsewhere and clicks
        // Reload, which asks for fresh state.
        poll()
        let inFlight = start()
        request()

        // The poll in flight returns what it read before the commit.
        deliver(inFlight)
        XCTAssertTrue(isSuperseded(), "Its result must neither launch nor show the overlay")
        XCTAssertFalse(isFromLatestPoll())
        XCTAssertFalse(isFresh())

        // The follow-up reads the tree after the request.
        poll()
        XCTAssertFalse(isSuperseded())
        XCTAssertTrue(isFromLatestPoll())
        XCTAssertTrue(isFresh())
    }

    func testAbandonedPollDoesNotDelayFreshness() {
        // The poll in flight never answers. The poller gives up on it, and
        // the next poll it starts is the only one that will deliver.
        poll()
        start()
        request()
        poll()
        XCTAssertFalse(isSuperseded(), "One delivery from a poll started after the request is enough")
        XCTAssertTrue(isFresh())
    }

    func testRequestWithNoPollInFlightNeedsTheNextPoll() {
        poll()
        request()
        XCTAssertTrue(isSuperseded(), "The current state predates the request")
        poll()
        XCTAssertFalse(isSuperseded())
        XCTAssertTrue(isFresh())
    }

    func testRequestDuringContextChangePollSupersedesItsResult() {
        // The leader changes into a large repository, which starts a slow
        // poll. While it runs, the user commits elsewhere and clicks
        // Reload. The poll read the tree before the commit.
        poll()
        let contextChangePoll = start()
        request()
        deliver(contextChangePoll)
        XCTAssertTrue(isSuperseded())
        XCTAssertFalse(isFresh())
        poll()
        XCTAssertTrue(isFresh())
    }

    func testContextChangeEndsRequirement() {
        poll()
        start()
        request()
        // The base changes: the poll in flight is superseded, and the
        // change's own poll reads the tree after the request.
        poll(context: "/repo base")
        XCTAssertTrue(isFromLatestPoll(context: "/repo base"))
    }

    func testTimedOutDeliveryIsNotFromLatestPoll() {
        poll()
        poll(timedOut: true)
        XCTAssertFalse(isFromLatestPoll(), "A timeout replays older cached state")
        poll()
        XCTAssertTrue(isFromLatestPoll())
    }

    func testCallbackWithoutDeliveryDoesNotRefresh() {
        poll()
        now += WorkgroupGitStateFreshness.freshAge + 1
        // Disabling the poller calls back with the same delivery count.
        freshness.pollerDidUpdate(deliveryCount: deliveries,
                                  deliveredPollNumber: delivered,
                                  timedOut: false,
                                  context: context,
                                  now: now)
        XCTAssertFalse(isFresh(), "Old state isn't re-stamped as new")
    }

    func testStateForAnotherContextIsNotFromLatestPoll() {
        poll()
        XCTAssertFalse(isFromLatestPoll(context: "/other"))
    }
}

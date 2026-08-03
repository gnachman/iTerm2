//
//  CompanionWakeupCoordinatorTests.swift
//  iTerm2 ModernTests
//
//  The global gate that decides WHEN to send a contentless-wakeup push. Stateless
//  about DB content: "is there anything to show" is the injected renderable check
//  (in production, the responder's own predicate over the current store). A wakeup
//  fires when there is renderable content above the phone's floor, subject to the
//  rate-limit interval - a hard invariant (no "fetched since last push" override).
//  Driven entirely through injected clock / renderable / send / scheduler.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CompanionWakeupCoordinatorTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000)
    private var interval: TimeInterval = 5
    private var renderable = false               // simple bool the floor-agnostic tests use
    private var renderableContentSeq: Int64?     // when set, renderable iff floor < this seq
    private var sends = 0
    private var deferredClosure: (() -> Void)?
    private var deferredDelay: TimeInterval?

    private func makeCoordinator() -> CompanionWakeupCoordinator {
        CompanionWakeupCoordinator(
            interval: { self.interval },
            clock: { self.now },
            hasRenderableContent: { messageFloor, _ in
                // Floor-aware when a content seq is set (for the rewind test); else the
                // simple bool.
                if let seq = self.renderableContentSeq { return messageFloor < seq }
                return self.renderable
            },
            send: { self.sends += 1 },
            scheduleAfter: { delay, closure in
                self.deferredDelay = delay
                self.deferredClosure = closure
            })
    }

    private func advance(_ dt: TimeInterval) { now = now.addingTimeInterval(dt) }

    private func fireDeferred() {
        let closure = deferredClosure
        deferredClosure = nil
        closure?()
    }

    // MARK: Content path

    func testRenderableContentFiresImmediately() {
        renderable = true
        makeCoordinator().noteContentActivity(chatID: "c")
        XCTAssertEqual(sends, 1, "renderable content with no recent push fires a wakeup immediately")
    }

    func testNothingRenderableDoesNotFire() {
        renderable = false
        makeCoordinator().noteContentActivity(chatID: "c")
        XCTAssertEqual(sends, 0, "no push when the responder would render nothing (e.g. an .external tool-call row)")
    }

    func testSecondRenderableWithinIntervalIsDeferred() {
        let c = makeCoordinator()
        renderable = true
        c.noteContentActivity(chatID: "c")           // fires
        advance(0.1)
        c.noteContentActivity(chatID: "c")           // too soon -> defer
        XCTAssertEqual(sends, 1)
    }

    func testRenderableAfterIntervalFires() {
        let c = makeCoordinator()
        renderable = true
        c.noteContentActivity(chatID: "c")           // fires (t=1000)
        advance(0.1)
        c.noteContentActivity(chatID: "c")           // deferred
        advance(5)
        c.noteContentActivity(chatID: "c")           // interval elapsed -> fires
        XCTAssertEqual(sends, 2)
    }

    // MARK: The interval is an invariant (no fetch-override)

    func testFetchSinceLastPushDoesNotBypassTheInterval() {
        let c = makeCoordinator()
        renderable = true
        c.noteContentActivity(chatID: "c")           // fires (t=1000)
        advance(1)
        renderable = false                           // the fetch drained everything
        c.noteNSEFetch(messageFloor: 10, alertFloor: 0)  // nothing outstanding -> no push
        XCTAssertEqual(sends, 1)
        advance(0.5)                                 // t=1001.5, only 1.5s since the push
        renderable = true                            // a new renderable reply arrives
        c.noteContentActivity(chatID: "c")
        XCTAssertEqual(sends, 1,
                       "new content soon after a push+fetch DEFERS - the interval is not bypassed")
    }

    // MARK: Fetch re-check + deferred

    func testFetchStillRenderableDefersThenFires() {
        let c = makeCoordinator()
        renderable = true
        c.noteContentActivity(chatID: "c")           // fires (t=1000)
        advance(1)
        c.noteNSEFetch(messageFloor: 10, alertFloor: 0)  // still renderable (truncated tail) -> defer
        XCTAssertEqual(sends, 1)
        advance(4)
        fireDeferred()                               // interval elapsed -> fires
        XCTAssertEqual(sends, 2)
    }

    func testDeferredCancelledWhenNoLongerOutstanding() {
        let c = makeCoordinator()
        renderable = true
        c.noteContentActivity(chatID: "c")           // fires
        advance(0.1)
        c.noteContentActivity(chatID: "c")           // deferred
        renderable = false                           // content drained/deleted
        advance(0.5)
        c.noteNSEFetch(messageFloor: 10, alertFloor: 0)  // not outstanding -> cancels deferred
        advance(4.4)
        fireDeferred()                               // stale generation -> no-op
        XCTAssertEqual(sends, 1)
    }

    func testDeferredFiresWhenStillOutstanding() {
        let c = makeCoordinator()
        renderable = true
        c.noteContentActivity(chatID: "c")           // fires
        advance(0.1)
        c.noteContentActivity(chatID: "c")           // deferred
        advance(4.9)
        fireDeferred()
        XCTAssertEqual(sends, 2)
    }

    // MARK: Structural: a regressed tip cannot loop (no high-water mark to strand)

    func testDeletedContentDoesNotLoopWakeups() {
        let c = makeCoordinator()
        renderable = true
        c.noteContentActivity(chatID: "c")           // fires. sends=1.
        XCTAssertEqual(sends, 1)
        // The top message is deleted, so the store now renders nothing above the
        // floor. The fetch that follows simply finds nothing - there is no stale
        // pending seq to strand, so no runaway empty-wakeup loop.
        renderable = false
        c.noteNSEFetch(messageFloor: 40, alertFloor: 0)
        XCTAssertEqual(sends, 1)
        c.noteNSEFetch(messageFloor: 40, alertFloor: 0)
        XCTAssertEqual(sends, 1, "no loop: the stateless check reads the truth every time")
    }

    // MARK: Store rewind lowers the floor (no stale-high suppression)

    func testRewindResetLowersFloorSoLowSeqContentFires() {
        let c = makeCoordinator()
        // A normal fetch advances the floor high.
        c.noteNSEFetch(messageFloor: 100, alertFloor: 0)
        XCTAssertEqual(sends, 0, "nothing renderable yet")
        // The store rewinds; renderable content now exists at a LOW seq (5). The
        // phone's own reconnect fetch reports the new low tip with reset=true. The
        // floor must ASSIGN down to 3 (not max back to 100), so seq 5 is above it.
        renderableContentSeq = 5
        c.noteNSEFetch(messageFloor: 3, alertFloor: 0, messageReset: true)
        XCTAssertEqual(sends, 1, "a reset fetch lowers the floor so post-rewind low-seq content fires")
    }

    // MARK: Backward clock step is clamped

    func testBackwardClockStepDoesNotStrandTheDeferredWakeup() {
        let c = makeCoordinator()
        renderable = true
        c.noteContentActivity(chatID: "c")           // fires at now=1000
        XCTAssertEqual(sends, 1)
        now = now.addingTimeInterval(-3600)          // wall clock steps back an hour
        c.noteContentActivity(chatID: "c")           // outstanding, too soon -> defer
        XCTAssertEqual(deferredDelay, 5, "deferred delay is clamped to the interval, not interval+3600")
    }
}

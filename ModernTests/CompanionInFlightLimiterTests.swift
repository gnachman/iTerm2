//
//  CompanionInFlightLimiterTests.swift
//  iTerm2 ModernTests
//
//  The limiter paces the streamer against the phone's streamAck feedback so the
//  live view never drifts far behind. Deterministic: no clock, just sent/ack
//  bookkeeping.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionInFlightLimiterTests: XCTestCase {
    func testAllowsEmitBeforeAnyAck() {
        var l = CompanionInFlightLimiter(maxLeadMilliseconds: 500, maxQueueDepth: 4)
        // Even far ahead, with no ack yet the stream is allowed to establish.
        l.noteSent(ptsMilliseconds: 100_000)
        XCTAssertTrue(l.mayEmit())
    }

    func testBlocksWhenLeadExceedsMax() {
        var l = CompanionInFlightLimiter(maxLeadMilliseconds: 500, maxQueueDepth: 4)
        l.noteSent(ptsMilliseconds: 1000)
        l.noteAck(ptsMilliseconds: 1000, queueDepth: 0)
        XCTAssertTrue(l.mayEmit())
        // Sent 700ms past the last ack -> too far ahead.
        l.noteSent(ptsMilliseconds: 1700)
        XCTAssertFalse(l.mayEmit())
    }

    func testResumesWhenAckCatchesUp() {
        var l = CompanionInFlightLimiter(maxLeadMilliseconds: 500, maxQueueDepth: 4)
        l.noteAck(ptsMilliseconds: 1000, queueDepth: 0)
        l.noteSent(ptsMilliseconds: 1700)
        XCTAssertFalse(l.mayEmit())
        // The phone catches up.
        l.noteAck(ptsMilliseconds: 1700, queueDepth: 0)
        XCTAssertTrue(l.mayEmit())
    }

    func testBlocksOnDeepQueue() {
        var l = CompanionInFlightLimiter(maxLeadMilliseconds: 500, maxQueueDepth: 4)
        l.noteSent(ptsMilliseconds: 1000)
        l.noteAck(ptsMilliseconds: 1000, queueDepth: 5)  // lead 0 but queue too deep
        XCTAssertFalse(l.mayEmit())
        l.noteAck(ptsMilliseconds: 1000, queueDepth: 1)
        XCTAssertTrue(l.mayEmit())
    }

    func testExactlyAtLeadLimitStillEmits() {
        var l = CompanionInFlightLimiter(maxLeadMilliseconds: 500, maxQueueDepth: 4)
        l.noteAck(ptsMilliseconds: 1000, queueDepth: 0)
        l.noteSent(ptsMilliseconds: 1500)  // lead == max
        XCTAssertTrue(l.mayEmit())
    }
}

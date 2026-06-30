//
//  CompanionStreamBudgetTests.swift
//  iTerm2 ModernTests
//
//  Deterministic tests for the rolling byte budget that keeps the stream under
//  the relay's daily quota. Time is injected.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionStreamBudgetTests: XCTestCase {
    func testNotExhaustedUnderLimit() {
        var b = CompanionStreamBudget(limitBytes: 1000, windowSeconds: 100)
        b.record(bytes: 400, now: 0)
        b.record(bytes: 400, now: 10)
        XCTAssertFalse(b.isExhausted(now: 20))
        XCTAssertEqual(b.remaining(now: 20), 200)
    }

    func testExhaustedAtOrOverLimit() {
        var b = CompanionStreamBudget(limitBytes: 1000, windowSeconds: 100)
        b.record(bytes: 600, now: 0)
        b.record(bytes: 400, now: 5)
        XCTAssertTrue(b.isExhausted(now: 10))
        XCTAssertEqual(b.remaining(now: 10), 0)
    }

    func testWindowRollResetsUsage() {
        var b = CompanionStreamBudget(limitBytes: 1000, windowSeconds: 100)
        b.record(bytes: 1000, now: 0)
        XCTAssertTrue(b.isExhausted(now: 50))
        // Past the window: counter resets.
        XCTAssertFalse(b.isExhausted(now: 101))
        XCTAssertEqual(b.remaining(now: 101), 1000)
    }

    func testWindowAnchorsOnFirstUseNotInit() {
        var b = CompanionStreamBudget(limitBytes: 1000, windowSeconds: 100)
        // First activity at t=1000 anchors the window there.
        b.record(bytes: 1000, now: 1000)
        XCTAssertTrue(b.isExhausted(now: 1050))
        XCTAssertFalse(b.isExhausted(now: 1101))
    }
}

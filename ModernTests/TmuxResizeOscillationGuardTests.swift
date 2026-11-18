//
//  TmuxResizeOscillationGuardTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxResizeOscillationGuardTests: XCTestCase {
    private let narrow = NSSize(width: 193, height: 43)
    private let wide = NSSize(width: 196, height: 43)

    func testAllowsOrdinaryResizes() {
        let sut = TmuxResizeOscillationGuard(interval: 3, maximumFlips: 1)
        XCTAssertTrue(sut.shouldRequest(size: NSSize(width: 100, height: 40), window: 1, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: NSSize(width: 110, height: 40), window: 1, now: 0.1))
        XCTAssertTrue(sut.shouldRequest(size: NSSize(width: 120, height: 40), window: 1, now: 0.2))
        XCTAssertTrue(sut.shouldRequest(size: NSSize(width: 130, height: 40), window: 1, now: 0.3))
    }

    // The zoomed pane / unzoomed split ping-pong from the 3.7.8 QA: 196, 193, 196, 193, ...
    func testRefusesPingPong() {
        let sut = TmuxResizeOscillationGuard(interval: 3, maximumFlips: 1)
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 0.01))
        // One return to an earlier size is allowed.
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0.02))
        XCTAssertFalse(sut.shouldRequest(size: wide, window: 0, now: 0.03))
        XCTAssertFalse(sut.shouldRequest(size: wide, window: 0, now: 0.04))
    }

    func testWindowsAreIndependent() {
        let sut = TmuxResizeOscillationGuard(interval: 3, maximumFlips: 1)
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 1, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 1, now: 0))
        XCTAssertFalse(sut.shouldRequest(size: wide, window: 0, now: 0))
    }

    func testResetAllowsRequestsAgain() {
        let sut = TmuxResizeOscillationGuard(interval: 3, maximumFlips: 1)
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertFalse(sut.shouldRequest(size: wide, window: 0, now: 0))
        sut.reset()
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 0))
    }

    func testSpacedOutRequestsAreNotAPingPong() {
        let sut = TmuxResizeOscillationGuard(interval: 3, maximumFlips: 1)
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 10))
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 20))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 30))
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 40))
    }

    func testQuietPeriodClearsARefusal() {
        let sut = TmuxResizeOscillationGuard(interval: 3, maximumFlips: 1)
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertFalse(sut.shouldRequest(size: wide, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 10))
    }

    // A refused size may be the one that fits, so the caller retries once after the interval.
    // A loop that is still going must not retry forever, so only a reset re-arms the retry.
    func testRetriesOnceAfterRefusalUntilReset() {
        let sut = TmuxResizeOscillationGuard(interval: 3, maximumFlips: 1)
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 0))
        XCTAssertFalse(sut.shouldRequest(size: wide, window: 0, now: 0))
        XCTAssertTrue(sut.shouldRetryAfterRefusal())
        XCTAssertFalse(sut.shouldRetryAfterRefusal())

        // The retry, after the interval, is allowed.
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 3.25))
        XCTAssertTrue(sut.shouldRequest(size: narrow, window: 0, now: 3.26))
        XCTAssertTrue(sut.shouldRequest(size: wide, window: 0, now: 3.27))
        XCTAssertFalse(sut.shouldRequest(size: narrow, window: 0, now: 3.28))
        XCTAssertFalse(sut.shouldRetryAfterRefusal())

        sut.reset()
        XCTAssertTrue(sut.shouldRetryAfterRefusal())
    }
}

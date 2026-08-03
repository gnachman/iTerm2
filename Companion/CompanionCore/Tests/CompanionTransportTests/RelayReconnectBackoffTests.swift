//
//  RelayReconnectBackoffTests.swift
//  CompanionCore
//
//  The full-jitter reconnect backoff (design §7.3 / Appendix C): first window is
//  the flat initial jitter, then exponential to the cap; every draw is within its
//  window; the window is monotonic and never exceeds the cap.
//

import XCTest
@testable import CompanionTransport

final class RelayReconnectBackoffTests: XCTestCase {
    private let backoff = RelayReconnectBackoff()   // defaults: 3 / 1 / 30

    func test_firstReconnect_usesInitialJitter() {
        XCTAssertEqual(backoff.jitterUpperBound(consecutiveFailures: 1), 3)
    }

    func test_subsequentFailures_growExponentiallyToTheCap() {
        // n>=2: min(cap, base * 2^n) with base 1, cap 30.
        XCTAssertEqual(backoff.jitterUpperBound(consecutiveFailures: 2), 4)
        XCTAssertEqual(backoff.jitterUpperBound(consecutiveFailures: 3), 8)
        XCTAssertEqual(backoff.jitterUpperBound(consecutiveFailures: 4), 16)
        XCTAssertEqual(backoff.jitterUpperBound(consecutiveFailures: 5), 30)   // 32 capped
        XCTAssertEqual(backoff.jitterUpperBound(consecutiveFailures: 6), 30)
        XCTAssertEqual(backoff.jitterUpperBound(consecutiveFailures: 20), 30)
    }

    func test_windowIsMonotonicAndCapped() {
        var previous = 0.0
        for n in 1...40 {
            let bound = backoff.jitterUpperBound(consecutiveFailures: n)
            XCTAssertGreaterThanOrEqual(bound, previous, "window must not shrink at n=\(n)")
            XCTAssertLessThanOrEqual(bound, backoff.cap, "window must not exceed the cap at n=\(n)")
            previous = bound
        }
    }

    func test_delayIsAlwaysWithinItsWindow() {
        // Full jitter: every draw lies in [0, upperBound].
        for n in 1...8 {
            let bound = backoff.jitterUpperBound(consecutiveFailures: n)
            for _ in 0..<200 {
                let d = backoff.delay(consecutiveFailures: n)
                XCTAssertGreaterThanOrEqual(d, 0)
                XCTAssertLessThanOrEqual(d, bound)
            }
        }
    }

    func test_customParametersAreHonored() {
        let b = RelayReconnectBackoff(initialJitter: 5, base: 2, cap: 100)
        XCTAssertEqual(b.jitterUpperBound(consecutiveFailures: 1), 5)
        XCTAssertEqual(b.jitterUpperBound(consecutiveFailures: 2), 8)     // 2 * 2^2
        XCTAssertEqual(b.jitterUpperBound(consecutiveFailures: 3), 16)    // 2 * 2^3
        XCTAssertEqual(b.jitterUpperBound(consecutiveFailures: 10), 100)  // capped
    }
}

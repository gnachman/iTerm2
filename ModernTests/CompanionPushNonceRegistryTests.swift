//
//  CompanionPushNonceRegistryTests.swift
//  iTerm2 ModernTests
//
//  The one-time push-nonce store: a nonce is recognized exactly once and only if
//  it was actually issued, with NO time expiry (an APNs-delayed push must still
//  match however late it arrives). Retention is bounded by capacity, not time.
//  This is what lets the mac tell its OWN solicited NSE fetch from any other
//  connection without false-alarming on a late fetch.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CompanionPushNonceRegistryTests: XCTestCase {
    private func makeRegistry(capacity: Int = 1024) -> CompanionPushNonceRegistry {
        var counter = 0
        return CompanionPushNonceRegistry(capacity: capacity, makeRandom: {
            counter += 1
            return "nonce-\(counter)"
        })
    }

    func testIssuedNonceIsConsumedExactlyOnce() {
        let reg = makeRegistry()
        let nonce = reg.makeNonce()
        XCTAssertTrue(reg.consume(nonce), "a freshly issued nonce is recognized")
        XCTAssertFalse(reg.consume(nonce), "single-use: the same nonce is not recognized twice")
    }

    func testUnknownNonceIsRejected() {
        let reg = makeRegistry()
        _ = reg.makeNonce()
        XCTAssertFalse(reg.consume("never-issued"), "a nonce that was never issued is rejected (the attacker case)")
    }

    func testNonceNeverExpiresByTime() {
        // No clock: a nonce stays valid no matter how much "time" passes, so an
        // APNs-delayed push that delivers it late still matches. As long as we
        // stay under capacity, issuing other nonces does not drop it.
        let reg = makeRegistry(capacity: 1024)
        let delayed = reg.makeNonce()
        for _ in 0..<500 { _ = reg.makeNonce() }   // lots of later pushes
        XCTAssertTrue(reg.consume(delayed), "a long-delayed (but un-evicted) nonce still matches")
    }

    func testOldestIsEvictedBeyondCapacity() {
        let reg = makeRegistry(capacity: 3)
        let first = reg.makeNonce()      // nonce-1
        _ = reg.makeNonce()              // nonce-2
        _ = reg.makeNonce()             // nonce-3
        _ = reg.makeNonce()             // nonce-4 -> evicts nonce-1
        XCTAssertFalse(reg.consume(first), "the oldest nonce is evicted once capacity is exceeded")
    }

    func testEvictionDoesNotDropNewerNonces() {
        let reg = makeRegistry(capacity: 2)
        _ = reg.makeNonce()              // nonce-1 (will be evicted)
        let keep1 = reg.makeNonce()      // nonce-2
        let keep2 = reg.makeNonce()      // nonce-3 -> evicts nonce-1
        XCTAssertTrue(reg.consume(keep2))
        XCTAssertTrue(reg.consume(keep1), "eviction removes only the oldest, not newer nonces")
    }

    func testIndependentNonces() {
        let reg = makeRegistry()
        let a = reg.makeNonce()
        let b = reg.makeNonce()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(reg.consume(b))
        XCTAssertTrue(reg.consume(a), "consuming one nonce does not invalidate another")
    }
}

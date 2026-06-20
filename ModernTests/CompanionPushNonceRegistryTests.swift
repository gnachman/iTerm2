//
//  CompanionPushNonceRegistryTests.swift
//  iTerm2 ModernTests
//
//  The one-time push-nonce store: a nonce is recognized exactly once, only
//  before it expires, and only if it was actually issued. This is what lets the
//  mac tell its OWN solicited NSE fetch from any other connection.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CompanionPushNonceRegistryTests: XCTestCase {
    private func makeRegistry(ttl: TimeInterval, now: @escaping () -> Date) -> CompanionPushNonceRegistry {
        var counter = 0
        return CompanionPushNonceRegistry(ttl: ttl, now: now, makeRandom: {
            counter += 1
            return "nonce-\(counter)"
        })
    }

    func testIssuedNonceIsConsumedExactlyOnce() {
        let reg = makeRegistry(ttl: 100, now: { Date(timeIntervalSince1970: 0) })
        let nonce = reg.makeNonce()
        XCTAssertTrue(reg.consume(nonce), "a freshly issued nonce is recognized")
        XCTAssertFalse(reg.consume(nonce), "single-use: the same nonce is not recognized twice")
    }

    func testUnknownNonceIsRejected() {
        let reg = makeRegistry(ttl: 100, now: { Date(timeIntervalSince1970: 0) })
        _ = reg.makeNonce()
        XCTAssertFalse(reg.consume("never-issued"), "a nonce that was never issued is rejected (the attacker case)")
    }

    func testExpiredNonceIsRejected() {
        var clock = Date(timeIntervalSince1970: 0)
        let reg = makeRegistry(ttl: 60, now: { clock })
        let nonce = reg.makeNonce()
        clock = Date(timeIntervalSince1970: 61)   // past the TTL
        XCTAssertFalse(reg.consume(nonce), "a nonce past its TTL is rejected")
    }

    func testNonceWithinTTLIsAccepted() {
        var clock = Date(timeIntervalSince1970: 0)
        let reg = makeRegistry(ttl: 60, now: { clock })
        let nonce = reg.makeNonce()
        clock = Date(timeIntervalSince1970: 59)
        XCTAssertTrue(reg.consume(nonce), "a nonce within its TTL is accepted")
    }

    func testIndependentNonces() {
        let reg = makeRegistry(ttl: 100, now: { Date(timeIntervalSince1970: 0) })
        let a = reg.makeNonce()
        let b = reg.makeNonce()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(reg.consume(b))
        XCTAssertTrue(reg.consume(a), "consuming one nonce does not invalidate another")
    }
}

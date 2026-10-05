//
//  AdapterSessionTests.swift
//  ModernTests
//
//  When a password manager adapter rejects a session, iTerm2 logs in again, unless the
//  session came straight from a login and never worked, in which case logging in again would
//  prompt for the master password in a loop. Several commands can be in flight, so a
//  rejection must be matched to the session the command was built with, not whatever session
//  is current when it fails.
//

import XCTest
@testable import iTerm2SharedARC

final class AdapterSessionTests: XCTestCase {
    func testSessionThatWorkedIsRenewedWhenRejected() {
        var session = AdapterSession()
        session.loggedIn(token: "A")
        let a = session.generation
        session.noteAccepted(generation: a)

        XCTAssertEqual(session.noteRejected(generation: a), .retry)
        XCTAssertNil(session.token, "The rejected session is dropped so the retry logs in")
    }

    func testFreshSessionRejectedBeforeWorkingStops() {
        var session = AdapterSession()
        session.loggedIn(token: "A")

        XCTAssertEqual(session.noteRejected(generation: session.generation), .stop)
        XCTAssertNil(session.token)
    }

    func testNonAuthFailureCountsAsAccepted() {
        // An item deleted elsewhere fails with “Not found.”, but the session got past the check.
        var session = AdapterSession()
        session.loggedIn(token: "A")
        let a = session.generation
        session.noteAccepted(generation: a)
        XCTAssertTrue(session.accepted)
        XCTAssertEqual(session.noteRejected(generation: a), .retry)
    }

    func testStaleRejectionAfterReloginKeepsNewSession() {
        var session = AdapterSession()
        session.loggedIn(token: "A")
        let a = session.generation
        session.noteAccepted(generation: a)

        // Two commands were built with A. The first is rejected, which renews the session.
        XCTAssertEqual(session.noteRejected(generation: a), .retry)
        session.loggedIn(token: "B")

        // The second, still carrying A, is rejected after the new login.
        XCTAssertEqual(session.noteRejected(generation: a), .retry, "Retry with the current session")
        XCTAssertEqual(session.token, "B", "The new session must survive a stale rejection")
        XCTAssertFalse(session.accepted)

        // And B can still prove itself and be renewed normally later.
        session.noteAccepted(generation: session.generation)
        XCTAssertTrue(session.accepted)
    }

    func testStaleAcceptanceDoesNotVouchForNewSession() {
        var session = AdapterSession()
        session.loggedIn(token: "A")
        let a = session.generation
        session.loggedIn(token: "B")

        session.noteAccepted(generation: a)
        XCTAssertFalse(session.accepted, "A success from the old session says nothing about the new one")
        XCTAssertEqual(session.noteRejected(generation: session.generation), .stop)
    }

    func testRejectionWithNoSessionRetries() {
        var session = AdapterSession()
        XCTAssertEqual(session.noteRejected(generation: nil), .retry)

        // Adapters without sessions return no token at login.
        session.loggedIn(token: nil)
        XCTAssertEqual(session.noteRejected(generation: session.generation), .retry)
    }

    func testUnknownGenerationIsTreatedAsCurrent() {
        var session = AdapterSession()
        session.loggedIn(token: "A")
        session.noteAccepted(generation: nil)
        XCTAssertTrue(session.accepted)
        XCTAssertEqual(session.noteRejected(generation: nil), .retry)
        XCTAssertNil(session.token)
    }

    func testClearForgetsSession() {
        var session = AdapterSession()
        session.loggedIn(token: "A")
        session.noteAccepted(generation: session.generation)
        session.clear()
        XCTAssertNil(session.token)
        XCTAssertFalse(session.accepted)
    }
}

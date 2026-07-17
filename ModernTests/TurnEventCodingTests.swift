//
//  TurnEventCodingTests.swift
//  iTerm2 ModernTests
//
//  TurnEvent is the explicit agent-turn-lifecycle signal carried on the Companion
//  wire (turn started / ended), decoupled from the typing-status spinner hint. It
//  must decode a value it does not recognize (a future revision's turn-event kind)
//  to .unknownFuture rather than throwing, because a known wire discriminator with
//  an undecodable body is NOT masked to .unsupported by the envelope: an unknown
//  TurnEvent would otherwise break the whole frame for an older peer.
//

import XCTest
@testable import iTerm2SharedARC

final class TurnEventCodingTests: XCTestCase {
    private struct Wrapper: Codable, Equatable {
        var e: TurnEvent
    }

    private func roundTrip(_ value: TurnEvent) throws -> TurnEvent {
        let data = try JSONEncoder().encode(Wrapper(e: value))
        return try JSONDecoder().decode(Wrapper.self, from: data).e
    }

    func testRoundTripStarted() throws {
        XCTAssertEqual(try roundTrip(.started), .started)
    }

    func testRoundTripEnded() throws {
        XCTAssertEqual(try roundTrip(.ended), .ended)
    }

    func testRoundTripUnknownFuture() throws {
        XCTAssertEqual(try roundTrip(.unknownFuture), .unknownFuture)
    }

    func testUnknownRawValueDecodesToUnknownFuture() throws {
        let json = Data(#"{"e":"pausedInFuture"}"#.utf8)
        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(decoded.e, .unknownFuture,
                       "an unrecognized turn-event value must degrade to .unknownFuture, not throw")
    }
}

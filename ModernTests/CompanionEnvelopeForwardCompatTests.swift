//
//  CompanionEnvelopeForwardCompatTests.swift
//  iTerm2 ModernTests
//
//  Forward compatibility: a message type a build does not recognize (sent by a
//  newer peer) must NOT fail the whole envelope decode. Swift's synthesized enum
//  Codable throws on an unknown case, so CompanionEnvelope decodes an unknown
//  payload into `.unsupported` while preserving the requestID, letting the
//  receiver reply with a correlated error instead of dropping the frame.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionEnvelopeForwardCompatTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
    }
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
    }

    func testUnknownClientMessageDecodesToUnsupportedKeepingRequestID() throws {
        // A payload case this build doesn't have (a future phone's message type).
        let json = #"{"requestID":42,"payload":{"someFutureMessage":{"x":1}}}"#.data(using: .utf8)!
        let env = try decoder().decode(ClientEnvelope.self, from: json)
        XCTAssertEqual(env.requestID, 42, "requestID must survive so the host can reply with an error")
        guard case .unsupported = env.payload else {
            return XCTFail("an unknown message type must decode to .unsupported")
        }
    }

    func testUnknownHostMessageDecodesToUnsupported() throws {
        let json = #"{"payload":{"brandNewEvent":{}}}"#.data(using: .utf8)!
        let env = try decoder().decode(HostEnvelope.self, from: json)
        XCTAssertNil(env.requestID)
        guard case .unsupported = env.payload else {
            return XCTFail("an unknown host message must decode to .unsupported")
        }
    }

    func testKnownMessageStillRoundTrips() throws {
        // The lenient decode must not weaken decoding of recognized messages.
        let original = ClientEnvelope(requestID: 7,
                                      payload: .hello(revision: 3, minimumPeer: 2))
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(ClientEnvelope.self, from: data)
        XCTAssertEqual(decoded.requestID, 7)
        guard case let .hello(revision, minimumPeer) = decoded.payload else {
            return XCTFail("expected .hello, got \(decoded.payload)")
        }
        XCTAssertEqual(revision, 3)
        XCTAssertEqual(minimumPeer, 2)
    }
}

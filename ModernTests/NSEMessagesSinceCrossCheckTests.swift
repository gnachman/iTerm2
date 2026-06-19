//
//  NSEMessagesSinceCrossCheckTests.swift
//  iTerm2 ModernTests
//
//  Drift guard for the NSE's slim messagesSince mirror. The slim decoder lives
//  in CompanionProtocol (not linkable into this target), so instead of decoding
//  with it directly we pin BOTH sides to the same wire vector: this test asserts
//  the PRODUCTION CompanionClientMessage/CompanionHostMessage enums encode to /
//  decode from the exact JSON shape that CompanionProtocol's
//  NSEMessagesSinceTests asserts the slim mirror produces/consumes. If either
//  side drifts from the vector, its test fails. (Same pattern as the
//  canonical-encoding cross-language vector shared with the JS worker.)
//
//  WireCoding uses JSONCoder with .millisecondsSince1970; this mirrors that
//  config so the bytes match what the real session emits.
//

import XCTest
@testable import iTerm2SharedARC

final class NSEMessagesSinceCrossCheckTests: XCTestCase {
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
    }
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
    }
    private func object(_ data: Data) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    func testProductionReplyMatchesWireVector() throws {
        let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
        let preview = CompanionMessagePreview(uniqueID: id, author: .agent, body: "hello")
        let host = CompanionHostMessage.messagesSince(chatName: "Chat A",
                                                      previews: [preview],
                                                      maxSeq: 7,
                                                      truncated: true)
        let produced = try object(encoder().encode(HostEnvelope(requestID: 42, payload: host)))
        let vector = try object("""
        {"requestID":42,"payload":{"messagesSince":{"chatName":"Chat A",
        "previews":[{"uniqueID":"550E8400-E29B-41D4-A716-446655440000","author":"agent","body":"hello"}],
        "maxSeq":7,"truncated":true}}}
        """.data(using: .utf8)!)
        XCTAssertEqual(produced, vector, "production reply must match the slim NSE wire vector")
    }

    func testProductionDecodesReplyVector() throws {
        let vector = """
        {"requestID":42,"payload":{"messagesSince":{"chatName":"Chat A","previews":[],"maxSeq":7,"truncated":false}}}
        """.data(using: .utf8)!
        let envelope = try decoder().decode(HostEnvelope.self, from: vector)
        guard case let .messagesSince(chatName, previews, maxSeq, truncated) = envelope.payload else {
            return XCTFail("expected .messagesSince, got \(envelope.payload)")
        }
        XCTAssertEqual(chatName, "Chat A")
        XCTAssertTrue(previews.isEmpty)
        XCTAssertEqual(maxSeq, 7)
        XCTAssertFalse(truncated)
    }

    func testProductionRequestMatchesWireVector() throws {
        let env = ClientEnvelope(requestID: 9, payload: .messagesSince(collapseToken: "tok", seq: 5, limit: 10))
        let produced = try object(encoder().encode(env))
        let vector = try object(
            #"{"requestID":9,"payload":{"messagesSince":{"collapseToken":"tok","seq":5,"limit":10}}}"#
                .data(using: .utf8)!)
        XCTAssertEqual(produced, vector, "production request must match the slim NSE wire vector")
    }
}

//
//  NSEMessagesSinceCrossCheckTests.swift
//  iTerm2 ModernTests
//
//  Drift guard for the NSE's slim messagesSince mirror. The slim decoder lives
//  in CompanionProtocol (not linkable into this target), so instead of decoding
//  with it directly both sides assert against ONE shared vector source,
//  CompanionWireVectors, compiled into this target and the package test target.
//  This test pins the PRODUCTION CompanionClientMessage/CompanionHostMessage
//  enums to those vectors; NSEMessagesSinceTests pins the slim mirror to the same
//  ones. A change to the wire shape must update CompanionWireVectors once, and
//  the side that wasn't updated fails - so the two can no longer drift.
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
        let id = try XCTUnwrap(UUID(uuidString: CompanionWireVectors.replyPreviewUUID))
        let preview = CompanionMessagePreview(uniqueID: id, author: .agent, body: "hello")
        let host = CompanionHostMessage.messagesSince(chatName: "Chat A",
                                                      previews: [preview],
                                                      maxSeq: 7,
                                                      truncated: true,
                                                      reset: false)
        let produced = try object(encoder().encode(HostEnvelope(requestID: 42, payload: host)))
        let vector = try XCTUnwrap(CompanionWireVectors.object(CompanionWireVectors.messagesSinceReply))
        XCTAssertEqual(produced, vector, "production reply must match the shared NSE wire vector")
    }

    func testProductionDecodesReplyVector() throws {
        let data = try XCTUnwrap(CompanionWireVectors.messagesSinceReply.data(using: .utf8))
        let envelope = try decoder().decode(HostEnvelope.self, from: data)
        guard case let .messagesSince(chatName, previews, maxSeq, truncated, reset) = envelope.payload else {
            return XCTFail("expected .messagesSince, got \(envelope.payload)")
        }
        XCTAssertEqual(chatName, "Chat A")
        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews.first?.body, "hello")
        XCTAssertEqual(maxSeq, 7)
        XCTAssertTrue(truncated)
        XCTAssertFalse(reset)
    }

    func testProductionRequestMatchesWireVector() throws {
        let env = ClientEnvelope(requestID: 9,
                                 payload: .messagesSince(collapseToken: "tok", seq: 5, limit: 10, nonce: "ab12"))
        let produced = try object(encoder().encode(env))
        let vector = try XCTUnwrap(CompanionWireVectors.object(CompanionWireVectors.messagesSinceRequest))
        XCTAssertEqual(produced, vector, "production request must match the shared NSE wire vector")
    }

    // The NSE encodes the request via the slim mirror; the mac decodes it via the
    // production enum. The mac must accept a request that carries the nonce...
    func testProductionDecodesRequestWithNonce() throws {
        let data = try XCTUnwrap(CompanionWireVectors.messagesSinceRequest.data(using: .utf8))
        let env = try decoder().decode(ClientEnvelope.self, from: data)
        guard case let .messagesSince(token, seq, limit, nonce) = env.payload else {
            return XCTFail("expected .messagesSince, got \(env.payload)")
        }
        XCTAssertEqual(token, "tok")
        XCTAssertEqual(seq, 5)
        XCTAssertEqual(limit, 10)
        XCTAssertEqual(nonce, "ab12")
    }

    // ...and a request that OMITS it (an older NSE, or a push that carried no
    // nonce), decoding the nonce as nil rather than failing.
    func testProductionDecodesRequestWithoutNonce() throws {
        let data = try XCTUnwrap(CompanionWireVectors.messagesSinceRequestNoNonce.data(using: .utf8))
        let env = try decoder().decode(ClientEnvelope.self, from: data)
        guard case let .messagesSince(_, _, _, nonce) = env.payload else {
            return XCTFail("expected .messagesSince, got \(env.payload)")
        }
        XCTAssertNil(nonce, "a nonce-less request must decode (cross-version), not throw")
    }
}

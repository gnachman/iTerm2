//
//  NSEMessagesSinceTests.swift
//  CompanionCore
//
//  The slim NSE request/reply mirror. These pin its own shape and its reply
//  classification (messages / error / other), and assert it produces/consumes
//  the SAME shared CompanionWireVectors that the production-side cross-check in
//  ModernTests uses - so the two cannot silently diverge.
//

import XCTest
@testable import CompanionProtocol

final class NSEMessagesSinceTests: XCTestCase {
    func testRequestMatchesSharedWireVector() throws {
        // The slim encoder must produce exactly the shared request vector that the
        // production enum is also pinned to.
        let data = try NSEMessagesSince.encodeRequest(requestID: 9, collapseToken: "tok",
                                                      seq: 5, limit: 10, nonce: "ab12")
        let produced = (try JSONSerialization.jsonObject(with: data)) as? NSDictionary
        XCTAssertEqual(produced, CompanionWireVectors.object(CompanionWireVectors.messagesSinceRequest))
    }

    func testDecodesSharedReplyVector() throws {
        let data = try XCTUnwrap(CompanionWireVectors.messagesSinceReply.data(using: .utf8))
        guard case let .messages(requestID, reply) = try NSEMessagesSince.decodeReply(data) else {
            return XCTFail("expected .messages")
        }
        XCTAssertEqual(requestID, 42)
        XCTAssertEqual(reply.chatName, "Chat A")
        XCTAssertEqual(reply.maxSeq, 7)
        XCTAssertTrue(reply.truncated)
        XCTAssertFalse(reply.reset)
        XCTAssertEqual(reply.previews.first?.author, "agent")
        XCTAssertEqual(reply.previews.first?.body, "hello")
        XCTAssertEqual(reply.previews.first?.uniqueID,
                       UUID(uuidString: CompanionWireVectors.replyPreviewUUID))
    }

    func testErrorReplyIsClassifiedAsError() throws {
        let json = #"{"requestID":1,"payload":{"error":{"code":"badRequest","message":"x"}}}"#.data(using: .utf8)!
        guard case let .error(requestID) = try NSEMessagesSince.decodeReply(json) else {
            return XCTFail("expected .error")
        }
        XCTAssertEqual(requestID, 1)
    }

    func testUnsolicitedFrameIsOther() throws {
        let json = #"{"payload":{"typingStatus":{"isTyping":true,"participant":"agent","chatID":"c"}}}"#
            .data(using: .utf8)!
        XCTAssertEqual(try NSEMessagesSince.decodeReply(json), .other)
    }

    func testEmptyPreviewsMessagesReply() throws {
        let json = #"{"requestID":2,"payload":{"messagesSince":{"chatName":"","previews":[],"maxSeq":0,"truncated":false,"reset":true}}}"#
            .data(using: .utf8)!
        guard case let .messages(_, reply) = try NSEMessagesSince.decodeReply(json) else {
            return XCTFail("expected .messages")
        }
        XCTAssertTrue(reply.previews.isEmpty)
        XCTAssertEqual(reply.maxSeq, 0)
        XCTAssertTrue(reply.reset)
    }
}

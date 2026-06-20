//
//  NSEMessagesSinceTests.swift
//  CompanionCore
//
//  The slim NSE request/reply mirror. These pin its own shape and its reply
//  classification (messages / error / other); a separate ModernTests cross-check
//  asserts it stays byte-compatible with the production enums.
//

import XCTest
@testable import CompanionProtocol

final class NSEMessagesSinceTests: XCTestCase {
    func testRequestEncodesExpectedShape() throws {
        let data = try NSEMessagesSince.encodeRequest(requestID: 9, collapseToken: "tok", seq: 5, limit: 10)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["requestID"] as? UInt64, 9)
        let payload = try XCTUnwrap(obj["payload"] as? [String: Any])
        let args = try XCTUnwrap(payload["messagesSince"] as? [String: Any])
        XCTAssertEqual(args["collapseToken"] as? String, "tok")
        XCTAssertEqual(args["seq"] as? Int, 5)
        XCTAssertEqual(args["limit"] as? Int, 10)
    }

    func testDecodesMessagesReply() throws {
        let json = """
        {"requestID":42,"payload":{"messagesSince":{"chatName":"Chat A",
        "previews":[{"uniqueID":"550E8400-E29B-41D4-A716-446655440000","author":"agent","body":"hi"}],
        "maxSeq":7,"truncated":true,"reset":false}}}
        """.data(using: .utf8)!
        guard case let .messages(requestID, reply) = try NSEMessagesSince.decodeReply(json) else {
            return XCTFail("expected .messages")
        }
        XCTAssertEqual(requestID, 42)
        XCTAssertEqual(reply.chatName, "Chat A")
        XCTAssertEqual(reply.maxSeq, 7)
        XCTAssertTrue(reply.truncated)
        XCTAssertFalse(reply.reset)
        XCTAssertEqual(reply.previews.first?.author, "agent")
        XCTAssertEqual(reply.previews.first?.body, "hi")
        XCTAssertEqual(reply.previews.first?.uniqueID,
                       UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000"))
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

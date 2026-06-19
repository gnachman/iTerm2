//
//  NSEMessagesSinceTests.swift
//  CompanionCore
//
//  The slim NSE request/reply mirror. These pin its own shape; a separate
//  cross-check (in the app's ModernTests) asserts it stays byte-compatible with
//  the production CompanionClientMessage/CompanionHostMessage enums.
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

    func testDecodeReply() throws {
        let json = """
        {"requestID":42,"payload":{"messagesSince":{"chatName":"Chat A",
        "previews":[{"uniqueID":"550E8400-E29B-41D4-A716-446655440000","author":"agent","body":"hi"}],
        "maxSeq":7,"truncated":true}}}
        """.data(using: .utf8)!
        let result = try XCTUnwrap(NSEMessagesSince.decodeReply(json))
        XCTAssertEqual(result.requestID, 42)
        XCTAssertEqual(result.reply.chatName, "Chat A")
        XCTAssertEqual(result.reply.maxSeq, 7)
        XCTAssertTrue(result.reply.truncated)
        XCTAssertEqual(result.reply.previews.count, 1)
        XCTAssertEqual(result.reply.previews[0].author, "agent")
        XCTAssertEqual(result.reply.previews[0].body, "hi")
        XCTAssertEqual(result.reply.previews[0].uniqueID,
                       UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000"))
    }

    func testNonMessagesSinceReplyDecodesAsNil() throws {
        let json = #"{"requestID":1,"payload":{"error":{"code":"badRequest","message":"x"}}}"#.data(using: .utf8)!
        XCTAssertNil(try NSEMessagesSince.decodeReply(json))
    }

    func testEmptyPreviewsReply() throws {
        let json = #"{"requestID":2,"payload":{"messagesSince":{"chatName":"","previews":[],"maxSeq":0,"truncated":false}}}"#
            .data(using: .utf8)!
        let result = try XCTUnwrap(NSEMessagesSince.decodeReply(json))
        XCTAssertTrue(result.reply.previews.isEmpty)
        XCTAssertEqual(result.reply.maxSeq, 0)
    }
}

//
//  NSESyncSinceTests.swift
//  CompanionCore
//
//  The slim NSE syncSince request/reply mirror. These pin its own shape and its
//  reply classification (sync / error / other), and assert it produces/consumes
//  the SAME shared CompanionWireVectors that the production-side cross-check in
//  ModernTests uses - so the two cannot silently diverge.
//

import XCTest
@testable import CompanionProtocol

final class NSESyncSinceTests: XCTestCase {
    func testRequestMatchesSharedWireVector() throws {
        let data = try NSESyncSince.encodeRequest(requestID: 9, messageSeq: 5,
                                                  alertSeq: 3, limit: 10, nonce: "ab12")
        let produced = (try JSONSerialization.jsonObject(with: data)) as? NSDictionary
        XCTAssertEqual(produced, CompanionWireVectors.object(CompanionWireVectors.syncSinceRequest))
    }

    func testRequestWithoutNonceMatchesSharedWireVector() throws {
        let data = try NSESyncSince.encodeRequest(requestID: 9, messageSeq: 5,
                                                  alertSeq: 3, limit: 10, nonce: nil)
        let produced = (try JSONSerialization.jsonObject(with: data)) as? NSDictionary
        XCTAssertEqual(produced, CompanionWireVectors.object(CompanionWireVectors.syncSinceRequestNoNonce))
    }

    func testDecodesSharedReplyVector() throws {
        let data = try XCTUnwrap(CompanionWireVectors.syncSinceReply.data(using: .utf8))
        guard case let .sync(requestID, reply) = try NSESyncSince.decodeReply(data) else {
            return XCTFail("expected .sync")
        }
        XCTAssertEqual(requestID, 42)
        XCTAssertEqual(reply.items.count, 2)
        XCTAssertEqual(reply.maxMessageSeq, 7)
        XCTAssertEqual(reply.maxAlertSeq, 4)
        XCTAssertTrue(reply.truncated)
        XCTAssertFalse(reply.messageReset)
        XCTAssertFalse(reply.alertReset)

        guard case let .message(message) = reply.items.first else {
            return XCTFail("expected first item to be a message")
        }
        XCTAssertEqual(message.chatID, "c1")
        XCTAssertEqual(message.chatName, "Chat A")
        XCTAssertEqual(message.author, "agent")
        XCTAssertEqual(message.body, "hello")
        XCTAssertEqual(message.seq, 7)
        XCTAssertEqual(message.uniqueID, UUID(uuidString: CompanionWireVectors.replyPreviewUUID))

        guard case let .alert(alert) = reply.items.last else {
            return XCTFail("expected last item to be an alert")
        }
        XCTAssertEqual(alert.threadKey, "sess-1")
        XCTAssertEqual(alert.title, "Mark Set")
        XCTAssertEqual(alert.body, "done")
        XCTAssertEqual(alert.seq, 4)
        XCTAssertEqual(alert.alertID, UUID(uuidString: CompanionWireVectors.replyAlertUUID))
    }

    func testErrorReplyIsClassifiedAsError() throws {
        let json = #"{"requestID":1,"payload":{"error":{"code":"badRequest","message":"x"}}}"#.data(using: .utf8)!
        guard case let .error(requestID) = try NSESyncSince.decodeReply(json) else {
            return XCTFail("expected .error")
        }
        XCTAssertEqual(requestID, 1)
    }

    func testUnsolicitedFrameIsOther() throws {
        let json = #"{"payload":{"typingStatus":{"isTyping":true,"participant":"agent","chatID":"c"}}}"#
            .data(using: .utf8)!
        XCTAssertEqual(try NSESyncSince.decodeReply(json), .other)
    }

    func testEmptyItemsSyncReply() throws {
        let json = #"{"requestID":2,"payload":{"syncSince":{"items":[],"maxMessageSeq":0,"maxAlertSeq":0,"messageReset":true,"alertReset":false,"truncated":false}}}"#
            .data(using: .utf8)!
        guard case let .sync(_, reply) = try NSESyncSince.decodeReply(json) else {
            return XCTFail("expected .sync")
        }
        XCTAssertTrue(reply.items.isEmpty)
        XCTAssertEqual(reply.maxMessageSeq, 0)
        XCTAssertTrue(reply.messageReset)
    }
}

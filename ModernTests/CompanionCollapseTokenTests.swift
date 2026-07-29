//
//  CompanionCollapseTokenTests.swift
//  iTerm2 ModernTests
//
//  The per-chat APNs collapse id (HMAC-SHA256(roomSecret, chatID)) used by the
//  relay-push feature. The same algorithm runs on the Mac and the phone, so
//  these properties (determinism, per-chat/per-secret distinctness, length) are
//  what make the token usable as both a coalescing key and a watermark key.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionCollapseTokenTests: XCTestCase {
    private let secret = Data((0..<32).map { UInt8($0) })

    func testDeterministic() {
        let a = CompanionCollapseToken.make(roomSecret: secret, chatID: "chat-1")
        let b = CompanionCollapseToken.make(roomSecret: secret, chatID: "chat-1")
        XCTAssertEqual(a, b)
    }

    func testDistinctPerChat() {
        let a = CompanionCollapseToken.make(roomSecret: secret, chatID: "chat-1")
        let b = CompanionCollapseToken.make(roomSecret: secret, chatID: "chat-2")
        XCTAssertNotEqual(a, b)
    }

    func testDistinctPerSecret() {
        let other = Data((0..<32).map { _ in UInt8(0xAB) })
        let a = CompanionCollapseToken.make(roomSecret: secret, chatID: "chat-1")
        let b = CompanionCollapseToken.make(roomSecret: other, chatID: "chat-1")
        XCTAssertNotEqual(a, b)
    }

    func testFitsCollapseIdLimit() {
        let token = CompanionCollapseToken.make(roomSecret: secret, chatID: "chat-1")
        XCTAssertEqual(token.count, 32)              // 16 bytes hex
        XCTAssertLessThanOrEqual(token.utf8.count, 64) // APNs collapse-id cap
        XCTAssertTrue(token.allSatisfy { $0.isHexDigit })
    }
}

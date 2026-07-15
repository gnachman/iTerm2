//
//  ChatBindingReferenceTests.swift
//  iTerm2 ModernTests
//
//  A chat's terminal/browser binding is stored as a single "session reference"
//  that is either the session's stableID (new/backfilled bindings) or a legacy
//  guid. isLinked(toReferenceIn:) is what lets a session-to-chat lookup match
//  either form, so it is the piece that makes the guid->stableID migration and
//  reload-durability transparent to callers.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatBindingReferenceTests: XCTestCase {
    func testMatchesStableIDReference() {
        var chat = Chat(title: "t", permissions: "")
        chat.terminalSessionGuid = "ptys_9QK3ZM7WX4VBT"
        XCTAssertTrue(chat.isLinked(toReferenceIn: ["ptys_9QK3ZM7WX4VBT", "01234567-89ab-cdef-0123-456789abcdef"]))
        XCTAssertFalse(chat.isLinked(toReferenceIn: ["01234567-89ab-cdef-0123-456789abcdef"]))
    }

    func testMatchesLegacyGuidReference() {
        var chat = Chat(title: "t", permissions: "")
        chat.browserSessionGuid = "01234567-89ab-cdef-0123-456789abcdef"
        XCTAssertTrue(chat.isLinked(toReferenceIn: ["01234567-89ab-cdef-0123-456789abcdef"]))
        XCTAssertFalse(chat.isLinked(toReferenceIn: ["ptys_9QK3ZM7WX4VBT"]))
    }

    func testUnboundChatMatchesNothing() {
        let chat = Chat(title: "t", permissions: "")
        XCTAssertFalse(chat.isLinked(toReferenceIn: ["anything", "ptys_9QK3ZM7WX4VBT"]))
    }
}

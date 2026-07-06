//
//  ChatServiceQueueTests.swift
//  iTerm2 ModernTests
//
//  Unit coverage for ChatService.queueInsertionIndex, the pure helper that
//  decides where a newly-enqueued message lands in the pending-turn queue.
//  A human-typed message must pre-empt queued watcher-event turns (so a user
//  can interrupt a long orchestration loop) without ever displacing the
//  in-flight head at index 0. Watcher events and everything else keep FIFO.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatServiceQueueTests: XCTestCase {
    private func userMessage(_ text: String = "hi") -> Message {
        Message(chatID: "c",
                author: .user,
                content: .plainText(text, context: nil),
                sentDate: Date(),
                uniqueID: UUID())
    }

    private func watcherMessage(_ detail: String = "idle") -> Message {
        let update = StatusUpdate(watcherID: "w",
                                  workgroupID: "wg",
                                  workgroupName: "Claude Code",
                                  roleID: "builtin.claudeCode.review",
                                  roleName: "Code Review",
                                  reason: .stateReached,
                                  stateReached: "idle",
                                  timestamp: Date(),
                                  detail: detail)
        return Message(chatID: "c",
                       author: .user,
                       content: .watcherEvent(update),
                       sentDate: Date(),
                       uniqueID: UUID())
    }

    // An empty queue: anything appends at 0 (and the caller starts a turn).
    func testEmptyQueueAppends() {
        XCTAssertEqual(ChatService.queueInsertionIndex(for: userMessage(), in: []), 0)
        XCTAssertEqual(ChatService.queueInsertionIndex(for: watcherMessage(), in: []), 0)
    }

    // A user message jumps ahead of queued watcher events but never past the
    // in-flight head (index 0), even when the head is itself a watcher event.
    func testUserMessageJumpsAheadOfWatcherBacklog() {
        let queue = [watcherMessage("head"), watcherMessage("a"), watcherMessage("b")]
        XCTAssertEqual(ChatService.queueInsertionIndex(for: userMessage(), in: queue), 1)
    }

    // With no watcher events queued behind the head, a user message appends
    // (ordinary FIFO): it waits for the in-flight turn, matching the existing
    // "user message during in-flight tool waits for the first turn" invariant.
    func testUserMessageAppendsWhenNoWatcherBacklog() {
        let queue = [userMessage("head")]
        XCTAssertEqual(ChatService.queueInsertionIndex(for: userMessage("new"), in: queue), 1)
    }

    // User FIFO is preserved: a second user message lands behind an earlier
    // queued user message but still ahead of watcher events.
    func testUserMessagePreservesUserFIFOAheadOfWatchers() {
        let queue = [userMessage("head"), userMessage("queuedUser"), watcherMessage("w")]
        XCTAssertEqual(ChatService.queueInsertionIndex(for: userMessage("new"), in: queue), 2)
    }

    // Watcher events never jump; they always append and keep arrival order.
    func testWatcherEventAlwaysAppends() {
        let queue = [userMessage("head"), watcherMessage("a")]
        XCTAssertEqual(ChatService.queueInsertionIndex(for: watcherMessage("b"), in: queue), 2)
    }
}

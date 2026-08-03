//
//  ChatBrokerTurnLifecycleTests.swift
//  iTerm2 ModernTests
//
//  ChatBroker.publish(turnEvent:) is the fan-out for the explicit agent-turn
//  boundary: it updates TurnStatusModel (so a mid-turn subscribe can seed the
//  phone) and delivers a .turnLifecycle update to the chat's subscribers. This is
//  the producer mechanism the ChatService emit sites (agentWorking / finishTurn)
//  call; those turn boundaries are exercised end-to-end by the live harness.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ChatBrokerTurnLifecycleTests: XCTestCase {
    private func makeBroker() throws -> ChatBroker {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        let listModel = try XCTUnwrap(ChatListModel(database: db))
        return ChatBroker(listModel: listModel)
    }

    // publish(turnEvent:) writes the process-wide TurnStatusModel.instance singleton.
    // Track every chatID a test marks in-flight and clear it in tearDown so state
    // doesn't leak across tests (setup/teardown symmetry).
    private var touchedChatIDs: [String] = []

    private func freshChatID() -> String {
        let id = UUID().uuidString
        touchedChatIDs.append(id)
        return id
    }

    override func tearDown() {
        for id in touchedChatIDs {
            TurnStatusModel.instance.set(inProgress: false, chatID: id)
        }
        touchedChatIDs.removeAll()
        super.tearDown()
    }

    func testPublishTurnStartedFansOutAndSetsModel() throws {
        let broker = try makeBroker()
        let chatID = freshChatID()
        var received: [TurnEvent] = []
        let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            if case let .turnLifecycle(event) = update { received.append(event) }
        }
        defer { sub.unsubscribe() }

        broker.publish(turnEvent: .started, toChatID: chatID)
        XCTAssertEqual(received, [.started], "a turn event must reach the chat's subscriber")
        XCTAssertTrue(TurnStatusModel.instance.inProgress(chatID: chatID),
                      "publishing .started must mark the turn in flight")
    }

    func testPublishTurnEndedClearsModel() throws {
        let broker = try makeBroker()
        let chatID = freshChatID()
        // Assert the TRANSITION, not just the terminal value: a fresh chatID starts
        // absent (false), so checking only the final false would pass even if
        // publish(turnEvent:) never touched the model. Prove .started sets it true
        // first, so .ended clearing it is load-bearing.
        broker.publish(turnEvent: .started, toChatID: chatID)
        XCTAssertTrue(TurnStatusModel.instance.inProgress(chatID: chatID),
                      ".started must mark the turn in flight before .ended can clear it")
        broker.publish(turnEvent: .ended, toChatID: chatID)
        XCTAssertFalse(TurnStatusModel.instance.inProgress(chatID: chatID),
                       "publishing .ended must clear the in-flight state")
    }

    func testTurnEventOnlyReachesMatchingChat() throws {
        // Subscribe BOTH the target chat and another chat on the SAME broker, so the
        // assertion proves delivery AND filtering: an inverted/never-true chatID
        // filter would fail the matching-received check, not silently pass an
        // empty-vs-empty comparison.
        let broker = try makeBroker()
        let chatID = freshChatID()
        let otherID = freshChatID()
        var matching: [TurnEvent] = []
        var other: [TurnEvent] = []
        let subMatching = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            if case let .turnLifecycle(event) = update { matching.append(event) }
        }
        let subOther = broker.subscribe(chatID: otherID, registrationProvider: nil) { update in
            if case let .turnLifecycle(event) = update { other.append(event) }
        }
        defer { subMatching.unsubscribe(); subOther.unsubscribe() }

        broker.publish(turnEvent: .started, toChatID: chatID)
        XCTAssertEqual(matching, [.started], "the chat's own subscriber must receive the event")
        XCTAssertTrue(other.isEmpty, "a subscriber to a different chat must not receive it")
    }
}

//
//  OrchestratorEnableKeepsTimerTests.swift
//  iTerm2 ModernTests
//
//  Enabling orchestration tears down the chat's dispatcher, which owns the
//  task that fires a pending timer. The timer stays persisted, so a fresh
//  dispatcher must be built right away to re-arm it; otherwise it misses its
//  deadline until the next orchestration tool call (QA finding F-278).
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorEnableKeepsTimerTests: XCTestCase {
    private var listModel: ChatListModel!
    private var broker: ChatBroker!
    private var chatID: String!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-enable-timer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        listModel = try XCTUnwrap(ChatListModel(database: db))
        let chat = Chat(title: "t", permissions: "")
        try listModel.add(chat: chat)
        chatID = chat.id
        broker = ChatBroker(listModel: listModel)
    }

    private func pendingTimer(id: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: "",
                         workgroupID: "session:timer", workgroupName: "Timer",
                         roleID: "timer", roleName: "Timer",
                         targetState: nil, registeredAt: Date(),
                         mode: .timer, condition: nil, notifyUser: nil,
                         fireDate: Date().addingTimeInterval(3600), note: nil)
    }

    func testEnablingOrchestrationReArmsPendingTimer() throws {
        try listModel.setWatchers([pendingTimer(id: "t")], forChatID: chatID)
        let client = OrchestratorClient.makeForTesting(broker: broker)
        let before = client.dispatcher(forChatID: chatID)
        addTeardownBlock { @MainActor in before.tearDown() }

        try client.enableOrchestration(forChatID: chatID)

        XCTAssertEqual(listModel.chat(id: chatID)?.orchestrationEnabled, true)
        XCTAssertEqual(listModel.watchers(forChatID: chatID).map(\.watcherID), ["t"])
        let after = try XCTUnwrap(client.existingDispatcherForTesting(chatID: chatID),
                                  "a chat with a pending timer needs a live dispatcher after enable")
        addTeardownBlock { @MainActor in after.tearDown() }
        XCTAssertFalse(after === before, "the old dispatcher is torn down and replaced")
        // The test host has finished launching, so the shared restoration
        // gate is open and the new dispatcher reconciles (arms) immediately.
        XCTAssertTrue(SessionRestorationGate.shared.isReady)
        XCTAssertNotNil(after.timerTaskForTesting(watcherID: "t"),
                        "the pending timer must be re-armed after enable")
    }

    func testEnablingOrchestrationWithNothingPendingBuildsNoDispatcher() throws {
        let client = OrchestratorClient.makeForTesting(broker: broker)

        try client.enableOrchestration(forChatID: chatID)

        XCTAssertEqual(listModel.chat(id: chatID)?.orchestrationEnabled, true)
        XCTAssertNil(client.existingDispatcherForTesting(chatID: chatID))
    }
}

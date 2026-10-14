//
//  OrchestratorTimerUnlinkTests.swift
//  iTerm2 ModernTests
//
//  A register_timer timer targets no session (the tool description says so),
//  so unlinking a session-bound chat from its terminal session, or closing
//  that session (which unlinks the chat), must not cancel it. Watches that
//  observe the session are orphaned by the unlink and are still dropped.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorTimerUnlinkTests: XCTestCase {
    private var listModel: ChatListModel!
    private var broker: ChatBroker!
    private var chatID: String!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-timer-unlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        listModel = try XCTUnwrap(ChatListModel(database: db))
        // A session-bound chat (orchestration off), as opened from
        // Session > Open AI Chat.
        let chat = Chat(title: "t", permissions: "")
        try listModel.add(chat: chat)
        chatID = chat.id
        broker = ChatBroker(listModel: listModel)
    }

    private func sessionWatch(id: String, sessionRef: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: sessionRef,
                         workgroupID: "session:\(sessionRef)", workgroupName: "S",
                         roleID: "role-\(id)", roleName: "S",
                         targetState: .idle, registeredAt: Date(),
                         mode: .tabStatus, condition: nil, notifyUser: nil,
                         fireDate: nil, note: nil)
    }

    // Far enough out that it never fires during the test.
    private func pendingTimer(id: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: "",
                         workgroupID: "session:timer", workgroupName: "Timer",
                         roleID: "timer", roleName: "Timer",
                         targetState: nil, registeredAt: Date(),
                         mode: .timer, condition: nil, notifyUser: nil,
                         fireDate: Date().addingTimeInterval(3600), note: "check deploy")
    }

    private func makeDispatcher(session: PTYSession) -> OrchestratorDispatcher {
        let ref = session.stableID
        let dispatcher = OrchestratorDispatcher(chatID: chatID,
                                                broker: broker,
                                                typedInput: OrchestratorTypedInputStore(),
                                                restorationGate: SessionRestorationGate(ready: true),
                                                sessionLookup: { $0 == ref ? session : nil },
                                                quitWillRestoreSessions: { _ in false })
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        return dispatcher
    }

    private func persistedWatcherIDs() -> [String] {
        listModel.watchers(forChatID: chatID).map(\.watcherID)
    }

    func testUnlinkKeepsPendingTimerArmedAndDropsSessionWatch() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        try listModel.setWatchers([sessionWatch(id: "w", sessionRef: session.stableID),
                                   pendingTimer(id: "t")],
                                  forChatID: chatID)
        let dispatcher = makeDispatcher(session: session)
        let armed = try XCTUnwrap(dispatcher.timerTaskForTesting(watcherID: "t"),
                                  "reconcile should arm the persisted timer")

        dispatcher.cancelWatchersOnUnlink()

        XCTAssertEqual(persistedWatcherIDs(), ["t"],
                       "the timer targets no session, so unlinking must keep it; the session watch is orphaned")
        let stillArmed = try XCTUnwrap(dispatcher.timerTaskForTesting(watcherID: "t"),
                                       "the timer's fire task must survive the unlink")
        XCTAssertFalse(stillArmed.isCancelled)
        XCTAssertFalse(armed.isCancelled)
    }

    // Closing the linked session drops its watch (with a watcherDropped event)
    // and then unlinks the chat (ChatViewController.sessionWillTerminate). The
    // timer must survive both.
    func testLinkedSessionCloseKeepsPendingTimer() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        try listModel.setWatchers([sessionWatch(id: "w", sessionRef: session.stableID),
                                   pendingTimer(id: "t")],
                                  forChatID: chatID)
        let dispatcher = makeDispatcher(session: session)

        NotificationCenter.default.post(name: NSNotification.Name.iTermSessionWillTerminate,
                                        object: session)
        RunLoop.main.run(mode: .default, before: .distantPast)
        // The dispatcher's own close handler drops only the watch on the gone
        // session.
        XCTAssertEqual(persistedWatcherIDs(), ["t"])
        XCTAssertNotNil(dispatcher.timerTaskForTesting(watcherID: "t"))
        dispatcher.cancelWatchersOnUnlink()

        XCTAssertEqual(persistedWatcherIDs(), ["t"])
        let task = try XCTUnwrap(dispatcher.timerTaskForTesting(watcherID: "t"))
        XCTAssertFalse(task.isCancelled)
    }

    // With no live dispatcher the client clears the persisted set directly;
    // that path must keep timers too.
    func testClientUnlinkWithoutDispatcherKeepsPersistedTimer() throws {
        try listModel.setWatchers([sessionWatch(id: "w", sessionRef: "some-session"),
                                   pendingTimer(id: "t")],
                                  forChatID: chatID)
        let client = OrchestratorClient.makeForTesting(broker: broker)

        client.cancelWatchers(forChatID: chatID)

        XCTAssertEqual(persistedWatcherIDs(), ["t"])
    }
}

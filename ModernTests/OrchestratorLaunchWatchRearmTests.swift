//
//  OrchestratorLaunchWatchRearmTests.swift
//  iTerm2 ModernTests
//
//  A chat whose only persisted watcher is a session watch (no timer) must get
//  a dispatcher at launch like a timer-bearing chat, or its watch stays
//  dormant until something touches the chat (QA finding F-133). And Stop must
//  cancel persisted watchers even when the chat has no dispatcher, or the
//  watch fires later and starts the turn the user tried to stop (F-279).
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorLaunchWatchRearmTests: XCTestCase {
    private var listModel: ChatListModel!
    private var broker: ChatBroker!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-launch-rearm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        listModel = try XCTUnwrap(ChatListModel(database: db))
        broker = ChatBroker(listModel: listModel)
    }

    private func addChat() throws -> String {
        let chat = Chat(title: "t", permissions: "")
        try listModel.add(chat: chat)
        return chat.id
    }

    private func sessionWatch(id: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: "no-such-session",
                         workgroupID: "session:no-such-session", workgroupName: "S",
                         roleID: "role-\(id)", roleName: "S",
                         targetState: .idle, registeredAt: Date(),
                         mode: .tabStatus, condition: nil, notifyUser: nil,
                         fireDate: nil, note: nil)
    }

    private func pendingTimer(id: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: "",
                         workgroupID: "session:timer", workgroupName: "Timer",
                         roleID: "timer", roleName: "Timer",
                         targetState: nil, registeredAt: Date(),
                         mode: .timer, condition: nil, notifyUser: nil,
                         fireDate: Date().addingTimeInterval(3600), note: nil)
    }

    private func sessionWatch(id: String, sessionRef: String) -> WorkgroupWatcher {
        var watcher = sessionWatch(id: id)
        watcher.sessionGUID = sessionRef
        return watcher
    }

    // F-133: a watch-only chat whose watched session was restored is resumed
    // at launch, not just timer chats.
    func testLaunchResumesWatchOnlyChatsWhoseSessionWasRestored() throws {
        let restored = try addChat()
        try listModel.setWatchers([sessionWatch(id: "w1", sessionRef: "restored")], forChatID: restored)
        let timerChat = try addChat()
        try listModel.setWatchers([pendingTimer(id: "t")], forChatID: timerChat)
        _ = try addChat()

        let watchChatIDs = OrchestratorClient.chatIDsWithResumableWatches(listModel) { $0 == "restored" }

        XCTAssertEqual(watchChatIDs, [restored])
        XCTAssertEqual(OrchestratorClient.chatIDsWithPersistedTimers(listModel), [timerChat])
    }

    // A watch-only chat whose watched sessions are all gone is left for the
    // user to open: resuming it would drop each watch with a status_update
    // that starts an unattended agent turn at launch.
    func testLaunchLeavesWatchOnlyChatsWithNoRestoredSessionAlone() throws {
        let gone = try addChat()
        try listModel.setWatchers([sessionWatch(id: "w", sessionRef: "gone")], forChatID: gone)

        XCTAssertEqual(OrchestratorClient.chatIDsWithResumableWatches(listModel) { _ in false }, [])
    }

    // An orchestration chat's tmux pane watch is held for reattach rather than
    // dropped, so it is resumed even though its old session is gone.
    func testLaunchResumesOrchestrationChatWithTmuxPaneWatch() throws {
        let chatID = try addChat()
        try listModel.setOrchestrationEnabled(true, forChatID: chatID)
        var watch = sessionWatch(id: "w", sessionRef: "gone")
        watch.tmuxPane = TmuxPaneIdentity(tmuxSessionGUID: "tmux", pane: 1)
        try listModel.setWatchers([watch], forChatID: chatID)

        XCTAssertEqual(OrchestratorClient.chatIDsWithResumableWatches(listModel) { _ in false }, [chatID])
    }

    // A chat with one restored watch and one whose session is gone would drop
    // the second at reconcile and start an agent turn, so it waits too.
    func testLaunchLeavesPartlyRestoredWatchChatsAlone() throws {
        let chatID = try addChat()
        try listModel.setWatchers([sessionWatch(id: "w1", sessionRef: "restored"),
                                   sessionWatch(id: "w2", sessionRef: "gone")],
                                  forChatID: chatID)

        XCTAssertEqual(OrchestratorClient.chatIDsWithResumableWatches(listModel) { $0 == "restored" }, [])
    }

    // A session-bound chat's tmux pane watch is dropped at reconcile rather
    // than held, so it is not resumed.
    func testLaunchLeavesSessionBoundChatWithGoneTmuxWatchAlone() throws {
        let chatID = try addChat()
        var watch = sessionWatch(id: "w", sessionRef: "gone")
        watch.tmuxPane = TmuxPaneIdentity(tmuxSessionGUID: "tmux", pane: 1)
        try listModel.setWatchers([watch], forChatID: chatID)

        XCTAssertEqual(OrchestratorClient.chatIDsWithResumableWatches(listModel) { _ in false }, [])
    }

    // With a live dispatcher both it and the client handle Stop; the second
    // call finds nothing to cancel, so exactly one notice is published.
    func testStopWithLiveDispatcherPublishesOneNotice() throws {
        let chatID = try addChat()
        let timer = pendingTimer(id: "t")
        try listModel.setWatchers([timer], forChatID: chatID)
        let client = OrchestratorClient.makeForTesting(broker: broker)
        let dispatcher = client.dispatcher(forChatID: chatID)
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        let expectedNotice = try XCTUnwrap(
            OrchestratorDispatcher.cancelledWatchersNotice([timer], cause: .stop))
        var notices = [String]()
        let observer = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            guard case let .delivery(message, _, _) = update,
                  case .clientLocal(let local) = message.content,
                  case .notice(let text) = local.action else { return }
            MainActor.assumeIsolated {
                notices.append(text)
            }
        }
        defer { observer.unsubscribe() }

        try broker.publishMessageFromUser(chatID: chatID, content: .userCommand(.stop))
        // Both handlers hop to the main actor in a Task. Wait until every
        // already-enqueued main-actor task has run.
        let drained = expectation(description: "main actor drained")
        Task { @MainActor in
            await Task.yield()
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10)
        RunLoop.main.run(mode: .default, before: Date())

        XCTAssertEqual(notices, [expectedNotice])
        XCTAssertTrue(listModel.watchers(forChatID: chatID).isEmpty)
    }

    // F-279: Stop through the broker on a chat with a persisted watch and no
    // dispatcher cancels the watch and tells the user.
    func testStopWithoutDispatcherCancelsPersistedWatch() throws {
        let chatID = try addChat()
        let watch = sessionWatch(id: "w")
        try listModel.setWatchers([watch], forChatID: chatID)
        let client = OrchestratorClient.makeForTesting(broker: broker)
        let expectedNotice = try XCTUnwrap(
            OrchestratorDispatcher.cancelledWatchersNotice([watch], cause: .stop))
        let noticeArrived = expectation(description: "notice published")
        var notices = [String]()
        let observer = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            guard case let .delivery(message, _, _) = update,
                  case .clientLocal(let local) = message.content,
                  case .notice(let text) = local.action else { return }
            MainActor.assumeIsolated {
                notices.append(text)
            }
            noticeArrived.fulfill()
        }
        defer { observer.unsubscribe() }

        try broker.publishMessageFromUser(chatID: chatID, content: .userCommand(.stop))
        wait(for: [noticeArrived], timeout: 10)

        XCTAssertEqual(notices, [expectedNotice])
        XCTAssertTrue(listModel.watchers(forChatID: chatID).isEmpty)
        withExtendedLifetime(client) {}
    }
}

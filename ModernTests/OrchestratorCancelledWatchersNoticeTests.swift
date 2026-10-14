//
//  OrchestratorCancelledWatchersNoticeTests.swift
//  iTerm2 ModernTests
//
//  Stop and Disable Orchestration cancel a chat's pending timers and watches
//  without telling the model (no status_update, no turn). The user is told
//  instead, with one chat notice counting what was cancelled, and nothing is
//  published when nothing was pending.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorCancelledWatchersNoticeTests: XCTestCase {
    private var listModel: ChatListModel!
    private var broker: ChatBroker!
    private var chatID: String!
    private var published: [Message] = []
    private var subscription: ChatBroker.Subscription?

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-cancel-notice-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        listModel = try XCTUnwrap(ChatListModel(database: db))
        let chat = Chat(title: "t", permissions: "")
        try listModel.add(chat: chat)
        chatID = chat.id
        broker = ChatBroker(listModel: listModel)
        published = []
        // The broker's fan-out is synchronous, so every message published
        // during a call is recorded before the call returns.
        subscription = broker.subscribe(chatID: chatID, registrationProvider: nil) { [weak self] update in
            guard case let .delivery(message, _, _) = update else { return }
            MainActor.assumeIsolated {
                self?.published.append(message)
            }
        }
    }

    override func tearDown() {
        subscription?.unsubscribe()
        subscription = nil
        super.tearDown()
    }

    private func sessionWatch(id: String, sessionRef: String = "no-such-session") -> WorkgroupWatcher {
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

    private func makeDispatcher(session: PTYSession? = nil) -> OrchestratorDispatcher {
        let ref = session?.stableID
        let dispatcher = OrchestratorDispatcher(chatID: chatID,
                                                broker: broker,
                                                typedInput: OrchestratorTypedInputStore(),
                                                restorationGate: SessionRestorationGate(ready: true),
                                                sessionLookup: { $0 == ref ? session : nil },
                                                quitWillRestoreSessions: { _ in false })
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        return dispatcher
    }

    // Every published message must be a client-local notice: anything else
    // (a status_update, a watcher event, a user message) would reach the model
    // or start a turn.
    private func publishedNotices(file: StaticString = #filePath,
                                  line: UInt = #line) -> [String] {
        return published.compactMap { message in
            guard message.author == .agent,
                  case .clientLocal(let local) = message.content,
                  case .notice(let text) = local.action else {
                XCTFail("unexpected non-notice message: \(message.content)", file: file, line: line)
                return nil
            }
            return text
        }
    }

    private func expected(_ watchers: [WorkgroupWatcher],
                          _ cause: OrchestratorDispatcher.WatcherCancellationCause) throws -> String {
        try XCTUnwrap(OrchestratorDispatcher.cancelledWatchersNotice(watchers, cause: cause))
    }

    // MARK: - Notice text

    func testNoticeTextCountsTimersAndWatches() {
        let oneTimer = [pendingTimer(id: "t")]
        let twoTimers = [pendingTimer(id: "t1"), pendingTimer(id: "t2")]
        let oneWatch = [sessionWatch(id: "w")]
        XCTAssertNil(OrchestratorDispatcher.cancelledWatchersNotice([], cause: .stop))
        XCTAssertNil(OrchestratorDispatcher.cancelledWatchersNotice([], cause: .disableOrchestration))
        // These assertions read the English source strings, so run them only
        // when the test host resolves strings in English.
        guard Bundle.main.preferredLocalizations.first?.hasPrefix("en") ?? true else { return }
        XCTAssertEqual(OrchestratorDispatcher.cancelledWatchersNotice(oneTimer, cause: .stop),
                       "Stop cancelled 1 pending timer.")
        XCTAssertEqual(OrchestratorDispatcher.cancelledWatchersNotice(twoTimers, cause: .stop),
                       "Stop cancelled 2 pending timers.")
        XCTAssertEqual(OrchestratorDispatcher.cancelledWatchersNotice(oneWatch, cause: .stop),
                       "Stop cancelled 1 pending watch.")
        XCTAssertEqual(OrchestratorDispatcher.cancelledWatchersNotice(twoTimers + oneWatch, cause: .stop),
                       "Stop cancelled 2 pending timers and 1 watch.")
        XCTAssertEqual(OrchestratorDispatcher.cancelledWatchersNotice(oneTimer, cause: .disableOrchestration),
                       "Disabling orchestration cancelled 1 pending timer.")
        XCTAssertEqual(OrchestratorDispatcher.cancelledWatchersNotice(oneWatch + oneWatch, cause: .disableOrchestration),
                       "Disabling orchestration cancelled 2 pending watches.")
        XCTAssertEqual(OrchestratorDispatcher.cancelledWatchersNotice(oneTimer + oneWatch, cause: .disableOrchestration),
                       "Disabling orchestration cancelled 1 pending timer and 1 watch.")
    }

    // MARK: - Stop

    func testStopWithPendingTimerPublishesOneNotice() throws {
        let timer = pendingTimer(id: "t")
        try listModel.setWatchers([timer], forChatID: chatID)
        let dispatcher = makeDispatcher()
        XCTAssertNotNil(dispatcher.timerTaskForTesting(watcherID: "t"),
                        "reconcile should arm the persisted timer")

        dispatcher.userDidStop()

        XCTAssertEqual(publishedNotices(), [try expected([timer], .stop)])
        XCTAssertTrue(listModel.watchers(forChatID: chatID).isEmpty)
    }

    func testStopWithTimersAndWatchesCountsBoth() throws {
        // Orchestration mode, so the session watch needs no per-chat Check
        // Terminal State permission to survive reconcile.
        try listModel.setOrchestrationEnabled(true, forChatID: chatID)
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let cancelled = [pendingTimer(id: "t1"), pendingTimer(id: "t2"),
                         sessionWatch(id: "w", sessionRef: session.stableID)]
        try listModel.setWatchers(cancelled, forChatID: chatID)
        let dispatcher = makeDispatcher(session: session)
        XCTAssertEqual(listModel.watchers(forChatID: chatID).count, 3,
                       "reconcile should keep all three watchers")

        dispatcher.userDidStop()

        XCTAssertEqual(publishedNotices(), [try expected(cancelled, .stop)])
    }

    func testStopWithNothingPendingPublishesNothing() throws {
        let dispatcher = makeDispatcher()

        dispatcher.userDidStop()

        XCTAssertEqual(published.count, 0)
    }

    // Stop arrives as a user .stop message through the broker; the dispatcher
    // handles it after a main-actor hop, so wait for the notice to arrive.
    func testStopThroughBrokerPublishesNotice() throws {
        let timer = pendingTimer(id: "t")
        try listModel.setWatchers([timer], forChatID: chatID)
        _ = makeDispatcher()
        let noticeArrived = expectation(description: "notice published")
        let observer = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            guard case let .delivery(message, _, _) = update,
                  case .clientLocal(let local) = message.content,
                  case .notice = local.action else { return }
            noticeArrived.fulfill()
        }
        defer { observer.unsubscribe() }

        try broker.publishMessageFromUser(chatID: chatID, content: .userCommand(.stop))
        // Drop the user's own stop message so only what the dispatcher
        // publishes in response is checked.
        XCTAssertEqual(published.count, 1)
        published.removeAll()
        wait(for: [noticeArrived], timeout: 10)

        XCTAssertEqual(publishedNotices(), [try expected([timer], .stop)])
    }

    // MARK: - Disable Orchestration

    func testDisableOrchestrationWithPendingWorkPublishesOneCancellationNotice() throws {
        try listModel.setOrchestrationEnabled(true, forChatID: chatID)
        let cancelled = [pendingTimer(id: "t"), sessionWatch(id: "w1"), sessionWatch(id: "w2")]
        try listModel.setWatchers(cancelled, forChatID: chatID)
        let client = OrchestratorClient.makeForTesting(broker: broker)

        try client.disableOrchestration(forChatID: chatID, disabledNotice: "disabled")

        XCTAssertEqual(publishedNotices(),
                       ["disabled", try expected(cancelled, .disableOrchestration)])
        XCTAssertTrue(listModel.watchers(forChatID: chatID).isEmpty)
        XCTAssertEqual(listModel.chat(id: chatID)?.orchestrationEnabled, false)
    }

    // A live dispatcher is torn down first; its watchers are counted from the
    // persisted set it keeps in sync.
    func testDisableOrchestrationWithLiveDispatcherCountsItsTimer() throws {
        try listModel.setOrchestrationEnabled(true, forChatID: chatID)
        let timer = pendingTimer(id: "t")
        try listModel.setWatchers([timer], forChatID: chatID)
        let client = OrchestratorClient.makeForTesting(broker: broker)
        _ = client.dispatcher(forChatID: chatID)

        try client.disableOrchestration(forChatID: chatID, disabledNotice: "disabled")

        XCTAssertEqual(publishedNotices(),
                       ["disabled", try expected([timer], .disableOrchestration)])
    }

    func testDisableOrchestrationWithNothingPendingPublishesOnlyDisabledNotice() throws {
        try listModel.setOrchestrationEnabled(true, forChatID: chatID)
        let client = OrchestratorClient.makeForTesting(broker: broker)

        try client.disableOrchestration(forChatID: chatID, disabledNotice: "disabled")

        XCTAssertEqual(publishedNotices(), ["disabled"])
    }
}

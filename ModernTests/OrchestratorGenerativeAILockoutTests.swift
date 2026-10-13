//
//  OrchestratorGenerativeAILockoutTests.swift
//  iTerm2 ModernTests
//
//  An administrator can forbid all LLM use with the GenerativeAIAllowed
//  advanced setting. A timer or watch registered by an AI chat before the
//  lockout must not wake the agent afterwards: its status_update would send
//  the chat history to the configured LLM endpoint. A blocked timer stays
//  persisted (dormant) so re-enabling AI does not silently lose it.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorGenerativeAILockoutTests: XCTestCase {
    private var listModel: ChatListModel!
    private var broker: ChatBroker!
    private var chatID: String!
    private var subscription: ChatBroker.Subscription?
    private var watcherEvents = [StatusUpdate]()

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-ai-lockout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        listModel = try XCTUnwrap(ChatListModel(database: db))
        var chat = Chat(title: "t", permissions: "")
        chat.orchestrationEnabled = true
        try listModel.add(chat: chat)
        chatID = chat.id
        broker = ChatBroker(listModel: listModel)
        watcherEvents = []
        subscription = broker.subscribe(chatID: chatID, registrationProvider: nil) { [weak self] update in
            guard case let .delivery(message, _, _) = update,
                  case let .watcherEvent(payload) = message.content else {
                return
            }
            MainActor.assumeIsolated {
                self?.watcherEvents.append(payload)
            }
        }
    }

    override func tearDown() {
        subscription?.unsubscribe()
        subscription = nil
        super.tearDown()
    }

    // A timer whose fire time passed while iTerm2 was not running, so it fires
    // as soon as the dispatcher re-arms it.
    private func overdueTimer(id: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: "",
                         workgroupID: "", workgroupName: "",
                         roleID: "", roleName: "",
                         targetState: nil, registeredAt: Date(timeIntervalSinceNow: -120),
                         mode: .timer, condition: nil, notifyUser: nil,
                         fireDate: Date(timeIntervalSinceNow: -60), note: "check the build")
    }

    private func tabStatusWatcher(id: String, sessionRef: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: sessionRef,
                         workgroupID: "wg", workgroupName: "WG",
                         roleID: "role-\(id)", roleName: "Role \(id)",
                         targetState: .working, registeredAt: Date(),
                         mode: .tabStatus, condition: nil, notifyUser: nil,
                         fireDate: nil, note: nil)
    }

    private func makeDispatcher() -> OrchestratorDispatcher {
        let dispatcher = OrchestratorDispatcher(chatID: chatID,
                                                broker: broker,
                                                typedInput: OrchestratorTypedInputStore(),
                                                restorationGate: SessionRestorationGate(ready: true),
                                                sessionLookup: { _ in nil })
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        return dispatcher
    }

    // Installs a cassette interceptor for the rest of the test, restoring the
    // previous one afterwards.
    private func installInterceptor(_ interceptor: @escaping (WebRequest, Bool) -> iTermAIClient.ReplayDelivery?) {
        let previous = iTermAIClient.requestInterceptor
        addTeardownBlock { iTermAIClient.requestInterceptor = previous }
        iTermAIClient.requestInterceptor = interceptor
    }

    private func persistedWatcherIDs() -> [String] {
        listModel.watchers(forChatID: chatID).map(\.watcherID)
    }

    // Runs the re-armed timer's fire task to completion. The task does not
    // sleep for an overdue timer, so this waits on no clock.
    private func runTimerTask(_ dispatcher: OrchestratorDispatcher, id: String) async throws {
        let task = try XCTUnwrap(dispatcher.timerTaskForTesting(watcherID: id),
                                 "reconcile should have re-armed the persisted timer")
        await task.value
    }

    func testOverdueTimerDoesNotFireWhileGenerativeAIIsDisallowed() async throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        try listModel.setWatchers([overdueTimer(id: "t1")], forChatID: chatID)
        let dispatcher = makeDispatcher()
        try await runTimerTask(dispatcher, id: "t1")

        XCTAssertTrue(watcherEvents.isEmpty,
                      "a timerFired status_update would send the chat to the LLM despite the lockout")
        XCTAssertEqual(persistedWatcherIDs(), ["t1"],
                       "the blocked timer stays persisted so re-enabling AI does not lose it")
    }

    // Positive control: the same overdue timer fires when AI is allowed.
    func testOverdueTimerFiresWhenGenerativeAIIsAllowed() async throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: true)
        try listModel.setWatchers([overdueTimer(id: "t1")], forChatID: chatID)
        let dispatcher = makeDispatcher()
        try await runTimerTask(dispatcher, id: "t1")

        XCTAssertEqual(watcherEvents.map(\.watcherID), ["t1"])
        XCTAssertEqual(watcherEvents.first?.reason, .timerFired)
        XCTAssertEqual(persistedWatcherIDs(), [])
    }

    // Any watcher event wakes the agent, not only a timer firing. A watch
    // dropped at restart because its session is gone is reported as a
    // watcherDropped status_update, which must not go out under the lockout.
    func testWatcherDroppedEventIsNotPublishedWhileGenerativeAIIsDisallowed() throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        try listModel.setWatchers([tabStatusWatcher(id: "gone", sessionRef: "no-such-session")],
                                  forChatID: chatID)
        _ = makeDispatcher()
        XCTAssertTrue(watcherEvents.isEmpty)
        // The session really is gone, so the watch is still removed.
        XCTAssertEqual(persistedWatcherIDs(), [])
    }

    // Positive control: the same drop is reported when AI is allowed.
    func testWatcherDroppedEventIsPublishedWhenGenerativeAIIsAllowed() throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: true)
        try listModel.setWatchers([tabStatusWatcher(id: "gone", sessionRef: "no-such-session")],
                                  forChatID: chatID)
        _ = makeDispatcher()
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["gone"])
        XCTAssertEqual(watcherEvents.first?.reason, .watcherDropped)
    }

    // A tab-status transition that reaches a watch's target would wake the
    // agent. Under the lockout it must not, and the watch stays persisted
    // (dormant) rather than being used up.
    func testTabStatusFireIsHeldWhileGenerativeAIIsDisallowed() throws {
        try runTabStatusTransition(allowed: false)
        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persistedWatcherIDs(), ["w"])
    }

    // Positive control for the tab-status path.
    func testTabStatusFireIsPublishedWhenGenerativeAIIsAllowed() throws {
        try runTabStatusTransition(allowed: true)
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["w"])
        XCTAssertEqual(watcherEvents.first?.reason, .stateReached)
        XCTAssertEqual(persistedWatcherIDs(), [])
    }

    private func runTabStatusTransition(allowed: Bool) throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: allowed)
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let ref = session.stableID
        try listModel.setWatchers([tabStatusWatcher(id: "w", sessionRef: ref)], forChatID: chatID)
        let dispatcher = OrchestratorDispatcher(chatID: chatID,
                                                broker: broker,
                                                typedInput: OrchestratorTypedInputStore(),
                                                restorationGate: SessionRestorationGate(ready: true),
                                                sessionLookup: { $0 == ref ? session : nil })
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        // Idle, then working (the watcher's target): a real transition.
        let idle = iTermSessionTabStatus(sessionID: ref)
        let working = iTermSessionTabStatus(sessionID: ref)
        working.hasIndicator = true
        NotificationCenter.default.post(name: iTermSessionTabStatus.didChangeNotificationName,
                                        object: idle)
        NotificationCenter.default.post(name: iTermSessionTabStatus.didChangeNotificationName,
                                        object: working)
        // The observer uses queue: .main; drain the run loop once (no
        // wall-clock wait) in case delivery is ever queued.
        RunLoop.main.run(mode: .default, before: .distantPast)
    }

    // Backstop at the single place LLM requests leave iTerm2: under the
    // lockout a request fails without reaching the plugin (or, in tests, the
    // cassette interceptor that stands in for it).
    func testLLMRequestIsRefusedWhileGenerativeAIIsDisallowed() {
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        var interceptorCalls = 0
        installInterceptor { _, _ in
            interceptorCalls += 1
            return iTermAIClient.ReplayDelivery(streamChunks: [],
                                                response: WebResponse(data: "{}", error: nil),
                                                errorReason: nil)
        }
        let done = expectation(description: "completion")
        var outcome: Result<WebResponse, PluginError>?
        _ = iTermAIClient.instance.request(
            webRequest: WebRequest(headers: [:], method: "POST", body: .string("{}"),
                                   url: "https://example.com/v1/chat"),
            stream: nil) { result in
                outcome = result
                done.fulfill()
            }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(interceptorCalls, 0, "the request must not be sent")
        guard case .failure = outcome else {
            return XCTFail("expected failure, got \(String(describing: outcome))")
        }
    }

    // Positive control for the backstop.
    func testLLMRequestIsSentWhenGenerativeAIIsAllowed() {
        pinAdvancedSetting("GenerativeAIAllowed", to: true)
        var interceptorCalls = 0
        installInterceptor { _, _ in
            interceptorCalls += 1
            return iTermAIClient.ReplayDelivery(streamChunks: [],
                                                response: WebResponse(data: "{}", error: nil),
                                                errorReason: nil)
        }
        let done = expectation(description: "completion")
        var outcome: Result<WebResponse, PluginError>?
        _ = iTermAIClient.instance.request(
            webRequest: WebRequest(headers: [:], method: "POST", body: .string("{}"),
                                   url: "https://example.com/v1/chat"),
            stream: nil) { result in
                outcome = result
                done.fulfill()
            }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(interceptorCalls, 1)
        guard case .success = outcome else {
            return XCTFail("expected success, got \(String(describing: outcome))")
        }
    }
}

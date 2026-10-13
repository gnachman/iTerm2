//
//  OrchestratorRestorationGateTests.swift
//  iTerm2 ModernTests
//
//  At launch, the AI-chat timer re-arm builds orchestration dispatchers in
//  applicationDidFinishLaunching, before window restoration has created the
//  sessions their persisted watchers target. A dispatcher must not reconcile
//  those watchers until restoration is done: otherwise every watch is dropped
//  as “session could not be restored” and each drop is a watcherEvent that
//  starts a paid agent turn. These tests drive an injected restoration gate
//  and session lookup, so no window restoration (or timing) is involved.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorRestorationGateTests: XCTestCase {
    private var listModel: ChatListModel!
    private var broker: ChatBroker!
    private var chatID: String!
    private var subscription: ChatBroker.Subscription?
    private var watcherEvents = [StatusUpdate]()

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        listModel = try XCTUnwrap(ChatListModel(database: db))
        var chat = Chat(title: "t", permissions: "")
        // Orchestration chats may read session state, so surviving tab-status
        // watchers are not dropped for lack of permission during reconcile.
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

    // A tab-status watcher targeting .working, which never arms the screen
    // escalation backstop, so reconcile starts no long-running task.
    private func watcher(id: String, sessionRef: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: sessionRef,
                         workgroupID: "wg", workgroupName: "WG",
                         roleID: "role-\(id)", roleName: "Role \(id)",
                         targetState: .working, registeredAt: Date(),
                         mode: .tabStatus, condition: nil, notifyUser: nil,
                         fireDate: nil, note: nil)
    }

    private func makeDispatcher(gate: SessionRestorationGate,
                                lookup: @escaping (String) -> PTYSession?) -> OrchestratorDispatcher {
        let dispatcher = OrchestratorDispatcher(chatID: chatID,
                                                broker: broker,
                                                typedInput: OrchestratorTypedInputStore(),
                                                restorationGate: gate,
                                                sessionLookup: lookup)
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        return dispatcher
    }

    private func persistedWatcherIDs() -> [String] {
        listModel.watchers(forChatID: chatID).map(\.watcherID)
    }

    func testWatchersSurviveUntilRestorationCompletes_thenOnlyMissingOnesDrop() throws {
        let restored = try XCTUnwrap(PTYSession(synthetic: false))
        let restoredRef = restored.stableID
        try listModel.setWatchers([watcher(id: "kept", sessionRef: restoredRef),
                                   watcher(id: "gone", sessionRef: "no-such-session")],
                                  forChatID: chatID)

        // Mid-launch: restoration has not created the session yet.
        var restorationDone = false
        let gate = SessionRestorationGate()
        let dispatcher = makeDispatcher(gate: gate) { ref in
            restorationDone && ref == restoredRef ? restored : nil
        }
        _ = dispatcher

        XCTAssertEqual(persistedWatcherIDs(), ["kept", "gone"],
                       "no watcher may be dropped before session restoration completes")
        XCTAssertTrue(watcherEvents.isEmpty,
                      "a watcherEvent before restoration completes would start a paid agent turn")

        // Restoration creates the session, then signals completion.
        restorationDone = true
        gate.markReady()

        XCTAssertEqual(persistedWatcherIDs(), ["kept"],
                       "only the watcher whose session really is gone is dropped")
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["gone"])
        XCTAssertEqual(watcherEvents.first?.reason, .watcherDropped)

        // Opening the gate again must not reconcile a second time.
        gate.markReady()
        XCTAssertEqual(watcherEvents.count, 1, "the drop is reported exactly once")
        XCTAssertEqual(persistedWatcherIDs(), ["kept"])
    }

    func testDispatcherCreatedAfterRestorationReconcilesImmediately() throws {
        try listModel.setWatchers([watcher(id: "gone", sessionRef: "no-such-session")],
                                  forChatID: chatID)
        let gate = SessionRestorationGate(ready: true)
        _ = makeDispatcher(gate: gate) { _ in nil }
        XCTAssertEqual(persistedWatcherIDs(), [])
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["gone"])
    }

    // Restoration posts tab-status changes as sessions come up. Before the
    // reconcile seeds each surviving watcher's state history, such a change
    // would read as a transition and fire the watch.
    func testTabStatusChangesBeforeRestorationCompletesDoNotFireWatchers() throws {
        let restored = try XCTUnwrap(PTYSession(synthetic: false))
        let restoredRef = restored.stableID
        try listModel.setWatchers([watcher(id: "kept", sessionRef: restoredRef)],
                                  forChatID: chatID)
        let gate = SessionRestorationGate()
        _ = makeDispatcher(gate: gate) { ref in ref == restoredRef ? restored : nil }

        // A status with an indicator reads as .working, the watcher's target.
        let status = iTermSessionTabStatus(sessionID: restoredRef)
        status.hasIndicator = true
        NotificationCenter.default.post(name: iTermSessionTabStatus.didChangeNotificationName,
                                        object: status)
        // The observer uses queue: .main. Posting on main delivers inline
        // today; draining the run loop once (no wall-clock wait) keeps the test
        // correct if delivery is ever queued instead.
        RunLoop.main.run(mode: .default, before: .distantPast)

        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persistedWatcherIDs(), ["kept"])

        // Positive control: once restoration completes and history is seeded,
        // the same notification path does fire the watch on a real transition.
        gate.markReady()
        let idle = iTermSessionTabStatus(sessionID: restoredRef)
        NotificationCenter.default.post(name: iTermSessionTabStatus.didChangeNotificationName,
                                        object: idle)
        NotificationCenter.default.post(name: iTermSessionTabStatus.didChangeNotificationName,
                                        object: status)
        RunLoop.main.run(mode: .default, before: .distantPast)
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["kept"])
        XCTAssertEqual(watcherEvents.first?.reason, .stateReached)
        XCTAssertEqual(persistedWatcherIDs(), [])
    }

    // A dispatcher torn down (chat deleted or left orchestration) while waiting
    // must not reconcile when restoration later completes.
    func testDispatcherTornDownBeforeRestorationCompletesNeverReconciles() throws {
        try listModel.setWatchers([watcher(id: "gone", sessionRef: "no-such-session")],
                                  forChatID: chatID)
        let gate = SessionRestorationGate()
        let dispatcher = makeDispatcher(gate: gate) { _ in nil }
        dispatcher.tearDown()
        gate.markReady()
        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persistedWatcherIDs(), ["gone"])
    }
}

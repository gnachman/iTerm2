//
//  OrchestratorTmuxWatchReattachTests.swift
//  iTerm2 ModernTests
//
//  A tmux -CC pane is not restored by window restoration. After a relaunch
//  the restored gateway reattaches tmux and TmuxWindowOpener builds a new
//  PTYSession, with a new stableID, for each pane, some time after the
//  restoration gate has opened. A watch on such a pane used to be dropped at
//  reconcile (“could not be restored”), which also started a paid agent turn.
//  It is now held until the pane reattaches, then re-bound to the new session
//  by its tmux identity (the tmux session's @iterm2_id plus the pane number).
//  It is dropped if that tmux session detaches or a deadline passes first.
//  The deadline is injected, so no test waits on a clock.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorTmuxWatchReattachTests: XCTestCase {
    private var listModel: ChatListModel!
    private var broker: ChatBroker!
    private var chatID: String!
    private var subscription: ChatBroker.Subscription?
    private var watcherEvents = [StatusUpdate]()
    private var scheduledDeadlines = [(delay: TimeInterval, block: @MainActor @Sendable () -> Void)]()

    private let paneIdentity = TmuxPaneIdentity(tmuxSessionGUID: "tmux-session-A", pane: 3)

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-tmux-\(UUID().uuidString)", isDirectory: true)
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
        scheduledDeadlines = []
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

    // A .working tab-status watcher never arms the screen escalation backstop,
    // so re-arming it starts no long-running task.
    private func watcher(id: String,
                         sessionRef: String,
                         tmuxPane: TmuxPaneIdentity?,
                         targetState: SessionState = .working) -> WorkgroupWatcher {
        var w = WorkgroupWatcher(watcherID: id, sessionGUID: sessionRef,
                                 workgroupID: "wg", workgroupName: "WG",
                                 roleID: "role-\(id)", roleName: "Role \(id)",
                                 targetState: targetState, registeredAt: Date(),
                                 mode: .tabStatus, condition: nil, notifyUser: nil,
                                 fireDate: nil, note: nil)
        w.tmuxPane = tmuxPane
        return w
    }

    private func makeDispatcher(lookup: @escaping (String) -> PTYSession?,
                                tmuxLookup: @escaping (TmuxPaneIdentity) -> PTYSession?) -> OrchestratorDispatcher {
        let dispatcher = OrchestratorDispatcher(
            chatID: chatID,
            broker: broker,
            typedInput: OrchestratorTypedInputStore(),
            restorationGate: SessionRestorationGate(ready: true),
            sessionLookup: lookup,
            tmuxPaneLookup: tmuxLookup,
            scheduleTmuxReattachDeadline: { [weak self] delay, block in
                self?.scheduledDeadlines.append((delay, block))
            })
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        return dispatcher
    }

    private func persisted() -> [WorkgroupWatcher] {
        listModel.watchers(forChatID: chatID)
    }

    private func postTmuxWindowDidOpen() {
        NotificationCenter.default.post(name: NSNotification.Name(kTmuxControllerWindowDidOpen),
                                        object: nil)
        RunLoop.main.run(mode: .default, before: .distantPast)
    }

    private func postTmuxDetached(sessionGUID: String) {
        NotificationCenter.default.post(name: .tmuxControllerDetached,
                                        object: nil,
                                        userInfo: [kTmuxControllerDetachedSessionGuidKey: sessionGUID])
        RunLoop.main.run(mode: .default, before: .distantPast)
    }

    private func postTabStatus(_ status: iTermSessionTabStatus) {
        NotificationCenter.default.post(name: iTermSessionTabStatus.didChangeNotificationName,
                                        object: status)
        RunLoop.main.run(mode: .default, before: .distantPast)
    }

    // The F-126 flow: the restoration gate opens before tmux reattaches.
    func testTmuxWatchIsHeldAtReconcileAndReboundWhenThePaneReattaches() throws {
        try listModel.setWatchers([watcher(id: "w", sessionRef: "old-stable-id", tmuxPane: paneIdentity)],
                                  forChatID: chatID)
        let reattached = try XCTUnwrap(PTYSession(synthetic: false))
        var tmuxAttached = false
        _ = makeDispatcher(lookup: { ref in
            tmuxAttached && ref == reattached.stableID ? reattached : nil
        }, tmuxLookup: { [paneIdentity] identity in
            tmuxAttached && identity == paneIdentity ? reattached : nil
        })

        XCTAssertTrue(watcherEvents.isEmpty,
                      "a tmux watch must not be dropped before its tmux session has had a chance to reattach")
        XCTAssertEqual(persisted().map(\.watcherID), ["w"])
        XCTAssertEqual(scheduledDeadlines.count, 1)
        XCTAssertEqual(scheduledDeadlines.first?.delay, OrchestratorDispatcher.tmuxReattachDeadline)

        // A tmux window opens before the pane's session can be found (as
        // retainWindow: posts before the pane is registered): still held.
        postTmuxWindowDidOpen()
        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persisted().first?.sessionGUID, "old-stable-id")

        // tmux reattaches and opens the window holding the pane.
        tmuxAttached = true
        postTmuxWindowDidOpen()

        XCTAssertTrue(watcherEvents.isEmpty)
        let rebound = try XCTUnwrap(persisted().first)
        XCTAssertEqual(rebound.watcherID, "w")
        XCTAssertEqual(rebound.sessionGUID, reattached.stableID,
                       "the watch follows the recreated session")
        XCTAssertEqual(rebound.tmuxPane, paneIdentity)

        // The deadline firing after the rebind does nothing.
        scheduledDeadlines.first?.block()
        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persisted().map(\.watcherID), ["w"])

        // The re-bound watch works: a transition to its target state fires it.
        // The first status reads .idle, the seeded state, so it is no transition.
        postTabStatus(iTermSessionTabStatus(sessionID: reattached.stableID))
        XCTAssertTrue(watcherEvents.isEmpty, "rebinding seeds state history, so a same-state status does not fire")
        let working = iTermSessionTabStatus(sessionID: reattached.stableID)
        working.hasIndicator = true
        postTabStatus(working)
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["w"])
        XCTAssertEqual(watcherEvents.first?.reason, .stateReached)
        XCTAssertEqual(persisted(), [])
    }

    // A held .idle watcher must not get a screen-escalation backstop while it
    // has no session: that task would exit at once but keep its slot, and the
    // re-arm after rebind would be refused. After rebind the backstop is armed,
    // and the seeded state keeps the pane's first .idle status from firing it.
    //
    // The escalation task is cancelled as soon as it exists, before the run loop
    // or main actor gets a turn, so it never reads the screen or asks an LLM.
    func testHeldWatchGetsNoBackstopUntilReboundAndIsSeededOnRebind() async throws {
        try listModel.setWatchers([watcher(id: "w", sessionRef: "old-stable-id",
                                           tmuxPane: paneIdentity, targetState: .idle)],
                                  forChatID: chatID)
        let reattached = try XCTUnwrap(PTYSession(synthetic: false))
        var tmuxAttached = false
        let dispatcher = makeDispatcher(lookup: { ref in
            tmuxAttached && ref == reattached.stableID ? reattached : nil
        }, tmuxLookup: { _ in tmuxAttached ? reattached : nil })
        XCTAssertNil(dispatcher.escalationTimerForTesting(watcherID: "w"))

        // A permission change re-gates every watcher, arming backstops.
        try broker.publishMessageFromUser(chatID: chatID, content: .setPermissions([]))
        // The dispatcher handles broker updates in a main-actor Task; one
        // enqueued after it runs after it.
        await Task { @MainActor in }.value
        XCTAssertNil(dispatcher.escalationTimerForTesting(watcherID: "w"),
                     "a held watcher has no session for a backstop to watch")
        XCTAssertEqual(persisted().map(\.watcherID), ["w"])

        tmuxAttached = true
        // Posted on main, a queue: .main observer runs inline. The run loop is
        // not spun so the backstop task can be cancelled before it gets a turn.
        NotificationCenter.default.post(name: NSNotification.Name(kTmuxControllerWindowDidOpen),
                                        object: nil)
        let backstop = dispatcher.escalationTimerForTesting(watcherID: "w")
        backstop?.cancel()
        XCTAssertNotNil(backstop, "rebinding arms the backstop")
        XCTAssertEqual(persisted().first?.sessionGUID, reattached.stableID)

        // The reattached pane reports .idle (no indicator). That is the seeded
        // state, not a transition, so the .idle watch does not fire.
        NotificationCenter.default.post(name: iTermSessionTabStatus.didChangeNotificationName,
                                        object: iTermSessionTabStatus(sessionID: reattached.stableID))
        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persisted().map(\.watcherID), ["w"])
    }

    // If the agent registered the same watch on the reattached pane while the
    // old one was held, the held copy is discarded at rebind so it can't fire twice.
    func testHeldWatchDuplicatingOneRegisteredOnTheReattachedPaneIsDiscarded() throws {
        let reattached = try XCTUnwrap(PTYSession(synthetic: false))
        try listModel.setWatchers([watcher(id: "held", sessionRef: "old-stable-id", tmuxPane: paneIdentity),
                                   watcher(id: "fresh", sessionRef: reattached.stableID, tmuxPane: paneIdentity)],
                                  forChatID: chatID)
        var tmuxAttached = false
        _ = makeDispatcher(lookup: { ref in ref == reattached.stableID ? reattached : nil },
                           tmuxLookup: { _ in tmuxAttached ? reattached : nil })
        XCTAssertEqual(persisted().map(\.watcherID), ["held", "fresh"])

        tmuxAttached = true
        postTmuxWindowDidOpen()
        XCTAssertTrue(watcherEvents.isEmpty, "discarding the duplicate is silent")
        XCTAssertEqual(persisted().map(\.watcherID), ["fresh"])

        postTabStatus(iTermSessionTabStatus(sessionID: reattached.stableID))
        let working = iTermSessionTabStatus(sessionID: reattached.stableID)
        working.hasIndicator = true
        postTabStatus(working)
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["fresh"], "the watch fires once")
    }

    // A pane that is already back when reconcile runs is re-bound right away.
    func testTmuxWatchWhosePaneIsAlreadyBackIsReboundAtReconcile() throws {
        try listModel.setWatchers([watcher(id: "w", sessionRef: "old-stable-id", tmuxPane: paneIdentity)],
                                  forChatID: chatID)
        let reattached = try XCTUnwrap(PTYSession(synthetic: false))
        _ = makeDispatcher(lookup: { ref in ref == reattached.stableID ? reattached : nil },
                           tmuxLookup: { _ in reattached })
        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persisted().first?.sessionGUID, reattached.stableID)
        XCTAssertTrue(scheduledDeadlines.isEmpty, "nothing is pending, so no deadline is scheduled")
    }

    func testTmuxWatchIsDroppedWhenThePaneNeverReattaches() throws {
        try listModel.setWatchers([watcher(id: "w", sessionRef: "old-stable-id", tmuxPane: paneIdentity)],
                                  forChatID: chatID)
        _ = makeDispatcher(lookup: { _ in nil }, tmuxLookup: { _ in nil })
        // A tmux window that isn't the pane's opens: still pending.
        postTmuxWindowDidOpen()
        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persisted().map(\.watcherID), ["w"])

        let deadline = try XCTUnwrap(scheduledDeadlines.first)
        deadline.block()

        XCTAssertEqual(watcherEvents.map(\.watcherID), ["w"])
        XCTAssertEqual(watcherEvents.first?.reason, .watcherDropped)
        XCTAssertEqual(persisted(), [])

        // Firing twice reports the drop once.
        deadline.block()
        XCTAssertEqual(watcherEvents.count, 1)
    }

    func testDetachOfTheWatchedTmuxSessionDropsThePendingWatch() throws {
        let other = TmuxPaneIdentity(tmuxSessionGUID: "tmux-session-B", pane: 3)
        try listModel.setWatchers([watcher(id: "a", sessionRef: "old-a", tmuxPane: paneIdentity),
                                   watcher(id: "b", sessionRef: "old-b", tmuxPane: other)],
                                  forChatID: chatID)
        _ = makeDispatcher(lookup: { _ in nil }, tmuxLookup: { _ in nil })

        postTmuxDetached(sessionGUID: "tmux-session-A")

        XCTAssertEqual(watcherEvents.map(\.watcherID), ["a"])
        XCTAssertEqual(watcherEvents.first?.reason, .watcherDropped)
        XCTAssertEqual(persisted().map(\.watcherID), ["b"],
                       "a detach of a different tmux session leaves its watch pending")
    }

    // A watch on an ordinary session whose session is gone is still dropped at
    // reconcile, even when a tmux watch beside it is held.
    func testNonTmuxWatchWithMissingSessionIsStillDroppedImmediately() throws {
        try listModel.setWatchers([watcher(id: "tmux", sessionRef: "old-tmux", tmuxPane: paneIdentity),
                                   watcher(id: "plain", sessionRef: "old-plain", tmuxPane: nil)],
                                  forChatID: chatID)
        _ = makeDispatcher(lookup: { _ in nil }, tmuxLookup: { _ in nil })
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["plain"])
        XCTAssertEqual(watcherEvents.first?.reason, .watcherDropped)
        XCTAssertEqual(persisted().map(\.watcherID), ["tmux"])
    }

    // A session-bound chat's link still names the old pane session after a
    // relaunch, so its watch is not re-bound to the new one (it would read a
    // session the chat isn't linked to); it is dropped at reconcile as before.
    func testSessionBoundChatsTmuxWatchIsDroppedAtReconcile() throws {
        try listModel.setOrchestrationEnabled(false, forChatID: chatID)
        try listModel.setWatchers([watcher(id: "w", sessionRef: "old-stable-id", tmuxPane: paneIdentity)],
                                  forChatID: chatID)
        _ = makeDispatcher(lookup: { _ in nil }, tmuxLookup: { _ in nil })
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["w"])
        XCTAssertEqual(watcherEvents.first?.reason, .watcherDropped)
        XCTAssertEqual(persisted(), [])
        XCTAssertTrue(scheduledDeadlines.isEmpty)
    }

    // A pending watch that is cancelled some other way (here, the chat is
    // unlinked) is not reported when the deadline fires.
    func testCancelledPendingWatchIsNotReportedAtTheDeadline() throws {
        try listModel.setWatchers([watcher(id: "w", sessionRef: "old-stable-id", tmuxPane: paneIdentity)],
                                  forChatID: chatID)
        let dispatcher = makeDispatcher(lookup: { _ in nil }, tmuxLookup: { _ in nil })
        dispatcher.cancelWatchersOnUnlink()
        XCTAssertEqual(persisted(), [])
        try XCTUnwrap(scheduledDeadlines.first).block()
        XCTAssertTrue(watcherEvents.isEmpty)
    }

    func testTornDownDispatcherIgnoresTheDeadline() throws {
        try listModel.setWatchers([watcher(id: "w", sessionRef: "old-stable-id", tmuxPane: paneIdentity)],
                                  forChatID: chatID)
        let dispatcher = makeDispatcher(lookup: { _ in nil }, tmuxLookup: { _ in nil })
        dispatcher.tearDown()
        try XCTUnwrap(scheduledDeadlines.first).block()
        XCTAssertTrue(watcherEvents.isEmpty)
        XCTAssertEqual(persisted().map(\.watcherID), ["w"])
    }

    // MARK: - Identity stamped at registration

    func testTmuxPaneIdentityIsOnlyMadeForTmuxClientsWithAKnownSessionGUID() {
        XCTAssertNil(OrchestratorDispatcher.tmuxPaneIdentity(isTmuxClient: false,
                                                             tmuxSessionGUID: "g",
                                                             pane: 1))
        XCTAssertNil(OrchestratorDispatcher.tmuxPaneIdentity(isTmuxClient: true,
                                                             tmuxSessionGUID: nil,
                                                             pane: 1))
        XCTAssertNil(OrchestratorDispatcher.tmuxPaneIdentity(isTmuxClient: true,
                                                             tmuxSessionGUID: "",
                                                             pane: 1))
        XCTAssertEqual(OrchestratorDispatcher.tmuxPaneIdentity(isTmuxClient: true,
                                                               tmuxSessionGUID: "g",
                                                               pane: 7),
                       TmuxPaneIdentity(tmuxSessionGUID: "g", pane: 7))
    }

    func testWatcherPersistedWithoutTmuxPaneDecodesAndTmuxPaneRoundTrips() throws {
        let legacy = watcher(id: "w", sessionRef: "s", tmuxPane: nil)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "tmuxPane")
        let decoded = try JSONDecoder().decode(WorkgroupWatcher.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.tmuxPane)

        let stamped = watcher(id: "w", sessionRef: "s", tmuxPane: paneIdentity)
        let roundTripped = try JSONDecoder().decode(WorkgroupWatcher.self,
                                                    from: JSONEncoder().encode(stamped))
        XCTAssertEqual(roundTripped.tmuxPane, paneIdentity)
    }
}

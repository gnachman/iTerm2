//
//  OrchestratorQuitRestorationTests.swift
//  iTerm2 ModernTests
//
//  An ordinary quit closes every window, which terminates every session and
//  posts iTermSessionWillTerminate. When window restoration will bring those
//  sessions back at the next launch (with the same stableID), that teardown is
//  not a real session close: watches a chat registered on a session must
//  survive it, and the agent must not be told they were dropped (a
//  watcherDropped event starts a paid agent turn). A real close still drops
//  them. The quit predicate is injected, so no app termination is involved.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorQuitRestorationTests: XCTestCase {
    private var listModel: ChatListModel!
    private var broker: ChatBroker!
    private var chatID: String!
    private var subscription: ChatBroker.Subscription?
    private var watcherEvents = [StatusUpdate]()

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-quit-\(UUID().uuidString)", isDirectory: true)
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

    private func watcher(id: String, sessionRef: String) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: id, sessionGUID: sessionRef,
                         workgroupID: "wg", workgroupName: "WG",
                         roleID: "role-\(id)", roleName: "Role \(id)",
                         targetState: .working, registeredAt: Date(),
                         mode: .tabStatus, condition: nil, notifyUser: nil,
                         fireDate: nil, note: nil)
    }

    private func makeDispatcher(session: PTYSession,
                                quitWillRestoreSessions: @escaping (Notification) -> Bool) -> OrchestratorDispatcher {
        let ref = session.stableID
        let dispatcher = OrchestratorDispatcher(chatID: chatID,
                                                broker: broker,
                                                typedInput: OrchestratorTypedInputStore(),
                                                restorationGate: SessionRestorationGate(ready: true),
                                                sessionLookup: { $0 == ref ? session : nil },
                                                quitWillRestoreSessions: quitWillRestoreSessions)
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        return dispatcher
    }

    private func makeTmuxDispatcher(chatID: String,
                                    session: PTYSession,
                                    quitMayReattachTmuxSession: @escaping (Notification) -> Bool) -> OrchestratorDispatcher {
        let ref = session.stableID
        let dispatcher = OrchestratorDispatcher(chatID: chatID,
                                                broker: broker,
                                                typedInput: OrchestratorTypedInputStore(),
                                                restorationGate: SessionRestorationGate(ready: true),
                                                sessionLookup: { $0 == ref ? session : nil },
                                                quitWillRestoreSessions: { _ in false },
                                                quitMayReattachTmuxSession: quitMayReattachTmuxSession)
        addTeardownBlock { @MainActor in dispatcher.tearDown() }
        return dispatcher
    }

    private func tmuxWatcher(id: String, sessionRef: String, tmuxPane: TmuxPaneIdentity?) -> WorkgroupWatcher {
        var w = watcher(id: id, sessionRef: sessionRef)
        w.tmuxPane = tmuxPane
        return w
    }

    private func postWillTerminate(_ session: PTYSession, wasTmuxClient: Bool = false) {
        NotificationCenter.default.post(name: NSNotification.Name.iTermSessionWillTerminate,
                                        object: session,
                                        userInfo: [iTermSessionWillTerminateWasTmuxClientKey: NSNumber(value: wasTmuxClient)])
        // The observer uses queue: .main. Posting on main delivers inline
        // today; draining the run loop once (no wall-clock wait) keeps the test
        // correct if delivery is ever queued instead.
        RunLoop.main.run(mode: .default, before: .distantPast)
    }

    private func persistedWatcherIDs() -> [String] {
        listModel.watchers(forChatID: chatID).map(\.watcherID)
    }

    func testQuitThatRestoresSessionsKeepsWatchesOnTerminatingSession() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        try listModel.setWatchers([watcher(id: "w", sessionRef: session.stableID)],
                                  forChatID: chatID)
        _ = makeDispatcher(session: session) { ($0.object as? PTYSession) === session }

        postWillTerminate(session)

        XCTAssertEqual(persistedWatcherIDs(), ["w"],
                       "a quit that window restoration will undo must not drop the watch")
        XCTAssertTrue(watcherEvents.isEmpty,
                      "the agent must not be told a watch was dropped by a restorable quit")
    }

    // Control: a real session close (not a restorable quit) still drops the
    // watch and reports it, so the test above fails for the right reason.
    func testRealSessionCloseStillDropsWatches() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        try listModel.setWatchers([watcher(id: "w", sessionRef: session.stableID)],
                                  forChatID: chatID)
        _ = makeDispatcher(session: session) { _ in false }

        postWillTerminate(session)

        XCTAssertEqual(persistedWatcherIDs(), [])
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["w"])
        XCTAssertEqual(watcherEvents.first?.reason, .watcherDropped)
    }

    // The predicate behind the injected closure. Only a quit after which
    // window restoration will run keeps links and watches, and a tmux client
    // session never does: tmux tabs are not saved for restoration (they come
    // back on reattach as new sessions), so its termination is a real close.
    func testPredicateKeepsOnlyRestorableNonTmuxSessionsDuringQuit() {
        func check(tmux: Bool, quitting: Bool, restore: Bool) -> Bool {
            SessionQuitRestoration.sessionWillBeRestored(isTmuxClient: tmux,
                                                         applicationIsQuitting: quitting,
                                                         willRestoreWindowsAtNextLaunch: restore)
        }
        XCTAssertTrue(check(tmux: false, quitting: true, restore: true))
        XCTAssertFalse(check(tmux: false, quitting: false, restore: true),
                       "closing a session while the app keeps running is a real close")
        XCTAssertFalse(check(tmux: false, quitting: true, restore: false),
                       "a quit without restoration (including Option-Quit) is a real close")
        XCTAssertFalse(check(tmux: true, quitting: true, restore: true),
                       "tmux client sessions are not restored, so they unlink at quit")
        XCTAssertFalse(check(tmux: false, quitting: false, restore: false))
    }

    // A tmux client session is not restored, but after a quit that restores
    // windows the restored gateway reattaches tmux and the pane comes back as
    // a new session. An orchestration chat's watch that recorded the pane's
    // tmux identity is re-bound to it at the next launch (F-126), so the quit
    // must keep it rather than drop it and wake the agent. A watch on the same
    // pane with no tmux identity can't be re-bound, so it is still dropped.
    func testRestoringQuitKeepsOrchestrationWatchWithTmuxIdentity() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let pane = TmuxPaneIdentity(tmuxSessionGUID: "tmux-session-A", pane: 3)
        try listModel.setWatchers([tmuxWatcher(id: "tmux", sessionRef: session.stableID, tmuxPane: pane),
                                   tmuxWatcher(id: "plain", sessionRef: session.stableID, tmuxPane: nil)],
                                  forChatID: chatID)
        _ = makeTmuxDispatcher(chatID: chatID, session: session) { ($0.object as? PTYSession) === session }

        postWillTerminate(session, wasTmuxClient: true)

        XCTAssertEqual(persistedWatcherIDs(), ["tmux"],
                       "a watch with a tmux identity must survive a restoring quit so it can be re-bound at launch")
        XCTAssertEqual(listModel.watchers(forChatID: chatID).first?.tmuxPane, pane)
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["plain"],
                       "only the watch that can't be re-bound is reported dropped")
    }

    // Control: closing a tmux pane while the app keeps running is a real
    // close, so even a watch with a tmux identity is dropped and reported.
    func testTmuxPaneCloseWithoutQuitStillDropsWatchWithTmuxIdentity() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let pane = TmuxPaneIdentity(tmuxSessionGUID: "tmux-session-A", pane: 3)
        try listModel.setWatchers([tmuxWatcher(id: "tmux", sessionRef: session.stableID, tmuxPane: pane)],
                                  forChatID: chatID)
        _ = makeTmuxDispatcher(chatID: chatID, session: session) { _ in false }

        postWillTerminate(session, wasTmuxClient: true)

        XCTAssertEqual(persistedWatcherIDs(), [])
        XCTAssertEqual(watcherEvents.map(\.watcherID), ["tmux"])
        XCTAssertEqual(watcherEvents.first?.reason, .watcherDropped)
    }

    // A session-bound chat's watches are never re-bound to a reattached pane
    // (its link still names the old pane session), so a restoring quit drops
    // them as before, even one that somehow carries a tmux identity.
    func testRestoringQuitStillDropsSessionBoundChatsTmuxWatch() throws {
        let boundChat = Chat(title: "bound", permissions: "")
        try listModel.add(chat: boundChat)
        var boundEvents = [StatusUpdate]()
        let boundSubscription = broker.subscribe(chatID: boundChat.id, registrationProvider: nil) { update in
            guard case let .delivery(message, _, _) = update,
                  case let .watcherEvent(payload) = message.content else {
                return
            }
            MainActor.assumeIsolated {
                boundEvents.append(payload)
            }
        }
        defer { boundSubscription.unsubscribe() }
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let pane = TmuxPaneIdentity(tmuxSessionGUID: "tmux-session-A", pane: 3)
        try listModel.setWatchers([tmuxWatcher(id: "tmux", sessionRef: session.stableID, tmuxPane: pane)],
                                  forChatID: boundChat.id)
        _ = makeTmuxDispatcher(chatID: boundChat.id, session: session) { ($0.object as? PTYSession) === session }

        postWillTerminate(session, wasTmuxClient: true)

        XCTAssertEqual(listModel.watchers(forChatID: boundChat.id).map(\.watcherID), [])
        XCTAssertEqual(boundEvents.map(\.watcherID), ["tmux"])
    }

    // The predicate behind quitMayReattachTmuxSession: only a tmux client
    // session terminating for a quit after which windows will be restored.
    func testTmuxReattachPredicate() {
        func check(tmux: Bool, quitting: Bool, restore: Bool) -> Bool {
            SessionQuitRestoration.tmuxSessionMayReattach(isTmuxClient: tmux,
                                                          applicationIsQuitting: quitting,
                                                          willRestoreWindowsAtNextLaunch: restore)
        }
        XCTAssertTrue(check(tmux: true, quitting: true, restore: true))
        XCTAssertFalse(check(tmux: true, quitting: false, restore: true),
                       "closing a pane while the app keeps running is a real close")
        XCTAssertFalse(check(tmux: true, quitting: true, restore: false),
                       "a quit without restoration (including Option-Quit) is a real close")
        XCTAssertFalse(check(tmux: false, quitting: true, restore: true),
                       "a non-tmux session is covered by sessionWillBeRestored")
    }

    // -[PTYSession terminate] clears tmuxMode before it posts
    // iTermSessionWillTerminate, so observers cannot ask the session whether
    // it was a tmux client. The notification carries that instead, and the
    // predicate reads it from there.
    func testWillTerminateNotificationReportsTmuxClient() throws {
        for tmux in [false, true] {
            // synthetic: a synthetic session's close is not undoable, so
            // terminate hard-stops it now instead of scheduling a delayed
            // hardStop and an Undo Close entry that would outlive this test.
            let session = try XCTUnwrap(PTYSession(synthetic: true))
            if tmux {
                session.setValue(NSNumber(value: TMUX_CLIENT.rawValue), forKey: "tmuxMode")
                XCTAssertTrue(session.isTmuxClient)
            }
            var posted: Notification?
            let observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name.iTermSessionWillTerminate,
                object: session,
                queue: nil) { posted = $0 }
            session.terminate()
            NotificationCenter.default.removeObserver(observer)

            let notification = try XCTUnwrap(posted)
            XCTAssertFalse(session.isTmuxClient, "terminate clears tmuxMode before posting")
            XCTAssertEqual(SessionQuitRestoration.wasTmuxClient(notification), tmux)
            // Setting tmuxMode queues follow-up work on the main queue; let it
            // run inside this test rather than during a later one.
            RunLoop.main.run(mode: .default, before: .distantPast)
        }
    }
}

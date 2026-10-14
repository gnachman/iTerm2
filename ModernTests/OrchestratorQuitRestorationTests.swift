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

    private func postWillTerminate(_ session: PTYSession) {
        NotificationCenter.default.post(name: NSNotification.Name.iTermSessionWillTerminate,
                                        object: session)
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

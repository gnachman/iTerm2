//
//  OrchestratorClient.swift
//  iTerm2SharedARC
//

import Foundation

// Client-side counterpart to the agent's orchestration tool surface.
// Subscribes to the chat broker; when an agent publishes an
// orchestration tool call as .remoteCommandRequest(.external(...)),
// runs the actual side effects through OrchestratorDispatcher and
// publishes the .remoteCommandResponse that resumes the parked LLM
// completion in ChatAgent.handleRemoteCommandResponse.
//
// This is the architectural mirror of ChatClient for AITerm's
// session-bound RemoteCommand path: the broker is the single
// transport for both directions, and the agent (server side) never
// reaches into PTYSession, iTermController, the workgroup model, or
// any other app state directly. All of that lives in
// OrchestratorDispatcher, which is owned here on the client side.
//
// Dispatcher lifetime is per-chat: created lazily on the first
// orchestration tool request for a chat, torn down on chat deletion
// or when the chat is toggled out of orchestration mode (via
// dropDispatcher(forChatID:)).
//
// @MainActor: the broker is @MainActor and the dispatcher is
// @MainActor; pinning the client to main makes the contract a
// compile-time check.
@MainActor
final class OrchestratorClient {
    private static var _instance: OrchestratorClient?
    static var instance: OrchestratorClient? {
        if _instance == nil, let broker = ChatBroker.instance {
            _instance = OrchestratorClient(broker: broker)
        }
        return _instance
    }

    // Test seam: build an isolated client (NOT the shared singleton, and NOT
    // stored in _instance) so the dispatcher-creation wiring -- which must hand
    // every per-chat dispatcher the SAME typed-input store -- can be exercised
    // end to end. Kept out of the singleton path so a test client never leaks
    // into production lookups.
    static func makeForTesting(broker: ChatBroker) -> OrchestratorClient {
        OrchestratorClient(broker: broker)
    }

    private let broker: ChatBroker
    private var subscription: ChatBroker.Subscription?
    private var chatWasDeletedObserver: NSObjectProtocol?
    private var sessionWillTerminateObserver: NSObjectProtocol?
    private var dispatchers: [String: OrchestratorDispatcher] = [:]
    // One per-session typed-input accumulator shared by every dispatcher this
    // client creates, so the safety gate's accumulator is per-session (keyed by
    // session GUID) rather than per-chat. See OrchestratorTypedInputStore.
    private let typedInput = OrchestratorTypedInputStore()

    private init(broker: ChatBroker) {
        self.broker = broker
        self.subscription = broker.subscribe(
            chatID: nil,
            registrationProvider: nil
        ) { [weak self] update in
            // Broker callbacks can fire from arbitrary contexts (the
            // broker is @MainActor today and the publish-time fan-out
            // is synchronous, but the subscription closure is
            // declared non-isolated). Hop to main before touching
            // dispatcher state.
            Task { @MainActor in
                self?.handle(update: update)
            }
        }
        // Drop the per-chat dispatcher when the chat row is deleted.
        // Mirrors ChatService's chatWasDeleted observer; without
        // this, the dispatcher's NotificationCenter observers and
        // broker subscription leak for the rest of the process
        // lifetime since this client holds the only strong reference.
        // The token is retained and removed in deinit: block-based
        // observers are NOT removed by removeObserver(self) (the observer
        // is an opaque token, not self), so a deinit-able client (e.g.
        // makeForTesting) would otherwise leak this block plus its captured
        // closure onto the process-global center. Mirrors
        // sessionWillTerminateObserver below.
        self.chatWasDeletedObserver = NotificationCenter.default.addObserver(
            forName: ChatListModel.chatWasDeleted,
            object: nil,
            queue: nil) { [weak self] notification in
                // Post site is @MainActor (ChatListModel.delete),
                // delivery is synchronous on the posting thread.
                MainActor.assumeIsolated {
                    guard let chatID = notification.userInfo?[ChatListModel.chatIDUserInfoKey] as? String else {
                        return
                    }
                    self?.dropDispatcher(forChatID: chatID)
                }
            }
        // Clear the shared typed-input store when a session terminates. This
        // lives on the CLIENT (process lifetime) rather than a per-chat
        // dispatcher: a dispatcher's own iTermSessionWillTerminate observer runs
        // only while that chat is open, so if the chat that typed into a session
        // closes before the session dies, the dispatcher-side cleanup never fires
        // and pending[guid]/contaminated[guid] would leak for the rest of the
        // process (GUIDs are never reused). The client owns the store, so this
        // always runs. (Per-dispatcher cleanup stays too -- it's the fast path
        // while the chat is live.)
        // queue: .main (not nil) so the block is delivered on the main thread
        // regardless of the post thread, matching the sibling observers of this
        // notification (OrchestratorDispatcher, SessionProvenanceRegistry) and
        // keeping the MainActor.assumeIsolated below safe. (iTermSessionWillTerminate
        // is posted from -[PTYSession terminate], a main-thread teardown today,
        // but .main guarantees it.)
        self.sessionWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.iTermSessionWillTerminate,
            object: nil,
            queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let session = notification.object as? PTYSession else { return }
                    self.typedInput.pending.removeValue(forKey: session.guid)
                    self.typedInput.contaminated.remove(session.guid)
                }
            }
    }

    deinit {
        subscription?.unsubscribe()
        if let chatWasDeletedObserver {
            NotificationCenter.default.removeObserver(chatWasDeletedObserver)
        }
        if let sessionWillTerminateObserver {
            NotificationCenter.default.removeObserver(sessionWillTerminateObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // Called from ChatViewController.setOrchestrationEnabled(false)
    // when the user toggles a chat out of orchestration mode.
    // Mirrors ChatService.dropAgent so the dispatcher's per-chat
    // watcher state and broker subscription are released along with
    // the agent's tool-call surface.
    func dropDispatcher(forChatID chatID: String) {
        // Synchronously detach broker/observer state before dropping
        // the dict entry. An in-flight handleToolCall Task can still
        // hold a strong ref past the dict removal; without tearDown
        // that orphan would keep delivering tab-status notifications,
        // resume parked permission prompts as if they were live, and
        // publish a posthumous tool_result into a chat that's no
        // longer in orchestration mode.
        if let existing = dispatchers.removeValue(forKey: chatID) {
            existing.tearDown()
        }
    }

    // Turn orchestration off for a chat (ChatViewController's Disable
    // Orchestration, after it drops the agent). Tears down the dispatcher
    // BEFORE the list-model write, for the reason given in
    // ChatViewController.setOrchestrationEnabled, then clears the
    // orchestration-only state, which includes every watcher. Publishes
    // `disabledNotice` and then, if that clear cancelled any pending timers or
    // watches, a notice counting them so the user doesn't keep waiting on
    // them. Both are client-local notices: nothing reaches the model.
    func disableOrchestration(forChatID chatID: String,
                              disabledNotice: String) throws {
        dropDispatcher(forChatID: chatID)
        let cancelled = broker.listModel.watchers(forChatID: chatID)
        try broker.listModel.setOrchestrationEnabled(false, forChatID: chatID)
        try? broker.publishNotice(chatID: chatID, notice: disabledNotice)
        OrchestratorDispatcher.publishCancelledWatchersNotice(broker: broker,
                                                              chatID: chatID,
                                                              cancelled: cancelled,
                                                              cause: .disableOrchestration)
    }

    // MARK: - Broker handler

    private func handle(update: ChatBroker.Update) {
        guard case let .delivery(message, chatID, _) = update else { return }
        switch message.author {
        case .user:
            handleUser(message: message, chatID: chatID)
        case .agent:
            handleAgent(message: message, chatID: chatID)
        }
    }

    // User-authored deliveries that touch the claim set:
    //   - a chat message that @-mentions sessions/workgroups grants a
    //     sticky claim for each named target (skips the later inline
    //     prompt) and posts a revocable notice.
    //   - the Revoke button on such a notice sends
    //     revokeOrchestrationPermission, which drops the claim.
    // Gated on orchestrationEnabled: session-bound chats use the
    // per-call permission model and never carry claimedScopes. Both
    // paths route through dispatcher(forChatID:), which creates the
    // per-chat dispatcher if it doesn't exist yet (the user can mention
    // a session before the agent has made its first tool call, and can
    // revoke after a restart before any tool call recreates it).
    private func handleUser(message: Message, chatID: String) {
        guard broker.listModel.chat(id: chatID)?.orchestrationEnabled == true else {
            return
        }
        switch message.content {
        case .plainText(let text, _):
            grantClaims(fromUserText: text, chatID: chatID)
        case .multipart(let subparts, _):
            // Mentions ride in the text subparts; attachments/context
            // can't carry one. Grant off the concatenated user text.
            let text = subparts.compactMap { subpart -> String? in
                switch subpart {
                case .plainText(let t), .markdown(let t): return t
                case .attachment, .context: return nil
                }
            }.joined(separator: "\n")
            grantClaims(fromUserText: text, chatID: chatID)
        case .userCommand(.revokeOrchestrationPermission(let scope)):
            dispatcher(forChatID: chatID).revokeClaim(scope: scope)
        default:
            break
        }
    }

    private func grantClaims(fromUserText text: String, chatID: String) {
        guard !MentionParser.mentions(in: text).isEmpty else { return }
        dispatcher(forChatID: chatID).grantClaimsFromMentions(in: text)
    }

    private func handleAgent(message: Message, chatID: String) {
        guard case let .remoteCommandRequest(payload, _) = message.content else { return }
        guard case let .external(ext) = payload else { return }
        let requestID = message.uniqueID
        Task { @MainActor [weak self] in
            await self?.dispatch(external: ext,
                                 requestID: requestID,
                                 chatID: chatID)
        }
    }

    // Runs the dispatcher for one external tool call and publishes
    // the response. The completion that the agent parked in
    // pendingRemoteCommands[requestID] is resumed when the broker
    // delivers the response back through
    // ChatService → ChatAgent.fetchCompletion →
    // handleRemoteCommandResponse.
    private func dispatch(external ext: ExternalRemoteCommand,
                          requestID: UUID,
                          chatID: String) async {
        let dispatcher = self.dispatcher(forChatID: chatID)
        let argsData = Data(ext.argsJSON.utf8)
        let resultData = await dispatcher.handleToolCall(
            name: ext.name,
            jsonArgs: argsData,
            llmMessage: ext.llmMessage)
        let resultString = String(decoding: resultData, as: UTF8.self)
        let functionCallID = ext.llmMessage.functionCallID
        do {
            try broker.publish(
                message: Message(
                    chatID: chatID,
                    author: .user,
                    content: .remoteCommandResponse(
                        .success(resultString),
                        requestID,
                        ext.name,
                        functionCallID),
                    sentDate: Date(),
                    uniqueID: UUID()),
                toChatID: chatID,
                partial: false)
        } catch {
            RLog("OrchestratorClient: failed to publish tool response: \(error)")
        }
    }

    // Drop a chat's session watchers when it is unlinked from its terminal
    // session (and stays session-bound). Timers target no session and are kept.
    // A live dispatcher tears down the dropped watchers' pollers; with no live
    // dispatcher there are no running pollers, so just rewrite the persisted
    // set directly. NOT called when a chat
    // leaves its link by becoming an orchestration chat (that path keeps
    // watchers) -- the caller (unlink action) enforces that distinction.
    func cancelWatchers(forChatID chatID: String) {
        if let existing = dispatchers[chatID] {
            existing.cancelWatchersOnUnlink()
        } else {
            let kept = OrchestratorDispatcher.watchersKeptOnUnlink(
                broker.listModel.watchers(forChatID: chatID))
            try? broker.listModel.setWatchers(kept, forChatID: chatID)
        }
    }

    // Re-arm timers persisted before an app restart so a fired (or overdue) timer
    // wakes its chat's agent even if the user never reopens any chat -- e.g. a
    // Sparkle upgrade that quits and relaunches while a timer's deadline passes.
    // Unlike a state/condition watch (whose reason to fire is a live session
    // changing, which can't happen while iTerm2 is down), a timer's deadline can
    // elapse during the downtime, so it must be re-armed eagerly rather than
    // lazily on next chat open.
    //
    // Scans the (already in-memory) chat list for timer-bearing chats; only if
    // one exists does it boot the chat service and instantiate that chat's
    // dispatcher, which runs reconcilePersistedWatchers once launch-time session
    // restoration finishes (see SessionRestorationGate) -- re-arming each
    // timer and firing any whose time already passed. Idempotent: a chat whose
    // dispatcher already exists is left as-is, and armTimer self-guards against
    // double-arming. Called once at launch (see iTermChatTimerLaunch).
    @MainActor
    static func rearmPersistedTimersAtLaunch() {
        // Under the administrator lockout a timer must not wake its chat (that
        // sends the chat to the LLM), so leave persisted timers dormant.
        guard iTermAdvancedSettingsModel.generativeAIAllowed() else {
            RLog("Not re-arming persisted AI chat timers: generative AI is disallowed by the administrator")
            return
        }
        guard let broker = ChatBroker.instance else { return }
        let model = broker.listModel
        var timerChatIDs = [String]()
        for i in 0..<model.count {
            let chat = model.chat(at: i)
            if chat.watchers.contains(where: { $0.effectiveMode == .timer }) {
                timerChatIDs.append(chat.id)
            }
        }
        guard !timerChatIDs.isEmpty else { return }
        // A fired timer publishes a status_update the chat service turns into an
        // agent turn; boot it so that consumer exists even with no chat window.
        broker.ensureServiceRunning()
        guard let client = instance else { return }
        for chatID in timerChatIDs {
            _ = client.dispatcher(forChatID: chatID)
        }
    }

    // Internal (not private) so wiring tests can obtain two dispatchers for two
    // chatIDs and confirm they share this client's single typed-input store.
    func dispatcher(forChatID chatID: String) -> OrchestratorDispatcher {
        if let existing = dispatchers[chatID] {
            return existing
        }
        let created = OrchestratorDispatcher(chatID: chatID, broker: broker,
                                             typedInput: typedInput)
        dispatchers[chatID] = created
        return created
    }
}

// ObjC shim for the launch-time timer re-arm. The app delegate is Objective-C
// and can't see OrchestratorClient (a MainActor Swift class); this NSObject
// subclass gives it a plain selector to call from applicationDidFinishLaunching.
@objc(iTermChatTimerLaunch)
final class iTermChatTimerLaunch: NSObject {
    @objc static func rearmPersistedTimers() {
        // applicationDidFinishLaunching runs on the main thread, so we're already
        // in the MainActor's execution context; assert that rather than hop.
        MainActor.assumeIsolated {
            OrchestratorClient.rearmPersistedTimersAtLaunch()
        }
    }

    // Called by the app delegate once window restoration (and the buried and
    // orphaned session adoption that follows it) has created the sessions it
    // is going to create. Dispatchers built earlier reconcile their persisted
    // watchers now.
    @objc static func sessionsDidFinishRestoring() {
        MainActor.assumeIsolated {
            SessionRestorationGate.shared.markReady()
        }
    }
}

// One-shot latch for “launch-time session restoration is done.” Until it
// opens, an OrchestratorDispatcher defers reconciling its persisted watchers,
// because a watched session that hasn't been restored yet is indistinguishable
// from one that is gone for good. Tests construct their own instance.
@MainActor
final class SessionRestorationGate {
    static let shared = SessionRestorationGate()

    private(set) var isReady = false
    private var waiters = [() -> Void]()

    init(ready: Bool = false) {
        isReady = ready
    }

    // Runs block now if the gate is open, otherwise once it opens.
    func whenReady(_ block: @escaping () -> Void) {
        if isReady {
            block()
        } else {
            waiters.append(block)
        }
    }

    func markReady() {
        guard !isReady else { return }
        RLog("Session restoration complete; releasing \(waiters.count) deferred watcher reconciliations")
        isReady = true
        let pending = waiters
        waiters.removeAll()
        for block in pending {
            block()
        }
    }
}

// Whether a session terminating right now is being torn down by an app quit
// that window restoration will undo. An ordinary quit closes every window,
// which terminates every session and posts iTermSessionWillTerminate, but
// when windows will be restored at the next launch each session comes back
// with the same stableID. A chat's link to such a session, and the watches and
// timers it registered, must outlive that teardown. “Quit and Close All
// Windows” (Option-Quit) discards the saved state, which turns off
// willRestoreWindowsAtNextLaunch, so it unlinks like a real close. tmux client
// sessions are not saved for restoration (reattaching creates new sessions),
// so their termination is always treated as a real close.
enum SessionQuitRestoration {
    // Takes an iTermSessionWillTerminate notification.
    @MainActor
    static func sessionWillBeRestoredAfterQuit(_ notification: Notification) -> Bool {
        // Sessions are terminated by -[iTermController cleanUpIfNeeded] while
        // the shared instance still exists. Once it is gone nothing can say
        // whether windows will be restored, so behave like a real close.
        guard let controller = iTermController.sharedInstance() else {
            return false
        }
        return sessionWillBeRestored(isTmuxClient: wasTmuxClient(notification),
                                     applicationIsQuitting: controller.applicationIsQuitting,
                                     willRestoreWindowsAtNextLaunch: controller.willRestoreWindowsAtNextLaunch)
    }

    // -[PTYSession terminate] clears tmuxMode before posting, so the
    // session's isTmuxClient is always false by now; read the value it
    // captured beforehand.
    static func wasTmuxClient(_ notification: Notification) -> Bool {
        (notification.userInfo?[iTermSessionWillTerminateWasTmuxClientKey] as? NSNumber)?.boolValue ?? false
    }

    static func sessionWillBeRestored(isTmuxClient: Bool,
                                      applicationIsQuitting: Bool,
                                      willRestoreWindowsAtNextLaunch: Bool) -> Bool {
        return !isTmuxClient && applicationIsQuitting && willRestoreWindowsAtNextLaunch
    }
}

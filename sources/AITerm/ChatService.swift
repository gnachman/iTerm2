//
//  ChatService.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

// Imaginary server. Subscribes to ChatBroker and routes each chat's
// user-side traffic through a per-chat ChatAgent. ChatAgent is the
// one agent class; it runs in session-bound or orchestration mode
// based on Chat.orchestrationEnabled, and publishes its replies back
// through the same broker so the client (chat VC) receives them via
// the broker subscription path.
@MainActor
class ChatService {
    private static var _instance: ChatService?
    static var instance: ChatService? {
        if _instance == nil {
            _instance = ChatService()
        }
        return _instance
    }
    private var agents = [String: ChatAgent]()
    // Keyed by chatID so dropAgent can release the matching context.
    // The previous flat array leaked one context per chat the user ever
    // opened for the lifetime of the process.
    private var registrationContexts = [String: RegistrationContext]()
    private let listModel: ChatListModel
    private let broker: ChatBroker

    // Per-chat queue of messages waiting for the agent. The agent
    // processes one turn at a time so the conversation history never
    // gets an in-flight tool call clobbered by a new turn. User
    // messages and (in orchestration mode) async watcher events share
    // the queue; messages that don't drive an LLM turn (clientLocal,
    // userCommand, setPermissions) bypass it. Keyed by chatID; the
    // first element is the in-flight message, the rest pending;
    // absent entry means idle.
    private var pendingMessages: [String: [Message]] = [:]

    init?() {
        guard let listModel = ChatListModel.instance, let broker = ChatBroker.instance else {
            return nil
        }
        self.listModel = listModel
        self.broker = broker
        _ = broker.subscribe(chatID: nil, registrationProvider: nil) { [weak self] update in
            self?.handle(update)
        }
        // Drop the per-chat agent (and any orchestrator dispatcher it
        // owns) when the chat row is removed. Without this the agent
        // and its NotificationCenter observers leak for the rest of
        // the process lifetime since ChatService holds the only strong
        // reference.
        // queue: nil means the block runs synchronously on the posting
        // thread. We *want* synchronous behavior here: ChatListModel.delete
        // is called from main-isolated code (ChatBroker.delete /
        // ChatViewController), and if dropAgent doesn't run until a later
        // runloop tick, an in-flight agent can still publish messages back
        // into ChatListModel.append for a now-orphaned chatID before we
        // tear it down. Passing queue: .main would defer the dispatch and
        // open exactly that window. (DispatchQueue.main scheduling is
        // not the same as "synchronously on main"; it's a separate
        // runloop turn.)
        NotificationCenter.default.addObserver(
            forName: ChatListModel.chatWasDeleted,
            object: nil,
            queue: nil) { [weak self] notification in
                // The post site is @MainActor, so the synchronous
                // delivery puts us on main here. The closure type is
                // nonisolated, so we still need assumeIsolated to call
                // into MainActor-bound code.
                MainActor.assumeIsolated {
                    guard let chatID = notification.userInfo?[ChatListModel.chatIDUserInfoKey] as? String else {
                        return
                    }
                    self?.dropAgent(forChatID: chatID)
                }
            }
    }

    private func handle(_ update: ChatBroker.Update) {
        switch update {
        case .typingStatus:
            break
        case let .delivery(message, chatID, _):
            switch message.author {
            case .agent:
                // Ignore messages from myself
                break
            case .user:
                handleUserMessage(message, inChat: chatID)
            }
        }
    }

    // Single entry point for every user-author message the broker
    // delivers. Four classes of message take off-queue exits:
    //
    //   - .clientLocal: UI-only state, never reaches the agent.
    //   - .userCommand: control plane (stop / orchestration toggle
    //     responses / orchestrator dispatcher hooks). Handled synchronously;
    //     no LLM turn.
    //   - .setPermissions: agent-state side effect only, no LLM
    //     round-trip. Applied immediately so a permission toggle
    //     mid-stream affects the next turn rather than being stuck
    //     behind it.
    //   - .remoteCommandResponse: resumes a parked tool-call
    //     dispatcher inside the IN-FLIGHT turn (the one that called
    //     the tool); it doesn't start a new turn. Enqueueing it
    //     would deadlock — the in-flight turn would wait for its
    //     tool result while the tool result waits in line behind the
    //     turn that's blocking on it.
    //
    // Everything else enqueues; the queue runs one turn at a time.
    private func handleUserMessage(_ message: Message, inChat chatID: String) {
        switch message.content {
        case .clientLocal:
            return

        case .userCommand(let command):
            handleUserCommand(command, inChat: chatID)
            return

        case .setPermissions:
            applySetPermissions(message, inChat: chatID)
            return

        case .remoteCommandResponse:
            deliverToolResult(message, inChat: chatID)
            return

        case .unsupported:
            // A placeholder for a message type this build doesn't
            // understand. It's display-only; never start an agent turn
            // for it. (In practice the Mac is always the newest build
            // and won't author one, but the broker round-trips every
            // message type through here.)
            return

        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandRequest, .selectSessionRequest,
                .renameChat, .append, .appendAttachment, .commit, .vectorStoreCreated,
                .terminalCommand, .multipart, .watcherEvent:
            enqueue(message: message, inChat: chatID)
        }
    }

    // Route a user-side .remoteCommandResponse directly to the agent
    // instead of through the per-chat queue. The agent's
    // fetchCompletion → handleRemoteCommandResponse resumes the
    // parked dispatcher continuation, which lets the in-flight
    // conversation.complete callback eventually fire and the
    // surrounding turn finish via the queue's normal finishTurn path.
    private func deliverToolResult(_ message: Message, inChat chatID: String) {
        guard let agent = agents[chatID] else {
            // No agent means no in-flight tool dispatch; nothing to
            // resume. The response message stays in history but
            // shouldn't kick off a new turn.
            return
        }
        try? agent.fetchCompletion(
            userMessage: message,
            history: historyExcluding(message, inChat: chatID),
            streaming: nil) { _ in }
    }

    private func handleUserCommand(_ command: UserCommand, inChat chatID: String) {
        switch command {
        case .stop:
            agents[chatID]?.stop()
        case .workgroupPermissionResponse, .revokeOrchestrationPermission:
            // Consumed by the orchestrator dispatcher / client via their
            // own broker subscriptions. The service shouldn't loop these
            // back to the LLM.
            break
        case let .enableOrchestrationResponse(requestID, approved):
            // The request_orchestration_enable tool parks the LLM
            // completion; resume it. The agent's pending map is empty
            // outside session-bound mode, so this is a no-op in
            // orchestration mode.
            agents[chatID]?.handleOrchestrationResponse(
                requestID: requestID, approved: approved)
        }
    }

    private func applySetPermissions(_ message: Message, inChat chatID: String) {
        // No-op outside session-bound mode; the agent's
        // handleSetPermission short-circuits, but we also skip the
        // typing-indicator flash that going through agentWorking would
        // produce.
        let history = historyExcluding(message, inChat: chatID)
        let agent = agents[chatID] ?? newAgent(
            forChatID: chatID,
            mode: agentMode(forChatID: chatID),
            messages: ArraySlice(history))
        try? agent.fetchCompletion(
            userMessage: message,
            history: history,
            streaming: nil) { _ in }
    }

    private func enqueue(message: Message, inChat chatID: String) {
        var queue = pendingMessages[chatID] ?? []
        queue.append(message)
        pendingMessages[chatID] = queue
        if queue.count == 1 {
            startNextTurn(forChatID: chatID)
        }
    }

    private func startNextTurn(forChatID chatID: String) {
        guard let message = pendingMessages[chatID]?.first else { return }
        agentWorking(chatID: chatID) { [weak self] stopTyping in
            guard let self else { return }
            let history = self.historyExcluding(message, inChat: chatID)
            let agent = self.agents[chatID] ?? self.newAgent(
                forChatID: chatID,
                mode: self.agentMode(forChatID: chatID),
                messages: ArraySlice(history))
            let streaming: ((StreamingUpdate) -> ())? = agent.supportsStreaming
                ? { [weak self] update in
                    self?.publishStreamingUpdate(update, toChatID: chatID)
                  }
                : nil
            do {
                try agent.fetchCompletion(
                    userMessage: message,
                    history: history,
                    streaming: streaming,
                    completion: { [weak self] reply in
                        stopTyping()
                        self?.finishTurn(chatID: chatID, reply: reply)
                    })
            } catch {
                RLog("ChatService fetchCompletion failed: \(error)")
                stopTyping()
                self.finishTurn(chatID: chatID, reply: nil)
            }
        }
    }

    private func finishTurn(chatID: String, reply: Message?) {
        if let reply {
            try? broker.publish(message: reply, toChatID: chatID, partial: false)
        }
        var queue = pendingMessages[chatID] ?? []
        if !queue.isEmpty {
            queue.removeFirst()
        }
        if queue.isEmpty {
            pendingMessages.removeValue(forKey: chatID)
        } else {
            pendingMessages[chatID] = queue
            startNextTurn(forChatID: chatID)
        }
    }

    private func agentMode(forChatID chatID: String) -> ChatAgent.Mode {
        let orchestration = listModel.chat(id: chatID)?.orchestrationEnabled ?? false
        return orchestration ? .orchestration : .sessionBound
    }

    // MARK: - Shared helpers

    private func publishStreamingUpdate(_ update: StreamingUpdate, toChatID chatID: String) {
        switch update {
        case .begin(let initial):
            try? broker.publish(message: initial, toChatID: chatID, partial: true)
        case .append(let chunk, let uuid):
            try? broker.publish(
                message: Message(chatID: chatID,
                                 author: .agent,
                                 content: .append(string: chunk, uuid: uuid),
                                 sentDate: Date(),
                                 uniqueID: UUID()),
                toChatID: chatID,
                partial: true)
        case .appendAttachment(let attachment, let uuid):
            try? broker.publish(
                message: Message(chatID: chatID,
                                 author: .agent,
                                 content: .appendAttachment(attachment: attachment, uuid: uuid),
                                 sentDate: Date(),
                                 uniqueID: UUID()),
                toChatID: chatID,
                partial: true)
        }
    }

    // Exclude client-local messages because the agent only knows about them because  it shares a
    // model with the client, which it probably shouldn't.
    private func messages(chatID: String) -> [Message] {
        guard let dbArray = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return []
        }
        return Array(dbArray.filter { !$0.isClientLocal })
    }

    // Build the LLM-history slice for an about-to-dispatch turn.
    //
    // The persisted DB rows are not the LLM history. Two cases cause
    // drift:
    //   - The agent rebuilds the LLM conversation from this slice and
    //     then re-adds `message` itself via fetchCompletion's
    //     userMessage parameter, so `message` must not appear here or
    //     it ships duplicated.
    //   - When the user types while a turn is already in flight (or
    //     types several messages in a row), the queued messages are
    //     persisted immediately but belong to *future* turns. They
    //     also must not appear in the current turn's history.
    //
    // Net rule: history = persisted rows minus (pendingMessages ∪
    // {message}). The legacy `dropLast()` approach assumed the last
    // row WAS the in-flight message, which is only true when nothing
    // landed between the message's persistence and its dispatch
    // (single-message case, no interleave). This filter is correct
    // for the interleaved case too.
    private func historyExcluding(_ message: Message, inChat chatID: String) -> [Message] {
        var excluded = Set<UUID>([message.uniqueID])
        if let pending = pendingMessages[chatID] {
            for p in pending {
                excluded.insert(p.uniqueID)
            }
        }
        return messages(chatID: chatID).filter { !excluded.contains($0.uniqueID) }
    }

    private func newAgent(forChatID chatID: String,
                          mode: ChatAgent.Mode,
                          messages: ArraySlice<Message>) -> ChatAgent {
        it_assert(agents[chatID] == nil)

        let reg = RegistrationContext(chatID: chatID, broker: broker)
        registrationContexts[chatID] = reg
        let agent = ChatAgent(
            chatID,
            broker: broker,
            mode: mode,
            registrationProvider: reg,
            messages: Array(messages))
        self.agents[chatID] = agent
        return agent
    }

    // Drop the in-flight ChatAgent for this chat. The orchestrator
    // dispatcher (if any) is released via the agent's deinit, which
    // unsubscribes from the broker and removes tab-status observers.
    // The next user message will spin up a fresh agent in whatever
    // mode the chat row currently dictates.
    //
    // Called from the toggle path when the user flips
    // orchestrationEnabled. The existing agent's mode is now stale.
    //
    // Order matters: clear pendingMessages BEFORE agent.stop(). stop()
    // calls cancelOutstandingOperation(), which synchronously fires
    // aitermControllerDidCancelOutstandingRequest and walks back up
    // through fetchCompletion's completion to finishTurn. If
    // pendingMessages still has entries at that point, finishTurn
    // would call startNextTurn, which would build a fresh agent using
    // the (already-toggled) listModel mode and install it into
    // agents[chatID]. Then the agents.removeValue below would evict
    // that brand-new agent, dropping it mid-turn with an in-flight
    // LLM call.
    func dropAgent(forChatID chatID: String) {
        pendingMessages.removeValue(forKey: chatID)
        agents[chatID]?.stop()
        agents.removeValue(forKey: chatID)
        registrationContexts.removeValue(forKey: chatID)
    }

    private class RegistrationContext: AIRegistrationProvider {
        private let chatID: String
        private let broker: ChatBroker

        init(chatID: String, broker: ChatBroker) {
            self.chatID = chatID
            self.broker = broker
        }
        func registrationProviderRequestRegistration(_ completion: @escaping (AITermController.Registration?) -> ()) {
            registrationProviderRequestRegistration(for: LLMMetadata.effectiveVendor, completion)
        }

        func registrationProviderRequestRegistration(for vendor: iTermAIVendor,
                                                     _ completion: @escaping (AITermController.Registration?) -> ()) {
            // AIRegistrationProvider is a protocol with no MainActor
            // isolation, but every call site reaches us from a
            // main-isolated stack (ChatAgent's AIConversation.prepare
            // closure runs on main). assumeIsolated lets us invoke
            // broker.requestRegistration, which is now @MainActor.
            MainActor.assumeIsolated {
                broker.requestRegistration(chatID: chatID,
                                           for: vendor,
                                           completion: completion)
            }
        }
    }

    func agentWorking(chatID: String, closure: (@escaping () -> ()) -> ()) {
        broker.publish(typingStatus: true, of: .agent, toChatID: chatID)
        closure() {
            self.broker.publish(typingStatus: false, of: .agent, toChatID: chatID)
        }
    }
}

//
//  ChatAgent.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

fileprivate extension AITermController.Message {
    static func role(from message: Message) -> LLM.Role {
        // Tool results are persisted as user-authored Messages, but on the LLM
        // side they have to be carried as role=.function so the per-vendor
        // request builders route them through the right serializer branch:
        // DeepSeek maps .function -> "tool" (otherwise the wire stays "user"
        // with a tool_call_id, which DeepSeek 400s with "insufficient tool
        // messages"), OpenAI Responses keys functionToolCallOutput off
        // role=.function (without this it logs "Unexpected user message body"
        // and drops the item). Anthropic and Gemini already accept either —
        // Anthropic special-cases functionOutput bodies before the role
        // switch, Gemini maps .function-without-function_call to "user".
        // Production live calls construct tool results with role=.function
        // directly (AITerm.swift around line 957); this keeps the chat-reload
        // path in lockstep with that invariant.
        switch message.content {
        case .remoteCommandResponse: return .function
        default: break
        }
        return switch message.author {
        case .user: .user
        case .agent: .assistant
        }
    }
}

extension Message {
    var functionCallName: String? {
        switch content {
        case .remoteCommandRequest(let request, safe: _):
            return request.llmMessage.function_call?.name
        case .remoteCommandResponse(_, _, let name, _):
            return name
        default:
            return nil
        }
    }

    var functionCall: LLM.FunctionCall? {
        switch content {
        case .remoteCommandRequest(let request, safe: _):
            return request.llmMessage.function_call
        default:
            return nil
        }
    }

    var functionCallID: LLM.Message.FunctionCallID? {
        switch content {
        case .remoteCommandRequest(let request, safe: _):
            return request.llmMessage.functionCallID
        case .remoteCommandResponse(_, _, _, let id):
            return id
        default:
            return nil
        }
    }
}

@MainActor
class ChatAgent {
    // Which tool surface this agent drives. Determined at init from
    // Chat.orchestrationEnabled and not changed for the agent's
    // lifetime; when the user toggles a chat's mode the existing
    // agent is replaced rather than mutated, because the conversation
    // history's tool-call shape would otherwise be inconsistent.
    enum Mode {
        case sessionBound
        case orchestration
    }

    // Mutable so the agent can transition from session-bound to
    // orchestration in place when the user approves the agent's
    // request_orchestration_enable tool call. The conversation
    // history and any in-flight tool result delivery are preserved
    // across the transition; the LLM sees the new tool surface and
    // system prompt on its next turn.
    private var mode: Mode
    private var conversation: AIConversation!
    private let chatID: String
    private var brokerSubscription: ChatBroker.Subscription?
    private var messageToPrompt = MessageToPromptStateMachine()
    private var pendingRemoteCommands = [UUID: PendingRemoteCommand]()
    private let broker: ChatBroker
    private let prepPipeline: MessagePrepPipeline
    private var lastSystemMessage: String?
    private var toolProviders: [ToolProvider] = []

    // Optional developer-only console trace of chat-agent traffic.
    // Gated on the advanced setting "aiChatVerboseConsoleLogging";
    // does nothing when off.
    private let consoleLogger: ChatAgentConsoleLogger

    // request_orchestration_enable tool: keyed by request UUID, the
    // LLM-framework completion is parked until the user clicks
    // Enable or Not Now (or the chat tears down).
    private var pendingOrchestrationRequests: [String: (Result<String, Error>) throws -> ()] = [:]

    struct PendingRemoteCommand {
        var completion: (Result<String, Error>) throws -> ()
        var responseID: String?
    }

    private var permissions: Set<RemoteCommand.Content.PermissionCategory>!
    private let registrationProvider: AIRegistrationProvider

    init(_ chatID: String,
         broker: ChatBroker,
         mode: Mode,
         registrationProvider: AIRegistrationProvider,
         messages: [Message]) {
        self.chatID = chatID
        self.broker = broker
        self.mode = mode
        self.registrationProvider = registrationProvider
        self.prepPipeline = MessagePrepPipeline(chatID: chatID)
        self.consoleLogger = ChatAgentConsoleLogger(chatID: chatID)
        permissions = Set<RemoteCommand.Content.PermissionCategory>()
        conversation = AIConversation(registrationProvider: registrationProvider)
        conversation.hostedTools.codeInterpreter = true

        switch mode {
        case .sessionBound:
            toolProviders = [
                RemoteCommandToolProvider(
                    allowedCategories: { [weak self] in self?.permissions ?? [] },
                    dispatcher: { [weak self] command, responseID, completion in
                        try self?.runRemoteCommand(command, responseID, completion: completion)
                    }),
                OrchestrationToolProvider.sessionBound(
                    enableRequestHandler: { [weak self] completion in
                        self?.parkOrchestrationRequest(completion: completion)
                    }),
            ]
        case .orchestration:
            toolProviders = [
                OrchestrationToolProvider.orchestration(
                    externalInvoker: { [weak self] name, llmMessage, args, completion in
                        self?.publishExternalToolRequest(
                            name: name,
                            llmMessage: llmMessage,
                            args: args,
                            completion: completion)
                    }),
            ]
            // System prompt is built from the user-customizable
            // kPreferenceKeyAIPromptAIChatOrchestration preference and
            // refreshed in load(messages:).
        }

        // toolProviders / mode are all initialized now, so it's safe
        // to share `self` with the prep pipeline.
        prepPipeline.delegate = self

        load(messages: messages)
    }

    private func flushPendingAgentText() {
        consoleLogger.flushPendingAgentText()
    }

    // MARK: - request_orchestration_enable

    // Park the LLM-framework completion and publish the request bubble.
    // The chat UI renders Enable / Not Now buttons; clicking one
    // publishes a UserCommand.enableOrchestrationResponse which the
    // ChatService routes to handleOrchestrationResponse below.
    private func parkOrchestrationRequest(
        completion: @escaping (Result<String, Error>) throws -> ()
    ) {
        let requestID = UUID().uuidString
        pendingOrchestrationRequests[requestID] = completion
        do {
            try broker.publishMessageFromAgent(
                chatID: chatID,
                content: .clientLocal(
                    .init(action: .enableOrchestrationRequest(requestID: requestID))))
        } catch {
            DLog("Failed to publish enable-orchestration request: \(error)")
            pendingOrchestrationRequests.removeValue(forKey: requestID)
            try? completion(.success("Failed to surface the request: \(error.localizedDescription)"))
        }
    }

    // Called by ChatService when a UserCommand.enableOrchestrationResponse
    // arrives. On approval, flips the chat's orchestrationEnabled flag
    // and transitions this agent in place to orchestration mode (the
    // next turn will register orchestrator tools and use the
    // orchestrator system prompt); on decline, just resumes the tool
    // call with a "user declined" string.
    func handleOrchestrationResponse(requestID: String, approved: Bool) {
        guard let completion = pendingOrchestrationRequests.removeValue(forKey: requestID) else {
            return
        }
        if approved {
            do {
                try ChatListModel.instance?.setOrchestrationEnabled(true, forChatID: chatID)
            } catch {
                // Persistence failed, so the in-memory transition would
                // leave the DB row out of sync with the agent and the
                // next app launch would rebuild this chat as
                // session-bound while the conversation history already
                // references orchestrator tool calls.
                DLog("Failed to set orchestrationEnabled: \(error)")
                try? completion(.success(
                    "Failed to enable orchestration: \(error.localizedDescription). "
                    + "The chat remains in its current mode."))
                return
            }
            transitionToOrchestration()
            // transitionToOrchestration() has already swapped the
            // conversation's tool registry to the orchestration surface,
            // so the very next outbound request on THIS turn carries the
            // orchestration tools. Tell the LLM what's actually true: it
            // can use the tools immediately, including for the
            // continuation of this turn if useful.
            try? completion(.success(
                "Orchestration is now active for the rest of this conversation. The orchestration "
                + "toolset (send_text, get_state, list_workgroups, register_watch, "
                + "start_code_review, etc.) is available to you now and you may call those tools "
                + "in the continuation of this turn or any subsequent turn."))
        } else {
            try? completion(.success("User declined to enable orchestration."))
        }
    }

    // In-place mode swap. Replaces the session-bound tool providers
    // with the orchestration provider, swaps in the orchestrator
    // system prompt, and marks systemMessageDirty so the LLM sees
    // the change on the next turn. The conversation history stays
    // intact. The OrchestratorDispatcher lives on the client side
    // (OrchestratorClient) and is created lazily there on the first
    // orchestration tool request for this chat.
    private func transitionToOrchestration() {
        guard mode != .orchestration else { return }
        mode = .orchestration

        // Cancel any session-bound RemoteCommand parked completions
        // BEFORE swapping tool providers. If a parked completion
        // resumed after the swap, its tool_result would arrive in the
        // orchestration conversation referring to a tool_use the LLM's
        // new tool surface doesn't include, producing an Anthropic
        // 400 (no matching tool_use). Resuming them now with
        // PendingCommandCanceled at least gives the conversation a
        // matched tool_result for the in-flight tool_use that the
        // session-bound providers had registered.
        cancelPendingCommands()

        let provider = OrchestrationToolProvider.orchestration(
            externalInvoker: { [weak self] name, llmMessage, args, completion in
                self?.publishExternalToolRequest(
                    name: name,
                    llmMessage: llmMessage,
                    args: args,
                    completion: completion)
            })
        toolProviders = [provider]
        updateOrchestrationSystemMessage()
        registerToolProviders()
    }

    // Publish an orchestration tool request to the broker and park
    // the LLM completion in pendingRemoteCommands. The actual
    // dispatch (PTYSession writes, session spawning, watcher
    // registration, etc.) is owned by OrchestratorClient on the
    // client side; it subscribes to the broker, runs the dispatcher,
    // and publishes a .remoteCommandResponse carrying the same
    // requestID. That response routes back into
    // handleRemoteCommandResponse, which resumes the parked
    // completion the same way the session-bound RemoteCommand path
    // does. The agent never touches PTYSession or the dispatcher
    // directly — the broker is the only transport.
    private func publishExternalToolRequest(
        name: String,
        llmMessage: AITermController.Message,
        args: AnyCodable,
        completion: @escaping (Result<String, Error>) throws -> ()
    ) {
        let requestID = UUID()
        pendingRemoteCommands[requestID] = .init(completion: completion, responseID: nil)
        // Flush any accumulated agent narrative into the log before
        // the tool entry (keeps Console output in chronological order).
        flushPendingAgentText()

        let argsData: Data
        if let dict = args.value as? [String: Any] {
            argsData = (try? JSONSerialization.data(
                withJSONObject: dict,
                options: [.sortedKeys])) ?? Data("{}".utf8)
        } else {
            argsData = Data("{}".utf8)
        }
        let argsString = String(decoding: argsData, as: UTF8.self)
        let markdown = OrchestrationToolProvider.humanDescription(
            forToolName: name, args: args)
        let payload = RemoteCommandPayload.external(ExternalRemoteCommand(
            llmMessage: llmMessage,
            name: name,
            argsJSON: argsString,
            markdownDescription: markdown))
        consoleLogger.logTool(.request, name: name, body: argsString)
        do {
            try broker.publish(
                message: Message(chatID: chatID,
                                 author: .agent,
                                 content: .remoteCommandRequest(payload, safe: nil),
                                 sentDate: Date(),
                                 uniqueID: requestID),
                toChatID: chatID,
                partial: false)
        } catch {
            // Drop the parked completion and surface the failure to
            // the LLM rather than leaving it parked forever.
            DLog("Failed to publish orchestration tool request: \(error)")
            pendingRemoteCommands.removeValue(forKey: requestID)
            try? completion(.failure(error))
        }
    }

    private func load(messages: [Message]) {
        // Pre-pass: extract the latest setPermissions as agent state.
        // The translator below skips .setPermissions itself; this is
        // the only side effect history translation needs. Walk
        // backwards and stop on the first match so long histories
        // don't pay an O(n) scan when permissions almost always live
        // near the head.
        for message in messages.reversed() {
            if case .setPermissions(let updated) = message.content {
                permissions = updated
                break
            }
        }
        // Pair any orphaned tool_result with a synthesized tool_use, and any
        // orphaned tool_use with a synthesized tool_result, so the vendor
        // doesn't reject the rebuilt prompt. Heals conversations that were
        // serialized before this fix as well as new ones.
        conversation.messages = AIChatToolCallRepair.repairingOrphanedToolPairs(
            translate(messages: messages))

        switch mode {
        case .sessionBound:
            updateSystemMessage(permissions)
        case .orchestration:
            // Rebuild the orchestration system prompt from the user's
            // preference (the saved-prompts list / default code-review
            // prompt can change between turns), then re-register tools
            // to track any provider state changes.
            updateOrchestrationSystemMessage()
            registerToolProviders()
        }
    }

    // Mode-agnostic history translation. A chat's persisted history
    // can carry messages from both AITerm and orchestration eras
    // because the user can flip the chat's mode at runtime; the
    // translator handles every Message.Content variant the same way
    // regardless of current mode, so old turns from the other mode
    // stay legible to the LLM.
    //
    // Cross-message reconciliation: any .remoteCommandRequest without
    // a matching .remoteCommandResponse (because iTerm2 was quit
    // mid-tool-call) gets a synthetic "interrupted" functionOutput
    // appended at the end so the LLM contract (every function_call
    // followed by a function_output) holds.
    private func translate(messages: [Message]) -> [AITermController.Message] {
        struct PendingRequest {
            let name: String
            let functionCallID: LLM.Message.FunctionCallID?
        }
        var aiMessages: [AITermController.Message] = []
        var pendingByRequestID: [UUID: PendingRequest] = [:]
        var orderedPendingIDs: [UUID] = []
        // aiMessages index of each request's functionCall, so an orphan's
        // synthesized output can be inserted right after its call rather
        // than at the end of the transcript (see the orphan filler loop).
        var callIndexByRequestID: [UUID: Int] = [:]

        for message in messages {
            switch message.content {
            case .setPermissions, .clientLocal, .renameChat, .append, .appendAttachment,
                    .commit, .vectorStoreCreated, .userCommand, .selectSessionRequest,
                    .unsupported:
                continue

            case .remoteCommandRequest(let payload, safe: _):
                guard let call = payload.llmMessage.function_call else { continue }
                let fcID = payload.llmMessage.functionCallID
                callIndexByRequestID[message.uniqueID] = aiMessages.count
                aiMessages.append(AITermController.Message(
                    responseID: nil,
                    role: .assistant,
                    body: .functionCall(call, id: fcID)))
                pendingByRequestID[message.uniqueID] = PendingRequest(
                    name: payload.name,
                    functionCallID: fcID)
                orderedPendingIDs.append(message.uniqueID)

            case .remoteCommandResponse(let result, let requestUUID, let name, let fcID):
                // If we never saw a matching .remoteCommandRequest the
                // tool_use record was squelched from the chat database.
                // ChatClient.processRemoteCommandRequest's .always
                // (auto-approve) and .never (auto-deny) paths return
                // nil from the broker processor, which causes
                // ChatBroker.publish to skip listModel.append entirely
                // (ChatBroker.swift:132-140). The tool runs and its
                // response is persisted normally, but no tool_use lands
                // in the DB. On the NEXT turn (e.g. queued user message
                // that arrived during the tool round-trip), load() calls
                // back into translate which sees the orphaned
                // tool_result; without this branch, Anthropic 400s:
                //   messages.N.content.M: unexpected `tool_use_id` found
                //   in `tool_result` blocks: …. Each `tool_result` block
                //   must have a corresponding `tool_use` block in the
                //   previous message.
                // Synthesize the missing functionCall so the LLM
                // contract (every tool_result preceded by a matching
                // tool_use) holds. Args are empty because the original
                // arguments aren't recoverable — they're not on the
                // tool_result. The call_id is what matters for the
                // pairing.
                if pendingByRequestID[requestUUID] == nil {
                    let synthesizedCall = LLM.FunctionCall(
                        name: name,
                        arguments: "{}",
                        id: fcID?.callID)
                    aiMessages.append(AITermController.Message(
                        responseID: nil,
                        role: .assistant,
                        body: .functionCall(synthesizedCall, id: fcID)))
                }
                let output: String
                switch result {
                case .success(let value): output = value
                case .failure(let error):
                    output = "Tool call failed: \(error.localizedDescription)"
                }
                aiMessages.append(AITermController.Message(
                    responseID: nil,
                    role: .function,
                    body: .functionOutput(name: name,
                                          output: output,
                                          id: fcID)))
                pendingByRequestID.removeValue(forKey: requestUUID)

            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .terminalCommand, .multipart, .watcherEvent:
                aiMessages.append(aiMessage(from: message))
            }
        }

        // Pair every still-orphaned request with a synthesized
        // "interrupted" output inserted IMMEDIATELY AFTER its function
        // call, not at the end of the transcript. OpenAI-style
        // chat-completions vendors (DeepSeek, legacy OpenAI) require an
        // assistant tool_calls message to be followed directly by the
        // tool output for each tool_call_id; appending the filler at the
        // end leaves any intervening user/assistant message between the
        // call and its output, which DeepSeek rejects with HTTP 400
        // "insufficient tool messages following tool_calls message"
        // (GitLab #12883). Collect (index, message) first, then insert in
        // descending index order so an earlier insertion doesn't shift
        // the target index of a later one.
        var orphanInserts: [(index: Int, message: AITermController.Message)] = []
        for requestID in orderedPendingIDs {
            guard let pending = pendingByRequestID.removeValue(forKey: requestID),
                  let callIndex = callIndexByRequestID[requestID] else {
                continue
            }
            let filler = AITermController.Message(
                responseID: nil,
                role: .function,
                body: .functionOutput(
                    name: pending.name,
                    output: AIChatToolCallRepair.interruptedToolCallOutput,
                    id: pending.functionCallID))
            orphanInserts.append((callIndex + 1, filler))
        }
        for insert in orphanInserts.sorted(by: { $0.index > $1.index }) {
            aiMessages.insert(insert.message, at: insert.index)
        }

        return aiMessages
    }

    private func updateSystemMessage(_ permissions: Set<RemoteCommand.Content.PermissionCategory>) {
        self.permissions = permissions
        var parts = [String]()

        let key = if AITermController.provider?.functionsSupported != true || permissions.isEmpty {
            kPreferenceKeyAIPromptAIChat
        } else {
            if permissions.contains(.actInWebBrowser) {
                if permissions.contains(.runCommands) || permissions.contains(.typeForYou) {
                    kPreferenceKeyAIPromptAIChatReadWriteTerminalBrowser
                } else {
                    kPreferenceKeyAIPromptAIChatReadOnlyTerminalBrowser
                }
            } else {
                if permissions.contains(.runCommands) || permissions.contains(.typeForYou) {
                    kPreferenceKeyAIPromptAIChatReadWriteTerminal
                } else {
                    kPreferenceKeyAIPromptAIChatReadOnlyTerminal
                }
            }
        }
        parts.append(iTermPreferences.string(forKey: key))
        parts.append("If a zip file is provided (this is rare), you should extract it and analyze the contents in the context of the accompanying messages.")

        conversation.systemMessage = parts.joined(separator: " ")
        if conversation.systemMessage != lastSystemMessage {
            // Force the whole conversation to be re-sent
            conversation.systemMessageDirty = true
            lastSystemMessage = conversation.systemMessage
        }
        registerToolProviders()
    }

    private func registerToolProviders() {
        conversation.removeAllFunctions()
        for provider in toolProviders {
            provider.registerTools(on: &conversation)
        }
    }

    // Build the orchestration system message from the user-customizable
    // kPreferenceKeyAIPromptAIChatOrchestration preference. The preference
    // value is an iTermSwiftyString-style template; `\(ai.default_code_review_prompt)`
    // and `\(ai.saved_prompt_names)` are evaluated against a transient
    // scope built here. Marks systemMessageDirty when the resolved text
    // changes so the next conversation turn re-sends the prompt.
    private func updateOrchestrationSystemMessage() {
        let template = iTermPreferences.string(
            forKey: kPreferenceKeyAIPromptAIChatOrchestration) ?? ""
        let resolved = Self.evaluateOrchestrationPromptTemplate(template)
        conversation.systemMessage = resolved
        if conversation.systemMessage != lastSystemMessage {
            conversation.systemMessageDirty = true
            lastSystemMessage = conversation.systemMessage
        }
    }

    @MainActor
    private static func evaluateOrchestrationPromptTemplate(_ template: String) -> String {
        let store = CodeReviewPromptStore.shared
        let defaultCodeReviewPrompt = store.defaultPromptText
        let savedPromptNames: String
        if store.prompts.isEmpty {
            savedPromptNames = "(none saved)"
        } else {
            savedPromptNames = store.prompts
                .map { "  - \($0.name)" }
                .joined(separator: "\n")
        }
        return AIPromptTemplateEvaluator.evaluateSynchronously(
            template,
            variables: ["default_code_review_prompt": defaultCodeReviewPrompt,
                        "saved_prompt_names": savedPromptNames])
    }

    deinit {
        // Beta/Nightly tripwire: parked tool completions should have
        // been drained in stop() while everything was alive. If
        // stop() didn't run, that's a programmer bug at the call
        // site, and resuming them from deinit re-enters
        // AITermController.doFunctionCall from a half-torn-down
        // object. The assertion surfaces it on testing channels.
        let isBetaChannel = Bundle.it_isEarlyAdopter() || Bundle.it_isNightlyBuild()
        let parkedCount = pendingOrchestrationRequests.count
        if isBetaChannel {
            it_assert(parkedCount == 0,
                      "ChatAgent.deinit: stop() was not called; \(parkedCount) parked completion(s) remain")
        }
        // Cleanup on main, capturing references explicitly so they
        // outlive self. Same belt-and-suspenders rationale as
        // OrchestratorDispatcher.deinit: deinit on a @MainActor class
        // is not itself main-actor-isolated, so if a future caller
        // ends up releasing the agent from a background Task, the
        // mutations below would corrupt @MainActor state
        // (ChatBroker.subs). Dispatching to main keeps the work safe
        // even if the assertion above is silenced.
        // Only touched on main; hand across the @Sendable boundary explicitly
        // since ChatBroker.Subscription isn't Sendable.
        nonisolated(unsafe) let sub = brokerSubscription
        let parked = pendingOrchestrationRequests
        DispatchQueue.main.async {
            sub?.unsubscribe()
            for (_, completion) in parked {
                try? completion(.success("Cancelled."))
            }
        }
    }

    private func aiMessage(from message: Message) -> AITermController.Message {
        let body = messageToPrompt.body(message: message)
        return AITermController.Message(
            responseID: message.responseID,
            role: AITermController.Message.role(from: message),
            body: body,
            reasoningContent: message.agentReasoning)
    }

    var supportsStreaming: Bool {
        return conversation.supportsStreaming
    }



    func fetchCompletion(userMessage: Message,
                         history: [Message],
                         streaming: ((StreamingUpdate) -> ())?,
                         completion: @escaping (Message?) -> ()) throws {
        try fetchCompletion(userMessage: userMessage,
                            history: history,
                            cancelPendingUploads: true,
                            streaming: streaming,
                            completion: completion)
    }

    private func cancelPendingCommands() {
        if !pendingRemoteCommands.isEmpty {
            let saved = pendingRemoteCommands.values
            pendingRemoteCommands.removeAll()
            for item in saved {
                try? item.completion(.failure(PendingCommandCanceled()))
                if let id = item.responseID {
                    conversation.deleteResponse(id) { error in
                        DLog("Deleted \(id): \(error.d)")
                    }
                }
            }
        }
    }

    func stop() {
        cancelPendingCommands()
        drainPendingOrchestrationRequests(reason: "Cancelled.")
        conversation.cancelOutstandingOperation()
    }

    // Resume any parked request_orchestration_enable tool callbacks so
    // the LLM-side state machine doesn't hang. Called from stop() on
    // user-initiated cancel and from deinit on agent teardown. Failing
    // to drain here can leave the LLM waiting on a tool_use response
    // forever (it's parked in pendingOrchestrationRequests by
    // parkOrchestrationRequest).
    private func drainPendingOrchestrationRequests(reason: String) {
        guard !pendingOrchestrationRequests.isEmpty else { return }
        let parked = pendingOrchestrationRequests
        pendingOrchestrationRequests.removeAll()
        for (_, completion) in parked {
            try? completion(.success(reason))
        }
    }

    func fetchCompletion(userMessage: Message,
                         history: [Message],
                         cancelPendingUploads: Bool,
                         streaming: ((StreamingUpdate) -> ())?,
                         completion: @escaping (Message?) -> ()) throws {
        load(messages: history)

        // Remove items that won't have a previous response ID.
        let filteredHistory = history.filter { message in
            switch message.content {
            case .setPermissions, .renameChat, .selectSessionRequest, .clientLocal,
                    .append, .appendAttachment, .commit, .vectorStoreCreated, .userCommand,
                    .watcherEvent, .unsupported:
                false

            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .terminalCommand, .multipart:
                true
            }
        }
        if cancelPendingUploads {
            prepPipeline.cancelAll()
        }
        switch userMessage.content {
        case .multipart:
            if try prepPipeline.handleMultipartUserMessage(userMessage: userMessage,
                                                           history: filteredHistory,
                                                           streaming: streaming,
                                                           completion: completion) {
                return
            }
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandRequest, .selectSessionRequest, .clientLocal, .commit,
                .terminalCommand:
            break
        case .renameChat, .append:
            return
        case .remoteCommandResponse(let result, let messageID, _, _):
            if handleRemoteCommandResponse(messageID: messageID,
                                           result: result) {
                return
            }
            // Orphan tool response. The parked completion this response
            // was meant to resume was cleared by cancelPendingCommands
            // (e.g. user pressed Stop while the tool was still
            // running, and the runner published the response anyway).
            // DON'T fall through to fetchCompletionForRegularMessage:
            // that would kick off a new LLM round-trip whose
            // conversation.complete → prepare → cancel() would
            // silently cancel any actively in-flight queued turn,
            // orphaning its completion and stalling the queue.
            // Pinned by AILiveHarness.test_chat_orphanToolResponseAfterStop_doesNotOrphanQueuedMessage.
            DLog("Dropping orphan .remoteCommandResponse for cancelled tool")
            completion(nil)
            return
        case .setPermissions(let allowedCategories):
            handleSetPermission(allowedCategories: allowedCategories,
                                completion: completion)
            return
        case .userCommand:
            it_fatalError("User commands should not reach fetchCompletion")
        case .vectorStoreCreated:
            it_fatalError("User should not create vector store")
        case .appendAttachment:
            it_fatalError("User-sent attachments not supported")
        case .watcherEvent:
            break
        case .unsupported:
            // A placeholder for a message type this build doesn't
            // understand; it never feeds the LLM. Resolve the completion
            // so the caller's turn doesn't hang.
            completion(nil)
            return
        }
        fetchCompletionForRegularMessage(userMessage: userMessage,
                                         history: filteredHistory,
                                         streaming: streaming,
                                         completion: completion)
    }

    private func handleRemoteCommandResponse(messageID: UUID,
                                             result: Result<String, AIError>) -> Bool {
        if let pending = pendingRemoteCommands[messageID] {
            NSLog("Agent handling remote command response to message \(messageID)")
            pendingRemoteCommands.removeValue(forKey: messageID)
            try? pending.completion(Result(result))
            return true
        }
        return false
    }

    private func handleSetPermission(allowedCategories: Set<RemoteCommand.Content.PermissionCategory>,
                                     completion: @escaping (Message?) -> ()) {
        if mode == .orchestration {
            // Orchestration chats have no per-call permission surface
            // and their system prompt is owned by the orchestration
            // provider; ignore stray setPermissions deliveries.
            completion(nil)
            return
        }
        permissions = allowedCategories
        registerToolProviders()
        updateSystemMessage(allowedCategories)
        completion(nil)
    }

    private func fetchCompletionForRegularMessage(userMessage: Message,
                                                  history: [Message],
                                                  streaming: ((StreamingUpdate) -> ())?,
                                                  completion: @escaping (Message?) -> ()) {
        cancelPendingCommands()

        let needsRenaming = !conversation.messages.anySatisfies({ $0.role == .user})
        if LLMMetadata.model()?.features.contains(.hostedWebSearch) == true,
           let configuration = userMessage.configuration {
            conversation.hostedTools.webSearch = configuration.hostedWebSearchEnabled
        } else {
            conversation.hostedTools.webSearch = false
        }

        let useCodeInterpeter = (LLMMetadata.model()?.features.contains(.hostedCodeInterpreter) == true)
        conversation.hostedTools.codeInterpreter = useCodeInterpeter

        if LLMMetadata.model()?.features.contains(.hostedFileSearch) == true,
           let vectorStoreIDs = userMessage.configuration?.vectorStoreIDs, !vectorStoreIDs.isEmpty {
            conversation.hostedTools.fileSearch = .init(vectorstoreIDs: vectorStoreIDs)
        } else {
            conversation.hostedTools.fileSearch = nil
        }

        if let responseID = userMessage.inResponseTo {
            conversation.deleteMessages(after: responseID)
        }

        // Build the user-side LLM message and let each tool provider
        // transform the body (orchestration prepends a <workgroups>
        // snapshot; session-bound providers leave it alone). The
        // composition order matches toolProviders.
        let baseUserAIMessage = aiMessage(from: userMessage)
        var transformedBody = baseUserAIMessage.body
        for provider in toolProviders {
            transformedBody = provider.transform(outgoingUserBody: transformedBody)
        }
        let userAIMessage = AITermController.Message(
            responseID: baseUserAIMessage.responseID,
            role: baseUserAIMessage.role,
            body: transformedBody,
            reasoningContent: baseUserAIMessage.reasoningContent)
        conversation.add(userAIMessage)
        conversation.model = userMessage.configuration?.model
        conversation.shouldThink = userMessage.configuration?.shouldThink

        // Optional console trace (gated on the advanced setting). Not
        // coupled to orchestration mode anymore - any chat agent can
        // emit per-turn entries when the setting is on.
        consoleLogger.beginTurn(userBody: userAIMessage.body.content)

        var uuid: UUID?
        let streamingCallback: ((LLM.StreamingUpdate, String?) -> ())?
        if let streaming {
            streamingCallback = { [weak self] streamingUpdate, responseID in
                switch streamingUpdate {
                case .appendAttachment(let chunk):
                    if uuid == nil,
                       let initialMessage = Self.message(attachment: chunk,
                                                         userMessage: userMessage,
                                                         responseID: responseID) {
                        streaming(.begin(initialMessage))
                        uuid = initialMessage.uniqueID
                    } else if let uuid {
                        streaming(.appendAttachment(chunk, uuid))
                    }
                case .append(let chunk):
                    Task { @MainActor [weak self] in
                        self?.consoleLogger.appendStreamChunk(chunk)
                    }
                    if uuid == nil,
                       let initialMessage = Self.message(completionText: chunk,
                                                         userMessage: userMessage,
                                                         streaming: true,
                                                         responseID: responseID) {
                        streaming(.begin(initialMessage))
                        uuid = initialMessage.uniqueID
                    } else if let uuid {
                        streaming(.append(chunk, uuid))
                    }
                case .willInvoke(_):
                    break
                }
            }
        } else {
            streamingCallback = nil
        }
        if conversation.busy {
            conversation.cancelOutstandingOperation()
        }
        conversation.complete(streaming: streamingCallback) { [weak self] result in
            guard let self else {
                return
            }
            #if ITERM_DEBUG
            // TEMPORARY probe (Development builds only — ITERM_DEBUG is set only
            // in the Development config, not Beta/Nightly/Deployment, and this
            // target never defines DEBUG): a turn that completes while
            // an orchestration tool call is still parked is the bug we're
            // chasing — the agent swaps in a fresh conversation on completion
            // and the parked tool's eventual result resumes a dead controller.
            // Log the result shape, the last message body kind, and how many
            // tool calls are still parked so a reproduction pins the trigger.
            do {
                let kind: String
                switch result {
                case .success: kind = "success"
                case .failure(let e):
                    kind = (e is PendingCommandCanceled) ? "cancelled" : "failure(\(e))"
                }
                let lastBody: String
                switch result.successValue?.messages.last?.body {
                case .some(.functionCall(let call, _)): lastBody = "functionCall(\(call.name ?? "?"))"
                case .some(.text(let t)): lastBody = "text(\(OrchestrationToolProvider.snippet(of: String(t.prefix(60)))))"
                case .some(.multipart): lastBody = "multipart"
                case .some(.functionOutput): lastBody = "functionOutput"
                case .some(.attachment): lastBody = "attachment"
                case .some(.uninitialized): lastBody = "uninitialized"
                case .none: lastBody = "none"
                }
                NSFuckingLog("ChatAgent.complete done: result=\(kind) lastBody=\(lastBody) parkedToolCalls=\(self.pendingRemoteCommands.count) needsRenaming=\(needsRenaming)")
            }
            #endif
            if result.failureValue is PendingCommandCanceled {
                completion(nil)
                return
            }
            if let updated = result.successValue {
                self.conversation = updated
                if needsRenaming {
                    self.requestRenaming()
                }
            }
            switch result {
            case .success(let updated):
                let fallback = updated.messages.last?.body.content ?? ""
                self.consoleLogger.logAgentReply(fallbackText: fallback)
            case .failure(let error):
                self.consoleLogger.logAgentError(error.localizedDescription)
            }
            let message = Self.committedMessage(forResult: result,
                                                userMessage: userMessage,
                                                streamID: uuid)
            completion(message)
        }
    }

    private func requestRenaming() {
        let prompt = "Please assign a short, specific name to this chat, less than 30 characters in length, but descriptive. It will be shown in a chat list UI. Respond with only the name of the chat."
        var history = conversation.messages + [AITermController.Message(role: .user, content: prompt)]
        // Remove response IDs so we don't pollute the conversation's history
        history = history.map { value in
            var temp = value
            temp.responseID = nil
            return temp
        }
        var newConversation = AIConversation(
            registrationProvider: nil,
            messages: history)
        newConversation.shouldThink = false
        AIConversation.completeOneShot(newConversation) { [weak self] (result: Result<AIConversation, Error>) in
            // Sanitize the model's reply here, at the single point where
            // titles are minted, so every .renameChat consumer (the chat
            // list, the window title) sees the same value and a blank or
            // padded reply can't blank or pad a title anywhere.
            let newName = result.successValue?.messages.last?.body.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let newName, !newName.isEmpty {
                do {
                    try self?.renameChat(newName)
                    // Only after the rename actually landed: a thrown
                    // rename means the chat keeps its old title, and an
                    // icon for the never-applied title would both bill a
                    // model call and display next to the wrong title.
                    self?.requestIconGeneration(title: newName)
                } catch {
                    DLog("renameChat failed: \(error)")
                }
            } else {
                DLog("Rename produced no usable title")
            }
        }
    }

    // Generate the chat-list icon for a freshly minted title. This lives
    // here, next to the title generation it follows, rather than inside
    // ChatListModel's persistence mutation: a .renameChat can flow
    // through the model from paths that must not bill a model call
    // (imports, replays, a future manual-rename UI). On failure the icon
    // is cleared: for a first generation that's a no-op (the default
    // icon stays), and after a re-rename it beats leaving the previous
    // title's icon displayed forever next to the new title. There is no
    // retry, and pre-existing chats are deliberately not backfilled,
    // since that would bill one model call per chat without the user
    // asking for anything.
    private func requestIconGeneration(title: String) {
        let chatID = self.chatID
        ChatIconGenerator.instance.requestIcon(forChatID: chatID,
                                               title: title) { data in
            do {
                try ChatListModel.instance?.setIcon(data, forChatID: chatID)
            } catch {
                DLog("Failed to save icon for chat \(chatID): \(error)")
            }
        }
    }

    private static func committedMessage(respondingTo userMessage: Message,
                                         fromLastMessageIn conversation: AIConversation) -> Message? {
        guard let text = conversation.messages.last?.body.content else {
            return nil
        }
        var msg = self.message(completionText: text,
                               userMessage: userMessage,
                               streaming: false,
                               responseID: conversation.messages.last?.responseID)
        // Carry DeepSeek-style reasoning content through to the persisted chat
        // message so reopening the chat can round-trip it on the next request.
        // Streaming runs harvest reasoning in Message.removeReasoningStatusSubparts;
        // this path handles the non-streaming completion.
        if let reasoning = conversation.messages.last?.reasoningContent, !reasoning.isEmpty {
            msg?.agentReasoning = reasoning
        }
        return msg
    }

    // Return a new message from the agent containing the content of the last message in result.
    private static func committedMessage(forResult result: Result<AIConversation, any Error>,
                                         userMessage: Message,
                                         streamID: UUID?) -> Message? {
        if let streamID {
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .commit(streamID),
                           sentDate: Date(),
                           uniqueID: UUID())
        }
        return result.handle { (updated: AIConversation) -> Message? in
            return committedMessage(respondingTo: userMessage,
                                    fromLastMessageIn: updated)
        } failure: { error in
            let nserror = error as NSError
            if userMessage.isExplanationRequest &&
                nserror.domain == iTermAIError.domain &&
                nserror.code == iTermAIError.ErrorType.requestTooLarge.rawValue {
                return Message(chatID: userMessage.chatID,
                               author: .agent,
                               content: .plainText("🛑 The text to analyze was too long. Select a portion of it and try again.",
                                                   context: nil),
                               sentDate: Date(),
                               uniqueID: UUID())
            }

            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .plainText("🛑 I ran into a problem: \(error.localizedDescription)",
                                               context: nil),
                           sentDate: Date(),
                           uniqueID: UUID())
        }
    }

    // This is for a committed message or an initial message in a stream.
    private static func message(completionText text: String,
                                userMessage: Message,
                                streaming: Bool,
                                responseID: String?) -> Message? {
        switch userMessage.content {
        case .plainText, .markdown, .explanationResponse, .terminalCommand,
                .remoteCommandResponse, .multipart, .watcherEvent:
            // .watcherEvent is a user-author message synthesized by the
            // orchestrator when a registered watcher fires. The agent
            // gets a turn to summarize the event for the user, and that
            // turn renders as plain markdown just like a normal reply.
            // It belongs alongside the other "agent replies with text"
            // shapes, not in the fatalError block below.
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .markdown(text),
                           sentDate: Date(),
                           uniqueID: UUID(),
                           responseID: responseID)
        case .explanationRequest(let explanationRequest):
            let messageID = UUID()
            return Message(
                chatID: userMessage.chatID,
                author: .agent,
                content: .explanationResponse(
                    ExplanationResponse(text: text,
                                        request: explanationRequest,
                                        final: streaming == false),
                    streaming ? ExplanationResponse.Update(final: false, messageID: messageID) : nil,
                    markdown: ""),  // markdown is added by the client.
                sentDate: Date(),
                uniqueID: messageID,
                responseID: responseID)
        case .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .appendAttachment, .vectorStoreCreated, .userCommand,
                .unsupported:
            it_fatalError()
        }
    }

    // Streaming only
    private static func message(attachment: LLM.Message.Attachment,
                                userMessage: Message,
                                responseID: String?) -> Message? {
        switch userMessage.content {
        case .plainText, .markdown, .explanationResponse, .terminalCommand,
                .remoteCommandResponse, .multipart, .watcherEvent:
            // .watcherEvent: see message(completionText:...) above for
            // the rationale. A streamed attachment that comes back on a
            // watcher-triggered turn is still an agent reply and renders
            // as a multipart message just like one triggered by plain
            // user text.
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .multipart(
                            [.attachment(attachment)],
                            vectorStoreID: nil),
                           sentDate: Date(),
                           uniqueID: UUID(),
                           responseID: responseID)
        case .explanationRequest(let explanationRequest):
            let messageID = UUID()
            return Message(
                chatID: userMessage.chatID,
                author: .agent,
                content: .explanationResponse(
                    // TODO: Support attachments in explanations
                    ExplanationResponse(text: attachment.contentString,
                                        request: explanationRequest,
                                        final: false),
                    ExplanationResponse.Update(final: false, messageID: messageID),
                    markdown: ""),  // markdown is added by the client.
                sentDate: Date(),
                uniqueID: messageID,
                responseID: responseID)
        case .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .appendAttachment, .vectorStoreCreated, .userCommand,
                .unsupported:
            it_fatalError()
        }
    }

}

extension LLM.Message.Attachment {
    var contentString: String {
        switch type {
        case .code(let code): code
        case .statusUpdate(let statusUpdate): statusUpdate.displayString
        case .file(let file):
            file.content.lossyString
        case .fileID: "[Attached file]"
        }
    }
}

extension Message {
    var isExplanationRequest: Bool {
        switch content {
        case .explanationRequest: true
        default: false
        }
    }
}

extension ChatAgent {
    // MARK: - Function Calling Infra

    private func renameChat(_ newName: String) throws {
        try broker.publish(message: .init(chatID: chatID,
                                          author: .agent,
                                          content: .renameChat(newName),
                                          sentDate: Date(),
                                          uniqueID: UUID()),
                           toChatID: chatID,
                           partial: false)
    }

    private func runRemoteCommand(_ remoteCommand: RemoteCommand,
                                  _ responseID: String?,
                                  completion: @escaping (Result<String, Error>) throws -> ()) throws {
        if remoteCommand.needsSafetyCheck {
            Task { @MainActor in
                let safe = await remoteCommand.isSafe(force: mode == .orchestration)
                do {
                    try reallyRunCommand(remoteCommand,
                                         responseID,
                                         safe: safe,
                                         completion: completion)
                } catch {
                    Task { @MainActor in
                        try? completion(.failure(error))
                    }
                }
            }
        } else {
            try reallyRunCommand(remoteCommand, responseID, safe: nil, completion: completion)
        }
    }

    private func reallyRunCommand(_ remoteCommand: RemoteCommand,
                                  _ responseID: String?,
                                  safe: Bool?,
                                  completion: @escaping (Result<String, Error>) throws -> ()) throws {
        let requestID = UUID()
        pendingRemoteCommands[requestID] = .init(completion: completion,
                                                 responseID: responseID)
        try broker.publish(message: .init(chatID: chatID,
                                          author: .agent,
                                          content: .remoteCommandRequest(.classic(remoteCommand), safe: safe),
                                          sentDate: Date(),
                                          uniqueID: requestID),
                           toChatID: chatID,
                           partial: false)
    }
}

extension Result where Failure == Error {
    // Upcast Result<Success,SpecificFailure> to Result<Success,Error>.
    init<SpecificFailure: Error>(_ result: Result<Success, SpecificFailure>) {
        self = result.mapError { $0 }
    }
}

// @preconcurrency: ChatAgent is @MainActor but MessagePrepPipelineDelegate
// is a pre-concurrency nonisolated protocol. The pipeline only invokes the
// delegate on the main thread, so relax the isolation check rather than
// thread isolation through the nonisolated protocol.
extension ChatAgent: @preconcurrency MessagePrepPipelineDelegate {
    func uploadFile(name: String,
                    content: Data,
                    completion: @escaping (Result<String, any Error>) -> ()) {
        conversation.uploadFile(name: name,
                                content: content,
                                completion: completion)
    }
    
    func publish(message: Message, toChatID chatID: String, partial: Bool) throws {
        try broker.publish(message: message, toChatID: chatID, partial: partial)
    }
    
    func createVectorStore(name: String, completion: @escaping (Result<String, any Error>) -> ()) {
        conversation.createVectorStore(name: name,
                                       completion: completion)
    }
    
    func addFilesToVectorStore(fileIDs: [String],
                               vectorStoreID: String,
                               completion: @escaping ((any Error)?) -> ()) {
        conversation.addFilesToVectorStore(fileIDs: fileIDs,
                                           vectorStoreID: vectorStoreID,
                                           completion: completion)
    }
    
    func publishNotice(chatID: String, message: String) throws {
        try broker.publishMessageFromAgent(
            chatID: chatID,
            content: .clientLocal(.init(action: .notice(message))))
    }
}

extension ChatAgent {
    /// Live-harness seam: re-runs the prompt-rebuild logic from
    /// `load(messages:)` on a synthetic transcript and returns the same
    /// `AIConversation.messages` shape `load(...)` would assign. Exists
    /// because `ChatAgent.init` requires a `ChatBroker`, and `ChatBroker`
    /// requires a real `ChatDatabase` / `ChatListModel` singleton that would
    /// write the user's actual chat DB during a test run. Mirror the body
    /// here if `load(messages:)` ever changes — `AILiveHarness` reaches
    /// `AIChatToolCallRepair` through this seam to validate the chat-restore
    /// path end-to-end against real vendor APIs.
    /// Translate a persisted transcript to LLM messages WITHOUT the orphan
    /// repair pass. Production never sends this (aiMessagesForReloadingTranscript
    /// always repairs), but the live negative-control test sends it to prove a
    /// real vendor actually rejects an un-repaired orphan tool_result, so the
    /// positive repair test cannot pass by accident.
    static func transcriptMessagesBeforeRepair(_ messages: [Message]) -> [AITermController.Message] {
        var stateMachine = MessageToPromptStateMachine()
        return messages.compactMap { message -> AITermController.Message? in
            switch message.content {
            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .terminalCommand,
                    .multipart, .watcherEvent:
                let body = stateMachine.body(message: message)
                return AITermController.Message(
                    responseID: message.responseID,
                    role: AITermController.Message.role(from: message),
                    body: body,
                    reasoningContent: message.agentReasoning)
            case .selectSessionRequest, .clientLocal, .renameChat, .append, .appendAttachment,
                    .commit, .vectorStoreCreated, .userCommand, .setPermissions, .unsupported:
                return nil
            }
        }
    }

    static func aiMessagesForReloadingTranscript(_ messages: [Message]) -> [AITermController.Message] {
        return AIChatToolCallRepair.repairingOrphanedToolPairs(
            transcriptMessagesBeforeRepair(messages))
    }
}

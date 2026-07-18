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

// Ref-counts outstanding turn-parks that cleared the typing spinner (a turn parked
// on the user's approval / Enable-Not-Now). The spinner is turned OFF on the first
// park and back ON only when the LAST park resolves, so approving one of two
// concurrent approval parks doesn't restore the spinner while another is still
// parked. Pure value type so the ref-counting is unit-testable.
struct ParkedTypingCounter {
    private var count = 0
    /// Register a park that clears typing. Returns true iff the spinner should be
    /// turned OFF now (this is the first outstanding cleared-typing park).
    mutating func park() -> Bool {
        defer { count += 1 }
        return count == 0
    }
    /// Register the resume of a cleared-typing park. Returns true iff the spinner
    /// should be turned back ON now (this was the last outstanding one).
    mutating func resume() -> Bool {
        guard count > 0 else { return false }
        count -= 1
        return count == 0
    }
    /// Forget all outstanding parks (a turn teardown/cancel resolves them abnormally
    /// without a matching resume; the ending turn's stopTyping handles the spinner).
    mutating func reset() {
        count = 0
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
    // The visible screen last auto-provided to the model for this chat, so an
    // unchanged screen is sent as a short marker instead of resending the grid.
    private var lastAutoProvidedScreen: String?

    // Optional developer-only console trace of chat-agent traffic.
    // Gated on the advanced setting "aiChatVerboseConsoleLogging";
    // does nothing when off.
    private let consoleLogger: ChatAgentConsoleLogger

    // request_orchestration_enable tool: keyed by request UUID, the
    // LLM-framework completion is parked until the user clicks
    // Enable or Not Now (or the chat tears down).
    private var pendingOrchestrationRequests: [String: (Result<String, Error>) throws -> ()] = [:]

    // Ref-count of outstanding turn-parks that cleared the typing spinner (remote-
    // command approval and orchestration-enable parks). See typingParkOnUser /
    // typingResumeFromPark.
    private var parkedTyping = ParkedTypingCounter()

    struct PendingRemoteCommand {
        var completion: (Result<String, Error>) throws -> ()
        var responseID: String?
        // True iff parking this command cleared the agent's typing status because it
        // blocks on the user's approval. handleRemoteCommandResponse restores typing
        // only in that case: re-emitting typing(true) for an auto-executed mid-turn
        // tool call would make the phone read the resume as a new-turn boundary and
        // reset the turn's accumulated reply text before it can be notified.
        var clearedTyping = false
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

    // The single park/resume typing bracket, shared by every site where a turn
    // parks on the user (remote-command approval, orchestration-enable). Clearing
    // typing on park keeps the phone's spinner from sticking and, on a
    // pre-turnLifecycle phone, lets the reply notification (which fires on typing
    // false) fire. Ref-counted so concurrent approval parks turn the spinner off
    // once and back on once, and so a new park site gets correct behavior for free
    // instead of re-deriving the false-on-park / restore-on-resume dance.
    private func typingParkOnUser() {
        if parkedTyping.park() {
            broker.publish(typingStatus: false, of: .agent, toChatID: chatID)
        }
    }
    private func typingResumeFromPark() {
        if parkedTyping.resume() {
            broker.publish(typingStatus: true, of: .agent, toChatID: chatID)
        }
    }

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
            // The turn is now parked waiting for the user's Enable/Not Now, so the
            // agent has stopped working. Clear the spinner (see typingParkOnUser):
            // without this, typingStatus stays true (agentWorking only completes when
            // the whole turn ends), leaving the phone's indicator stuck AND its
            // session-reply notification (which fires on typing false) never firing.
            typingParkOnUser()
        } catch {
            RLog("Failed to publish enable-orchestration request: \(error)")
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
        // Resuming the parked turn: the agent is working again, so restore the
        // spinner that parkOrchestrationRequest cleared (see typingResumeFromPark;
        // ref-counted so a concurrent park keeps it off until the last resolves).
        typingResumeFromPark()
        if approved {
            do {
                try ChatListModel.instance?.setOrchestrationEnabled(true, forChatID: chatID)
            } catch {
                // Persistence failed, so the in-memory transition would
                // leave the DB row out of sync with the agent and the
                // next app launch would rebuild this chat as
                // session-bound while the conversation history already
                // references orchestrator tool calls.
                RLog("Failed to set orchestrationEnabled: \(error)")
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
        pendingRemoteCommands[requestID] = .init(completion: completion,
                                                 responseID: llmMessage.responseID)
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
            RLog("Failed to publish orchestration tool request: \(error)")
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
        conversation.messages = translate(messages: messages)

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
    // Persisted tool calls replay STRUCTURED (function_call/functionOutput
    // items), never as prose: replaying them as assistant text taught the
    // model to imitate the format and fabricate tool results instead of
    // calling tools. OpenAI reasoning models require the reasoning item
    // alongside a historical function_call; it is persisted with the call
    // (llmMessage.reasoningItems) and rides here, while pre-persistence
    // calls replay without their OpenAI item id so the API treats them as
    // developer-provided context (see ResponsesBodyRequestBuilder). The
    // repair pass heals both orphan directions (interrupted calls,
    // auto-approved responses whose request was never persisted) so every
    // vendor accepts the rebuilt prompt.
    private func translate(messages: [Message]) -> [AITermController.Message] {
        let replayed = AIChatToolCallRepair.repairingOrphanedToolPairs(
            Self.aiMessagesForStructuredReplay(messages, stateMachine: &messageToPrompt))
        // Rewrite session guids the model wrote in prose (@-mentions) into the
        // reload-durable stableID, so a chat that predates stableIDs shows the
        // model references consistent with the stableIDs the <workgroups>
        // snapshot now emits, without migrating any stored data. Only free text
        // is rewritten: structured tool-call arguments carry vendor
        // signatures/ids that must replay verbatim, and tool output stays a
        // faithful copy of the terminal.
        let resolve: (String) -> String? = { guid in
            iTermController.sharedInstance()?.anySession(withGUID: guid)?.stableID
        }
        return replayed.map { message in
            var message = message
            message.body = Self.stabilizeSessionReferences(in: message.body, resolve: resolve)
            return message
        }
    }

    private static let sessionGuidRegex = try! NSRegularExpression(
        pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    // Rewrites each guid in `text` that `resolve` maps to a live session's
    // stableID into that stableID, as a proper @-mention: if the guid was not
    // already written as a mention (preceded by "@", "@session:", or "@wg-"),
    // an "@" is prepended. That repairs a pre-stableID chat where the model
    // wrote a bare session id without the sigil, turning it into a clickable
    // link. A guid that does not resolve (a workgroup id, a dead session, a bare
    // uuid in output) is left verbatim. Each distinct guid is resolved once.
    static func stabilizeSessionGuids(in text: String, resolve: (String) -> String?) -> String {
        let ns = text as NSString
        let matches = sessionGuidRegex.matches(in: text,
                                               range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            return text
        }
        let result = NSMutableString()
        var cursor = 0
        var cache = [String: String?]()
        for match in matches {
            let range = match.range
            if range.location > cursor {
                result.append(ns.substring(with: NSRange(location: cursor,
                                                         length: range.location - cursor)))
            }
            let guid = ns.substring(with: range)
            let stableID: String?
            if let cached = cache[guid] {
                stableID = cached
            } else {
                stableID = resolve(guid)
                cache[guid] = stableID
            }
            if let stableID {
                if !Self.guidIsAlreadyMention(ns: ns, guidRange: range) {
                    result.append("@")
                }
                result.append(stableID)
            } else {
                result.append(guid)
            }
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            result.append(ns.substring(from: cursor))
        }
        return result as String
    }

    // True when the guid at `guidRange` was already written as an @-mention:
    // directly after "@" (a bare-id mention) or after "@session:" / "@wg-".
    private static func guidIsAlreadyMention(ns: NSString, guidRange: NSRange) -> Bool {
        let loc = guidRange.location
        guard loc > 0 else {
            return false
        }
        if ns.substring(with: NSRange(location: loc - 1, length: 1)) == "@" {
            return true
        }
        for prefix in ["@session:", "@wg-"] {
            let plen = (prefix as NSString).length
            if loc >= plen,
               ns.substring(with: NSRange(location: loc - plen, length: plen)).lowercased() == prefix {
                return true
            }
        }
        return false
    }

    private static func stabilizeSessionReferences(in body: LLM.Message.Body,
                                                   resolve: (String) -> String?) -> LLM.Message.Body {
        switch body {
        case .text(let text):
            return .text(stabilizeSessionGuids(in: text, resolve: resolve))
        case .multipart(let bodies):
            return .multipart(bodies.map { stabilizeSessionReferences(in: $0, resolve: resolve) })
        case .uninitialized, .functionCall, .functionOutput, .attachment:
            return body
        }
    }

    private static func aiMessagesForStructuredReplay(_ messages: [Message],
                                                      stateMachine: inout MessageToPromptStateMachine) -> [AITermController.Message] {
        var aiMessages: [AITermController.Message] = []
        for message in messages {
            switch message.content {
            case .setPermissions, .clientLocal, .renameChat, .append, .appendAttachment,
                    .commit, .vectorStoreCreated, .userCommand, .selectSessionRequest,
                    .unsupported:
                continue

            case .remoteCommandRequest(let payload, safe: _):
                // A request with no function_call has nothing to replay
                // (squelched/auto-approved shapes); its orphaned response,
                // if any, is healed by the repair pass.
                guard payload.llmMessage.function_call != nil else { continue }
                var call = aiMessage(from: message, stateMachine: &stateMachine)
                // The persisted llmMessage carries the turn's reasoning
                // items; ride them onto the rebuilt call so the request
                // builder can replay them ahead of it.
                call.reasoningItems = payload.llmMessage.reasoningItems
                aiMessages.append(call)

            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .terminalCommand, .multipart, .watcherEvent, .remoteCommandResponse:
                aiMessages.append(aiMessage(from: message, stateMachine: &stateMachine))
            }
        }
        return aiMessages
    }

    /// Resolve a turn's model name the same way request routing does
    /// (AIConversation.complete: manual models first, then the built-in
    /// catalog, so a manual config wins over a built-in that shares its name).
    /// nil for an unknown or absent name; the caller falls back to the global
    /// default, keeping capability gating and routing in agreement.
    static func resolvedModel(named name: String?) -> AIMetadata.Model? {
        guard let name else { return nil }
        return LLMMetadata.manualModels().first { $0.name == name }
            ?? AIMetadata.instance.models.first { $0.name == name }
    }

    /// Hosted-tool enablement for a turn, pure over the effective model's
    /// features and the turn's configuration so it can never silently read
    /// the global default model.
    static func hostedTools(features: Set<AIMetadata.Model.Feature>,
                            configuration: Message.Configuration?) -> HostedTools {
        var tools = HostedTools()
        if features.contains(.hostedWebSearch), let configuration {
            tools.webSearch = configuration.hostedWebSearchEnabled
        } else {
            tools.webSearch = false
        }
        tools.codeInterpreter = features.contains(.hostedCodeInterpreter)
        if features.contains(.hostedFileSearch),
           let vectorStoreIDs = configuration?.vectorStoreIDs, !vectorStoreIDs.isEmpty {
            tools.fileSearch = .init(vectorstoreIDs: vectorStoreIDs)
        } else {
            tools.fileSearch = nil
        }
        return tools
    }

    private static func aiMessage(from message: Message,
                                  stateMachine: inout MessageToPromptStateMachine) -> AITermController.Message {
        let body = stateMachine.body(message: message)
        return AITermController.Message(
            responseID: message.responseID,
            role: AITermController.Message.role(from: message),
            body: body,
            reasoningContent: message.agentReasoning)
    }

    private func updateSystemMessage(_ permissions: Set<RemoteCommand.Content.PermissionCategory>) {
        self.permissions = permissions
        var parts = [String]()

        // A session-bound chat can be linked to a terminal, a browser, both, or
        // neither (the Link/Unlink Terminal and Web Browser menu items are
        // independent). The permission set reflects what's actually linked:
        // browser-specific categories appear only when a browser is linked, the
        // rest only when a terminal is linked. Pick the prompt that matches the
        // real combination so a browser-only chat isn't told it has a terminal.
        let hasBrowser = permissions.contains(.actInWebBrowser)
        let hasTerminal = permissions.contains { !$0.isBrowserSpecific }
        let readWrite = permissions.contains(.runCommands) || permissions.contains(.typeForYou)
        let key = if AITermController.provider?.functionsSupported != true || (!hasTerminal && !hasBrowser) {
            kPreferenceKeyAIPromptAIChat
        } else if hasBrowser && !hasTerminal {
            kPreferenceKeyAIPromptAIChatBrowser
        } else if hasBrowser {
            readWrite ? kPreferenceKeyAIPromptAIChatReadWriteTerminalBrowser
                      : kPreferenceKeyAIPromptAIChatReadOnlyTerminalBrowser
        } else {
            readWrite ? kPreferenceKeyAIPromptAIChatReadWriteTerminal
                      : kPreferenceKeyAIPromptAIChatReadOnlyTerminal
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
        let resolved = [
            Self.evaluateOrchestrationPromptTemplate(template),
            Self.orchestrationDisplayPolicy
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        conversation.systemMessage = resolved
        if conversation.systemMessage != lastSystemMessage {
            conversation.systemMessageDirty = true
            lastSystemMessage = conversation.systemMessage
        }
    }

    private static let orchestrationDisplayPolicy = """
    Terminal output display policy:
    - iTerm2 displays raw terminal command output to the user as its own code block.
    - Do not repeat raw command output in prose, do not convert it into Markdown tables, and do not reformat listings such as ls, ps, df, netstat, or grep output.
    - After running a command, summarize only non-obvious findings or ask what to do next.
    - Speak at the user’s level: never expose internal identifiers or fields (session ids, workgroup ids, status_source, role_id) in prose. To point the user at a session, write its FULL @-prefixed id (iTerm2 renders it as the session’s clickable name) or name it by role (“the Code Review”, “your Chat”); a partial or bare id is dead text, not a link, so never abbreviate one.
    - “Workgroup” is an internal grouping, not something the user named. Do not use the word “workgroup” or a wg-/workgroup_id with the user; refer to a session by its role, using the workgroup’s human name only if you truly must disambiguate.

    Talking to the user:
    - Be concise. This chat is a control surface, not a place to think out loud: say what changed or what you need, and nothing more.
    - Do not narrate routine mechanics. Registering or re-registering a watch, reading a screen to check state, and the individual steps of a multi-tool action are not worth a message on their own; do them silently and report only the result.
    - One message per meaningful outcome, not one per tool call. If a single event (say, a review finishing clean) leads you to check a screen, tell a session to continue, and re-arm a watch, that is one outcome: report it once, after you have acted, in a sentence or two.
    - Treat a <status_update> as a system signal to act on, not a message to acknowledge. Do not thank it, restate it, or re-explain your standing plan each time one fires.
    - When the user has set up a standing loop (“keep doing X until there are no steps left”), run it silently: speak up only when a step actually advances, when the loop finishes, or when something needs the user’s decision. Do not ask what to do next on each iteration; you already know the next step.
    - Do not repeat yourself across turns. Announce a milestone once: once you have told the user a step finished (a fix applied, a review kicked off, a review came back clean), do not announce it again when a later tool result or status_update merely re-confirms the same thing. If nothing new has happened since your last message, say nothing.
    """

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
        Self.aiMessage(from: message, stateMachine: &messageToPrompt)
    }

    var supportsStreaming: Bool {
        return conversation.supportsStreaming
    }

    /// The auto-provided context for a session-bound chat, or nil if this chat is
    /// not session-bound, has no linked session, or has granted neither "provided
    /// automatically" permission. Read at request time so it is fresh; an unchanged
    /// visible screen collapses to a short marker rather than resending the grid.
    private func autoProvidedContext() -> String? {
        guard mode == .sessionBound else {
            return nil
        }
        guard let guid = ChatListModel.instance?.chat(id: chatID)?.terminalSessionGuid,
              let session = iTermController.sharedInstance().anySession(forReference: guid) else {
            RLog("autoProvidedContext: chat \(chatID) is session-bound but has no linked session (guid=\(ChatListModel.instance?.chat(id: chatID)?.terminalSessionGuid ?? "nil")); not auto-providing")
            return nil
        }
        let rce = RemoteCommandExecutor.instance
        let stateP = rce.permission(chatID: chatID, inSessionGuid: guid, category: .checkTerminalState)
        let contentsP = rce.permission(chatID: chatID, inSessionGuid: guid, category: .viewContents)
        RLog("autoProvidedContext: chat \(chatID) session \(guid): Check Terminal State=\(stateP), View Contents=\(contentsP) (inject when .always)")
        // Auto-send requires an explicit, informed global consent, not merely a
        // per-chat .always permission: a legacy "Always" grant (e.g. an old
        // "View History = Always" carried across the rename to "View Contents")
        // reaches .always WITHOUT ever passing the per-chat "Send Automatically"
        // confirmation, so gating on the permission alone would silently start
        // sending the screen. Suppress until the user has granted consent (the
        // per-chat confirmation grants it; the one-time prompt asks otherwise).
        let wantsAutoSend = (stateP == .always || contentsP == .always)
        if Self.shouldSuppressAutoProvide(wantsAutoSend: wantsAutoSend,
                                          consent: iTermUserDefaults.autoProvideConsent) {
            RLog("autoProvidedContext: chat \(chatID) wants auto-send but consent is not granted (\(iTermUserDefaults.autoProvideConsent.rawValue)); suppressing")
            requestAutoProvideConsentIfNeeded()
            return nil
        }
        var blocks = [String]()
        if stateP == .always {
            blocks.append("<terminal-state>\n" + Self.neutralizeContextDelimiters(session.aiState) + "\n</terminal-state>")
        }
        if contentsP == .always {
            let screen = WorkgroupIntrospection.screenContents(
                forSession: session,
                requestedLines: Int(session.screen.height())).text
            if screen == lastAutoProvidedScreen {
                blocks.append("<visible-screen unchanged=\"true\"/>")
            } else {
                lastAutoProvidedScreen = screen
                blocks.append("<visible-screen>\n" + Self.neutralizeContextDelimiters(screen) + "\n</visible-screen>")
            }
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n")
    }

    // Set once the one-time auto-provide consent prompt has been shown this launch so
    // it can't stack: autoProvidedContext re-evaluates every turn across all chats.
    // Static (shared by every agent) so the user is asked at most once per launch. A
    // persisted Granted/Denied ends it across launches.
    private static var didAskAutoProvideConsentThisSession = false

    /// Show the one-time consent prompt (non-blocking) when a turn wanted to auto-send
    /// but the user has never decided. This turn already suppressed auto-send; once
    /// the user grants, the next turn includes the screen. Shown asynchronously so the
    /// in-flight turn is not held on a modal.
    private func requestAutoProvideConsentIfNeeded() {
        guard Self.shouldAskAutoProvideConsent(consent: iTermUserDefaults.autoProvideConsent,
                                               alreadyAskedThisSession: Self.didAskAutoProvideConsentThisSession) else {
            return
        }
        Self.didAskAutoProvideConsentThisSession = true
        DispatchQueue.main.async {
            // Re-check: a concurrent chat's prompt (or a per-chat opt-in) may have
            // resolved consent while this was queued.
            guard iTermUserDefaults.autoProvideConsent == .unknown else { return }
            let selection = iTermWarning.show(
                withTitle: "iTerm2 can include this session’s visible screen and terminal state with every message you send in AI chats where you’ve allowed it, so the assistant sees what you see. You can turn this off any time from a chat’s permission settings.",
                actions: ["Turn On", "Not Now"],
                accessory: nil,
                identifier: nil,
                silenceable: .kiTermWarningTypePersistent,
                heading: "Share Terminal Contents Automatically?",
                window: nil)
            iTermUserDefaults.autoProvideConsent = (selection == .kiTermWarningSelection0) ? .granted : .denied
        }
    }

    /// Whether auto-providing terminal state / visible screen must be suppressed:
    /// true when a turn would auto-send (a category is at .always) but the user has
    /// not granted the global auto-provide consent. This is what stops a legacy
    /// "Always" grant from silently sending the screen before an informed choice.
    nonisolated static func shouldSuppressAutoProvide(wantsAutoSend: Bool,
                                                      consent: iTermAutoProvideConsent) -> Bool {
        return wantsAutoSend && consent != .granted
    }

    /// Whether to show the one-time auto-provide consent prompt: only when the user
    /// has never decided (Unknown) and it has not already been shown this launch
    /// (autoProvidedContext re-evaluates every turn, so the modal must not stack).
    /// A persisted Granted/Denied ends it across launches. Denied is an explicit
    /// "no" - never nag again.
    nonisolated static func shouldAskAutoProvideConsent(consent: iTermAutoProvideConsent,
                                                        alreadyAskedThisSession: Bool) -> Bool {
        return consent == .unknown && !alreadyAskedThisSession
    }

    /// Defang our control-tag delimiters in untrusted terminal content so it cannot
    /// break out of the <visible-screen> / <terminal-state> wrappers and inject
    /// trusted top-level context (prompt injection): terminal output that contains a
    /// literal closing tag (a file the user cats, a hostile log line) would otherwise
    /// close the block early and make everything after it read as top-level model
    /// instructions. Mirrors the guillemet approach in
    /// AutoModeClassifier.neutralizePromptDelimiters, but deliberately preserves
    /// newlines because the visible screen's row layout is meaningful to the model.
    nonisolated static func neutralizeContextDelimiters(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "</visible-screen>", with: "\u{2039}/visible-screen\u{203A}")
            .replacingOccurrences(of: "<visible-screen", with: "\u{2039}visible-screen")
            .replacingOccurrences(of: "</terminal-state>", with: "\u{2039}/terminal-state\u{203A}")
            .replacingOccurrences(of: "<terminal-state", with: "\u{2039}terminal-state")
    }

    /// Append an auto-provided context block to the outgoing user body, matching how
    /// the orchestration provider prepends its snapshot.
    private static func appending(context: String, to body: LLM.Message.Body) -> LLM.Message.Body {
        switch body {
        case .text(let text):
            return .text(text + "\n" + context)
        case .multipart(let parts):
            return .multipart(parts + [.text(context)])
        case .uninitialized, .functionCall, .functionOutput, .attachment:
            return body
        }
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
        drainPendingOrchestrationRequests(reason: "Cancelled.")
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
        // This is the ONE choke point that abnormally resolves every parked
        // completion (both drains above); none of them runs typingResumeFromPark, so
        // forget the outstanding cleared-typing parks here. A leftover count would
        // make the next turn's first park fail to clear the spinner (and, on a
        // pre-turnLifecycle phone, its reply notification never fire). Resetting here
        // covers ALL callers - stop(), transitionToOrchestration(), and
        // fetchCompletionForRegularMessage() - not just stop().
        parkedTyping.reset()
    }

    func stop() {
        cancelPendingCommands()   // resolves parked completions and resets parkedTyping
        drainPendingOrchestrationRequests(reason: "Cancelled.")
        conversation.cancelOutstandingOperation()
        // Safety-net clear of TurnStatusModel. In the normal case the cancel walks
        // back through fetchCompletion's completion to ChatService.finishTurn (see
        // the handleUserCommand(.stop) and dropAgent comments; cancelPendingCommands
        // resumes a parked continuation, which lets the conversation.complete
        // callback fire the same way deliverToolResult's success path does), and
        // finishTurn emits turnEvent(.ended) which clears the model - so this is
        // then a redundant no-op. It bites only if a resumed/failed completion never
        // reaches finishTurn, so an abandoned turn can't leave the chat permanently
        // marked in-flight for the subscribe seed to read.
        //
        // This does NOT suppress finishTurn's turnEvent(.ended) fan-out on a Stop. A
        // turnLifecycleRevision phone treats that .ended like the typing(false) it
        // already receives today on a Stop (same content, same timing relative to
        // the reply), and a parked request that surfaced via userActionRequest has
        // already marked its preamble notified, so .ended fires nothing new. A
        // stricter "never notify for an explicitly Stopped turn" rule would suppress
        // the fan-out in finishTurn on the cancel path - a separate, deliberate change.
        TurnStatusModel.instance.set(inProgress: false, chatID: chatID)
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
            // These content types drive no LLM round-trip. They are normally
            // agent-authored deliveries (not routed here), but a user-authored one
            // still reaches here as a turn: close it via completion(nil) rather than
            // returning bare, so agentWorking's typing(true)/turnEvent(.started) is
            // balanced by finishTurn (stopTyping + turnEvent(.ended)) and the queue
            // head is popped. A bare return would strand typing, leave TurnStatusModel
            // in-flight, and wedge the queue.
            completion(nil)
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
            RLog("Dropping orphan .remoteCommandResponse for cancelled tool")
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
            // Restore typing only if parking this command cleared it (an approval
            // park). Re-emitting typing(true) for an auto-executed tool call would
            // make the phone treat the resume as a new turn and reset the turn's
            // accumulated reply text before it can be notified.
            if pending.clearedTyping {
                typingResumeFromPark()
            }
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
        // Model-layer provider lock: the UI's picker lock can't cover turns
        // that arrive with no configuration (the phone) or with a stale one,
        // so the binding is enforced here on every turn, BEFORE any
        // conversation state is touched. A rejected turn becomes an ordinary
        // agent reply and never reaches the API.
        let verdict = ChatProviderBinding.evaluate(
            boundModelName: ChatListModel.instance?.modelName(forChatID: chatID),
            turnModelName: userMessage.configuration?.model,
            defaultModelName: LLMMetadata.model()?.name,
            vendor: ChatProviderBinding.vendor(forModelName:))
        let turnModelName: String?
        switch verdict {
        case .reject(let reason):
            RLog("ChatAgent: rejected cross-provider turn in \(chatID): \(reason)")
            completion(Message(chatID: userMessage.chatID,
                               author: .agent,
                               content: .markdown(reason),
                               sentDate: Date(),
                               uniqueID: UUID()))
            return
        case .proceed(let modelName, let bindChatTo):
            turnModelName = modelName
            if let bindChatTo {
                try? ChatListModel.instance?.setModel(chatID: chatID, modelName: bindChatTo)
            }
        }

        cancelPendingCommands()

        let needsRenaming = !conversation.messages.anySatisfies({ $0.role == .user})
        // Hosted-tool capability comes from the model the turn will ACTUALLY
        // run on (the binding's verdict, resolved the same way request
        // routing resolves conversation.model), not the global default.
        // With the provider lock, a configuration-less turn runs on the
        // chat's bound model, which can differ from the default; gating on
        // the default could attach code_interpreter to a model that 400s it.
        let effectiveModel = Self.resolvedModel(named: turnModelName) ?? LLMMetadata.model()
        conversation.hostedTools = Self.hostedTools(features: effectiveModel?.features ?? [],
                                                    configuration: userMessage.configuration)

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
        // Auto-provide the linked session's terminal state and/or visible screen when
        // the user has granted the matching "provided automatically" permission for
        // this chat (Check Terminal State -> state, View Contents -> visible screen).
        // Done here (server-side) so phone- and desktop-originated turns both get it;
        // the desktop compose path no longer injects it.
        if let autoContext = autoProvidedContext() {
            transformedBody = Self.appending(context: autoContext, to: transformedBody)
        }
        let userAIMessage = AITermController.Message(
            responseID: baseUserAIMessage.responseID,
            role: baseUserAIMessage.role,
            body: transformedBody,
            reasoningContent: baseUserAIMessage.reasoningContent)
        conversation.add(userAIMessage)
        // The binding's verdict, not the raw configuration: a turn with no
        // configuration runs on the chat's bound model.
        conversation.model = turnModelName
        conversation.shouldThink = userMessage.configuration?.shouldThink
        conversation.reasoningEffort = userMessage.configuration?.reasoningEffort
        conversation.serviceTier = userMessage.configuration?.serviceTier

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
                    RLog("renameChat failed: \(error)")
                }
            } else {
                RLog("Rename produced no usable title")
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
                RLog("Failed to save icon for chat \(chatID): \(error)")
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

            let details = error.localizedDescription
                .components(separatedBy: "\n")
                .map { "    " + $0 }
                .joined(separator: "\n")
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .markdown("**Request failed**\n\n\(details)"),
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
                let transcript = SafetyTranscript.forChat(chatID)
                let safe = await remoteCommand.isSafe(force: mode == .orchestration,
                                                      transcript: transcript)
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
        // If this command blocks on the user's approval, the agent is now waiting,
        // not working: clear typing so the phone's spinner isn't stuck and (on a
        // pre-turnLifecycle phone) the reply notification, which fires on typing
        // false, still fires. The park condition mirrors
        // ChatClient.processRemoteCommandRequest exactly (ask, or always+unsafe, or
        // no resolvable session) via the shared Permission.parksOnApproval
        // predicate. Auto-run (.always+safe) / auto-deny (.never) commands resolve
        // without the user mid-turn, so leave typing alone - re-emitting it would
        // make the phone read the resume as a new turn and drop the reply text.
        let needsApproval = remoteCommandParksOnUser(remoteCommand, safe: safe)
        pendingRemoteCommands[requestID] = .init(completion: completion,
                                                 responseID: responseID,
                                                 clearedTyping: needsApproval)
        try broker.publish(message: .init(chatID: chatID,
                                          author: .agent,
                                          content: .remoteCommandRequest(.classic(remoteCommand), safe: safe),
                                          sentDate: Date(),
                                          uniqueID: requestID),
                           toChatID: chatID,
                           partial: false)
        if needsApproval {
            typingParkOnUser()
        }
    }

    // Predict whether this command will PARK on the user's approval, matching
    // ChatClient.processRemoteCommandRequest exactly: guid selection by category
    // (browser categories resolve browserSessionGuid, else terminalSessionGuid);
    // no resolvable session -> a selectSessionRequest, which parks; otherwise the
    // shared Permission.parksOnApproval mapping (ask, or always+unsafe). Kept in
    // lockstep with the real gate via that shared predicate so a safe .ask command
    // (which still parks) or a browser-category command (its own guid) can't
    // mispredict and strand the phone's typing / reply-notification state.
    private func remoteCommandParksOnUser(_ remoteCommand: RemoteCommand, safe: Bool?) -> Bool {
        let category = remoteCommand.content.permissionCategory
        let guid = category.isBrowserSpecific
            ? ChatListModel.instance?.chat(id: chatID)?.browserSessionGuid
            : ChatListModel.instance?.chat(id: chatID)?.terminalSessionGuid
        guard let guid,
              iTermController.sharedInstance().anySession(forReference: guid) != nil else {
            return true
        }
        let permission = RemoteCommandExecutor.instance.permission(chatID: chatID,
                                                                   inSessionGuid: guid,
                                                                   category: category)
        return permission.parksOnApproval(safe: safe)
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
    /// here if `load(messages:)` ever changes so `AILiveHarness` validates
    /// the chat-restore path end-to-end against real vendor APIs.
    static func aiMessagesForReloadingTranscript(_ messages: [Message]) -> [AITermController.Message] {
        AIChatToolCallRepair.repairingOrphanedToolPairs(
            transcriptMessagesBeforeRepair(messages))
    }

    /// Test-only seam: the structured translation WITHOUT the orphan-repair
    /// pass, for the live negative controls that prove vendors really do
    /// reject un-repaired orphans (so the positive tests aren't vacuous).
    static func transcriptMessagesBeforeRepair(_ messages: [Message]) -> [AITermController.Message] {
        var stateMachine = MessageToPromptStateMachine()
        return aiMessagesForStructuredReplay(messages, stateMachine: &stateMachine)
    }
}

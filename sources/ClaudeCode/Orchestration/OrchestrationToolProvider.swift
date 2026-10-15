//
//  OrchestrationToolProvider.swift
//  iTerm2SharedARC
//

import Foundation

// The orchestration mode's tool surface, bundled as one ToolProvider.
// The companion is RemoteCommandToolProvider, which is the chat's
// session-bound tool surface; together they're the two providers
// ChatAgent ever registers.
//
// What this provider does depends on the chat's current mode:
//
// - .sessionBound: only the request_orchestration_enable tool. The
//   session-bound agent uses it to ask the user to upgrade this chat
//   into orchestration mode; the dispatcher closure parks the LLM
//   completion until the user clicks Enable / Not Now. No system
//   prompt override, no user-text transform.
//
// - .orchestration: the orchestrator's coordinator surface. Two tool
//   groups:
//
//   1. Workgroup-shaped tools (list_workgroups, get_state,
//      send_text, register_watch, start_code_review, etc.). The
//      session-acting ones address their target by session_guid
//      (copied from list_workgroups' SessionSummary); the
//      workgroup-scoped ones (clippings) take a workgroup_id.
//
//   2. Session-shaped tools (session_executeCommand,
//      session_getCommandOutput, session_createFile, etc.) that
//      mirror the session-bound RemoteCommand surface but address
//      sessions by raw GUID (pulled from list_workgroups'
//      SessionSummary).
//
//   Both families dispatch through the same externalInvoker closure
//   the agent provides. The agent publishes
//   .remoteCommandRequest(.external(...)) to the broker and parks
//   the LLM completion; OrchestratorClient (app-side subscriber)
//   runs the dispatcher and publishes the response. The provider
//   never touches PTYSession, iTermController, the dispatcher, or
//   any other app state directly — that's the architectural line
//   between the agent (server) and the app (client).
//
//   Plus the orchestrator system prompt and the per-turn
//   <workgroups> snapshot injection on outgoing user messages.
final class OrchestrationToolProvider: ToolProvider {
    enum Mode {
        case sessionBound
        case orchestration
    }

    typealias EnableRequestHandler =
        (_ completion: @escaping (Result<String, Error>) throws -> ()) -> ()

    // Closure the agent provides for every orchestration tool call
    // (workgroup-shaped AND session_*). The agent's implementation
    // serializes args, publishes .remoteCommandRequest(.external(...))
    // to the broker, and parks the LLM completion. The actual
    // dispatch (PTYSession writes, session spawning, watcher
    // registration, etc.) happens client-side in OrchestratorClient,
    // which subscribes to the broker, runs the dispatcher, and
    // publishes the .remoteCommandResponse that resumes the parked
    // completion via handleRemoteCommandResponse.
    typealias ExternalToolInvoker = (
        _ name: String,
        _ llmMessage: AITermController.Message,
        _ args: AnyCodable,
        _ completion: @escaping (Result<String, Error>) throws -> ()
    ) -> ()

    private let mode: Mode
    private let enableRequestHandler: EnableRequestHandler?
    private let externalInvoker: ExternalToolInvoker?
    // .sessionBound only: whether to expose the watch tools this turn. True
    // when the chat is linked to a terminal session (watchers observe a single
    // session). Resolved each registerTools() so a Link/Unlink toggle picks up
    // on the next register.
    private let offerWatchers: () -> Bool

    // The session-bound provider now carries an externalInvoker (like the
    // orchestration one) so its watch tools can ride the same
    // .remoteCommandRequest(.external(...)) broker path to OrchestratorClient.
    // The RemoteCommand tool surface still routes through the agent's own
    // session-bound dispatcher; only the watch tools use the invoker.
    static func sessionBound(
        enableRequestHandler: @escaping EnableRequestHandler,
        externalInvoker: @escaping ExternalToolInvoker,
        offerWatchers: @escaping () -> Bool
    ) -> OrchestrationToolProvider {
        OrchestrationToolProvider(mode: .sessionBound,
                                  enableRequestHandler: enableRequestHandler,
                                  externalInvoker: externalInvoker,
                                  offerWatchers: offerWatchers)
    }

    static func orchestration(
        externalInvoker: @escaping ExternalToolInvoker
    ) -> OrchestrationToolProvider {
        OrchestrationToolProvider(mode: .orchestration,
                                  enableRequestHandler: nil,
                                  externalInvoker: externalInvoker,
                                  offerWatchers: { false })
    }

    private init(mode: Mode,
                 enableRequestHandler: EnableRequestHandler?,
                 externalInvoker: ExternalToolInvoker?,
                 offerWatchers: @escaping () -> Bool) {
        self.mode = mode
        self.enableRequestHandler = enableRequestHandler
        self.externalInvoker = externalInvoker
        self.offerWatchers = offerWatchers
    }

    // MARK: - ToolProvider

    func registerTools(on conversation: inout AIConversation) {
        switch mode {
        case .sessionBound:
            registerEnableRequestTool(on: &conversation)
            registerSessionBoundWatchTools(on: &conversation)
        case .orchestration:
            registerWorkgroupTools(on: &conversation)
            registerSessionTools(on: &conversation)
        }
    }

    func volatileContext() -> String? {
        guard mode == .orchestration else { return nil }
        return Self.workgroupsSnapshot()
    }

    // MARK: - request_orchestration_enable (.sessionBound)

    private func registerEnableRequestTool(on conversation: inout AIConversation) {
        guard let handler = enableRequestHandler else { return }
        let decl = ChatGPTFunctionDeclaration(
            name: "request_orchestration_enable",
            description: """
                Ask the user to enable orchestration mode for this chat. Use this whenever the \
                task requires interacting with the user's iTerm2 sessions and you don't currently \
                have the tools to do it: sending text or keystrokes, running shell commands, \
                reading on-screen output, controlling a running terminal program, watching a \
                session for changes, or coordinating across multiple sessions (Code Review, Diff, \
                Chat, etc.). This applies to single-session tasks as well as multi-session ones; \
                if the user asks you to do something in their terminal and you have no way to \
                act on a session, this is the tool to call. The user is prompted with a \
                description of what orchestration grants and chooses to approve or decline. On \
                approval, this chat switches to the orchestration tool surface (send_text, \
                get_screen_contents, get_state, register_watch, etc.) starting with the next \
                turn; the linked terminal or browser session, if any, is detached. Returns a \
                string describing the outcome.
                """,
            parameters: JSONSchema(rawJSON: [
                "type": "object",
                "properties": [:],
                "additionalProperties": false,
            ]))
        conversation.define(
            function: decl,
            arguments: AnyCodable.self
        ) { _, _, completion in
            handler(completion)
        }
    }

    // MARK: - Watch tools (.sessionBound, terminal-linked)

    // The watch tools for a session-bound chat. They dispatch through the SAME
    // externalInvoker the orchestration surface uses, so the app-side
    // OrchestratorClient runs the real watcher machinery (tab-status observer,
    // screen pollers, persistence, restart reconciliation). register_watch here
    // has no session_guid: the dispatcher fills the target from the chat's linked
    // terminal session, and it's offered only when a watch form is available
    // (offerWatchers). register_timer, unregister_watch and list_watches are
    // offered regardless: a timer reads nothing and needs no session, so a chat
    // with no linked terminal (or with reads denied) can still set, list and
    // cancel one. request_notification_permission is filtered on companion state
    // exactly as registerWorkgroupTools does.
    private func registerSessionBoundWatchTools(on conversation: inout AIConversation) {
        var definitions: [ToolDefinition] = [OrchestratorCommand.registerTimerDefinition]
        if offerWatchers() {
            definitions.append(OrchestratorCommand.sessionBoundRegisterWatchDefinition)
        }
        definitions.append(OrchestratorCommand.unregisterWatchDefinition)
        definitions.append(OrchestratorCommand.listWatchesDefinition)
        // Offer request_notification_permission on the same companion-state
        // condition as the orchestration surface, reusing its shared definition
        // rather than re-declaring the prose/schema here.
        if CompanionPushRegistry.canPromptForPermission, !CompanionPushRegistry.canNotify,
           let permission = OrchestratorCommand.allToolDefinitions.first(where: {
               $0.name == ToolName.requestNotificationPermission.rawValue }) {
            definitions.append(permission)
        }
        registerExternalTools(definitions, on: &conversation)
    }

    // MARK: - Workgroup-shaped tools (.orchestration)

    private func registerWorkgroupTools(on conversation: inout AIConversation) {
        let definitions = OrchestratorCommand.allToolDefinitions.filter { definition in
            // The push tools depend on the paired phone's state. Tools are
            // bound at agent creation, so a phone pairing mid-conversation
            // appears on the next agent rebuild; notify is offered whenever
            // a phone is around (even before permission, since permission
            // can be granted mid-conversation) and reports a clear error if
            // pushes still can't be delivered.
            if definition.name == ToolName.notify.rawValue,
               !CompanionPushRegistry.phoneIsConnected,
               !CompanionPushRegistry.canNotify {
                return false
            }
            if definition.name == ToolName.requestNotificationPermission.rawValue,
               !CompanionPushRegistry.canPromptForPermission || CompanionPushRegistry.canNotify {
                return false
            }
            return true
        }
        registerExternalTools(definitions, on: &conversation)
    }

    // Shared registration loop: turn each ToolDefinition into an LLM function
    // whose invocation is forwarded through the externalInvoker. Used by both
    // the orchestration workgroup surface and the session-bound watch surface.
    private func registerExternalTools(_ definitions: [ToolDefinition],
                                       on conversation: inout AIConversation) {
        guard let invoker = externalInvoker else { return }
        for definition in definitions {
            let decl = ChatGPTFunctionDeclaration(
                name: definition.name,
                description: definition.description,
                parameters: JSONSchema(rawJSON: definition.inputSchema))
            let toolName = definition.name
            conversation.define(
                function: decl,
                arguments: AnyCodable.self
            ) { llmMessage, args, completion in
                invoker(toolName, llmMessage, args, completion)
            }
        }
    }

    // MARK: - Session-shaped tools (.orchestration)

    private func registerSessionTools(on conversation: inout AIConversation) {
        for content in RemoteCommand.Content.allCases {
            switch content {
            case .isAtPrompt(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .executeCommand(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getLastExitStatus(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getCommandHistory(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getLastCommand(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getCommandBeforeCursor(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .searchCommandHistory(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getCommandOutput(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getScreenContents:
                // NOT offered as session_get_screen_contents: the orchestrator
                // already has a workgroup-level get_screen_contents (which also
                // pairs with scroll_wheel), so a session_* mirror would be a
                // redundant duplicate. (handleSessionToolCall also rejects it
                // defensively.) It exists on RemoteCommand.Content only so the
                // session-bound surface can offer it.
                break
            case .getTerminalSize(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getShellType(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .detectSSHSession(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getRemoteHostname(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getUserIdentity(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getCurrentDirectory(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .setClipboard(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .insertTextAtCursor, .deleteCurrentLine:
                // NOT offered in orchestration mode. These .controlTerminal tools
                // write straight to the PTY with no classification (unlike the
                // gated send_text and execute_command paths), and their payload
                // can submit an arbitrary command (insert_text_at_cursor with a
                // CR, delete_current_line via Ctrl-U), which would bypass the
                // safety gate entirely. send_text (screen/shell-aware gated)
                // already covers typing and control keys, so these are
                // redundant here as well. (handleSessionToolCall also rejects
                // them defensively.)
                break
            case .getManPage(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .createFile(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .searchBrowser(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .loadURL(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .webSearch(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getURL(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .readWebPage(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .restartSession(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            }
        }
    }

    // Generic only because JSONSchema(for:) needs the prototype value
    // for reflection to derive the property schema. Dispatch itself is
    // type-erased — every session_* tool routes through the same
    // externalInvoker closure with the raw LLM args. The dispatcher
    // (client-side) does the per-content decode and PTYSession dispatch.
    private func registerSessionTool<T: Codable>(content: RemoteCommand.Content,
                                                  prototype: T,
                                                  on conversation: inout AIConversation) {
        guard let invoker = externalInvoker else { return }
        // Take the prototype's schema and graft session_guid on at
        // the top level so the agent's arg payload stays flat.
        var schema = JSONSchema(for: prototype, descriptions: content.argDescriptions)
        schema.properties["session_guid"] = JSONSchema.Property(
            type: AnyCodable("string"),
            description: "GUID of the session to target. Pull session_guid values from list_workgroups output (each role's session_guid field).")
        if !schema.required.contains("session_guid") {
            schema.required.append("session_guid")
        }

        let toolName = "session_" + content.functionName
        let decl = ChatGPTFunctionDeclaration(
            name: toolName,
            description: content.functionDescription + " Targets the session with the supplied session_guid.",
            parameters: schema)

        conversation.define(
            function: decl,
            arguments: AnyCodable.self
        ) { llmMessage, args, completion in
            invoker(toolName, llmMessage, args, completion)
        }
    }

    // MARK: - Logging helper

    static func snippet(of string: String) -> String {
        return string
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    // MARK: - User-message transform

    // The `<workgroups>` snapshot for the current turn. Emitted as a
    // standalone trailing volatile block (not merged with the user body),
    // so it needs no surrounding separators.
    //
    // Scope: by design the orchestrator sees the full app-wide workgroup
    // graph (every window, tab, split, and synthetic single-session
    // workgroup the user has open). list_workgroups returns the same set.
    // Per-session
    // control still gates on a one-time user approval (see
    // OrchestratorDispatcher.ensureSessionClaim), so visibility doesn't
    // equal authority; but the agent is intentionally trusted to see
    // the whole graph so it can suggest cross-session coordination the
    // user hadn't explicitly surfaced.
    @MainActor
    private static func workgroupsSnapshot() -> String {
        let workgroups = WorkgroupIntrospection.allWorkgroups()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json: String
        if let data = try? encoder.encode(workgroups),
           let text = String(data: data, encoding: .utf8) {
            json = text
        } else {
            json = "[]"
        }
        return """
        <workgroups>
        \(json)
        </workgroups>
        """
    }

    // MARK: - Human-readable tool descriptions for the chat bubble

    // Called by the agent when building the .remoteCommandRequest
    // bubble for an orchestration tool call. Session/workgroup targets
    // are emitted as @-mentions (e.g. "@<session_guid>"); they're
    // resolved to clickable, current-name links (or "[defunct session]")
    // at display time in the app by OrchestrationMentionRenderer, so
    // this builder does no cross-process workgroup lookup of its own.
    @MainActor
    static func humanDescription(forToolName name: String,
                                  args: AnyCodable) -> String {
        let dict = (args.value as? [String: Any]) ?? [:]
        // Each bubble is a complete localized sentence. Session and workgroup
        // targets are @-mentions (or a localized fallback) and quoted
        // previews carry their own quotation marks, so both are injected as
        // self-contained values.
        switch name {
        case "list_workgroups":
            return String(localized: "OrchestrationTool.ListWorkgroups",
                          defaultValue: "Looking up workgroups",
                          comment: "AI chat bubble shown when the AI lists the workgroups.")
        case "get_state":
            let session = sessionDescription(args: dict)
            return String(localized: "OrchestrationTool.GetState",
                          defaultValue: "Checking state of \(session)",
                          comment: "AI chat bubble shown when the AI checks a session’s state. The placeholder is a link to the session.")
        case "get_screen_contents":
            let session = sessionDescription(args: dict)
            return String(localized: "OrchestrationTool.GetScreenContents",
                          defaultValue: "Reading screen of \(session)",
                          comment: "AI chat bubble shown when the AI reads a session’s screen. The placeholder is a link to the session.")
        case "scroll_wheel":
            // direction defaults to "up" (reveal older content) at the
            // dispatcher; mirror that here so the bubble matches behavior.
            let direction = (dict["direction"] as? String) ?? "up"
            let session = sessionDescription(args: dict)
            if direction == "down" {
                return String(localized: "OrchestrationTool.ScrollDown",
                              defaultValue: "Scrolling \(session) to show newer content",
                              comment: "AI chat bubble shown when the AI scrolls a session down. The placeholder is a link to the session.")
            }
            return String(localized: "OrchestrationTool.ScrollUp",
                          defaultValue: "Scrolling \(session) to show older content",
                          comment: "AI chat bubble shown when the AI scrolls a session up. The placeholder is a link to the session.")
        case "list_workgroup_clippings":
            let workgroup = workgroupDescription(args: dict)
            return String(localized: "OrchestrationTool.ListClippings",
                          defaultValue: "Listing clippings in \(workgroup)",
                          comment: "AI chat bubble shown when the AI lists a workgroup’s clippings. The placeholder is a link to the workgroup.")
        case "send_text":
            let text = (dict["text"] as? String) ?? ""
            let session = sessionDescription(args: dict)
            let quoted = previewQuote(text)
            return String(localized: "OrchestrationTool.SendText",
                          defaultValue: "Typing into \(session): \(quoted)",
                          comment: "AI chat bubble shown when the AI types into a session. The first placeholder is a link to the session; the second is the typed text, already in quotation marks.")
        case "interrupt":
            let session = sessionDescription(args: dict)
            return String(localized: "OrchestrationTool.Interrupt",
                          defaultValue: "Interrupting \(session)",
                          comment: "AI chat bubble shown when the AI interrupts a session. The placeholder is a link to the session.")
        case "add_workgroup_clipping":
            let workgroup = workgroupDescription(args: dict)
            if let title = dict["title"] as? String {
                return String(localized: "OrchestrationTool.AddClipping",
                              defaultValue: "Posting clipping \u{201C}\(title)\u{201D} to \(workgroup)",
                              comment: "AI chat bubble shown when the AI posts a clipping to a workgroup. The first placeholder is the clipping’s title; the second is a link to the workgroup.")
            }
            return String(localized: "OrchestrationTool.AddUntitledClipping",
                          defaultValue: "Posting an untitled clipping to \(workgroup)",
                          comment: "AI chat bubble shown when the AI posts a clipping with no title to a workgroup. The placeholder is a link to the workgroup.")
        case "start_session":
            if let cmd = dict["command"] as? String, !cmd.isEmpty {
                return String(localized: "OrchestrationTool.StartSessionWithCommand",
                              defaultValue: "Starting new session: `\(cmd)`",
                              comment: "AI chat bubble shown when the AI starts a new session that runs a command. The placeholder is the command, shown as code.")
            }
            return String(localized: "OrchestrationTool.StartSession",
                          defaultValue: "Starting new session",
                          comment: "AI chat bubble shown when the AI starts a new session.")
        case "start_code_review":
            let session = sessionDescription(args: dict)
            if let name = dict["prompt_name"] as? String, !name.isEmpty {
                return String(localized: "OrchestrationTool.CodeReviewSavedPrompt",
                              defaultValue: "Kicking off Code Review on \(session) with saved prompt \u{201C}\(name)\u{201D}",
                              comment: "AI chat bubble shown when the AI starts a Code Review. The first placeholder is a link to the session; the second is the name of a saved review prompt.")
            } else if let custom = dict["custom_prompt"] as? String, !custom.isEmpty {
                let quoted = previewQuote(custom)
                return String(localized: "OrchestrationTool.CodeReviewCustomPrompt",
                              defaultValue: "Kicking off Code Review on \(session) with \(quoted)",
                              comment: "AI chat bubble shown when the AI starts a Code Review with its own prompt. The first placeholder is a link to the session; the second is the start of the prompt, already in quotation marks.")
            }
            return String(localized: "OrchestrationTool.CodeReviewDefaultPrompt",
                          defaultValue: "Kicking off Code Review on \(session) with the default prompt",
                          comment: "AI chat bubble shown when the AI starts a Code Review with the default prompt. The placeholder is a link to the session.")
        case "register_watch":
            // Session-bound register_watch carries no session_guid (the target
            // is the chat's linked session); render that as "the linked session"
            // rather than the "(unknown session)" fallback.
            let hasGuid = (dict["session_guid"] as? String).map { !$0.isEmpty } ?? false
            let condition = (dict["condition"] as? String).flatMap { $0.isEmpty ? nil : previewQuote($0) }
            // A state name from the tool's schema, such as idle.
            // Localization unneeded
            let state = (dict["target_state"] as? String) ?? "?"
            guard hasGuid else {
                if let condition {
                    return String(localized: "OrchestrationTool.WatchLinkedCondition",
                                  defaultValue: "Will notify when the linked session satisfies: \(condition)",
                                  comment: "AI chat bubble shown when the AI sets up a watch on the chat’s linked session. The placeholder is the condition, already in quotation marks.")
                }
                return String(localized: "OrchestrationTool.WatchLinkedState",
                              defaultValue: "Will notify when the linked session becomes **\(state)**",
                              comment: "AI chat bubble shown when the AI sets up a watch on the chat’s linked session. The placeholder is a session state name such as idle, which stays in English. Keep the ** markers, which make it bold.")
            }
            let session = sessionDescription(args: dict)
            if let condition {
                return String(localized: "OrchestrationTool.WatchCondition",
                              defaultValue: "Will notify when \(session) satisfies: \(condition)",
                              comment: "AI chat bubble shown when the AI sets up a watch on a session. The first placeholder is a link to the session; the second is the condition, already in quotation marks.")
            }
            return String(localized: "OrchestrationTool.WatchState",
                          defaultValue: "Will notify when \(session) becomes **\(state)**",
                          comment: "AI chat bubble shown when the AI sets up a watch on a session. The first placeholder is a link to the session; the second is a session state name such as idle, which stays in English. Keep the ** markers, which make it bold.")
        case "register_timer":
            let note = (dict["note"] as? String).flatMap { $0.isEmpty ? nil : previewQuote($0) }
            return Self.timerDescription(when: Self.timerWhen(dict: dict), quotedNote: note)
        case "unregister_watch":
            return String(localized: "OrchestrationTool.UnregisterWatch",
                          defaultValue: "Cancelling a watch",
                          comment: "AI chat bubble shown when the AI cancels a watch it set up.")
        case "list_watches":
            return String(localized: "OrchestrationTool.ListWatches",
                          defaultValue: "Listing active watches",
                          comment: "AI chat bubble shown when the AI lists the watches it set up.")
        default:
            if name.hasPrefix("session_") {
                let raw = String(name.dropFirst("session_".count))
                if raw == "execute_command",
                   let cmd = dict["command"] as? String,
                   !cmd.isEmpty {
                    let code = cmd.escapedForMarkdownCode.truncatedWithTrailingEllipsis(to: 80)
                    return String(localized: "OrchestrationTool.ExecuteCommand",
                                  defaultValue: "Executing `\(code)`",
                                  comment: "AI chat bubble shown when the AI runs a command in a session. The placeholder is the command, shown as code.")
                }
                // Use the @<guid> mention form (not a bare backticked guid) so
                // OrchestrationMentionRenderer rewrites it to the session's name
                // (or "[defunct session]" when it no longer resolves).
                let tool = prettifyToolName(raw)
                let session = sessionDescription(args: dict)
                return String(localized: "OrchestrationTool.SessionTool",
                              defaultValue: "\(tool) in \(session)",
                              comment: "AI chat bubble shown when the AI uses a tool on a session. The first placeholder is the tool’s name in English, such as Get selection; the second is a link to the session.")
            }
            // A tool's internal name, made readable.
            return prettifyToolName(name)
        }
    }

    private static func prettifyToolName(_ name: String) -> String {
        let words = name.split(separator: "_").map(String.init)
        guard let first = words.first else { return name }
        let capitalized = first.prefix(1).uppercased() + first.dropFirst()
        return ([capitalized] + words.dropFirst()).joined(separator: " ")
    }

    // Emits an @-mention of the target session rather than resolving it
    // here. OrchestrationMentionRenderer turns it into a link to the
    // session's current name at display time, or "[defunct session]"
    // once the session is gone, sharing the same machinery the
    // orchestrator's text bubbles use.
    private static func sessionDescription(args dict: [String: Any]) -> String {
        guard let guid = dict["session_guid"] as? String, !guid.isEmpty else {
            return String(localized: "OrchestrationTool.UnknownSession",
                          defaultValue: "_(unknown session)_",
                          comment: "Shown in an AI chat bubble in place of a session the AI did not identify. Keep the _ markers, which make it italic.")
        }
        return "@\(guid)"
    }

    // As above, but for a whole-workgroup target. The workgroup_id is
    // already in the "session:<uuid>" / "wg-<uuid>" form the mention
    // renderer's regex understands.
    private static func workgroupDescription(args dict: [String: Any]) -> String {
        guard let wg = dict["workgroup_id"] as? String, !wg.isEmpty else {
            return String(localized: "OrchestrationTool.UnknownWorkgroup",
                          defaultValue: "_unknown workgroup_",
                          comment: "Shown in an AI chat bubble in place of a workgroup the AI did not identify. Keep the _ markers, which make it italic.")
        }
        return "@\(wg)"
    }

    private static func previewQuote(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let maxLen = 80
        let snippet: String
        if oneLine.count <= maxLen {
            snippet = oneLine
        } else {
            snippet = String(oneLine.prefix(maxLen)) + "…"
        }
        return "\u{201C}\(snippet)\u{201D}"
    }

    // When the register_timer bubble says the timer fires: after a duration
    // (e.g. "2 hrs"), or, when the model gave an absolute fire_at that can't be
    // read as a future delta, at <fire_at>. The duration uses the shared
    // localized formatter (DateFormatter.compactDateDifferenceString) rather
    // than a hand-rolled one.
    enum TimerWhen: Equatable {
        case after(String)
        case at(String)
        case later
    }

    private static func timerWhen(dict: [String: Any]) -> TimerWhen {
        if let delay = (dict["delay_seconds"] as? NSNumber)?.doubleValue, delay > 0 {
            return .after(DateFormatter.compactDateDifferenceString(fromTimeDelta: delay))
        }
        if let fireAt = dict["fire_at"] as? String, !fireAt.isEmpty {
            if let date = parseISO8601(fireAt) {
                let delta = date.timeIntervalSinceNow
                if delta > 0 {
                    return .after(DateFormatter.compactDateDifferenceString(fromTimeDelta: delta))
                }
            }
            return .at(fireAt)
        }
        return .later
    }

    // The register_timer bubble text. Each case is a complete localized
    // sentence so translators control word order; quotedNote is the already
    // quoted note preview, if any.
    static func timerDescription(when: TimerWhen, quotedNote: String?) -> String {
        switch (when, quotedNote) {
        case let (.after(duration), nil):
            return String(localized: "OrchestrationTool.TimerAfter",
                          defaultValue: "Setting a timer to fire in \(duration)",
                          comment: "AI chat bubble shown when the AI sets a timer. The placeholder is a short duration, such as 5min.")
        case let (.after(duration), note?):
            return String(localized: "OrchestrationTool.TimerAfterWithNote",
                          defaultValue: "Setting a timer to fire in \(duration): \(note)",
                          comment: "AI chat bubble shown when the AI sets a timer. The first placeholder is a short duration, such as 5min; the second is the timer’s note, already in quotation marks.")
        case let (.at(time), nil):
            return String(localized: "OrchestrationTool.TimerAt",
                          defaultValue: "Setting a timer to fire at \(time)",
                          comment: "AI chat bubble shown when the AI sets a timer. The placeholder is the time the AI asked for, as an ISO 8601 timestamp.")
        case let (.at(time), note?):
            return String(localized: "OrchestrationTool.TimerAtWithNote",
                          defaultValue: "Setting a timer to fire at \(time): \(note)",
                          comment: "AI chat bubble shown when the AI sets a timer. The first placeholder is the time the AI asked for, as an ISO 8601 timestamp; the second is the timer’s note, already in quotation marks.")
        case (.later, nil):
            return String(localized: "OrchestrationTool.TimerLater",
                          defaultValue: "Setting a timer to fire later",
                          comment: "AI chat bubble shown when the AI sets a timer without a recognizable time.")
        case let (.later, note?):
            return String(localized: "OrchestrationTool.TimerLaterWithNote",
                          defaultValue: "Setting a timer to fire later: \(note)",
                          comment: "AI chat bubble shown when the AI sets a timer without a recognizable time. The placeholder is the timer’s note, already in quotation marks.")
        }
    }

    // Parse an ISO-8601 date-time, tolerating both fractional and whole seconds.
    private static func parseISO8601(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}

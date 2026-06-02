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
//      send_text, register_watch, start_code_review, etc.) addressed
//      by OrchestratorTarget(workgroup_id, role).
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

    static func sessionBound(
        enableRequestHandler: @escaping EnableRequestHandler
    ) -> OrchestrationToolProvider {
        OrchestrationToolProvider(mode: .sessionBound,
                                  enableRequestHandler: enableRequestHandler,
                                  externalInvoker: nil)
    }

    static func orchestration(
        externalInvoker: @escaping ExternalToolInvoker
    ) -> OrchestrationToolProvider {
        OrchestrationToolProvider(mode: .orchestration,
                                  enableRequestHandler: nil,
                                  externalInvoker: externalInvoker)
    }

    private init(mode: Mode,
                 enableRequestHandler: EnableRequestHandler?,
                 externalInvoker: ExternalToolInvoker?) {
        self.mode = mode
        self.enableRequestHandler = enableRequestHandler
        self.externalInvoker = externalInvoker
    }

    // MARK: - ToolProvider

    func registerTools(on conversation: inout AIConversation) {
        switch mode {
        case .sessionBound:
            registerEnableRequestTool(on: &conversation)
        case .orchestration:
            registerWorkgroupTools(on: &conversation)
            registerSessionTools(on: &conversation)
        }
    }

    func transform(outgoingUserBody body: LLM.Message.Body) -> LLM.Message.Body {
        guard mode == .orchestration else { return body }
        let prefix = Self.workgroupsSnapshotPrefix()
        switch body {
        case .text(let s):
            return .text(prefix + s)
        case .multipart(let parts):
            return .multipart([.text(prefix)] + parts)
        case .uninitialized, .functionCall, .functionOutput, .attachment:
            return body
        }
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

    // MARK: - Workgroup-shaped tools (.orchestration)

    private func registerWorkgroupTools(on conversation: inout AIConversation) {
        guard let invoker = externalInvoker else { return }
        for definition in OrchestratorCommand.allToolDefinitions {
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
            case .getTerminalSize(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getShellType(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .detectSSHSession(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getRemoteHostname(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getUserIdentity(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getCurrentDirectory(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .setClipboard(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .insertTextAtCursor(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .deleteCurrentLine(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getManPage(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .createFile(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .searchBrowser(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .loadURL(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .webSearch(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .getURL(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
            case .readWebPage(let p): registerSessionTool(content: content, prototype: p, on: &conversation)
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

    // The `<workgroups>` snapshot prefix that wraps every orchestration
    // turn. Returned without trailing user text so callers can either
    // prepend it to a text body or insert it as a leading subpart of a
    // multipart body.
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
    private static func workgroupsSnapshotPrefix() -> String {
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
    // bubble for an orchestration tool call. Reads workgroup state
    // for the role/workgroup labels — a small read-only excursion
    // across the agent/app line, contained to label rendering.
    @MainActor
    static func humanDescription(forToolName name: String,
                                  args: AnyCodable) -> String {
        let dict = (args.value as? [String: Any]) ?? [:]
        switch name {
        case "list_workgroups":
            return "Looking up workgroups"
        case "get_state":
            return "Checking state of " + roleDescription(args: dict)
        case "get_screen_contents":
            return "Reading screen of " + roleDescription(args: dict)
        case "list_workgroup_clippings":
            return "Listing clippings in " + workgroupDescription(args: dict)
        case "send_text":
            let text = (dict["text"] as? String) ?? ""
            return "Typing into " + roleDescription(args: dict)
                + ": " + previewQuote(text)
        case "interrupt":
            return "Interrupting " + roleDescription(args: dict)
        case "add_workgroup_clipping":
            let title = (dict["title"] as? String) ?? "(untitled)"
            return "Posting clipping \u{201C}\(title)\u{201D} to "
                + workgroupDescription(args: dict)
        case "start_session":
            if let cmd = dict["command"] as? String, !cmd.isEmpty {
                return "Starting new session: `\(cmd)`"
            }
            return "Starting new session"
        case "start_code_review":
            let promptLabel: String
            if let name = dict["prompt_name"] as? String, !name.isEmpty {
                promptLabel = "with saved prompt \u{201C}\(name)\u{201D}"
            } else if let custom = dict["custom_prompt"] as? String, !custom.isEmpty {
                promptLabel = "with " + previewQuote(custom)
            } else {
                promptLabel = "with the default prompt"
            }
            return "Kicking off Code Review on " + roleDescription(args: dict)
                + " " + promptLabel
        case "register_watch":
            let state = (dict["target_state"] as? String) ?? "?"
            return "Will notify when " + roleDescription(args: dict)
                + " becomes **\(state)**"
        case "unregister_watch":
            return "Cancelling a watch"
        case "list_watches":
            return "Listing active watches"
        default:
            if name.hasPrefix("session_") {
                let guid = (dict["session_guid"] as? String) ?? "?"
                let raw = String(name.dropFirst("session_".count))
                return "`\(prettifyToolName(raw))` on session `\(guid)`"
            }
            return prettifyToolName(name)
        }
    }

    private static func prettifyToolName(_ name: String) -> String {
        let words = name.split(separator: "_").map(String.init)
        guard let first = words.first else { return name }
        let capitalized = first.prefix(1).uppercased() + first.dropFirst()
        return ([capitalized] + words.dropFirst()).joined(separator: " ")
    }

    @MainActor
    private static func roleDescription(args dict: [String: Any]) -> String {
        // Best-effort: even when the model emits target in a shape we
        // can't decode (e.g. it hallucinated XML inside a JSON string —
        // {"target": "\n  <workgroup_id>...</workgroup_id>\n
        // <role>...</role>\n"} — surface SOMETHING readable in the
        // activity line instead of "_unknown role_". The dispatcher
        // will fail the call with malformed_args either way; this is
        // only about what the user sees scrolling by.
        let raw = dict["target"]
        var wg: String?
        var role: String?
        if let target = raw as? [String: Any] {
            wg = target["workgroup_id"] as? String
            role = target["role"] as? String
        } else if let str = raw as? String {
            // Extract <workgroup_id>...</workgroup_id> and <role>...</role>
            // by hand. Model hallucinations of this shape are common; we
            // don't try to fix the call, just to render it.
            wg = extractTag("workgroup_id", from: str)
            role = extractTag("role", from: str)
        }
        guard let wg, let role else {
            return "_(malformed target)_"
        }
        if let resolved = WorkgroupIntrospection.resolve(
            target: OrchestratorTarget(workgroupID: wg, role: role)) {
            return "**\(resolved.roleName)** in **\(resolved.workgroupName)**"
        }
        return "**\(role)** in **\(wg)**"
    }

    private static func extractTag(_ name: String, from text: String) -> String? {
        let open = "<\(name)>"
        let close = "</\(name)>"
        guard let start = text.range(of: open),
              let end = text.range(of: close, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        let inner = text[start.upperBound..<end.lowerBound]
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    private static func workgroupDescription(args dict: [String: Any]) -> String {
        guard let wg = dict["workgroup_id"] as? String else {
            return "_unknown workgroup_"
        }
        return "**\(WorkgroupIntrospection.displayName(forWorkgroupID: wg))**"
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
}

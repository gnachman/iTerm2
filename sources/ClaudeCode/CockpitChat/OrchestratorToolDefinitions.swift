//
//  OrchestratorToolDefinitions.swift
//  iTerm2SharedARC
//

import Foundation

// JSON-Schema definitions for the 16 orchestrator tools. Passed to
// AIConversation in the tools array of each LLM request so the model
// knows what it can call.
//
// Schemas use plain dictionaries because the destination is JSON
// (the LLM API serializes them) and writing a typed schema layer for
// 16 tools would be more code than the schemas themselves. Keep
// descriptions tunable here. they're what the LLM sees and how it
// decides which tool to use.
struct ToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: Any]
}

// MARK: - Schema helpers

private let stringSchema: [String: Any] = ["type": "string"]
private let integerSchema: [String: Any] = ["type": "integer"]
private let booleanSchema: [String: Any] = ["type": "boolean"]

private func string(_ description: String, enumValues: [String]? = nil) -> [String: Any] {
    var result: [String: Any] = ["type": "string", "description": description]
    if let enumValues {
        result["enum"] = enumValues
    }
    return result
}

private func integer(_ description: String) -> [String: Any] {
    return ["type": "integer", "description": description]
}

private func boolean(_ description: String) -> [String: Any] {
    return ["type": "boolean", "description": description]
}

private func object(_ properties: [(String, [String: Any])],
                    required: [String]) -> [String: Any] {
    var props = [String: Any]()
    for (k, v) in properties { props[k] = v }
    return [
        "type": "object",
        "properties": props,
        "required": required,
        "additionalProperties": false,
    ]
}

private let emptyObjectSchema: [String: Any] = [
    "type": "object",
    "properties": [String: Any](),
    "required": [String](),
    "additionalProperties": false,
]

private let targetSchema: [String: Any] = object([
    ("workgroup_id", string("Runtime workgroup instance ID, or the workgroup display name if unambiguous.")),
    ("role", string("Role within the workgroup. Either the stable role_id (e.g. \u{201C}builtin.claudeCode.review\u{201D}) or the display name (e.g. \u{201C}Code Review\u{201D}).")),
], required: ["workgroup_id", "role"])

// MARK: - Tool list

extension OrchestratorCommand {
    static let allToolDefinitions: [ToolDefinition] = [

        // -------- Discovery --------

        ToolDefinition(
            name: ToolName.listWorkgroups.rawValue,
            description: "List all active workgroups and their member sessions. Each session reports its role within the workgroup, current status (idle/working/waiting), and kind (claude-code/shell/tui/other). Standalone sessions appear as single-session workgroups with a synthetic ID prefixed \u{201C}session:\u{201D}.",
            inputSchema: emptyObjectSchema),

        ToolDefinition(
            name: ToolName.getState.rawValue,
            description: "Get rich state for a single role within a workgroup, including the last cc-status detail message for Claude Code sessions.",
            inputSchema: object([
                ("target", targetSchema),
            ], required: ["target"])),

        ToolDefinition(
            name: ToolName.getScreenContents.rawValue,
            description: "Get the visible contents of a session. For Claude Code sessions, returns a synthesized view of recent hook events (assistant messages, tool calls). For shell sessions, returns scrollback. For TUI sessions, returns a snapshot of the rendered screen with is_snapshot=true; there is no history beyond what's currently displayed. The result includes a kind field so you know how to read the text.",
            inputSchema: object([
                ("target", targetSchema),
                ("lines", integer("Number of trailing lines to return for shell sessions. Default 100. Ignored for tui/claude-code kinds.")),
            ], required: ["target"])),

        ToolDefinition(
            name: ToolName.listWorkgroupClippings.rawValue,
            description: "List the clippings posted to a workgroup. Clippings are structured snippets (type, title, detail) that the user or other agents have posted to the workgroup leader for shared reference. Optional type_filter limits to clippings of a particular type (e.g. \u{201C}Code Review Comment\u{201D}).",
            inputSchema: object([
                ("workgroup_id", stringSchema),
                ("type_filter", string("Optional. Only return clippings whose type matches this string exactly.")),
            ], required: ["workgroup_id"])),

        // -------- Action (claim required) --------

        ToolDefinition(
            name: ToolName.sendText.rawValue,
            description: "Type text into a session as if the user typed it. By default appends a newline. The text supports a small backslash-escape vocabulary so you can send control keys and special characters: \\\\ for a literal backslash, \\n for newline, \\r for carriage return, \\t for tab, and \\uXXXX (four hex digits, JSON-style) for any Unicode scalar. Use this to drive control keys: \\u0003 for Ctrl-C (prefer the dedicated interrupt tool), \\u0004 for Ctrl-D / EOF, \\u001a for Ctrl-Z, \\u000c for Ctrl-L, \\u001b for Escape, etc. When sending a standalone control key, pass append_newline=false so you don't tack an Enter onto it. You may combine control bytes with text and a trailing newline in a single call (e.g. \\u001b:q\\n to quit vim). iTerm2 detects embedded control bytes and sends the payload as a raw keystroke stream rather than a bracketed paste, so the control bytes are interpreted by the target program rather than inserted as literal data. The return value `{\"ack\":{}}` only confirms that the bytes were transmitted; it does NOT confirm the program behaved as you expected. For interactive TUIs (vim, emacs, less, htop, fzf, etc.) always follow up with `get_screen_contents` to verify the effect before telling the user it worked. Requires the user to have approved this chat to control the workgroup; the user is prompted inline on the first send to an unclaimed workgroup.",
            inputSchema: object([
                ("target", targetSchema),
                ("text", stringSchema),
                ("append_newline", boolean("Whether to append a newline to the text. Defaults to true. Set to false when sending control keys (e.g. \\u001b for Escape) by themselves.")),
            ], required: ["target", "text"])),

        ToolDefinition(
            name: ToolName.interrupt.rawValue,
            description: "Send SIGINT to the foreground process of a session, equivalent to the user pressing Ctrl-C. Requires workgroup claim.",
            inputSchema: object([
                ("target", targetSchema),
            ], required: ["target"])),

        ToolDefinition(
            name: ToolName.addWorkgroupClipping.rawValue,
            description: "Post a clipping to a workgroup so it appears alongside any user-posted clippings. Useful for surfacing structured findings (e.g. distilled code-review comments) for the user or other agents to consume. Requires workgroup claim.",
            inputSchema: object([
                ("workgroup_id", stringSchema),
                ("type", string("Short tag describing the clipping kind, e.g. \u{201C}Code Review Comment\u{201D} or \u{201C}Build Error\u{201D}.")),
                ("title", string("One-line headline.")),
                ("detail", string("Full description. Markdown is supported.")),
            ], required: ["workgroup_id", "type", "title", "detail"])),

        // -------- Code Review (convenience) --------

        ToolDefinition(
            name: ToolName.startCodeReview.rawValue,
            description: "Run a Code Review in one call. The target must be the Code Review role. The role can be in either of two ready states: (a) the prompt overlay is up (pending_action mentions \u{201C}Code Review prompt overlay\u{201D}), in which case the overlay is populated and the review program launches; or (b) the Code Review session is already running and idle at its chat prompt, in which case the review prompt is typed in directly to start a fresh review on the existing session. Either way the call auto-registers a watcher for the role reaching idle, so you'll receive a status_update when the review completes. The call errors only if the role isn't the Code Review role or its program is busy. Pick the prompt by name from the saved prompts (see the system message for the list) via prompt_name, OR pass custom_prompt with free-form text, OR leave both nil to use the user's default prompt. Prefer this over send_text + register_watch for code reviews.",
            inputSchema: object([
                ("target", targetSchema),
                ("prompt_name", string("Optional. Name of a saved prompt from the user's prompt list.")),
                ("custom_prompt", string("Optional. Free-form prompt text when no saved prompt fits.")),
            ], required: ["target"])),

        // -------- Spawn (always prompts) --------

        ToolDefinition(
            name: ToolName.startSession.rawValue,
            description: "Spawn a new terminal session. Use window=\u{201C}new\u{201D} to open a new window, \u{201C}tab\u{201D} (default) to add a tab to the current window, or \u{201C}current\u{201D} to split the current pane vertically. The user is always prompted to approve the spawn (and the command being run, if any). Returns the synthetic workgroup_id of the new single-session workgroup so you can immediately drive the new session with the other tools (send_text, get_screen_contents, etc.).",
            inputSchema: object([
                ("profile", string("Optional profile name. Falls back to the default profile when absent.")),
                ("command", string("Optional command to run in the new session. If absent, the profile's default shell is used.")),
                ("cwd", string("Optional working directory.")),
                ("window", string("Where to put the new session. \u{201C}new\u{201D} for a new window, \u{201C}current\u{201D} to split the current pane, \u{201C}tab\u{201D} (default) for a new tab in the current window.",
                                  enumValues: ["new", "current", "tab"])),
            ], required: [])),

        // -------- Watchers (async; non-blocking) --------

        ToolDefinition(
            name: ToolName.registerWatch.rawValue,
            description: "Register an async watcher for a session reaching a particular state (idle / working / waiting). This call returns immediately and does NOT block your turn. When the watched state is reached, iTerm2 delivers a `<status_update>...</status_update>` message into the chat as a separate turn; treat that as a system event from iTerm2 (not a new user request) and respond with a brief summary to the user. Watchers are de-duplicated on (session, target_state): registering the same watch twice returns the existing watcher_id. If the target is already in the desired state at registration time, the watcher fires immediately. Watchers persist across iTerm2 restarts; if a watched session can't be restored, you get a status_update with reason=\u{201C}watcher_dropped\u{201D}.",
            inputSchema: object([
                ("target", targetSchema),
                // "unknown" is included in the enum so the schema matches
                // the runtime SessionState type (which can appear in
                // get_state output), but it isn't a transition target;
                // the dispatcher rejects watch registrations for
                // "unknown" with a clear error.
                ("target_state", string("State to watch for. Must be a transition target: \u{201C}idle\u{201D}, \u{201C}working\u{201D}, or \u{201C}waiting\u{201D}. \u{201C}unknown\u{201D} is shown by get_state when a session has no tab status yet, but it is not a watchable transition.", enumValues: ["idle", "working", "waiting", "unknown"])),
            ], required: ["target", "target_state"])),

        ToolDefinition(
            name: ToolName.unregisterWatch.rawValue,
            description: "Cancel a registered watcher by its watcher_id (from register_watch or list_watches). No-op if the watcher has already fired or doesn't exist.",
            inputSchema: object([
                ("watcher_id", stringSchema),
            ], required: ["watcher_id"])),

        ToolDefinition(
            name: ToolName.listWatches.rawValue,
            description: "List every async watcher currently registered for this chat.",
            inputSchema: emptyObjectSchema),

        // -------- User --------
        //
        // notify_user is intentionally not registered: the dispatcher
        // throws notImplemented for it today, so advertising it would
        // tempt the LLM to call it and burn a tool-call slot for a
        // structured error. When implemented, restore the definition
        // here and the dispatcher arm in OrchestratorDispatcher.
    ]
}

//
//  OrchestratorToolDefinitions.swift
//  iTerm2SharedARC
//

import Foundation

// JSON-Schema definitions for the 12 orchestrator tools. Passed to
// AIConversation in the tools array of each LLM request so the model
// knows what it can call.
//
// Schemas use plain dictionaries because the destination is JSON
// (the LLM API serializes them) and writing a typed schema layer for
// 12 tools would be more code than the schemas themselves. Keep
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

private func nullableString(_ description: String, enumValues: [String]? = nil) -> [String: Any] {
    var result: [String: Any] = ["type": ["string", "null"], "description": description]
    if let enumValues {
        result["enum"] = enumValues.map { $0 as Any } + [NSNull()]
    }
    return result
}

private func nullableInteger(_ description: String) -> [String: Any] {
    return ["type": ["integer", "null"], "description": description]
}

private func nullableBoolean(_ description: String) -> [String: Any] {
    return ["type": ["boolean", "null"], "description": description]
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

// Every session-acting tool addresses its target with this one field.
// The agent copies a session_guid verbatim from the <workgroups>
// snapshot (each role carries a session_guid); the app resolves it to
// the owning workgroup and role. A GUID is globally unique, so no
// separate role/workgroup disambiguation is needed.
private let sessionGuidSchema: [String: Any] =
    string("The session_guid of the target session, copied verbatim from a role in the <workgroups> snapshot (its session_guid field).")

// MARK: - Tool list

extension OrchestratorCommand {
    // Computed (not a stored let) because parts of the text depend on
    // runtime state: push-related guidance only appears when a companion
    // device is paired. Evaluated at agent creation, like the tool list
    // itself.
    static var allToolDefinitions: [ToolDefinition] { [

        // -------- Discovery --------

        ToolDefinition(
            name: ToolName.listWorkgroups.rawValue,
            description: "List all active workgroups and their member sessions. Each session reports its role within the workgroup, current status (idle/working/waiting), status_source, and kind (claude-code/shell/tui/other). status_source says how much to trust `status`: \u{201C}reported\u{201D} means the program announces its own status (accurate, and state watchers fire on exact transitions); \u{201C}inferred\u{201D} means iTerm2 is guessing from indicators, so `status` is unreliable (e.g. a program waiting at a splash screen looks \u{201C}idle\u{201D}). Standalone sessions appear as single-session workgroups with a synthetic ID prefixed \u{201C}session:\u{201D}.",
            inputSchema: emptyObjectSchema),

        ToolDefinition(
            name: ToolName.getState.rawValue,
            description: "Get rich state for a single session, including the last cc-status detail message for Claude Code sessions. The status_source field says whether `status` is announced by the program itself (\u{201C}reported\u{201D}, trustworthy) or guessed from indicators (\u{201C}inferred\u{201D}, unreliable).",
            inputSchema: object([
                ("session_guid", sessionGuidSchema),
            ], required: ["session_guid"])),

        ToolDefinition(
            name: ToolName.getScreenContents.rawValue,
            description: "Get the visible contents of a session. For Claude Code sessions, returns a synthesized view of recent hook events (assistant messages, tool calls). For shell sessions, returns scrollback. For TUI sessions, returns a snapshot of the rendered screen with is_snapshot=true; there is no history beyond what's currently displayed. The result includes a kind field so you know how to read the text.\n\nThe result also reports `screen` (\u{201C}primary\u{201D} or \u{201C}alternate\u{201D}) and `mouse_reporting` (bool). On the primary screen the returned text is linear scrollback (real history; ask for more `lines` to see more). On the alternate screen (full-screen apps like vim/less/htop, and Claude Code) ONLY the current grid is returned and is_snapshot is true: older content isn't in scrollback. To view content that scrolled off, if `screen` is \u{201C}alternate\u{201D} and `mouse_reporting` is true, use the scroll_wheel tool (direction=\u{201C}up\u{201D}) and then call get_screen_contents again.\n\nThe text uses a few markup tokens (the angle brackets are U+27E8/U+27E9 and effectively never occur in real terminal output):\n\u{27E8}dim\u{27E9}\u{2026}\u{27E8}/dim\u{27E9} wraps faint/dimmed text. This is how shells and TUIs render inline suggestions and ghost completions (zsh-autosuggestions, fish autosuggest, Claude Code's suggested reply, etc.). \n\u{27E8}cursor\u{27E9} marks the text cursor's position. \n\u{27E8}image\u{27E9} stands in for an inline image. These tokens are inserted by iTerm2 and are not literally present on the screen.",
            inputSchema: object([
                ("session_guid", sessionGuidSchema),
                ("lines", nullableInteger("Number of trailing lines to return for shell sessions. Use null for the default 100. Ignored for tui/claude-code kinds.")),
            ], required: ["session_guid", "lines"])),

        ToolDefinition(
            name: ToolName.scrollWheel.rawValue,
            description: "Send mouse scroll-wheel events to a session to reveal content that's off-screen. This is only useful when get_screen_contents reports screen=\u{201C}alternate\u{201D} (a full-screen app like Claude Code, vim, less, htop): on the alternate screen only the current grid is returned, and older content isn't in scrollback, so scrolling the app's own viewport is the only way to see it. REQUIRES the session to have mouse reporting enabled (get_screen_contents reports mouse_reporting=true); if it's off, this tool errors and does nothing. Workflow: call get_screen_contents, and if you need to see earlier content and screen=\u{201C}alternate\u{201D} with mouse_reporting=true, call scroll_wheel with direction=\u{201C}up\u{201D}, then call get_screen_contents again to read the now-revealed lines. Repeat to page further. Not every alternate-screen app honors the scroll wheel (some ignore it, some scroll a pane you didn't intend); if the screen doesn't change after scrolling, stop and tell the user rather than scrolling blindly. On the primary screen (screen=\u{201C}primary\u{201D}) you don't need this at all: just ask get_screen_contents for more lines.",
            inputSchema: object([
                ("session_guid", sessionGuidSchema),
                ("lines", integer("Number of scroll-wheel notches to send. Each notch is one wheel event; how many text lines that moves depends on the app (often 1 or 3). Start small (e.g. 3) and re-read.")),
                ("direction", string("\u{201C}up\u{201D} reveals OLDER content (the usual choice for paging back through history); \u{201C}down\u{201D} reveals NEWER content. Defaults to \u{201C}up\u{201D}.", enumValues: ["up", "down"])),
            ], required: ["session_guid", "lines"])),

        ToolDefinition(
            name: ToolName.listWorkgroupClippings.rawValue,
            description: "List the clippings posted to a workgroup. Clippings are structured snippets (type, title, detail) that the user or other agents have posted to the workgroup leader for shared reference. Optional type_filter limits to clippings of a particular type (e.g. \u{201C}Code Review Comment\u{201D}).",
            inputSchema: object([
                ("workgroup_id", stringSchema),
                ("type_filter", nullableString("Optional. Only return clippings whose type matches this string exactly. Use null for all types.")),
            ], required: ["workgroup_id", "type_filter"])),

        // -------- Action (claim required) --------

        ToolDefinition(
            name: ToolName.sendText.rawValue,
            description: "Type text into a session as if the user typed it. By default appends a newline. The text supports a small backslash-escape vocabulary so you can send control keys and special characters: \\\\ for a literal backslash, \\n for newline, \\r for carriage return, \\t for tab, and \\uXXXX (four hex digits, JSON-style) for any Unicode scalar. Use this to drive control keys: \\u0003 for Ctrl-C (prefer the dedicated interrupt tool), \\u0004 for Ctrl-D / EOF, \\u001a for Ctrl-Z, \\u000c for Ctrl-L, \\u001b for Escape, etc. When sending a standalone control key, pass append_newline=false so you don't tack an Enter onto it. You may combine control bytes with text and a trailing newline in a single call (e.g. \\u001b:q\\n to quit vim). iTerm2 detects embedded control bytes and sends the payload as a raw keystroke stream rather than a bracketed paste, so the control bytes are interpreted by the target program rather than inserted as literal data. The return value `{\"ack\":{}}` only confirms that the bytes were transmitted; it does NOT confirm the program behaved as you expected. For interactive TUIs (vim, emacs, less, htop, fzf, etc.) always follow up with `get_screen_contents` to verify the effect before telling the user it worked. Requires the user to have approved this chat to control the workgroup; the user is prompted inline on the first send to an unclaimed workgroup.",
            inputSchema: object([
                ("session_guid", sessionGuidSchema),
                ("text", stringSchema),
                ("append_newline", nullableBoolean("Whether to append a newline to the text. Use null for the default true. Set to false when sending control keys (e.g. \\u001b for Escape) by themselves.")),
            ], required: ["session_guid", "text", "append_newline"])),

        ToolDefinition(
            name: ToolName.interrupt.rawValue,
            description: "Send SIGINT to the foreground process of a session, equivalent to the user pressing Ctrl-C. Requires workgroup claim.",
            inputSchema: object([
                ("session_guid", sessionGuidSchema),
            ], required: ["session_guid"])),

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
            description: "Run a Code Review in one call. The session_guid must name the Code Review role's session. The session can be in either of two ready states: (a) the prompt overlay is up (pending_action mentions \u{201C}Code Review prompt overlay\u{201D}), in which case the overlay is populated and the review program launches; or (b) the Code Review session is already running and idle at its chat prompt, in which case the review prompt is typed in directly to start a fresh review on the existing session. Either way the call auto-registers a watcher for the session reaching idle, so you'll receive a status_update when the review completes. The call errors only if the session isn't the Code Review role or its program is busy. Pick the prompt by name from the saved prompts (see the system message for the list) via prompt_name, OR pass custom_prompt with free-form text, OR leave both nil to use the user's default prompt. Prefer this over send_text + register_watch for code reviews.",
            inputSchema: object([
                ("session_guid", sessionGuidSchema),
                ("prompt_name", nullableString("Optional. Name of a saved prompt from the user's prompt list. Use null when not using a saved prompt.")),
                ("custom_prompt", nullableString("Optional. Free-form prompt text when no saved prompt fits. Use null to use the default prompt.")),
            ], required: ["session_guid", "prompt_name", "custom_prompt"])),

        // -------- Spawn (always prompts) --------

        ToolDefinition(
            name: ToolName.startSession.rawValue,
            description: "Spawn a new terminal session. Use window=\u{201C}new\u{201D} to open a new window, \u{201C}tab\u{201D} (default) to add a tab to the current window, or \u{201C}current\u{201D} to split the current pane vertically. The user is always prompted to approve the spawn (and the command being run, if any). Returns the session_guid of the new session so you can immediately drive it with the other tools (send_text, get_screen_contents, etc.).",
            inputSchema: object([
                ("profile", nullableString("Optional profile name. Use null to fall back to the default profile.")),
                ("command", nullableString("Optional command to run in the new session. Use null for the profile's default shell.")),
                ("cwd", nullableString("Optional working directory. Use null for the default.")),
                ("window", nullableString("Where to put the new session. \u{201C}new\u{201D} for a new window, \u{201C}current\u{201D} to split the current pane, \u{201C}tab\u{201D} (default) for a new tab in the current window. Use null for tab.",
                                          enumValues: ["new", "current", "tab"])),
            ], required: ["profile", "command", "cwd", "window"])),

        // -------- Watchers (async; non-blocking) --------

        ToolDefinition(
            name: ToolName.registerWatch.rawValue,
            description: "Register an async watcher on a session. Supply exactly ONE of target_state or condition. This call returns immediately and does NOT block your turn. When the watch fires, iTerm2 delivers a `<status_update>...</status_update>` message into the chat as a separate turn; treat that as a system event from iTerm2 (not a new user request) and respond with a brief summary to the user.\(CompanionPushRegistry.devicePaired ? " When the user asked to be told or alerted when this happens, set notify_user=true: iTerm2 then sends a push notification to their iPhone automatically when the watch fires (a chat reply alone won't reach a user who is away from the Mac). If notifications aren't enabled yet, call request_notification_permission before registering." : "") Choosing the form: use target_state (idle/working/waiting) when the session's status_source is \u{201C}reported\u{201D} (see list_workgroups / get_state) — the watch then fires on the program's own exact status transitions. When status_source is \u{201C}inferred\u{201D}, or when what you're waiting for isn't really an idle/working/waiting transition (e.g. \u{201C}emacs has exited and a shell prompt is showing\u{201D}, \u{201C}the build printed a success or failure line\u{201D}, \u{201C}a password prompt appeared\u{201D}), prefer condition: a plain-English description that an AI judge evaluates by periodically reading the session's screen. Inferred idle/busy is ambiguous (a program parked at a splash screen counts as \u{201C}idle\u{201D}), so a specific condition is far more accurate there. Screen-judged watches (all condition watches, and target_state watches on \u{201C}inferred\u{201D} sessions) time out after a few minutes with reason=\u{201C}watchTimedOut\u{201D}; re-register to keep waiting. Watchers are de-duplicated on (session, target_state, condition): registering the same watch twice returns the existing watcher_id. If the goal is already satisfied at registration time, the watcher fires immediately. Watchers persist across iTerm2 restarts; if a watched session can't be restored, you get a status_update with reason=\u{201C}watcherDropped\u{201D}. Either way, do NOT poll yourself.",
            inputSchema: object([
                ("session_guid", sessionGuidSchema),
                // "unknown" is included in the enum so the schema matches
                // the runtime SessionState type (which can appear in
                // get_state output), but it isn't a transition target;
                // the dispatcher rejects watch registrations for
                // "unknown" with a clear error.
                ("target_state", string("State to watch for. Must be a transition target: \u{201C}idle\u{201D}, \u{201C}working\u{201D}, or \u{201C}waiting\u{201D}. \u{201C}unknown\u{201D} is shown by get_state when a session has no tab status yet, but it is not a watchable transition. Mutually exclusive with condition.", enumValues: ["idle", "working", "waiting", "unknown"])),
                ("condition", string("Plain-English condition to watch for, judged by an AI reading the session's screen, e.g. \u{201C}emacs has exited and a shell prompt is showing\u{201D}. Describe what will be VISIBLE on screen when the condition holds. Mutually exclusive with target_state.")),
            ] + (CompanionPushRegistry.devicePaired ? [
                ("notify_user", boolean("Set true when the user asked to be told/alerted when this happens. iTerm2 sends a push notification to their iPhone automatically when the watch fires; you do not need to call notify yourself.")),
            ] : []), required: ["session_guid"])),

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

        // -------- Companion phone --------

        // The push tools are conditionally offered (see
        // OrchestrationToolProvider's filter): notify whenever a companion
        // phone is paired, request_notification_permission only while a
        // phone is connected but cannot yet receive pushes.
        ToolDefinition(
            name: ToolName.notify.rawValue,
            description: "Send a push notification to the user's iPhone (their paired iTerm2 companion device). Use it to alert the user to something that needs their attention when they may be away from the Mac: a long-running task finished, a session is waiting on input, or an error needs their decision. Keep it brief; it renders as a standard iOS notification. Do not use it for routine progress updates. If it fails because notifications aren't enabled, call request_notification_permission first.",
            inputSchema: object([
                ("title", string("Short notification title, a few words.")),
                ("body", string("Notification body, one or two sentences.")),
            ], required: ["title", "body"])),

        ToolDefinition(
            name: ToolName.requestNotificationPermission.rawValue,
            description: "Ask the user, on their paired iPhone, for permission to receive notifications. Call this before the first notify when the user asks to be alerted about something (e.g. \u{201C}let me know when my job finishes\u{201D}) and notifications aren't enabled yet. iOS shows its standard permission dialog on the phone; this returns the outcome. If the user previously declined, the dialog cannot be shown again and they must enable notifications in iOS Settings, which the result will say. This is a valuable feature that users won't discover on their own, so offer this when they ask to be notified (for example, if you create a watcher, you should probably request notification permission). If the result is a decline, accept it: do not call this again or lobby the user about Settings unless they bring it up.",
            inputSchema: emptyObjectSchema),
    ] }
}

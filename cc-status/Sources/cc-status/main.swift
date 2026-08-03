import Foundation

// Get iTerm2 session ID from environment.
// TERM_SESSION_ID is like "w0t0p0:D1B2BAE2-3D01-4BB6-9021-27D6CF210957"
guard let termSessionID = ProcessInfo.processInfo.environment["TERM_SESSION_ID"],
      let colonIndex = termSessionID.firstIndex(of: ":") else {
    exit(0)
}
let sessionID = String(termSessionID[termSessionID.index(after: colonIndex)...])

// Read JSON payload from stdin.
let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty,
      let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
      let eventName = json["hook_event_name"] as? String else {
    exit(0)
}

// Map hook event to status, colors, and detail.
//
// Detail lifecycle:
//   • SET on events that carry rich, at-a-glance info (PermissionRequest, Stop,
//     Notification for unusual subtypes).
//   • CLEARED (set to "") on events that make prior detail stale: the start of a
//     new turn (UserPromptSubmit), ongoing tool activity (Pre/PostToolUse), and
//     session boundaries (SessionStart/End). This is what stops "Allow Edit: …"
//     from sticking around after the user grants permission.
//   • LEFT ALONE (nil) for duplicate signals — Notification(permission_prompt)
//     would overwrite PermissionRequest's richer detail; Notification(idle_prompt)
//     would overwrite Stop's last_assistant_message.
// status/colors are nil for updates that only store the background-task
// count without changing what's displayed (SubagentStop reaching zero).
var status: String? = nil
var dotColor: String? = nil
var textColor: String? = nil
// nil = don't touch detail; non-nil (including "") = send --detail through.
var detail: String? = nil
// nil = don't touch the stored count; non-nil = send --background-tasks.
// iTerm2 keeps the count in RAM only (never written to disk); it exists
// so a later idle_prompt, whose payload carries no task info, can read
// back what the last Stop/SubagentStop knew.
var backgroundTasks: Int? = nil

switch eventName {
case "UserPromptSubmit", "PreToolUse", "PostToolUse":
    status = "working"
    dotColor = "#ff9500"
    textColor = "#ff9500"
    detail = ""  // new turn / tool activity — previous detail is stale
case "PermissionRequest":
    status = "waiting"
    dotColor = "#5f87ff"
    textColor = "#5f87ff"
    detail = permissionDetail(json)
case "Notification":
    let notificationType = json["notification_type"] as? String
    if notificationType == "idle_prompt" {
        // Verified against Claude Code 2.1.201: idle_prompt payloads do
        // NOT carry background_tasks, so read back the count the
        // Stop/SubagentStop handlers stored in iTerm2. Without the
        // fallback, the idle nudge (~60s after Stop) would flip a
        // working-because-background session to idle, resurrecting the
        // false-idle bug.
        let running = backgroundTaskCount(json) ?? storedBackgroundTaskCount(it2SessionID: sessionID)
        if running > 0 {
            status = "working"
            dotColor = "#ff9500"
            textColor = "#ff9500"
            detail = backgroundDetail(count: running)
        } else {
            status = "idle"
            dotColor = "#00d75f"
            textColor = "#888888"
            if let message = json["last_assistant_message"] as? String {
                // Re-assert the last message. Also replaces a stale
                // "N background tasks running" line from an earlier
                // Stop, if this payload happens to carry the message.
                detail = condense(message)
            } else {
                // Clear the detail. An earlier Stop may have set
                // "N background tasks running" and the tasks have
                // since finished without another Stop (background
                // shell commands end silently); leaving that line
                // next to an idle dot would be false. The cost is
                // that Stop's last_assistant_message no longer
                // survives the nudge (2.1.201 idle_prompt payloads
                // lack the message); truthful-but-empty beats
                // sticky-but-possibly-false.
                detail = ""
            }
        }
    } else {
        status = "waiting"
        dotColor = "#5f87ff"
        textColor = "#5f87ff"
        // Skip detail for permission_prompt (PermissionRequest carries it better).
        // Other subtypes (auth_success, elicitation_dialog, ...) get the message.
        if notificationType != "permission_prompt", let message = json["message"] as? String {
            detail = condense(message)
        }
    }
case "Stop":
    // Stop fires whenever the main loop finishes a turn, including while
    // background subagents (Agent tool with run_in_background) and
    // background Bash tasks keep working. In that case the session is not
    // meaningfully idle: a completion watcher that trusts "idle" here
    // fires on every between-subagents lull. background_tasks (Claude
    // Code 2.1.198+; shape verified against 2.1.201) lists the
    // still-running work; stay "working" until a Stop arrives with none.
    // Store the count in iTerm2 only when the payload actually carried
    // the field: on older Claude Code it never exists, and the stored
    // count correctly stays at its initial zero.
    let running: Int
    if let counted = backgroundTaskCount(json) {
        running = counted
        backgroundTasks = counted
    } else {
        running = 0
    }
    if running > 0 {
        status = "working"
        dotColor = "#ff9500"
        textColor = "#ff9500"
        detail = backgroundDetail(count: running)
    } else {
        status = "idle"
        dotColor = "#00d75f"
        textColor = "#888888"
        if let message = json["last_assistant_message"] as? String {
            detail = condense(message)
        } else {
            detail = ""
        }
    }
case "SubagentStop":
    // Fires when any subagent finishes, including background agents
    // completing while the main loop sits at the prompt, so it is the
    // only signal that updates the count between turns. The payload
    // still lists the agent that just stopped as "running" (verified on
    // 2.1.201), so exclude it by agent_id. Only re-assert "working"
    // while work remains: SubagentStop also fires for internal utility
    // agents while the session is genuinely idle, and flashing those as
    // "working" would create the inverse of the false-idle bug.
    guard let remaining = backgroundTaskCount(json, excludingID: json["agent_id"] as? String) else {
        exit(0)  // No field: nothing to learn from this event.
    }
    backgroundTasks = remaining
    if remaining > 0 {
        status = "working"
        dotColor = "#ff9500"
        textColor = "#ff9500"
        detail = backgroundDetail(count: remaining)
    }
    // remaining == 0: last one done. Store the zero but change nothing
    // visible; the main loop wakes to process the results and its own
    // events (PostToolUse/Stop) report from here.
case "StopFailure":
    // The turn ended in an API error, but background tasks keep running
    // independently; apply the same gate as Stop so a failed turn does
    // not fake idleness during background work.
    let running: Int
    if let counted = backgroundTaskCount(json) {
        running = counted
        backgroundTasks = counted
    } else {
        running = storedBackgroundTaskCount(it2SessionID: sessionID)
    }
    if running > 0 {
        status = "working"
        dotColor = "#ff9500"
        textColor = "#ff9500"
        detail = backgroundDetail(count: running)
    } else {
        status = "idle"
        dotColor = "#00d75f"
        textColor = "#888888"
        detail = ""
    }
case "SessionStart", "SessionEnd":
    status = "idle"
    dotColor = "#00d75f"
    textColor = "#888888"
    detail = ""  // session boundary — wipe stale detail
    backgroundTasks = 0  // and the stored count with it
default:
    exit(0)
}

// Build and run it2 invocation. Every field is presence-gated: an
// update can change just the stored background-task count without
// touching the visible status.
var it2Args = [
    "set-status",
    "--session", sessionID,
]
if let status = status {
    it2Args.append(contentsOf: ["--status", status])
}
if let dotColor = dotColor {
    it2Args.append(contentsOf: ["--dot-color", dotColor])
}
if let textColor = textColor {
    it2Args.append(contentsOf: ["--text-color", textColor])
}
// Pass --detail only when cc-status has an opinion; empty string explicitly clears.
if let detail = detail {
    it2Args.append(contentsOf: ["--detail", detail])
}
if let backgroundTasks = backgroundTasks {
    it2Args.append(contentsOf: ["--background-tasks", String(backgroundTasks)])
}

let it2 = resolveIt2()
let process = Process()
process.executableURL = it2.executable
process.arguments = it2.leadingArgs + it2Args
do {
    try process.run()
} catch {
    FileHandle.standardError.write(Data("cc-status: failed to run it2: \(error)\n".utf8))
    exit(0)
}
process.waitUntilExit()
if process.terminationStatus != 0 {
    FileHandle.standardError.write(Data("cc-status: it2 exited \(process.terminationStatus) for \(eventName)\n".utf8))
}

// MARK: - it2 resolution

/// Locate the it2 binary to run.
///
/// cc-status is invoked through a stable symlink in iTerm2's dot dir that points
/// at <bundle>/Contents/Resources/utilities/cc-status, and it2 ships right next
/// to it in that same directory. Resolving it2 relative to our own realpath is
/// robust against $PATH not containing the utilities dir: anything in a shell rc
/// that rewrites PATH (mise, asdf, perlbrew, …) drops the entry iTerm2 injects,
/// which would otherwise make `/usr/bin/env it2` fail to find it2 and — because
/// we exit 0 on a failed launch — silently leave the Session Status tool empty.
///
/// Returns the absolute it2 path when the sibling is present and executable;
/// otherwise falls back to a PATH lookup via /usr/bin/env so a hand-installed it2
/// still works if the bundle layout ever changes.
func resolveIt2() -> (executable: URL, leadingArgs: [String]) {
    let fm = FileManager.default
    // Claude Code invokes the hook by its absolute command path, so argv[0] is
    // the dot-dir symlink; resolvingSymlinksInPath follows it into the bundle.
    let argv0 = CommandLine.arguments.first ?? "cc-status"
    let resolved = URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
    let sibling = resolved.deletingLastPathComponent()
        .appendingPathComponent("it2")
    if fm.isExecutableFile(atPath: sibling.path) {
        return (sibling, [])
    }
    return (URL(fileURLWithPath: "/usr/bin/env"), ["it2"])
}

// MARK: - Background tasks

/// Number of still-running background subagents/tasks reported in a hook
/// payload, or nil when the field is absent (older Claude Code versions,
/// and all Notification payloads).
///
/// Verified against Claude Code 2.1.201: the field is an array of objects
/// like {"id", "type" (shell/subagent), "status" ("running"), "description",
/// "command"/"agent_type"}. Completed tasks are pruned from the array, but
/// filter by status anyway in case a finished entry ever lingers; count
/// unknown statuses as active because a wrongly-active count only delays a
/// watcher (the orchestrator escalates to screen observation), while a
/// wrongly-zero count fires it falsely. The dictionary/number shapes are
/// defensive, in case the representation changes.
///
/// excludingID drops the entry whose id matches: a SubagentStop payload
/// still lists the agent that just stopped as "running".
func backgroundTaskCount(_ json: [String: Any], excludingID: String? = nil) -> Int? {
    guard let value = json["background_tasks"] else {
        return nil
    }
    let finishedStatuses: Set<String> = [
        "completed", "failed", "cancelled", "canceled", "killed", "stopped", "done",
    ]
    switch value {
    case let array as [Any]:
        return array.filter { element in
            guard let dict = element as? [String: Any] else { return true }
            if let excludingID, let id = dict["id"] as? String, id == excludingID {
                return false
            }
            if let taskStatus = (dict["status"] as? String)?.lowercased(),
               finishedStatuses.contains(taskStatus) {
                return false
            }
            return true
        }.count
    case let dict as [String: Any]:
        return dict.count
    case let number as NSNumber:
        return number.intValue
    default:
        return nil
    }
}

/// Detail line shown while the prompt is idle but background work continues.
func backgroundDetail(count: Int) -> String {
    return count == 1
        ? "1 background task running"
        : "\(count) background tasks running"
}

// MARK: - Stored background-task count
//
// idle_prompt payloads carry no background_tasks (verified on 2.1.201),
// so the last count seen by Stop/StopFailure/SubagentStop is stored IN
// iTerm2 (RAM only, alongside the rest of the session's tab status;
// nothing touches the filesystem) via set-status --background-tasks,
// and read back here. cc-status runs once per hook event and keeps no
// state of its own.

/// Ask iTerm2 for the stored count. 0 when unavailable for any reason
/// (no stored value, session gone, it2 failed): the safe default, since
/// it just restores the pre-background-awareness behavior.
func storedBackgroundTaskCount(it2SessionID: String) -> Int {
    let it2 = resolveIt2()
    let process = Process()
    process.executableURL = it2.executable
    process.arguments = it2.leadingArgs + ["session", "get-background-tasks", "-s", it2SessionID]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return 0
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let output = String(data: data, encoding: .utf8),
          let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return 0
    }
    return max(0, count)
}

// MARK: - Detail formatting

/// Collapse all whitespace runs to single spaces and truncate to ~180 chars so
/// the toolbelt has room to wrap to three lines.
func condense(_ s: String, limit: Int = 180) -> String {
    let collapsed = s.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    if collapsed.count <= limit {
        return collapsed
    }
    let end = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
    return String(collapsed[..<end]) + "\u{2026}"
}

/// "Allow <tool>: <key field>?" for a PermissionRequest payload.
func permissionDetail(_ json: [String: Any]) -> String? {
    guard let toolName = json["tool_name"] as? String else {
        return nil
    }
    let toolInput = (json["tool_input"] as? [String: Any]) ?? [:]
    // AskUserQuestion is not a permission to grant: it is a question posed to the
    // user. Show the question itself rather than the "Allow …?" framing.
    if toolName == "AskUserQuestion" {
        let questions = (toolInput["questions"] as? [[String: Any]]) ?? []
        let texts = questions.compactMap { $0["question"] as? String }
        if !texts.isEmpty {
            return condense(texts.joined(separator: " "))
        }
    }
    // ExitPlanMode asks the user to approve a plan, not to grant a permission, so
    // the "Allow …?" framing is wrong here too. The plan body is too long to show.
    if toolName == "ExitPlanMode" {
        return "Review proposed plan?"
    }
    return "Allow " + toolCallSummary(toolName: toolName, toolInput: toolInput) + "?"
}

/// One-line summary of a tool invocation, showing the most identifying field.
func toolCallSummary(toolName: String, toolInput: [String: Any]) -> String {
    switch toolName {
    case "Bash":
        let command = (toolInput["command"] as? String) ?? ""
        return condense("Bash: " + command)
    case "Read", "Edit", "Write", "MultiEdit":
        let path = (toolInput["file_path"] as? String) ?? ""
        return "\(toolName): \(shortPath(path))"
    case "NotebookEdit":
        let path = (toolInput["notebook_path"] as? String) ?? ""
        return "NotebookEdit: \(shortPath(path))"
    case "Grep":
        let pattern = (toolInput["pattern"] as? String) ?? ""
        var s = "Grep \u{201C}\(pattern)\u{201D}"
        if let glob = toolInput["glob"] as? String, !glob.isEmpty {
            s += " in \(glob)"
        } else if let path = toolInput["path"] as? String, !path.isEmpty {
            s += " in \(shortPath(path))"
        }
        return s
    case "Glob":
        let pattern = (toolInput["pattern"] as? String) ?? ""
        return "Glob: \(pattern)"
    case "Agent", "Task":
        let desc = (toolInput["description"] as? String) ?? ""
        return "\(toolName): \(desc)"
    case "WebFetch":
        let url = (toolInput["url"] as? String) ?? ""
        return "WebFetch: \(shortURL(url))"
    case "WebSearch":
        let query = (toolInput["query"] as? String) ?? ""
        return "WebSearch: \(query)"
    default:
        // mcp__<server>__<tool> → <server>/<tool>
        if toolName.hasPrefix("mcp__") {
            let parts = toolName
                .dropFirst("mcp__".count)
                .components(separatedBy: "__")
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                return "\(parts[0])/\(parts.last!)"
            }
        }
        // Unknown tool: humanize its identifier so a raw internal keyword
        // (AskUserQuestion, TodoWrite, ExitPlanMode, …) never leaks into the UI.
        return humanize(toolName)
    }
}

/// Split a PascalCase/camelCase tool identifier into spaced words so unhandled
/// tools read naturally instead of leaking their raw keyword. Keeps acronym runs
/// together: "AskUserQuestion" -> "Ask User Question", "URLFetch" -> "URL Fetch".
func humanize(_ identifier: String) -> String {
    let chars = Array(identifier)
    var words: [String] = []
    var current = ""
    for (i, c) in chars.enumerated() {
        if c.isUppercase, !current.isEmpty {
            let prev = chars[i - 1]
            let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
            // Boundary after a lowercase/digit (askU…) or when an acronym run
            // gives way to a new word (URLFetch -> URL | Fetch).
            if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextIsLower) {
                words.append(current)
                current = ""
            }
        }
        current.append(c)
    }
    if !current.isEmpty {
        words.append(current)
    }
    return words.isEmpty ? identifier : words.joined(separator: " ")
}

/// Shorten a long absolute path to `…/parent/file`. Leaves short paths alone.
func shortPath(_ p: String, limit: Int = 60) -> String {
    if p.count <= limit {
        return p
    }
    let url = URL(fileURLWithPath: p)
    let file = url.lastPathComponent
    let parent = url.deletingLastPathComponent().lastPathComponent
    if parent.isEmpty {
        return "\u{2026}/\(file)"
    }
    return "\u{2026}/\(parent)/\(file)"
}

/// Shorten a URL to `host/<first-path-component>`.
func shortURL(_ raw: String) -> String {
    guard let url = URL(string: raw), let host = url.host else {
        return raw
    }
    let first = url.pathComponents.dropFirst().first ?? ""
    return first.isEmpty ? host : "\(host)/\(first)"
}

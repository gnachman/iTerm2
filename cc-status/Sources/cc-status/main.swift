import Foundation

// Driven by Claude Code hooks (~/.claude/settings.json). Codex CLI hooks (~/.codex/hooks.json)
// send the same payload shape, so one binary serves both; the hook configuration passes
// --agent codex to say which (see Agent).
//
// The entry point. The work is split across Addressing.swift (which session), HookEvent.swift
// (what to say about it) and It2Runner.swift (saying it); what stays here is main() plus the
// helpers that turn a hook payload into detail text and read back what iTerm2 holds.

func main() {
    let environment = ProcessInfo.processInfo.environment
    let agent = Agent(arguments: CommandLine.arguments)
    guard let event = readHookEvent() else {
        return
    }
    guard let address = resolveAddress(environment) else {
        return
    }
    guard let update = statusUpdate(forEvent: event.name, json: event.json, address: address, agent: agent),
          !update.isEmpty else {
        // Nothing to say. This happens on a Codex SubagentStop that leaves work
        // running: the decrement already stored the new count and the display is
        // deliberately unchanged, so there is no reason to spend another round
        // trip on a set-status carrying only an address.
        return
    }
    It2Runner(address: address, eventName: event.name, agent: agent).send(update)
}

// MARK: - Agent tty

/// Path of the terminal the agent is running in, or nil when there is none.
/// Codex 0.155+ starts hooks with setsid (openai/codex#43876), so the hook has
/// no controlling terminal of its own; the nearest ancestor that still has one
/// is the agent.
func agentTTYPath() -> String? {
    if let own = FileHandle(forWritingAtPath: "/dev/tty") {
        own.closeFile()
        return "/dev/tty"
    }
    var pid = getppid()
    while pid > 1 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        let dev = info.kp_eproc.e_tdev
        if dev != -1, let name = devname(dev, S_IFCHR) {
            return "/dev/" + String(cString: name)
        }
        pid = info.kp_eproc.e_ppid
    }
    return nil
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
// idle_prompt payloads carry no background_tasks (verified on 2.1.201), so the last count seen by
// Stop/StopFailure/SubagentStop is stored IN iTerm2 (RAM only, alongside the rest of the
// session's tab status; nothing touches the filesystem) via set-status --background-tasks, and
// read back here. iTerm2 also uses that count itself, to hold an expiring status back while
// background work is outstanding. cc-status runs once per hook event and keeps no state of its
// own.

/// Trimmed stdout of an it2 subcommand, or nil if it failed. Always quiet: these reads happen
/// mid-turn and a failure is not worth a word; each caller has a safe default instead.
func quietIt2Output(_ arguments: [String]) -> String? {
    guard let result = runIt2(arguments + ["--quiet-if-unresolved"]), result.status == 0 else {
        return nil
    }
    return result.stdout
}

/// Ask iTerm2 for the stored count. 0 when unavailable for any reason
/// (no stored value, session gone, it2 failed): the safe default, since
/// it just restores the pre-background-awareness behavior.
func storedBackgroundTaskCount(addressArgs: [String]) -> Int {
    guard let output = quietIt2Output(["session", "get-background-tasks"] + addressArgs),
          let count = Int(output) else {
        return 0
    }
    return max(0, count)
}

/// Adds to the stored background-task count and returns the status as it stands afterwards, or
/// nil if the call failed or its answer could not be read. One it2 round trip, and atomic: iTerm2
/// applies the delta where the count lives, so two hooks changing it at once cannot lose one.
func changeBackgroundTaskCount(by delta: Int, addressArgs: [String]) -> CurrentStatus? {
    guard let output = quietIt2Output(["set-status"] + addressArgs
                                      + optionArgs("--background-tasks-delta", String(delta))
                                      + ["--json"]) else {
        return nil
    }
    return CurrentStatus(json: output)
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
    case "apply_patch":
        // Codex CLI's file edit. tool_input is the whole patch; show the files.
        let patch = (toolInput["patch"] as? String) ?? (toolInput["input"] as? String) ?? ""
        let files = applyPatchFiles(patch)
        if files.isEmpty {
            return "Edit"
        }
        return condense("Edit: " + files.map { shortPath($0) }.joined(separator: ", "))
    case "update_plan":
        return "Update plan"
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

/// Files named in the "*** Update/Add/Delete File:" headers of an apply_patch.
func applyPatchFiles(_ patch: String) -> [String] {
    var files: [String] = []
    for line in patch.split(separator: "\n", omittingEmptySubsequences: true) {
        for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] {
            if line.hasPrefix(prefix) {
                let path = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty, !files.contains(path) {
                    files.append(path)
                }
            }
        }
    }
    return files
}

/// Split a PascalCase/camelCase tool identifier into spaced words so unhandled
/// tools read naturally instead of leaking their raw keyword. Keeps acronym runs
/// together: "AskUserQuestion" -> "Ask User Question", "URLFetch" -> "URL Fetch".
func humanize(_ identifier: String) -> String {
    // Codex names its tools in snake_case, which the pass below cannot see:
    // split there first so "read_file" reads as "Read File".
    if identifier.contains("_") {
        let words = identifier.split(separator: "_").map { part -> String in
            let word = humanize(String(part))
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        return words.isEmpty ? identifier : words.joined(separator: " ")
    }
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

// Runs last, and is the only top-level statement in the package: SPM allows those in main.swift
// alone, which is why the other three files hold declarations only.
main()

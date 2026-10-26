import Foundation

// Turning a hook payload into the detail text the Session Status tool shows, and reading the
// background-task list out of one.
enum AgentHookDetail {
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
    static func backgroundTaskCount(_ json: [String: Any], excludingID: String? = nil) -> Int? {
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
    static func backgroundDetail(count: Int) -> String {
        return count == 1
            ? "1 background task running"
            : "\(count) background tasks running"
    }

    /// The turn's final message, condensed for the detail line, or "" when the
    /// payload has none: the detail is cleared rather than left stale.
    static func lastMessageDetail(_ json: [String: Any]) -> String {
        return (json["last_assistant_message"] as? String).map { condense($0) } ?? ""
    }

    /// Collapse all whitespace runs to single spaces and truncate to ~180 chars so
    /// the toolbelt has room to wrap to three lines.
    static func condense(_ s: String, limit: Int = 180) -> String {
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
    static func permissionDetail(_ json: [String: Any]) -> String? {
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
    static func toolCallSummary(toolName: String, toolInput: [String: Any]) -> String {
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
    static func applyPatchFiles(_ patch: String) -> [String] {
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
    static func humanize(_ identifier: String) -> String {
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
    static func shortPath(_ p: String, limit: Int = 60) -> String {
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
    static func shortURL(_ raw: String) -> String {
        guard let url = URL(string: raw), let host = url.host else {
            return raw
        }
        let first = url.pathComponents.dropFirst().first ?? ""
        return first.isEmpty ? host : "\(host)/\(first)"
    }
}

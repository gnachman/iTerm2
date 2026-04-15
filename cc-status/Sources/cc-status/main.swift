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
let status: String
let dotColor: String
let textColor: String
// nil = don't touch detail; non-nil (including "") = send --detail through.
var detail: String? = nil

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
        status = "idle"
        dotColor = "#00d75f"
        textColor = "#888888"
        // Leave detail alone so Stop's last_assistant_message survives the nudge.
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
    status = "idle"
    dotColor = "#00d75f"
    textColor = "#888888"
    if let message = json["last_assistant_message"] as? String {
        detail = condense(message)
    } else {
        detail = ""
    }
case "StopFailure", "SessionStart", "SessionEnd":
    status = "idle"
    dotColor = "#00d75f"
    textColor = "#888888"
    detail = ""  // session boundary — wipe stale detail
default:
    exit(0)
}

// Build and run it2 invocation.
var args = [
    "it2", "set-status",
    "--session", sessionID,
    "--status", status,
    "--dot-color", dotColor,
    "--text-color", textColor,
]
// Pass --detail only when cc-status has an opinion; empty string explicitly clears.
if let detail = detail {
    args.append(contentsOf: ["--detail", detail])
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = args
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
    return "Allow " + toolCallSummary(toolName: toolName, toolInput: toolInput) + "?"
}

/// One-line summary of a tool invocation, showing the most identifying field.
func toolCallSummary(toolName: String, toolInput: [String: Any]) -> String {
    switch toolName {
    case "Bash":
        let command = (toolInput["command"] as? String) ?? ""
        return condense("Bash: " + command)
    case "Read", "Edit", "Write":
        let path = (toolInput["file_path"] as? String) ?? ""
        return "\(toolName): \(shortPath(path))"
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
    case "Agent":
        let desc = (toolInput["description"] as? String) ?? ""
        return "Agent: \(desc)"
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
        return toolName
    }
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

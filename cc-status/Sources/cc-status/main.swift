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

// Map hook event to status and colors.
let status: String
let dotColor: String
let textColor: String
switch eventName {
case "PreToolUse", "PostToolUse", "UserPromptSubmit":
    status = "working"
    dotColor = "#ff9500"
    textColor = "#ff9500"
case "PermissionRequest", "Notification":
    status = "waiting"
    dotColor = "#5f87ff"
    textColor = "#5f87ff"
case "Stop", "StopFailure", "SessionStart", "SessionEnd":
    status = "idle"
    dotColor = "#00d75f"
    textColor = "#888888"
default:
    exit(0)
}

// Run: it2 set-status --session <id> --status <status> --dot-color <color> --text-color <color>
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [
    "it2", "set-status",
    "--session", sessionID,
    "--status", status,
    "--dot-color", dotColor,
    "--text-color", textColor
]
try? process.run()
process.waitUntilExit()

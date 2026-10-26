import Foundation

/// Handles authentication with iTerm2's API server.
enum CookieAuth {
    /// Get cookie and key credentials for the WebSocket handshake.
    /// Checks environment variables first, falls back to AppleScript.
    static func getCredentials() -> (cookie: String?, key: String?) {
        // Fast path: cookie from environment
        if let cookie = ProcessInfo.processInfo.environment["ITERM2_COOKIE"] {
            let key = ProcessInfo.processInfo.environment["ITERM2_KEY"]
            return (cookie, key)
        }

        // Fallback: request single-use cookie via AppleScript
        return runAppleScript(reusable: false)
    }

    /// Request a reusable cookie via AppleScript.
    /// Shows an announcement in the originating session and waits for user approval.
    static func requestReusableCookie() -> (cookie: String?, key: String?) {
        return runAppleScript(reusable: true)
    }

    /// Request a single-use cookie via AppleScript (ignoring environment).
    static func requestCookie() -> (cookie: String?, key: String?) {
        return runAppleScript(reusable: false)
    }

    // MARK: - Private

    /// The AppleScript target application for the current process.
    ///
    /// Prefers the advertiser this process actually connected to (see
    /// SocketConnection.chosenAdvertisedRecord) over the inherited IT2_APP_PATH, because the
    /// variable is frozen into a tmux server's environment by whichever tab started it, days and
    /// several builds ago, while the record is published by an iTerm2 attached right now. Asking
    /// the wrong one yields a cookie this instance rejects.
    private static var appTarget: String {
        return appTarget(recordAppPath: SocketConnection.chosenAdvertisedRecord?["app"],
                         inheritedAppPath: ProcessInfo.processInfo.environment["IT2_APP_PATH"])
    }

    /// Pure form of the rule above, so it can be tested without a tmux server or a live socket.
    /// Defaults to "iTerm2", which is correct whenever only one instance is running.
    static func appTarget(recordAppPath: String?, inheritedAppPath: String?) -> String {
        for candidate in [recordAppPath, inheritedAppPath] {
            if let candidate, !candidate.isEmpty {
                return "application \"\(candidate)\""
            }
        }
        return "application \"iTerm2\""
    }

    private static func runAppleScript(reusable: Bool) -> (cookie: String?, key: String?) {
        var params = "request cookie and key for app named \"it2\""
        if reusable {
            params += " reusable true"
            if let sessionId = ProcessInfo.processInfo.environment["ITERM_SESSION_ID"] {
                let escaped = sessionId.replacingOccurrences(of: "\"", with: "\\\"")
                params += " session id \"\(escaped)\""
            }
        }
        // A bare `tell` launches the app when it is not running. it2 runs from hooks that fire as
        // iTerm2 quits (e.g., Claude Code's SessionEnd), and relaunching it then can clobber the
        // saved window state during a logout or restart. When iTerm2 is not running the script
        // returns nothing, which is reported below as a failure to get credentials.
        let target = appTarget
        let script = "if \(target) is running then tell \(target) to \(params)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (nil, nil)
        }

        guard process.terminationStatus == 0 else {
            return (nil, nil)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return (nil, nil)
        }

        // Output format: "COOKIE KEY" separated by space
        let parts = output.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else {
            return (nil, nil)
        }

        return (String(parts[0]), String(parts[1]))
    }
}

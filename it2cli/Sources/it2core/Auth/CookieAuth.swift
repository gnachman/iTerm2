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

    /// The AppleScript target application. Defaults to "iTerm2" but can be
    /// overridden with IT2_APP_PATH to target a specific instance (e.g. a
    /// path like "/Applications/iTerm2-nightly.app").
    private static var appTarget: String {
        if let path = ProcessInfo.processInfo.environment["IT2_APP_PATH"] {
            return "application \"\(path)\""
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
        let script = "tell \(appTarget) to \(params)"

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

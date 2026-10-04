//
//  ClaudeCodeRemoteConfigDirResolver.swift
//  iTerm2SharedARC
//
//  Finds CLAUDE_CONFIG_DIR on a host reached through SSH Integration, the remote counterpart of
//  ClaudeCodeConfigDirResolver's login-shell source.
//
//  The variable usually lives in the user's rc files, so the host's login shell (as reported by
//  getshell) is run interactive and, where the shell takes the flag, login, the way iTerm2 starts
//  it. It prints /usr/bin/env rather than the variable itself, so nothing depends on the shell's
//  syntax (tcsh, for one, errors on an unset variable), and the same parser as the local lookup
//  reads it.
//
//  rc files print banners, motd and escape codes, so the env output is fenced by two markers made
//  from a random sentinel, and only what lies between them counts. A missing end marker means the
//  output was cut short, which is a failure, not "unset".
//
//  Never anything from the profile: a profile whose command is a custom command must not have that
//  command run again for this or any other purpose. Only the login shell is used.
//
//  Pure apart from the injected runner and timer, so ModernTests can play a scripted framer.
//

import Foundation

enum ClaudeCodeRemoteConfigDirResolver {
    struct Dependencies {
        /// Runs a command line through /bin/sh -c on the remote host and delivers its output and
        /// exit status.
        let run: (_ commandLine: String, _ completion: @escaping (Data, Int32) -> Void) -> Void
        /// Calls `block` after `seconds`.
        let after: (_ seconds: TimeInterval, _ block: @escaping () -> Void) -> Void
        let makeSentinel: () -> String
    }

    /// Matches the local lookup's bound: long enough for a slow rc file, short enough that an rc
    /// file waiting for input does not hold the install forever.
    static let deadline: TimeInterval = 20

    static func startMarker(_ sentinel: String) -> String {
        return "iTerm2-claude-config-dir-begin-\(sentinel)"
    }

    static func endMarker(_ sentinel: String) -> String {
        return "iTerm2-claude-config-dir-end-\(sentinel)"
    }

    static func commandLine(shell: String, sentinel: String) -> String {
        // Separate flags: not every shell accepts them bundled. The same rule as the local lookup
        // for which shells take -l at all.
        let flags = ClaudeCodeConfigDirResolver.loginFlagSupported(shellPath: shell) ? "-i -l -c" : "-i -c"
        // The markers are made of letters, digits and dashes, so they need no quoting inside the
        // single-quoted script.
        let script = "echo \(startMarker(sentinel)); /usr/bin/env; echo \(endMarker(sentinel))"
        return "\(shellQuote(shell)) \(flags) \(shellQuote(script))"
    }

    /// The configuration directory the output reports, or nil when the output does not contain a
    /// complete answer. Unset or empty means Claude Code's default under `home`.
    static func directory(fromOutput output: String, sentinel: String, home: String) -> String? {
        let lines = output.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        }
        let start = startMarker(sentinel)
        let end = endMarker(sentinel)
        guard let first = lines.firstIndex(where: { $0.hasSuffix(start) }),
              let last = lines[(first + 1)...].firstIndex(where: { $0.hasSuffix(end) }) else {
            return nil
        }
        let environment = lines[(first + 1)..<last].joined(separator: "\n")
        let homeDirectory = trimmingTrailingSlashes(home)
        guard let value = ClaudeCodeOnboarding.parseCLAUDE_CONFIG_DIR(from: environment), !value.isEmpty else {
            return homeDirectory + "/.claude"
        }
        if value == "~" {
            return homeDirectory
        }
        if value.hasPrefix("~/") {
            return homeDirectory + value.dropFirst()
        }
        return value
    }

    /// Delivers the directory, or nil when the lookup failed: no shell or home to work with, the
    /// command did not produce a complete answer, or the deadline passed. The caller must not
    /// guess on nil. Called exactly once, on whatever queue `run` and `after` call back on.
    static func resolve(shell: String?,
                        home: String?,
                        dependencies: Dependencies,
                        completion: @escaping (String?) -> Void) {
        guard let shell, !shell.isEmpty, let home, !home.isEmpty else {
            RLog("Remote CLAUDE_CONFIG_DIR lookup failed: the remote login shell or home is unknown")
            completion(nil)
            return
        }
        let sentinel = dependencies.makeSentinel()
        var done = false
        let finish = { (result: String?) in
            guard !done else {
                return
            }
            done = true
            completion(result)
        }
        dependencies.after(deadline) {
            if !done {
                RLog("Remote CLAUDE_CONFIG_DIR lookup failed: no answer within \(deadline) seconds")
            }
            finish(nil)
        }
        dependencies.run(commandLine(shell: shell, sentinel: sentinel)) { data, status in
            let output = String(decoding: data, as: UTF8.self)
            let result = directory(fromOutput: output, sentinel: sentinel, home: home)
            if result == nil {
                RLog("Remote CLAUDE_CONFIG_DIR lookup failed: incomplete output, status \(status)")
            }
            DLog("Remote CLAUDE_CONFIG_DIR lookup status=\(status) result=\(result ?? "(failed)")")
            finish(result)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func trimmingTrailingSlashes(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}

//
//  ClaudeInteractivity.swift
//  iTerm2SharedARC
//
//  Decides whether a claude process that appeared in a session is an interactive Claude Code
//  session, the only kind worth offering the Claude Code integration for. Pure logic, so it can
//  be tested without a session; PTYSession+ClaudeInteractivity gathers the inputs.
//

import Foundation

// What claude's command line says about the run.
enum ClaudeInvocation: Equatable {
    // A one-off run that never becomes a session: -p, --version, a management subcommand, and so on.
    case nonInteractive
    // Nothing on the command line rules out a session. That includes a bare `claude` and
    // `claude "fix the bug"`, which starts a session with a prompt, but also anything we don't
    // recognize, so it isn't proof of a session.
    case undetermined

    // Flags that make claude exit without starting a session in this terminal.
    private static let nonInteractiveFlags: Set<String> = [
        "-p", "--print",
        "-v", "--version",
        "-h", "--help",
        "--bg", "--background",
    ]

    // Subcommands, as of Claude Code 2.1.289 plus a few older ones. None starts a session, even the
    // ones that prompt, so none deserves the offer. `attach` is missing on purpose: it opens a
    // background session in this terminal.
    private static let subcommands: Set<String> = [
        "agents", "auth", "auto-mode", "config", "doctor", "gateway", "import", "install", "kill",
        "logs", "mcp", "migrate-installer", "plugin", "plugins", "purge", "respawn", "rm",
        "setup-token", "stop", "ultrareview", "update", "upgrade",
    ]

    // Classifies the claude process `pid` from its command line as `dataSource` reports it.
    static func classify(processID pid: pid_t, dataSource: ProcessDataSource) -> ClaudeInvocation {
        // Only raw argv will do. Without exact boundaries, a quoted prompt splits into words that
        // can look like a subcommand or flag: `claude "update the readme"` would read as
        // `claude update ...` and be declined for good. Escaped arguments hide flags instead:
        // `--print=x` would arrive as `"--print=x"`. Leave such runs to the tty mode check.
        guard let argv = dataSource.rawCommandLineArguments?(forProcess: pid) else {
            DLog("No raw argv for claude pid \(pid); not classifying its command line")
            return .undetermined
        }
        let invocation = classify(arguments: Array(argv.dropFirst()))
        DLog("claude pid \(pid) argv \(argv) is \(invocation)")
        return invocation
    }

    // `arguments` excludes argv[0].
    static func classify(arguments: [String]) -> ClaudeInvocation {
        // A subcommand only counts as the first argument. A word after an option may be that
        // option's value, and values can be anything: `claude --add-dir config` or
        // `claude --resume update` are sessions. Rather than track which options take values,
        // leave those runs to the tty mode check, since this answer is final.
        if let first = arguments.first, subcommands.contains(first) {
            return .nonInteractive
        }
        for argument in arguments {
            if argument == "--" {
                // Everything after this is the prompt.
                return .undetermined
            }
            if argument.hasPrefix("-") {
                // An attached value (--print=x) still names the flag.
                let flag = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? argument
                if nonInteractiveFlags.contains(flag) {
                    return .nonInteractive
                }
            }
        }
        return .undetermined
    }
}

enum ClaudeProcessLocator {
    // Walks up from the foreground job to the login shell and returns the outermost claude, the
    // one closest to the shell: that's the command the user ran. Interactive claude starts its
    // own children in the foreground (hooks, statusLine commands, MCP servers, Bash tool calls),
    // and any of them may run claude too, e.g. `claude --version`. Taking the innermost would
    // judge the session by that child.
    static func outermostClaude(startingAt start: iTermProcessInfo?) -> iTermProcessInfo? {
        var outermost: iTermProcessInfo?
        var current = start
        var depth = 0
        while let info = current, depth < 64 {
            if let title = info.argv0 ?? info.name {
                // The same boundary as the foreground job ancestry GlobalJobMonitor watches.
                if title.hasPrefix("-") || title.hasPrefix("iTermServer") {
                    break
                }
                if (title as NSString).lastPathComponent.lowercased() == "claude" {
                    outermost = info
                }
            }
            current = info.parent
            depth += 1
        }
        return outermost
    }
}

// The terminal mode of the tty claude runs on. Interactive Claude Code puts its tty in raw mode
// (ICANON off) to read single keys; a non-interactive run leaves it canonical.
enum ClaudeTTYMode: Equatable {
    case raw
    case canonical
    // The tty can't be read from here, e.g. a tmux server too old to run the query.
    case unknown

    init(icanon: Bool) {
        self = icanon ? .canonical : .raw
    }

    // Parses `stty -a` output, which has the same words on macOS and Linux: "icanon" when
    // canonical, "-icanon" when not.
    init(sttyOutput: String) {
        let words = Set(sttyOutput.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        if words.contains("-icanon") {
            self = .raw
        } else if words.contains("icanon") {
            self = .canonical
        } else {
            self = .unknown
        }
    }
}

// One sample of claude's tty.
struct ClaudeTTYReading: Equatable {
    var mode: ClaudeTTYMode
    // Whether claude's process group had the tty's foreground when the mode was read. Every common
    // shell puts the tty in raw mode at its prompt, so a raw reading only means something when
    // claude has the foreground. Asked about claude rather than about a shell, because the shell
    // drawing the prompt may be nested anywhere below the login shell. nil when that couldn't be
    // told.
    var claudeHasForeground: Bool?

    static let unknown = ClaudeTTYReading(mode: .unknown, claudeHasForeground: nil)

    // Whether claude's process group is the tty's foreground one, given each as known (0 or nil
    // for unknown). A wrapper script that runs claude shares claude's group, so it counts too.
    static func claudeHasForeground(foregroundGroup: pid_t?, claudeGroup: pid_t?) -> Bool? {
        guard let foregroundGroup, foregroundGroup > 0, let claudeGroup, claudeGroup > 0 else {
            return nil
        }
        return foregroundGroup == claudeGroup
    }
}

enum ClaudeInteractivityPolicy {
    enum Decision: Equatable {
        case offer
        // Not a session. Stop checking until claude runs again.
        case decline
        // Check again after this many seconds.
        case checkAgain(after: TimeInterval)
    }

    // How often to check while undecided.
    static let checkInterval: TimeInterval = 0.5

    // Raw mode only counts once claude has been running this long. When a reading can't say who
    // has the foreground, a raw one this early could still be the shell's line editor at the
    // prompt: over SSH Integration the mode is framer's last report, and framer checks the login
    // shell's tty once a second and whenever it writes.
    static let settleTime: TimeInterval = 1.5

    // When the tty can't be read, offer if claude is still running after this long. Short-lived
    // runs like `claude plugin list` finish well within it.
    static let fallbackDwellTime: TimeInterval = 3

    // A claude that has kept its tty canonical this long isn't going to start a session.
    static let giveUpTime: TimeInterval = 15

    // `elapsed` is how long claude has been running in the session.
    static func decide(invocation: ClaudeInvocation,
                       reading: ClaudeTTYReading,
                       elapsed: TimeInterval) -> Decision {
        if invocation == .nonInteractive {
            return .decline
        }
        if reading.claudeHasForeground == false {
            // Usually a shell's prompt, read after claude exited (before GlobalJobMonitor noticed)
            // or before it started (a stale report). It says nothing about claude, so it can't
            // lead to an offer. But it can also hold for the whole run, e.g. for a claude without
            // the terminal as its controlling one. Give up eventually rather than poll until it
            // exits.
            if elapsed >= giveUpTime {
                return .decline
            }
            return .checkAgain(after: checkInterval)
        }
        switch reading.mode {
        case .raw:
            if elapsed >= settleTime {
                return .offer
            }
        case .canonical:
            if elapsed >= giveUpTime {
                return .decline
            }
        case .unknown:
            if elapsed >= fallbackDwellTime {
                return .offer
            }
        }
        return .checkAgain(after: checkInterval)
    }
}

import Darwin
import Foundation

// Telling a one-off agent run from an interactive one, so the hook does not record a conversation
// nobody could usefully resume.

/// Whether the agent whose hook is running is a one-off, non-interactive run, such as
/// `claude -p` or `codex exec` called from a script, or from a Bash tool call inside an
/// interactive agent. Such runs fire SessionStart like any other, and recording their conversation
/// would replace the one the user is actually having in the session.
enum AgentRunMode: Equatable {
    case headless
    /// Interactive, or nothing said otherwise.
    case undetermined

    /// Classifies a run from its arguments, without argv[0].
    static func classify(agent: AgentKind, arguments: [String]) -> AgentRunMode {
        // Everything after "--" is a prompt.
        let options = arguments.prefix { $0 != "--" }
        switch agent {
        case .claude:
            for argument in options where argument.hasPrefix("-") {
                // An attached value (--print=x) still names the flag.
                let flag = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? argument
                if flag == "-p" || flag == "--print" {
                    return .headless
                }
                // Short flags can be combined, as in -cp (continue, print).
                if !flag.hasPrefix("--") && flag.count > 2 && flag.dropFirst().contains("p") {
                    return .headless
                }
            }
            return .undetermined
        case .codex:
            // `codex exec`, or its alias `e`, which only counts as the first argument since
            // anywhere else it may be an option's value.
            if options.first == "e" || options.contains("exec") {
                return .headless
            }
            return .undetermined
        }
    }

    /// What the hook needs to know about a process: its parent and its arguments.
    struct ProcessFacts {
        var parent: pid_t
        var argv: [String]
    }

    /// The shells an agent may run its hook command through.
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]

    /// Classifies the agent that ran this hook, found by walking up from `start` (the hook's
    /// parent) past any shell the hook command ran in. Undetermined when it cannot be found.
    static func ofAgent(_ agent: AgentKind,
                        startingAt start: pid_t = getppid(),
                        facts: (pid_t) -> ProcessFacts? = processFacts) -> AgentRunMode {
        var pid = start
        for _ in 0..<4 {
            guard pid > 1, let info = facts(pid), let argv0 = info.argv.first else {
                return .undetermined
            }
            let name = (argv0 as NSString).lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if !shells.contains(name) {
                return classify(agent: agent, arguments: Array(info.argv.dropFirst()))
            }
            pid = info.parent
        }
        return .undetermined
    }

    /// Reads a process's parent and arguments from the kernel. nil when it cannot.
    static func processFacts(_ pid: pid_t) -> ProcessFacts? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var procMIB: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&procMIB, 4, &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        let parent = info.kp_eproc.e_ppid

        var argsMIB: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var length = 0
        guard sysctl(&argsMIB, 3, nil, &length, nil, 0) == 0, length > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&argsMIB, 3, &buffer, &length, nil, 0) == 0 else {
            return nil
        }
        // Layout: argc (Int32), the executable path, NUL padding, then argc NUL-terminated
        // arguments.
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < length && buffer[index] != 0 {
            index += 1
        }
        while index < length && buffer[index] == 0 {
            index += 1
        }
        var argv = [String]()
        while argv.count < Int(argc) && index < length {
            let start = index
            while index < length && buffer[index] != 0 {
                index += 1
            }
            argv.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return ProcessFacts(parent: parent, argv: argv)
    }
}

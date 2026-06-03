import Foundation

/// Hard rules for an agent that types shell commands into a terminal.
/// Deterministic, no LLM involvement. Wire up by assigning the method
/// reference to the classifier's hook:
///
///     let rules = TerminalHardRules()
///     classifier.hardRules = rules.evaluate
///
/// `evaluate` consumes one submitted shell line — i.e. the bytes buffered
/// between an Enter keystroke and the prior one. It returns:
///
///   - `.allow` for clearly safe read-only commands,
///   - `.block` for categorically destructive patterns,
///   - `.needsManualApproval` for medium-risk commands,
///   - `nil` to fall through to the LLM classifier.
///
/// Limitations: this is pattern-based, not a real shell parser. Variable
/// substitution and quoting tricks (`X=rm; $X -rf /`) bypass it. For
/// evasion-resistance, run the line through a real shell tokenizer first
/// and pass the canonicalized form to evaluate.
///
/// The public sets are `var` so callers can extend them at runtime.
final class TerminalHardRules {

    /// Commands whose every invocation is considered safe regardless of flags.
    /// Read-only by design — these don't modify filesystem, processes, or network.
    var hardAllowCommands: Set<String> = [
        "ls", "pwd", "cd", "echo", "printf",
        "cat", "head", "tail", "wc", "nl", "tac", "rev",
        "stat", "file", "type", "which", "command",
        "whoami", "id", "groups", "hostname", "uname", "date",
        "df", "du", "free", "uptime", "nproc",
        "basename", "dirname", "realpath", "readlink",
        "cut", "tr", "sort", "uniq", "comm", "diff", "cmp",
        "grep", "egrep", "fgrep", "rg", "ag",
        "true", "false", "test", "expr",
    ]

    /// First-token privilege-escalation commands. Categorical deny.
    var privilegeEscalation: Set<String> = [
        "sudo", "su", "doas", "pkexec",
    ]

    /// First-token commands whose flags determine whether they're destructive.
    /// Defaulted to manual approval so a human sees the full invocation.
    var manualApprovalCommands: Set<String> = [
        "rm", "mv", "cp", "chmod", "chown", "chgrp",
        "ln", "mkdir", "rmdir", "touch",
        "make", "cmake", "ninja",
        "pip", "pip3", "npm", "yarn", "pnpm", "bun", "cargo", "go",
        "brew", "apt", "dnf", "yum", "pacman",
        "docker", "podman", "kubectl",
        "ssh", "scp", "rsync",
        "curl", "wget",
        "kill", "killall", "pkill",
    ]

    /// Substrings that categorically block the line. Conservative — only
    /// patterns with no plausible safe use. Checked before first-token
    /// rules so `rm -rf /` doesn't get demoted by the `rm` token rule.
    var hardDenySubstrings: [String] = [
        "rm -rf /",
        "rm -rf /*",
        "rm -rf ~",
        "rm -rf $HOME",
        "rm -rf \"$HOME\"",
        ":(){:|:&};:",
        "mkfs.",
        "dd of=/dev/",
        "chmod -R 777 /",
        "> /dev/sd",
        "> /dev/nvme",
    ]

    /// Substrings that send the line to manual approval regardless of the
    /// first token. Pipe-to-shell and device redirects are the canonical
    /// examples — the destructive part is the structure, not the command.
    var manualApprovalSubstrings: [String] = [
        "| sh", "|sh ", "|sh\n",
        "| bash", "|bash ", "|bash\n",
        "| zsh", "|zsh ",
        "> /dev/",
        " | sudo",
    ]

    /// Git subcommands considered read-only. `git` itself is gated through
    /// a per-subcommand check rather than blanket manualApprovalCommands —
    /// most agent-issued git commands are status/log/diff and shouldn't
    /// pay an LLM round-trip.
    var gitReadOnlySubcommands: Set<String> = [
        "status", "log", "diff", "show", "blame",
        "ls-files", "ls-tree", "rev-parse", "describe",
        "branch", "tag", "remote", "config",
    ]

    func evaluate(_ action: TranscriptEntry) -> ClassifierDecision? {
        guard case .toolCall(_, let raw) = action else { return nil }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return .allow }

        // Terminal escape sequences in agent-typed input could rewrite
        // already-displayed output, toggle alt-screen, or write to the
        // clipboard via OSC 52. No legitimate use in a shell line.
        if line.unicodeScalars.contains(where: { $0.value == 0x1B }) {
            return .block(reason: "input contains a terminal escape sequence")
        }

        // History expansion at line start runs a previous command we have
        // no way to inspect statically.
        if line.hasPrefix("!") {
            return .needsManualApproval(
                reason: "history expansion (`!`) at line start runs a previous command that cannot be inspected statically"
            )
        }

        for pattern in hardDenySubstrings {
            if line.contains(pattern) {
                return .block(reason: "matches hard-deny pattern: `\(pattern)`")
            }
        }

        for pattern in manualApprovalSubstrings {
            if line.contains(pattern) {
                return .needsManualApproval(
                    reason: "line contains `\(pattern)` — review before allowing"
                )
            }
        }

        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let first = tokens.first else { return .allow }
        // A leading backslash defeats shell aliases (`\rm`); strip it so
        // the token-level rule still applies.
        let cmd = first.hasPrefix("\\") ? String(first.dropFirst()) : String(first)

        if privilegeEscalation.contains(cmd) {
            return .block(reason: "privilege escalation: `\(cmd)`")
        }

        if cmd == "git" {
            let sub = tokens.dropFirst().first.map(String.init) ?? ""
            if gitReadOnlySubcommands.contains(sub) {
                return .allow
            }
            return .needsManualApproval(
                reason: sub.isEmpty
                    ? "`git` with no subcommand"
                    : "`git \(sub)` may modify repository state"
            )
        }

        if cmd == "find" {
            // `find` is read-only unless asked to mutate. The flags below
            // are the destructive ones.
            let destructive = [" -delete", " -exec ", " -execdir ", " -ok ", " -okdir "]
            if destructive.contains(where: line.contains) {
                return .needsManualApproval(
                    reason: "`find` invoked with -delete/-exec/-ok can mutate the filesystem"
                )
            }
            return .allow
        }

        if hardAllowCommands.contains(cmd) {
            return .allow
        }

        if manualApprovalCommands.contains(cmd) {
            return .needsManualApproval(
                reason: "`\(cmd)` can have destructive effects depending on its arguments"
            )
        }

        return nil
    }
}

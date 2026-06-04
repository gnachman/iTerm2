import Foundation

/// Hard rules for an agent that types shell commands into a terminal.
/// Deterministic, no LLM involvement. Wire up by assigning the method
/// reference to the classifier's hook:
///
///     let rules = TerminalHardRules()
///     classifier.hardRules = rules.evaluate
///
/// `evaluate` consumes one submitted shell line (the bytes buffered between
/// an Enter keystroke and the prior one). It returns:
///
///   - `.allow` only for a line that is provably a simple, read-only
///     command: no command/process substitution, no parameter or arithmetic
///     expansion, no redirection, and every operator-separated segment is
///     itself read-only-allowable.
///   - `.block` for categorically destructive patterns.
///   - `.needsManualApproval` for medium-risk commands.
///   - `nil` to fall through to the LLM classifier for anything that cannot
///     be proven simple-read-only but is not categorically dangerous.
///
/// A small quote-aware scanner (see `scan`) tracks single-quote,
/// double-quote, and backslash state so operators and metacharacters are
/// only honored when unquoted. This is the shell tokenizer internalized: it
/// does not need to be a full parser, only conservative enough that anything
/// it cannot prove simple-read-only is never auto-allowed. When the line is
/// ambiguous (for example unbalanced quotes) it returns `nil`. The previous
/// version classified from the first token alone, so `ls && rm x` and
/// `cat secret > ~/.ssh/authorized_keys` auto-allowed; this closes that hole.
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

    /// Git subcommands that are read-only regardless of their arguments. `git`
    /// is gated per-subcommand rather than via blanket manualApprovalCommands
    /// because most agent-issued git commands are status/log/diff and should
    /// not pay an LLM round-trip.
    ///
    /// Deliberately excludes subcommands that only look read-only: `config`
    /// can write `.git/config` and arrange later arbitrary command execution
    /// (`git config core.pager '<cmd>'`, `alias.x '!<cmd>'`), and
    /// `branch`/`tag`/`remote` mutate repository state with the right flags.
    /// Those fall through to manual approval.
    var gitReadOnlySubcommands: Set<String> = [
        "status", "log", "diff", "show", "blame",
        "ls-files", "ls-tree", "rev-parse", "describe",
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

        // Categorical hard-deny wins over everything. These patterns have no
        // plausible safe use, so they are matched against the whole line.
        for pattern in hardDenySubstrings {
            if line.contains(pattern) {
                return .block(reason: "matches hard-deny pattern: `\(pattern)`")
            }
        }

        let scanned = scan(line)

        // Unbalanced quotes or a dangling escape mean we cannot reason about
        // the line. Never auto-allow it; defer to the LLM classifier.
        guard scanned.balanced else { return nil }

        // Classify every operator-separated segment and fold with precedence
        // block > needsManualApproval > defer(nil) > allow.
        var blockReason: String?
        var manualReason: String?
        var sawDefer = false
        for segment in scanned.segments {
            switch classifySegment(segment) {
            case .block(let reason):
                if blockReason == nil { blockReason = reason }
            case .needsManualApproval(let reason):
                if manualReason == nil { manualReason = reason }
            case .allow:
                break
            case .unparseable, .none:
                sawDefer = true
            }
        }

        // History expansion at line start runs a previous command we have no
        // way to inspect statically.
        if manualReason == nil && line.hasPrefix("!") {
            manualReason = "history expansion (`!`) at line start runs a previous command that cannot be inspected statically"
        }

        // Existing line-level manual-approval triggers (pipe-to-shell and the
        // like). Matched against the unquoted projection only, so the same
        // metacharacters appearing inside quotes do not false-positive.
        if manualReason == nil {
            for pattern in manualApprovalSubstrings {
                if scanned.unquotedProjection.contains(pattern) {
                    let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    manualReason = "line contains `\(trimmed)` and needs review before it runs"
                    break
                }
            }
        }

        if let blockReason {
            return .block(reason: blockReason)
        }
        if let manualReason {
            return .needsManualApproval(reason: manualReason)
        }
        if sawDefer {
            return nil
        }

        // Every segment is read-only. Only auto-allow when the structure is
        // also provably simple: no command/process substitution, no parameter
        // or arithmetic expansion, and no redirection. Anything else defers
        // to the LLM rather than auto-allowing.
        if scanned.hasSubstitution || scanned.hasExpansion || scanned.hasRedirection {
            return nil
        }
        return .allow
    }

    /// Decide a single operator-separated segment in isolation. Mirrors the
    /// first-token rules: privilege escalation blocks, git and find have their
    /// own read-only checks, hard-allow commands allow, manual-approval
    /// commands need review, and anything unknown returns nil to defer to the
    /// LLM. An empty segment (for example the gap in `a && b`) is allowable.
    private func classifySegment(_ rawSegment: String) -> ClassifierDecision? {
        let segment = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        if segment.isEmpty {
            return .allow
        }
        let tokens = segment.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let first = tokens.first else { return .allow }
        // A leading backslash defeats shell aliases (`\rm`); strip it so the
        // token-level rule still applies.
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
            // `find` is read-only unless asked to mutate. The flags below are
            // the destructive ones: -exec/-ok families run commands, and the
            // -fprint/-fprintf/-fls primaries create or truncate a named file
            // without any redirection operator.
            let destructive = [" -delete", " -exec ", " -execdir ", " -ok ", " -okdir ",
                               " -fprint ", " -fprintf ", " -fls "]
            if destructive.contains(where: segment.contains) {
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

    /// Result of the quote-aware scan of a single line.
    private struct ScanResult {
        /// The line split on unquoted shell operators (`|`, `&`, `;`, and
        /// newline). Empty and whitespace-only segments are kept; the caller
        /// trims them.
        var segments: [String]
        /// An unquoted command/process substitution or parameter/arithmetic
        /// expansion appears somewhere: `$(`, `${`, `$[`, a backtick, `<(`,
        /// or `>(`.
        var hasSubstitution: Bool
        /// A word-initial zsh `=cmd` expansion appears unquoted.
        var hasExpansion: Bool
        /// A redirection (`>`, `>>`, `<`, `2>`, `&>`, and so on) appears
        /// unquoted.
        var hasRedirection: Bool
        /// The line with quoted regions removed but unquoted operators kept.
        /// Used for the manual-approval substring backstop so it does not
        /// false-positive on quoted metacharacters.
        var unquotedProjection: String
        /// False if the line ended inside a quote or on a dangling backslash.
        var balanced: Bool
    }

    /// Walk the line tracking single-quote, double-quote, and backslash state
    /// so operators and metacharacters are only honored when unquoted. This is
    /// the internalized tokenizer described in the type comment. It is
    /// deliberately conservative: it does not parse the full grammar, only
    /// enough that anything it cannot prove simple-read-only is not allowed.
    /// Splitting more than necessary is safe (it only defers); failing to
    /// split would be unsafe, so unknown operators always break a segment.
    private func scan(_ line: String) -> ScanResult {
        var segments: [String] = []
        var current = ""
        var projection = ""
        var hasSubstitution = false
        var hasExpansion = false
        var hasRedirection = false
        var inSingle = false
        var inDouble = false
        var escaped = false
        var atWordStart = true

        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            if escaped {
                current.append(c)
                if !inSingle && !inDouble { projection.append(c) }
                escaped = false
                atWordStart = false
                i += 1
                continue
            }
            if c == "\\" && !inSingle {
                // Backslash escapes the next character outside single quotes.
                current.append(c)
                if !inDouble { projection.append(c) }
                escaped = true
                atWordStart = false
                i += 1
                continue
            }
            if inSingle {
                current.append(c)
                if c == "'" { inSingle = false }
                i += 1
                continue
            }
            if inDouble {
                // Command substitution stays active inside double quotes.
                if c == "`" {
                    hasSubstitution = true
                } else if c == "$", let n = next, n == "(" || n == "{" || n == "[" {
                    hasSubstitution = true
                }
                current.append(c)
                if c == "\"" { inDouble = false }
                i += 1
                continue
            }

            switch c {
            case "'":
                inSingle = true
                current.append(c)
                atWordStart = false
            case "\"":
                inDouble = true
                current.append(c)
                atWordStart = false
            case "`":
                hasSubstitution = true
                current.append(c)
                projection.append(c)
                atWordStart = false
            case "$":
                if let n = next, n == "(" || n == "{" || n == "[" {
                    hasSubstitution = true
                }
                current.append(c)
                projection.append(c)
                atWordStart = false
            case "<", ">":
                if let n = next, n == "(" {
                    // Process substitution: <( ... ) or >( ... ).
                    hasSubstitution = true
                } else {
                    hasRedirection = true
                }
                current.append(c)
                projection.append(c)
                atWordStart = false
            case "=":
                // zsh word-initial `=cmd` expands to the path of cmd. Require a
                // following command character so `test x = y` is not flagged.
                if atWordStart, let n = next, n != "=", n != " ", n != "\t" {
                    hasExpansion = true
                }
                current.append(c)
                projection.append(c)
                atWordStart = false
            case "|", "&", ";", "\n":
                segments.append(current)
                current = ""
                projection.append(c)
                atWordStart = true
            case " ", "\t":
                current.append(c)
                projection.append(c)
                atWordStart = true
            default:
                current.append(c)
                projection.append(c)
                atWordStart = false
            }
            i += 1
        }
        segments.append(current)

        let balanced = !inSingle && !inDouble && !escaped
        return ScanResult(segments: segments,
                          hasSubstitution: hasSubstitution,
                          hasExpansion: hasExpansion,
                          hasRedirection: hasRedirection,
                          unquotedProjection: projection,
                          balanced: balanced)
    }
}

import Foundation

/// Deterministic pre-classifier for an agent that types shell commands into a
/// terminal. Wire up by assigning the method reference to the classifier's hook:
///
///     let rules = TerminalHardRules()
///     classifier.hardRules = rules.evaluate
///
/// This is a BLOCKLIST, not an allowlist. It never permits a command, and
/// (matching Claude Code) it never hard-denies one either -- a categorical deny
/// has no approval path, which dead-ends a legitimate request and invites bypass
/// attempts. It only surfaces a command for one-tap human approval, or defers.
/// `evaluate` returns:
///
///   - `.needsManualApproval` for a DELIBERATELY NARROW set: cases that could
///     deceive the classifier about what actually runs, hide the payload from it
///     entirely, or are catastrophic. Specifically: terminal escape sequences;
///     carriage returns (a parser differential -- but NOT plain LF newlines, so
///     heredocs and multi-line commands defer); unbalanced quotes; pipe-to-shell
///     (`curl x | sh`, whose fetched bytes are invisible); obscure zsh dangerous
///     builtins; and a catastrophic tripwire -- root/home wipes (`rm -r /`),
///     `chmod`/`chown -R` of root, `find <root> -delete`, writing to a raw
///     device (`dd of=/dev/sda`, `> /dev/sda`), and `mkfs`.
///   - `nil` (defer to the LLM classifier) for EVERYTHING else -- redirection,
///     command/process substitution, zsh `=cmd`, `$IFS`, `/proc/*/environ`,
///     `sudo`, `rm` of a subpath, `git`, and every ordinary command. The
///     classifier reads these in full and judges them against what the user
///     asked for.
///
/// The catastrophic tripwire and pipe-to-shell are computed by TOKENIZING each
/// operator-separated segment into its argv (quotes stripped, env-prefix and
/// modifiers skipped) and checking the actual command + flags + target -- NOT by
/// substring match. That is what makes `echo "rm -rf /"` (argv[0] == echo) and
/// `# rm -rf /` (a comment) and `| sha256sum` (not a shell) defer, while
/// `rm -fr /`, `dd if=/dev/zero of=/dev/sda`, and `curl x|sh` are caught
/// regardless of flag order or spacing. A substring matcher got both wrong.
///
/// The narrow keep-set mirrors Claude Code's AUTO mode: there, an auto-mode
/// classifier makes every permission decision and the interactive structural
/// `ask` checks (redirection, substitution, `$IFS`, ...) are skipped -- only the
/// parser-differential "misparsing" floor survives. This orchestrator is that
/// auto mode; the LLM (fail-closed, prompt-injection-hardened) is the only layer
/// that says yes or no to an ordinary command.
///
/// There is deliberately no allowlist of "safe" verbs. Auto-allowing read-only
/// commands (cat/grep/git status/...) conflated "read-only" with "safe": for an
/// autonomous agent a read is the exfiltration primitive, and some read-only
/// commands even execute code (a poisoned `core.pager` runs on `git log`).
///
/// The public sets are `var` so callers can extend them at runtime.
final class TerminalHardRules {

    // See the type doc above: no allowlist, no hard block. The deterministic
    // layer only surfaces for approval or defers (nil) to the LLM classifier.

    /// zsh module builtins that bypass ordinary command checks: fine-grained fd
    /// access (sysopen/syswrite), pty command execution (zpty), network
    /// exfiltration (ztcp/zsocket), and the zsh/files builtin rm/mv/chmod (zf_*).
    /// `zmodload` is the gateway. Ported from Claude Code's ZSH_DANGEROUS_COMMANDS
    /// but WITHOUT `mapfile`/`emulate` -- those have common benign uses (`mapfile`
    /// is a standard bash builtin, `readarray`). Matched on a segment's base
    /// command (after env-prefix/modifier stripping), surfaced for approval.
    var zshDangerousCommands: Set<String> = [
        "zmodload",
        "sysopen", "sysread", "syswrite", "sysseek",
        "zpty", "ztcp", "zsocket",
        "zf_rm", "zf_mv", "zf_ln", "zf_chmod", "zf_chown",
        "zf_mkdir", "zf_rmdir", "zf_chgrp",
    ]

    /// Shell interpreters that, downstream of a pipe (`curl x | sh`), execute the
    /// piped bytes -- which the classifier cannot see. Matched on a segment's
    /// base command, so spacing and flags don't matter and `| sha256sum` (starts
    /// with "sh" but isn't a shell) is not a false positive.
    var shellInterpreters: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "mksh", "pdksh",
        "ash", "fish", "tcsh", "csh", "busybox",
    ]

    /// Command modifiers skipped when finding a segment's effective command, so
    /// `sudo rm -rf /` and `env FOO=1 rm -rf /` still surface `rm` as the command.
    /// Best-effort: a modifier that carries its OWN option with a value
    /// (`sudo -u root rm ...`, `nice -n 10 rm ...`) is not unwound, so those
    /// forms defer to the LLM rather than hitting the tripwire.
    private static let commandModifiers: Set<String> = [
        "sudo", "doas", "command", "builtin", "exec", "eval", "!",
        "env", "nohup", "nice", "time", "then", "do", "noglob", "nocorrect",
    ]

    // `-exec`-family commands whose executed command makes `find <root> -exec ...`
    // catastrophic. `find ~ -exec grep {} \;` (a read-only exec) is NOT here, so
    // it defers.
    private static let destructiveExecCommands: Set<String> = [
        "rm", "unlink", "rmdir", "mv", "dd", "shred", "chmod", "chown",
        "chgrp", "truncate", "mkfs",
    ]

    // /dev nodes that are safe to write to; a `dd of=` or redirect to any OTHER
    // /dev/* (a raw block device) is the catastrophic case.
    private static let safeDevTargets: Set<String> = [
        "null", "zero", "stdout", "stderr", "tty", "random", "urandom", "full",
    ]

    // Shared reason for every history-expansion / quick-substitution surface.
    private static let historyExpansionReason =
        "the command uses shell history expansion (`!`/`^`), which resurrects a previous command that can't be safety-checked"

    // True if `segment` contains an unquoted, unescaped `!` that triggers history
    // expansion: a `!` NOT immediately followed by whitespace, `=`, `(`, a
    // newline, or end-of-string (those are a literal `!` in bash/zsh). Quote-
    // aware, tracking single AND double quote state like the sibling scanners
    // (`scan`, `tokenizeWords`): single quotes and a preceding backslash disable
    // expansion; DOUBLE quotes do NOT (bash runs histexpand before quote removal,
    // so `!` expands inside them), but a `'` inside double quotes is a LITERAL
    // apostrophe and must not open a phantom single-quote region that swallows a
    // following `!`. Used per operator-separated segment so mid-line resurrection
    // (`sudo !!`, `echo "don't stop!!"`) is caught, not just a leading `!`.
    private static func hasHistoryExpansion(_ segment: String) -> Bool {
        let chars = Array(segment)
        var inSingle = false
        var inDouble = false
        var escaped = false
        for (i, c) in chars.enumerated() {
            if inSingle {
                if c == "'" { inSingle = false }
                continue                              // single quotes: fully literal
            }
            if escaped { escaped = false; continue }  // char after a backslash
            if c == "\\" { escaped = true; continue } // escapes next (incl. `\!` in "")
            if c == "\"" { inDouble.toggle(); continue }
            if c == "'" && !inDouble { inSingle = true; continue }
            guard c == "!" else { continue }          // `!` expands even inside ""
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            switch next {
            case nil, " ", "\t", "=", "(", "\n":
                continue                              // literal `!`
            default:
                return true                           // history expansion
            }
        }
        return false
    }

    func evaluate(_ action: TranscriptEntry) -> ClassifierDecision? {
        guard case .toolCall(_, let raw) = action else { return nil }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return nil }

        // The deterministic layer only surfaces a command for one-tap human
        // approval (.needsManualApproval) or defers (nil) to the LLM classifier,
        // which is the only layer that says yes/no to an ordinary command. No
        // allowlist, no hard block. It keeps a NARROW set: a parser-differential
        // / spoofing floor, and a catastrophic tripwire.

        // Character-presence floor (applies even to multi-line input):
        //  - ESC could rewrite the screen or drive OSC 52 (clipboard).
        //  - CR is the submit gesture and tokenizes differently for the shell
        //    than for our line reconstruction (a genuine misparsing vector).
        if line.unicodeScalars.contains(where: { $0.value == 0x1B }) {
            return .needsManualApproval(reason: "the command contains a terminal escape sequence")
        }
        if line.unicodeScalars.contains(where: { $0.value == 0x0D }) {
            return .needsManualApproval(
                reason: "the command contains a carriage return, which the shell and the safety check tokenize differently")
        }

        // History expansion / quick substitution at LINE START (`!!`, `!rm`,
        // `!-2`, `!string`, `^old^new`) resurrects a previous command we cannot
        // inspect statically -- the shell rebuilds it from history, handing the
        // classifier an opaque token, not the command it runs. Same invisible-
        // payload rationale as pipe-to-shell. Checked BEFORE the multi-line defer
        // so it is caught even as the first physical line of a heredoc/for-loop:
        // deferring an opaque `!!` to the LLM would not help, since the LLM can't
        // inspect the resurrected command either. BANG_HIST (zsh) / histexpand
        // (bash) are on by default interactively. A `!` followed by whitespace
        // (`! cmd`, logical negation -- a commandModifier), `=`, `(` (a glob /
        // subshell under zsh or extglob), or a newline (`!\n`, a literal `!`) is
        // NOT expansion. Mid-line `!` (`sudo !!`, `echo x; !rm`) is caught by the
        // per-segment scan further down (single-line only).
        if line.hasPrefix("^") {
            return .needsManualApproval(reason: Self.historyExpansionReason)
        }
        if line.hasPrefix("!"), let second = line.dropFirst().first,
           second != " ", second != "\t", second != "=", second != "(",
           second != "\n" {
            return .needsManualApproval(reason: Self.historyExpansionReason)
        }

        // A plain (LF) multi-line command -- a heredoc, a for-loop, a multi-line
        // paste -- is read in full by the classifier. Skip all the single-line
        // parse-based checks below: scanning a heredoc BODY for quotes or
        // commands is what produced false positives (an apostrophe in the body,
        // or a documented `rm -rf /`). LF defers; the classifier judges it. This
        // matches Claude Code, whose LF-newline check is nonMisparsing (skipped
        // in auto mode) and which extracts heredoc bodies before analysis.
        if line.unicodeScalars.contains(where: { $0.value == 0x0A }) {
            return nil
        }

        let scanned = scan(line)

        // Unbalanced quotes / dangling escape: ambiguous parse, so the shell and
        // the classifier could read it differently. Surface for review.
        guard scanned.balanced else {
            return .needsManualApproval(
                reason: "the command has unbalanced quotes and cannot be parsed for safety")
        }

        // Catastrophic tripwire + pipe-to-shell, computed by TOKENIZING each
        // operator-separated segment into its argv (quotes stripped, env-prefix /
        // modifiers skipped) and checking the actual command + flags + target.
        // This is why `echo "rm -rf /"` (argv[0] == echo), `# rm -rf /` (a
        // comment), `echo ":(){:|:&};:"` (a quoted string), and `| sha256sum`
        // (not a shell) all DEFER, while `rm -fr /`, `dd if=/dev/zero of=/dev/sda`,
        // and `curl x|sh` are caught regardless of flag order or spacing.
        // Everything not caught -- redirection to a normal file, substitution,
        // `$IFS`, /proc/environ, sudo, `rm` of a subpath, git, plain reads, and
        // the fork bomb (rare, and the classifier recognizes it) -- defers.
        for segment in scanned.segments {
            // History expansion is not confined to line start: bash/zsh expand an
            // unquoted `!`-designator ANYWHERE (`sudo !!`, `echo x; !rm`,
            // `x | !ls`). Scan every operator-separated segment, exactly as the
            // pipe-to-shell / catastrophic checks do, rather than testing only the
            // prefix.
            //
            // This runs AFTER the LF multi-line defer, so it only sees single-line
            // commands. That asymmetry with the line-START `!`/`^` check (which
            // runs BEFORE the defer, so it catches a line that STARTS with history
            // expansion even in multi-line input) is deliberate: a MID-line `!` on
            // a later physical line is usually a heredoc/here-doc body byte, and
            // scanning multi-line bodies for `!` reintroduces exactly the heredoc
            // false positives the LF defer exists to avoid. A line that STARTS
            // with `!!`/`^` is unambiguously history; a `!` buried in a later body
            // line is not, so it defers to the LLM like the rest of the body.
            if Self.hasHistoryExpansion(segment.text) {
                return .needsManualApproval(reason: Self.historyExpansionReason)
            }
            let words = Self.tokenizeWords(segment.text)
            // Redirect (`>`/`>>`) to a raw block device, on any command.
            if Self.redirectsToBlockDevice(words) {
                return .needsManualApproval(reason: "the command writes directly to a device")
            }
            guard let (cmd, args) = Self.effectiveCommand(words) else { continue }
            if let decision = catastrophicVerdict(cmd: cmd, args: args,
                                                  afterPipe: segment.afterPipe) {
                return decision
            }
        }
        return nil
    }

    /// The catastrophic verdict for one segment's tokenized (command, args).
    /// Instance method because it consults the extensible `shellInterpreters` /
    /// `zshDangerousCommands` sets.
    private func catastrophicVerdict(cmd: String, args: [String],
                                     afterPipe: Bool) -> ClassifierDecision? {
        // Pipe-to-shell: a shell interpreter reading bytes piped into it (`curl
        // x | sh`) runs content the classifier cannot see. ONLY an actual pipe
        // `|` counts -- `x && bash deploy.sh` / `x; sh` run a named script or an
        // interactive shell, which the classifier CAN judge, so they defer.
        if afterPipe, shellInterpreters.contains(cmd) {
            return .needsManualApproval(
                reason: "the command pipes into a shell (`\(cmd)`), whose input can't be safety-checked")
        }
        // Obscure zsh dangerous builtins.
        if zshDangerousCommands.contains(cmd) {
            return .needsManualApproval(
                reason: "zsh builtin `\(cmd)` can bypass ordinary command checks")
        }
        // rm -r of the whole root or home directory (force not required -- a
        // recursive delete of root is worth a prompt with or without -f).
        if cmd == "rm",
           Self.hasFlag(args, short: ["r", "R"], long: "recursive"),
           args.contains(where: Self.isCatastrophicTarget) {
            return .needsManualApproval(
                reason: "the command recursively deletes the filesystem root or home directory")
        }
        // chmod/chown/chgrp -R on the whole root or home directory.
        if cmd == "chmod" || cmd == "chown" || cmd == "chgrp",
           Self.hasFlag(args, short: ["R"], long: "recursive"),
           args.contains(where: Self.isCatastrophicTarget) {
            return .needsManualApproval(
                reason: "the command recursively changes ownership/permissions on the filesystem root or home directory")
        }
        // dd writing directly to a raw block device (of=/dev/sda, not /dev/null).
        if cmd == "dd", args.contains(where: Self.isDeviceWriteArg) {
            return .needsManualApproval(reason: "the command writes directly to a device with dd")
        }
        // mkfs formats (destroys) a filesystem.
        if cmd == "mkfs" || cmd.hasPrefix("mkfs.") {
            return .needsManualApproval(reason: "the command formats a filesystem (mkfs)")
        }
        // find rooted at / or home that deletes, or -execs a destructive command
        // (`find ~ -exec grep {} \;`, a read-only exec, defers).
        if cmd == "find",
           args.contains(where: Self.isCatastrophicTarget),
           Self.findIsDestructive(args, shellInterpreters: shellInterpreters) {
            return .needsManualApproval(
                reason: "the command deletes or runs a destructive command across the filesystem root or home directory with find")
        }
        return nil
    }

    // A tokenized segment's effective command and arguments: leading `VAR=val`
    // env assignments and command modifiers (sudo/env/eval/`!`/...) skipped, so
    // `sudo rm -rf /`, `FOO=1 rm -rf /`, and `! rm -rf /` all surface `rm`.
    // Option flags belonging to a modifier are skipped too, so `sudo -i rm -rf /`
    // and `env -i rm -rf /` still surface `rm` rather than the flag `-i`. A
    // VALUE-carrying option (`sudo -u root rm ...`) is NOT unwound: its value
    // becomes the command, which isn't a catastrophic verb, so it defers to the
    // LLM -- matching the best-effort note on `commandModifiers`.
    // Returns nil for an empty segment or a bare env-assignment (`FOO=bar`).
    static func effectiveCommand(_ words: [String]) -> (cmd: String, args: [String])? {
        var i = 0
        var sawModifier = false
        while i < words.count {
            let w = words[i]
            if isEnvAssignment(w) { i += 1; continue }
            let base = baseCommandName(w.hasPrefix("\\") ? String(w.dropFirst()) : w)
            if commandModifiers.contains(base) { sawModifier = true; i += 1; continue }
            // After a modifier, an option flag (`-i`, `-H`, `--login`, `--`) is the
            // modifier's, not the command; skip it so the real command after the
            // flags is found. Only after a modifier: a leading `-flag` with no
            // modifier is a malformed line we leave alone.
            if sawModifier && w.hasPrefix("-") && w.count > 1 { i += 1; continue }
            return (base, Array(words[(i + 1)...]))
        }
        return nil
    }

    // True if any word writes to a raw block device via redirect (`> /dev/sda`,
    // `>/dev/sda`, `2>/dev/sda`, or the space-free `cat x>/dev/sda`), on any
    // command. Complements the dd `of=` check.
    private static func redirectsToBlockDevice(_ words: [String]) -> Bool {
        for (i, w) in words.enumerated() {
            // The shell treats `>`/`>>` (optionally preceded by an fd number or
            // `&`) as a word boundary even with NO surrounding spaces, but our
            // whitespace tokenizer does not split there. Scan the WHOLE word for a
            // redirect operator, not just its start, so `cat /dev/zero>/dev/sda`
            // and `x>>/dev/sda` are caught like the spaced `> /dev/sda`. The
            // pattern always contains a `>`, so a match is never zero-length.
            var searchStart = w.startIndex
            while let r = w.range(of: #"&?[0-9]*>>?"#, options: .regularExpression,
                                  range: searchStart..<w.endIndex) {
                let target = String(w[r.upperBound...])
                if !target.isEmpty {
                    if isBlockDevicePath(target) { return true }   // "…>/dev/sda"
                } else if i + 1 < words.count, isBlockDevicePath(words[i + 1]) {
                    return true                                     // "…>" "/dev/sda"
                }
                if r.upperBound >= w.endIndex { break }
                searchStart = r.upperBound
            }
        }
        return false
    }

    // `of=/dev/sda` (a raw block device), but not `of=/dev/null` etc.
    private static func isDeviceWriteArg(_ arg: String) -> Bool {
        guard arg.hasPrefix("of=") else { return false }
        return isBlockDevicePath(String(arg.dropFirst("of=".count)))
    }

    // A `/dev/*` path that is a raw device, not a safe node (null/zero/tty/...).
    private static func isBlockDevicePath(_ p: String) -> Bool {
        guard p.hasPrefix("/dev/") else { return false }
        let dev = String(p.dropFirst("/dev/".count))
        return !dev.isEmpty && !safeDevTargets.contains(dev) && !dev.hasPrefix("fd/")
    }

    // A `find` invocation is destructive if it deletes, or -execs a destructive
    // command (rm/dd/...) OR a shell interpreter (`find / -exec sh -c '...'` is
    // the most common way to run arbitrary destructive work under find, and the
    // shell's `-c` string is invisible to the classifier -- the same reason
    // pipe-to-shell is caught). `-exec grep`/`-exec cat` (read-only) is not.
    // `shellInterpreters` is passed in because it is the extensible instance set.
    private static func findIsDestructive(_ args: [String],
                                          shellInterpreters: Set<String>) -> Bool {
        if args.contains("-delete") { return true }
        for (i, a) in args.enumerated()
        where ["-exec", "-execdir", "-ok", "-okdir"].contains(a) {
            guard i + 1 < args.count else { continue }
            let target = baseCommandName(args[i + 1])
            if destructiveExecCommands.contains(target) || shellInterpreters.contains(target) {
                return true
            }
        }
        return false
    }

    // Quote-aware word split: honors single/double quotes and backslash escapes,
    // strips the quote characters, and splits on unquoted whitespace. So
    // `rm -rf "/"` -> ["rm","-rf","/"] and `echo "rm -rf /"` -> ["echo","rm -rf /"].
    static func tokenizeWords(_ s: String) -> [String] {
        var words: [String] = []
        var cur = ""
        var started = false
        var inSingle = false, inDouble = false, escaped = false
        for ch in s {
            if escaped { cur.append(ch); escaped = false; started = true; continue }
            if ch == "\\" && !inSingle { escaped = true; started = true; continue }
            if inSingle { started = true; if ch == "'" { inSingle = false } else { cur.append(ch) }; continue }
            if inDouble { started = true; if ch == "\"" { inDouble = false } else { cur.append(ch) }; continue }
            if ch == "'" { inSingle = true; started = true; continue }
            if ch == "\"" { inDouble = true; started = true; continue }
            if ch == " " || ch == "\t" {
                if started { words.append(cur); cur = ""; started = false }
                continue
            }
            cur.append(ch); started = true
        }
        if started { words.append(cur) }
        return words
    }

    // True for a `NAME=value` env-assignment word (a valid shell identifier
    // before the `=`). Used only to skip LEADING assignments while finding a
    // segment's command; `of=/dev/sda` never reaches here as a leading token
    // because `dd` precedes it.
    private static func isEnvAssignment(_ w: String) -> Bool {
        guard let eq = w.firstIndex(of: "="), eq != w.startIndex else { return false }
        let name = w[w.startIndex..<eq]
        guard let f = name.first, f.isLetter || f == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // True if `args` contains the flag, in short (`-rf`, `-r`), long
    // (`--recursive`), or combined form, in any position/order.
    private static func hasFlag(_ args: [String], short: Set<Character>, long: String) -> Bool {
        for a in args {
            if a.hasPrefix("--") {
                if a.dropFirst(2) == long { return true }
            } else if a.hasPrefix("-") && a.count > 1 {
                if a.dropFirst().contains(where: { short.contains($0) }) { return true }
            }
        }
        return false
    }

    // True if `token` names the whole filesystem root or home directory (in any
    // of its spellings), not a subpath: `/`, `//`, `/*`, `/.`, `/..`, `~`, `~/`,
    // `~/*`, `$HOME`, `${HOME}`, `$HOME/*`. `/tmp/git` and `~/Downloads` are NOT.
    private static func isCatastrophicTarget(_ token: String) -> Bool {
        var s = token
        if s.hasSuffix("*") { s = String(s.dropLast()) }              // /*  -> /   ; ~/* -> ~/
        if s.count > 1 && s.hasSuffix("/") { s = String(s.dropLast()) } // ~/ -> ~ ; //  -> /
        if s.isEmpty { return false }
        if s == "/." || s == "/.." { s = "/" }                         // /. , /.. are root
        if s.allSatisfy({ $0 == "/" }) { s = "/" }                     // //, /// -> /
        return ["/", "~", "$HOME", "${HOME}"].contains(s)
    }

    // Lowercased basename of a command token: `/usr/bin/SUDO` -> `sudo`.
    private static func baseCommandName(_ token: String) -> String {
        let lower = token.lowercased()
        if let slash = lower.lastIndex(of: "/") {
            return String(lower[lower.index(after: slash)...])
        }
        return lower
    }

    /// Result of the quote-aware scan of a single line.
    private struct ScanResult {
        /// The line split on unquoted `|`, `&`, `;`. Each segment records whether
        /// it was started by a pipe (`|`), so pipe-to-shell fires only on an
        /// actual pipe, not on `&&`/`;`. Empty segments are kept; callers trim.
        var segments: [(text: String, afterPipe: Bool)]
        /// False if the line ended inside a quote or on a dangling backslash.
        var balanced: Bool
    }

    /// Split a line into operator-separated segments, honoring single-quote,
    /// double-quote, and backslash state so an operator inside quotes does not
    /// split, and recording which segments follow a `|`. Only `segments` and
    /// `balanced` are needed by `evaluate` (the per-segment argv work is done by
    /// `effectiveCommand`); this is intentionally NOT a full shell parser. (LF is
    /// not handled here: multi-line input returns nil in `evaluate` before scan.)
    private func scan(_ line: String) -> ScanResult {
        var segments: [(String, Bool)] = []
        var current = ""
        var currentAfterPipe = false
        var inSingle = false
        var inDouble = false
        var escaped = false

        let chars = Array(line)
        var i = 0
        func split(afterPipe: Bool) { segments.append((current, currentAfterPipe)); current = ""; currentAfterPipe = afterPipe }
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if escaped {
                current.append(c); escaped = false; i += 1; continue
            }
            if c == "\\" && !inSingle {
                current.append(c); escaped = true; i += 1; continue
            }
            if inSingle {
                current.append(c); if c == "'" { inSingle = false }; i += 1; continue
            }
            if inDouble {
                current.append(c); if c == "\"" { inDouble = false }; i += 1; continue
            }
            switch c {
            case "'": inSingle = true; current.append(c)
            case "\"": inDouble = true; current.append(c)
            case "|":
                if next == "|" { split(afterPipe: false); i += 1 }        // `||` logical-or
                else if next == "&" { split(afterPipe: true); i += 1 }    // `|&` pipe both
                else { split(afterPipe: true) }                          // `|` pipe
            case "&":
                if next == ">" { current.append(c) }                      // `&>` redirect: not a split
                else { split(afterPipe: false); if next == "&" { i += 1 } } // `&&` / background `&`
            case ";":
                split(afterPipe: false)
            default:
                current.append(c)
            }
            i += 1
        }
        segments.append((current, currentAfterPipe))
        return ScanResult(segments: segments,
                          balanced: !inSingle && !inDouble && !escaped)
    }
}

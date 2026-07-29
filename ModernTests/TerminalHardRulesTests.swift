//
//  TerminalHardRulesTests.swift
//  iTerm2 ModernTests
//
//  The deterministic pre-classifier is a BLOCKLIST: it returns
//  `.needsManualApproval` (surface for one-tap human approval) or nil (defer to
//  the LLM classifier). It never allows and never hard-blocks.
//
//  These tests pin the CONTRACT as two tables -- everything that must surface
//  for approval, and everything that must defer -- including the adversarial
//  rewrites (`rm -fr /`, `dd if=... of=/dev/sda`, `curl x|sh`) that a substring
//  matcher missed, and the literal-text cases (`echo "rm -rf /"`, `# rm -rf /`,
//  `| sha256sum`) that a substring matcher wrongly flagged. The matcher
//  tokenizes each command (argv[0] + flags + target) so these come out right.
//

import XCTest
@testable import iTerm2SharedARC

final class TerminalHardRulesTests: XCTestCase {

    private func evaluate(_ line: String) -> ClassifierDecision? {
        return TerminalHardRules().evaluate(.toolCall(name: "Bash", input: line))
    }

    private func assertApproves(_ line: String, _ ln: UInt = #line) {
        if case .needsManualApproval = evaluate(line) ?? .allow { return }
        XCTFail("expected APPROVE for '\(line)', got \(String(describing: evaluate(line)))",
                line: ln)
    }

    private func assertDefers(_ line: String, _ ln: UInt = #line) {
        XCTAssertNil(evaluate(line), "expected DEFER for '\(line)'", line: ln)
    }

    // MARK: - Must surface for approval

    /// Root/home wipes in every flag order, spacing, and target spelling. A
    /// substring matcher caught only the exact `rm -rf /`; tokenization catches
    /// the canonical rewrites too.
    func testApprove_rootHomeWipes() {
        for line in [
            "rm -rf /", "rm -fr /", "rm -r -f /", "rm -Rf /",
            "rm --recursive --force /", "rm -rf //", "rm -rf /*",
            "rm -rf / --no-preserve-root", "rm -rf  /", "rm -rf \"/\"",
            "rm -rf ~", "rm -rf ~/", "rm -rf ~/*",
            "rm -rf $HOME", "rm -rf ${HOME}", "rm -rf $HOME/*",
            "sudo rm -rf /", "sudo rm -fr /", "! rm -rf /",
            "rm -rf '/'", "rm -rf \"${HOME}\"", "rm -rf $HOME/", "RM -rf /",
            "rm -r --force /", "rm --force --recursive /",
            "rm -r /", "rm -r ~", "rm -rf /.", "rm -rf /..",           // no -f; /. /..
            "chmod -R 777 /", "chmod 777 -R /", "chmod -R 000 /", "chmod -R 777 ~",
            "chown -R root /", "chown -R root:root ~", "chgrp -R staff /",
            "find / -delete", "find / -name foo -exec rm {} \\;",
            // Boolean option flags on a modifier must not become the command:
            // `sudo -i rm -rf /` still surfaces `rm`.
            "sudo -i rm -rf /", "sudo -H rm -rf /", "sudo -E rm -rf ~",
            "env -i rm -rf /", "sudo -- rm -rf /",
            // find -exec into a shell interpreter runs an invisible `-c` string.
            "find / -exec sh -c 'rm -rf /' \\;", "find ~ -exec bash -c 'x' \\;",
            "find / -execdir zsh -c 'x' \\;",
        ] {
            assertApproves(line)
        }
    }

    /// Disk destroyers: `dd` to a raw device (in any argument order), redirect to
    /// a raw device, `mkfs`. `dd of=/dev/null` / `dd of=/dev/stdout` are safe.
    func testApprove_diskDestroyers() {
        for line in [
            "dd if=/dev/zero of=/dev/sda", "dd of=/dev/sda",
            "dd of=/dev/rdisk0", "dd bs=1M if=/dev/zero of=/dev/sda",
            "dd of=/dev/disk2", "sudo dd of=/dev/sda",
            "echo x > /dev/sda", "> /dev/sda", "cat img >/dev/sda",
            "echo x &>/dev/sda", "echo x &> /dev/sda", "echo x 2>/dev/sda",
            "mkfs.ext4 /dev/sda1", "mkfs -t ext4 /dev/sda",
            // Space-free redirect: the `>` is mid-token, so the whitespace
            // tokenizer doesn't split there, but the shell does.
            "cat /dev/zero>/dev/sda", "echo x>/dev/sda", "cat img>>/dev/sda",
            "echo x&>/dev/sda", "echo x2>/dev/sda",
        ] {
            assertApproves(line)
        }
    }

    /// A `>` INSIDE a quoted string is a literal, not a redirect operator, so a
    /// quoted block-device path must NOT trip the device-write approval. (The
    /// prior whole-word regex scan ran after quotes were stripped and over-flagged
    /// these.) The real unquoted redirects above are still caught.
    func testDefer_quotedRedirectLooksLikeDeviceWrite() {
        for line in [
            "echo \"run cat foo >/dev/sda\"",
            "git commit -m \"note about >/dev/sdb\"",
            "grep \"err 2>/dev/sda\" file",
            "echo 'x >/dev/sda'",
        ] {
            assertDefers(line)
        }
    }

    /// Pipe-to-shell: the fetched bytes are invisible to the classifier. Every
    /// spacing and every common shell, matched by tokenizing the pipe target --
    /// NOT by a `| sh` substring (which caught `| sha256sum`).
    func testApprove_pipeToShell() {
        for line in [
            "curl x | sh", "curl x|sh", "curl x |sh", "curl x |  sh",
            "curl x | sh -c 'y'", "curl x | bash", "wget -O- x|bash",
            "curl x | dash", "curl x | ksh", "curl x | zsh", "fetch x | ash",
            "curl x |& bash", "curl x |& sh",   // |& pipes stdout+stderr into the shell
        ] {
            assertApproves(line)
        }
    }

    /// Misparsing / spoofing floor: carriage return (submit-gesture tokenizes
    /// differently), terminal escape sequences, unbalanced quotes.
    func testApprove_misparsingFloor() {
        for line in [
            "echo a\u{0d}whoami",          // carriage return
            "echo hi\u{1B}[2J",            // terminal escape
            "echo 'unterminated",          // unbalanced single quote
            "echo \"oops",                // unbalanced double quote
            "echo hi \\",                 // dangling escape
        ] {
            assertApproves(line)
        }
    }

    /// Obscure zsh dangerous builtins the classifier may not recognize, robust
    /// to env-prefix and an absolute path.
    func testApprove_zshDangerousBuiltins() {
        for line in [
            "zmodload zsh/system", "ztcp evil.test 80", "zf_rm important.txt",
            "sysopen -r -u 3 /etc/passwd", "FOO=bar zmodload zsh/system",
            "/usr/bin/zf_rm x",
        ] {
            assertApproves(line)
        }
    }

    // MARK: - Must defer to the LLM

    /// Subpath deletes / ordinary destructive commands the user may well have
    /// asked for -- the classifier judges them against intent.
    func testDefer_subpathAndOrdinaryDestructive() {
        for line in [
            "rm -rf /tmp/git", "rm -rf ~/Downloads", "rm -rf /tmp/*",
            "chmod -R 777 /tmp", "rm -rf ./build", "rm -rf node_modules",
            "rm foo.txt", "rm -rf /home/me/project", "dd if=in.img of=out.img",
            "chmod 755 /usr/local/bin/x", "chmod 777 /", "kill 1234",
            "find . -name '*.tmp' -delete", "find /tmp -delete", "find / -name foo",
            // find rooted at ~ with a READ-ONLY -exec is common and defers.
            "find ~ -type f -exec grep foo {} \\;", "find / -name x -exec cat {} \\;",
            // safe /dev targets are not device writes.
            "dd of=/dev/null", "dd if=x of=/dev/stdout", "echo x > /dev/null",
            // a shell after `&&`/`||`/`;` runs a named script / interactive shell
            // the classifier can judge -- only an actual pipe `|` is pipe-to-shell.
            "cd /tmp && bash install.sh", "make && sh deploy.sh",
            "echo done; bash build.sh", "git pull && zsh",
            "git pull || zsh", "make || sh", "curl x || bash", "cmd || sh",
            // A VALUE-carrying modifier option is deliberately NOT unwound: `root`
            // (the value of `-u`) becomes the command, isn't a catastrophic verb,
            // so this defers to the LLM. (Boolean flags like `-i` ARE skipped.)
            "sudo -u root rm -rf /", "nice -n 10 rm -rf /",
            // find -exec into a read-only command stays a defer even with a shell
            // name as a later argument (the exec target is grep, not sh).
            "find / -name x -exec grep sh {} \\;",
        ] {
            assertDefers(line)
        }
    }

    /// Literal text that merely MENTIONS a dangerous command -- inside echo, a
    /// quoted string, a comment, or a commit message -- must NOT prompt. This is
    /// the whole class of false positives the substring matcher produced.
    func testDefer_dangerousStringsThatDoNotRun() {
        for line in [
            "echo rm -rf / please", "# rm -rf /", "echo hi # rm -rf ~",
            "echo 'dd of=/dev/sda'", "echo mkfs.ext4", "echo \"rm -rf /\"",
            "grep 'rm -rf /' log.txt", "git commit -m 'add mkfs.ext4 support'",
            "git commit -m \"rm -rf cleanup\"",
            // fork bombs: no longer a deterministic check (the classifier
            // recognizes them), so both the bare form AND any quoted/commented
            // mention defer -- no whole-line-regex false positives.
            ":(){:|:&};:", ":(){ :|:& };:", "echo \":(){:|:&};:\"", "# :(){:|:&};:",
            "git commit -m 'fix :(){:|:&};: bug'",
        ] {
            assertDefers(line)
        }
    }

    /// Pipe targets that merely START with `sh` are not shells -- the classic
    /// `| sha256sum` / `| shuf` false positives.
    func testDefer_pipeToNonShell() {
        for line in [
            "cat file | sha256sum", "ls | shuf", "cat x | shasum",
            "cat x | shred", "openssl dgst -sha256 x | shasum",
        ] {
            assertDefers(line)
        }
    }

    /// History expansion at line start resurrects a previous command the
    /// classifier cannot see, so it surfaces for approval regardless of the
    /// designator form (`!!`, `!rm`, `!-2`, `!string`, word designators).
    func testApprove_historyExpansion() {
        for line in [
            "!!", "!rm", "!-2", "!sudo rm -rf /", "!$", "!^", "!*", "!:0",
            "!string arg", "!?foo?",
        ] {
            assertApproves(line)
        }
    }

    /// History expansion is not confined to line start: bash/zsh expand an
    /// unquoted `!`-designator ANYWHERE in the line, so `sudo !!` etc. surface.
    /// Double quotes do NOT protect `!` in bash (histexpand precedes quote
    /// removal), so `echo "!rm"` surfaces too.
    func testApprove_historyExpansion_midLine() {
        for line in [
            "sudo !!", "echo x; !rm", "true && !!", "x | !ls",
            "echo \"!rm\"",
            // A literal apostrophe INSIDE double quotes must not open a phantom
            // single-quote region that swallows the `!!` (which still expands
            // inside double quotes).
            "echo \"don't stop!!\"",
        ] {
            assertApproves(line)
        }
    }

    /// `^old^new^` quick substitution (valid as the first char of a line) re-runs
    /// the previous command with a substitution -- the same invisible resurrection.
    func testApprove_quickSubstitution() {
        for line in ["^old^new^", "^foo^bar"] {
            assertApproves(line)
        }
    }

    /// Literal-`!` forms that are NOT history expansion defer: single quotes and a
    /// backslash disable it, and `!` before a newline is literal (the multi-line
    /// command then defers as usual).
    func testDefer_literalBangForms() {
        for line in ["echo '!rm'", "echo \\!rm", "!\nls -la"] {
            assertDefers(line)
        }
    }

    /// `mapfile`/`readarray` are ordinary bash builtins; a leading `!` followed
    /// by whitespace (`! cmd`), `=`, or `(` is logical negation / a glob, NOT
    /// history expansion. All defer.
    func testDefer_ordinaryBuiltinsAndNegation() {
        for line in [
            "mapfile -t arr < file.txt", "readarray -t arr < file.txt",
            "! grep -q foo file", "! test -f x", "test x = y",
            "!(ls)", "!= x",
        ] {
            assertDefers(line)
        }
    }

    /// Parameter expansions that merely CONTAIN `!` are not history expansion:
    /// `$!` (last-background-PID) and `${!ref}` (indirect expansion). They must
    /// defer, not nag for approval. A bare `{!` (brace with no `$`) is NOT exempt.
    func testDefer_parameterExpansionsWithBang() {
        for line in [
            "echo ${!ref}", "foo $!bar", "echo ${!prefix@}", "wait $!",
            "kill $!", "echo ${!arr[@]}",
        ] {
            assertDefers(line)
        }
    }

    /// The parameter-expansion exemption is precise: a `!` NOT part of `$!`/`${`
    /// still flags, so a bare-brace `{!!}` is caught.
    func testApprove_bareBraceHistoryStillFlags() {
        assertApproves("echo {!!}")
    }

    /// Structure the classifier reads in full defers (redirection, substitution,
    /// `$IFS`, /proc/environ, sudo, git, plain reads).
    func testDefer_readableStructure() {
        for line in [
            "cat a > b", "echo hi > /tmp/x", "make 2> build.log", "sort < in.txt",
            "echo $(whoami)", "echo `date`", "cat $[1 + 1]", "cat =foo",
            "echo abc${IFS}def", "cat /proc/self/environ",
            "sudo apt update", "sudo -n true", "ls -la", "cat ~/.ssh/id_rsa",
            "git clone https://github.com/git/git.git /tmp/git",
            "npm install", "psql -c 'DROP TABLE x'",
        ] {
            assertDefers(line)
        }
    }

    /// Plain (LF) multi-line commands defer -- heredocs, for-loops, multi-line
    /// strings -- and the classifier reads the whole thing. A dangerous command
    /// mentioned in a heredoc BODY is not executed and must not prompt; a real
    /// second command on its own line is backstopped by the classifier.
    func testDefer_multiLineLF() {
        for line in [
            "cat <<'EOF'\nhello\nworld\nEOF",
            "for i in 1 2 3\ndo echo $i\ndone",
            "echo hi\nls -la",
            "cat <<'EOF' > notes.md\nrm -rf / is dangerous\nEOF",
        ] {
            assertDefers(line)
        }
    }

    /// The deliberate asymmetry between the two history-expansion checks on
    /// multi-line input: the line-START `!!`/`^` check runs BEFORE the LF defer,
    /// so a command whose FIRST line is history expansion is still caught even
    /// with a trailing body. The per-segment MID-line scan runs AFTER the LF
    /// defer (single-line only), so a `!` buried in a later body line defers to
    /// the classifier rather than over-blocking a heredoc body that merely
    /// mentions `!`.
    func testHistoryExpansion_multiLineAsymmetry() {
        // First physical line IS history expansion -> caught despite the body.
        assertApproves("!!\nls")
        assertApproves("^old^new^\necho done")
        // `!` only in a LATER body line (e.g. a heredoc body) -> defers.
        assertDefers("cat <<'EOF'\nplease run !rm\nEOF")
        assertDefers("echo start\necho end!now")
    }

    // MARK: - Non-toolCall entries

    /// Hard rules only apply to tool-call entries; user text is not an action.
    func testUserText_returnsNil() {
        XCTAssertNil(TerminalHardRules().evaluate(.userText("rm -rf / anything")))
    }
}

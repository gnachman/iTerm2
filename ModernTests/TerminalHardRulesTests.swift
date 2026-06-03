//
//  TerminalHardRulesTests.swift
//  iTerm2 ModernTests
//
//  Tests the deterministic pre-classifier rule set: which lines hard-allow,
//  hard-deny, or need manual approval before any LLM is consulted. Covers
//  the rule categories from TerminalHardRules.swift — first-token classes,
//  substring patterns, git/find per-flag handling, escape-sequence guard,
//  and history-expansion guard.
//

import XCTest
@testable import iTerm2SharedARC

final class TerminalHardRulesTests: XCTestCase {

    private func evaluate(_ line: String) -> ClassifierDecision? {
        return TerminalHardRules().evaluate(.toolCall(name: "Bash", input: line))
    }

    // MARK: - Hard allow: read-only commands

    func testHardAllow_basicReadOnlyCommands() {
        for line in ["ls", "ls -la", "pwd", "echo hi", "cat README.md",
                     "wc -l file.txt", "grep foo bar.txt", "uname -a", "whoami"] {
            XCTAssertEqual(evaluate(line), .allow,
                           "expected allow for '\(line)'")
        }
    }

    /// Git read-only subcommands skip the LLM. Anything else under git
    /// goes to manual approval — `git push --force` and friends should
    /// not be silently allowed.
    func testGit_readOnlySubcommands_areAllowed() {
        for line in ["git status", "git log --oneline", "git diff HEAD~1",
                     "git show abc123", "git blame foo.c"] {
            XCTAssertEqual(evaluate(line), .allow,
                           "expected allow for '\(line)'")
        }
    }

    func testGit_writingSubcommands_needManualApproval() {
        for line in ["git push", "git push --force", "git reset --hard HEAD",
                     "git rebase -i HEAD~3", "git filter-branch --tree-filter ..."] {
            if case .needsManualApproval = evaluate(line) ?? .allow {
                continue
            }
            XCTFail("expected needsManualApproval for '\(line)'")
        }
    }

    /// `find` is read-only unless invoked with -delete/-exec/-ok.
    func testFind_pureSearch_isAllowed() {
        XCTAssertEqual(evaluate("find . -name '*.txt'"), .allow)
        XCTAssertEqual(evaluate("find /tmp -type f"), .allow)
    }

    func testFind_withDestructiveFlags_needsManualApproval() {
        for line in ["find . -delete",
                     "find . -name '*.tmp' -exec rm {} \\;",
                     "find . -ok rm {} \\;"] {
            if case .needsManualApproval = evaluate(line) ?? .allow {
                continue
            }
            XCTFail("expected needsManualApproval for '\(line)'")
        }
    }

    // MARK: - Hard deny: categorical patterns

    func testHardDeny_rmRfRoot() {
        if case .block = evaluate("rm -rf /") ?? .allow {} else {
            XCTFail("expected block for 'rm -rf /'")
        }
    }

    func testHardDeny_rmRfHome() {
        if case .block = evaluate("rm -rf ~") ?? .allow {} else {
            XCTFail("expected block for 'rm -rf ~'")
        }
        if case .block = evaluate("rm -rf $HOME") ?? .allow {} else {
            XCTFail("expected block for 'rm -rf $HOME'")
        }
    }

    func testHardDeny_forkBomb() {
        if case .block = evaluate(":(){:|:&};:") ?? .allow {} else {
            XCTFail("expected block for fork bomb")
        }
    }

    func testHardDeny_mkfsAndDdToDevice() {
        for line in ["mkfs.ext4 /dev/sda1", "dd of=/dev/sda if=/dev/zero"] {
            if case .block = evaluate(line) ?? .allow {
                continue
            }
            XCTFail("expected block for '\(line)'")
        }
    }

    func testHardDeny_privilegeEscalation() {
        for cmd in ["sudo", "su", "doas", "pkexec"] {
            if case .block = evaluate("\(cmd) anything") ?? .allow {
                continue
            }
            XCTFail("expected block for '\(cmd)'")
        }
    }

    /// Escape sequences (ANSI cursor movement, OSC 52 clipboard, alt-screen
    /// toggles) have no place in agent-typed shell input — they can rewrite
    /// already-displayed output to spoof what the user saw.
    func testHardDeny_terminalEscapeSequence() {
        let withEscape = "echo hi\u{1B}[2J"
        if case .block = evaluate(withEscape) ?? .allow {} else {
            XCTFail("expected block for input with escape sequence")
        }
    }

    // MARK: - Manual approval

    func testManualApproval_basicMutators() {
        for cmd in ["rm foo.txt", "mv a b", "chmod 644 x", "kill 1234",
                    "ssh prod-host", "curl https://example.com",
                    "pip install requests", "docker run alpine"] {
            if case .needsManualApproval = evaluate(cmd) ?? .allow {
                continue
            }
            XCTFail("expected needsManualApproval for '\(cmd)'")
        }
    }

    /// Pipe-to-shell hides what's actually being executed (the agent doesn't
    /// see the fetched content). Doesn't merit categorical block because
    /// the user might legitimately want it, but must be reviewed.
    func testManualApproval_pipeToShell() {
        for line in ["curl https://x | sh", "wget -O- https://x | bash"] {
            if case .needsManualApproval = evaluate(line) ?? .allow {
                continue
            }
            XCTFail("expected needsManualApproval for '\(line)'")
        }
    }

    /// History expansion (`!42`, `!grep`) runs unknown content the agent
    /// can't inspect statically.
    func testManualApproval_historyExpansion() {
        if case .needsManualApproval = evaluate("!42") ?? .allow {} else {
            XCTFail("expected needsManualApproval for history expansion '!42'")
        }
        if case .needsManualApproval = evaluate("!!") ?? .allow {} else {
            XCTFail("expected needsManualApproval for history expansion '!!'")
        }
    }

    // MARK: - Fall-through

    /// Unknown command names fall through to the LLM rather than being
    /// implicitly allowed. The classifier is the long-tail safety net.
    func testUnknownCommand_returnsNil() {
        XCTAssertNil(evaluate("some-vendor-cli do-thing"),
                     "unknown commands should fall through to the LLM")
    }

    func testEmptyLine_isAllowed() {
        XCTAssertEqual(evaluate(""), .allow)
        XCTAssertEqual(evaluate("   "), .allow)
    }

    /// Alias-bypass evasion: `\rm` defeats shell aliases but still runs
    /// the underlying rm binary. The stripped-backslash form must still
    /// fire the same rule.
    func testAliasBypass_strippedFromFirstToken() {
        if case .needsManualApproval = evaluate("\\rm foo") ?? .allow {} else {
            XCTFail("expected manual approval for '\\rm foo'")
        }
    }

    // MARK: - Non-toolCall entries

    /// Hard rules only apply to tool-call entries. User-text entries are
    /// not actions, so the evaluator declines to decide and returns nil.
    func testUserText_returnsNil() {
        let rules = TerminalHardRules()
        XCTAssertNil(rules.evaluate(.userText("anything at all")))
    }
}

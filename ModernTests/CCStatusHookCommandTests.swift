//
//  CCStatusHookCommandTests.swift
//  iTerm2 ModernTests
//
//  Coverage for recognizing and resolving cc-status in Claude Code hook
//  commands (issue 13099), and for the install and health-check decisions
//  built on it. Filesystem access is replaced by an isExecutable closure.
//

import XCTest
@testable import iTerm2SharedARC

final class CCStatusHookCommandTests: XCTestCase {
    private let env = ["HOME": "/Users/alice", "XDG": "/x", "PATH": "/opt/bin:/usr/bin"]
    private let installed = "/Users/alice/.config/iterm2/cc-status"

    private func resolutions(_ command: String,
                             executables: Set<String>? = nil) -> [CCStatusHookCommand.Resolution] {
        let executables = executables ?? [installed]
        return CCStatusHookCommand.resolutions(of: command, environment: env) {
            executables.contains($0)
        }
    }

    // MARK: - Recognition

    func testRecognizesPlainPath() {
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus(installed))
    }

    func testRecognizesBareName() {
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("cc-status"))
    }

    func testIgnoresSimilarNames() {
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("/usr/bin/cc-status-old"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("/usr/bin/my-cc-status"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("/usr/bin/cc-status.sh"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("echo hello"))
    }

    func testBareNameOnlyInCommandPosition() {
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("~/bin/notify-hook cc-status"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("echo cc-status >> ~/log"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("foo > cc-status"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("foo 2>&1 cc-status"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("(foo) cc-status"))
    }

    func testBareNameInCommandPosition() {
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("cc-status --verbose"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("true; cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("true && cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("false || cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("cat | cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("true\ncc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("(cc-status)"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("exec cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("command cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("FOO=1 BAR=2 cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("2>/dev/null cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("> /dev/null cc-status"))
    }

    func testPathInArgumentPositionStillMatches() {
        // A path can only be cc-status itself, as in the issue 13099 wrapper's test.
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("[ -x /a/cc-status ]"))
    }

    func testIgnoresRedirectTarget() {
        // These write to a file named cc-status rather than run one.
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("echo done > /tmp/cc-status"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("foo 2>>/a/cc-status"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("/a/cc-status > /tmp/log"))
    }

    func testIfKeywordsKeepCommandPosition() {
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("if cc-status; then :; fi"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("if true; then cc-status; fi"))
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("! cc-status"))
    }

    func testAmpersandRedirectTarget() {
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("cc-status &>/dev/null"))
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("notify &>/tmp/cc-status"))
    }

    func testIgnoresComment() {
        XCTAssertFalse(CCStatusHookCommand.refersToCCStatus("true # /a/cc-status"))
    }

    func testRecognizesPathWithArguments() {
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus("/a/cc-status --verbose"))
    }

    // MARK: - Resolution

    func testPlainPathExecutable() {
        XCTAssertEqual(resolutions(installed), [.executable(installed)])
    }

    func testPlainPathMissing() {
        XCTAssertEqual(resolutions("/gone/cc-status"), [.notExecutable("/gone/cc-status")])
    }

    func testHomeVariable() {
        XCTAssertEqual(resolutions("$HOME/.config/iterm2/cc-status"), [.executable(installed)])
    }

    func testBracedHomeVariable() {
        XCTAssertEqual(resolutions("${HOME}/.config/iterm2/cc-status"), [.executable(installed)])
    }

    func testTilde() {
        XCTAssertEqual(resolutions("~/.config/iterm2/cc-status"), [.executable(installed)])
    }

    func testQuotedTildeIsLiteral() {
        // sh doesn't expand a quoted tilde, so this is a relative path.
        XCTAssertEqual(resolutions("\"~/.config/iterm2/cc-status\""), [.unresolvable])
    }

    func testTildeUserIsUnresolvable() {
        XCTAssertEqual(resolutions("~bob/cc-status"), [.unresolvable])
    }

    func testOtherVariable() {
        XCTAssertEqual(resolutions("$XDG/cc-status", executables: ["/x/cc-status"]),
                       [.executable("/x/cc-status")])
    }

    func testUnsetVariableIsUnresolvable() {
        XCTAssertEqual(resolutions("$NOPE/cc-status"), [.unresolvable])
    }

    func testCommandSubstitutionIsUnresolvable() {
        XCTAssertEqual(resolutions("$(brew --prefix)/bin/cc-status"), [.unresolvable])
        XCTAssertEqual(resolutions("`brew --prefix`/bin/cc-status"), [.unresolvable])
    }

    func testParameterExpansionWithOperatorIsUnresolvable() {
        XCTAssertEqual(resolutions("${HOME:-/tmp}/cc-status"), [.unresolvable])
    }

    func testRelativePathIsUnresolvable() {
        XCTAssertEqual(resolutions("bin/cc-status"), [.unresolvable])
    }

    func testBareNameSearchesPath() {
        XCTAssertEqual(resolutions("cc-status", executables: ["/usr/bin/cc-status"]),
                       [.executable("/usr/bin/cc-status")])
    }

    func testBareNameMissIsUnresolvable() {
        // Claude Code’s PATH may include directories this one lacks.
        XCTAssertEqual(resolutions("cc-status", executables: []), [.unresolvable])
    }

    private func bareNameResolution(path: String?, executables: Set<String>) -> [CCStatusHookCommand.Resolution] {
        var environment = env
        environment["PATH"] = path
        return CCStatusHookCommand.resolutions(of: "cc-status", environment: environment) {
            executables.contains($0)
        }
    }

    func testBareNameWithEmptyPathEntryIsUnresolvable() {
        // An empty entry means the working directory, which can’t be checked.
        XCTAssertEqual(bareNameResolution(path: "/usr/bin::/bin", executables: []), [.unresolvable])
        XCTAssertEqual(bareNameResolution(path: "/usr/bin:", executables: []), [.unresolvable])
    }

    func testBareNameWithRelativePathEntryIsUnresolvable() {
        XCTAssertEqual(bareNameResolution(path: "bin:/usr/bin", executables: []), [.unresolvable])
    }

    func testBareNameWithoutPathIsUnresolvable() {
        // sh falls back to a default search path.
        XCTAssertEqual(bareNameResolution(path: nil, executables: []), [.unresolvable])
    }

    func testBareNameFoundAfterEmptyEntry() {
        XCTAssertEqual(bareNameResolution(path: ":/opt/bin", executables: ["/opt/bin/cc-status"]),
                       [.executable("/opt/bin/cc-status")])
    }

    func testSingleQuotesAreLiteral() {
        XCTAssertEqual(resolutions("'$HOME/cc-status'"), [.unresolvable])
        XCTAssertEqual(resolutions("'/a b/cc-status'", executables: ["/a b/cc-status"]),
                       [.executable("/a b/cc-status")])
    }

    func testDoubleQuotesExpandVariables() {
        XCTAssertEqual(resolutions("\"$HOME/.config/iterm2/cc-status\""), [.executable(installed)])
    }

    func testEscapedSpace() {
        XCTAssertEqual(resolutions("/a\\ b/cc-status", executables: ["/a b/cc-status"]),
                       [.executable("/a b/cc-status")])
    }

    func testWrapperFromIssue13099() {
        let command = "[ -x \"$HOME/.config/iterm2/cc-status\" ] || exit 0; exec \"$HOME/.config/iterm2/cc-status\""
        XCTAssertTrue(CCStatusHookCommand.refersToCCStatus(command))
        XCTAssertEqual(resolutions(command), [.executable(installed), .executable(installed)])
    }

    func testQuotedPathWithSpaces() {
        XCTAssertEqual(resolutions("\"/Users/John Smith/cc-status\"", executables: ["/Users/John Smith/cc-status"]),
                       [.executable("/Users/John Smith/cc-status")])
    }

    // MARK: - runsOnlyCCStatus

    func testRunsOnlyCCStatus() {
        let commands = [
            installed,
            "$HOME/.config/iterm2/cc-status",
            "cc-status --verbose",
            "exec cc-status",
            "FOO=1 cc-status",
            "cc-status 2>/dev/null",
            "(cc-status)",
            "true; cc-status",
            "$(brew --prefix)/bin/cc-status",
            "test -x /a/cc-status && /a/cc-status",
            "[ -x \"$HOME/.config/iterm2/cc-status\" ] || exit 0; exec \"$HOME/.config/iterm2/cc-status\"",
            "command -v cc-status >/dev/null && cc-status",
            "command -V cc-status >/dev/null && cc-status",
            "type cc-status >/dev/null 2>&1 && cc-status",
            "which cc-status >/dev/null && cc-status",
            "cc-status &>/dev/null",
            "cc-status &>> /tmp/log",
            "if [ -x ~/x/cc-status ]; then ~/x/cc-status; fi",
            "if ! [ -x ~/x/cc-status ]; then exit 0; fi; ~/x/cc-status",
            "if [ -x /a/cc-status ]; then /a/cc-status; elif [ -x /b/cc-status ]; then /b/cc-status; else exit 0; fi",
            "cc-status \"$@\"",
            "exec 2>/dev/null; /a/cc-status",
            "[[ -x /a/cc-status ]] || exit 0; exec /a/cc-status",
            "[[ -x \"$HOME/.config/iterm2/cc-status\" ]] || exit 0; exec \"$HOME/.config/iterm2/cc-status\"",
            "/a/cc-status; exit $((0))",
            "/a/cc-status; exit $((1 + 2))",
            "test -x /a/cc-status 2>&1 >&- && /a/cc-status",
            "/a/cc-status >> /tmp/cc.log 2>&1",
            "[ -x ~/x/cc-status ] || exit 0; ~/x/cc-status; exit $?",
            "cc-status \"${1:-stop}\"",
            "if [ -x /a/cc-status ]; then\n/a/cc-status\nfi",
        ]
        for command in commands {
            XCTAssertTrue(CCStatusHookCommand.runsOnlyCCStatus(command), command)
        }
    }

    func testDoesNotRunOnlyCCStatus() {
        let commands = [
            "echo hi",
            "echo done > /tmp/cc-status",
            "/a/cc-status && /usr/local/bin/notify",
            "notify; /a/cc-status",
            "cat | cc-status",
            "[ -x /a/cc-status ] && rm /tmp/x",
            "/a/cc-status $(notify)",
            "/a/cc-status `notify`",
            "/a/cc-status \"${X:-$(notify)}\"",
            ": > /tmp/claude-stopped; /a/cc-status",
            "/a/cc-status; exit $(( $(notify) ))",
            "/a/cc-status; exit $((`notify`))",
            "/a/cc-status $((notify) )",
            "/a/cc-status $((notify); true)",
            "/a/cc-status $((notify",
            "true >> ~/claude-stops.log && /a/cc-status",
            "exec >>/tmp/hook.log 2>&1; /a/cc-status",
            "[ -x /a/cc-status ] 2>/tmp/err && /a/cc-status",
            "notify /a/cc-status",
            "exec",
            "cc-status & notify",
            "command -p notify && cc-status",
            "command notify; cc-status",
            "if [ -x /a/cc-status ]; then /a/cc-status; else notify; fi",
        ]
        for command in commands {
            XCTAssertFalse(CCStatusHookCommand.runsOnlyCCStatus(command), command)
        }
    }

    // MARK: - isPlainAbsolutePath

    func testPlainAbsolutePath() {
        XCTAssertTrue(CCStatusHookCommand.isPlainAbsolutePath(installed))
        XCTAssertFalse(CCStatusHookCommand.isPlainAbsolutePath("$HOME/cc-status"))
        XCTAssertFalse(CCStatusHookCommand.isPlainAbsolutePath("\"/a/cc-status\""))
        XCTAssertFalse(CCStatusHookCommand.isPlainAbsolutePath("/a/cc-status x"))
        XCTAssertFalse(CCStatusHookCommand.isPlainAbsolutePath("cc-status"))
    }

    // MARK: - needsEnvironment

    func testNeedsEnvironment() {
        XCTAssertFalse(CCStatusHookCommand.needsEnvironment(installed))
        XCTAssertFalse(CCStatusHookCommand.needsEnvironment("\"/a b/cc-status\" --verbose"))
        XCTAssertFalse(CCStatusHookCommand.needsEnvironment("$(brew --prefix)/bin/cc-status"))
        XCTAssertFalse(CCStatusHookCommand.needsEnvironment("echo $HOME"))
        XCTAssertTrue(CCStatusHookCommand.needsEnvironment("$HOME/.config/iterm2/cc-status"))
        XCTAssertTrue(CCStatusHookCommand.needsEnvironment("${XDG}/cc-status"))
        XCTAssertTrue(CCStatusHookCommand.needsEnvironment("~/.config/iterm2/cc-status"))
        XCTAssertTrue(CCStatusHookCommand.needsEnvironment("cc-status"))
        XCTAssertTrue(CCStatusHookCommand.needsEnvironment("true; exec \"$HOME/x/cc-status\""))
    }

    // MARK: - parseEnvironment

    func testParseEnvironment() {
        let parsed = CCStatusHookCommand.parseEnvironment("HOME=/Users/a\nX=a=b\n=junk\nnoequals\nEMPTY=")
        XCTAssertEqual(parsed, ["HOME": "/Users/a", "X": "a=b", "EMPTY": ""])
    }

    // MARK: - existingHookAction

    private func action(_ command: String, executables: Set<String>) -> ClaudeCodeOnboarding.ExistingHookAction {
        return ClaudeCodeOnboarding.existingHookAction(command,
                                                       ccStatusPath: installed,
                                                       environment: env) {
            executables.contains($0)
        }
    }

    private func shouldRewrite(_ command: String, executables: Set<String>) -> Bool {
        return action(command, executables: executables) == .rewrite
    }

    func testRewriteLeavesCurrentPathAlone() {
        XCTAssertFalse(shouldRewrite(installed, executables: [installed]))
    }

    func testRewriteUpdatesOtherPlainPath() {
        // A different dot dir, even if it still works.
        XCTAssertTrue(shouldRewrite("/Users/alice/.config/iterm2-alt4/cc-status",
                                    executables: ["/Users/alice/.config/iterm2-alt4/cc-status"]))
    }

    func testRewriteKeepsWorkingCustomCommand() {
        XCTAssertFalse(shouldRewrite("$HOME/.config/iterm2/cc-status", executables: [installed]))
        XCTAssertFalse(shouldRewrite("[ -x \"$HOME/.config/iterm2/cc-status\" ] || exit 0; exec \"$HOME/.config/iterm2/cc-status\"",
                                     executables: [installed]))
    }

    func testRewriteKeepsUnresolvableCommand() {
        XCTAssertFalse(shouldRewrite("$(brew --prefix)/bin/cc-status", executables: []))
    }

    func testRewriteKeepsBareNameMissingFromPath() {
        // The installer's environment may lack the login files' PATH.
        XCTAssertFalse(shouldRewrite("cc-status", executables: [installed]))
    }

    func testRewriteFixesBrokenCustomCommand() {
        XCTAssertTrue(shouldRewrite("$HOME/gone/cc-status", executables: [installed]))
        XCTAssertTrue(shouldRewrite("[ -x \"$HOME/gone/cc-status\" ] || exit 0; exec \"$HOME/gone/cc-status\"",
                                    executables: [installed]))
        XCTAssertTrue(shouldRewrite("if [ -x ~/gone/cc-status ]; then ~/gone/cc-status; fi",
                                    executables: [installed]))
        XCTAssertTrue(shouldRewrite("~/gone/cc-status &>/dev/null", executables: [installed]))
    }

    func testBrokenCompoundCommandIsKeptAndOursAdded() {
        // Rewriting would drop the notifier.
        XCTAssertEqual(action("$HOME/gone/cc-status && /usr/local/bin/notify", executables: [installed]),
                       .addAlongside)
    }

    func testWorkingCompoundCommandIsKept() {
        XCTAssertEqual(action("$HOME/.config/iterm2/cc-status && /usr/local/bin/notify", executables: [installed]),
                       .keep)
    }

    // MARK: - hooksHealthy

    private func settings(command: String, events: [String] = ClaudeCodeOnboarding.hookEventNames) -> [String: Any] {
        var hooks = [String: Any]()
        for event in events {
            hooks[event] = [["hooks": [["type": "command", "command": command]]]]
        }
        return ["hooks": hooks]
    }

    private func healthy(_ settings: [String: Any], executables: Set<String>) -> Bool {
        return ClaudeCodeOnboarding.hooksHealthy(inSettings: settings, environment: env) {
            executables.contains($0)
        }
    }

    func testHealthyWithHomeVariable() {
        XCTAssertTrue(healthy(settings(command: "$HOME/.config/iterm2/cc-status"),
                              executables: [installed]))
    }

    func testHealthyWithUnresolvableCommand() {
        XCTAssertTrue(healthy(settings(command: "$(brew --prefix)/bin/cc-status"), executables: []))
    }

    func testUnhealthyWhenTargetMissing() {
        XCTAssertFalse(healthy(settings(command: "$HOME/.config/iterm2/cc-status"), executables: []))
    }

    func testUnhealthyWhenEventMissing() {
        let events = Array(ClaudeCodeOnboarding.hookEventNames.dropLast())
        XCTAssertFalse(healthy(settings(command: installed, events: events), executables: [installed]))
    }

    func testHealthyWithBareNameMissingFromPath() {
        XCTAssertTrue(healthy(settings(command: "cc-status"), executables: []))
    }

    // Reinstall must fix whatever the health check calls broken, given the same environment,
    // by rewriting the command or adding an entry beside it; otherwise the warning comes back
    // after every Reinstall. The installer's own symlink is executable, since it was just created.
    func testUnhealthyCommandsAreRewritten() {
        let commands = [
            installed,
            "/Users/alice/.config/iterm2-alt4/cc-status",
            "/gone/cc-status",
            "$HOME/.config/iterm2/cc-status",
            "$HOME/gone/cc-status",
            "~/gone/cc-status",
            "$XDG/cc-status",
            "$NOPE/cc-status",
            "cc-status",
            "$(brew --prefix)/bin/cc-status",
            "[ -x \"$HOME/gone/cc-status\" ] || exit 0; exec \"$HOME/gone/cc-status\"",
            "[ -x \"$HOME/.config/iterm2/cc-status\" ] || exit 0; exec \"$HOME/.config/iterm2/cc-status\"",
            "$HOME/gone/cc-status && /usr/local/bin/notify",
            "if [ -x ~/gone/cc-status ]; then ~/gone/cc-status; fi",
            "command -v cc-status >/dev/null && cc-status",
        ]
        let environments: [[String: String]] = [env, [:], ["HOME": "/Users/bob"]]
        let executableSets: [Set<String>] = [[installed],
                                             [installed, "/x/cc-status"],
                                             [installed, "/usr/bin/cc-status"]]
        for command in commands {
            for environment in environments {
                for executables in executableSets {
                    let isExecutable = { (path: String) in executables.contains(path) }
                    let healthy = ClaudeCodeOnboarding.hooksHealthy(inSettings: settings(command: command),
                                                                    environment: environment,
                                                                    isExecutable: isExecutable)
                    let action = ClaudeCodeOnboarding.existingHookAction(command,
                                                                         ccStatusPath: installed,
                                                                         environment: environment,
                                                                         isExecutable: isExecutable)
                    XCTAssertTrue(healthy || action != .keep,
                                  "\(command) is unhealthy but kept with \(environment) and \(executables)")
                }
            }
        }
    }

    func testUnhealthyWithoutCCStatus() {
        XCTAssertFalse(healthy(settings(command: "echo hi"), executables: [installed]))
    }
}

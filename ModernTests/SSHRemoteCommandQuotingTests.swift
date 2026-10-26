//
//  SSHRemoteCommandQuotingTests.swift
//  iTerm2 ModernTests
//
//  `it2ssh host <command>` must run <command> on the host the way `ssh host <command>` does: ssh
//  joins the words after the host with spaces and hands that string to the remote shell, which
//  parses it. it2ssh sends its argv %q-quoted, so the parser recovers those words exactly. It then
//  split them again and the conductor joined the pieces with spaces, which dropped every quote:
//  `claude 'review this; then that'` arrived as `claude review this; then that`.
//

import XCTest
@testable import iTerm2SharedARC

final class SSHRemoteCommandQuotingTests: XCTestCase {
    /// What it2ssh sends: each argument %q-quoted, separated by spaces.
    private func parse(_ argv: [String]) -> ParsedSSHArguments {
        let sent = argv.map { arg -> String in
            // Single quotes are a correct %q-equivalent quoting for these tests.
            "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
        return ParsedSSHArguments(sent, booleanArgs: "", hostnameFinder: iTermHostnameFinder())
    }

    /// Exactly what it2ssh sends: bash's `printf "%q "` of its arguments.
    private func parseAsIt2sshSends(_ argv: [String]) throws -> ParsedSSHArguments {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "printf '%q ' \"$@\"", "bash"] + argv
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ParsedSSHArguments(String(decoding: data, as: UTF8.self),
                                  booleanArgs: "", hostnameFinder: iTermHostnameFinder())
    }

    // %q writes a newline, a tab or other control characters as $'…' quoting. A command with a
    // newline (a multi-line code review prompt, say) must survive it.
    func testBashQuotingWithControlCharactersRoundTrips() throws {
        for command in [#"printf '%s\n' 'a  b;c'"#,
                        "echo 'line one\nline two'",
                        #"echo $HOME "a\"b" 'it'\''s'"# + "\ttab",
                        "echo 日本語 😀",
                        "esc \u{1b}[0m bell \u{07}"] {
            let parsed = try parseAsIt2sshSends(["host", command])
            XCTAssertEqual(parsed.commandLine, command, "for \(command.debugDescription)")
        }
    }

    // MARK: - What ssh would send

    func testOneQuotedArgumentIsSentAsIs() {
        let parsed = parse(["host", "claude 'review this; then that'"])
        XCTAssertEqual(parsed.commandLine, "claude 'review this; then that'")
    }

    // Several arguments are joined with spaces, exactly as ssh does, and the remote shell parses
    // the result: `ssh host echo a ';' echo b` runs two commands.
    func testSeveralArgumentsAreJoinedWithSpaces() {
        let parsed = parse(["host", "echo", "a", ";", "echo", "b"])
        XCTAssertEqual(parsed.commandLine, "echo a ; echo b")
    }

    func testOptionsAndHostAreNotPartOfTheCommand() {
        let parsed = parse(["-p", "2222", "-l", "me", "host", "git", "diff", "main"])
        XCTAssertEqual(parsed.commandLine, "git diff main")
        XCTAssertEqual(parsed.port, 2222)
    }

    func testNoCommand() {
        XCTAssertEqual(parse(["host"]).commandLine, "")
    }

    // The split words are still there for deciding what the command is (a custom shell, say).
    func testWordsAreStillAvailable() {
        let parsed = parse(["host", "/usr/bin/zsh -l"])
        XCTAssertEqual(parsed.commandArgs, ["/usr/bin/zsh", "-l"])
    }

    // A conductor saved before commandLine existed has only the split words. Joining them is what
    // happened before, so restoring it changes nothing.
    func testDecodingAnOlderSaveFallsBackToTheWords() throws {
        let data = try JSONEncoder().encode(parse(["host", "echo", "hi"]))
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "commandLine")
        let decoded = try JSONDecoder().decode(ParsedSSHArguments.self,
                                               from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(decoded.commandLine, "echo hi")
    }

    func testRoundTrip() throws {
        let parsed = parse(["host", "claude 'a b'"])
        let decoded = try JSONDecoder().decode(ParsedSSHArguments.self,
                                               from: JSONEncoder().encode(parsed))
        XCTAssertEqual(decoded.commandLine, "claude 'a b'")
    }

    // MARK: - On the wire to framer

    // Framer reads one base64-encoded argument per line. A command containing a newline (a
    // multi-line prompt, a printf format) must be encoded whole, or it is split into two
    // arguments and framer joins them back with a space.
    func testLoginArgumentWithANewlineStaysOneArgument() {
        let command = Conductor.Command.framerLogin(cwd: "$HOME", args: ["printf '%s\n' x"])
        XCTAssertEqual(command.wireArguments, ["login", "$HOME", "printf '%s\n' x"])
    }

    func testRunArgumentWithANewlineStaysOneArgument() {
        XCTAssertEqual(Conductor.Command.framerRun("echo a\necho b").wireArguments, ["run", "echo a\necho b"])
    }

    // Everything else is sent as before.
    func testOtherCommandsAreUnchanged() {
        let command = Conductor.Command.framerIT2Close(connid: "c1")
        XCTAssertEqual(command.wireArguments, command.stringValue.components(separatedBy: "\n"))
    }

    // MARK: - What the conductor hands the remote shell

    func testUnmodifiedCommandGoesAsIs() {
        XCTAssertEqual(Conductor.remoteCommandString(modifiedCommandArgs: nil,
                                                     commandLine: "claude 'review this; then that'"),
                       "claude 'review this; then that'")
    }

    func testNoCommandMeansAnInteractiveLoginShell() {
        XCTAssertNil(Conductor.remoteCommandString(modifiedCommandArgs: nil, commandLine: ""))
        XCTAssertNil(Conductor.remoteCommandString(modifiedCommandArgs: [], commandLine: ""))
    }

    // A shell that shell integration adjusted (bash gets --posix): those are exact argv words by
    // now, so each is quoted, and none can be split or reinterpreted on the way.
    func testAdjustedShellArgumentsAreQuotedWordByWord() {
        XCTAssertEqual(Conductor.remoteCommandString(modifiedCommandArgs: ["/bin/bash", "--posix", "-c", "echo 'a b'; ls"],
                                                     commandLine: "/bin/bash -c \"echo 'a b'; ls\""),
                       "'/bin/bash' '--posix' '-c' 'echo '\\''a b'\\''; ls'")
    }
}

// A command run with `it2ssh host <command>` gets it2's environment, but only the interactive
// shell-integration scripts put ~/.iterm2/bin on PATH, so `it2` was not found. The login shell's
// profile can reset PATH outright (Debian's /etc/profile does), so the change has to be part of
// the command, after the profile, in the login shell's own syntax.
final class RemoteCommandIT2PathTests: XCTestCase {
    private func run(_ shell: String, _ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", Conductor.commandPuttingIT2OnPath(command, loginShell: shell)]
        process.environment = ["HOME": "/h", "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func testPOSIXShells() throws {
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/ksh", "/bin/dash"]
        where FileManager.default.isExecutableFile(atPath: shell) {
            XCTAssertEqual(try run(shell, #"printf '%s|' "$PATH" 'a  b'"#),
                           "/h/.iterm2/bin:/usr/bin:/bin|a  b|", shell)
        }
    }

    func testCsh() throws {
        for shell in ["/bin/tcsh", "/bin/csh"] where FileManager.default.isExecutableFile(atPath: shell) {
            XCTAssertEqual(try run(shell, #"printf '%s|' "$PATH" 'a  b'"#),
                           "/h/.iterm2/bin:/usr/bin:/bin|a  b|", shell)
        }
    }

    func testFishSyntax() {
        XCTAssertEqual(Conductor.commandPuttingIT2OnPath("claude", loginShell: "/usr/bin/fish"),
                       #"set -gx PATH "$HOME/.iterm2/bin" $PATH; claude"#)
    }

    // A shell whose syntax we do not know runs the command untouched rather than broken.
    func testUnknownShellIsUnchanged() {
        XCTAssertEqual(Conductor.commandPuttingIT2OnPath("claude", loginShell: "/usr/bin/nu"), "claude")
    }
}

// What `it2ssh host …` asked for decides how the remote side is set up.
final class RemoteLaunchKindTests: XCTestCase {
    func testNoCommandIsAnInteractiveLoginShell() {
        XCTAssertEqual(Conductor.remoteLaunchKind(commandArgs: []), .interactive)
    }

    // A shell named as the command is the session's shell, and shell integration adjusts it.
    func testAShellIsACustomShell() {
        XCTAssertEqual(Conductor.remoteLaunchKind(commandArgs: ["/usr/local/bin/bash"]), .customShell("/usr/local/bin/bash"))
        XCTAssertEqual(Conductor.remoteLaunchKind(commandArgs: ["zsh", "-l"]), .customShell("zsh"))
        XCTAssertEqual(Conductor.remoteLaunchKind(commandArgs: ["fish"]), .customShell("fish"))
    }

    // Anything else is a command for the login shell to run, exactly as given. It is not "the
    // shell": that made shell integration skip it entirely, so `it2ssh host claude` got no it2.
    func testAnythingElseIsACommand() {
        XCTAssertEqual(Conductor.remoteLaunchKind(commandArgs: ["claude", "--resume"]), .command)
        XCTAssertEqual(Conductor.remoteLaunchKind(commandArgs: ["git", "diff"]), .command)
        XCTAssertEqual(Conductor.remoteLaunchKind(commandArgs: ["bashful"]), .command)
    }
}

// What getshell sets up on the remote. it2 used to come only with shell-integration injection:
// with "Load shell integration automatically" off, or a shell that cannot be injected (tcsh,
// macOS bash 3.2), there was no socket and no IT2_SOCK at all, so every remote it2 feature
// failed silently. Now the socket comes whenever there is a connection to frame, and the setting
// decides only what is uploaded.
final class RemoteSetupTests: XCTestCase {
    private func setup(_ kind: Conductor.RemoteLaunchKind,
                       injectable: Bool = true,
                       setting: Bool = true,
                       home: Bool = true) -> Conductor.RemoteSetup {
        return Conductor.remoteSetup(launchKind: kind,
                                     shellSupportsInjection: injectable,
                                     shouldInjectShellIntegration: setting,
                                     haveHome: home)
    }

    func testInjectableShellWithTheSettingOnGetsEverything() {
        XCTAssertEqual(setup(.interactive),
                       .init(injectShellIntegration: true, uploadIT2: true, activateIT2: true))
        XCTAssertEqual(setup(.customShell("zsh")),
                       .init(injectShellIntegration: true, uploadIT2: true, activateIT2: true))
    }

    // tcsh: the scripts cannot be injected, but it2 is uploaded and its socket exists.
    func testShellThatCannotBeInjectedStillGetsIt2() {
        XCTAssertEqual(setup(.interactive, injectable: false),
                       .init(injectShellIntegration: false, uploadIT2: true, activateIT2: true))
        XCTAssertEqual(setup(.customShell("/bin/tcsh"), injectable: false),
                       .init(injectShellIntegration: false, uploadIT2: true, activateIT2: true))
    }

    // The setting off means nothing is written to the host, but an it2 already there works.
    func testSettingOffUploadsNothingButStillHasASocket() {
        for kind: Conductor.RemoteLaunchKind in [.interactive, .customShell("bash"), .command] {
            XCTAssertEqual(setup(kind, setting: false),
                           .init(injectShellIntegration: false, uploadIT2: false, activateIT2: true), "\(kind)")
        }
    }

    // A command is run as given, never through the injected scripts.
    func testCommandGetsIt2WithoutInjection() {
        XCTAssertEqual(setup(.command),
                       .init(injectShellIntegration: false, uploadIT2: true, activateIT2: true))
    }

    // Without the remote home there is nowhere to put the socket or the files.
    func testNoHomeMeansNothing() {
        XCTAssertEqual(setup(.interactive, home: false),
                       .init(injectShellIntegration: false, uploadIT2: false, activateIT2: false))
    }
}


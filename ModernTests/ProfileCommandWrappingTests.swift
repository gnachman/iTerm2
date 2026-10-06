//
//  ProfileCommandWrappingTests.swift
//  iTerm2 ModernTests
//
//  A custom or SSH profile's command line is an interpolated string: \(…) is evaluated and
//  backslash escapes such as \n are expanded. Its value is the command. For an SSH profile, and
//  a custom command run in a login shell, that command is then handed to `login … -c`, escaped so
//  it arrives intact.
//
//  The two used to happen in the wrong order: the command line was escaped for the shell first
//  and the whole result evaluated afterwards, so the evaluation expanded the escaping's own \\ and
//  \" back to \ and ". Any command containing a backslash or a double quote reached the shell
//  broken.
//

import XCTest
@testable import iTerm2SharedARC

final class ProfileCommandWrappingTests: XCTestCase {
    private func computedCommand(_ profile: [AnyHashable: Any]) -> String? {
        var result: String?
        let done = expectation(description: "computed")
        ITAddressBookMgr.computeCommand(forProfile: profile,
                                        objectType: .windowObject,
                                        scope: iTermVariableScope()) { command, _ in
            result = command
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result
    }

    /// The argument `login` hands its shell with -c.
    private func dashCArgument(_ command: String?) -> String? {
        guard let command else {
            return nil
        }
        let words = (command as NSString).componentsInShellCommand() ?? []
        guard let index = words.firstIndex(of: "-c"), index + 1 < words.count else {
            return nil
        }
        return words[index + 1]
    }

    private func sshProfile(_ commandLine: String) -> [AnyHashable: Any] {
        return [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeSSHValue,
                KEY_COMMAND_LINE: commandLine,
                KEY_SSH_CONFIG: ["sshIntegration": true]]
    }

    // A command with single quotes, double quotes and a backslash survives to the shell.
    func testSSHCommandLineArrivesIntact() throws {
        let commandLine = #"host 'printf '\''%s\n'\'' "a  b;c"'"#
        let inner = try XCTUnwrap(dashCArgument(computedCommand(sshProfile(commandLine))))
        // \n in the command line is an escape of the interpolated string, as it always was, so it
        // becomes a newline; everything else is exactly as written.
        let expected = commandLine.replacingOccurrences(of: #"\n"#, with: "\n")
        XCTAssertTrue(inner.hasSuffix(" " + expected), "got \(inner)")
    }

    // An interpolated value is part of the command, not spliced into the escaped form, so a value
    // containing spaces no longer ends the -c argument early.
    func testInterpolatedValueIsPartOfTheCommand() throws {
        let commandLine = #"host echo \("a b")"#
        let inner = try XCTUnwrap(dashCArgument(computedCommand(sshProfile(commandLine))))
        XCTAssertTrue(inner.hasSuffix(" host echo a b"), "got \(inner)")
    }

    // A literal backslash needs \\ in the command line, the rule for interpolated strings, and is
    // then delivered as one backslash.
    func testEscapedBackslashIsOneBackslash() throws {
        let inner = try XCTUnwrap(dashCArgument(computedCommand(sshProfile(#"host grep 'a\\|b'"#))))
        XCTAssertTrue(inner.hasSuffix(#" host grep 'a\|b'"#), "got \(inner)")
    }

    // it2ssh loads shell integration on the host unless told not to; an SSH profile tells it when
    // its own "Load shell integration automatically" is off. The flag is it2ssh's first argument.
    func testSSHProfileWithShellIntegrationOffPassesTheFlag() throws {
        var profile = sshProfile("host")
        profile[KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY] = false
        let inner = try XCTUnwrap(dashCArgument(computedCommand(profile)))
        XCTAssertTrue(inner.hasSuffix("/it2ssh' --no-shell-integration host"), "got \(inner)")
    }

    func testSSHProfileWithShellIntegrationOnDoesNot() throws {
        var profile = sshProfile("host")
        profile[KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY] = true
        let inner = try XCTUnwrap(dashCArgument(computedCommand(profile)))
        XCTAssertFalse(inner.contains("--no-shell-integration"), "got \(inner)")
        XCTAssertTrue(inner.hasSuffix("/it2ssh' host"), "got \(inner)")
    }

    func testCustomCommandInLoginShellArrivesIntact() throws {
        let commandLine = #"printf '%s' "x\\y" 'it'\''s'"#
        let profile: [AnyHashable: Any] = [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeCustomValue,
                                           KEY_COMMAND_LINE: commandLine,
                                           KEY_RUN_COMMAND_IN_LOGIN_SHELL: true]
        let inner = try XCTUnwrap(dashCArgument(computedCommand(profile)))
        XCTAssertEqual(inner, #"printf '%s' "x\y" 'it'\''s'"#)
    }

    // Unchanged: a custom command not run in a login shell is the evaluated command line itself.
    func testPlainCustomCommandIsTheEvaluatedCommandLine() {
        let profile: [AnyHashable: Any] = [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeCustomValue,
                                           KEY_COMMAND_LINE: #"echo \("hi")"#]
        XCTAssertEqual(computedCommand(profile), "echo hi")
    }
}

//
//  ShellArgumentsTests.swift
//  ModernTests
//
//  The pidinfo service runs the user’s shell to read its environment. Login-interactive runs
//  add -l so PATH matches a terminal session, but only for shells known to accept it: tcsh and
//  csh reject -l with other flags and elvish has no -l, so those get -i alone. A manual check
//  that the shells shipped with macOS accept these shapes is in tests/check_shell_arguments.sh.
//

import XCTest
@testable import iTerm2SharedARC

final class ShellArgumentsTests: XCTestCase {
    private let script = "/tmp/script"
    private let loginCapable = ["/bin/zsh", "/bin/bash", "/bin/sh", "/bin/dash", "/bin/ksh", "/opt/homebrew/bin/fish", "/opt/homebrew/bin/nu"]
    private let loginIncapable = ["/bin/tcsh", "/bin/csh", "/opt/local/bin/tcsh", "/opt/homebrew/bin/elvish", "/usr/local/bin/xonsh"]

    private func arguments(_ shell: String, _ mode: iTermShellRunMode) -> [String] {
        return iTermShellArguments.arguments(forShell: shell, mode: mode, scriptPath: script)
    }

    func testLoginInteractiveAddsLoginFlagWhereSupported() {
        for shell in loginCapable {
            XCTAssertEqual(arguments(shell, .loginInteractive), ["-l", "-i", "-c", script], shell)
        }
    }

    func testLoginInteractiveFallsBackToInteractiveForOtherShells() {
        for shell in loginIncapable {
            XCTAssertEqual(arguments(shell, .loginInteractive), ["-i", "-c", script], shell)
        }
    }

    func testInteractiveNeverAddsLoginFlag() {
        for shell in loginCapable + loginIncapable {
            XCTAssertEqual(arguments(shell, .interactive), ["-i", "-c", script], shell)
        }
    }

    func testBareIsDashCOnly() {
        for shell in loginCapable + loginIncapable {
            XCTAssertEqual(arguments(shell, .bare), ["-c", script], shell)
        }
    }
}

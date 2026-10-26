//
//  ClaudeCodeConfigDirResolverTests.swift
//  ModernTests
//
//  Where the Claude Code installer reads CLAUDE_CONFIG_DIR from. Claude Code reads
//  it from the shell that launched it, and the installer used to ask the account's
//  login shell unconditionally. A profile that runs a different shell, or a custom
//  command, can start claude with a different value (seen 2026-09-27: bash profile,
//  export in ~/.profile, installer asked zsh and installed into ~/.claude). Now the
//  session that triggered the install decides which sources make sense, the user is
//  asked when there is more than one, and nothing from a profile's custom command is
//  ever run.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeConfigDirResolverTests: XCTestCase {
    private let zsh = "/opt/homebrew/bin/zsh"
    private let bash = "/opt/homebrew/bin/bash"

    private func profile(command: String?, commandLine: String? = nil) -> [AnyHashable: Any] {
        var dict: [AnyHashable: Any] = [:]
        if let command {
            dict[KEY_CUSTOM_COMMAND as String] = command
        }
        if let commandLine {
            dict[KEY_COMMAND_LINE as String] = commandLine
        }
        return dict
    }

    // MARK: - Which sources a session offers

    func testLoginShellProfileOffersOnlyTheLoginShell() {
        let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh,
                                                          profile: profile(command: kProfilePreferenceCommandTypeLoginShellValue),
                                                          runningJob: nil)
        XCTAssertEqual(sources, [.loginShell(path: zsh)])
    }

    func testProfileWithNoCommandTypeIsALoginShell() {
        let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh, profile: [:], runningJob: nil)
        XCTAssertEqual(sources, [.loginShell(path: zsh)])
    }

    func testCustomShellProfileOffersBothShells() {
        let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh,
                                                          profile: profile(command: kProfilePreferenceCommandTypeCustomShellValue,
                                                                           commandLine: bash),
                                                          runningJob: nil)
        XCTAssertEqual(sources, [.loginShell(path: zsh), .profileShell(path: bash)])
    }

    func testCustomShellEqualToTheLoginShellIsNotAmbiguous() {
        let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh,
                                                          profile: profile(command: kProfilePreferenceCommandTypeCustomShellValue,
                                                                           commandLine: " \(zsh) "),
                                                          runningJob: nil)
        XCTAssertEqual(sources, [.loginShell(path: zsh)])
    }

    func testCustomShellWithEmptyPathFallsBackToTheLoginShell() {
        let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh,
                                                          profile: profile(command: kProfilePreferenceCommandTypeCustomShellValue,
                                                                           commandLine: ""),
                                                          runningJob: nil)
        XCTAssertEqual(sources, [.loginShell(path: zsh)])
    }

    // A custom command is never run again. The only thing that can tell us what it
    // exported is a process it already started.
    func testCustomCommandProfileOffersTheRunningJobWhenThereIsOne() {
        let job = ClaudeCodeConfigDirResolver.RunningJob(pid: 4242, name: "claude")
        let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh,
                                                          profile: profile(command: kProfilePreferenceCommandTypeCustomValue,
                                                                           commandLine: "/usr/local/bin/start-dev-env"),
                                                          runningJob: job)
        XCTAssertEqual(sources, [.loginShell(path: zsh), .runningJob(job)])
    }

    // A shell's exec-time environment predates its rc files and a platform binary's
    // is hidden by the kernel, so only the agent's own process is worth reading.
    func testCustomCommandProfileDoesNotOfferAJobThatIsNotTheAgent() {
        let job = ClaudeCodeConfigDirResolver.RunningJob(pid: 4242, name: "bash")
        let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh,
                                                          profile: profile(command: kProfilePreferenceCommandTypeCustomValue,
                                                                           commandLine: "/opt/homebrew/bin/bash"),
                                                          runningJob: job)
        XCTAssertEqual(sources, [.loginShell(path: zsh)])
    }

    func testCustomCommandProfileWithNothingRunningOffersOnlyTheLoginShell() {
        let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh,
                                                          profile: profile(command: kProfilePreferenceCommandTypeCustomValue,
                                                                           commandLine: "/usr/local/bin/start-dev-env"),
                                                          runningJob: nil)
        XCTAssertEqual(sources, [.loginShell(path: zsh)])
    }

    // Remote hosts are a later phase; until then an ssh profile installs locally the
    // way it always has.
    func testSSHAndBrowserProfilesUseTheLoginShell() {
        for type in [kProfilePreferenceCommandTypeSSHValue, kProfilePreferenceCommandTypeBrowserValue] {
            let sources = ClaudeCodeConfigDirResolver.sources(loginShell: zsh,
                                                              profile: profile(command: type, commandLine: "example.com"),
                                                              runningJob: ClaudeCodeConfigDirResolver.RunningJob(pid: 1, name: "ssh"))
            XCTAssertEqual(sources, [.loginShell(path: zsh)], type)
        }
    }

    // MARK: - Resolving a chosen source

    private struct Recorder {
        var shellsRun: [String] = []
        var loginFlags: [Bool] = []
        var pidsRead: [pid_t] = []
    }

    private func dependencies(shellOutput: String?,
                              processEnvironment: [String]?,
                              recorder: UnsafeMutablePointer<Recorder>) -> ClaudeCodeConfigDirResolver.Dependencies {
        return ClaudeCodeConfigDirResolver.Dependencies(
            runInteractiveShell: { path, login, completion in
                recorder.pointee.shellsRun.append(path)
                recorder.pointee.loginFlags.append(login)
                completion(shellOutput)
            },
            processEnvironment: { pid in
                recorder.pointee.pidsRead.append(pid)
                return processEnvironment
            },
            homeDirectory: "/Users/test",
            defaultDirectory: URL(fileURLWithPath: "/Users/test/.claude"))
    }

    private func resolve(_ source: ClaudeCodeConfigDirResolver.Source,
                         shellOutput: String? = nil,
                         processEnvironment: [String]? = nil,
                         recorder: UnsafeMutablePointer<Recorder>) -> URL? {
        var result: URL?
        var delivered = false
        ClaudeCodeConfigDirResolver.resolve(source,
                                            dependencies: dependencies(shellOutput: shellOutput,
                                                                       processEnvironment: processEnvironment,
                                                                       recorder: recorder)) { url in
            result = url
            delivered = true
        }
        XCTAssertTrue(delivered, "completion must run synchronously when the dependencies do")
        return result
    }

    func testProfileShellRunsThatShellAsALoginShell() {
        var recorder = Recorder()
        let url = resolve(.profileShell(path: bash),
                          shellOutput: "PATH=/usr/bin\nCLAUDE_CONFIG_DIR=/Users/test/.config/alt/claude\n",
                          recorder: &recorder)
        XCTAssertEqual(recorder.shellsRun, [bash])
        XCTAssertEqual(recorder.loginFlags, [true], "iTerm2 starts its shells as login shells, so the lookup must too")
        XCTAssertEqual(url?.path, "/Users/test/.config/alt/claude")
    }

    func testLoginShellRunsTheLoginShell() {
        var recorder = Recorder()
        let url = resolve(.loginShell(path: zsh),
                          shellOutput: "CLAUDE_CONFIG_DIR=~/work/.claude\n",
                          recorder: &recorder)
        XCTAssertEqual(recorder.shellsRun, [zsh])
        XCTAssertEqual(url?.path, "/Users/test/work/.claude", "a tilde in the value expands against the home directory")
    }

    func testShellThatDoesNotSetTheVariableMeansTheDefaultDirectory() {
        var recorder = Recorder()
        let url = resolve(.loginShell(path: zsh), shellOutput: "PATH=/usr/bin\nHOME=/Users/test\n", recorder: &recorder)
        XCTAssertEqual(url?.path, "/Users/test/.claude")
    }

    func testShellThatCouldNotRunIsAFailureNotAGuess() {
        var recorder = Recorder()
        let url = resolve(.loginShell(path: zsh), shellOutput: nil, recorder: &recorder)
        XCTAssertNil(url)
    }

    func testRunningJobReadsThatProcessEnvironmentAndRunsNoShell() {
        var recorder = Recorder()
        let job = ClaudeCodeConfigDirResolver.RunningJob(pid: 4242, name: "claude")
        let url = resolve(.runningJob(job),
                          processEnvironment: ["HOME=/Users/test", "CLAUDE_CONFIG_DIR=/Users/test/.config/alt/claude"],
                          recorder: &recorder)
        XCTAssertEqual(recorder.pidsRead, [4242])
        XCTAssertTrue(recorder.shellsRun.isEmpty)
        XCTAssertEqual(url?.path, "/Users/test/.config/alt/claude")
    }

    func testRunningJobWithoutTheVariableMeansTheDefaultDirectory() {
        var recorder = Recorder()
        let job = ClaudeCodeConfigDirResolver.RunningJob(pid: 4242, name: "claude")
        let url = resolve(.runningJob(job), processEnvironment: ["HOME=/Users/test"], recorder: &recorder)
        XCTAssertEqual(url?.path, "/Users/test/.claude")
    }

    func testRunningJobThatHasExitedIsAFailure() {
        var recorder = Recorder()
        let job = ClaudeCodeConfigDirResolver.RunningJob(pid: 4242, name: "claude")
        let url = resolve(.runningJob(job), processEnvironment: nil, recorder: &recorder)
        XCTAssertNil(url)
    }

    // The kernel answers with no environment block at all for a process it will
    // not expose. That must not read as "the variable is unset".
    func testRunningJobWhoseEnvironmentIsHiddenIsAFailure() {
        var recorder = Recorder()
        let job = ClaudeCodeConfigDirResolver.RunningJob(pid: 4242, name: "claude")
        let url = resolve(.runningJob(job), processEnvironment: [], recorder: &recorder)
        XCTAssertNil(url)
    }

    // MARK: - Which directories to offer

    // The user is asked about directories, not shells. Every source is resolved
    // first; sources that agree collapse into one candidate and a single candidate
    // means there is nothing to ask.
    func testSourcesThatAgreeCollapseToOneCandidate() {
        let login = ClaudeCodeConfigDirResolver.Source.loginShell(path: zsh)
        let profile = ClaudeCodeConfigDirResolver.Source.profileShell(path: bash)
        let dir = URL(fileURLWithPath: "/Users/test/.claude")
        let candidates = ClaudeCodeConfigDirResolver.candidates(from: [(login, dir), (profile, URL(fileURLWithPath: "/Users/test/.claude/"))])
        XCTAssertEqual(candidates, [.init(directory: dir, sources: [login, profile])])
    }

    func testSourcesThatDisagreeAreOfferedInSourceOrder() {
        let login = ClaudeCodeConfigDirResolver.Source.loginShell(path: zsh)
        let profile = ClaudeCodeConfigDirResolver.Source.profileShell(path: bash)
        let a = URL(fileURLWithPath: "/Users/test/.claude")
        let b = URL(fileURLWithPath: "/Users/test/.config/alt/claude")
        let candidates = ClaudeCodeConfigDirResolver.candidates(from: [(login, a), (profile, b)])
        XCTAssertEqual(candidates, [.init(directory: a, sources: [login]), .init(directory: b, sources: [profile])])
    }

    // A source that could not be read has nothing to offer; the others still can.
    func testFailedSourcesAreDropped() {
        let login = ClaudeCodeConfigDirResolver.Source.loginShell(path: zsh)
        let job = ClaudeCodeConfigDirResolver.Source.runningJob(.init(pid: 1, name: "claude"))
        let b = URL(fileURLWithPath: "/Users/test/.config/alt/claude")
        let candidates = ClaudeCodeConfigDirResolver.candidates(from: [(login, nil), (job, b)])
        XCTAssertEqual(candidates, [.init(directory: b, sources: [job])])
    }

    func testAllSourcesFailedMeansNoCandidates() {
        let login = ClaudeCodeConfigDirResolver.Source.loginShell(path: zsh)
        XCTAssertEqual(ClaudeCodeConfigDirResolver.candidates(from: [(login, nil)]), [])
    }

    // MARK: - Login flag

    // Bourne-family shells and fish take -l next to -i; tcsh only takes -l alone and
    // xonsh spells it --login, so those run interactive-only as before.
    func testLoginFlagIsUsedOnlyForShellsThatAcceptItWithInteractive() {
        for path in ["/bin/bash", "/opt/homebrew/bin/zsh", "/bin/sh", "/bin/ksh", "/opt/homebrew/bin/fish", "/bin/dash"] {
            XCTAssertTrue(ClaudeCodeConfigDirResolver.loginFlagSupported(shellPath: path), path)
        }
        for path in ["/bin/tcsh", "/bin/csh", "/opt/homebrew/bin/xonsh", "/usr/local/bin/nu", ""] {
            XCTAssertFalse(ClaudeCodeConfigDirResolver.loginFlagSupported(shellPath: path), path)
        }
    }

    // MARK: - Reading the environment of a live process

    // The production environment reader goes through KERN_PROCARGS2, which returns
    // the exec-time environment. The kernel exposes it for the caller's own process
    // and for third-party binaries such as claude, but not for platform binaries
    // (a spawned /bin/sleep answers with argv only), so the round trip is proven on
    // this process rather than on a child. A pid that is gone reads as nil.
    func testProcessEnvironmentReaderRoundTrip() {
        let entries = iTermLSOF.environment(forProcess: getpid())
        XCTAssertNotNil(entries)
        XCTAssertTrue(entries?.contains { $0.hasPrefix("HOME=") } ?? false, "got \(String(describing: entries))")

        let output = ClaudeCodeConfigDirResolver.environmentOutput(fromEntries: entries ?? [])
        let home = ClaudeCodeOnboarding.parseVariable("HOME", from: output)
        XCTAssertEqual(home, ProcessInfo.processInfo.environment["HOME"])

        XCTAssertNil(iTermLSOF.environment(forProcess: 2_147_483_000), "a pid that does not exist reads as nil")
    }
}

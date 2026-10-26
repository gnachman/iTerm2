//
//  WorkgroupRemoteHostTests.swift
//  iTerm2 ModernTests
//
//  A workgroup peer of a leader on a host reached through SSH Integration runs on that host
//  (Phase 6). It connects the way the leader did, replaying every hop, with the peer's command as
//  the last hop's remote command, in the leader's directory there.
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupRemoteHostTests: XCTestCase {
    private func hop(_ sshargs: String, _ directory: String? = nil) -> SSHReconnectionInfo {
        return SSHReconnectionInfo(sshargs: sshargs, initialDirectory: directory, boolargs: "")
    }

    // MARK: - The leader's arguments without its command

    func testArgumentsBeforeTheCommandKeepOptionsAndHost() {
        XCTAssertEqual(ParsedSSHArguments.sshargs("-p 2222 -i ~/.ssh/k user@host claude --resume",
                                                  booleanArgs: "", replacingCommandWith: nil),
                       "'-p' '2222' '-i' '~/.ssh/k' 'user@host'")
    }

    // Options after the host still belong to ssh, as OpenSSH parses them.
    func testOptionsAfterTheHostAreKept() {
        XCTAssertEqual(ParsedSSHArguments.sshargs("host -t -o 'ServerAliveInterval 30' top",
                                                  booleanArgs: "t", replacingCommandWith: nil),
                       "'host' '-t' '-o' 'ServerAliveInterval 30'")
    }

    func testCommandIsReplacedAsOneWord() {
        XCTAssertEqual(ParsedSSHArguments.sshargs("host old command",
                                                  booleanArgs: "", replacingCommandWith: "git diff 'main'"),
                       "'host' 'git diff '\\''main'\\'''")
    }

    // What comes back parses to the same connection with exactly the new command.
    func testReplacedArgumentsRoundTrip() {
        let rebuilt = ParsedSSHArguments.sshargs("-l me host ls -l", booleanArgs: "",
                                                 replacingCommandWith: "claude 'review; this'")
        let parsed = ParsedSSHArguments(rebuilt, booleanArgs: "", hostnameFinder: iTermHostnameFinder())
        XCTAssertEqual(parsed.username, "me")
        XCTAssertEqual(parsed.host, "host")
        XCTAssertEqual(parsed.commandLine, "claude 'review; this'")
    }

    // MARK: - Saving with a workgroup

    func testSavedHostRoundTrips() throws {
        let original = WorkgroupRemoteHost(hops: [hop("bastion", "/home/me"), hop("-p 2200 internal claude")],
                                           directory: "/srv/repo",
                                           sshConfig: ["key": "value"])
        let saved = try XCTUnwrap(original.dictionaryValue)
        let restored = try XCTUnwrap(WorkgroupRemoteHost(dictionary: saved, leader: nil))
        XCTAssertEqual(restored.hops.map(\.sshargs), ["bastion", "-p 2200 internal claude"])
        XCTAssertEqual(restored.hops.map(\.initialDirectory), ["/home/me", nil])
        XCTAssertEqual(restored.directory, "/srv/repo")
        XCTAssertEqual(restored.sshConfig?["key"] as? String, "value")
        // The restored host launches the same way.
        XCTAssertEqual(restored.launchPlan(remoteCommand: "git diff").firstHopArguments,
                       original.launchPlan(remoteCommand: "git diff").firstHopArguments)
    }

    func testASavedHostWithoutHopsIsRejected() {
        XCTAssertNil(WorkgroupRemoteHost(dictionary: [:], leader: nil))
        XCTAssertNil(WorkgroupRemoteHost(dictionary: ["hops": "[]"], leader: nil))
    }

    // MARK: - Building a peer's launch

    func testSingleHop() throws {
        let remote = WorkgroupRemoteHost(hops: [hop("host claude")], directory: "/srv/repo", sshConfig: nil)
        let launch = remote.launchPlan(remoteCommand: "git diff")
        XCTAssertEqual(launch.jumps.count, 1)
        XCTAssertEqual(launch.jumps[0].initialDirectory, "/srv/repo", "starts in the leader's directory")
        let parsed = ParsedSSHArguments(launch.firstHopArguments, booleanArgs: "", hostnameFinder: iTermHostnameFinder())
        XCTAssertEqual(parsed.host, "host")
        XCTAssertEqual(launch.jumps[0].sshargs, launch.firstHopArguments)
        // The command runs under /bin/sh whatever the login shell is.
        XCTAssertEqual(parsed.commandLine, WorkgroupRemoteHost.peerRemoteCommand("git diff"))
        XCTAssertTrue(parsed.commandLine.hasPrefix("/bin/sh -c "))
    }

    // Each earlier hop is replayed as it was; only the last carries the command and the
    // directory.
    func testSeveralHops() throws {
        let remote = WorkgroupRemoteHost(hops: [hop("bastion", "/home/me"), hop("-p 2200 internal claude")],
                                         directory: "/srv/repo", sshConfig: nil)
        let launch = remote.launchPlan(remoteCommand: "git diff")
        XCTAssertEqual(launch.jumps.count, 2)
        XCTAssertEqual(launch.firstHopArguments, "'bastion'")
        XCTAssertEqual(launch.jumps[0].initialDirectory, "/home/me")
        let last = ParsedSSHArguments(launch.jumps[1].sshargs, booleanArgs: "", hostnameFinder: iTermHostnameFinder())
        XCTAssertEqual(last.host, "internal")
        XCTAssertEqual(last.port, 2200)
        XCTAssertEqual(last.commandLine, WorkgroupRemoteHost.peerRemoteCommand("git diff"))
        XCTAssertEqual(launch.jumps[1].initialDirectory, "/srv/repo")
    }

    // No command: an interactive login shell on the host, never the leader's command.
    func testEmptyCommandIsAnInteractiveShell() {
        let launch = WorkgroupRemoteHost(hops: [hop("host claude")], directory: "/srv", sshConfig: nil)
            .launchPlan(remoteCommand: "")
        let parsed = ParsedSSHArguments(launch.firstHopArguments, booleanArgs: "", hostnameFinder: iTermHostnameFinder())
        XCTAssertEqual(parsed.commandLine, "")
        XCTAssertEqual(launch.jumps[0].initialDirectory, "/srv")
    }

    // A command with quotes and newlines (a code review prompt) survives intact.
    func testAwkwardCommandSurvives() {
        let command = "claude 'review this;\nit'\\''s fine'"
        let launch = WorkgroupRemoteHost(hops: [hop("host")], directory: nil, sshConfig: nil)
            .launchPlan(remoteCommand: command)
        let parsed = ParsedSSHArguments(launch.firstHopArguments, booleanArgs: "", hostnameFinder: iTermHostnameFinder())
        XCTAssertEqual(parsed.commandLine, WorkgroupRemoteHost.peerRemoteCommand(command))
        XCTAssertEqual(try runPeerScript(shell: "/bin/sh", rc: nil, command: "printf '%s' " + command.replacingOccurrences(of: "claude ", with: "")),
                       "review this;\nit's fine")
    }

    // The login shell runs the peer's command with -c, whichever shell it is. Quotes, a bang
    // and a newline in the command (as a code review's arguments have) must come through fish
    // and tcsh too, whose quoting differs from POSIX.
    func testCommandSurvivesEveryLoginShell() throws {
        let command = "printf '%s|' \"it's\" 'bang!' 'two\nlines' '$HOME'"
        let expected = "it's|bang!|two\nlines|$HOME|"
        var ran = 0
        for shell in ["/bin/sh", "/bin/zsh", "/bin/bash", "/bin/tcsh", "/bin/csh",
                      "/opt/homebrew/bin/fish", "/usr/local/bin/fish", "/usr/bin/fish"]
        where FileManager.default.isExecutableFile(atPath: shell) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-c", WorkgroupRemoteHost.peerRemoteCommand(command)]
            process.environment = ["HOME": NSTemporaryDirectory(), "SHELL": "/bin/sh", "PATH": "/usr/bin:/bin"]
            let out = Pipe()
            process.standardOutput = out
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(String(decoding: data, as: UTF8.self), expected, shell)
            ran += 1
        }
        XCTAssertGreaterThan(ran, 1)
    }

    // MARK: - The peer's PATH

    /// Runs peerShellScript(command) under /bin/sh with $SHELL set to `shell`, a home whose
    /// startup file `rc` (name, contents) puts ~/claudebin on PATH, and ~/.iterm2/bin present.
    /// Returns standard output.
    private func runPeerScript(shell: String, rc: (String, String)?, command: String) throws -> String {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("peer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let bin = home.appendingPathComponent("claudebin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".iterm2/bin"),
                                                withIntermediateDirectories: true)
        let claude = bin.appendingPathComponent("claude")
        try "#!/bin/sh\necho CLAUDE\n".write(to: claude, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        if let rc {
            try rc.1.write(to: home.appendingPathComponent(rc.0), atomically: false, encoding: .utf8)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", WorkgroupRemoteHost.peerShellScript(command)]
        process.environment = ["HOME": home.path, "SHELL": shell, "PATH": "/usr/bin:/bin", "TERM": "xterm"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private let probe = #"claude; printf '%s\n' "$PATH""#

    // Claude Code's installer adds ~/.local/bin to PATH in ~/.zshrc, which zsh -c skips.
    func testZshPeerGetsThePathFromZshrc() throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else {
            throw XCTSkip("no zsh")
        }
        let out = try runPeerScript(shell: "/bin/zsh",
                                    rc: (".zshrc", "export PATH=\"$HOME/claudebin:$PATH\"\n"),
                                    command: probe)
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "CLAUDE", out)
        let path = try XCTUnwrap(lines.last).split(separator: ":").map(String.init)
        XCTAssertTrue(path.first?.hasSuffix("/.iterm2/bin") ?? false, out)
        XCTAssertEqual(path.filter { $0.hasSuffix("/.iterm2/bin") }.count, 1, out)
        XCTAssertTrue(path.contains { $0.hasSuffix("/claudebin") }, out)
    }

    // ... and in ~/.bash_profile for bash, which macOS's bash -c doesn't read either.
    func testBashPeerGetsThePathFromBashProfile() throws {
        let out = try runPeerScript(shell: "/bin/bash",
                                    rc: (".bash_profile", "export PATH=\"$HOME/claudebin:$PATH\"\n"),
                                    command: probe)
        XCTAssertEqual(out.split(separator: "\n").first.map(String.init), "CLAUDE", out)
    }

    // Startup files that print, or whose shell gives no PATH at all, leave PATH as it was.
    func testNoisyOrFailingStartupFilesFallBack() throws {
        let noisy = try runPeerScript(shell: "/bin/zsh",
                                      rc: (".zshrc", "echo IT2PATH=/bogus; echo noise\nexport PATH=\"$HOME/claudebin:$PATH\"\n"),
                                      command: probe)
        XCTAssertEqual(noisy.split(separator: "\n").first.map(String.init), "CLAUDE", noisy)
        let failing = try runPeerScript(shell: "/nonexistent/zsh", rc: nil, command: #"printf '%s' "$PATH""#)
        XCTAssertTrue(failing.hasSuffix(":/usr/bin:/bin"), failing)
    }
}

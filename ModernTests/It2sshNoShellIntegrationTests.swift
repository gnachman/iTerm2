//
//  It2sshNoShellIntegrationTests.swift
//  iTerm2 ModernTests
//
//  it2ssh injects shell integration (and uploads it2) by default. `it2ssh --no-shell-integration
//  …` opts out; SSH profiles whose "Load shell integration automatically" is off pass it. It used
//  to be decided by that setting of whatever session it2ssh was typed in. The flag is it2ssh's
//  own, only as the first argument, and never reaches ssh; it2ssh tells iTerm2 with `si=0` in
//  SendConductor, which an older iTerm2 ignores.
//

import XCTest
@testable import iTerm2SharedARC

final class It2sshNoShellIntegrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("it2ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var record: URL {
        return root.appendingPathComponent("args")
    }

    /// Runs the real it2ssh (the shell-integration repo's, which the app bundles a copy of) with a
    /// fake ssh, returning its exit status and standard error.
    @discardableResult
    private func runIt2ssh(_ arguments: [String]) throws -> (status: Int32, stderr: String) {
        let fakeSSH = root.appendingPathComponent("ssh")
        // NUL-separated so arguments with newlines survive. With no arguments it prints a usage
        // line and fails, as `ssh` with no host does; it2ssh greps that for boolean options.
        try """
            #!/bin/sh
            [ "$#" -eq 0 ] && { echo 'usage: ssh [-46AaCfGgKkMNnqsTtVvXxYy] [-p port] destination' >&2; exit 255; }
            for a in "$@"; do printf '%s\\0' "$a"; done > '\(record.path)'
            """.write(to: fakeSSH, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)
        // it2ssh's usage comes from plain `ssh`, found on PATH.
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("ssh"),
                                                    withDestinationURL: fakeSSH)
        let it2ssh = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("submodules/iTerm2-shell-integration/utilities/it2ssh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [it2ssh.path] + arguments
        process.environment = ["HOME": root.appendingPathComponent("home").path,
                               "SSH": fakeSSH.path,
                               "TERM": "xterm-256color",
                               "PATH": bin.path + ":/usr/bin:/bin"]
        let input = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        // it2ssh reads until a blank line after ssh exits.
        input.fileHandleForWriting.write(Data("\n".utf8))
        try input.fileHandleForWriting.close()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: errorData, as: UTF8.self))
    }

    /// Runs the real it2ssh with a fake ssh, returning the arguments ssh was given.
    private func sshArguments(_ arguments: [String]) throws -> [String] {
        try runIt2ssh(arguments)
        let data = try Data(contentsOf: record)
        return String(decoding: data, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
            .dropLast().map(String.init)
    }

    /// The ssh arguments it2ssh reports to iTerm2 (the last field of its it2ssh= escape).
    private func reportedSSHArgs(_ remoteCommand: String) throws -> String {
        // The escape ends at BEL (or ESC, inside tmux).
        let range = try XCTUnwrap(remoteCommand.range(of: "1337;it2ssh=[^\u{07}\u{1b}]*", options: .regularExpression))
        let fields = remoteCommand[range].split(separator: " ")
        let encoded = try XCTUnwrap(fields.last.map(String.init))
        return String(decoding: try XCTUnwrap(Data(base64Encoded: encoded)), as: UTF8.self)
    }

    func testDefaultInjects() throws {
        let args = try sshArguments(["-p", "2222", "host"])
        let remote = try XCTUnwrap(args.last)
        XCTAssertTrue(remote.contains("SendConductor=v=3"), remote)
        XCTAssertFalse(remote.contains("si=0"), remote)
    }

    func testFlagOptsOutAndNeverReachesSSH() throws {
        let args = try sshArguments(["--no-shell-integration", "-p", "2222", "host"])
        XCTAssertFalse(args.contains("--no-shell-integration"), "\(args)")
        XCTAssertTrue(args.contains("2222"), "\(args)")
        let remote = try XCTUnwrap(args.last)
        XCTAssertTrue(remote.contains("SendConductor=v=3;si=0"), remote)
        XCTAssertEqual(try reportedSSHArgs(remote).trimmingCharacters(in: .whitespaces), "-p 2222 host")
    }

    // Anywhere but first it is not it2ssh's: after the host it is part of the remote command.
    func testFlagAfterTheHostIsTheRemoteCommands() throws {
        let args = try sshArguments(["host", "echo", "--no-shell-integration"])
        let remote = try XCTUnwrap(args.last)
        XCTAssertFalse(remote.contains("si=0"), remote)
        XCTAssertTrue(try reportedSSHArgs(remote).contains("--no-shell-integration"))
    }

    // Once a word after the host isn't an option, the rest is the remote command, as for ssh. An
    // option's value is not an option either.
    func testFlagAfterTheRemoteCommandStartsIsTheRemoteCommands() throws {
        for arguments in [["host", "-t", "echo", "--no-shell-integration"],
                          ["host", "-p", "--no-shell-integration"],
                          ["host", "-2", "echo", "--no-shell-integration"]] {
            // Removed first, so a refusal (which never runs ssh) can't pass on an earlier record.
            try? FileManager.default.removeItem(at: record)
            let args = try sshArguments(arguments)
            let remote = try XCTUnwrap(args.last, "\(arguments)")
            XCTAssertTrue(try reportedSSHArgs(remote).contains("--no-shell-integration"), "\(arguments)")
        }
    }

    // After --, ssh reads no options after the host either, so there it is the remote command.
    func testFlagAfterTheHostFollowingDoubleDashIsTheRemoteCommand() throws {
        let args = try sshArguments(["--", "host", "--no-shell-integration"])
        let remote = try XCTUnwrap(args.last)
        XCTAssertFalse(remote.contains("si=0"), remote)
        XCTAssertTrue(try reportedSSHArgs(remote).contains("--no-shell-integration"))
    }

    // ssh's usage exits 255, which used to end it2ssh (set -e, pipefail) before its `exit 1`.
    func testUsageExitsOne() throws {
        for arguments in [[], ["--no-shell-integration"]] {
            let result = try runIt2ssh(arguments)
            XCTAssertEqual(result.status, 1, "\(arguments)")
            XCTAssertTrue(result.stderr.contains("usage: it2ssh"), "\(arguments): \(result.stderr)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), "never connects")
        }
    }

    // Where ssh would read an option, the flag can only be a misplaced it2ssh option: refuse it
    // rather than quietly load shell integration after all.
    func testMisplacedFlagIsRefused() throws {
        for arguments in [["host", "--no-shell-integration"],
                          ["-p", "2222", "--no-shell-integration", "host"],
                          // ssh keeps reading options after the host until a word that isn't one.
                          ["host", "-t", "--no-shell-integration"],
                          ["-p", "22", "host", "-t", "--no-shell-integration"],
                          ["host", "-p", "22", "--no-shell-integration"],
                          ["host", "-tv", "--no-shell-integration"],
                          ["host", "-2", "--no-shell-integration"]] {
            let result = try runIt2ssh(arguments)
            XCTAssertEqual(result.status, 1, "\(arguments)")
            XCTAssertTrue(result.stderr.contains("--no-shell-integration must be the first argument"),
                          "\(arguments): \(result.stderr)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), "\(arguments) never connects")
        }
    }
}

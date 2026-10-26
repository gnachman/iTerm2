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

    /// Runs the real it2ssh with a fake ssh, returning the arguments ssh was given.
    private func sshArguments(_ arguments: [String]) throws -> [String] {
        let fakeSSH = root.appendingPathComponent("ssh")
        let record = root.appendingPathComponent("args")
        // NUL-separated so arguments with newlines survive. Prints nothing, as `ssh` with no host
        // would print its usage; it2ssh only greps that for boolean options.
        try """
            #!/bin/sh
            [ "$#" -eq 0 ] && exit 0
            for a in "$@"; do printf '%s\\0' "$a"; done > '\(record.path)'
            """.write(to: fakeSSH, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)
        let it2ssh = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("submodules/iTerm2-shell-integration/utilities/it2ssh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [it2ssh.path] + arguments
        process.environment = ["HOME": root.appendingPathComponent("home").path,
                               "SSH": fakeSSH.path,
                               "TERM": "xterm-256color",
                               "PATH": "/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // it2ssh reads until a blank line after ssh exits.
        input.fileHandleForWriting.write(Data("\n".utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
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
}

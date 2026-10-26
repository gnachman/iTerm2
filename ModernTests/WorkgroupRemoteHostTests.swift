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
        XCTAssertEqual(parsed.commandLine, "/bin/sh -c 'git diff'")
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
        XCTAssertEqual(last.commandLine, "/bin/sh -c 'git diff'")
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
        let words = BashWordSplitter.words(parsed.commandLine)
        XCTAssertEqual(words, ["/bin/sh", "-c", command])
    }
}

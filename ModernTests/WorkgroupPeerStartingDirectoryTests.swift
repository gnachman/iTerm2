//
//  WorkgroupPeerStartingDirectoryTests.swift
//  ModernTests
//
//  Created by George Nachman on 11/11/26.
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupPeerStartingDirectoryTests: XCTestCase {
    private typealias Subject = WorkgroupPeerStartingDirectory

    private func kind(remote: Bool, tmux: Bool, localServer: Bool) -> Subject.LeaderKind {
        return Subject.leaderKind(hasRemoteHost: remote,
                                  isTmuxClient: tmux,
                                  tmuxServerKnownToBeLocal: localServer)
    }

    // MARK: - Classification

    func testLocalShell() {
        XCTAssertEqual(kind(remote: false, tmux: false, localServer: false), .localShell)
    }

    // Server locality only matters for a tmux client.
    func testLocalShellIgnoresTmuxServerLocality() {
        XCTAssertEqual(kind(remote: false, tmux: false, localServer: true), .localShell)
    }

    func testSSHIntegration() {
        XCTAssertEqual(kind(remote: true, tmux: false, localServer: false), .sshIntegration)
    }

    // A tmux integration pane reached through SSH Integration is on the host, whatever the
    // server's locality says.
    func testTmuxThroughSSHIntegrationIsSSHIntegration() {
        XCTAssertEqual(kind(remote: true, tmux: true, localServer: false), .sshIntegration)
        XCTAssertEqual(kind(remote: true, tmux: true, localServer: true), .sshIntegration)
    }

    func testTmuxOnLocalServer() {
        XCTAssertEqual(kind(remote: false, tmux: true, localServer: true), .tmuxLocalServer)
    }

    // Covers both a server known to be remote (e.g., tmux over plain ssh) and one whose locality
    // isn't known yet.
    func testTmuxOnOtherOrUnknownServer() {
        XCTAssertEqual(kind(remote: false, tmux: true, localServer: false), .tmuxOtherServer)
    }

    // MARK: - Starting directory

    func testLocalShellUsesLeadersCurrentDirectory() {
        XCTAssertEqual(Subject(leaderKind: .localShell), .leadersCurrentDirectory)
    }

    func testTmuxOnLocalServerUsesLeadersCurrentDirectory() {
        XCTAssertEqual(Subject(leaderKind: .tmuxLocalServer), .leadersCurrentDirectory)
    }

    func testSSHIntegrationStartsInLeadersDirectoryOnHost() {
        XCTAssertEqual(Subject(leaderKind: .sshIntegration), .leadersDirectoryOnHost)
    }

    // A path on another machine must never be used as a local directory.
    func testTmuxOnOtherServerStartsInHomeDirectory() {
        XCTAssertEqual(Subject(leaderKind: .tmuxOtherServer), .homeDirectory)
    }
}

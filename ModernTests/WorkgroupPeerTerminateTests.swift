//
//  WorkgroupPeerTerminateTests.swift
//  ModernTests
//
//  Exit Workgroup while a peer was the displayed member closed the whole window, leader included,
//  and the peers later came back as orphans (QA finding F-930). Teardown swaps the leader back into
//  the shared pane and then terminates the peer, but the swap left the swapped-out peer with the tab
//  as its delegate, so its termination acted on a tab it no longer lived in. Peers were also only
//  terminated undoably, which kept them restorable.
//

import XCTest
@testable import iTerm2SharedARC

// Records the delegate a session had when it was terminated.
private final class TerminateSpyPTYSession: PTYSession {
    var terminated = false
    var delegateAtTerminate: PTYSessionDelegate?

    override func terminate() {
        if !terminated {
            terminated = true
            delegateAtTerminate = delegate
        }
        super.terminate()
    }
}

final class WorkgroupPeerTerminateTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private var spawner: FakeWorkgroupSpawner!
    private var leader: PTYSession!
    private var tab: PTYTab!
    private var instance: iTermWorkgroupInstance!
    private var peer: TerminateSpyPTYSession!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        iTermWorkgroupController.instance.checkConsistency()
        fixture.close()
        fixture = nil
        instance = nil
        peer = nil
        tab = nil
        leader = nil
        spawner = nil
        super.tearDown()
    }

    // Enters a workgroup of the window's session and one peer, and shows the peer.
    private func enterWorkgroupAndShowPeer() throws {
        let terminal = fixture.terminal
        leader = try XCTUnwrap(terminal.currentSession())
        tab = try XCTUnwrap(leader.delegate as? PTYTab)

        // Peers are born buried: they have a view but no tab.
        spawner = FakeWorkgroupSpawner()
        let profile = leader.profile
        spawner.sessionFactory = {
            let peer = TerminateSpyPTYSession(synthetic: false)!
            peer.profile = profile
            terminal.setupSession(peer, with: nil)
            peer.bury()
            return peer
        }
        let root = WGFix.makeRoot()
        let peerConfig = WGFix.makePeer(parentID: root.uniqueIdentifier)
        let workgroup = WGFix.wrap(name: "F930", sessions: [root, peerConfig])
        instance = try XCTUnwrap(iTermWorkgroupInstance.enter(workgroup: workgroup,
                                                              on: leader,
                                                              spawner: spawner))
        peer = try XCTUnwrap(spawner.session(forConfigID: peerConfig.uniqueIdentifier) as? TerminateSpyPTYSession)

        XCTAssertTrue(instance.peerPort.activate(identifier: peerConfig.uniqueIdentifier))
        XCTAssertTrue(tab.sessions().contains(peer), "Precondition: the peer occupies the pane")
    }

    func testExitWorkgroupWithPeerShownTerminatesDetachedPeerAndKeepsLeader() throws {
        try enterWorkgroupAndShowPeer()

        iTermWorkgroupController.instance.exit(instance: instance)

        XCTAssertTrue(peer.terminated)
        XCTAssertNil(peer.delegateAtTerminate,
                     "A peer swapped out of the pane must not act on the tab when it terminates")
        XCTAssertFalse(peer.shell.paused,
                       "A peer of an exited workgroup must be stopped for good, not kept for Undo Close")
        XCTAssertFalse(leader.exited, "Exiting the workgroup must not terminate the leader")
        XCTAssertTrue(leader.delegate === tab)
        XCTAssertEqual(tab.sessions(), [leader])
        XCTAssertEqual(fixture.terminal.numberOfTabs(), 1)
    }

    // When the shown peer's own closing drives the teardown, that close must
    // stay undoable.
    func testClosingShownPeerKeepsItRevivable() throws {
        try enterWorkgroupAndShowPeer()

        peer.terminate()

        XCTAssertTrue(peer.exited)
        XCTAssertTrue(instance.didTeardown, "The peer's termination should exit the workgroup")
        XCTAssertTrue(peer.shell.paused, "Closing the shown peer must stay undoable")
    }
}

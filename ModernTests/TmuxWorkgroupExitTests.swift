//
//  TmuxWorkgroupExitTests.swift
//  iTerm2 ModernTests
//
//  Exit Workgroup on a workgroup in a tmux Integration tab. The server is the source of truth for
//  its members: Exit swaps the leader back into view through tmux and kills the members' panes,
//  and the tab follows tmux's layout. Closing the peers in view here as well emptied the leader's
//  tab before the leader's pane came back to it when two peer groups each showed a peer, and
//  closing a tmux tab's last session hides its window, so the leader's window disappeared.
//  QA finding F-614.
//

import XCTest
@testable import iTerm2SharedARC

/// Records soft closes instead of closing through a window, which tests don't have.
private final class ExitSoftCloseSpyTab: PTYTab {
    var softClosed = [PTYSession]()

    override func softClose(_ session: PTYSession) {
        softClosed.append(session)
    }
}

final class TmuxWorkgroupExitTests: WorkgroupEntryTestBase {
    private var tmux: TmuxRecordingGateway!
    private var controller: TmuxController!

    override func tearDown() {
        if let task = leader?.shell as AnyObject as? iTermTask {
            TaskNotifier.sharedInstance().deregister(task)
        }
        if let controller {
            TmuxControllerRegistry.sharedInstance().setController(nil, forClient: controller.clientName)
        }
        controller = nil
        tmux = nil
        super.tearDown()
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10)
    }

    func testExitLeavesPeersInViewToTmux() throws {
        try checkPeerInViewIsLeftToTmux(closingSplit: false)
    }

    // Closing another member (Cmd-W on the split) ends the workgroup the same way. QA finding F-618.
    func testClosingAMemberLeavesPeersInViewToTmux() throws {
        try checkPeerInViewIsLeftToTmux(closingSplit: true)
    }

    private func checkPeerInViewIsLeftToTmux(closingSplit: Bool) throws {
        let root = WGFix.makeRoot()
        let peer = WGFix.makePeer(parentID: root.uniqueIdentifier)
        let split = WGFix.makeSplit(parentID: root.uniqueIdentifier)
        let wg = WGFix.wrap(name: "rootPeerSplit", sessions: [root, peer, split])
        let instance = try XCTUnwrap(enterWorkgroup(wg))

        // Make it a workgroup on a tmux server, attached. The leader becomes a tmux client before
        // it has a controller, so it installs no tmux status bar monitor, which needs a profile.
        leader.setTmuxPane(0)
        drainMainQueue()
        tmux = TmuxRecordingGateway()
        controller = TmuxController(gateway: tmux.gateway,
                                    clientName: "workgroup-exit-test",
                                    profile: [:],
                                    profileModel: nil)
        leader.tmuxController = controller
        let binding = try XCTUnwrap(TmuxWorkgroupBinding(leader: leader, workgroup: wg,
                                                         instanceID: instance.instanceUniqueIdentifier,
                                                         gitBase: "main"))
        XCTAssertTrue(binding.isConnected)
        instance.tmuxBinding = binding

        // The peer is in view, in the leader's tab.
        let peerSession = try XCTUnwrap(spawner.session(forConfigID: peer.uniqueIdentifier))
        let view = SessionView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        peerSession.view = view
        let splitView = PTYSplitView(frame: view.frame)
        splitView.addSubview(view)
        let map = NSMapTable<SessionView, PTYSession>.strongToStrongObjects()
        map.setObject(peerSession, forKey: view)
        let tab = try XCTUnwrap(ExitSoftCloseSpyTab(root: splitView, sessions: map))
        peerSession.delegate = tab
        instance.peerPort.activeSessionIdentifier = peer.uniqueIdentifier

        if closingSplit {
            instance.teardown(becauseSessionTerminated: try XCTUnwrap(spawner.session(forConfigID: split.uniqueIdentifier)))
        } else {
            // Exit Workgroup.
            instance.teardown()
        }
        drainMainQueue()

        XCTAssertEqual(tab.softClosed.count, 0, "the peer leaves its tab when tmux removes its pane")
        XCTAssertFalse(peerSession.exited)
        XCTAssertNil(peerSession.workgroupInstance)
    }
}

//
//  TmuxWorkgroupFilteredMemberTests.swift
//  iTerm2 ModernTests
//
//  With Find > Filter open on a workgroup member in a tmux Integration tab, the tab shows a
//  synthetic stand-in in place of the member's session. When a peer switch (made by another
//  client, since a filtered member shows no workgroup toolbar) parks the member's pane, the
//  member's session must be buried as usual, not terminated along with the stand-in, so that
//  switching back brings back the same session and its filter. QA finding F-654.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupFilteredMemberTests: XCTestCase {
    private var tmuxSessions = [PTYSession]()
    private var gatewayDelegate: TmuxTestGatewayDelegate?
    private var controller: TmuxController?

    override func tearDown() {
        // -setTmuxPane: registers the session's task with the shared notifier.
        for session in tmuxSessions {
            if let task = session.shell as AnyObject as? iTermTask {
                TaskNotifier.sharedInstance().deregister(task)
            }
        }
        tmuxSessions = []
        if let controller {
            TmuxControllerRegistry.sharedInstance().setController(nil, forClient: controller.clientName)
        }
        controller = nil
        gatewayDelegate = nil
        super.tearDown()
    }

    private func tmuxSession(pane: Int32) -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.view = SessionView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        session.setTmuxPane(pane)
        tmuxSessions.append(session)
        return session
    }

    private struct Fixture {
        var tab: PTYTab
        var controller: TmuxController
        var leader: PTYSession
        var standIn: PTYSession
        var peer: PTYSession
    }

    /// Window @1 shows the leader %0, filtered, in the slot and the split member %1 beside it. The
    /// peer %2 is parked, with a buried session.
    private func makeFixture() -> Fixture {
        let leader = tmuxSession(pane: 0)
        let split = tmuxSession(pane: 1)
        let peer = tmuxSession(pane: 2)
        _ = PTYSessionPeerPort(peers: ["ROOT": iTermPromise(value: leader),
                                       "P1": iTermPromise(value: peer)],
                               activeSessionIdentifier: "ROOT",
                               leaderIdentifier: "ROOT")
        // A session that has been buried keeps its session when its pane leaves a tab, as a
        // member of a workgroup on a tmux server does (keepsTmuxSessionWhenItLeavesItsTab).
        leader.markTmuxBuried()
        peer.markTmuxBuried()

        let root = PTYSplitView(frame: NSRect(x: 0, y: 0, width: 601, height: 300))
        root.isVertical = true
        let map = NSMapTable<SessionView, PTYSession>.strongToStrongObjects()
        for session in [leader, split] {
            root.addSubview(session.view!)
            map.setObject(session, forKey: session.view!)
        }
        let tab = PTYTab(root: root, sessions: map)!

        let delegate = TmuxTestGatewayDelegate()
        gatewayDelegate = delegate
        let gateway = TmuxGateway(delegate: delegate, dcsID: "dcs")!
        let controller = TmuxController(gateway: gateway,
                                        clientName: "filtered-member-test",
                                        profile: [:],
                                        profileModel: nil)!
        self.controller = controller
        // A tmux tab gets its controller when it is opened from a tmux layout.
        tab.setValue(controller, forKey: "tmuxController_")
        tab.setValue(1, forKey: "tmuxWindow")
        for session in [leader, split] {
            session.delegate = tab
        }
        // Burying registers the session with its controller.
        leader.tmuxController = controller
        XCTAssertTrue(leader.keepsTmuxSessionWhenItLeavesItsTab)
        controller.registerBuriedSession(peer, withPane: 2)
        tab.setActiveSession(leader)

        // Find > Filter on the leader.
        let standIn = PTYSession(synthetic: true)!
        standIn.view = SessionView(frame: leader.view!.frame)
        standIn.delegate = tab
        tab.perform(NSSelectorFromString("replaceActiveSessionWithSyntheticSession:"), with: standIn)
        standIn.filter = "MAINLINE4"
        XCTAssertTrue(standIn.live === leader)
        XCTAssertEqual(leader.contentSubscribers?.count, 1, "the filter reads the leader's content")
        return Fixture(tab: tab, controller: controller, leader: leader, standIn: standIn, peer: peer)
    }

    private func applyLayout(_ layout: String, _ fixture: Fixture) {
        let tree = TmuxLayoutParser.sharedInstance().parsedLayout(from: layout)!
        fixture.tab.perform(NSSelectorFromString("replaceViewHierarchyWithParseTree:tmuxController:"),
                            with: tree,
                            with: fixture.controller)
    }

    func testAFilteredMemberParkedByAPeerSwitchIsBuriedAndComesBack() {
        let fixture = makeFixture()

        // Another client switches to the peer: %2 takes the leader's place.
        applyLayout("abcd,81x24,0,0{40x24,0,0,2,40x24,41,0,1}", fixture)
        XCTAssertFalse(fixture.leader.exited, "the leader's session must be kept")
        XCTAssertTrue(fixture.controller.session(forWindowPane: 0) === fixture.leader,
                      "the leader's session is buried for its parked pane")
        XCTAssertEqual(fixture.leader.tmuxFilterToRestore, "MAINLINE4")
        XCTAssertNil(fixture.standIn.live, "the stand-in no longer shows the leader")
        XCTAssertEqual(fixture.leader.contentSubscribers?.count ?? 0, 0,
                       "the retired filter must not keep reading the buried session")

        // And back to the leader. Joining the tab registers a session with its controller, which
        // needs a window that this test has none of.
        fixture.leader.tmuxController = nil
        applyLayout("abcd,81x24,0,0{40x24,0,0,0,40x24,41,0,1}", fixture)
        XCTAssertTrue(fixture.tab.sessions().contains(where: { $0 === fixture.leader }),
                      "the same session returns to the slot")
        XCTAssertNil(fixture.leader.tmuxFilterToRestore, "its filter is taken to be put back (this tab is not in a window, so it is dropped)")
    }
}

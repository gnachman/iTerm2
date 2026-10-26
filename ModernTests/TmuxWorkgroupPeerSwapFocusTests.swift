//
//  TmuxWorkgroupPeerSwapFocusTests.swift
//  iTerm2 ModernTests
//
//  Switching peers in a workgroup in a tmux Integration tab swaps the peer's pane into the slot
//  (swap-pane), and the tab is rebuilt from tmux's layout. Focus in the slot must stay in the slot,
//  on the peer that now fills it, as it does for a local workgroup. It went to the other pane of the
//  window, the split member, so typing landed there. QA finding F-650.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupPeerSwapFocusTests: XCTestCase {
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
        XCTAssertTrue(session.isTmuxClient)
        return session
    }

    private struct Fixture {
        var tab: PTYTab
        var controller: TmuxController
        var leader: PTYSession
        var split: PTYSession
        var peer: PTYSession
        var port: PTYSessionPeerPort
    }

    /// Window @1 shows the leader %0 in the slot and the split member %1 beside it. The peer %2 is
    /// parked, with a buried session. With `focusSlot` the leader is active, otherwise the split.
    private func makeFixture(focusSlot: Bool) -> Fixture {
        let leader = tmuxSession(pane: 0)
        let split = tmuxSession(pane: 1)
        let peer = tmuxSession(pane: 2)
        let port = PTYSessionPeerPort(peers: ["ROOT": iTermPromise(value: leader),
                                              "P1": iTermPromise(value: peer)],
                                      activeSessionIdentifier: "ROOT",
                                      leaderIdentifier: "ROOT")
        XCTAssertTrue(leader.belongs(toPeers: port))
        XCTAssertTrue(peer.belongs(toPeers: port))

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
                                        clientName: "peer-swap-focus-test",
                                        profile: [:],
                                        profileModel: nil)!
        self.controller = controller
        // A tmux tab gets its controller when it is opened from a tmux layout.
        tab.setValue(controller, forKey: "tmuxController_")
        tab.setValue(1, forKey: "tmuxWindow")
        for session in [leader, split] {
            session.delegate = tab
        }
        controller.registerBuriedSession(peer, withPane: 2)
        tab.setActiveSession(focusSlot ? leader : split)
        return Fixture(tab: tab, controller: controller, leader: leader, split: split, peer: peer, port: port)
    }

    /// tmux swapped the peer %2 into the leader's place.
    private func applySwappedLayout(_ fixture: Fixture) {
        let tree = TmuxLayoutParser.sharedInstance().parsedLayout(from: "abcd,81x24,0,0{40x24,0,0,2,40x24,41,0,1}")!
        fixture.tab.perform(NSSelectorFromString("replaceViewHierarchyWithParseTree:tmuxController:"),
                            with: tree,
                            with: fixture.controller)
    }

    func testFocusInTheSlotStaysInTheSlotAfterAPeerSwap() {
        let fixture = makeFixture(focusSlot: true)
        applySwappedLayout(fixture)
        XCTAssertTrue(fixture.tab.sessions().contains(where: { $0 === fixture.peer }),
                      "the peer's buried session fills the slot")
        XCTAssertTrue(fixture.tab.activeSession === fixture.peer,
                      "focus must follow the slot, not move to the split member")
    }

    // Control: focus in the split member stays there.
    func testFocusInTheSplitStaysInTheSplitAfterAPeerSwap() {
        let fixture = makeFixture(focusSlot: false)
        applySwappedLayout(fixture)
        XCTAssertTrue(fixture.tab.activeSession === fixture.split)
    }
}

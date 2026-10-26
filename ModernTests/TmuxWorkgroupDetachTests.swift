//
//  TmuxWorkgroupDetachTests.swift
//  iTerm2 ModernTests
//
//  Detaching from tmux with a workgroup peer in view ends the workgroup on this Mac: the parked
//  leader's buried session is terminated, which tears the instance down. The windows outlive the
//  detach, as for any tmux window, so the peer in view must stay in its place like any detached
//  pane. It was closed, which left an empty area where it had been. QA finding F-652.
//

import XCTest
@testable import iTerm2SharedARC

/// Records soft closes instead of closing through a window, which tests don't have.
private final class SoftCloseSpyTab: PTYTab {
    var softClosed = [PTYSession]()

    override func softClose(_ session: PTYSession) {
        softClosed.append(session)
    }
}

final class TmuxWorkgroupDetachTests: XCTestCase {
    private struct Fixture {
        var tab: SoftCloseSpyTab
        var leader: SpyPTYSession
        var peerInView: SpyPTYSession
        var buriedPeer: SpyPTYSession
        var port: PTYSessionPeerPort
    }

    /// The peer P1 is in view in a tab; the leader and the peer P2 are buried.
    private func makeFixture() -> Fixture {
        let leader = SpyPTYSession(synthetic: false)!
        let peerInView = SpyPTYSession(synthetic: false)!
        let buriedPeer = SpyPTYSession(synthetic: false)!
        peerInView.view = SessionView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))

        let root = PTYSplitView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        root.addSubview(peerInView.view!)
        let map = NSMapTable<SessionView, PTYSession>.strongToStrongObjects()
        map.setObject(peerInView, forKey: peerInView.view!)
        let tab = SoftCloseSpyTab(root: root, sessions: map)!
        peerInView.delegate = tab

        let port = PTYSessionPeerPort(peers: ["ROOT": iTermPromise(value: leader),
                                              "P1": iTermPromise(value: peerInView),
                                              "P2": iTermPromise(value: buriedPeer)],
                                      activeSessionIdentifier: "P1",
                                      leaderIdentifier: "ROOT")
        return Fixture(tab: tab, leader: leader, peerInView: peerInView, buriedPeer: buriedPeer, port: port)
    }

    /// Ending a peer in a tab is deferred to the main queue's next pass.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10)
    }

    func testAPeerInViewStaysWhenTheConnectionIsGone() {
        let fixture = makeFixture()
        fixture.port.invalidate(keepingPeersInTabs: true)
        drainMainQueue()
        XCTAssertEqual(fixture.tab.softClosed.count, 0, "the peer in view must stay in its tab")
        XCTAssertEqual(fixture.peerInView.spy_terminateCount, 0)
        XCTAssertEqual(fixture.buriedPeer.spy_terminateCount, 1, "a buried peer has no tab to stay in")
        XCTAssertEqual(fixture.leader.spy_terminateCount, 0, "the port's leader is never ended by it")
    }

    // Control: otherwise a peer in view is closed through its tab, as the workgroup ends.
    func testAPeerInViewIsClosedOtherwise() {
        let fixture = makeFixture()
        fixture.port.invalidate()
        drainMainQueue()
        XCTAssertEqual(fixture.tab.softClosed.count, 1)
        XCTAssertTrue(fixture.tab.softClosed.first === fixture.peerInView)
        XCTAssertEqual(fixture.buriedPeer.spy_terminateCount, 1)
    }
}

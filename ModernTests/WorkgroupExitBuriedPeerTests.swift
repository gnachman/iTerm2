//
//  WorkgroupExitBuriedPeerTests.swift
//  iTerm2 ModernTests
//
//  A local workgroup's peer that was shown and then switched away keeps its tab as its delegate
//  while buried. Exit Workgroup took that as the peer being in the tab and closed it through the
//  tab, and the tab, holding only the leader, closed with it, taking the window. A buried peer is
//  terminated instead, and the leader stays. QA finding F-713.
//

import XCTest
@testable import iTerm2SharedARC

/// Records soft closes instead of closing through a window, which tests don't have.
private final class BuriedPeerSoftCloseSpyTab: PTYTab {
    var softClosed = [PTYSession]()

    override func softClose(_ session: PTYSession) {
        softClosed.append(session)
    }
}

final class WorkgroupExitBuriedPeerTests: XCTestCase {
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10)
    }

    /// The leader is in a tab; the peer was shown once, so its delegate is still that tab.
    private func makeTab(leader: PTYSession, peer: PTYSession) -> BuriedPeerSoftCloseSpyTab {
        leader.view = SessionView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let root = PTYSplitView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        root.addSubview(leader.view!)
        let map = NSMapTable<SessionView, PTYSession>.strongToStrongObjects()
        map.setObject(leader, forKey: leader.view!)
        let tab = BuriedPeerSoftCloseSpyTab(root: root, sessions: map)!
        leader.delegate = tab
        peer.delegate = tab
        return tab
    }

    func testABuriedPeerWithAStaleTabIsTerminatedNotClosedThroughTheTab() {
        let leader = SpyPTYSession(synthetic: false)!
        let peer = SpyPTYSession(synthetic: false)!
        let tab = makeTab(leader: leader, peer: peer)
        XCTAssertFalse(tab.sessions().contains { $0 === peer }, "precondition: the peer is buried")
        let port = PTYSessionPeerPort(peers: ["ROOT": iTermPromise(value: leader),
                                              "P1": iTermPromise(value: peer)],
                                      activeSessionIdentifier: "ROOT",
                                      leaderIdentifier: "ROOT")
        port.invalidate()
        drainMainQueue()
        XCTAssertEqual(tab.softClosed.count, 0, "closing it through the tab would close the leader's tab")
        XCTAssertEqual(peer.spy_terminateCount, 1)
        XCTAssertEqual(leader.spy_terminateCount, 0)
    }
}

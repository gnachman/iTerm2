//
//  TmuxWorkgroupLateLeaderTests.swift
//  iTerm2 ModernTests
//
//  Attaching to a tmux session with more windows than the Dashboard limit opens the Dashboard
//  instead of the windows, so a workgroup's leader may have no session when its instance would be
//  adopted. Opening the leader's window later showed the leader and its split as ordinary panes
//  until the next attach. The state is now read again once the leader's pane has a session.
//  QA finding F-615.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupLateLeaderTests: XCTestCase {
    private var tmux: TmuxRecordingGateway!
    private var controller: TmuxController!
    private var attacher: TmuxWorkgroupAttacher!
    private var sessions = [PTYSession]()

    override func setUp() {
        super.setUp()
        tmux = TmuxRecordingGateway()
        controller = TmuxController(gateway: tmux.gateway,
                                    clientName: "late-leader-test",
                                    profile: [:],
                                    profileModel: nil)
        attacher = TmuxWorkgroupAttacher(controller: controller)
    }

    override func tearDown() {
        for session in sessions {
            if let task = session.shell as AnyObject as? iTermTask {
                TaskNotifier.sharedInstance().deregister(task)
            }
        }
        sessions = []
        TmuxControllerRegistry.sharedInstance().setController(nil, forClient: controller.clientName)
        attacher = nil
        controller = nil
        tmux = nil
        super.tearDown()
    }

    private var stateReads: Int {
        return tmux.written.filter { $0.hasPrefix("show -q -t $") }.count
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10)
    }

    func testTheStateIsReadAgainOnceWhenTheLeaderGetsASession() {
        // Asked twice, as two refreshes would before the window opens.
        attacher.adoptWhenLeaderHasSession(paneID: 5)
        attacher.adoptWhenLeaderHasSession(paneID: 5)
        drainMainQueue()
        XCTAssertEqual(stateReads, 0, "nothing to do until the leader has a session")

        // The leader's window opens.
        let leader = PTYSession(synthetic: false)!
        leader.setTmuxPane(5)
        sessions.append(leader)
        controller.registerBuriedSession(leader, withPane: 5)
        drainMainQueue()
        XCTAssertEqual(stateReads, 1, "read once: \(tmux.written)")

        // Once tmux answers, nothing asks again: a second waiter would have queued another read.
        for _ in 0..<3 {
            tmux.reply()
        }
        drainMainQueue()
        XCTAssertEqual(stateReads, 1, "read once: \(tmux.written)")
    }
}

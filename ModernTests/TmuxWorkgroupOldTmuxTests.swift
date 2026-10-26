//
//  TmuxWorkgroupOldTmuxTests.swift
//  iTerm2 ModernTests
//
//  A workgroup in a tmux Integration tab keeps its state on the tmux server, which needs tmux 3.2
//  or later. With an older tmux, entering one fell back to native splits and tabs, which the next
//  layout change from tmux removed, ending the workgroup with no message. Entering is now refused
//  there, and the Workgroups menu disables it. QA finding F-619.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupOldTmuxTests: WorkgroupEntryTestBase {
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

    /// Makes the leader a pane of a tmux server whose version is `version`.
    private func makeLeaderATmuxPane(version: String) {
        // The leader becomes a tmux client before it has a controller, so it installs no tmux
        // status bar monitor, which needs a profile.
        leader.setTmuxPane(0)
        drainMainQueue()
        tmux = TmuxRecordingGateway()
        tmux.gateway.minimumServerVersion = NSDecimalNumber(string: version)
        controller = TmuxController(gateway: tmux.gateway,
                                    clientName: "old-tmux-test",
                                    profile: [:],
                                    profileModel: nil)
        leader.tmuxController = controller
    }

    private func refusal(_ wg: iTermWorkgroup) -> iTermWorkgroupController.EnterRefusal? {
        return iTermWorkgroupController.instance.enterRefusal(workgroupUniqueIdentifier: wg.uniqueIdentifier,
                                                               on: leader)
    }

    func testTmuxOlderThan32IsRefused() {
        let wg = WGFix.wgRootOnly()
        iTermWorkgroupModel.instance.add(wg)
        defer { iTermWorkgroupModel.instance.remove(uniqueIdentifier: wg.uniqueIdentifier) }
        makeLeaderATmuxPane(version: "3.1")
        guard case .tmuxTooOld = refusal(wg) else {
            XCTFail("expected tmuxTooOld, got \(String(describing: refusal(wg)))")
            return
        }
        XCTAssertFalse(iTermWorkgroupController.instance.canEnterFromUI(workgroupUniqueIdentifier: wg.uniqueIdentifier,
                                                                        on: leader))
    }

    // Control: tmux 3.2 has what a workgroup needs.
    func testTmux32IsAllowed() {
        let wg = WGFix.wgRootOnly()
        iTermWorkgroupModel.instance.add(wg)
        defer { iTermWorkgroupModel.instance.remove(uniqueIdentifier: wg.uniqueIdentifier) }
        makeLeaderATmuxPane(version: "3.2")
        XCTAssertNil(refusal(wg))
    }
}

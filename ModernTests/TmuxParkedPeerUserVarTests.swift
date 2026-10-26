//
//  TmuxParkedPeerUserVarTests.swift
//  iTerm2 ModernTests
//
//  A workgroup peer is created in a parked window, which iTerm2 learns of from %window-add and
//  then a display of the window. Its shell can print its first prompt before then, while the pane
//  has no session, so that output is dropped and its screen comes from capture-pane, which keeps
//  no escape sequences. User variables set by that prompt were lost until the next one. They must
//  be applied to the pane's buried session as they are to a pane in a window being opened.
//  QA finding F-651.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxParkedPeerUserVarTests: XCTestCase {
    private var tmux: TmuxRecordingGateway!
    private var controller: TmuxController!

    override func setUp() {
        super.setUp()
        tmux = TmuxRecordingGateway()
        tmux.gateway.minimumServerVersion = NSDecimalNumber(string: "3.4")
        controller = TmuxController(gateway: tmux.gateway,
                                    clientName: "parked-peer-user-var-test",
                                    profile: [:],
                                    profileModel: nil)
        // Normally learned when the version is detected.
        controller.setValue(true, forKey: "versionKnown")
    }

    override func tearDown() {
        for session in controller.buriedSessions() {
            if let task = session.shell as AnyObject as? iTermTask {
                TaskNotifier.sharedInstance().deregister(task)
            }
        }
        controller.detach()
        TmuxControllerRegistry.sharedInstance().setController(nil, forClient: controller.clientName)
        controller = nil
        tmux = nil
        super.tearDown()
    }

    /// A display of window @`window` (listWindowsDetailedFormat, tmux 3.2+) holding pane %`pane`,
    /// tagged as parked.
    private func parkedWindowRecord(window: Int, pane: Int) -> String {
        let layout = "af3d,80x24,0,0,\(pane)"
        return ["s", "@\(window)", "zsh", "80", "24", layout, "", "0", layout, "off",
                TmuxWorkgroupState.ParkedTag(instanceID: "I").encoded].joined(separator: "\t")
    }

    private func setUserVar(_ name: String, _ value: String) -> Data {
        let encoded = Data(value.utf8).base64EncodedString()
        return Data("\u{1b}]1337;SetUserVar=\(name)=\(encoded)\u{07}".utf8)
    }

    func testUserVarFromAParkedPeersFirstPromptReachesItsBuriedSession() {
        // %window-add for the peer's new window.
        controller.openWindow(withId: 9, intentional: false, profile: [:])
        XCTAssertTrue(tmux.written.last?.hasPrefix("display -p -F") ?? false, "\(tmux.written)")

        // Its shell's first prompt arrives before iTerm2 knows the window is parked.
        controller.didDropOutput(setUserVar("host_name", "new"), forPane: 5)

        // The display shows it is parked: the pane gets a buried session, filled from tmux.
        tmux.reply([parkedWindowRecord(window: 9, pane: 5)])
        XCTAssertNotNil(controller.session(forWindowPane: 5), "a buried session for the parked pane")
        // Two captures of history, the pane's state, its pending output, and its @uservars. The
        // session then executes the captured sequences with the pane's state, as one in a window
        // being opened does (VT100ScreenMutableState), which needs more of an app than this has.
        for _ in 0..<5 {
            tmux.reply()
        }

        XCTAssertEqual(controller.userVars(forPane: 5)["user.host_name"], "new")
        XCTAssertTrue(tmux.written.contains { $0.hasPrefix("set -p -t %5 @uservars") },
                      "the variable is saved in tmux for other clients: \(tmux.written)")
    }

    // Once the buried session exists the pane's output reaches it, so a value its shell sets then
    // is newer than one captured before, which must not overwrite it.
    func testALaterValueSetInTheBuriedSessionWins() {
        controller.openWindow(withId: 9, intentional: false, profile: [:])
        controller.didDropOutput(setUserVar("host_name", "old"), forPane: 5)
        tmux.reply([parkedWindowRecord(window: 9, pane: 5)])
        XCTAssertNotNil(controller.session(forWindowPane: 5))

        // What the buried session does when its shell sets the variable again.
        controller.setUserVariableWithKey("user.host_name", value: "new", pane: 5)
        for _ in 0..<5 {
            tmux.reply()
        }
        XCTAssertEqual(controller.userVars(forPane: 5)["user.host_name"], "new")
    }

    // The parked window must stop counting as awaiting its layout, or every new pane's dropped
    // output would be scanned from then on.
    func testAParkedWindowStopsAwaitingItsLayout() {
        controller.openWindow(withId: 9, intentional: false, profile: [:])
        tmux.reply([parkedWindowRecord(window: 9, pane: 5)])

        // A pane in some other window that iTerm2 never opens.
        controller.didDropOutput(setUserVar("host_name", "other"), forPane: 7)
        XCTAssertEqual(controller.takeDeferredTokens(forPane: 7).count, 0)
    }
}

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

    // MARK: - The offer to repair a broken arrangement's profile

    // The identifier of iTermNaggingController's offer to assign a profile to a session whose
    // saved profile has no name or GUID (the 3.5.7 bug). Accepting it saves the chosen profile
    // into the arrangement it names, finding the session there by its GUID.
    private let repairOfferIdentifier = "ArrangementMissingProfile"
    private var restoredSessions = [PTYSession]()

    /// A session restored from a tmux pane's arrangement, whose profile is `[:]` (so it has
    /// neither a name nor a GUID, and is in no profile model), optionally with a session GUID and
    /// an arrangement name.
    private func restoreSession(sessionGUID: String?, arrangementName: String?) throws -> PTYSession {
        let leaf: [AnyHashable: Any] = [kLayoutDictWindowPaneKey: 6,
                                        kLayoutDictWidthKey: 80,
                                        kLayoutDictHeightKey: 24]
        var arrangement = PTYSession.arrangement(fromTmuxParsedLayout: leaf,
                                                 bookmark: [:],
                                                 tmuxController: controller,
                                                 window: 9)
        if let sessionGUID {
            // SESSION_ARRANGEMENT_GUID, which is private to PTYSession.m.
            arrangement["Session GUID"] = sessionGUID
        }
        let view = SessionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let session = try XCTUnwrap(PTYSession(fromArrangement: arrangement,
                                               named: arrangementName,
                                               in: view,
                                               with: nil,
                                               for: .paneObject,
                                               partialAttachments: nil,
                                               options: nil))
        restoredSessions.append(session)
        // As the callers of the restore do in the app.
        session.tmuxController = controller
        return session
    }

    private func forgetRestoredSessions() {
        for session in restoredSessions {
            if let task = session.shell as AnyObject as? iTermTask {
                TaskNotifier.sharedInstance().deregister(task)
            }
        }
        restoredSessions = []
    }

    // Control: a session restored from a named arrangement, which has its GUID, can be repaired.
    func testARestoredSessionFromANamedArrangementIsOfferedARepair() throws {
        defer { forgetRestoredSessions() }
        let session = try restoreSession(sessionGUID: "restored-session", arrangementName: "Saved Arrangement")
        XCTAssertTrue(session.hasAnnouncement(withIdentifier: repairOfferIdentifier))
    }

    // With no arrangement name there is no saved arrangement to repair: accepting the offer saved
    // the default arrangement under a nil name, which raised.
    func testARestoredSessionWithoutAnArrangementNameIsNotOfferedARepair() throws {
        defer { forgetRestoredSessions() }
        let session = try restoreSession(sessionGUID: "restored-session", arrangementName: nil)
        XCTAssertFalse(session.hasAnnouncement(withIdentifier: repairOfferIdentifier))
    }

    // With no session GUID nothing in the arrangement can be matched to the session.
    func testARestoredSessionWithoutAGUIDIsNotOfferedARepair() throws {
        defer { forgetRestoredSessions() }
        let session = try restoreSession(sessionGUID: nil, arrangementName: "Saved Arrangement")
        XCTAssertFalse(session.hasAnnouncement(withIdentifier: repairOfferIdentifier))
    }

    // A parked window's pane is restored from a tmux layout, with neither.
    func testAParkedPanesBuriedSessionIsNotOfferedARepair() throws {
        controller.openWindow(withId: 9, intentional: false, profile: [:])
        tmux.reply([parkedWindowRecord(window: 9, pane: 5)])
        let session = try XCTUnwrap(controller.session(forWindowPane: 5))
        XCTAssertFalse(session.hasAnnouncement(withIdentifier: repairOfferIdentifier))
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

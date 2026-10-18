//
//  TmuxWorkgroupEndToEndHarness.swift
//  iTerm2 ModernTests
//
//  End-to-end harness for workgroups in tmux Integration. NOT a unit test: it starts a private
//  tmux server and launches a real session running `tmux -CC attach`, so the test host enters real
//  tmux Integration mode with a real TmuxController and real tabs, then enters workgroups and
//  checks both what iTerm2 shows and what is on the server. It opens windows, so it also needs
//  ITERM2_ONSCREEN_TESTS=1 (see OnscreenTestGate). Run it with
//  ITERM2_ONSCREEN_TESTS=1 tools/run_tmux_workgroup_live.sh --e2e; otherwise every test skips.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class TmuxWorkgroupEndToEndHarness: XCTestCase, iTermWarningHandler {
    private var server: TmuxTestServer!
    private var gatewaySessions = [PTYSession]()
    private var workgroupIDs = [String]()
    /// Titles of warnings that would have put up a modal alert, which nobody is there to dismiss.
    private var warnings = [String]()
    private let timeout: TimeInterval = 30

    override func setUpWithError() throws {
        try super.setUpWithError()
        let environment = ProcessInfo.processInfo.environment
        guard environment["ITERM2_TMUX_E2E"] == "1" else {
            throw XCTSkip("End-to-end harness; run tools/run_tmux_workgroup_live.sh --e2e")
        }
        // It opens real windows in the test host.
        try OnscreenTestGate.skipUnlessEnabled()
        let path = environment["ITERM2_TMUX_PATH"] ?? "/opt/homebrew/bin/tmux"
        try MainActor.assumeIsolated {
            // A run killed before its tear-down leaves its workgroups saved, and one with the
            // shape of an instance on the server would be adopted with it.
            for workgroup in iTermWorkgroupModel.instance.workgroups where workgroup.uniqueIdentifier.hasPrefix("e2e-") {
                iTermWorkgroupModel.instance.remove(uniqueIdentifier: workgroup.uniqueIdentifier)
            }
            server = try TmuxTestServer(tmuxPath: path)
        }
        iTermWarning.setWarningHandler(self)
    }

    func warningWouldShow(_ alert: NSAlert, identifier: String?) -> NSApplication.ModalResponse {
        warnings.append("\(identifier ?? "nil"): \(alert.informativeText)")
        return .alertFirstButtonReturn
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            for id in workgroupIDs {
                for instance in iTermWorkgroupController.instance.allInstances where instance.workgroupUniqueIdentifier == id {
                    if let leader = instance.mainSession {
                        iTermWorkgroupController.instance.exit(on: leader)
                    }
                }
                iTermWorkgroupModel.instance.remove(uniqueIdentifier: id)
            }
            for session in gatewaySessions {
                session.tmuxController?.detach()
            }
            server?.kill()
            for session in gatewaySessions {
                // Find the window first: a terminated session no longer knows it.
                let window = session.delegate?.realParentWindow()?.window
                session.terminate()
                window?.close()
            }
            gatewaySessions = []
            // Every test ends with no window left without a session, which is what a user would
            // see after detaching or exiting.
            let deadline = Date(timeIntervalSinceNow: 10)
            while !windowsWithAnEmptyTab().isEmpty && Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            let empty = windowsWithAnEmptyTab()
            XCTAssertEqual(empty, [], "windows left without a session")
            for terminal in (iTermController.sharedInstance()?.terminals() as? [PseudoTerminal]) ?? []
                where empty.contains(terminal.debugDescription) {
                terminal.window?.close()
            }
        }
        XCTAssertEqual(warnings, [], "Warnings would have put up modal alerts")
        // nil, though declared nonnull, is how alerts are shown again.
        _ = (iTermWarning.self as AnyObject).perform(#selector(iTermWarning.setWarningHandler(_:)), with: nil)
        super.tearDown()
    }

    // MARK: - Helpers

    private func waitUntil(_ what: String,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () throws -> Bool) rethrows {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while try !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(what)", file: file, line: line)
                return
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    /// Attaches the test host to the private server and returns the gateway session once the
    /// initial windows are open and the leader pane (%0) has its session.
    private func attach(waitingForLeader: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) throws -> PTYSession {
        var profile = (ProfileModel.sharedInstance()?.defaultProfile() as? [AnyHashable: Any]) ?? [:]
        profile[KEY_GUID] = UUID().uuidString
        profile[KEY_NAME] = "tmux workgroup e2e"
        profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeCustomValue
        profile[KEY_COMMAND_LINE] = ([server.tmuxPath] + server.baseArguments + ["-CC", "attach", "-t", "s"])
            .joined(separator: " ")
        var launched: PTYSession?
        iTermSessionLauncher.launchBookmark(profile, in: nil, respectTabbingMode: false) { launched = $0 }
        waitUntil("the gateway session to launch", file: file, line: line) { launched != nil }
        let gateway = try XCTUnwrap(launched, file: file, line: line)
        // Tear-down kills the server, which ends the gateway, often within the few seconds that
        // count as a short-lived session. The modal warning about that would stall the run.
        gateway.isSingleUseSession = true
        gatewaySessions.append(gateway)
        if waitingForLeader {
            waitUntil("the leader pane's session", file: file, line: line) {
                gateway.tmuxController?.session(forWindowPane: 0) != nil || gateway.exited
            }
            if gateway.exited {
                // tmux -CC quit instead of attaching; what it printed says why.
                XCTFail("tmux -CC attach exited:\n\(gateway.screen.compactLineDumpWithContinuationMarks())",
                        file: file, line: line)
            }
        } else {
            waitUntil("the initial windows", file: file, line: line) { gateway.tmuxController?.workgroupAttacher != nil }
        }
        return gateway
    }

    private func leader(_ gateway: PTYSession) throws -> PTYSession {
        return try XCTUnwrap(gateway.tmuxController?.session(forWindowPane: 0))
    }

    private func config(_ id: String, _ kind: iTermWorkgroupSessionConfig.Kind, parent: String?,
                        toolbarItems: [iTermWorkgroupToolbarItem] = [],
                        command: String = "exec sleep 86400",
                        mode: iTermWorkgroupSessionMode = .regular) -> iTermWorkgroupSessionConfig {
        return iTermWorkgroupSessionConfig(uniqueIdentifier: id, parentID: parent, kind: kind, profileGUID: nil,
                                           command: command, urlString: "", toolbarItems: toolbarItems,
                                           displayName: id, mode: mode)
    }

    /// A root with a split and a tab, added to the model for the test.
    private func addSplitAndTabWorkgroup() -> iTermWorkgroup {
        let id = "e2e-" + UUID().uuidString
        let workgroup = iTermWorkgroup(uniqueIdentifier: id, name: "E2E", sessions: [
            config(id + ".root", .root, parent: nil),
            config(id + ".split", .split(SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)),
                   parent: id + ".root"),
            config(id + ".tab", .tab, parent: id + ".root"),
        ])
        iTermWorkgroupModel.instance.add(workgroup)
        workgroupIDs.append(id)
        return workgroup
    }

    /// Pane IDs and tags as the server has them.
    private func tags() throws -> [Int: String] {
        var result = [Int: String]()
        for line in try server.lines(["list-panes", "-s", "-t", "s", "-F", "#{pane_id} #{@iterm2_wg}"]) {
            let fields = line.split(separator: " ", maxSplits: 1)
            if let pane = Int(fields[0].dropFirst()), fields.count == 2 {
                result[pane] = String(fields[1])
            }
        }
        return result
    }

    private func records() throws -> [String] {
        return try server.lines(["show", "-t", "s"]).filter { $0.hasPrefix(TmuxWorkgroupState.instanceOptionName(instanceID: "")) }
    }

    // MARK: - Parked panes

    /// Text on a session's screen.
    private func screenText(_ session: PTYSession) -> String {
        var text = ""
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            text = mutableState.currentGrid.compactLineDump()
        })
        return text
    }

    /// A pane in a window parked for instance "X", printing a counter, created the way a peer is.
    private func makeParkedCounter() throws -> Int {
        let tag = TmuxWorkgroupState.ParkedTag(instanceID: "X").encoded
        let script = "i=0; while :; do i=$((i+1)); echo COUNTER-$i; sleep 0.2; done"
        let reply = try server.lines(["new-window", "-d", "-a", "-t", "s:{end}", "-P", "-F", "#{pane_id}", "sh", "-c", script,
                                      ";", "set", "-w", "-t", "s:{end}", "@iterm2_wg_parked", tag])
        return try XCTUnwrap(Int(try XCTUnwrap(reply.first).dropFirst()))
    }

    // A parked pane is never a tab, but it has a session, buried, that keeps receiving its output.
    func testParkedPaneHasABuriedSessionThatReceivesOutput() throws {
        let gateway = try attach()
        let controller = try XCTUnwrap(gateway.tmuxController)
        let parked = try makeParkedCounter()
        waitUntil("the parked pane's buried session") { controller.session(forWindowPane: Int32(parked)) != nil }
        let session = try XCTUnwrap(controller.session(forWindowPane: Int32(parked)))
        XCTAssertTrue(session.isTmuxBuried)
        XCTAssertNil(session.delegate, "no tab")
        let window = try server.int(["display", "-p", "-t", "%\(parked)", "#{window_id}"], prefix: "@")
        XCTAssertNil(controller.window(Int32(window)), "the parked window is not opened as a tab")
        waitUntil("output to keep arriving") { self.screenText(session).contains("COUNTER-10") }
    }

    // A swap-pane between a workgroup's leader and a parked peer (made directly in tmux, as another
    // client's switch would be) adopts the peer's own session into the tab and buries the leader's,
    // which stays alive and registered. Swapping back reverses it, with the same session objects
    // throughout, and the peer's output keeps arriving while it is in view.
    func testSwapAdoptsTheBuriedSessionAndBuriesTheLeader() throws {
        let gateway = try attach()
        let controller = try XCTUnwrap(gateway.tmuxController)
        let id = "e2e-" + UUID().uuidString
        let counter = "i=0; while :; do i=$((i+1)); echo COUNTER-$i; sleep 0.2; done"
        let workgroup = iTermWorkgroup(uniqueIdentifier: id, name: "E2E counter", sessions: [
            config(id + ".root", .root, parent: nil, toolbarItems: [.modeSwitcher]),
            config(id + ".p1", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher], command: counter),
        ])
        iTermWorkgroupModel.instance.add(workgroup)
        workgroupIDs.append(id)
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: id, on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        waitUntil("the peer's session") { instance.peerPort.realizedPeerSessions.count == 2 }
        let peer = try XCTUnwrap(instance.peerPort.session(forIdentifier: id + ".p1"))
        let parked = Int(peer.tmuxPane)
        XCTAssertTrue(peer.isTmuxBuried)
        waitUntil("the parked peer's output") { self.screenText(peer).contains("COUNTER-") }
        let tab = try XCTUnwrap(leader.delegate as? PTYTab)

        _ = try server.lines(["swap-pane", "-d", "-s", "%0", "-t", "%\(parked)"])
        waitUntil("the peer to be adopted and the leader buried") { !peer.isTmuxBuried && leader.isTmuxBuried }
        XCTAssertTrue((peer.delegate as? PTYTab) === tab, "the peer's own session is in the leader's tab")
        XCTAssertTrue(controller.session(forWindowPane: Int32(parked)) === peer)
        XCTAssertTrue(controller.session(forWindowPane: 0) === leader, "the leader's session is still registered")
        XCTAssertFalse(leader.exited)
        XCTAssertTrue(leader.workgroupInstance === instance, "the instance is intact")
        let count = screenText(peer)
        waitUntil("the peer's output to keep arriving in the tab") { self.screenText(peer) != count }

        _ = try server.lines(["swap-pane", "-d", "-s", "%\(parked)", "-t", "%0"])
        waitUntil("the leader to be adopted back") { !leader.isTmuxBuried && peer.isTmuxBuried }
        XCTAssertTrue((leader.delegate as? PTYTab) === tab)
        XCTAssertFalse(peer.exited)
        XCTAssertTrue(controller.session(forWindowPane: Int32(parked)) === peer)
    }

    // MARK: - Peers

    /// A root with two peers, added to the model for the test.
    private func addPeersWorkgroup() -> iTermWorkgroup {
        let id = "e2e-" + UUID().uuidString
        // With the peer switcher, as real peer groups have: a toolbar changes the pane's geometry.
        let workgroup = iTermWorkgroup(uniqueIdentifier: id, name: "E2E peers", sessions: [
            config(id + ".root", .root, parent: nil, toolbarItems: [.modeSwitcher]),
            config(id + ".p1", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher]),
            config(id + ".p2", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher]),
        ])
        iTermWorkgroupModel.instance.add(workgroup)
        workgroupIDs.append(id)
        return workgroup
    }

    private func parkedWindowCount() throws -> Int {
        return try server.lines(["list-windows", "-t", "s", "-F", "#{@iterm2_wg_parked}"]).filter { !$0.isEmpty }.count
    }

    // Entering a workgroup with peers in a tmux tab creates each peer as a pane parked in a hidden
    // window of its own, with a buried session here. Switching through the peer port swaps panes in
    // tmux and the tab follows, with the same sessions throughout; Exit Workgroup removes it all.
    func testPeers() throws {
        let gateway = try attach()
        let workgroup = addPeersWorkgroup()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        let port = instance.peerPort
        let p1 = workgroup.uniqueIdentifier + ".p1"
        let p2 = workgroup.uniqueIdentifier + ".p2"
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        let peer1 = try XCTUnwrap(port.session(forIdentifier: p1))
        let peer2 = try XCTUnwrap(port.session(forIdentifier: p2))
        XCTAssertTrue(peer1.isTmuxBuried && peer2.isTmuxBuried, "parked peers have buried sessions")
        XCTAssertEqual(try parkedWindowCount(), 2, "one hidden window per parked peer")
        XCTAssertTrue(peer1.workgroupInstance === instance)

        // What the slot shows with the leader in it, toolbar included.
        let leaderGeometry = geometry(leader)

        XCTAssertTrue(port.activate(identifier: p1))
        waitUntil("the first peer in view") { !peer1.isTmuxBuried && leader.isTmuxBuried }
        XCTAssertTrue((peer1.delegate as? PTYTab) != nil)
        XCTAssertEqual(port.activeSessionIdentifier, p1)
        // The incoming peer fills the slot exactly as the leader did, toolbar included, so no rows
        // end up under the toolbar.
        waitUntil("the peer's layout to settle") { self.geometry(peer1) == leaderGeometry }
        XCTAssertEqual(geometry(peer1), leaderGeometry)
        XCTAssertEqual(peer1.rows, leader.rows)

        XCTAssertTrue(port.activate(identifier: p2))
        waitUntil("the second peer in view") { !peer2.isTmuxBuried && peer1.isTmuxBuried }
        XCTAssertEqual(port.activeSessionIdentifier, p2)

        XCTAssertTrue(port.activate(identifier: workgroup.uniqueIdentifier + ".root"))
        waitUntil("the leader back in view") { !leader.isTmuxBuried && peer2.isTmuxBuried }
        XCTAssertFalse(peer1.exited || peer2.exited || leader.exited)

        let instanceID = instance.instanceUniqueIdentifier
        iTermWorkgroupController.instance.exit(on: leader)
        try waitUntil("the server to forget the instance") { try records().isEmpty && tags().isEmpty }
        try waitUntil("the parked windows to close") { try parkedWindowCount() == 0 }
        XCTAssertFalse(iTermWorkgroupController.instance.allInstances.contains { $0.instanceUniqueIdentifier == instanceID },
                       "the client that ended it never adopts it again while it is being removed")
        XCTAssertEqual(try server.lines(["list-panes", "-s", "-t", "s", "-F", "#{pane_id}"]), ["%0"])
    }

    // The slot changes size (the user makes the window bigger): every parked peer is pinned to the
    // new size, so switching to one resizes nothing.
    func testParkedPeersFollowTheSlotsSize() throws {
        let gateway = try attach()
        let workgroup = addPeersWorkgroup()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let port = try XCTUnwrap(leader.workgroupInstance).peerPort
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        let peers = try [".p1", ".p2"].map { try XCTUnwrap(port.session(forIdentifier: workgroup.uniqueIdentifier + $0)) }
        func size(_ session: PTYSession) throws -> String? {
            return try server.lines(["display", "-p", "-t", "%\(session.tmuxPane)", "#{pane_width}x#{pane_height}"]).first
        }
        let before = try XCTUnwrap(try size(leader))
        let window = try XCTUnwrap(leader.delegate?.realParentWindow()?.window)
        var frame = window.frame
        frame.size.width += 200
        frame.size.height += 100
        window.setFrame(frame, display: true)
        try waitUntil("tmux to resize the slot") { try size(leader) != before }
        let after = try XCTUnwrap(try size(leader))
        try waitUntil("the parked peers to be pinned to the new size") {
            try peers.allSatisfy { try size($0) == after }
        }
    }

    /// What a session's slot shows: its view, scroll view, visible area and Metal view.
    private func geometry(_ session: PTYSession) -> [NSRect] {
        guard let view = session.view else {
            return []
        }
        return [view.frame, view.scrollview.frame,
                NSRect(origin: .zero, size: view.scrollview.documentVisibleRect.size),
                view.metalView?.frame ?? .zero]
    }

    // Another client switches peers (here tmux does it directly, as that client's guarded swap
    // would). This client follows the layout, and the incoming peer fills the slot exactly as the
    // leader did, toolbar included, rather than being laid out first and given its toolbar after.
    func testAnotherClientsSwitchIsFollowedWithTheSameLayout() throws {
        let gateway = try attach()
        let workgroup = addPeersWorkgroup()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let port = try XCTUnwrap(leader.workgroupInstance).peerPort
        let p1 = workgroup.uniqueIdentifier + ".p1"
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        let peer1 = try XCTUnwrap(port.session(forIdentifier: p1))
        waitUntil("the leader's toolbar") { leader.view?.scrollview.frame.height ?? 0 < leader.view?.frame.height ?? 0 }
        let leaderGeometry = geometry(leader)
        let leaderRows = leader.rows

        _ = try server.lines(["swap-pane", "-d", "-s", "%0", "-t", "%\(peer1.tmuxPane)"])
        waitUntil("the peer in view") { !peer1.isTmuxBuried && leader.isTmuxBuried }
        waitUntil("the port to follow") { port.activeSessionIdentifier == p1 }
        waitUntil("the peer's layout to settle") { self.geometry(peer1) == leaderGeometry && peer1.rows == leaderRows }
        XCTAssertEqual(geometry(peer1), leaderGeometry)
        XCTAssertEqual(peer1.rows, leaderRows)
    }

    // Reattaching adopts the peers' panes: parked ones get buried sessions and the port can switch.
    func testPeersAreAdoptedOnReattach() throws {
        let gateway = try attach()
        let workgroup = addPeersWorkgroup()
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: try leader(gateway), mechanism: .menu))
        let port = try XCTUnwrap(try leader(gateway).workgroupInstance).peerPort
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        let p1 = workgroup.uniqueIdentifier + ".p1"
        XCTAssertTrue(port.activate(identifier: p1))
        waitUntil("the first peer in view") { port.session(forIdentifier: p1)?.isTmuxBuried == false }

        gateway.tmuxController?.detach()
        waitUntil("the client to detach") { gateway.tmuxController == nil || gateway.tmuxController?.isAttached == false }

        let again = try attach()
        let controller = try XCTUnwrap(again.tmuxController)
        // The leader is parked now, so its session is buried.
        waitUntil("the instance to be adopted") {
            controller.session(forWindowPane: 0)?.workgroupInstance?.peerPort.realizedPeerSessions.count == 3
        }
        let adopted = try XCTUnwrap(controller.session(forWindowPane: 0)?.workgroupInstance)
        XCTAssertEqual(adopted.peerPort.activeSessionIdentifier, p1, "the peer in view is the active one")
        let leaderAgain = try XCTUnwrap(controller.session(forWindowPane: 0))
        XCTAssertTrue(leaderAgain.isTmuxBuried)
        XCTAssertTrue(adopted.peerPort.activate(identifier: workgroup.uniqueIdentifier + ".root"))
        waitUntil("the leader back in view") { !leaderAgain.isTmuxBuried }
    }

    /// Windows that have no session left in some tab, or none at all.
    private func windowsWithAnEmptyTab() -> [String] {
        let terminals = (iTermController.sharedInstance()?.terminals() as? [PseudoTerminal]) ?? []
        return terminals.compactMap { terminal in
            let tabs = terminal.tabs() ?? []
            if tabs.isEmpty || tabs.contains(where: { ($0.sessions() ?? []).isEmpty }) {
                return terminal.debugDescription
            }
            return nil
        }
    }

    // Detaching while a peer is in view ends the workgroup on this Mac, starting from the
    // leader, which is buried. Its teardown used to terminate the peer in view where it stood,
    // leaving its window with no session in it.
    func testDetachingWithAPeerInViewLeavesNoEmptyWindow() throws {
        let gateway = try attach()
        let workgroup = addPeersWorkgroup()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let port = try XCTUnwrap(leader.workgroupInstance).peerPort
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        let leaderGeometry = geometry(leader)
        let p1 = workgroup.uniqueIdentifier + ".p1"
        XCTAssertTrue(port.activate(identifier: p1))
        let inView = try XCTUnwrap(port.session(forIdentifier: p1))
        waitUntil("the first peer in view") { !inView.isTmuxBuried && leader.isTmuxBuried }
        // Let the swap's layout update finish, so nothing from it arrives after the detach.
        waitUntil("the peer's layout to settle") { self.geometry(inView) == leaderGeometry }
        XCTAssertEqual(windowsWithAnEmptyTab(), [])
        // As when the profile's session end action is No Action: the peer stays on screen
        // after detaching, showing that tmux detached, rather than closing itself.
        inView.forceDefaultEndAction = true

        gateway.tmuxController?.detach()
        waitUntil("the client to detach") { gateway.tmuxController == nil || gateway.tmuxController?.isAttached == false }
        waitUntil("the workgroup to end") { inView.workgroupInstance == nil }
        // A tab closing happens on a later pass of the run loop.
        waitUntil("no window to be left without a session") { self.windowsWithAnEmptyTab().isEmpty }
    }

    // MARK: - Entry, exit, adoption (14b)

    // Entering a workgroup in a tmux tab creates its split and tab as tmux panes running on the
    // server, tagged there, and adopts their sessions; Exit Workgroup removes them from the server.
    func testEnterAndExit() throws {
        let gateway = try attach()
        let workgroup = addSplitAndTabWorkgroup()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        waitUntil("both members to arrive") { instance.nonPeerSessions.count == 2 }
        XCTAssertTrue(instance.nonPeerSessions.allSatisfy { $0.isTmuxClient }, "members are tmux panes")
        XCTAssertEqual(try records().count, 1)
        XCTAssertEqual(try tags().count, 3, "leader, split and tab are tagged")

        iTermWorkgroupController.instance.exit(on: leader)
        XCTAssertNil(leader.workgroupInstance)
        try waitUntil("the server to forget the instance") { try records().isEmpty && tags().isEmpty }
        XCTAssertEqual(try server.lines(["list-panes", "-s", "-t", "s", "-F", "#{pane_id}"]), ["%0"],
                       "only the leader's pane is left")
    }

    // The leader's program exits (its pane closes, as when the shell exits): the workgroup ends,
    // here and on the server, members and parked peers included. Reported 2026-10-09: a tab with a
    // split and the parked peers stayed behind.
    func testTheLeaderExitingEndsTheWorkgroupOnTheServer() throws {
        let id = "e2e-" + UUID().uuidString
        let workgroup = iTermWorkgroup(uniqueIdentifier: id, name: "E2E leader exits", sessions: [
            config(id + ".root", .root, parent: nil, toolbarItems: [.modeSwitcher]),
            config(id + ".p1", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher]),
            config(id + ".p2", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher]),
            config(id + ".tab", .tab, parent: id + ".root"),
            config(id + ".tabsplit", .split(SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)),
                   parent: id + ".tab"),
        ])
        iTermWorkgroupModel.instance.add(workgroup)
        workgroupIDs.append(id)
        let gateway = try attach()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: id, on: leader, mechanism: .menu))
        // Held weakly, as nothing but the workgroup controller holds an instance in the app: the
        // cleanup must not depend on the ended instance (or its binding) staying alive.
        weak var instance = leader.workgroupInstance
        waitUntil("every member") {
            instance?.nonPeerSessions.count == 2 && instance?.peerPort.realizedPeerSessions.count == 3
        }
        XCTAssertEqual(try tags().count, 5)

        _ = try server.lines(["kill-pane", "-t", "%\(leader.tmuxPane)"])
        try waitUntil("the server to forget the instance") { try records().isEmpty && tags().isEmpty }
        try waitUntil("the parked windows to close") { try parkedWindowCount() == 0 }
        try waitUntil("the members' panes to close") {
            try self.server.lines(["list-panes", "-s", "-t", "s", "-F", "#{pane_id}"]).isEmpty
        }
        XCTAssertTrue(instance?.didTeardown ?? true)
    }

    // Detaching only forgets the instance here; reattaching adopts it again with its members.
    func testDetachLeavesTheServerAloneAndReattachAdopts() throws {
        let gateway = try attach()
        let workgroup = addSplitAndTabWorkgroup()
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: try leader(gateway), mechanism: .menu))
        let instance = try XCTUnwrap(try leader(gateway).workgroupInstance)
        waitUntil("both members to arrive") { instance.nonPeerSessions.count == 2 }
        let tagsBefore = try tags()

        gateway.tmuxController?.detach()
        waitUntil("the client to detach") { gateway.tmuxController == nil || gateway.tmuxController?.isAttached == false }
        XCTAssertEqual(try records().count, 1, "detaching leaves the record")
        XCTAssertEqual(try tags(), tagsBefore, "and the tags")

        let again = try attach()
        try waitUntil("the instance to be adopted") {
            try leader(again).workgroupInstance?.nonPeerSessions.count == 2
        }
        let adopted = try XCTUnwrap(try leader(again).workgroupInstance)
        XCTAssertEqual(adopted.workgroupUniqueIdentifier, workgroup.uniqueIdentifier)
        XCTAssertEqual(adopted.instanceUniqueIdentifier, instance.instanceUniqueIdentifier)
    }

    // MARK: - Hidden panes no workgroup here can show

    /// Enters a workgroup whose two peers print a marker, detaches, forgets the workgroup (as on a
    /// Mac that never had it) and attaches again. Returns the new gateway, the instance ID, and
    /// the peers' pane IDs.
    private func attachToAnUnknownWorkgroup() throws -> (PTYSession, String, [Int]) {
        let gateway = try attach()
        let id = "e2e-" + UUID().uuidString
        let workgroup = iTermWorkgroup(uniqueIdentifier: id, name: "E2E unknown", sessions: [
            config(id + ".root", .root, parent: nil, toolbarItems: [.modeSwitcher]),
            config(id + ".p1", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher],
                   command: "echo PEER-ONE; exec sleep 86400"),
            config(id + ".p2", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher],
                   command: "echo PEER-TWO; exec sleep 86400"),
        ])
        iTermWorkgroupModel.instance.add(workgroup)
        workgroupIDs.append(id)
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: id, on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        waitUntil("both peers' sessions") { instance.peerPort.realizedPeerSessions.count == 3 }
        let instanceID = instance.instanceUniqueIdentifier
        let peers = try [".p1", ".p2"].map { Int(try XCTUnwrap(instance.peerPort.session(forIdentifier: id + $0)).tmuxPane) }

        gateway.tmuxController?.detach()
        waitUntil("the client to detach") { gateway.tmuxController == nil || gateway.tmuxController?.isAttached == false }
        iTermWorkgroupModel.instance.remove(uniqueIdentifier: id)
        return (try attach(), instanceID, peers)
    }

    private func hiddenPaneOffer(in session: PTYSession?, instanceID: String) -> Bool {
        return session?.hasAnnouncement(withIdentifier: TmuxWorkgroupHiddenPaneOffer.announcementIdentifier(instanceID: instanceID)) ?? false
    }

    /// Panes on the server.
    private func paneIDs() throws -> Set<Int> {
        return Set(try server.lines(["list-panes", "-s", "-t", "s", "-F", "#{pane_id}"]).compactMap { Int($0.dropFirst()) })
    }

    // Peers of a workgroup this Mac doesn't have would be hidden forever, so the leader offers
    // them. Opening shows each in a tab of its own, with what it printed, and untags it, so no
    // workgroup parks it again.
    func testUnknownWorkgroupsPeersOpenInTabs() throws {
        let (gateway, instanceID, peers) = try attachToAnUnknownWorkgroup()
        let controller = try XCTUnwrap(gateway.tmuxController)
        let leader = try leader(gateway)
        XCTAssertNil(leader.workgroupInstance, "nothing here adopts it")
        waitUntil("the offer in the leader") { self.hiddenPaneOffer(in: leader, instanceID: instanceID) }

        XCTAssertTrue(leader.debugSelectAction(0, ofAnnouncementWithIdentifier:
            TmuxWorkgroupHiddenPaneOffer.announcementIdentifier(instanceID: instanceID)))
        try waitUntil("the peers to be in tabs") {
            try peers.allSatisfy { paneID in
                let session = controller.session(forWindowPane: Int32(paneID))
                return session?.delegate != nil && session?.isTmuxBuried == false
            } && parkedWindowCount() == 0
        }
        for (paneID, marker) in zip(peers, ["PEER-ONE", "PEER-TWO"]) {
            let session = try XCTUnwrap(controller.session(forWindowPane: Int32(paneID)))
            waitUntil("\(marker) on screen") { self.screenText(session).contains(marker) }
        }
        let tags = try tags()
        XCTAssertTrue(peers.allSatisfy { tags[$0] == nil }, "the peers are untagged: \(tags)")
        XCTAssertNotNil(tags[0], "the leader keeps its tag, for Macs that have the workgroup")
        XCTAssertFalse(hiddenPaneOffer(in: leader, instanceID: instanceID))
    }

    func testUnknownWorkgroupsPeersCanBeStopped() throws {
        let (gateway, instanceID, peers) = try attachToAnUnknownWorkgroup()
        let controller = try XCTUnwrap(gateway.tmuxController)
        let leader = try leader(gateway)
        waitUntil("the offer in the leader") { self.hiddenPaneOffer(in: leader, instanceID: instanceID) }

        XCTAssertTrue(leader.debugSelectAction(1, ofAnnouncementWithIdentifier:
            TmuxWorkgroupHiddenPaneOffer.announcementIdentifier(instanceID: instanceID)))
        try waitUntil("the peers to be gone from the server") { try self.paneIDs().isDisjoint(with: peers) }
        try waitUntil("their parked windows to close") { try parkedWindowCount() == 0 }
        waitUntil("their sessions to end") { peers.allSatisfy { controller.session(forWindowPane: Int32($0)) == nil } }
        XCTAssertTrue(try paneIDs().contains(0), "the leader is untouched")
        XCTAssertEqual(controller.clientSessions().count, 1, "no tab was opened")
    }

    // A parked window left by a workgroup that has ended is offered too, in a tab of this
    // connection since there is no leader.
    func testAParkedWindowLeftByAnEndedWorkgroupOpensInATab() throws {
        let gateway = try attach()
        let controller = try XCTUnwrap(gateway.tmuxController)
        let parked = try makeParkedCounter()
        let host = try leader(gateway)
        waitUntil("the offer") { self.hiddenPaneOffer(in: host, instanceID: "X") }

        XCTAssertTrue(host.debugSelectAction(0, ofAnnouncementWithIdentifier:
            TmuxWorkgroupHiddenPaneOffer.announcementIdentifier(instanceID: "X")))
        waitUntil("the pane in a tab") { controller.session(forWindowPane: Int32(parked))?.delegate != nil }
        let session = try XCTUnwrap(controller.session(forWindowPane: Int32(parked)))
        XCTAssertFalse(session.isTmuxBuried)
        let count = screenText(session)
        waitUntil("its output to keep arriving") { self.screenText(session) != count && self.screenText(session).contains("COUNTER-") }
        XCTAssertEqual(try parkedWindowCount(), 0)
    }

    // MARK: - Code review, diff and Reload (14c part 4)

    /// A directory the members' commands write into, to show what ran.
    private func outputDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iterm2wg-e2e-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        // tmux reports the real path (/private/var, not /var).
        guard let real = realpath(url.path, nil) else {
            return url.path
        }
        defer { free(real) }
        return String(cString: real)
    }

    private func contents(_ path: String) -> String? {
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// A root with a diff peer and a code review peer, like the Claude Code preset. Each one's
    /// command records that it ran in `directory`.
    private func addReviewWorkgroup(directory: String) -> iTermWorkgroup {
        let id = "e2e-" + UUID().uuidString
        let review = "printf '%s' \\(codeReviewPrompt) > '\(directory)/prompt'; " +
            "cp '\\(codeReviewSystemPromptFile)' '\(directory)/system-prompt'; " +
            "cp '\\(codeReviewSettingsFile)' '\(directory)/settings'; exec sleep 86400"
        let workgroup = iTermWorkgroup(uniqueIdentifier: id, name: "E2E review", sessions: [
            config(id + ".root", .root, parent: nil, toolbarItems: [.modeSwitcher]),
            config(id + ".diff", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher],
                   command: "echo diffed >> '\(directory)/diff'; exec sleep 86400", mode: .diff),
            config(id + ".review", .peer, parent: id + ".root", toolbarItems: [.modeSwitcher],
                   command: review, mode: .codeReview),
        ])
        iTermWorkgroupModel.instance.add(workgroup)
        workgroupIDs.append(id)
        return workgroup
    }

    /// Whether the member at a position is waiting, from its tag on the server.
    private func isWaiting(_ position: Int, of instance: iTermWorkgroupInstance) throws -> Bool {
        let id = instance.instanceUniqueIdentifier
        let tag = try tags().values.compactMap { TmuxWorkgroupState.PaneTag(encoded: $0) }
            .first { $0.instanceID == id && $0.position == position }
        return try XCTUnwrap(tag, "no member at \(position)").waiting
    }

    /// Starting a member replaces its pane and session before tmux 3.8, so the members are looked
    /// up each time.
    private struct ReviewWorkgroup {
        static let diffPosition = 1
        static let reviewPosition = 2
        var instance: iTermWorkgroupInstance
        var diffID: String
        var reviewID: String
        var diff: PTYSession { instance.peerPort.session(forIdentifier: diffID)! }
        var review: PTYSession { instance.peerPort.session(forIdentifier: reviewID)! }
    }

    private func enterReviewWorkgroup(_ gateway: PTYSession, directory: String) throws -> ReviewWorkgroup {
        let workgroup = addReviewWorkgroup(directory: directory)
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        let port = instance.peerPort
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        return ReviewWorkgroup(instance: instance,
                               diffID: workgroup.uniqueIdentifier + ".diff",
                               reviewID: workgroup.uniqueIdentifier + ".review")
    }

    // A code review peer waits behind its prompt overlay, running nothing. Start evaluates the
    // command then, with its input files written on the server under the server's home, and runs it
    // in the peer's pane.
    func testCodeReviewPeerStartsOnStart() throws {
        let directory = try outputDirectory()
        let home = directory + "/home"
        _ = try server.lines(["set-environment", "-g", "HOME", home])
        let gateway = try attach()
        let w = try enterReviewWorkgroup(gateway, directory: directory)
        waitUntil("the review's prompt overlay") { w.review.view?.codeReviewPromptOverlay != nil }
        XCTAssertTrue(try isWaiting(ReviewWorkgroup.reviewPosition, of: w.instance))
        XCTAssertNil(contents(directory + "/prompt"), "nothing runs before Start")

        let overlay = try XCTUnwrap(w.review.view?.codeReviewPromptOverlay)
        overlay.onStart?("Review it’s “code” 100%")
        waitUntil("the review to run") { self.contents(directory + "/settings") != nil }
        XCTAssertEqual(contents(directory + "/prompt"), "Review it’s “code” 100%")
        let systemPrompt = CodeReviewIt2.substitute(
            iTermPreferences.string(forKey: kPreferenceKeyAIPromptCodeReviewSystem) ?? "",
            command: CodeReviewIt2.command(onRemoteHost: false, bundlePath: Bundle.main.bundlePath))
        XCTAssertEqual(contents(directory + "/system-prompt"), systemPrompt)
        XCTAssertNotNil(contents(home + "/.iterm2/code-review/settings.txt"), "inputs are under the server's home")
        XCTAssertFalse(try isWaiting(ReviewWorkgroup.reviewPosition, of: w.instance))
        XCTAssertNil(overlay.superview, "Start dismissed the overlay")
    }

    // A diff peer waits for changes. When its launch fires it runs in the peer's pane, once.
    func testDiffPeerStartsWhenItsLaunchFires() throws {
        let directory = try outputDirectory()
        let gateway = try attach()
        let w = try enterReviewWorkgroup(gateway, directory: directory)
        waitUntil("the diff's pending launch") { w.diff.hasPendingDiffLaunch }
        XCTAssertTrue(try isWaiting(ReviewWorkgroup.diffPosition, of: w.instance))
        w.diff.firePendingDiffLaunch()
        waitUntil("the diff to run") { self.contents(directory + "/diff") != nil }
        try waitUntil("the diff to be started on the server") { try !self.isWaiting(ReviewWorkgroup.diffPosition, of: w.instance) }
        XCTAssertEqual(contents(directory + "/diff"), "diffed\n")
        XCTAssertFalse(w.diff.hasPendingDiffLaunch)
    }

    // Another client started both (here tmux does it directly, as that client's claim would): this
    // client stops waiting, so it does not start them again.
    func testStartedElsewhereStopsWaitingHere() throws {
        let directory = try outputDirectory()
        let gateway = try attach()
        let w = try enterReviewWorkgroup(gateway, directory: directory)
        waitUntil("both to wait") { w.diff.hasPendingDiffLaunch && w.review.view?.codeReviewPromptOverlay != nil }
        for session in [w.diff, w.review] {
            let tag = try XCTUnwrap(TmuxWorkgroupState.PaneTag(encoded: try XCTUnwrap(tags()[Int(session.tmuxPane)])))
            _ = try server.lines(["set", "-p", "-t", "%\(session.tmuxPane)", "@iterm2_wg", tag.started.encoded])
        }
        waitUntil("both to stop waiting") {
            !w.diff.hasPendingDiffLaunch && w.diff.view?.diffWaitingPromptOverlay == nil &&
                w.review.view?.codeReviewPromptOverlay == nil
        }
    }

    // Reattaching to members still waiting waits again here; ones already started do not.
    func testReattachWaitsOnlyForMembersStillWaiting() throws {
        let directory = try outputDirectory()
        let gateway = try attach()
        let w = try enterReviewWorkgroup(gateway, directory: directory)
        waitUntil("the diff's pending launch") { w.diff.hasPendingDiffLaunch }
        w.diff.firePendingDiffLaunch()
        try waitUntil("the diff to be started") { try !self.isWaiting(ReviewWorkgroup.diffPosition, of: w.instance) }

        try waitUntil("this client to have the started diff's session") {
            try Int(w.diff.tmuxPane) == self.pane(atPosition: ReviewWorkgroup.diffPosition,
                                                  instanceID: w.instance.instanceUniqueIdentifier)
        }
        let diffPane = w.diff.tmuxPane
        let reviewPane = w.review.tmuxPane
        gateway.tmuxController?.detach()
        waitUntil("the client to detach") { gateway.tmuxController == nil || gateway.tmuxController?.isAttached == false }
        let again = try attach()
        let controller = try XCTUnwrap(again.tmuxController)
        waitUntil("the instance to be adopted") {
            controller.session(forWindowPane: 0)?.workgroupInstance?.peerPort.realizedPeerSessions.count == 3
        }
        let diff = try XCTUnwrap(controller.session(forWindowPane: diffPane))
        let review = try XCTUnwrap(controller.session(forWindowPane: reviewPane))
        waitUntil("the review's prompt overlay") { review.view?.codeReviewPromptOverlay != nil }
        XCTAssertFalse(diff.hasPendingDiffLaunch, "the diff already started")
        XCTAssertEqual(contents(directory + "/diff"), "diffed\n", "and is not run again")
    }

    /// Whether relaunching keeps the member's pane (tmux 3.8 and later respawn it) rather than
    /// replacing it.
    private func respawns(_ gateway: PTYSession) throws -> Bool {
        return try XCTUnwrap(gateway.tmuxController?.gateway).versionAtLeastDecimalNumber(with: "3.8")
    }

    private func addSplitWorkgroup(directory: String) -> iTermWorkgroup {
        let id = "e2e-" + UUID().uuidString
        let workgroup = iTermWorkgroup(uniqueIdentifier: id, name: "E2E reload", sessions: [
            config(id + ".root", .root, parent: nil),
            config(id + ".split", .split(SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)),
                   parent: id + ".root", toolbarItems: [.reload(nil)],
                   command: "echo ran >> '\(directory)/split'; exec sleep 86400"),
        ])
        iTermWorkgroupModel.instance.add(workgroup)
        workgroupIDs.append(id)
        return workgroup
    }

    /// The server's pane at a member's position.
    private func pane(atPosition position: Int, instanceID: String) throws -> Int? {
        let tag = TmuxWorkgroupState.PaneTag(instanceID: instanceID, position: position).encoded
        return try tags().first { $0.value == tag }?.key
    }

    // Reload on a member reruns its command, now evaluated. Before tmux 3.8 its pane is replaced and
    // its session with it; the workgroup carries on with the new one, here and on the server.
    func testReloadRelaunchesASplit() throws {
        let directory = try outputDirectory()
        let workgroup = addSplitWorkgroup(directory: directory)
        let splitID = workgroup.uniqueIdentifier + ".split"
        let gateway = try attach()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        waitUntil("the split") { instance.nonPeerSessions.count == 1 && self.contents(directory + "/split") == "ran\n" }
        let split = try XCTUnwrap(instance.nonPeerSessions.first)
        XCTAssertTrue(split.canRelaunchWorkgroupMember)
        try assertMemberRelaunched(instance: instance, old: split, respawns: respawns(gateway),
                                   relaunch: { instance.workgroupNavigationDidTapReload(ownerPeerID: splitID) },
                                   member: { instance.nonPeerSessions.first })
        waitUntil("the split to run again") { self.contents(directory + "/split") == "ran\nran\n" }
        XCTAssertFalse(instance.toolbarItems(for: try XCTUnwrap(instance.nonPeerSessions.first)).isEmpty,
                       "the member keeps its toolbar")
    }

    /// The process running at a member's position, so a test can tell when it was relaunched.
    private func process(atPosition position: Int, instanceID: String) throws -> String? {
        guard let pane = try pane(atPosition: position, instanceID: instanceID) else {
            return nil
        }
        return try server.lines(["display", "-p", "-t", "%\(pane)", "#{pane_pid}"]).first
    }

    /// Relaunches a member with `relaunch`, then checks that the instance's member for its position
    /// is the session for the server's pane there: the same one if it was respawned, else a new
    /// one, with the old one gone. The instance lives on.
    private func assertMemberRelaunched(instance: iTermWorkgroupInstance,
                                        old: PTYSession,
                                        respawns: Bool,
                                        position: Int = 1,
                                        file: StaticString = #filePath, line: UInt = #line,
                                        relaunch: () throws -> Void,
                                        member: () -> PTYSession?) throws {
        let instanceID = instance.instanceUniqueIdentifier
        let before = try process(atPosition: position, instanceID: instanceID)
        try relaunch()
        try waitUntil("the member to be relaunched", file: file, line: line) {
            let now = try self.process(atPosition: position, instanceID: instanceID)
            return now != nil && now != before
        }
        try waitUntil("the member's session to be the one for its pane", file: file, line: line) {
            guard let pane = try self.pane(atPosition: position, instanceID: instance.instanceUniqueIdentifier),
                  let session = member() else {
                return false
            }
            return Int(session.tmuxPane) == pane && !session.exited
        }
        let session = try XCTUnwrap(member(), file: file, line: line)
        if respawns {
            XCTAssertTrue(session === old, "respawned in the same pane, with the same session", file: file, line: line)
        } else {
            XCTAssertFalse(session === old, "a replaced pane has a new session", file: file, line: line)
            waitUntil("the old session to end", file: file, line: line) { old.exited }
        }
        XCTAssertTrue(session.workgroupInstance === instance, file: file, line: line)
        XCTAssertFalse(instance.didTeardown, "the workgroup carries on", file: file, line: line)
        XCTAssertEqual(try records().count, 1, file: file, line: line)
    }

    // Reload on the peer in view. A replacement fills the slot as the old one did, toolbar
    // included, and the port switches to and from it as before.
    func testReloadRelaunchesAPeerInView() throws {
        let gateway = try attach()
        let workgroup = addPeersWorkgroup()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        let port = instance.peerPort
        let p1 = workgroup.uniqueIdentifier + ".p1"
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        let leaderGeometry = geometry(leader)
        XCTAssertTrue(port.activate(identifier: p1))
        let peer = try XCTUnwrap(port.session(forIdentifier: p1))
        waitUntil("the peer in view") { !peer.isTmuxBuried && leader.isTmuxBuried }

        let workgroupPort = try XCTUnwrap(port as? iTermWorkgroupPeerPort)
        try assertMemberRelaunched(instance: instance, old: peer, respawns: respawns(gateway),
                                   relaunch: { workgroupPort.workgroupNavigationDidTapReload(ownerPeerID: p1) },
                                   member: { port.session(forIdentifier: p1) })
        let relaunched = try XCTUnwrap(port.session(forIdentifier: p1))
        XCTAssertTrue(relaunched.delegate is PTYTab, "in the tab")
        XCTAssertEqual(port.activeSessionIdentifier, p1)
        waitUntil("the slot's layout to settle") { self.geometry(relaunched) == leaderGeometry }
        XCTAssertEqual(geometry(relaunched), leaderGeometry)

        XCTAssertTrue(port.activate(identifier: workgroup.uniqueIdentifier + ".root"))
        waitUntil("the leader back in view") { !leader.isTmuxBuried && relaunched.isTmuxBuried }
        XCTAssertTrue(port.activate(identifier: p1))
        waitUntil("the relaunched peer in view again") { !relaunched.isTmuxBuried }
    }

    // Another client replaces a member (as it does before tmux 3.8): this client follows, and its
    // workgroup carries on.
    func testAnotherClientsReplacementIsFollowed() throws {
        let directory = try outputDirectory()
        let workgroup = addSplitWorkgroup(directory: directory)
        let gateway = try attach()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        waitUntil("the split") { instance.nonPeerSessions.count == 1 }
        let split = try XCTUnwrap(instance.nonPeerSessions.first)

        let other = try TmuxTestClient(server: server)
        addTeardownBlock { other.stop() }
        var ready = false
        other.whenReady { ready = true }
        waitUntil("the other client to attach") { ready }
        try assertMemberRelaunched(instance: instance, old: split, respawns: false, relaunch: {
            var replies: [String?]?
            other.gateway.sendList(TmuxWorkgroupCommands.relaunchMember(
                paneID: Int(split.tmuxPane),
                script: "echo elsewhere >> '\(directory)/split'; exec sleep 86400",
                tag: TmuxWorkgroupState.PaneTag(instanceID: instance.instanceUniqueIdentifier, position: 1),
                method: .replace(sessionID: other.sessionID, instanceID: instance.instanceUniqueIdentifier),
                remainOnExit: false)) { replies = $0 }
            waitUntil("the other client's replacement") { replies != nil }
        }, member: { instance.nonPeerSessions.first })
        XCTAssertEqual(instance.nonPeerSessions.count, 1)
    }

    // MARK: - Nested peer groups

    /// A root with a split that hosts two peers of its own.
    private func addNestedPeersWorkgroup() -> iTermWorkgroup {
        let id = "e2e-" + UUID().uuidString
        let split = iTermWorkgroupSessionConfig.Kind.split(SplitSettings(orientation: .vertical, side: .trailingOrBottom,
                                                                          location: 0.5))
        let workgroup = iTermWorkgroup(uniqueIdentifier: id, name: "E2E nested", sessions: [
            config(id + ".root", .root, parent: nil),
            config(id + ".split", split, parent: id + ".root", toolbarItems: [.modeSwitcher]),
            config(id + ".sp1", .peer, parent: id + ".split", toolbarItems: [.modeSwitcher]),
            config(id + ".sp2", .peer, parent: id + ".split", toolbarItems: [.modeSwitcher]),
        ])
        iTermWorkgroupModel.instance.add(workgroup)
        workgroupIDs.append(id)
        return workgroup
    }

    // A split's own peers are tmux panes parked like the leader's, switching among them is a
    // guarded swap the tab follows, reattaching adopts the group with the peer in view active, and
    // Exit Workgroup removes it all.
    func testANestedPeerGroupLivesOnTheServer() throws {
        let gateway = try attach()
        let workgroup = addNestedPeersWorkgroup()
        let id = workgroup.uniqueIdentifier
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: id, on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        waitUntil("the split") { instance.nonPeerSessions.count == 1 }
        let host = try XCTUnwrap(instance.nonPeerSessions.first)
        XCTAssertTrue(host.isTmuxClient)
        let port = try XCTUnwrap(host.peerPort)
        waitUntil("the split's peers") { port.realizedPeerSessions.count == 3 }
        let sp1 = try XCTUnwrap(port.session(forIdentifier: id + ".sp1"))
        let sp2 = try XCTUnwrap(port.session(forIdentifier: id + ".sp2"))
        XCTAssertTrue(sp1.isTmuxClient && sp2.isTmuxClient, "the peers are tmux panes")
        XCTAssertTrue(sp1.isTmuxBuried && sp2.isTmuxBuried)
        XCTAssertEqual(try parkedWindowCount(), 2)
        XCTAssertEqual(try tags().count, 4, "leader, split and both peers are tagged")

        XCTAssertTrue(port.activate(identifier: id + ".sp1"))
        waitUntil("the split's first peer in view") { !sp1.isTmuxBuried && host.isTmuxBuried }
        XCTAssertEqual(port.activeSessionIdentifier, id + ".sp1")
        XCTAssertTrue((sp1.delegate as? PTYTab) === (leader.delegate as? PTYTab), "in the split's place")
        let sp1Pane = sp1.tmuxPane

        gateway.tmuxController?.detach()
        waitUntil("the client to detach") { gateway.tmuxController == nil || gateway.tmuxController?.isAttached == false }
        let again = try attach()
        let controller = try XCTUnwrap(again.tmuxController)
        waitUntil("the nested group to be adopted") {
            controller.session(forWindowPane: sp1Pane)?.peerPort?.realizedPeerSessions.count == 3
        }
        let adoptedPort = try XCTUnwrap(controller.session(forWindowPane: sp1Pane)?.peerPort)
        XCTAssertEqual(adoptedPort.activeSessionIdentifier, id + ".sp1", "the peer in view is the active one")
        let adoptedHost = try XCTUnwrap(adoptedPort.session(forIdentifier: id + ".split"))
        XCTAssertTrue(adoptedHost.isTmuxBuried)
        XCTAssertTrue(adoptedPort.activate(identifier: id + ".split"))
        waitUntil("the split back in view") { !adoptedHost.isTmuxBuried }

        let adopted = try XCTUnwrap(controller.session(forWindowPane: 0)?.workgroupInstance)
        iTermWorkgroupController.instance.exit(on: try XCTUnwrap(adopted.mainSession))
        try waitUntil("the server to forget the instance") { try records().isEmpty && tags().isEmpty }
        try waitUntil("the parked windows to close") { try parkedWindowCount() == 0 }
    }

    // MARK: - Repairs

    // Someone joined a parked peer into the leader's window (as a client that died mid-switch could
    // leave it). This client parks it again: the tab shows the leader alone, the peer's session is
    // buried and still the instance's, and switching to it works.
    func testAPeerJoinedIntoViewIsParkedAgain() throws {
        let gateway = try attach()
        let workgroup = addPeersWorkgroup()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        let port = instance.peerPort
        let p1 = workgroup.uniqueIdentifier + ".p1"
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        let peerPane = try XCTUnwrap(port.session(forIdentifier: p1)).tmuxPane

        _ = try server.lines(["join-pane", "-d", "-s", "%\(peerPane)", "-t", "%\(leader.tmuxPane)"])
        try waitUntil("the peer to be parked again") {
            try self.server.lines(["display", "-p", "-t", "%\(peerPane)", "#{@iterm2_wg_parked}"]).first ==
                TmuxWorkgroupState.ParkedTag(instanceID: instance.instanceUniqueIdentifier).encoded
        }
        waitUntil("the tab to show the leader alone") {
            (leader.delegate as? PTYTab)?.sessions().count == 1
        }
        let peer = try XCTUnwrap(port.session(forIdentifier: p1))
        waitUntil("the peer's session to be buried") { peer.isTmuxBuried }
        XCTAssertTrue(peer.workgroupInstance === instance)
        XCTAssertFalse(instance.didTeardown)
        // The client followed the peer into view when it was joined there, and follows the leader
        // back once the peer's pane is parked, which it learns of separately.
        waitUntil("the leader to be the peer in view") {
            port.activeSessionIdentifier == workgroup.uniqueIdentifier + ".root"
        }
        XCTAssertTrue(port.activate(identifier: p1))
        waitUntil("the peer in view") { !peer.isTmuxBuried && leader.isTmuxBuried }
    }

    // The peer in view exited while no iTerm2 was attached, so every remaining member is parked.
    // Reattaching brings the leader back in a tab and adopts the instance.
    func testWhenThePeerInViewIsGoneTheLeaderComesBack() throws {
        let gateway = try attach()
        let workgroup = addPeersWorkgroup()
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: try leader(gateway), mechanism: .menu))
        let instance = try XCTUnwrap(try leader(gateway).workgroupInstance)
        let port = instance.peerPort
        let p1 = workgroup.uniqueIdentifier + ".p1"
        waitUntil("both peers' sessions") { port.realizedPeerSessions.count == 3 }
        XCTAssertTrue(port.activate(identifier: p1))
        let peer = try XCTUnwrap(port.session(forIdentifier: p1))
        waitUntil("the peer in view") { !peer.isTmuxBuried }
        let peerPane = peer.tmuxPane

        gateway.tmuxController?.detach()
        waitUntil("the client to detach") { gateway.tmuxController == nil || gateway.tmuxController?.isAttached == false }
        _ = try server.lines(["kill-pane", "-t", "%\(peerPane)"])

        let again = try attach(waitingForLeader: false)
        let controller = try XCTUnwrap(again.tmuxController)
        try waitUntil("the leader back in a tab, with the instance adopted") {
            guard let leader = controller.session(forWindowPane: 0) else {
                return false
            }
            let records = try self.records()
            return !leader.isTmuxBuried && leader.delegate is PTYTab && leader.workgroupInstance != nil &&
                records.count == 1
        }
        let adopted = try XCTUnwrap(controller.session(forWindowPane: 0)?.workgroupInstance)
        XCTAssertEqual(adopted.instanceUniqueIdentifier, instance.instanceUniqueIdentifier)
        XCTAssertEqual(adopted.peerPort.activeSessionIdentifier, workgroup.uniqueIdentifier + ".root")
        XCTAssertEqual(try server.lines(["display", "-p", "-t", "%0", "#{@iterm2_wg_parked}"]), [],
                       "the leader is no longer in a parked window")
    }

    // MARK: - Waiting on another client's lock

    /// Another client, connected, holding the session's workgroup lock as if it were creating peers.
    private func holdLockInAnotherClient() throws -> TmuxTestClient {
        let other = try TmuxTestClient(server: server)
        addTeardownBlock { other.stop() }
        var ready = false
        other.whenReady { ready = true }
        waitUntil("the other client to attach") { ready }
        var identity: TmuxWorkgroupCommands.ClientIdentity?
        other.gateway.sendCommand(TmuxWorkgroupCommands.identityQuery, responseTarget: other.reply { reply in
            identity = reply.flatMap { TmuxWorkgroupCommands.ClientIdentity(reported: $0) }
        }, responseSelector: #selector(TmuxTestReply.handle(_:)))
        waitUntil("the other client's identity") { identity != nil }
        _ = try server.lines(["set", "-t", "s", TmuxWorkgroupCommands.lockOptionName, try XCTUnwrap(identity).lockValue])
        return other
    }

    private func lockValue() throws -> String? {
        return try server.option(TmuxWorkgroupCommands.lockOptionName)
    }

    private struct LockWait {
        var leader: PTYSession
        var port: PTYSessionPeerPort
        var identifier: String
    }

    /// Enters a workgroup with peers while another client holds the lock, and waits for the bar
    /// saying so.
    private func enterWhileLocked(_ gateway: PTYSession) throws -> LockWait {
        let workgroup = addPeersWorkgroup()
        let leader = try leader(gateway)
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: leader, mechanism: .menu))
        let instance = try XCTUnwrap(leader.workgroupInstance)
        let identifier = TmuxWorkgroupBinding.lockWaitAnnouncementIdentifier(instanceID: instance.instanceUniqueIdentifier)
        waitUntil("the bar saying it is waiting") { leader.hasAnnouncement(withIdentifier: identifier) }
        XCTAssertEqual(instance.peerPort.realizedPeerSessions.count, 1, "no peers while the lock is held")
        return LockWait(leader: leader, port: instance.peerPort, identifier: identifier)
    }

    // The other client finishes and releases the lock: this one wakes, creates its peers, and the
    // bar goes away.
    func testWaitsForAnotherClientsLock() throws {
        let gateway = try attach()
        _ = try holdLockInAnotherClient()
        let w = try enterWhileLocked(gateway)
        _ = try server.lines(["set", "-u", "-t", "s", TmuxWorkgroupCommands.lockOptionName])
        waitUntil("the peers") { w.port.realizedPeerSessions.count == 3 }
        waitUntil("the bar to go") { !w.leader.hasAnnouncement(withIdentifier: w.identifier) }
        try waitUntil("the lock to be released") { try self.lockValue() == nil }
    }

    // The holder goes away without releasing it: its lock is stale, and this client takes it.
    func testHolderDetachingWakesTheWaiter() throws {
        let gateway = try attach()
        let other = try holdLockInAnotherClient()
        let w = try enterWhileLocked(gateway)
        other.stop()
        waitUntil("the peers") { w.port.realizedPeerSessions.count == 3 }
        waitUntil("the bar to go") { !w.leader.hasAnnouncement(withIdentifier: w.identifier) }
        try waitUntil("the lock to be released") { try self.lockValue() == nil }
    }

    // The holder is connected but seems stuck: Take Over evicts it.
    func testTakeOver() throws {
        let gateway = try attach()
        _ = try holdLockInAnotherClient()
        let w = try enterWhileLocked(gateway)
        XCTAssertTrue(w.leader.debugSelectAction(0, ofAnnouncementWithIdentifier: w.identifier))
        waitUntil("the peers") { w.port.realizedPeerSessions.count == 3 }
        try waitUntil("the lock to be released") { try self.lockValue() == nil }
    }

    // Cancel stops waiting and leaves the other client's lock alone. The peers are created on
    // demand later.
    func testCancel() throws {
        let gateway = try attach()
        _ = try holdLockInAnotherClient()
        let held = try lockValue()
        let w = try enterWhileLocked(gateway)
        XCTAssertTrue(w.leader.debugSelectAction(1, ofAnnouncementWithIdentifier: w.identifier))
        waitUntil("the bar to go") { !w.leader.hasAnnouncement(withIdentifier: w.identifier) }
        XCTAssertEqual(try lockValue(), held)
        XCTAssertEqual(try parkedWindowCount(), 0)
    }
}

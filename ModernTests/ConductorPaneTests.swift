//
//  ConductorPaneTests.swift
//  iTerm2 ModernTests
//
//  A pane is a program a workgroup peer runs through its leader's framer (framer.py `pane`)
//  instead of over a new ssh connection. The conductor starts it, resizes it, feeds it input,
//  and hands its output and exit to the client that started it. Output and exits are routed
//  by depth, like every other framer report, so a pane started by an outer conductor is found
//  from the innermost one PTYSession talks to.
//

import XCTest
@testable import iTerm2SharedARC

private final class PaneConductorDelegate: NSObject, ConductorDelegate {
    private(set) var writes = [String]()
    private(set) var quits = 0
    func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {}
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    func conductorWrite(string: String) { writes.append(string) }
    func conductorAbort(reason: String) {}
    func conductorQuit() { quits += 1 }
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    let guid = "the-leader"

    // Every argument written so far, decoded. Each is one base64 line; a long one is split
    // across lines that end in a backslash.
    var decodedLines: [String] {
        var result = [String]()
        var pending = ""
        for line in writes.joined().components(separatedBy: "\n") {
            if line.hasSuffix("\\") {
                pending += line.dropLast()
                continue
            }
            let full = pending + line
            pending = ""
            if full.isEmpty {
                continue
            }
            result.append(String(data: Data(base64Encoded: full) ?? Data(), encoding: .utf8) ?? "?")
        }
        return result
    }

    func reset() { writes = [] }
}

private final class FakePaneClient: NSObject, ConductorPaneClient {
    private(set) var output = Data()
    private(set) var exitCodes = [Int32]()
    private(set) var lostConnection = 0
    func conductorPaneDidOutput(_ data: Data) { output.append(data) }
    func conductorPaneDidExit(code: Int32) { exitCodes.append(code) }
    func conductorPaneDidLoseConnection() { lostConnection += 1 }
}

@MainActor
final class ConductorPaneTests: XCTestCase {
    private var delegate: PaneConductorDelegate!
    private var conductor: Conductor!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            delegate = PaneConductorDelegate()
            conductor = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
            conductor.framedPID = 100
            conductor.delegate = delegate
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            conductor = nil
            delegate = nil
        }
        super.tearDown()
    }

    // The framer's answer to the command in flight.
    private func reply(_ lines: [String], status: UInt8 = 0, conductor: Conductor? = nil) {
        let c = conductor ?? self.conductor!
        c.handleCommandBegin(identifier: "x", depth: c.depth)
        for line in lines {
            c.handle(line: line, depth: c.depth)
        }
        c.handleCommandEnd(identifier: "x", type: "f", status: status, depth: c.depth)
    }

    func testStartingAPaneSendsThePaneCommand() {
        let client = FakePaneClient()
        conductor.startPane(rows: 31, cols: 97, directory: "~/src", command: "exec claude\n--resume",
                            client: client) { _ in }
        XCTAssertEqual(delegate.decodedLines, ["pane", "31", "97", "~/src", "exec claude\n--resume"])
    }

    func testThePanesVariablesAreSentAfterItsCommand() {
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "",
                            environment: ["TERM_SESSION_ID": "w0t0p1:X", "TERM": "xterm-256color"],
                            client: client) { _ in }
        XCTAssertEqual(delegate.decodedLines,
                       ["pane", "24", "80", "~", "", "TERM=xterm-256color", "TERM_SESSION_ID=w0t0p1:X"])
    }

    func testPanesHearWhenTheConnectionEnds() {
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { _ in }
        reply(["4242"])
        conductor.quit()
        XCTAssertEqual(client.lostConnection, 1)
        conductor.handlePaneOutput(Data("late".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(client.output, Data(), "forgotten")
    }

    func testThePanesPidIsReportedAndItsOutputAndExitReachTheClient() {
        let client = FakePaneClient()
        var reported: Int32?
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { pid in
            reported = pid
        }
        reply(["4242"])
        XCTAssertEqual(reported, 4242)

        conductor.handlePaneOutput(Data("hello".utf8), pid: 4242, depth: 0)
        conductor.handlePaneOutput(Data(" world".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(client.output, Data("hello world".utf8))

        conductor.handleTerminate(4242, code: 3, depth: 0)
        XCTAssertEqual(client.exitCodes, [3])
        XCTAssertEqual(delegate.quits, 0, "a pane exiting is not the login shell exiting")

        conductor.handlePaneOutput(Data("late".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(client.output, Data("hello world".utf8), "forgotten after it exits")
    }

    // Pane output leaves for its session as soon as it is parsed, so the first of it can come
    // before the reply that names the pane is handled. It is kept, then given to the client.
    func testOutputBeforeTheReplyReachesTheClient() {
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { _ in }
        conductor.handlePaneOutput(Data("early ".utf8), pid: 4242, depth: 0)
        reply(["4242"])
        conductor.handlePaneOutput(Data("later".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(client.output, Data("early later".utf8))
    }

    // The connection ending (or the queue being reset when the conductor resynchronizes) must
    // still answer, or a peer waiting to start would sit with no program forever.
    func testAnAbortedStartReportsNoPid() {
        let client = FakePaneClient()
        var called = false
        var reported: Int32? = 1
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { pid in
            called = true
            reported = pid
        }
        conductor.forceReturnToGroundState()
        XCTAssertTrue(called)
        XCTAssertNil(reported)
    }

    // An aborted query says nothing about the pane, so what was kept for it stays kept.
    func testAnAbortedReattachCannotTell() {
        conductor.handlePaneOutput(Data("kept".utf8), pid: 4242, depth: 0)
        let client = FakePaneClient()
        var reattached: PaneReattachment?
        conductor.reattachPane(4242, client: client) { reattached = $0 }
        conductor.forceReturnToGroundState()
        XCTAssertEqual(reattached, .unknown)
        XCTAssertEqual(conductor.unclaimedPanes[4242]?.output, Data("kept".utf8))
    }

    func testAFailedStartReportsNoPid() {
        let client = FakePaneClient()
        var called = false
        var reported: Int32? = 1
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { pid in
            called = true
            reported = pid
        }
        reply(["Command failed: no such directory"], status: 1)
        XCTAssertTrue(called)
        XCTAssertNil(reported)
    }

    func testOutputForAnUnknownPidIsDropped() {
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { _ in }
        reply(["4242"])
        conductor.handlePaneOutput(Data("x".utf8), pid: 999, depth: 0)
        XCTAssertEqual(client.output, Data())
    }

    func testInputResizeAndKillGoToThePanesPid() {
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { _ in }
        reply(["4242"])

        delegate.reset()
        conductor.resizePane(4242, rows: 40, cols: 120)
        XCTAssertEqual(delegate.decodedLines, ["panesize", "4242", "40", "120"])
        reply([])

        delegate.reset()
        conductor.sendToPane(4242, data: Data("ls\r".utf8))
        XCTAssertEqual(delegate.decodedLines, ["send", "4242", Data("ls\r".utf8).base64EncodedString()])
        reply([])

        delegate.reset()
        conductor.killPane(4242)
        XCTAssertEqual(delegate.decodedLines, ["kill", "4242"])
    }

    func testAPaneOfAnOuterConductorIsFoundFromTheInnerOne() {
        // PTYSession talks to its innermost conductor; output from the outer framer's pane
        // arrives there with the outer depth and has to be passed up.
        let inner = Conductor("inner", boolArgs: "", dcsID: "dcs-inner", clientUniqueID: "cid-inner",
                              varsToSend: [:], clientVars: [:], initialDirectory: nil,
                              shouldInjectShellIntegration: false, parent: conductor)
        inner.framedPID = 200
        inner.delegate = delegate
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { _ in }
        reply(["4242"])

        inner.handlePaneOutput(Data("up".utf8), pid: 4242, depth: conductor.depth)
        XCTAssertEqual(client.output, Data("up".utf8))
        inner.handleTerminate(4242, code: 0, depth: conductor.depth)
        XCTAssertEqual(client.exitCodes, [0])
    }

    func testAPaneWhoseClientIsGoneIsKilled() {
        var client: FakePaneClient? = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client!) { _ in }
        reply(["4242"])
        client = nil

        delegate.reset()
        conductor.handlePaneOutput(Data("x".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(delegate.decodedLines, ["kill", "4242"])
        // It may outlive the signal; what it writes meanwhile is nobody's.
        conductor.handlePaneOutput(Data("still here".utf8), pid: 4242, depth: 0)
        XCTAssertNil(conductor.unclaimedPanes[4242], "not kept for a session")
    }

    // MARK: - Reattaching after a restart or a recovery

    func testOutputForAnUnclaimedPaneIsKeptAndReplayedOnReattach() {
        conductor.handlePaneOutput(Data("while ".utf8), pid: 4242, depth: 0)
        conductor.handlePaneOutput(Data("away".utf8), pid: 4242, depth: 0)
        let client = FakePaneClient()
        var reattached: PaneReattachment?
        delegate.reset()
        conductor.reattachPane(4242, client: client) { reattached = $0 }
        XCTAssertEqual(delegate.decodedLines, ["panes"])
        reply(["4242 77"])
        XCTAssertEqual(reattached, .reattached)
        XCTAssertEqual(client.output, Data("while away".utf8), "nothing is dropped")
        conductor.handlePaneOutput(Data(" and now".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(client.output, Data("while away and now".utf8))
        XCTAssertTrue(conductor.knownPanePIDs.contains(77))
    }

    func testAPaneThatExitedWhileUnclaimedReportsItsExitOnReattach() {
        conductor.handlePaneOutput(Data("last words".utf8), pid: 4242, depth: 0)
        conductor.handleTerminate(4242, code: 5, depth: 0)
        let client = FakePaneClient()
        var reattached: PaneReattachment?
        conductor.reattachPane(4242, client: client) { reattached = $0 }
        reply([""])
        XCTAssertEqual(reattached, .reattached)
        XCTAssertEqual(client.output, Data("last words".utf8))
        XCTAssertEqual(client.exitCodes, [5])
    }

    func testAPaneThatIsGoneDoesNotReattach() {
        let client = FakePaneClient()
        var reattached: PaneReattachment?
        conductor.reattachPane(4242, client: client) { reattached = $0 }
        reply(["77"])
        XCTAssertEqual(reattached, .gone)
        conductor.handlePaneOutput(Data("x".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(client.output, Data(), "not registered")
    }

    func testRecoveryNamesThePanesSoTheirExitsAreKept() {
        let recovery = ConductorRecovery(pid: 123, dcsID: "dcs", tree: [:], sshargs: "host",
                                         boolArgs: "", clientUniqueID: "cid", version: 2,
                                         flow: nil, panes: [4242], parent: nil,
                                         it2Proxy: IT2ProxyState())
        let recovered = Conductor(recovery: recovery)
        XCTAssertTrue(recovered.awaitingResynchronization)
        recovered.handleTerminate(4242, code: 0, depth: 0)
        XCTAssertEqual(recovered.unclaimedPanes[4242]?.exitCode, 0,
                       "a pane, not taken for a background job")
    }

    func testTheRecoveryBlockNamesPanes() {
        _ = conductor.handleRecovery(line: ":begin-recovery")
        for line in [":recovery: version 2", ":recovery: login 55", ":recovery: pane 4242",
                     ":recovery: process 66", ":recovery: dcsID d", ":recovery: sshargs s",
                     ":recovery: boolArgs b", ":recovery: clientUniqueID c"] {
            _ = conductor.handleRecovery(line: line)
        }
        XCTAssertEqual(conductor.handleRecovery(line: ":end-recovery")?.panes, [4242])
    }

    func testARestoredConductorIsNotReadyForPanesUntilItResynchronizes() throws {
        let json = try XCTUnwrap(conductor.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        XCTAssertTrue(restored.awaitingResynchronization)
        // Commands sent before then are aborted when it resynchronizes, so no pane starts on it.
        XCTAssertTrue(restored.framing)
        XCTAssertFalse(WorkgroupRemoteHost.canStartPanes(on: restored))
        restored.didResynchronize()
        XCTAssertFalse(restored.awaitingResynchronization)
        XCTAssertTrue(WorkgroupRemoteHost.canStartPanes(on: restored))
    }

    // MARK: - Stranded panes

    func testRunningPanesAreTheFramersAnswer() {
        var running: Set<Int32>?
        conductor.runningPanes { running = $0 }
        XCTAssertEqual(delegate.decodedLines, ["panes"])
        reply(["12 34"])
        XCTAssertEqual(running, [12, 34])
        XCTAssertTrue(conductor.knownPanePIDs.isSuperset(of: [12, 34]))
    }

    func testRunningPanesIsNilWhenTheFramerCannotSay() {
        var running: Set<Int32>? = [1]
        conductor.runningPanes { running = $0 }
        reply([], status: 1)
        XCTAssertNil(running)
    }

    // Stopping is the user's choice for a pane no session claims: what it wrote is no longer
    // wanted, and nothing about it is kept once it exits.
    func testStoppingAnUnclaimedPaneKillsItAndKeepsNothing() {
        conductor.handlePaneOutput(Data("unread".utf8), pid: 4242, depth: 0)
        delegate.reset()
        conductor.stopUnclaimedPane(4242)
        XCTAssertEqual(delegate.decodedLines, ["kill", "4242"])
        XCTAssertNil(conductor.unclaimedPanes[4242])
        conductor.handlePaneOutput(Data("dying words".utf8), pid: 4242, depth: 0)
        XCTAssertNil(conductor.unclaimedPanes[4242])
        conductor.handleTerminate(4242, code: 15, depth: 0)
        XCTAssertNil(conductor.unclaimedPanes[4242])
        XCTAssertTrue(conductor.stoppingPanes.isEmpty)
    }

    // Recovery replaces the conductor; the framer and its panes carry on, and so does what was
    // kept for panes without a session.
    func testRecoveryKeepsWhatWasKeptForUnclaimedPanes() throws {
        conductor.handlePaneOutput(Data("kept".utf8), pid: 4242, depth: 0)
        let shim = Conductor("", boolArgs: "", dcsID: "", clientUniqueID: "", varsToSend: [:],
                             clientVars: [:], initialDirectory: nil,
                             shouldInjectShellIntegration: false, parent: nil)
        shim.delegate = delegate
        shim.startRecovery()
        shim.adoptUnclaimedPanes(from: conductor)
        _ = shim.handleRecovery(line: ":begin-recovery")
        for line in [":recovery: version 2", ":recovery: login 55", ":recovery: pane 4242",
                     ":recovery: dcsID d", ":recovery: sshargs s", ":recovery: boolArgs b",
                     ":recovery: clientUniqueID c"] {
            _ = shim.handleRecovery(line: line)
        }
        let recovery = try XCTUnwrap(shim.handleRecovery(line: ":end-recovery"))
        let recovered = Conductor(recovery: recovery)
        XCTAssertEqual(recovered.unclaimedPanes[4242]?.output, Data("kept".utf8))
    }
}

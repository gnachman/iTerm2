//
//  ConductorFlowTests.swift
//  iTerm2 ModernTests
//
//  The conductor's side of flow control: it turns flow control on with `flow on 2` (or `flow on`
//  for a framer that predates version 2), writes the
//  controller's grants at once instead of queueing them, sends drains and pings through the
//  priority lane, times round trips from when each command was written, and resumes flow
//  control after recovery. Typed keys also take the priority lane, in order.
//

import XCTest
@testable import iTerm2SharedARC

private final class FlowConductorDelegate: NSObject, ConductorDelegate {
    private(set) var writes = [String]()
    func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {}
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    func conductorWrite(string: String) { writes.append(string) }
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    let guid = "the-session"

    /// Each command written so far, as its decoded arguments.
    var commands: [[String]] {
        var result = [[String]]()
        var args = [String]()
        var pending = ""
        for line in writes.joined().components(separatedBy: "\n").dropLast() {
            if line.isEmpty {
                if !args.isEmpty {
                    result.append(args)
                }
                args = []
                continue
            }
            if line.hasSuffix("\\") {
                pending += line.dropLast()
                continue
            }
            let full = pending + line
            pending = ""
            let decoded = full == "=" ? Data() : (Data(base64Encoded: full) ?? Data())
            args.append(String(data: decoded, encoding: .utf8) ?? "?")
        }
        return result
    }

    func reset() { writes = [] }
}

@MainActor
final class ConductorFlowTests: XCTestCase {
    private var delegate: FlowConductorDelegate!
    private var conductor: Conductor!
    private var now: TimeInterval = 1000

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            Conductor.flowControlAvailableForTesting = true
            delegate = FlowConductorDelegate()
            conductor = makeConductor()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            Conductor.flowControlAvailableForTesting = nil
            conductor = nil
            delegate = nil
        }
        super.tearDown()
    }

    private func makeConductor(parent: Conductor? = nil) -> Conductor {
        let c = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                          varsToSend: [:], clientVars: [:], initialDirectory: nil,
                          shouldInjectShellIntegration: false, parent: parent)
        c.framedPID = 100
        c.delegate = delegate
        c.flowClock = { [unowned self] in self.now }
        c.flowTicksAutomatically = false
        return c
    }

    /// The framer's answer to the oldest command in flight.
    private func reply(_ lines: [String] = [], status: UInt8 = 0, conductor: Conductor? = nil) {
        let c = conductor ?? self.conductor!
        c.handleCommandBegin(identifier: "x", depth: c.depth)
        for line in lines {
            c.handle(line: line, depth: c.depth)
        }
        c.handleCommandEnd(identifier: "x", type: "f", status: status, depth: c.depth)
    }

    /// Version 1 is what a framer that predates version 2 speaks: it refuses `flow on 2`.
    private func startFlowControl(roundTrip: TimeInterval = 0.08, version: Int = 1) {
        conductor.startFlowControlIfPossible()
        XCTAssertEqual(delegate.commands.last, ["flow", "on", "2"])
        if version == 1 {
            reply(["bad arguments"], status: 1)
            XCTAssertEqual(delegate.commands.last, ["flow", "on"])
        }
        now += roundTrip
        reply(["\(version) boottime"])
    }

    // MARK: - The priority lane

    func testTypedKeysGoAheadOfQueuedCommandsInOrder() {
        conductor.runRemoteCommand("first") { _, _ in }
        conductor.runRemoteCommand("second") { _, _ in }
        conductor.sendKeys(Data("a".utf8))
        conductor.sendKeys(Data("b".utf8))
        reply()  // "first" finishes.
        XCTAssertEqual(delegate.commands.map { $0.first! }, ["run", "send", "send"])
        reply()
        reply()  // Both keystrokes are answered, so "second" can go.
        XCTAssertEqual(delegate.commands.map { $0.first! }, ["run", "send", "send", "run"])
        let sent = delegate.commands.filter { $0.first == "send" }.map { $0[2] }
        XCTAssertEqual(sent, [Data("a".utf8).base64EncodedString(),
                              Data("b".utf8).base64EncodedString()],
                       "first in, first out")
    }

    func testANestedSessionsKeysKeepTheirPriorityInItsParent() {
        let child = makeConductor(parent: conductor)
        child.framedPID = 200
        conductor.runRemoteCommand("busy") { _, _ in }
        conductor.runRemoteCommand("queued") { _, _ in }
        child.sendKeys(Data("k".utf8))
        reply()
        XCTAssertEqual(delegate.commands.map { $0.first! }, ["run", "send"],
                       "the child's key is relayed ahead of the parent's queued command")
    }

    // MARK: - Negotiation

    func testFlowOnStartsTheControllerAndTimesItsRoundTrip() {
        startFlowControl(roundTrip: 0.08)
        XCTAssertEqual(conductor.flowClockName, "boottime")
        let controller = conductor.flowController!
        XCTAssertEqual(controller.granted, 8 * 1024, "flow on carries the initial credit")
        XCTAssertEqual(controller.rttMin(now: now), 0.08, accuracy: 1e-9)
    }

    func testAnOlderFramerLeavesFlowControlOff() {
        conductor.startFlowControlIfPossible()
        reply(["unrecognized command"], status: 1)
        reply(["unrecognized command"], status: 1)
        XCTAssertEqual(delegate.commands, [["flow", "on", "2"], ["flow", "on"]])
        XCTAssertNil(conductor.flowController)
    }

    // MARK: - Version 2

    private func grants(_ flow: String) -> [Int] {
        delegate.commands.filter { $0.count == 3 && $0[0] == "grant" && $0[1] == flow }.compactMap { Int($0[2]) }
    }

    func testVersionTwoGrantsEachFlowByName() {
        startFlowControl(version: 2)
        XCTAssertEqual(conductor.flowVersion, 2)
        XCTAssertEqual(grants("it2").count, 1, "it2 gets credit of its own at once")
        let controller = conductor.flowController!
        controller.frameDidArrive(now: now, sendMilliseconds: 5_000, bytes: 4096, limited: false, exempt: false)
        controller.flowDidConsume(.leader, bytes: 4096, now: now)
        now += 0.03
        conductor.flowTick()
        XCTAssertEqual(grants("leader"), [4096])
        XCTAssertFalse(delegate.commands.contains { $0.count == 2 && $0[0] == "grant" },
                       "no grant without a flow")
    }

    func testAPaneGetsCreditOfItsOwnBackWhenItsSessionConsumes() {
        startFlowControl(version: 2)
        conductor.flowPaneDidStart(77)
        let first = grants("77")
        XCTAssertEqual(first.count, 1)
        let controller = conductor.flowController!
        controller.frameDidArrive(now: now, flow: .pane(77), sendMilliseconds: 5_000, bytes: first[0],
                                  limited: true, exempt: false)
        now += 0.03
        conductor.flowTick()
        XCTAssertEqual(grants("77").count, 1, "not until the pane's session has consumed it")
        conductor.flowPaneDidConsume(77, bytes: first[0], now: now)
        now += 0.03
        conductor.flowTick()
        XCTAssertEqual(grants("77").count, 2)
        conductor.flowPaneDidEnd(77)
        XCTAssertNil(controller.window(of: .pane(77)))
    }

    // A pane's session can consume its output before the conductor has read the leader's
    // ledger, where the output's arrival was recorded first. The consumption must still count.
    func testAPanesConsumptionCountsBeforeItsArrivalWasRead() {
        startFlowControl(version: 2)
        conductor.flowPaneDidStart(77)
        let ledger = FramerFlowLedger(clock: { [unowned self] in self.now })
        conductor.activeFlowLedger = ledger
        ledger.activate {}
        ledger.frameDidArrive(bytes: 1000, sendMilliseconds: 5_000, flags: 0, flow: 77)
        conductor.flowPaneDidConsume(77, bytes: 1000, now: now)
        conductor.flowTick()
        XCTAssertEqual(conductor.flowController!.backlog(of: .pane(77)), 0)
    }

    // A pane's last output can still be in the ledger when its exit is handled. Reading it
    // afterward must not bring the ended flow back, or the conductor would tick and grant to
    // it for the rest of the connection.
    func testAnEndedPanesLateArrivalDoesNotBringItsFlowBack() {
        startFlowControl(version: 2)
        conductor.flowPaneDidStart(77)
        let ledger = FramerFlowLedger(clock: { [unowned self] in self.now })
        conductor.activeFlowLedger = ledger
        ledger.activate {}
        ledger.frameDidArrive(bytes: 1000, sendMilliseconds: 5_000, flags: 0, flow: 77)
        conductor.flowPaneDidEnd(77)
        ledger.frameDidArrive(bytes: 500, sendMilliseconds: 5_001, flags: 0, flow: 77)
        conductor.flowTick()
        XCTAssertNil(conductor.flowController!.window(of: .pane(77)))
    }

    // A framer from an older iTerm2 has one flow: a pane's output is the leader's, consumed as
    // soon as it is handed to the pane's session.
    func testWithAVersionOneFramerPaneOutputIsTheLeaders() {
        startFlowControl(version: 1)
        XCTAssertEqual(conductor.flowVersion, 1)
        let ledger = FramerFlowLedger(clock: { [unowned self] in self.now })
        conductor.activeFlowLedger = ledger
        ledger.activate {}
        ledger.frameDidArrive(bytes: 3000, sendMilliseconds: 5_000, flags: 0, flow: 77)
        conductor.flowTick()
        let controller = conductor.flowController!
        XCTAssertEqual(controller.arrived, 3000)
        XCTAssertEqual(controller.consumed, 3000)
        XCTAssertNil(controller.window(of: .pane(77)))
        conductor.flowPaneDidStart(77)
        XCTAssertNil(controller.window(of: .pane(77)), "version 1 has no pane flows")
    }

    func testOnlyTheOutermostConductorTurnsItOn() {
        let child = makeConductor(parent: conductor)
        child.startFlowControlIfPossible()
        XCTAssertEqual(delegate.commands, [])
    }

    func testTurningTheSettingOffLeavesFlowControlOff() {
        Conductor.flowControlAvailableForTesting = false
        conductor.startFlowControlIfPossible()
        XCTAssertEqual(delegate.commands, [])
    }

    // MARK: - Grants, drains and pings

    func testGrantsAreWrittenAtOnceEvenWithACommandInFlight() {
        startFlowControl()
        conductor.runRemoteCommand("slow") { _, _ in }
        delegate.reset()
        let controller = conductor.flowController!
        controller.frameDidArrive(now: now, sendMilliseconds: 5_000, bytes: 4096, limited: false, exempt: false)
        controller.flowDidConsume(.leader, bytes: 4096, now: now)
        now += 0.03
        conductor.flowTick()
        XCTAssertEqual(delegate.commands, [["grant", "4096"]])
    }

    func testCommandRoundTripsAreSamples() {
        startFlowControl(roundTrip: 0.2)
        conductor.runRemoteCommand("quick") { _, _ in }
        now += 0.05
        reply()
        XCTAssertEqual(conductor.flowController!.rttMin(now: now), 0.05, accuracy: 1e-9)
    }

    func testTheValveStartsADrainThatEndsWithAPingAndAGrant() {
        startFlowControl()
        delegate.reset()
        conductor.handleSideChannelOutput("%notif valve", pid: SSH_OUTPUT_NOTIF_PID, channel: 1, depth: 0)
        XCTAssertEqual(delegate.commands, [["drain"]])
        XCTAssertTrue(conductor.flowController!.isDraining)
        now += 0.3
        reply()  // The drain's reply; nothing arrived that is not yet executed.
        XCTAssertEqual(delegate.commands, [["drain"], ["ping"]])
        now += 0.06
        reply()  // The ping's reply.
        let controller = conductor.flowController!
        XCTAssertFalse(controller.isDraining)
        XCTAssertEqual(controller.rttMin(now: now), 0.06, accuracy: 1e-9, "the ping's round trip")
        XCTAssertEqual(delegate.commands.last, ["grant", String(8 * 1024)],
                       "the framer discarded its credit, so the whole window is granted again")
    }

    func testDrainsTakeThePriorityLane() {
        startFlowControl()
        conductor.runRemoteCommand("busy") { _, _ in }
        conductor.runRemoteCommand("queued") { _, _ in }
        conductor.handleSideChannelOutput("%notif valve", pid: SSH_OUTPUT_NOTIF_PID, channel: 1, depth: 0)
        delegate.reset()
        reply()  // "busy" finishes.
        XCTAssertEqual(delegate.commands.first, ["drain"])
    }

    // MARK: - Recovery

    func testRecoveryResumesFlowControlAfterResynchronizing() {
        let recovery = ConductorRecovery(pid: 123, dcsID: "dcs", tree: [:], sshargs: "host",
                                         boolArgs: "", clientUniqueID: "cid", version: 2,
                                         flow: "1 monotonic", parent: nil,
                                         it2Proxy: IT2ProxyState())
        let recovered = Conductor(recovery: recovery)
        recovered.flowClock = { [unowned self] in self.now }
        recovered.flowTicksAutomatically = false
        XCTAssertEqual(recovered.flowClockName, "monotonic")
        let controller = recovered.flowController!
        XCTAssertTrue(controller.quarantined, "the backlog is not sampled")
        XCTAssertEqual(controller.granted, 0, "recover left the framer with no credit")
        recovered.delegate = delegate
        recovered.didResynchronize()
        // Resynchronizing sends reset2; the ping waits for its reply.
        let reset = delegate.commands.last!
        XCTAssertEqual(reset.first, "reset2")
        reply([reset[1]], conductor: recovered)
        XCTAssertEqual(delegate.commands.last, ["ping"])
    }

    // After iTerm2 restarts, the conductor is rebuilt from its saved state with no controller,
    // while the framer may still have flow control on. Without a new `flow on` the framer
    // stops once its leftover credit is spent.
    func testARestoredConductorTurnsFlowControlBackOnAfterResynchronizing() throws {
        let json = try XCTUnwrap(conductor.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowClock = { [unowned self] in self.now }
        restored.flowTicksAutomatically = false
        XCTAssertFalse(restored.queue.contains { $0.command == .framerFlowOn } ||
                       delegate.commands.contains(["flow", "on", "2"]),
                       "not before the conductor has resynchronized")
        restored.didResynchronize()
        XCTAssertTrue(restored.queue.contains { $0.command == .framerFlowOn } ||
                      delegate.commands.contains(["flow", "on", "2"]))
    }

    // After a restart the framer may still be spending credit from before when `flow on`
    // reaches it, and those frames would be counted against the new initial credit. A drain
    // first sets every count from what actually arrived.
    func testARestoredConductorDrainsWhenFlowControlComesBackOn() throws {
        let json = try XCTUnwrap(conductor.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowClock = { [unowned self] in self.now }
        restored.flowTicksAutomatically = false
        restored.didResynchronize()
        XCTAssertTrue(restored.flowRestartingAfterRestore)

        // What the reply to that `flow on` does.
        conductor.flowRestartingAfterRestore = true
        startFlowControl(version: 2)
        XCTAssertTrue(conductor.flowController!.isDraining)
        XCTAssertTrue(delegate.commands.contains(["drain"]))
        XCTAssertFalse(conductor.flowRestartingAfterRestore)
    }

    func testAFreshStartDoesNotDrain() {
        startFlowControl(version: 2)
        XCTAssertFalse(conductor.flowController!.isDraining)
        XCTAssertFalse(delegate.commands.contains(["drain"]))
    }

    func testResynchronizingWithFlowControlRunningDoesNotRestartIt() {
        startFlowControl()
        let controller = conductor.flowController
        delegate.reset()
        conductor.didResynchronize()
        XCTAssertFalse(conductor.queue.contains { $0.command == .framerFlowOn } ||
                       delegate.commands.contains(["flow", "on", "2"]))
        XCTAssertTrue(conductor.flowController === controller)
    }

    func testTheOutermostConductorRestartsFlowControlWhenAnInnerOneResynchronizes() {
        let child = makeConductor(parent: conductor)
        child.framedPID = 200
        child.didResynchronize()
        XCTAssertTrue(conductor.queue.contains { $0.command == .framerFlowOn } ||
                      delegate.commands.contains(["flow", "on", "2"]),
                      "the parent, which owns flow control, turns it on")
        XCTAssertFalse(child.queue.contains { $0.command == .framerFlowOn })
    }

    func testRecoveryWithoutFlowControlLeavesItOff() {
        let recovery = ConductorRecovery(pid: 123, dcsID: "dcs", tree: [:], sshargs: "host",
                                         boolArgs: "", clientUniqueID: "cid", version: 2,
                                         flow: nil, parent: nil, it2Proxy: IT2ProxyState())
        XCTAssertNil(Conductor(recovery: recovery).flowController)
    }

    func testTheRecoveryBlocksFlowLineIsRead() {
        _ = conductor.handleRecovery(line: ":begin-recovery")
        for line in [":recovery: version 2", ":recovery: flow 1 boottime", ":recovery: login 55",
                     ":recovery: dcsID d", ":recovery: sshargs s", ":recovery: boolArgs b",
                     ":recovery: clientUniqueID c"] {
            _ = conductor.handleRecovery(line: line)
        }
        let recovery = conductor.handleRecovery(line: ":end-recovery")
        XCTAssertEqual(recovery?.flow, "1 boottime")
    }

    func testFlowReplyParsing() {
        func parse(_ reply: String) -> String? {
            Conductor.flowVersionAndClock(fromReply: reply).map { "\($0.0) \($0.1)" }
        }
        XCTAssertEqual(parse("1 boottime\n"), "1 boottime")
        XCTAssertEqual(parse("2 monotonic"), "2 monotonic")
        XCTAssertNil(parse("3 boottime"), "a future version")
        XCTAssertNil(parse("1"))
        XCTAssertNil(parse("unrecognized command"))
    }

    // MARK: - Side command output

    func testASideCommandIsKilledPastTheOutputCap() {
        conductor.sideCommandOutputCap = 10
        var result: (Data, Int32)?
        conductor.runRemoteCommand("yes") { data, status in result = (data, status) }
        reply(["4242"])
        delegate.reset()
        conductor.handleSideChannelOutput("12345678", pid: 4242, channel: 1, depth: 0)
        XCTAssertEqual(delegate.commands, [])
        conductor.handleSideChannelOutput("abcdefgh", pid: 4242, channel: 1, depth: 0)
        XCTAssertEqual(delegate.commands, [["kill", "4242"]])
        conductor.handleSideChannelOutput("more", pid: 4242, channel: 1, depth: 0)
        XCTAssertEqual(delegate.commands, [["kill", "4242"]], "killed once")
        conductor.handleTerminate(4242, code: 15, depth: 0)
        XCTAssertEqual(result?.0, Data("12345678".utf8), "output past the cap is dropped")
        XCTAssertEqual(result?.1, 15)
    }

    func testQuittingStopsFlowControl() {
        startFlowControl()
        conductor.quit()
        XCTAssertNil(conductor.flowController)
    }
}

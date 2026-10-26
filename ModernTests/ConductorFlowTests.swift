//
//  ConductorFlowTests.swift
//  iTerm2 ModernTests
//
//  The conductor's side of flow control: it turns flow control on with `flow on 2` (or `flow on`
//  for a framer that predates version 2), writes the
//  controller's grants at once instead of queueing them, sends drains and pings through the
//  priority lane, times round trips from when each command was written, and resumes flow
//  control after recovery. Typed keys also take the priority lane, in order. With nested SSH
//  Integration each conductor controls its own framer once its parent does.
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
        return Self.decode(writes.joined())
    }

    /// The commands a nested conductor wrote, relayed as keystrokes through this conductor's
    /// `send` to `pid`, the process this conductor frames (the inner ssh).
    func relayedCommands(pid: Int32 = 100) -> [[String]] {
        let data = commands.filter { $0.count == 3 && $0[0] == "send" && $0[1] == String(pid) }
            .map { Data(base64Encoded: $0[2]) ?? Data() }
            .reduce(Data(), +)
        return Self.decode(String(data: data, encoding: .utf8) ?? "")
    }

    var ledger: FramerFlowLedger?
    func conductorFlowLedger() -> FramerFlowLedger? { ledger }

    static func decode(_ text: String) -> [[String]] {
        var result = [[String]]()
        var args = [String]()
        var pending = ""
        for line in text.components(separatedBy: "\n").dropLast() {
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
        // As when it started the framer, which speaks reset2.
        c.framerVersion = .v2
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

    /// Runs what was already dispatched to the main queue.
    private func runMainQueue() {
        let done = expectation(description: "main queue")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 10)
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

    // MARK: - The login shell ends

    // When the framer's login shell exits, the conductor tells the framer to quit, so ssh ends
    // and it2ssh reports it. The framer reads only framer commands: a pre-framer `quit`, with
    // its random line prefix, means nothing to it, and the session hung after `exit`.
    func testTheFramerIsToldToQuitWhenItsLoginShellEnds() {
        conductor.handleTerminate(100, code: 0, depth: conductor.depth)
        XCTAssertEqual(delegate.commands.last, ["quit"])
    }

    // Disconnecting from the menu quits a running framer the same way.
    func testQuittingARunningFramerSendsTheFramersQuit() {
        conductor.quit()
        XCTAssertEqual(delegate.commands.last, ["quit"])
    }

    // MARK: - Recovering a nested conductor

    // While a nested connection is recovered, the session's conductor is the one being
    // recovered, which does not frame yet. Its parent may still be waiting for a reply, such as
    // the reset that follows its own recovery, whose lines carry the code it checks. They are at
    // the parent's depth and must reach it, or the parent waits forever.
    func testARecoveringChildPassesItsParentsReplyLinesUp() {
        conductor.startFlowControlIfPossible()
        XCTAssertEqual(delegate.commands.last, ["flow", "on", "2"])
        let child = makeConductor(parent: conductor)
        child.framedPID = nil
        child.startRecovery()
        XCTAssertFalse(child.framing)
        XCTAssertEqual(child.depth, conductor.depth + 1)
        // The parent's answer, handed to the child, which the session talks to now.
        child.handleCommandBegin(identifier: "x", depth: conductor.depth)
        child.handle(line: "2 boottime", depth: conductor.depth)
        child.handleCommandEnd(identifier: "x", type: "f", status: 0, depth: conductor.depth)
        XCTAssertNotNil(conductor.flowController, "the parent got its reply line")
        XCTAssertEqual(conductor.flowClockName, "boottime")
    }

    // MARK: - Nested conductors

    private func makeChild() -> Conductor {
        let child = makeConductor(parent: conductor)
        child.framedPID = 200
        return child
    }

    /// The child's `flow on 2` goes out through the parent; this answers it.
    private func startChildFlowControl(_ child: Conductor, roundTrip: TimeInterval = 0.1) {
        child.startFlowControlIfPossible()
        XCTAssertEqual(delegate.relayedCommands().last, ["flow", "on", "2"])
        reply()  // The parent's send that relayed it.
        now += roundTrip
        reply(["2 monotonic"], conductor: child)
    }

    // Each framer limits its own reads, so every depth runs a controller of its own.
    func testAChildTurnsItOnOnceItsParentRunsVersionTwo() {
        startFlowControl(version: 2)
        let child = makeChild()
        startChildFlowControl(child)
        XCTAssertNotNil(child.flowController)
        XCTAssertEqual(child.flowVersion, 2)
        XCTAssertEqual(child.flowController?.rttMin(now: now) ?? 0, 0.1, accuracy: 1e-9)
    }

    // After a restore every depth comes back at once; the child waits for its parent's answer.
    func testAChildWaitsForItsParentToTurnItOn() {
        let child = makeChild()
        child.startFlowControlIfPossible()
        XCTAssertEqual(delegate.relayedCommands(), [], "the parent's framer is not controlled yet")
        startFlowControl(version: 2)
        XCTAssertEqual(delegate.relayedCommands(), [["flow", "on", "2"]])
    }

    // Mixed versions keep today's behavior: only the outermost framer is controlled.
    func testAChildStaysOffWhenItsParentSpeaksOnlyVersionOne() {
        let child = makeChild()
        child.startFlowControlIfPossible()
        startFlowControl(version: 1)
        child.startFlowControlIfPossible()
        XCTAssertEqual(delegate.relayedCommands(), [])
        XCTAssertNil(child.flowController)
    }

    // An older framer on the inner host (one that survived an iTerm2 upgrade) is not
    // controlled; the outer framer still is.
    func testAChildWhoseFramerPredatesVersionTwoStaysOff() {
        startFlowControl(version: 2)
        let child = makeChild()
        child.startFlowControlIfPossible()
        reply()  // The parent's relayed send.
        reply(["bad arguments"], status: 1, conductor: child)
        XCTAssertNil(child.flowController)
        XCTAssertEqual(delegate.relayedCommands().filter { $0.first == "flow" }, [["flow", "on", "2"]],
                       "no fallback to version 1")
        XCTAssertNotNil(conductor.flowController)
    }

    func testAChildStaysOffWhenItsParentHasNoFlowControl() {
        let child = makeChild()
        child.startFlowControlIfPossible()
        conductor.startFlowControlIfPossible()
        reply(["unrecognized command"], status: 1)
        reply(["unrecognized command"], status: 1)
        XCTAssertNil(conductor.flowController)
        XCTAssertEqual(delegate.relayedCommands(), [])
    }

    // The flow control monitor shows how long commands take to be answered, which says how slow
    // the path is whether or not flow control is on. A drain's reply comes back behind
    // everything the framer had sent, so it says nothing about the path and is left out.
    func testRoundTripsAreRecordedWithoutFlowControl() throws {
        Conductor.flowControlAvailableForTesting = false
        conductor.runRemoteCommand("true") { _, _ in }
        now += 0.25
        reply(["4242"])
        XCTAssertNil(conductor.flowController)
        XCTAssertEqual(conductor.roundTrips.count, 1)
        let sample = try XCTUnwrap(conductor.roundTrips.first)
        XCTAssertEqual(sample.seconds, 0.25, accuracy: 1e-9)
        XCTAssertEqual(sample.time, now, accuracy: 1e-9)
    }

    func testADrainsReplyIsNotARoundTrip() {
        startFlowControl(version: 2)
        let before = conductor.roundTrips.count
        conductor.flowController!.valveDidOpen(now: now)
        now += 0.5
        reply()
        XCTAssertEqual(conductor.roundTrips.count, before, "the drain's reply")
    }

    func testAChildStaysOffWhenTheSettingIsOff() {
        startFlowControl(version: 2)
        Conductor.flowControlAvailableForTesting = false
        makeChild().startFlowControlIfPossible()
        XCTAssertEqual(delegate.relayedCommands(), [])
    }

    // A grant is how the inner framer gets to read; it must not wait behind the parent's queue.
    func testAChildsGrantsTakeItsParentsPriorityLane() {
        startFlowControl(version: 2)
        let child = makeChild()
        startChildFlowControl(child)
        conductor.runRemoteCommand("busy") { _, _ in }
        conductor.runRemoteCommand("queued") { _, _ in }
        delegate.reset()
        let controller = child.flowController!
        controller.frameDidArrive(now: now, sendMilliseconds: 5_000, bytes: 4096, limited: false, exempt: false)
        controller.flowDidConsume(.leader, bytes: 4096, now: now)
        now += 0.03
        child.flowTick()
        reply()  // "busy" finishes.
        XCTAssertEqual(delegate.commands.map { $0.first! }, ["send"],
                       "the grant is relayed ahead of the parent's queued command")
        XCTAssertEqual(delegate.relayedCommands(), [["grant", "leader", "4096"]])
    }

    // A child's grant waits in its parent's queue, and the controller has already counted it.
    // If the queue is dropped the inner framer never gets that credit, so the child turns flow
    // control on again, which resets the framer's credit, and drains to resynchronize.
    func testALostRelayedGrantRestartsTheChildsFlowControl() {
        startFlowControl(version: 2)
        let child = makeChild()
        startChildFlowControl(child)
        conductor.runRemoteCommand("busy") { _, _ in }
        delegate.reset()
        let controller = child.flowController!
        controller.frameDidArrive(now: now, sendMilliseconds: 5_000, bytes: 4096, limited: false, exempt: false)
        controller.flowDidConsume(.leader, bytes: 4096, now: now)
        now += 0.03
        child.flowTick()
        XCTAssertEqual(delegate.relayedCommands(), [["grant", "leader", "4096"]],
                       "relayed, and not yet answered")
        conductor.forceReturnToGroundState()
        XCTAssertNil(child.flowController)
        XCTAssertEqual(delegate.relayedCommands().last, ["flow", "on", "2"])
        reply()  // The relayed flow on.
        reply(["2 monotonic"], conductor: child)
        XCTAssertNotNil(child.flowController)
        XCTAssertTrue(child.flowController?.isDraining ?? false)
    }

    // A grant the parent delivered is not lost, so nothing restarts.
    func testADeliveredRelayedGrantRestartsNothing() {
        startFlowControl(version: 2)
        let child = makeChild()
        startChildFlowControl(child)
        let controller = child.flowController!
        controller.frameDidArrive(now: now, sendMilliseconds: 5_000, bytes: 4096, limited: false, exempt: false)
        controller.flowDidConsume(.leader, bytes: 4096, now: now)
        now += 0.03
        child.flowTick()
        reply()  // The parent's send relaying the child's first grant, for it2.
        reply()  // And the leader's.
        conductor.forceReturnToGroundState()
        XCTAssertTrue(child.flowController === controller)
    }

    // A child that ended while waiting for its parent is not started when the parent is ready.
    func testAnEndedWaitingChildIsNotStartedLater() {
        let ledger = FramerFlowLedger(clock: { [unowned self] in self.now })
        delegate.ledger = ledger
        let child = makeChild()
        child.startFlowControlIfPossible()
        child.stopFlowControl()
        startFlowControl(version: 2)
        XCTAssertEqual(delegate.relayedCommands(), [])
        XCTAssertFalse(ledger.isActive(depth: 1))
    }

    // The session's ledger keeps each depth apart; each conductor reads its own.
    func testEachConductorReadsItsOwnDepth() {
        let ledger = FramerFlowLedger(clock: { [unowned self] in self.now })
        delegate.ledger = ledger
        startFlowControl(version: 2)
        let child = makeChild()
        startChildFlowControl(child)
        XCTAssertTrue(ledger.isActive(depth: 0))
        XCTAssertTrue(ledger.isActive(depth: 1))
        ledger.frameDidArrive(bytes: 500, sendMilliseconds: 7_000, flags: 0, flow: 0, depth: 1,
                              carrierMilliseconds: 9_000)
        ledger.frameDidExecute(bytes: 500, depth: 1)
        ledger.frameDidArrive(bytes: 900, sendMilliseconds: 9_000, flags: 0, flow: 0, depth: 0,
                              carrierMilliseconds: 0)
        child.flowTick()
        conductor.flowTick()
        XCTAssertEqual(child.flowController?.arrived, 500)
        XCTAssertEqual(child.flowController?.consumed, 500)
        XCTAssertEqual(conductor.flowController?.arrived, 900)
        XCTAssertEqual(conductor.flowController?.consumed, 0)
    }

    // A child measures its frames to the parent's frames that carried them, and its window
    // is capped by what the parent's leader carries.
    func testAChildMeasuresToItsCarrierAndFollowsItsParentsWindow() {
        let ledger = FramerFlowLedger(clock: { [unowned self] in self.now })
        delegate.ledger = ledger
        startFlowControl(version: 2)
        let child = makeChild()
        startChildFlowControl(child)
        let rtt = child.flowController!.rttMin(now: now)
        ledger.frameDidArrive(bytes: 500, sendMilliseconds: 7_000, flags: 0, flow: 0, depth: 1,
                              carrierMilliseconds: 9_000)
        now += 0.5
        // Sent by the parent's framer 100 ms after the first, it took 400 ms longer to arrive.
        ledger.frameDidArrive(bytes: 500, sendMilliseconds: 7_100, flags: 0, flow: 0, depth: 1,
                              carrierMilliseconds: 9_100)
        child.flowTick()
        XCTAssertEqual(child.flowController!.feedbackDelay(now: now), rtt + 0.4, accuracy: 0.002)
        XCTAssertEqual(child.flowController!.carrierWindow, conductor.flowController!.window(of: .leader))
        XCTAssertNil(conductor.flowController!.carrierWindow, "the outermost has no carrier")
        conductor.stopFlowControl()
        child.flowTick()
        XCTAssertNil(child.flowController!.carrierWindow, "no cap without the parent's controller")
    }

    // A 0 carrier means the parent's frame was not controlled: no carrier at all.
    func testAChildsFramesWithoutACarrierAreMeasuredOnArrival() {
        let ledger = FramerFlowLedger(clock: { [unowned self] in self.now })
        delegate.ledger = ledger
        startFlowControl(version: 2)
        let child = makeChild()
        startChildFlowControl(child)
        let rtt = child.flowController!.rttMin(now: now)
        ledger.frameDidArrive(bytes: 500, sendMilliseconds: 7_000, flags: 0, flow: 0, depth: 1,
                              carrierMilliseconds: 0)
        now += 0.5
        ledger.frameDidArrive(bytes: 500, sendMilliseconds: 7_100, flags: 0, flow: 0, depth: 1,
                              carrierMilliseconds: 0)
        child.flowTick()
        XCTAssertEqual(child.flowController!.feedbackDelay(now: now), rtt, accuracy: 1e-9)
        XCTAssertEqual(child.flowController!.queueingDelay(now: now)!, 0.4, accuracy: 0.002,
                       "measured on arrival, it took 400 ms longer")
    }

    func testAChildsPanesHaveFlowsOfTheirOwn() {
        startFlowControl(version: 2)
        let child = makeChild()
        startChildFlowControl(child)
        child.flowPaneDidStart(77)
        XCTAssertNotNil(child.flowController?.window(of: .pane(77)))
        XCTAssertNil(conductor.flowController?.window(of: .pane(77)), "the pane is the child's")
    }

    // When an inner ssh ends and another starts, the new child's depth must stay registered even
    // if the old one stops late.
    func testAnEndedChildDoesNotUnregisterItsSuccessor() {
        let ledger = FramerFlowLedger(clock: { [unowned self] in self.now })
        delegate.ledger = ledger
        startFlowControl(version: 2)
        let first = makeChild()
        startChildFlowControl(first)
        let second = makeChild()
        startChildFlowControl(second)
        first.stopFlowControl()
        XCTAssertTrue(ledger.isActive(depth: 1))
        second.stopFlowControl()
        XCTAssertFalse(ledger.isActive(depth: 1))
    }

    func testTurningTheSettingOffLeavesFlowControlOff() {
        Conductor.flowControlAvailableForTesting = false
        conductor.startFlowControlIfPossible()
        XCTAssertEqual(delegate.commands, [])
    }

    // MARK: - Why the monitor says it is off

    // The monitor says why this connection is unpaced, not what the setting says now: a
    // connection opened with the setting off stays unpaced after it is turned back on, and its
    // framer supports flow control all along.
    func testTheMonitorGivesTheReasonDecidedWhenTheConnectionStarted() throws {
        Conductor.flowControlAvailableForTesting = false
        conductor.startFlowControlIfPossible()
        let whileOff = try XCTUnwrap(FlowControlMonitor.reasonOff(conductor))
        XCTAssertTrue(whileOff.contains("advanced setting was off"), whileOff)
        Conductor.flowControlAvailableForTesting = true
        XCTAssertNil(conductor.flowController)
        XCTAssertEqual(FlowControlMonitor.reasonOff(conductor), whileOff)
    }

    func testTheMonitorSaysAFramerThatRefusedFlowControlDoesNotSupportIt() throws {
        conductor.startFlowControlIfPossible()
        reply(["unrecognized command"], status: 1)
        reply(["unrecognized command"], status: 1)
        let reason = try XCTUnwrap(FlowControlMonitor.reasonOff(conductor))
        XCTAssertTrue(reason.contains("does not support flow control"), reason)
        Conductor.flowControlAvailableForTesting = false
        XCTAssertEqual(FlowControlMonitor.reasonOff(conductor), reason, "the setting changing changes nothing")
    }

    func testTheMonitorSaysAChildWaitsForItsParent() throws {
        let child = makeChild()
        child.startFlowControlIfPossible()
        let reason = try XCTUnwrap(FlowControlMonitor.reasonOff(child))
        XCTAssertTrue(reason.contains("runs flow control version 2"), reason)
    }

    func testTheMonitorSaysAChildWasOffBecauseOfTheSettingNotItsParent() throws {
        Conductor.flowControlAvailableForTesting = false
        let child = makeChild()
        child.startFlowControlIfPossible()
        let reason = try XCTUnwrap(FlowControlMonitor.reasonOff(child))
        XCTAssertTrue(reason.contains("advanced setting was off"), reason)
    }

    func testTheMonitorGivesNoReasonWhileFlowControlRuns() {
        startFlowControl(version: 2)
        XCTAssertNil(FlowControlMonitor.reasonOff(conductor))
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

    // A recovered framer with flow control on is saved as possibly on, so a restore after this
    // turns it back on whatever the setting.
    func testARecoveredFramerWithFlowControlOnIsSavedAsPossiblyOn() throws {
        Conductor.flowControlAvailableForTesting = false
        let recovery = ConductorRecovery(pid: 123, dcsID: "dcs", tree: [:], sshargs: "host",
                                         boolArgs: "", clientUniqueID: "cid", version: 2,
                                         flow: "2 monotonic", parent: nil,
                                         it2Proxy: IT2ProxyState())
        let recovered = Conductor(recovery: recovery)
        recovered.flowTicksAutomatically = false
        XCTAssertTrue(recovered.flowMayBeOn)
        let json = try XCTUnwrap(recovered.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowTicksAutomatically = false
        delegate.reset()
        restored.didResynchronize()
        XCTAssertTrue(restored.queue.contains { $0.command == .framerFlowOn } ||
                      delegate.commands.contains(["flow", "on", "2"]))
    }

    // Whether the framer listens for it2 isn't saved, so a restored conductor asks again;
    // otherwise “Remote host can control iTerm2” stays disabled though it2 works.
    func testARestoredConductorListensForIt2AgainAfterResynchronizing() throws {
        conductor.it2Nonce = "nonce"
        conductor.it2SocketPath = "/home/u/.iterm2/it2/x.sock"
        let json = try XCTUnwrap(conductor.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowClock = { [unowned self] in self.now }
        restored.flowTicksAutomatically = false
        XCTAssertFalse(restored.it2ListenSucceeded)
        XCTAssertFalse(restored.it2ProxyActive)
        delegate.reset()
        restored.didResynchronize()
        let listen = ["it2listen", "/home/u/.iterm2/it2/x.sock"]
        // Answer each command in turn, as the framer would, through the listen.
        var answered = 0
        while answered < delegate.commands.count && !restored.it2ListenSucceeded {
            let command = delegate.commands[answered]
            answered += 1
            reply(command.first == "reset2" ? [command[1]] : [], conductor: restored)
        }
        XCTAssertTrue(delegate.commands.contains(listen), "\(delegate.commands)")
        XCTAssertTrue(restored.it2ListenSucceeded)
        XCTAssertEqual(delegate.commands[answered - 1], listen)
    }

    // A restored conductor that never set up it2 has nothing to listen for.
    func testARestoredConductorWithoutIt2DoesNotListen() throws {
        let json = try XCTUnwrap(conductor.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowClock = { [unowned self] in self.now }
        restored.flowTicksAutomatically = false
        delegate.reset()
        restored.didResynchronize()
        XCTAssertFalse(delegate.commands.contains { $0.first == "it2listen" })
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

    // The framer has no way to turn flow control off, so one that was controlled before a
    // restart stops for good once its leftover credit is spent unless a controller grants
    // again. That outranks the setting, which only decides whether new framers are controlled.
    func testARestoredFramerThatWasControlledIsControlledEvenWithTheSettingOff() throws {
        startFlowControl(version: 2)
        let json = try XCTUnwrap(conductor.jsonValue)
        Conductor.flowControlAvailableForTesting = false
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowClock = { [unowned self] in self.now }
        restored.flowTicksAutomatically = false
        delegate.reset()
        restored.didResynchronize()
        XCTAssertTrue(restored.queue.contains { $0.command == .framerFlowOn } ||
                      delegate.commands.contains(["flow", "on", "2"]))
    }

    func testARestoredFramerThatWasNeverControlledStaysOffWithTheSettingOff() throws {
        let json = try XCTUnwrap(conductor.jsonValue)
        Conductor.flowControlAvailableForTesting = false
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowTicksAutomatically = false
        restored.didResynchronize()
        XCTAssertFalse(restored.queue.contains { $0.command == .framerFlowOn } ||
                       delegate.commands.contains(["flow", "on", "2"]))
    }

    // A framer that refused flow control is not in its mode.
    func testARestoredFramerThatRefusedFlowControlStaysOffWithTheSettingOff() throws {
        conductor.startFlowControlIfPossible()
        reply(["unrecognized command"], status: 1)
        reply(["unrecognized command"], status: 1)
        let json = try XCTUnwrap(conductor.jsonValue)
        Conductor.flowControlAvailableForTesting = false
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowTicksAutomatically = false
        delegate.reset()
        restored.didResynchronize()
        XCTAssertFalse(restored.queue.contains { $0.command == .framerFlowOn } ||
                       delegate.commands.contains(["flow", "on", "2"]))
    }

    // An aborted `flow on` may have reached the framer, which then waits for grants. While the
    // connection lasts it is sent again, and the new controller drains to learn what is in
    // flight.
    func testAnAbortedFlowOnIsSentAgain() {
        conductor.startFlowControlIfPossible()
        conductor.forceReturnToGroundState()
        runMainQueue()
        XCTAssertEqual(delegate.commands.filter { $0.first == "flow" }.count, 2)
        reply(["2 boottime"])
        XCTAssertNotNil(conductor.flowController)
        XCTAssertTrue(conductor.flowController?.isDraining ?? false)
    }

    // Replies are matched by position. A reset's command absorbs replies to the commands it
    // aborted, so the `flow on` sent again must follow it, or it could take one of them.
    func testAFlowOnAbortedByAResetIsSentAgainAfterTheResetsCommand() {
        conductor.runRemoteCommand("busy") { _, _ in }
        conductor.startFlowControlIfPossible()
        XCTAssertFalse(delegate.commands.contains(["flow", "on", "2"]), "it waits behind busy")
        delegate.reset()
        conductor.reset()
        runMainQueue()
        XCTAssertEqual(delegate.commands.first?.first, "reset2")
        XCTAssertTrue(conductor.queue.contains { $0.command == .framerFlowOn } ||
                      delegate.commands.lastIndex(of: ["flow", "on", "2"]) ?? 0 > 0)
    }

    // One resynchronization sends `flow on` once and uses no more than one retry.
    func testResynchronizingWhileFlowOnIsPendingSendsItOnce() {
        conductor.startFlowControlIfPossible()
        delegate.reset()
        conductor.didResynchronize()
        runMainQueue()
        let flowOns = conductor.queue.filter { $0.command == .framerFlowOn }.count +
            delegate.commands.filter { $0 == ["flow", "on", "2"] }.count
        XCTAssertEqual(flowOns, 1)
    }

    // Quitting cancels commands without answering them; nothing is sent again.
    func testAnAbortedFlowOnIsNotSentAgainAfterQuitting() {
        conductor.startFlowControlIfPossible()
        conductor.quit()
        runMainQueue()
        XCTAssertEqual(delegate.commands.filter { $0.first == "flow" }.count, 1)
        XCTAssertFalse(conductor.queue.contains { $0.command == .framerFlowOn })
    }

    func testAnAbortedFlowOnIsNotSentAgainAfterUnhooking() {
        conductor.startFlowControlIfPossible()
        conductor.handleUnhook()
        runMainQueue()
        XCTAssertEqual(delegate.commands.filter { $0.first == "flow" }.count, 1)
        XCTAssertFalse(conductor.queue.contains { $0.command == .framerFlowOn })
    }

    // Something that keeps dropping the queue must not make this loop.
    func testAbortedFlowOnsAreRetriedOnlyAFewTimes() {
        conductor.startFlowControlIfPossible()
        for _ in 0..<10 {
            conductor.forceReturnToGroundState()
            runMainQueue()
        }
        XCTAssertEqual(delegate.commands.filter { $0.first == "flow" }.count, 4)
    }

    // A child waiting for its parent keeps waiting through the parent's retry.
    func testAWaitingChildStartsOnceItsParentsRetriedFlowOnSucceeds() {
        let child = makeChild()
        child.startFlowControlIfPossible()
        conductor.startFlowControlIfPossible()
        conductor.forceReturnToGroundState()
        runMainQueue()
        reply(["2 boottime"])
        XCTAssertNotNil(conductor.flowController)
        XCTAssertEqual(delegate.commands.last, ["drain"], "the parent may have had credit in flight")
        // The drain, then the ping that follows it, go ahead in the priority lane.
        for _ in 0..<3 where delegate.relayedCommands().isEmpty {
            reply()
        }
        XCTAssertEqual(delegate.relayedCommands(), [["flow", "on", "2"]], "\(delegate.commands)")
    }

    // After a restart, replies to commands sent before it can still arrive. Only `reset2`, whose
    // reply carries a code, lets the conductor skip them; with the old `reset` they were taken as
    // answers to new commands (a stale reply to `flow on` turned flow control off for good). So
    // the framer's version is saved with the conductor.
    func testARestoredConductorResynchronizesWithTheFramersOwnReset() throws {
        conductor.framerVersion = .v2  // As when it started the framer.
        let json = try XCTUnwrap(conductor.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        restored.flowTicksAutomatically = false
        XCTAssertEqual(restored.framerVersion, .v2)
        delegate.reset()
        restored.didResynchronize()
        XCTAssertEqual(delegate.commands.first?.first, "reset2", "\(delegate.commands)")
    }

    // Resynchronizing a nested connection clears every depth's queue and resets each. Clearing a
    // queue clears its ancestors' too, so a parent's reset sent before its child was cleared was
    // aborted at once, and the reply to it, with nothing waiting, was taken as the answer to the
    // next command: after a restart, an empty reply to `flow on` turned flow control off.
    func testResettingANestedConnectionLeavesEachDepthItsOwnReset() {
        conductor.framerVersion = .v2
        let child = makeChild()
        child.framerVersion = .v2
        child.resetTransitively()
        XCTAssertTrue(hasReset2(conductor), "\((conductor.contextsInFlight + conductor.queue).map(\.command))")
        XCTAssertTrue(hasReset2(child))
        // A reply to a command sent before, at the parent's depth, is skipped by the reset.
        reply()
        XCTAssertTrue(hasReset2(conductor), "the reset waits for its own code")
    }

    private func pendingCommands(_ c: Conductor) -> [Conductor.Command] {
        (c.contextsInFlight + c.queue).map(\.command)
    }

    private func hasReset2(_ c: Conductor) -> Bool {
        pendingCommands(c).contains {
            if case .framerReset2 = $0 { return true }
            return false
        }
    }

    // Every depth that frames is reset, not only the one above the depth that resynchronized:
    // clearing the queues cleared all of them.
    func testResettingADeepChainResetsEveryDepth() {
        conductor.framerVersion = .v2
        let middle = makeChild()
        middle.framerVersion = .v2
        let inner = makeConductor(parent: middle)
        inner.framedPID = 300
        inner.framerVersion = .v2
        inner.resetTransitively()
        XCTAssertTrue(hasReset2(conductor), "\(pendingCommands(conductor))")
        XCTAssertTrue(hasReset2(middle), "\(pendingCommands(middle))")
        XCTAssertTrue(hasReset2(inner))
    }

    // A conductor that does not frame, such as one whose host had no Python, has no framer to
    // reset: what it sent would be typed into whatever reads its terminal, a nested framer
    // included, and answered as if it were that one's.
    func testAConductorThatDoesNotFrameIsNotReset() {
        conductor.framerVersion = .v2
        let plain = makeChild()
        plain.framedPID = nil
        let inner = makeConductor(parent: plain)
        inner.framedPID = 300
        inner.framerVersion = .v2
        inner.resetTransitively()
        XCTAssertEqual(pendingCommands(plain), [], "nothing for a conductor that does not frame")
        XCTAssertTrue(hasReset2(conductor))
        XCTAssertTrue(hasReset2(inner))
    }

    // A conductor saved by an older iTerm2 does not know its framer's version, and a framer from
    // before 3.6 rejects `reset2`, which would leave the conductor waiting forever. It first
    // asks the framer to stat "/" spelled in a way of its own; the framer answers in order, so
    // once that spelling comes back every reply to an earlier command has passed, and the next
    // reply is `reset2`'s: its code, or a framer that predates it.
    /// Answers the command in flight as the framer would: a reset with its code, anything else
    /// with no lines.
    private func answer(_ c: Conductor) {
        if case .framerReset2(let code) = c.contextsInFlight.first?.command {
            reply([code], conductor: c)
        } else {
            reply(conductor: c)
        }
    }

    private func markerOfFileStat(_ command: [String]?) -> String? {
        guard let command, command.count == 3, command[0] == "file", command[1] == "stat",
              let data = Data(base64Encoded: command[2]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func testAFramerOfUnknownVersionIsFoundToSpeakReset2() throws {
        conductor.framerVersion = nil  // Saved by an older iTerm2.
        conductor.resetTransitively()
        let marker = try XCTUnwrap(markerOfFileStat(delegate.commands.first), "\(delegate.commands)")
        XCTAssertFalse(delegate.commands.contains { $0.first == "reset2" }, "not before the marker")
        // A reply to a command sent before, which failed: not taken for `reset2`'s.
        reply([], status: 1)
        XCTAssertNil(conductor.framerVersion)
        XCTAssertFalse(delegate.commands.contains { $0.first == "reset2" })
        reply(["{\"absolutePath\": \"\(marker)\", \"kind\": {\"folder\": {}}}"])
        let reset2 = try XCTUnwrap(delegate.commands.last)
        XCTAssertEqual(reset2.first, "reset2")
        reply([reset2[1]])
        XCTAssertEqual(conductor.framerVersion, .v2)
    }

    func testAFramerThatPredatesReset2IsResetTheOldWay() throws {
        conductor.framerVersion = nil
        conductor.resetTransitively()
        let marker = try XCTUnwrap(markerOfFileStat(delegate.commands.first))
        reply(["{\"absolutePath\": \"\(marker)\"}"])
        XCTAssertEqual(delegate.commands.last?.first, "reset2")
        delegate.reset()
        reply([], status: 1)  // What a framer from before 3.6 answers to a command it lacks.
        XCTAssertEqual(conductor.framerVersion, .v1)
        // The old reset clears autopolling, so it goes ahead of the autopoll queued after it.
        let next = (conductor.contextsInFlight + conductor.queue).map(\.command)
        XCTAssertEqual(next.first, .framerReset1, "\(next)")
        XCTAssertTrue(next.contains(.framerAutopoll))
    }

    // The marker is "/" spelled with "./" and "/" in a random order: it always exists, so the
    // framer can stat it, and its reply spells the path as it was given.
    func testTheResetMarkerIsTheRootSpelledUniquely() {
        let a = Conductor.resetMarkerPath()
        let b = Conductor.resetMarkerPath()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(URL(fileURLWithPath: a).resolvingSymlinksInPath().path, "/")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: a, isDirectory: &isDirectory) && isDirectory.boolValue)
        XCTAssertTrue(a.allSatisfy { $0 == "/" || $0 == "." })
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

    func testEveryDepthRestartsFlowControlWhenTheInnermostResynchronizes() {
        let child = makeConductor(parent: conductor)
        child.framedPID = 200
        child.didResynchronize()
        XCTAssertTrue(conductor.queue.contains { $0.command == .framerFlowOn } ||
                      delegate.commands.contains(["flow", "on", "2"]),
                      "the parent turns it on first")
        XCTAssertFalse(child.queue.contains { $0.command == .framerFlowOn })
        XCTAssertFalse(delegate.relayedCommands().contains(["flow", "on", "2"]))
        // The parent resets, then relays the child's reset; its flow on goes out once the
        // commands ahead of it are answered.
        XCTAssertEqual(delegate.commands.first?.first, "reset2", "the outermost resets first")
        for _ in 0..<5 where delegate.commands.last != ["flow", "on", "2"] {
            answer(conductor)
        }
        XCTAssertEqual(delegate.commands.last, ["flow", "on", "2"])
        reply(["2 boottime"])
        XCTAssertNotNil(conductor.flowController)
        XCTAssertTrue(child.queue.contains { $0.command == .framerFlowOn } ||
                      delegate.relayedCommands().last == ["flow", "on", "2"],
                      "then the child, which controls its own framer")
        // The child answers the commands its resynchronization queued first; the parent
        // relays each in a send of its own, answered empty.
        for _ in 0..<10 where delegate.relayedCommands().last != ["flow", "on", "2"] {
            if child.queue.contains(where: { $0.command == .framerFlowOn }) {
                answer(child)
            }
            answer(conductor)
        }
        XCTAssertEqual(delegate.relayedCommands().last, ["flow", "on", "2"])
        XCTAssertNil(child.flowController)
        reply(["2 boottime"], conductor: child)
        XCTAssertNotNil(child.flowController)
        XCTAssertTrue(child.flowController?.isDraining ?? false,
                      "its framer may still be spending credit from before the restart")
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

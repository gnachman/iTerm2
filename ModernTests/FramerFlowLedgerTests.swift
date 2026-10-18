//
//  FramerFlowLedgerTests.swift
//  iTerm2 ModernTests
//
//  Flow control measures delay when a frame is parsed and counts it as consumed once the session
//  has executed it. The screen records each flow-controlled frame in a ledger when it is parsed
//  and when it executes, and the conductor takes those records on the main thread and feeds them
//  to its controller.
//

import XCTest
@testable import iTerm2SharedARC

final class FramerFlowLedgerTests: XCTestCase {
    private func osc134(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]134;:\(payload)\u{1b}\\".utf8)
    }

    func testNothingIsRecordedUntilActive() {
        let ledger = FramerFlowLedger(clock: { 5 })
        ledger.frameDidArrive(bytes: 10, sendMilliseconds: 99, flags: 0)
        XCTAssertFalse(ledger.isActive)
        XCTAssertEqual(ledger.takeEvents(), [])
    }

    func testRecordsInOrderAndWakesOncePerBatch() {
        let ledger = FramerFlowLedger(clock: { 5 })
        let woke = expectation(description: "woke")
        woke.expectedFulfillmentCount = 1
        woke.assertForOverFulfill = true
        ledger.activate { woke.fulfill() }
        ledger.frameDidArrive(bytes: 10, sendMilliseconds: 99, flags: 1)
        ledger.frameDidExecute(bytes: 10)
        wait(for: [woke], timeout: 10)
        XCTAssertEqual(ledger.takeEvents(), [.arrived(time: 5, flow: 0, sendMilliseconds: 99, bytes: 10, flags: 1),
                                              .executed(time: 5, bytes: 10)])
        XCTAssertEqual(ledger.takeEvents(), [])
        ledger.deactivate()
        ledger.frameDidArrive(bytes: 1, sendMilliseconds: 99, flags: 0)
        XCTAssertEqual(ledger.takeEvents(), [])
    }

    func testTheScreenRecordsArrivalAndExecutionOfControlledFramesOnly() {
        let harness = TerminalTestHarness()
        let ledger = FramerFlowLedger(clock: { 7 })
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.flowLedger = ledger
        })
        ledger.activate {}
        harness.send(Array("\u{1b}P2000p0 boolargs -\n".utf8))
        harness.send(osc134("%output a 100 -1 0 123456 1") + Array("hello".utf8) + osc134("%end a"))
        harness.send(osc134("%output b 100 -1 0") + Array("old".utf8) + osc134("%end b"))
        harness.sync()
        XCTAssertEqual(ledger.takeEvents(), [.arrived(time: 7, flow: 0, sendMilliseconds: 123456, bytes: 5, flags: 1),
                                              .executed(time: 7, bytes: 5)])
    }

    // A workgroup peer's pane output counts as the pane's on arrival and leaves for the pane's
    // session then; the leader never executes it, so it is not the leader's consumption.
    func testPaneFramesArriveAsThePanesAndAreNotExecutedHere() {
        let harness = TerminalTestHarness()
        let ledger = FramerFlowLedger(clock: { 7 })
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.flowLedger = ledger
        })
        ledger.activate {}
        harness.send(Array("\u{1b}P2000p0 boolargs -\n".utf8))
        harness.send(osc134("%output a 77 3 0 555 1") + Array("pane!".utf8) + osc134("%end a"))
        harness.sync()
        XCTAssertEqual(ledger.takeEvents(), [.arrived(time: 7, flow: 77, sendMilliseconds: 555, bytes: 5, flags: 1)])
    }

    // it2 data under version 2 carries the framer's clock and flags; credit counts decoded bytes.
    func testIT2DataArrivesAsIT2s() {
        let harness = TerminalTestHarness()
        let ledger = FramerFlowLedger(clock: { 7 })
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.flowLedger = ledger
        })
        ledger.activate {}
        harness.send(Array("\u{1b}P2000p0 boolargs -\n".utf8))
        harness.send(osc134("%it2 c1 data aGVsbG8= 99 1"))
        harness.send(osc134("%it2 c1 data aGVsbG8="))
        harness.sync()
        XCTAssertEqual(ledger.takeEvents(), [.arrived(time: 7, flow: FramerFlowLedger.it2Flow,
                                                       sendMilliseconds: 99, bytes: 5, flags: 1)])
    }

    // A read the parser holds entirely (here, the start of an escape sequence) makes no tokens.
    // Its bytes still count once read, or the pane's flow would wait for them forever.
    func testBytesThatMakeNoTokensAreStillCounted() {
        let harness = TerminalTestHarness()
        let ledger = FramerFlowLedger(clock: { 9 })
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.consumptionLedger = ledger
        })
        ledger.activate {}
        harness.send(Array("\u{1b}[".utf8))
        harness.send(Array("31mx".utf8))
        harness.sync()
        let executed = ledger.takeEvents().reduce(0) { total, event in
            if case let .executed(_, bytes) = event {
                return total + bytes
            }
            return total
        }
        XCTAssertEqual(executed, 6)
    }

    // A background session yields to a busy foreground one after each token. Yielding after
    // the last token of a batch used to skip counting the batch, so a hidden workgroup peer's
    // output went uncounted while its leader was busy, and the pane's flow stalled for good.
    func testABackgroundSessionCountsWhatItRunsWhileAnotherIsBusy() {
        let busy = TerminalTestHarness()
        var unpauser: Unpauser?
        busy.screen.performBlock(joinedThreads: { _, mutableState, _ in
            unpauser = mutableState.tokenExecutor.pause()
        })
        // Queued but held, so the foreground session has tokens throughout.
        busy.send(Array("busy".utf8))

        let background = TerminalTestHarness()
        let ledger = FramerFlowLedger(clock: { 9 })
        background.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.tokenExecutor.isBackgroundSession = true
            mutableState.consumptionLedger = ledger
        })
        ledger.activate {}
        background.send(Array("hello".utf8))
        let deadline = Date(timeIntervalSinceNow: 5)
        var executed = 0
        while executed < 5 && Date() < deadline {
            background.sync()
            executed += ledger.takeEvents().reduce(0) { total, event in
                if case let .executed(_, bytes) = event {
                    return total + bytes
                }
                return total
            }
        }
        unpauser?.unpause()
        busy.sync()
        XCTAssertEqual(executed, 5)
    }

    // A pane's session records what its executor runs, for the pane's flow.
    func testAPaneSessionRecordsWhatItExecutes() {
        let harness = TerminalTestHarness()
        let ledger = FramerFlowLedger(clock: { 9 })
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.consumptionLedger = ledger
        })
        ledger.activate {}
        harness.send(Array("hello".utf8))
        harness.sync()
        let executed = ledger.takeEvents().reduce(0) { total, event in
            if case let .executed(_, bytes) = event {
                return total + bytes
            }
            return total
        }
        XCTAssertEqual(executed, 5)
    }
}

/// The conductor takes the ledger's records and feeds them to its controller.
@MainActor
final class ConductorFlowLedgerTests: XCTestCase {
    private final class Delegate: NSObject, ConductorDelegate {
        var writes = [String]()
        let ledger = FramerFlowLedger(clock: { 1000 })
        func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                              completion: @escaping (Bool, Bool, Bool) -> Void) {}
        func conductorDismissIT2AuthorizationPrompt(guid: String) {}
        func conductorWrite(string: String) { writes.append(string) }
        func conductorAbort(reason: String) {}
        func conductorQuit() {}
        func conductorStateDidChange() {}
        func conductorStopQueueingInput() {}
        func conductorSendInitialText() {}
        func conductorFlowLedger() -> FramerFlowLedger? { ledger }
        let guid = "g"
    }

    override func tearDown() {
        Conductor.flowControlAvailableForTesting = nil
        super.tearDown()
    }

    func testExecutedFramesReturnCredit() {
        Conductor.flowControlAvailableForTesting = true
        let delegate = Delegate()
        let conductor = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
        conductor.framedPID = 100
        conductor.delegate = delegate
        conductor.flowClock = { 1000.05 }
        conductor.flowTicksAutomatically = false
        conductor.startFlowControlIfPossible()
        conductor.handleCommandBegin(identifier: "x", depth: 0)
        conductor.handle(line: "1 boottime", depth: 0)
        conductor.handleCommandEnd(identifier: "x", type: "f", status: 0, depth: 0)
        XCTAssertTrue(delegate.ledger.isActive)

        delegate.writes = []
        delegate.ledger.frameDidArrive(bytes: 4096, sendMilliseconds: 5_000, flags: 0)
        delegate.ledger.frameDidExecute(bytes: 4096)
        conductor.flowTick()
        XCTAssertEqual(conductor.flowController?.consumed, 4096)
        let grant = Conductor.encode(arguments: ["grant", "4096"], isFramer: true, linePrefix: "") + "\n"
        XCTAssertEqual(delegate.writes, [grant])

        conductor.quit()
        XCTAssertFalse(delegate.ledger.isActive)
    }

    // Frames that follow the reply to flow on can be parsed and executed before the reply is
    // handled. They must still count, or credit the framer spent stays counted as outstanding.
    func testFramesBeforeTheReplyIsHandledAreCounted() {
        Conductor.flowControlAvailableForTesting = true
        let delegate = Delegate()
        let conductor = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
        conductor.framedPID = 100
        conductor.delegate = delegate
        conductor.flowClock = { 1000.05 }
        conductor.flowTicksAutomatically = false
        conductor.startFlowControlIfPossible()
        XCTAssertTrue(delegate.ledger.isActive)
        delegate.ledger.frameDidArrive(bytes: 3000, sendMilliseconds: 5_000, flags: 0)
        delegate.ledger.frameDidExecute(bytes: 3000)
        conductor.handleCommandBegin(identifier: "x", depth: 0)
        conductor.handle(line: "1 boottime", depth: 0)
        conductor.handleCommandEnd(identifier: "x", type: "f", status: 0, depth: 0)
        XCTAssertEqual(conductor.flowController?.consumed, 3000)
        XCTAssertEqual(conductor.flowController?.arrived, 3000)
    }

    func testAnOlderFramerReleasesTheLedger() {
        Conductor.flowControlAvailableForTesting = true
        let delegate = Delegate()
        let conductor = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
        conductor.framedPID = 100
        conductor.delegate = delegate
        conductor.flowTicksAutomatically = false
        conductor.startFlowControlIfPossible()
        // It refuses version 2, then version 1.
        for _ in 0..<2 {
            conductor.handleCommandBegin(identifier: "x", depth: 0)
            conductor.handleCommandEnd(identifier: "x", type: "f", status: 1, depth: 0)
        }
        XCTAssertFalse(delegate.ledger.isActive)
    }
}

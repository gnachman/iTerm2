//
//  FramerFlowControllerTests.swift
//  iTerm2 ModernTests
//
//  The flow controller sizes how much credit the framer may have outstanding from how long
//  output waits on its way from the framer. These tests drive its pieces with explicit times;
//  FramerFlowSimulationTests runs it over simulated connections.
//

import XCTest
@testable import iTerm2SharedARC

final class FramerFlowControllerTests: XCTestCase {
    private typealias Controller = FramerFlowController
    private let KB = 1024

    private final class Sent {
        var commands = [Controller.Command]()
        var grants: [Int] {
            commands.compactMap { if case .grant(_, let n) = $0 { return n } else { return nil } }
        }
        var drains: Int { commands.filter { $0 == .drain }.count }
        var pings: Int { commands.filter { $0 == .ping }.count }
    }

    private func makeController(now: TimeInterval = 0,
                                recovering: Bool = false) -> (Controller, Sent) {
        let sent = Sent()
        let controller = Controller(now: now, recovering: recovering) { sent.commands.append($0) }
        return (controller, sent)
    }

    /// A frame's send time on a framer clock `offset` ms ahead of iTerm2's, which spent
    /// `delay` seconds between the framer and arriving at `now`.
    private func sendMS(now: TimeInterval, delay: TimeInterval, offset: Int64 = 5_000_000) -> Int64 {
        return Int64(((now - delay) * 1000).rounded()) + offset
    }

    private func arrive(_ c: Controller, at now: TimeInterval, delay: TimeInterval,
                        bytes: Int = 1000, limited: Bool = false, exempt: Bool = false) {
        c.frameDidArrive(now: now, sendMilliseconds: sendMS(now: now, delay: delay),
                         bytes: bytes, limited: limited, exempt: exempt)
    }

    /// A frame arrives and the session consumes it at once.
    private func execute(_ c: Controller, at now: TimeInterval, delay: TimeInterval,
                         bytes: Int = 1000, limited: Bool = false) {
        arrive(c, at: now, delay: delay, bytes: bytes, limited: limited)
        c.flowDidConsume(.leader, bytes: bytes, now: now)
    }

    // MARK: - Pieces

    func testWindowedMinimumAgesOutAfterTwoBuckets() {
        var w = WindowedExtreme(keepsMinimum: true)
        w.add(5, now: 0, window: 10)
        w.add(7, now: 1, window: 10)
        XCTAssertEqual(w.value(now: 4, window: 10), 5)
        w.add(8, now: 6, window: 10)  // Rotates: 5 is now in the previous bucket.
        XCTAssertEqual(w.value(now: 6, window: 10), 5)
        w.add(9, now: 11, window: 10)  // Rotates again: the bucket with 5 is gone.
        XCTAssertEqual(w.value(now: 11, window: 10), 8)
    }

    func testQueueingDelayCancelsTheClockOffsetAndIsNeverNegative() {
        let (c, _) = makeController()
        c.roundTripDidComplete(sentAt: 0, now: 0.1)
        execute(c, at: 1.0, delay: 0.040)  // The empty path.
        for (i, queued) in [0.190, 0.230, 0.150, 0.200].enumerated() {
            execute(c, at: 2.0 + 0.02 * Double(i), delay: 0.040 + queued)
        }
        XCTAssertEqual(c.queueingDelay(now: 2.07)!, 0.150, accuracy: 0.002)
        // A reading below the baseline becomes the baseline at once: dq is zero, not negative.
        execute(c, at: 2.08, delay: 0.010)
        XCTAssertEqual(c.queueingDelay(now: 2.08), 0)
    }

    func testFlowOnStartsWithTheInitialCredit() {
        let (c, sent) = makeController()
        XCTAssertEqual(c.granted, 8 * KB)
        XCTAssertEqual(c.outstanding, 8 * KB)
        c.tick(now: 0.02)
        XCTAssertEqual(sent.commands, [], "nothing to top up yet")
    }

    func testConsumedCreditIsGrantedAgain() {
        let (c, sent) = makeController()
        execute(c, at: 0.05, delay: 0.03, bytes: 4 * KB)
        c.tick(now: 0.06)
        XCTAssertEqual(sent.grants, [4 * KB])
        XCTAssertEqual(c.outstanding, 8 * KB)
    }

    func testSmallTopUpsWait() {
        let (c, sent) = makeController()
        execute(c, at: 0.05, delay: 0.03, bytes: 100)
        c.tick(now: 0.06)
        XCTAssertEqual(sent.grants, [], "less than W/4")
    }

    func testExemptBytesAreNotCounted() {
        let (c, sent) = makeController()
        arrive(c, at: 0.05, delay: 0.03, bytes: 4 * KB, exempt: true)
        c.flowDidConsume(.leader, bytes: 4 * KB, now: 0.05)
        c.tick(now: 0.06)
        XCTAssertEqual(c.consumed, 0)
        XCTAssertEqual(sent.grants, [])
    }

    // MARK: - Drains

    func testDrainReplyResynchronizesTheCount() {
        let (c, sent) = makeController()
        execute(c, at: 0.05, delay: 0.03, bytes: 4 * KB)
        c.tick(now: 0.06)  // Grants 4 KB; outstanding 8 KB.
        arrive(c, at: 0.1, delay: 0.03, bytes: 2 * KB)
        c.valveDidOpen(now: 0.1)
        XCTAssertEqual(sent.drains, 1)
        // The framer discarded what credit it had. 2 KB arrived and is not executed yet.
        c.drainDidReply(now: 0.2)
        XCTAssertEqual(c.outstanding, 2 * KB)
        // Delay is measured on arrival, so the path is empty once the reply is in, whatever the
        // session has yet to execute.
        XCTAssertEqual(sent.pings, 1)
        c.flowDidConsume(.leader, bytes: 2 * KB, now: 0.25)
        XCTAssertEqual(c.outstanding, 0)
    }

    func testPingAfterDrainTakesARoundTripAndRestoresTheWindow() {
        let (c, sent) = makeController()
        let before = c.window
        c.valveDidOpen(now: 1.0)
        c.drainDidReply(now: 1.2)
        XCTAssertEqual(sent.pings, 1)
        c.pingDidReply(roundTrip: 0.05, now: 1.25)
        XCTAssertEqual(c.rttMin(now: 1.25), 0.05, accuracy: 1e-9)
        XCTAssertEqual(c.window, before)
        XCTAssertEqual(sent.commands.last, .grant(.leader, Int(before)))
        XCTAssertFalse(c.isDraining)
    }

    func testAnAbandonedDrainKeepsLaterGrants() {
        let (c, sent) = makeController()
        c.valveDidOpen(now: 1.0)
        // Sent before the drain reached the framer.
        execute(c, at: 1.5, delay: 0.5, bytes: 4 * KB)
        c.tick(now: 3.5)  // Past the 2 s deadline: abandoned, and the window topped up.
        XCTAssertFalse(c.isDraining)
        XCTAssertEqual(sent.grants, [4 * KB])
        // The late reply: the framer discarded its credit, then got the 4 KB grant.
        c.drainDidReply(now: 4.0)
        XCTAssertEqual(c.outstanding, 4 * KB)
    }

    func testRecoveryIsAResetDrainWithoutADeadline() {
        let (c, sent) = makeController(recovering: true)
        XCTAssertTrue(c.isDraining)
        XCTAssertTrue(c.quarantined)
        XCTAssertEqual(c.granted, 0)
        // Backlog sent while no one was reading: minutes old, so it must not be sampled.
        arrive(c, at: 1, delay: 120, bytes: 3 * KB, limited: true)
        c.tick(now: 30)
        XCTAssertTrue(c.isDraining, "a reset's drain is never abandoned")
        c.drainDidReply(now: 31)  // The end of the recovery block.
        c.flowDidConsume(.leader, bytes: 3 * KB, now: 32)
        XCTAssertNil(c.queueingDelay(now: 32), "the backlog was not sampled")
        XCTAssertEqual(sent.commands, [.ping])
        c.pingDidReply(roundTrip: 0.08, now: 32.08)
        XCTAssertFalse(c.quarantined)
        XCTAssertEqual(sent.commands.last, .grant(.leader, 8 * KB))
        XCTAssertEqual(c.rttMin(now: 32.08), 0.08, accuracy: 1e-9)
    }

    func testQuarantineTakesNoSamples() {
        let (c, _) = makeController()
        c.reset(now: 1)
        execute(c, at: 1.5, delay: 120, limited: true)
        c.roundTripDidComplete(sentAt: 1.0, now: 1.6)
        XCTAssertNil(c.queueingDelay(now: 1.5))
        XCTAssertEqual(c.statistics.roundTripSamples, 0)
    }

    func testSilenceDuringAFloodResetsTheBaselines() {
        let (c, sent) = makeController()
        execute(c, at: 0.1, delay: 0.05, limited: true)
        XCTAssertEqual(sent.drains, 0)
        // Nothing arrives for 3 s (more than max(2 s, 4 x (rtt + target))), then output resumes.
        execute(c, at: 3.1, delay: 0.05, limited: true)
        XCTAssertEqual(c.statistics.silences, 1)
        XCTAssertEqual(sent.drains, 1)
        XCTAssertTrue(c.quarantined)
    }

    func testSilenceAfterOrdinaryOutputIsNotSuspicious() {
        let (c, sent) = makeController()
        execute(c, at: 0.1, delay: 0.05, limited: false)
        execute(c, at: 60, delay: 0.05, limited: false)
        XCTAssertEqual(c.statistics.silences, 0)
        XCTAssertEqual(sent.drains, 0)
    }

    // MARK: - Grants and the window

    func testIdleSessionSendsNothing() {
        let (c, sent) = makeController()
        var t = 0.0
        while t < 30 {
            t += 0.02
            c.tick(now: t)
        }
        XCTAssertEqual(sent.commands, [])
    }

    func testTypingNeitherDrainsNorChangesTheWindow() {
        let (c, sent) = makeController()
        let window = c.window
        var t = 0.0
        var step = 0
        while t < 60 {
            t += 0.02
            step += 1
            if step % 25 == 0 {
                execute(c, at: t, delay: 0.03, bytes: 3)
            }
            c.tick(now: t)
        }
        XCTAssertEqual(sent.drains, 0)
        XCTAssertEqual(c.window, window)
    }

    func testHeartbeatWhenTheFramerMayBeBlocked() {
        let (c, sent) = makeController()
        // A limited frame arrives but is not executed: the session is busy.
        arrive(c, at: 0.1, delay: 0.05, bytes: 8 * KB, limited: true)
        c.tick(now: 0.5)
        XCTAssertEqual(sent.grants, [])
        c.tick(now: 1.1)
        XCTAssertEqual(sent.grants, [0], "a zero-byte grant shows the controller is alive")
        XCTAssertEqual(c.statistics.heartbeats, 1)
    }

    func testDecreaseIsCappedAtHalfAndOncePerRoundTrip() {
        let (c, _) = makeController()
        c.roundTripDidComplete(sentAt: 0, now: 0.1)
        // Grow the window in slow start with window-limited frames on an empty path, stopping
        // before a drain is due (nine times the 100 ms a fresh start counts as).
        var t = 0.1
        while t < 0.8 {
            t += 0.025
            execute(c, at: t, delay: 0.05, bytes: 8 * KB, limited: true)
            c.tick(now: t)
        }
        XCTAssertFalse(c.isDraining)
        let grown = c.window
        XCTAssertGreaterThan(grown, Double(8 * KB))
        // A queue far above target: the window halves, and not again within rttmin.
        t += 0.025
        execute(c, at: t, delay: 1.05, limited: true)
        execute(c, at: t + 0.1, delay: 1.05, limited: true)
        c.tick(now: t + 0.1)
        let halved = c.window
        XCTAssertEqual(halved, max(grown / 2, c.floor(now: t + 0.1)), accuracy: 1)
        c.tick(now: t + 0.15)
        XCTAssertEqual(c.window, halved, accuracy: 1, "at most once per rttmin")
        XCTAssertEqual(c.statistics.decreases, 1)
    }

    // A tick after a long gap (an idle session stops ticking; a busy main thread delays the
    // timer) counts at most a round trip toward growth, not the whole gap.
    func testALongGapBetweenTicksGrowsTheWindowByAtMostAStep() {
        let (c, _) = makeController()
        c.roundTripDidComplete(sentAt: 0, now: 0.1)
        var t = 0.1
        // Out of slow start: a queue above target / 2.
        execute(c, at: t, delay: 0.05, bytes: 1000, limited: true)
        execute(c, at: t + 0.01, delay: 0.12, bytes: 1000, limited: true)
        c.tick(now: t + 0.01)
        t += 0.2
        execute(c, at: t, delay: 0.06, bytes: 1000, limited: true)
        c.tick(now: t)
        let before = c.window
        t += 30
        execute(c, at: t, delay: 0.06, bytes: 1000, limited: true)
        c.tick(now: t)
        let step = max(c.parameters.stepMinimum, before / c.parameters.growthDivisor)
        XCTAssertLessThanOrEqual(c.window, before + step + 1)
    }

    // MARK: - Flows

    private func grants(_ sent: Sent, to flow: Controller.Flow) -> [Int] {
        sent.commands.compactMap { if case .grant(flow, let n) = $0 { return n } else { return nil } }
    }

    // A pane gets credit of its own when it starts, drawn from the window.
    func testANewFlowGetsCreditAtOnce() {
        let (c, sent) = makeController()
        c.flowDidStart(.pane(7), now: 0.01)
        XCTAssertEqual(grants(sent, to: .pane(7)).count, 1)
        XCTAssertEqual(c.outstanding(of: .pane(7)), grants(sent, to: .pane(7)).first)
    }

    // Credit comes back to a flow only when its own session consumes.
    func testCreditReturnsToTheFlowThatConsumed() {
        let (c, sent) = makeController()
        c.flowDidStart(.pane(7), now: 0)
        let paneCredit = c.outstanding(of: .pane(7))!
        c.frameDidArrive(now: 0.05, flow: .pane(7), sendMilliseconds: sendMS(now: 0.05, delay: 0.03),
                         bytes: paneCredit, limited: true, exempt: false)
        arrive(c, at: 0.05, delay: 0.03, bytes: 4 * KB)
        c.flowDidConsume(.leader, bytes: 4 * KB, now: 0.05)
        sent.commands.removeAll()
        c.tick(now: 0.06)
        XCTAssertEqual(grants(sent, to: .pane(7)), [], "the pane's session has not consumed")
        XCTAssertFalse(grants(sent, to: .leader).isEmpty)
        c.flowDidConsume(.pane(7), bytes: paneCredit, now: 0.07)
        c.tick(now: 0.09)
        XCTAssertFalse(grants(sent, to: .pane(7)).isEmpty)
    }

    // A flow whose session stops consuming is capped, and the others get the rest of the window.
    func testAFlowThatFallsBehindIsCappedAndOthersGetTheRest() {
        let (c, _) = makeController()
        c.roundTripDidComplete(sentAt: 0, now: 0.1)
        c.flowDidStart(.pane(7), now: 0.1)
        var t = 0.1
        // Both flood; the pane's session never consumes. Stops before a drain is due (nine
        // times the 100 ms a fresh start counts as).
        while t < 0.8 {
            t += 0.025
            execute(c, at: t, delay: 0.05, bytes: 2 * KB, limited: true)
            c.frameDidArrive(now: t, flow: .pane(7), sendMilliseconds: sendMS(now: t, delay: 0.05),
                             bytes: 512, limited: true, exempt: false)
            c.tick(now: t)
        }
        XCTAssertGreaterThan(c.statistics.capDecreases, 0)
        XCTAssertGreaterThan(c.consumptionDelay(of: .pane(7), now: t)!, c.target(now: t))
        XCTAssertEqual(c.window(of: .pane(7))!, c.floor(now: t), accuracy: 1, "capped down to the floor")
        XCTAssertEqual(c.window(of: .leader)!, c.window - c.window(of: .pane(7))!, accuracy: 1)
    }

    // Flows that are not using their credit hold the floor; the busy one gets the window.
    func testIdleFlowsHoldTheFloor() {
        let (c, _) = makeController()
        c.roundTripDidComplete(sentAt: 0, now: 0.1)
        c.flowDidStart(.pane(7), now: 0.1)
        c.flowDidStart(.pane(8), now: 0.1)
        var t = 0.1
        while t < 0.5 {
            t += 0.025
            c.frameDidArrive(now: t, flow: .pane(7), sendMilliseconds: sendMS(now: t, delay: 0.05),
                             bytes: 2 * KB, limited: true, exempt: false)
            c.flowDidConsume(.pane(7), bytes: 2 * KB, now: t)
            c.tick(now: t)
        }
        let floor = c.floor(now: t)
        XCTAssertEqual(c.window(of: .leader)!, floor, accuracy: 1)
        XCTAssertEqual(c.window(of: .pane(8))!, floor, accuracy: 1)
        XCTAssertEqual(c.window(of: .pane(7))!, c.window, accuracy: 1, "idle credit is not on the path")
    }

    // A drain discards every flow's credit; its reply sets each flow's count to what arrived and
    // was not consumed.
    func testADrainResynchronizesEveryFlow() {
        let (c, _) = makeController()
        c.flowDidStart(.pane(7), now: 0)
        c.frameDidArrive(now: 0.1, flow: .pane(7), sendMilliseconds: sendMS(now: 0.1, delay: 0.05),
                         bytes: 1000, limited: false, exempt: false)
        arrive(c, at: 0.1, delay: 0.05, bytes: 3000)
        c.flowDidConsume(.leader, bytes: 1000, now: 0.1)
        c.valveDidOpen(now: 0.2)
        c.drainDidReply(now: 0.3)
        XCTAssertEqual(c.outstanding(of: .pane(7)), 1000)
        XCTAssertEqual(c.outstanding(of: .leader), 2000)
    }

    // An ended pane's credit goes with it.
    func testAnEndedFlowIsForgotten() {
        let (c, _) = makeController()
        c.flowDidStart(.pane(7), now: 0)
        c.flowDidEnd(.pane(7))
        XCTAssertNil(c.window(of: .pane(7)))
        XCTAssertEqual(c.outstanding, 8 * KB)
    }
}

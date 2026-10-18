//
//  FramerFlowSimulationTests.swift
//  iTerm2 ModernTests
//
//  The flow controller over simulated connections. A framer keeps credit per flow and reads its
//  sources round-robin, as framer.py does; everything it writes, replies included, crosses one
//  in-order path with a fixed rate and one-way delay; and on iTerm2's side each flow has its own
//  consumer. The leader's parser stops reading when the leader's token queue is full, as
//  TokenExecutor's semaphore makes it, so a slow leader delays every flow's arrivals. Pane output
//  leaves at parse time for the pane's own session. The leader has the framer's echo allowance:
//  with no credit, a write of at most 256 bytes goes out exempt, from a bucket of 256 bytes
//  refilled at 2.5 KB/s. Peers have none.
//
//  What Ctrl-C waits out for a flow is everything of it the framer has already sent: what is
//  still on the path, then what its session has yet to consume.
//

import XCTest
@testable import iTerm2SharedARC

final class FramerFlowSimulationTests: XCTestCase {
    typealias Controller = FramerFlowController
    typealias Flow = Controller.Flow
    private static let KB = 1024.0

    enum Source {
        case flood
        case idle
        /// `bytes` written every `every` seconds, like echo while typing.
        case typing(every: TimeInterval, bytes: Int)
        /// Floods from the given time on.
        case floodFrom(TimeInterval)
    }

    enum Consumer {
        /// Consumes on arrival.
        case immediate
        /// Consumes this many bytes a second.
        case rate(Double)
        /// Consumes on arrival until the given time, then never again.
        case stallsAt(TimeInterval)
    }

    struct FlowSpec {
        var flow: Flow
        var source: Source
        var consumer: Consumer
    }

    struct FlowResult {
        /// Bytes consumed after the warm-up as a share of what the path could carry.
        var utilization: Double
        /// The most Ctrl-C would have waited after the warm-up, in seconds.
        var worstBacklog: TimeInterval
        /// The longest a typed write took from the program to being consumed.
        var worstEcho: TimeInterval
        /// The most bytes that waited to be consumed at once.
        var worstQueue: Double
        /// The largest window the flow had.
        var largestWindow: Double
    }

    struct Result {
        var controller: Controller
        var flows: [Flow: FlowResult]
        var utilization: Double { flows.values.reduce(0) { $0 + $1.utilization } }
    }

    private struct Frame {
        var at: TimeInterval
        var flow: Flow?
        var bytes: Int
        var sentAt: TimeInterval
        var limited: Bool
        var exempt = false
        var reply: Controller.Command?
    }

    private final class FlowModel {
        let spec: FlowSpec
        var credit = 0
        /// Written by the program, not yet read by the framer.
        var pending = 0
        var queue = 0.0
        var consumedTotal = 0
        /// (offset in the flow's bytes, when written) for typed writes not yet consumed.
        var typed = [(offset: Int, at: TimeInterval)]()
        var writtenTotal = 0
        var nextTyping: TimeInterval = 0
        var lastArrivalOnPath: TimeInterval?
        var bucket = 256.0
        var bytesOnPath = 0
        var result = FlowResult(utilization: 0, worstBacklog: 0, worstEcho: 0, worstQueue: 0, largestWindow: 0)
        var consumedAfterWarmup = 0.0

        init(_ spec: FlowSpec) {
            self.spec = spec
        }

        func produce(at t: TimeInterval) {
            switch spec.source {
            case .flood:
                pending = Int.max / 2
            case .floodFrom(let start):
                if t >= start {
                    pending = Int.max / 2
                }
            case .idle:
                break
            case let .typing(every, bytes):
                if t >= nextTyping {
                    nextTyping = t + every
                    pending += bytes
                    writtenTotal += bytes
                    typed.append((writtenTotal, t))
                }
            }
        }

        func consumable(at t: TimeInterval, dt: TimeInterval) -> Double {
            switch spec.consumer {
            case .immediate:
                return queue
            case .rate(let r):
                return min(queue, r * dt)
            case .stallsAt(let stall):
                return t < stall ? queue : 0
            }
        }

        /// What Ctrl-C would wait out now: the path, then the session.
        func backlog(at t: TimeInterval) -> TimeInterval {
            let path = max(0, (lastArrivalOnPath ?? t) - t)
            switch spec.consumer {
            case .immediate:
                return path
            case .rate(let r):
                return max(path, (queue + Double(bytesOnPath)) / r)
            case .stallsAt:
                return path
            }
        }
    }

    private func simulate(rate: Double,
                          oneWay: TimeInterval,
                          seconds: TimeInterval,
                          warmup: TimeInterval = 10,
                          leaderQueueLimit: Double = 160 * KB,
                          flows specs: [FlowSpec]) -> Result {
        var nextDeparture: TimeInterval = 0
        var downstream = [Frame]()
        var upstream = [(at: TimeInterval, command: Controller.Command)]()
        var pending = [Controller.Command]()
        var pingSentAt = [TimeInterval]()
        let models = specs.map(FlowModel.init)
        var byFlow = [Flow: FlowModel]()
        for model in models {
            byFlow[model.spec.flow] = model
        }
        let c = Controller(now: 0, recovering: false) { pending.append($0) }
        byFlow[.leader]?.credit = c.parameters.initialCredit
        // The reply to flow on is the first round trip.
        c.roundTripDidComplete(sentAt: 0, now: 2 * oneWay)
        for model in models where model.spec.flow != .leader {
            c.flowDidStart(model.spec.flow, now: 2 * oneWay)
        }
        func arrival(_ bytes: Int, sentAt t: TimeInterval) -> TimeInterval {
            nextDeparture = max(nextDeparture, t) + Double(bytes) / rate
            return nextDeparture + oneWay
        }
        let dt = 0.001
        var t = 0.0
        var nextTick = 0.0
        var rotation = 0
        while t < seconds {
            t += dt
            while let first = upstream.first, first.at <= t {
                upstream.removeFirst()
                switch first.command {
                case let .grant(flow, n):
                    byFlow[flow]?.credit += n
                case .drain:
                    for model in models {
                        model.credit = 0
                    }
                    downstream.append(Frame(at: arrival(0, sentAt: t), bytes: 0, sentAt: t, limited: false,
                                            reply: .drain))
                case .ping:
                    downstream.append(Frame(at: arrival(0, sentAt: t), bytes: 0, sentAt: t, limited: false,
                                            reply: .ping))
                }
            }
            // The framer: round-robin, at most 4 KB from one flow at a time.
            for model in models {
                model.produce(at: t)
            }
            // The echo allowance, for the leader's small writes when it has no credit.
            if let leader = byFlow[.leader] {
                leader.bucket = min(256, leader.bucket + 2560 * dt)
                if leader.credit == 0, leader.pending > 0, leader.pending <= 256,
                   Double(leader.pending) <= leader.bucket {
                    let n = leader.pending
                    leader.bucket -= Double(n)
                    leader.pending = 0
                    let at = arrival(n, sentAt: t)
                    leader.lastArrivalOnPath = at
                    downstream.append(Frame(at: at, flow: .leader, bytes: n, sentAt: t, limited: false,
                                            exempt: true))
                }
            }
            var progress = true
            while progress {
                progress = false
                for i in 0..<models.count {
                    let model = models[(rotation + i) % models.count]
                    guard model.credit > 0, model.pending > 0 else {
                        continue
                    }
                    let n = min(model.credit, model.pending, 4096)
                    model.credit -= n
                    model.pending -= n
                    let at = arrival(n, sentAt: t)
                    model.lastArrivalOnPath = at
                    model.bytesOnPath += n
                    downstream.append(Frame(at: at, flow: model.spec.flow, bytes: n, sentAt: t,
                                            limited: model.credit == 0 && model.pending > 0))
                    progress = true
                }
                rotation += 1
            }
            // iTerm2's parser, which stops reading while the leader's queue is full.
            while let first = downstream.first, first.at <= t,
                  (byFlow[.leader]?.queue ?? 0) < leaderQueueLimit {
                downstream.removeFirst()
                if let flow = first.flow, let model = byFlow[flow] {
                    if !first.exempt {
                        model.bytesOnPath -= first.bytes
                    }
                    model.queue += Double(first.bytes)
                    c.frameDidArrive(now: t, flow: flow,
                                     sendMilliseconds: Int64(first.sentAt * 1000) + 777_000,
                                     bytes: first.bytes, limited: first.limited, exempt: first.exempt)
                } else if first.reply == .drain {
                    c.drainDidReply(now: t)
                } else if first.reply == .ping {
                    c.pingDidReply(roundTrip: t - pingSentAt.removeFirst(), now: t)
                }
            }
            // The sessions.
            for model in models {
                let n = Int(model.consumable(at: t, dt: dt))
                if n > 0 {
                    model.queue -= Double(n)
                    model.consumedTotal += n
                    if t > warmup {
                        model.consumedAfterWarmup += Double(n)
                    }
                    c.flowDidConsume(model.spec.flow, bytes: n, now: t)
                }
                while let first = model.typed.first, first.offset <= model.consumedTotal {
                    model.typed.removeFirst()
                    if t > warmup {
                        model.result.worstEcho = max(model.result.worstEcho, t - first.at)
                    }
                }
                if t > warmup {
                    model.result.worstBacklog = max(model.result.worstBacklog, model.backlog(at: t))
                    model.result.worstQueue = max(model.result.worstQueue, model.queue)
                }
                model.result.largestWindow = max(model.result.largestWindow,
                                                 c.window(of: model.spec.flow) ?? 0)
            }
            if t >= nextTick {
                c.tick(now: t)
                nextTick = t + c.tickInterval(now: t)
            }
            for command in pending {
                if command == .ping {
                    pingSentAt.append(t)
                }
                upstream.append((t + oneWay, command))
            }
            pending.removeAll()
        }
        var results = [Flow: FlowResult]()
        for model in models {
            var result = model.result
            result.utilization = model.consumedAfterWarmup / (rate * (seconds - warmup))
            results[model.spec.flow] = result
        }
        return Result(controller: c, flows: results)
    }

    /// rttmin + 2 x target + the floor's worth: about what Ctrl-C should wait at most. The floor
    /// is sized at the path's rate; it drains at the session's own rate when that is slower.
    private func bound(rate: Double, oneWay: TimeInterval, consumerRate: Double? = nil) -> TimeInterval {
        let rtt = 2 * oneWay
        let target = max(0.025, rtt)
        let floor = min(max(rate * 0.025, 2 * Self.KB), 16 * Self.KB)
        return rtt + 2 * target + floor / (consumerRate ?? rate)
    }

    private func flood(_ flow: Flow, consumer: Consumer = .immediate) -> FlowSpec {
        FlowSpec(flow: flow, source: .flood, consumer: consumer)
    }

    // MARK: - One flow, as with a framer of version 1

    func testAFloodIsBoundedAndDrained() {
        // 20 KB/s on a 100 ms round trip: plain ssh would queue minutes of output.
        let rate = 20 * Self.KB
        let result = simulate(rate: rate, oneWay: 0.05, seconds: 60, flows: [flood(.leader)])
        let c = result.controller
        XCTAssertGreaterThanOrEqual(c.statistics.drains, 2, "drains refresh the baseline")
        XCTAssertEqual(c.statistics.abandonedDrains, 0)
        // In flight after Ctrl-C: about rttmin + 2 x target.
        XCTAssertLessThan(result.flows[.leader]!.worstBacklog, 0.6)
        // Drains cost about a tenth of a sustained flood.
        XCTAssertGreaterThan(result.utilization, 0.8)
        XCTAssertEqual(c.deliveryRate(now: 60)!, rate, accuracy: 2 * Self.KB)
    }

    func testAFastPathStaysBusyAndUnderTheCap() {
        let result = simulate(rate: 10 * Self.KB * Self.KB, oneWay: 0.02, seconds: 30, flows: [flood(.leader)])
        XCTAssertGreaterThan(result.utilization, 0.5)
        XCTAssertLessThan(result.flows[.leader]!.worstBacklog, 0.3)
        XCTAssertLessThanOrEqual(result.controller.window, result.controller.parameters.absoluteCap)
    }

    func testALongPathStaysWithinItsBound() {
        // 20 KB/s on an 800 ms round trip: rttmin + 2 x target is 2.4 s.
        let result = simulate(rate: 20 * Self.KB, oneWay: 0.4, seconds: 90, flows: [flood(.leader)])
        XCTAssertLessThan(result.flows[.leader]!.worstBacklog, 3.2)
        XCTAssertGreaterThan(result.utilization, 0.7)
    }

    // Version 1 measured at execution because a busy executor hid a backlog from a controller
    // that measured at the parser: Ctrl-C took 12.6 times its bound. Measured on arrival, the
    // session's own consumption delay caps its share instead.
    func testASlowLeaderSessionKeepsCtrlCBounded() {
        let rate = 1 * Self.KB * Self.KB
        let consumerRate = 100 * Self.KB
        let result = simulate(rate: rate, oneWay: 0.02, seconds: 40,
                              flows: [flood(.leader, consumer: .rate(consumerRate))])
        let leader = result.flows[.leader]!
        XCTAssertLessThan(leader.worstBacklog, bound(rate: rate, oneWay: 0.02, consumerRate: consumerRate) + 0.1)
        XCTAssertGreaterThan(leader.utilization, 0.08, "the session's own rate is the limit")
    }

    // A small frame crosses the path faster than a large one. Readings take that out, or echo
    // would set a baseline no 4 KB frame reaches, and a flood beside it would look queued.
    func testTypingBesideAFloodDoesNotShrinkTheWindow() {
        let alone = simulate(rate: 20 * Self.KB, oneWay: 0.05, seconds: 60, flows: [flood(.pane(7))])
        let typing = simulate(rate: 20 * Self.KB, oneWay: 0.05, seconds: 60, flows: [
            FlowSpec(flow: .leader, source: .typing(every: 0.2, bytes: 3), consumer: .immediate),
            flood(.pane(7)),
        ])
        XCTAssertGreaterThan(typing.flows[.pane(7)]!.utilization, alone.utilization - 0.05)
    }

    // MARK: - Several flows

    // Two floods share the path about equally, and each waits no longer than one alone.
    func testTwoFloodsShareThePath() {
        let result = simulate(rate: 20 * Self.KB, oneWay: 0.05, seconds: 60,
                              flows: [flood(.leader), flood(.pane(7))])
        XCTAssertGreaterThan(result.utilization, 0.8)
        for flow in [Flow.leader, .pane(7)] {
            let r = result.flows[flow]!
            XCTAssertGreaterThan(r.utilization, 0.35, "\(flow)")
            XCTAssertLessThan(r.utilization, 0.6, "\(flow)")
            XCTAssertLessThan(r.worstBacklog, 0.6, "\(flow)")
        }
    }

    func testFourFloodsShareAFastPath() {
        let result = simulate(rate: 1 * Self.KB * Self.KB, oneWay: 0.02, seconds: 40,
                              flows: [flood(.leader), flood(.pane(7)), flood(.pane(8)), flood(.it2)])
        XCTAssertGreaterThan(result.utilization, 0.8)
        for (flow, r) in result.flows {
            XCTAssertGreaterThan(r.utilization, 0.18, "\(flow)")
            XCTAssertLessThan(r.utilization, 0.3, "\(flow)")
            XCTAssertLessThan(r.worstBacklog, 0.3, "\(flow)")
        }
    }

    func testTwoFloodsOnALongPath() {
        let result = simulate(rate: 20 * Self.KB, oneWay: 0.4, seconds: 90,
                              flows: [flood(.leader), flood(.pane(7))])
        XCTAssertGreaterThan(result.utilization, 0.7)
        for flow in [Flow.leader, .pane(7)] {
            XCTAssertLessThan(result.flows[flow]!.worstBacklog, 3.6, "\(flow)")
        }
    }

    // A peer flooding the connection leaves typing in the leader responsive (its echo allowance
    // carries it through drains), and gets nearly all of the path.
    func testAFloodingPaneLeavesTheLeaderResponsive() {
        let rate = 20 * Self.KB
        let result = simulate(rate: rate, oneWay: 0.05, seconds: 60, flows: [
            FlowSpec(flow: .leader, source: .typing(every: 0.2, bytes: 3), consumer: .immediate),
            flood(.pane(7)),
        ])
        XCTAssertLessThan(result.flows[.leader]!.worstEcho, 0.6)
        XCTAssertGreaterThan(result.flows[.pane(7)]!.utilization, 0.8)
    }

    // A peer has no echo allowance, so typing in it pauses for a drain: about a round trip
    // plus a target of queue, every nine drain lengths.
    func testTypingInAPeerBesideAFlood() {
        let result = simulate(rate: 20 * Self.KB, oneWay: 0.05, seconds: 60, flows: [
            flood(.leader),
            FlowSpec(flow: .pane(7), source: .typing(every: 0.2, bytes: 3), consumer: .immediate),
        ])
        XCTAssertLessThan(result.flows[.pane(7)]!.worstEcho, 1.0)
        XCTAssertGreaterThan(result.flows[.leader]!.utilization, 0.8)
    }

    // A peer whose session stops reading holds back only itself: its backlog stays within its
    // window, and the leader gets the path.
    func testAStalledPaneHoldsBackOnlyItself() {
        let result = simulate(rate: 1 * Self.KB * Self.KB, oneWay: 0.02, seconds: 40,
                              flows: [flood(.leader), flood(.pane(7), consumer: .stallsAt(5))])
        let pane = result.flows[.pane(7)]!
        XCTAssertLessThanOrEqual(pane.worstQueue, pane.largestWindow + 4096)
        XCTAssertLessThan(pane.worstQueue, 256 * Self.KB)
        XCTAssertGreaterThan(result.flows[.leader]!.utilization, 0.7)
    }

    // A slow leader session costs a flooding peer only the leader's share.
    func testASlowLeaderSessionLeavesThePathToAPeer() {
        let rate = 1 * Self.KB * Self.KB
        let consumerRate = 100 * Self.KB
        let result = simulate(rate: rate, oneWay: 0.02, seconds: 40,
                              flows: [flood(.leader, consumer: .rate(consumerRate)), flood(.pane(7))])
        XCTAssertLessThan(result.flows[.leader]!.worstBacklog,
                          bound(rate: rate, oneWay: 0.02, consumerRate: consumerRate) + 0.1)
        XCTAssertGreaterThan(result.flows[.pane(7)]!.utilization, 0.6)
    }

    // A peer that starts flooding later takes its share from the leader's.
    func testAPeerThatStartsLaterGetsItsShare() {
        let result = simulate(rate: 20 * Self.KB, oneWay: 0.05, seconds: 60, warmup: 30, flows: [
            flood(.leader),
            FlowSpec(flow: .pane(7), source: .floodFrom(20), consumer: .immediate),
        ])
        XCTAssertGreaterThan(result.flows[.pane(7)]!.utilization, 0.35)
        XCTAssertGreaterThan(result.flows[.leader]!.utilization, 0.35)
    }

    // Idle peers cost a flood nothing: their credit sits unused, off the path.
    func testIdlePeersCostAFloodNothing() {
        let alone = simulate(rate: 20 * Self.KB, oneWay: 0.05, seconds: 60, flows: [flood(.leader)])
        let result = simulate(rate: 20 * Self.KB, oneWay: 0.05, seconds: 60, flows: [
            flood(.leader),
            FlowSpec(flow: .pane(7), source: .idle, consumer: .immediate),
            FlowSpec(flow: .pane(8), source: .idle, consumer: .immediate),
        ])
        XCTAssertGreaterThan(result.flows[.leader]!.utilization, alone.utilization - 0.03)
    }
}

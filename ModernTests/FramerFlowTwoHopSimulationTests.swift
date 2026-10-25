//
//  FramerFlowTwoHopSimulationTests.swift
//  iTerm2 ModernTests
//
//  Flow control over nested SSH Integration, simulated: `it2ssh host1`, then `it2ssh host2`
//  inside it. host2's framer sends its frames over path A to host1, where they wait in the pty
//  of the inner ssh until host1's framer reads them. host1's framer reads that pty only with
//  credit, as the leader's output, and sends it with anything of its own (a flooding pane) over
//  path B to iTerm2. Each path is in order, with a fixed rate and one-way delay, and delivers a
//  frame in pieces of 512 bytes, so host1 can read the start of one before its end arrives.
//
//  Two controllers run: the outer one for host1's framer and the inner one for host2's. The
//  inner one's commands go to host1 and on to host2 as keystrokes; host2's replies come back in
//  its output, through host1's pty like the rest of it. An inner frame reaches iTerm2 inside the
//  outer frame that carried its last byte, and counts as consumed once the session has executed
//  that outer frame. Its delay is measured to the outer frame that carried its first line.
//
//  What Ctrl-C at host2 waits out is everything host2 has already sent: on path A, in host1's
//  pty, on path B, and in the session. So the worst wait is the longest any inner frame took
//  from host2 to being consumed.
//

import XCTest
@testable import iTerm2SharedARC

final class FramerFlowTwoHopSimulationTests: XCTestCase {
    typealias Controller = FramerFlowController
    private static let KB = 1024.0

    struct Path {
        var rate: Double
        var oneWay: TimeInterval
        /// For a link whose rate changes, as with Network Link Conditioner: the rate in force at
        /// a time.
        var rateAt: ((TimeInterval) -> Double)?
        /// Each piece takes up to this much longer to cross, at random, though pieces stay in
        /// order.
        var jitter: TimeInterval
        /// Times when nothing crosses, as while TCP waits out a retransmission timeout.
        var stalls: [Range<TimeInterval>] = []
        private var nextDeparture: TimeInterval = 0
        private var lastArrival: TimeInterval = 0
        private var noise: UInt64 = 0x9E3779B97F4A7C15

        init(rate: Double, oneWay: TimeInterval, jitter: TimeInterval = 0,
             rateAt: ((TimeInterval) -> Double)? = nil) {
            self.rate = rate
            self.oneWay = oneWay
            self.jitter = jitter
            self.rateAt = rateAt
        }

        mutating func arrival(_ bytes: Int, sentAt t: TimeInterval) -> TimeInterval {
            var start = max(nextDeparture, t)
            if let stall = stalls.first(where: { $0.contains(start) }) {
                start = stall.upperBound
            }
            nextDeparture = start + Double(bytes) / (rateAt?(start) ?? rate)
            noise = noise &* 6364136223846793005 &+ 1442695040888963407
            let extra = jitter * Double(noise >> 11) / Double(1 << 53)
            lastArrival = max(lastArrival, nextDeparture + oneWay + extra)
            return lastArrival
        }
    }

    struct Result {
        var outer: Controller
        var inner: Controller
        /// host2's bytes consumed a second, after the warm-up.
        var innerRate: Double
        /// host1's pane's bytes consumed a second, after the warm-up.
        var paneRate: Double
        /// The longest an inner frame took from host2 to being consumed, after the warm-up.
        var worstInnerWait: TimeInterval
        /// The longest a frame of host1's pane took from host1 to being consumed.
        var worstPaneWait: TimeInterval
        /// The most of host2's output that waited in host1's pty, where Ctrl-C at host2 can't
        /// discard it.
        var worstHost1Buffer: Int
        /// The inner controller's window, sampled every 100 ms after the warm-up.
        var innerWindows: [Double]
    }

    private struct InnerFrame {
        var bytes: Int
        var sentAt: TimeInterval
        var limited: Bool
        /// When host1 sent the outer frames carrying its first and last bytes.
        var firstCarrier: TimeInterval?
        var lastCarrier: TimeInterval?
    }

    enum Host2Source {
        case flood
        /// `bytes` every `every` seconds, like echo, until `floodFrom`, then a flood.
        case typingThenFlood(every: TimeInterval, bytes: Int, floodFrom: TimeInterval)
    }

    /// What waits in host1's pty, in order.
    private enum Host1Item {
        /// Bytes of an inner frame, by index, as one piece arrived; the frame is complete once
        /// its last piece is read.
        case data(Int, remaining: Int, first: Bool, last: Bool)
        case reply(Controller.Command)
    }

    private enum OuterFlow {
        case leader
        case pane
    }

    private struct OuterFrame {
        var at: TimeInterval
        var flow: OuterFlow?
        var bytes: Int
        var sentAt: TimeInterval
        var limited: Bool
        /// Inner frames whose last byte this carries.
        var completes = [Int]()
        /// Replies from host2 this carries.
        var innerReplies = [Controller.Command]()
        /// host1's own reply, for the outer controller.
        var reply: Controller.Command?
    }

    private enum Upstream {
        case outer(Controller.Command)
        case relayed(Controller.Command)
    }

    /// `perHop` measures each inner frame's delay against the outer frame that carried it, on
    /// host1's clock, and `capsInner` limits the inner window to what the outer leader's
    /// carries, as iTerm2 does. Without them the inner controller works as it did before
    /// nested framers measured their own hop: against arrival here.
    private func simulate(pathA a: Path,
                          pathB b: Path,
                          seconds: TimeInterval = 60,
                          warmup: TimeInterval = 10,
                          host2: Host2Source? = .flood,
                          host1PaneFloodsFrom: TimeInterval? = nil,
                          perHop: Bool = true,
                          capsInner: Bool = true,
                          carrierOfFirstLine: Bool = true,
                          eachStep: ((_ outer: Controller, _ inner: Controller, _ t: TimeInterval,
                                      _ innerConsumed: Double) -> Void)? = nil) -> Result {
        var pathA = a
        var pathB = b
        // The hosts' clocks are unrelated to each other and to this Mac's.
        let host1Offset: TimeInterval = 333
        let host2Offset: TimeInterval = 777
        func ms(_ t: TimeInterval, _ offset: TimeInterval) -> Int64 {
            Int64(((t + offset) * 1000).rounded(.down))
        }

        var outerCommands = [Controller.Command]()
        var innerCommands = [Controller.Command]()
        let outer = Controller(now: 0, recovering: false) { outerCommands.append($0) }
        let inner = Controller(now: 0, recovering: false) { innerCommands.append($0) }
        // The replies to flow on are each one's first round trip.
        outer.roundTripDidComplete(sentAt: 0, now: 2 * b.oneWay)
        inner.roundTripDidComplete(sentAt: 0, now: 2 * (a.oneWay + b.oneWay))
        if host1PaneFloodsFrom != nil {
            outer.flowDidStart(.pane(1), now: 0)
        }

        var host2Credit = outer.parameters.initialCredit
        var host1LeaderCredit = outer.parameters.initialCredit
        var host1PaneCredit = 0
        var innerFrames = [InnerFrame]()
        var host2Pending = 0
        var nextTyping: TimeInterval = 0
        var onPathA = [(at: TimeInterval, item: Host1Item)]()
        var host1Buffer = [Host1Item]()
        var host1BufferBytes = 0
        var onPathB = [OuterFrame]()
        var toHost1 = [(at: TimeInterval, command: Upstream)]()
        var toHost2 = [(at: TimeInterval, command: Controller.Command)]()
        var outerPingSentAt = [TimeInterval]()
        var innerPingSentAt = [TimeInterval]()
        /// The leader's frames waiting for the session, with the bytes not yet consumed.
        var session = [(frame: OuterFrame, remaining: Int)]()

        var innerConsumed = 0.0
        var paneConsumed = 0.0
        var worstInnerWait: TimeInterval = 0
        var worstPaneWait: TimeInterval = 0
        var worstHost1Buffer = 0
        var innerWindows = [Double]()
        var nextSample = warmup

        let dt = 0.001
        var t = 0.0
        var nextOuterTick = 0.0
        var nextInnerTick = 0.0
        var rotation = 0
        while t < seconds {
            t += dt

            // Commands reach host1; the inner controller's go on to host2.
            while let first = toHost1.first, first.at <= t {
                toHost1.removeFirst()
                switch first.command {
                case .relayed(let command):
                    toHost2.append((t + a.oneWay, command))
                case .outer(.grant(let flow, let n)):
                    if flow == .leader {
                        host1LeaderCredit += n
                    } else {
                        host1PaneCredit += n
                    }
                case .outer(let command):
                    if command == .drain {
                        host1LeaderCredit = 0
                        host1PaneCredit = 0
                    }
                    onPathB.append(OuterFrame(at: pathB.arrival(0, sentAt: t), bytes: 0, sentAt: t,
                                              limited: false, reply: command))
                }
            }
            while let first = toHost2.first, first.at <= t {
                toHost2.removeFirst()
                switch first.command {
                case .grant(_, let n):
                    host2Credit += n
                case let command:
                    if command == .drain {
                        host2Credit = 0
                    }
                    onPathA.append((pathA.arrival(0, sentAt: t), .reply(command)))
                }
            }

            // host2's framer.
            switch host2 {
            case .flood:
                host2Pending = Int.max / 2
            case let .typingThenFlood(every, bytes, floodFrom):
                if t >= floodFrom {
                    host2Pending = Int.max / 2
                } else if t >= nextTyping {
                    nextTyping = t + every
                    host2Pending += bytes
                }
            case nil:
                break
            }
            while host2Credit > 0, host2Pending > 0 {
                let n = min(host2Credit, host2Pending, 4096)
                host2Credit -= n
                host2Pending -= n
                innerFrames.append(InnerFrame(bytes: n, sentAt: t, limited: host2Credit == 0 && host2Pending > 0))
                var left = n
                while left > 0 {
                    let piece = min(left, 512)
                    onPathA.append((pathA.arrival(piece, sentAt: t),
                                    .data(innerFrames.count - 1, remaining: piece, first: left == n, last: piece == left)))
                    left -= piece
                }
            }
            while let first = onPathA.first, first.at <= t {
                onPathA.removeFirst()
                host1Buffer.append(first.item)
                if case .data(_, let n, _, _) = first.item {
                    host1BufferBytes += n
                }
            }
            if t > warmup {
                worstHost1Buffer = max(worstHost1Buffer, host1BufferBytes)
            }

            // host1's framer: round-robin between the leader's pty and its pane, at most 4 KB at
            // a time. host2's replies are small and go out at once, in order, as echo would.
            var progress = true
            while progress {
                progress = false
                for i in 0..<2 {
                    let leaderTurn = (rotation + i) % 2 == 0
                    if leaderTurn {
                        var frame = OuterFrame(at: 0, flow: .leader, bytes: 0, sentAt: t, limited: false)
                        var budget = min(host1LeaderCredit, 4096)
                        while let head = host1Buffer.first {
                            switch head {
                            case .reply(let command):
                                frame.innerReplies.append(command)
                                host1Buffer.removeFirst()
                                continue
                            case let .data(index, remaining, first, last):
                                guard budget > 0 else {
                                    break
                                }
                                let n = min(budget, remaining)
                                budget -= n
                                frame.bytes += n
                                host1BufferBytes -= n
                                if first {
                                    innerFrames[index].firstCarrier = t
                                }
                                if n == remaining {
                                    if last {
                                        innerFrames[index].lastCarrier = t
                                        frame.completes.append(index)
                                    }
                                    host1Buffer.removeFirst()
                                } else {
                                    host1Buffer[0] = .data(index, remaining: remaining - n, first: false, last: last)
                                }
                                continue
                            }
                            break
                        }
                        guard frame.bytes > 0 || !frame.innerReplies.isEmpty else {
                            continue
                        }
                        host1LeaderCredit -= frame.bytes
                        frame.limited = host1LeaderCredit == 0 && host1BufferBytes > 0
                        frame.at = pathB.arrival(frame.bytes, sentAt: t)
                        onPathB.append(frame)
                        progress = true
                    } else if let start = host1PaneFloodsFrom, t >= start, host1PaneCredit > 0 {
                        let n = min(host1PaneCredit, 4096)
                        host1PaneCredit -= n
                        onPathB.append(OuterFrame(at: pathB.arrival(n, sentAt: t), flow: .pane, bytes: n,
                                                  sentAt: t, limited: host1PaneCredit == 0))
                        progress = true
                    }
                }
                rotation += 1
            }

            // iTerm2.
            while let first = onPathB.first, first.at <= t {
                onPathB.removeFirst()
                let carrier = ms(first.sentAt, host1Offset)
                switch first.flow {
                case .leader:
                    if first.bytes > 0 {
                        outer.frameDidArrive(now: t, flow: .leader, sendMilliseconds: carrier,
                                             bytes: first.bytes, limited: first.limited, exempt: false)
                    }
                    for index in first.completes {
                        let f = innerFrames[index]
                        let carriedAt = carrierOfFirstLine ? f.firstCarrier! : f.lastCarrier!
                        inner.frameDidArrive(now: t, flow: .leader,
                                             sendMilliseconds: ms(f.sentAt, host2Offset),
                                             bytes: f.bytes, limited: f.limited, exempt: false,
                                             carrierMilliseconds: perHop ? ms(carriedAt, host1Offset) : nil)
                    }
                    for reply in first.innerReplies {
                        if reply == .drain {
                            inner.drainDidReply(now: t)
                        } else if reply == .ping {
                            inner.pingDidReply(roundTrip: t - innerPingSentAt.removeFirst(), now: t)
                        }
                    }
                    session.append((first, first.bytes))
                case .pane:
                    outer.frameDidArrive(now: t, flow: .pane(1), sendMilliseconds: carrier,
                                         bytes: first.bytes, limited: first.limited, exempt: false)
                    outer.flowDidConsume(.pane(1), bytes: first.bytes, now: t)
                    if t > warmup {
                        paneConsumed += Double(first.bytes)
                        worstPaneWait = max(worstPaneWait, t - first.sentAt)
                    }
                case nil:
                    if first.reply == .drain {
                        outer.drainDidReply(now: t)
                    } else if first.reply == .ping {
                        outer.pingDidReply(roundTrip: t - outerPingSentAt.removeFirst(), now: t)
                    }
                }
            }
            // The session executes as fast as output arrives. An outer frame counts once its
            // inner frames have run, and they count then too.
            while let first = session.first {
                session.removeFirst()
                if first.remaining > 0 {
                    outer.flowDidConsume(.leader, bytes: first.remaining, now: t)
                }
                for index in first.frame.completes {
                    let f = innerFrames[index]
                    inner.flowDidConsume(.leader, bytes: f.bytes, now: t)
                    if t > warmup {
                        innerConsumed += Double(f.bytes)
                        worstInnerWait = max(worstInnerWait, t - f.sentAt)
                    }
                }
            }

            if t >= nextOuterTick {
                outer.tick(now: t)
                nextOuterTick = t + outer.tickInterval(now: t)
            }
            if t >= nextInnerTick {
                if capsInner {
                    inner.carrierWindow = outer.window(of: .leader)
                }
                inner.tick(now: t)
                nextInnerTick = t + inner.tickInterval(now: t)
            }
            for command in outerCommands {
                if command == .ping {
                    outerPingSentAt.append(t)
                }
                toHost1.append((t + b.oneWay, .outer(command)))
            }
            outerCommands.removeAll()
            for command in innerCommands {
                if command == .ping {
                    innerPingSentAt.append(t)
                }
                toHost1.append((t + b.oneWay, .relayed(command)))
            }
            innerCommands.removeAll()
            eachStep?(outer, inner, t, innerConsumed)
            if t >= nextSample {
                innerWindows.append(inner.window)
                nextSample += 0.1
            }
        }
        let measured = seconds - warmup
        return Result(outer: outer, inner: inner,
                      innerRate: innerConsumed / measured,
                      paneRate: paneConsumed / measured,
                      worstInnerWait: worstInnerWait,
                      worstPaneWait: worstPaneWait,
                      worstHost1Buffer: worstHost1Buffer,
                      innerWindows: innerWindows)
    }

    private func summary(_ r: Result) -> String {
        let w = r.innerWindows.sorted()
        return "inner \(Int(r.innerRate)) B/s, wait \(r.worstInnerWait) s, host1 pty \(r.worstHost1Buffer) B, "
            + "pane \(Int(r.paneRate)) B/s, pane wait \(r.worstPaneWait) s, inner window median "
            + "\(Int(w[w.count / 2])) 95th \(Int(w[w.count * 95 / 100]))"
    }

    private func timeAtFloor(_ r: Result) -> Double {
        let floor = r.inner.parameters.floorMinimum
        return Double(r.innerWindows.filter { $0 <= floor + 64 }.count) / Double(r.innerWindows.count)
    }

    private let fast = Path(rate: 1024 * FramerFlowTwoHopSimulationTests.KB, oneWay: 0.01)
    private let slow = Path(rate: 20 * FramerFlowTwoHopSimulationTests.KB, oneWay: 0.05)

    // For reference, one hop over `slow` (host1's pane alone) waits at most 0.46 s at 16 KB/s,
    // as FramerFlowSimulationTests.testAFloodIsBoundedAndDrained bounds by 0.6 s.

    // MARK: - The inner hop is the slow one

    // host2 is far away and host1 near: the inner controller paces host2 as one hop would.
    func testASlowInnerHopBoundsCtrlCAtTheInnerHost() {
        let r = simulate(pathA: slow, pathB: fast)
        XCTAssertGreaterThan(r.innerRate, 0.7 * slow.rate, summary(r))
        XCTAssertLessThan(r.worstInnerWait, 0.6, summary(r))
    }

    // Echo from typing on host2 sets the baseline with small frames; then a program floods.
    // Measured to the frame that carried an inner frame's last byte, a 4 KB frame's reading
    // would hold the 0.2 s it takes to cross the inner hop, every large frame would look
    // queued, and the flood would be held to a fraction of the hop.
    func testAFloodAfterTypingOverASlowInnerHopUsesTheHop() {
        let source = Host2Source.typingThenFlood(every: 0.2, bytes: 20, floodFrom: 15)
        let r = simulate(pathA: slow, pathB: fast, warmup: 20, host2: source)
        let lastByte = simulate(pathA: slow, pathB: fast, warmup: 20, host2: source, carrierOfFirstLine: false)
        XCTAssertGreaterThan(r.innerRate, 0.7 * slow.rate, summary(r))
        XCTAssertLessThan(r.worstInnerWait, 0.6, summary(r))
        XCTAssertGreaterThan(r.innerRate, lastByte.innerRate, summary(lastByte))
    }

    // MARK: - The outer hop is the slow one

    // host1 is far away and host2 near it, as with a bastion. host2's output waits in host1's
    // pty for the outer credit, where Ctrl-C at host2 can't discard it. Measured end to end,
    // that wait hid behind the outer hop's own, and Ctrl-C waited 0.82 s; now 0.61 s.
    func testASlowOuterHopBoundsCtrlCAtTheInnerHost() {
        let r = simulate(pathA: fast, pathB: slow)
        let before = simulate(pathA: fast, pathB: slow, perHop: false, capsInner: false)
        XCTAssertGreaterThan(r.innerRate, 0.7 * slow.rate, summary(r))
        XCTAssertLessThan(r.worstInnerWait, 0.8, summary(r))
        XCTAssertLessThan(r.worstHost1Buffer, before.worstHost1Buffer)
        // One run's worst wait swings with small changes to the path, in both designs, so they
        // are compared on the mean over nearby paths.
        let nearby = { (perHop: Bool) -> Double in
            let paths = [0.048, 0.05, 0.052].flatMap { oneWay in
                [19.0, 21.0].map { Path(rate: $0 * Self.KB, oneWay: oneWay) }
            }
            return paths.map {
                self.simulate(pathA: self.fast, pathB: $0, perHop: perHop, capsInner: perHop).worstInnerWait
            }.reduce(0, +) / Double(paths.count)
        }
        let (perHopMean, endToEndMean) = (nearby(true), nearby(false))
        XCTAssertLessThan(perHopMean, 0.85 * endToEndMean, "\(perHopMean) s against \(endToEndMean) s")
    }

    // Both controllers act on the same backlog. Paced by their own round trips they drove each
    // other into swings: the inner window overshot, then sat at the floor 14% of the time.
    func testTheInnerWindowIsSteadyBehindASlowOuterHop() {
        let r = simulate(pathA: fast, pathB: slow)
        let w = r.innerWindows.sorted()
        XCTAssertLessThan(timeAtFloor(r), 0.05, summary(r))
        XCTAssertLessThan(w[w.count * 95 / 100], 2 * w[w.count / 2], summary(r))
    }

    // MARK: - Floods on both hosts

    // A pane on host1 floods beside host2's flood. They share the outer hop, and host1's pane
    // waits no more than it would alone. host2's flood waits longest when the outer controller
    // drains: host1 stops reading for a round trip while host2 spends credit it already has.
    // End to end its window swung to the floor a fifth of the time and Ctrl-C waited 0.96 s;
    // now 0.85 s.
    func testFloodsOnBothHostsShareTheOuterHop() {
        let b = Path(rate: 40 * Self.KB, oneWay: 0.05)
        let r = simulate(pathA: fast, pathB: b, host1PaneFloodsFrom: 0)
        let before = simulate(pathA: fast, pathB: b, host1PaneFloodsFrom: 0, perHop: false, capsInner: false)
        XCTAssertGreaterThan(r.innerRate + r.paneRate, 0.7 * b.rate, summary(r))
        XCTAssertGreaterThan(r.innerRate, 0.25 * b.rate, summary(r))
        XCTAssertGreaterThan(r.paneRate, 0.25 * b.rate, summary(r))
        XCTAssertLessThan(r.worstPaneWait, 0.6, summary(r))
        XCTAssertLessThan(r.worstInnerWait, 1.0, summary(r))
        // One run's worst wait swings by a fifth with a 2% change to the path, in both designs,
        // so they are compared on the mean over nearby paths.
        let nearby = { (perHop: Bool) -> Double in
            let paths = [0.048, 0.05, 0.052].flatMap { oneWay in
                [39.0, 41.0].map { Path(rate: $0 * Self.KB, oneWay: oneWay) }
            }
            return paths.map {
                self.simulate(pathA: self.fast, pathB: $0, host1PaneFloodsFrom: 0, perHop: perHop,
                              capsInner: perHop).worstInnerWait
            }.reduce(0, +) / Double(paths.count)
        }
        let (perHopMean, endToEndMean) = (nearby(true), nearby(false))
        XCTAssertLessThan(perHopMean, 0.95 * endToEndMean, "\(perHopMean) s against \(endToEndMean) s")
        XCTAssertLessThan(timeAtFloor(r), 0.05, summary(r))
        XCTAssertGreaterThan(timeAtFloor(before), 0.1, "the comparison still shows what changed")
    }

    // MARK: - A link that changes speed

    // host2's flood through host1, with the outer hop fast, slowed to 500 Kbit/s, and fast
    // again, as with Network Link Conditioner on the Mac: once the hop is fast, so is the flood.
    // Where the outer window happens to be when the hop speeds up decides whether it climbs
    // out, so the throttle is lifted at many moments.
    func testANestedFloodRecoversWhenTheOuterHopSpeedsUpAtAnyMoment() {
        checkRecovery(jitter: 0)
    }

    // The same with the delay of each piece on the outer hop varying, as on a real network.
    func testANestedFloodRecoversWhenAJitteryOuterHopSpeedsUp() {
        checkRecovery(jitter: 0.005)
        checkRecovery(jitter: 0.02)
    }

    private func checkRecovery(jitter: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        let fastRate = 1024 * Self.KB
        var report = [String]()
        var worst = Double.infinity
        for tenth in stride(from: 300, through: 400, by: 7) {
            let lift = Double(tenth) / 10
            let b = Path(rate: fastRate, oneWay: 0.013, jitter: jitter) { t in (20..<lift).contains(t) ? 62_500 : fastRate }
            var bySecond = [Double](repeating: 0, count: 101)
            var last = 0.0
            var windowAtLift = 0.0
            _ = simulate(pathA: Path(rate: fastRate, oneWay: 0.05), pathB: b, seconds: 100, warmup: 0) { outer, _, t, consumed in
                bySecond[Int(t)] += consumed - last
                last = consumed
                if windowAtLift == 0 && t >= lift {
                    windowAtLift = outer.window
                }
            }
            let before = bySecond[10..<20].reduce(0, +) / 10
            let after = bySecond[90..<100].reduce(0, +) / 10
            worst = min(worst, after / before)
            report.append("lift \(lift): W \(Int(windowAtLift)), after/before \(String(format: "%.2f", after / before))")
        }
        print("jitter \(jitter):\n" + report.joined(separator: "\n"))
        XCTAssertGreaterThan(worst, 0.5, "jitter \(jitter): " + report.joined(separator: "; "), file: file, line: line)
    }

    // MARK: - The link's cost per byte

    // The cost per byte the outer controller reads off its frames is the slow hop's, and holds
    // steady while the delay of each piece jitters a little.
    func testTheCostPerByteIsSteadyOnAJitteryHop() {
        for jitter in [0.0, 0.005, 0.02] {
            let b = Path(rate: 20 * Self.KB, oneWay: 0.05, jitter: jitter)
            var costs = [TimeInterval]()
            var nextSample = 10.0
            _ = simulate(pathA: fast, pathB: b, host1PaneFloodsFrom: 0) { outer, _, t, _ in
                if t >= nextSample {
                    nextSample += 0.1
                    costs.append(outer.snapshot(now: t).delayBaseline.costPerKilobyte)
                }
            }
            let truth = 1024 / b.rate
            let sorted = costs.sorted()
            let median = sorted[sorted.count / 2]
            let low = sorted[sorted.count / 20]
            let high = sorted[sorted.count * 19 / 20]
            let description = String(format: "jitter %.3f: true %.1f ms/KB, median %.1f, 5%%–95%% %.1f–%.1f",
                                     jitter, truth * 1000, median * 1000, low * 1000, high * 1000)
            let close = Double(costs.filter { abs($0 - truth) <= 0.3 * truth }.count) / Double(costs.count)
            print(description + String(format: ", %.0f%% within 30%%", close * 100))
            XCTAssertEqual(median, truth, accuracy: 0.1 * truth, description)
            // For a few seconds at a time it is off by up to half: when a bucket at either end
            // of the edge has seen only a few frames, none of which crossed an empty path, its
            // least delay is too high. The lower edge passes under such a point in the middle
            // but not at an end. Requiring more frames there would drop rare sizes, and with
            // them the correction, whenever half the window ages out, which costs more. What
            // the wandering costs is checked below, by the outcomes.
            if jitter <= 0.005 {
                XCTAssertGreaterThan(close, 0.85, description)
            }
        }
    }

    // Ctrl-C at the inner host stays bounded and the flood keeps the hop busy when the delay of
    // each piece on the slow outer hop jitters, alone and beside a pane flooding host1. Each is
    // the mean over nearby paths, since one run's worst wait swings with small changes. (The
    // correction from the delivery rate did as well here; this guards the size baseline.)
    func testAJitteryOuterHopStillBoundsCtrlC() {
        for jitter in [0.005, 0.02] {
            for (rate, pane, bound) in [(20.0, false, 0.8), (40.0, true, 1.0)] {
                var waits = [Double]()
                var use = [Double]()
                for oneWay in [0.048, 0.05, 0.052] {
                    let r = simulate(pathA: fast, pathB: Path(rate: rate * Self.KB, oneWay: oneWay, jitter: jitter),
                                     host1PaneFloodsFrom: pane ? 0 : nil)
                    waits.append(r.worstInnerWait)
                    use.append((r.innerRate + r.paneRate) / (rate * Self.KB))
                }
                let description = "jitter \(jitter), \(Int(rate)) KB/s\(pane ? " shared" : ""): waits \(waits), use \(use)"
                XCTAssertLessThan(waits.reduce(0, +) / 3, bound, description)
                XCTAssertGreaterThan(use.reduce(0, +) / 3, 0.7, description)
            }
        }
    }

    // MARK: - Stalls

    // The outer hop stalls now and then for a couple of seconds, as when TCP waits out a
    // retransmission timeout. Both controllers may take it for a paused host and reset, the
    // inner one's drain travelling through the outer hop, but once the hop moves again host2's
    // flood is back within a few round trips.
    func testANestedFloodResumesPromptlyAfterAnOuterStall() {
        var b = Path(rate: 62_500, oneWay: 0.015)
        b.stalls = [20..<22.5, 30..<32.5, 40..<42.5]
        var bySecond = [Double](repeating: 0, count: 61)
        var last = 0.0
        var events = [String]()
        _ = simulate(pathA: Path(rate: 1024 * Self.KB, oneWay: 0.05), pathB: b, seconds: 60, warmup: 0) { outer, inner, t, consumed in
            bySecond[Int(t)] += consumed - last
            last = consumed
            if t >= 59.999 {
                events = outer.events.map { String(format: "outer %.2f ", $0.time) + $0.description }
                    + inner.events.map { String(format: "inner %.2f ", $0.time) + $0.description }
            }
        }
        let steady = bySecond[12..<20].reduce(0, +) / 8
        let description = "steady \(Int(steady)) B/s, by second \(bySecond.map(Int.init))\n" + events.joined(separator: "\n")
        print("nested stalls: " + description)
        for second in [24, 25, 26, 27, 28, 29, 34, 35, 36, 37, 38, 39, 44, 45, 50, 55] {
            XCTAssertGreaterThan(bySecond[second], 0.6 * steady, "second \(second): " + description)
        }
    }
}

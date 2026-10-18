//
//  FramerFlowController.swift
//  iTerm2SharedARC
//
//  Flow control for an ssh integration session. The framer sends a program's output only with
//  credit, which iTerm2 grants. This controller decides how much credit may be outstanding (the
//  window, W) from how long output waits between the framer and iTerm2, the way LEDBAT does:
//  each controlled frame carries the framer's clock, and the least delay seen recently is taken
//  as the empty path.
//
//  Output belongs to flows: the leader (the login shell and side commands), each workgroup
//  peer's pane, and it2. Every flow's bytes share one in-order stream, so one loop sizes W for
//  the whole connection, measuring delay when frames arrive. Each flow has credit of its own,
//  returned only when its own session consumes the bytes, so a slow consumer holds back only
//  itself. Flows that are using their credit split W equally and idle ones hold the floor. A
//  flow whose session falls behind (its bytes wait more than the target between arrival and
//  consumption) has its share capped, so its backlog, which Ctrl-C has to wait out, stays
//  bounded. A framer that predates flows sends everything as the leader's.
//
//  Pure logic: every entry point takes the time, and commands go out through `send`, so it
//  can be tested without a connection. The conductor feeds it and carries out its commands.
//

import Foundation

final class FramerFlowController {
    enum Flow: Hashable, CustomStringConvertible {
        /// The login shell and side commands.
        case leader
        /// A workgroup peer's program, by its pid on the remote host.
        case pane(Int32)
        /// Data for it2 commands.
        case it2

        var description: String {
            switch self {
            case .leader:
                return "leader"
            case .pane(let pid):
                return "pane \(pid)"
            case .it2:
                return "it2"
            }
        }
    }

    enum Command: Equatable {
        /// Add credit to a flow. Zero bytes is a heartbeat. Has no reply.
        case grant(Flow, Int)
        /// Zero the framer's credit, every flow's. Its reply goes to `drainDidReply`.
        case drain
        /// Time a round trip across an empty path. Its reply goes to `pingDidReply`.
        case ping
    }

    struct Parameters {
        var initialCredit = 8 * 1024
        var absoluteCap = 4.0 * 1024 * 1024
        /// Growth per round trip is max(stepMinimum, W / growthDivisor).
        var growthDivisor = 16.0
        var stepMinimum = 4.0 * 1024
        /// A grant goes out only when the top-up is at least the flow's window divided by this.
        var grantThresholdDivisor = 4.0
        var minimumGrantInterval: TimeInterval = 0.020
        var grantIntervalRTTDivisor = 4.0
        var minimumTarget: TimeInterval = 0.025
        /// floor = clamp(rate * floorTime, floorMinimum, floorMaximum)
        var floorTime: TimeInterval = 0.025
        var floorMinimum = 2.0 * 1024
        var floorMaximum = 16.0 * 1024
        /// The baseline window L is at least this long.
        var minimumBaselineWindow: TimeInterval = 10
        /// A drain repeats after this many times the previous drain's length.
        var drainRepeat = 9.0
        var heartbeatInterval: TimeInterval = 1
        /// How recent a window-limited frame must be to count as evidence of output.
        var heartbeatEvidence: TimeInterval = 5
        var defaultRTT: TimeInterval = 0.100
        var drainDeadlineMinimum: TimeInterval = 2
        var drainDeadlineRTTs = 4.0
        var silenceMinimum: TimeInterval = 2
        var silenceMultiplier = 4.0
        var rateBoundMultiplier = 2.0
        /// The most the framer reads from a source at once (framer.py FLOW_READ_SIZE).
        var frameSize = 4096
    }

    /// Counters for logging and tests.
    struct Statistics: Equatable {
        var grants = 0
        var heartbeats = 0
        var drains = 0
        var resetDrains = 0
        var abandonedDrains = 0
        var silences = 0
        var valves = 0
        var decreases = 0
        var roundTripSamples = 0
        /// Times a flow's share was capped because its session fell behind.
        var capDecreases = 0
    }

    private enum DrainState {
        case idle
        /// The drain was sent; waiting for its reply.
        case draining
        /// Waiting for the ping's reply.
        case pinging
    }

    private struct Unconsumed {
        var time: TimeInterval
        var bytes: Int
        var exempt: Bool
    }

    private struct FlowState {
        /// Totals in bytes. Exempt bytes (the echo allowance) are not counted, since the framer
        /// did not spend credit on them.
        var granted = 0
        var arrived = 0
        var consumed = 0
        var outstanding: Int { granted - consumed }
        /// How much credit this flow may have outstanding.
        var window: Double
        var lastLimitedArrival = -TimeInterval.infinity
        var lastArrival = -TimeInterval.infinity
        /// Whether it was using its credit as of the last distribution.
        var busy = false
        /// Arrived and not yet consumed, oldest first, with when each frame arrived.
        var unconsumed = [Unconsumed]()
        var unconsumedHead = 0
        /// (time, wait) with wait increasing: how long frames waited between arrival and
        /// consumption, for the least over the last rttmin.
        var waits = [(time: TimeInterval, wait: TimeInterval)]()
        /// The most this flow's window may be while its session keeps up. Nil when its session
        /// has never fallen behind.
        var cap: Double?
        var lastCapDecrease = -TimeInterval.infinity

        var oldestUnconsumed: Unconsumed? {
            unconsumedHead < unconsumed.count ? unconsumed[unconsumedHead] : nil
        }
    }

    let parameters: Parameters
    private(set) var statistics = Statistics()
    private let send: (Command) -> Void

    /// The window: how much credit may be outstanding across all flows.
    private(set) var window: Double
    private var flows: [Flow: FlowState]
    /// Flows that ended. Frames of theirs still on the way arrive afterward and are ignored,
    /// rather than bringing the flow back with nobody left to consume them.
    private var endedFlows = Set<Flow>()
    /// Totals in bytes across flows since flow control started.
    var granted: Int { flows.values.reduce(0) { $0 + $1.granted } }
    var arrived: Int { flows.values.reduce(0) { $0 + $1.arrived } }
    var consumed: Int { flows.values.reduce(0) { $0 + $1.consumed } }
    var outstanding: Int { granted - consumed }

    private var base = WindowedExtreme(keepsMinimum: true)
    private var roundTrip = WindowedExtreme(keepsMinimum: true)
    private var rate = WindowedExtreme(keepsMinimum: false)
    private var lastRoundTrip: TimeInterval
    private var lastRate: Double?
    /// (time, owd) with owd increasing, for the minimum over the last rttmin.
    private var recent = [(time: TimeInterval, owd: TimeInterval)]()

    private var slowStart = true
    private var lastDoubling: TimeInterval
    private var lastTick: TimeInterval
    private var lastArrival: TimeInterval
    /// Whether the last frame to arrive was sent after the framer ran out of credit.
    private var lastArrivalWasLimited = false
    private var lastLimitedArrival = -TimeInterval.infinity
    private var lastDecrease = -TimeInterval.infinity
    private var lastGrant: TimeInterval

    /// The arrival that began the current rate interval. Bytes after it count, so the rate is
    /// measured between deliveries: a single frame cannot make a short interval look fast.
    private var rateStart: TimeInterval?
    private var rateBytes = 0
    private var rateWasLimited = false

    private var drainState = DrainState.idle
    private var drainIsReset = false
    private var drainSentAt: TimeInterval = 0
    private var windowBeforeDrain: Double
    /// Flows that were using their credit when the drain began. A drain stops every flow, so
    /// none runs out of credit during it; these count as busy again when it ends.
    private var busyBeforeDrain = Set<Flow>()
    /// Each flow's `granted` when each unanswered drain was sent.
    private var unansweredDrains = [[Flow: Int]]()
    private var lastDrainEnd: TimeInterval
    private var lastDrainLength: TimeInterval
    /// (time, seconds window-limited) per tick since the last drain, for the drain schedule.
    private var limitedHistory = [(time: TimeInterval, seconds: TimeInterval)]()
    /// From a reset until its drain completes, nothing is sampled.
    private(set) var quarantined = false
    private var quarantineEnd = -TimeInterval.infinity

    /// Starts after the framer accepted `flow on`, which gave the leader the initial credit.
    /// `recovering` instead starts after `recover` on a framer with flow control, which leaves
    /// it with no credit: the end of the recovery block is the reply to that reset's drain.
    init(now: TimeInterval,
         recovering: Bool,
         parameters: Parameters = Parameters(),
         send: @escaping (Command) -> Void) {
        self.parameters = parameters
        self.send = send
        window = Double(parameters.initialCredit)
        windowBeforeDrain = window
        flows = [.leader: FlowState(window: window)]
        lastRoundTrip = parameters.defaultRTT
        lastDoubling = now
        lastTick = now
        lastArrival = now
        lastGrant = now
        lastDrainEnd = now
        // A fresh start counts as a completed drain one default round trip long, so a flood
        // that starts at once can be drained within its first second.
        lastDrainLength = parameters.defaultRTT
        if recovering {
            beginDrain(now: now, reset: true, sendCommand: false)
        } else {
            flows[.leader]!.granted = parameters.initialCredit
        }
    }

    // MARK: - Derived values

    /// L: how far back the minimums look. At least two drain periods, so a drain's samples
    /// last until the next drain refreshes them.
    private var baselineWindow: TimeInterval {
        max(parameters.minimumBaselineWindow, 2 * (parameters.drainRepeat + 1) * lastDrainLength)
    }

    func rttMin(now: TimeInterval) -> TimeInterval {
        roundTrip.value(now: now, window: baselineWindow) ?? lastRoundTrip
    }

    func target(now: TimeInterval) -> TimeInterval {
        max(parameters.minimumTarget, rttMin(now: now))
    }

    /// Delivery rate in bytes per second, if measured.
    func deliveryRate(now: TimeInterval) -> Double? {
        rate.value(now: now, window: baselineWindow) ?? lastRate
    }

    func floor(now: TimeInterval) -> Double {
        guard let rate = deliveryRate(now: now) else {
            return Double(parameters.initialCredit)
        }
        return min(max(rate * parameters.floorTime, parameters.floorMinimum), parameters.floorMaximum)
    }

    /// How often `tick` should run.
    func tickInterval(now: TimeInterval) -> TimeInterval {
        max(parameters.minimumGrantInterval, rttMin(now: now) / parameters.grantIntervalRTTDivisor)
    }

    /// Queueing delay: the least any frame that arrived in the last rttmin waited.
    func queueingDelay(now: TimeInterval) -> TimeInterval? {
        let horizon = now - rttMin(now: now)
        recent.removeAll { $0.time < horizon }
        guard let least = recent.first?.owd,
              let base = base.value(now: now, window: baselineWindow) else {
            return nil
        }
        return max(0, least - base)
    }

    /// How long a flow's bytes have been waiting for its session to consume them: the least
    /// any frame consumed in the last rttmin waited, or, if none was consumed, how long the
    /// oldest one has been waiting.
    func consumptionDelay(of flow: Flow, now: TimeInterval) -> TimeInterval? {
        guard var state = flows[flow] else {
            return nil
        }
        let horizon = now - rttMin(now: now)
        state.waits.removeAll { $0.time < horizon }
        flows[flow] = state
        if let least = state.waits.first?.wait {
            return least
        }
        return state.oldestUnconsumed.map { now - $0.time }
    }

    func window(of flow: Flow) -> Double? {
        flows[flow]?.window
    }

    func outstanding(of flow: Flow) -> Int? {
        flows[flow]?.outstanding
    }

    func granted(to flow: Flow) -> Int? {
        flows[flow]?.granted
    }

    /// Bytes of the flow that arrived and have not been consumed.
    func backlog(of flow: Flow) -> Int? {
        flows[flow].map { $0.arrived - $0.consumed }
    }

    /// Whether `tick` has anything to do. An idle session needs no ticks until a frame
    /// arrives: its windows are full, nothing is waiting to be consumed, and no heartbeat is due.
    func wantsTicks(now: TimeInterval) -> Bool {
        if isDraining || now - lastArrival <= parameters.heartbeatEvidence {
            return true
        }
        return flows.values.contains { state in
            if state.arrived != state.consumed {
                return true
            }
            let topUp = state.window - Double(state.outstanding)
            return topUp > 0 && topUp >= state.window / parameters.grantThresholdDivisor
        }
    }

    var isDraining: Bool {
        if case .idle = drainState {
            return false
        }
        return true
    }

    // MARK: - Inputs

    /// A flow began, such as a pane. It gets credit at once, drawn from the window.
    func flowDidStart(_ flow: Flow, now: TimeInterval) {
        endedFlows.remove(flow)
        guard flows[flow] == nil else {
            return
        }
        flows[flow] = FlowState(window: floor(now: now))
        if !isDraining {
            distribute(now: now, elapsed: 0)
            topUp(flow, now: now)
        }
    }

    /// A flow ended. Its credit goes with it.
    func flowDidEnd(_ flow: Flow) {
        guard flow != .leader else {
            return
        }
        flows.removeValue(forKey: flow)
        endedFlows.insert(flow)
    }

    /// A controlled frame reached iTerm2, sent at `sendMilliseconds` on the framer's clock.
    /// `limited` means the flow ran out of credit before it was sent; `exempt` means it came from
    /// the echo allowance. `now` must be on a clock that counts sleep, like CLOCK_MONOTONIC.
    func frameDidArrive(now: TimeInterval,
                        flow: Flow = .leader,
                        sendMilliseconds: Int64,
                        bytes: Int,
                        limited: Bool,
                        exempt: Bool) {
        if endedFlows.contains(flow) {
            return
        }
        if flows[flow] == nil {
            // Output of a flow nobody announced, such as a pane started before a recovery.
            flows[flow] = FlowState(window: floor(now: now))
        }
        if !exempt {
            flows[flow]!.arrived += bytes
        }
        flows[flow]!.unconsumed.append(Unconsumed(time: now, bytes: bytes, exempt: exempt))
        flows[flow]!.lastArrival = now
        if limited {
            flows[flow]!.lastLimitedArrival = now
        }
        let silence = now - lastArrival
        let wasFlooding = lastArrivalWasLimited
        lastArrival = now
        lastArrivalWasLimited = limited
        if limited {
            lastLimitedArrival = now
        }
        if quarantined {
            return
        }
        if case .idle = drainState, silence > silenceThreshold(now: now), wasFlooding {
            // Frames were arriving window-limited and then none arrived for a while: the remote
            // was paused or suspended, which can step its clock, or the path stalled. Either way
            // the baselines are suspect.
            statistics.silences += 1
            reset(now: now)
            return
        }
        if let rateStart {
            if !exempt {
                rateBytes += bytes
            }
            if limited {
                rateWasLimited = true
            }
            if now - rateStart >= rttMin(now: now) {
                takeRateSample(now: now, since: rateStart)
            }
        } else {
            rateStart = now
        }
        // A frame is seen once its last byte is in, so its reading includes the time to transmit
        // it: 0.2 s for 4 KB at 20 KB/s. Small frames, such as echo, would then set a baseline
        // that large ones never reach, and every large frame would look queued. Taking the
        // transmission time out at the measured rate leaves roughly when its first byte came.
        let transmission = deliveryRate(now: now).map { Double(bytes) / $0 } ?? 0
        let owd = now - Double(sendMilliseconds) / 1000 - transmission
        // The reading joins the baseline before dq is computed, so dq is never negative.
        base.add(owd, now: now, window: baselineWindow)
        while let last = recent.last, last.owd >= owd {
            recent.removeLast()
        }
        recent.append((now, owd))
    }

    /// The flow's session consumed `bytes` of its output, in the order it arrived.
    func flowDidConsume(_ flow: Flow, bytes: Int, now: TimeInterval) {
        guard var state = flows[flow] else {
            return
        }
        var remaining = bytes
        var oldest: TimeInterval?
        while remaining > 0, state.unconsumedHead < state.unconsumed.count {
            var head = state.unconsumed[state.unconsumedHead]
            oldest = oldest ?? head.time
            let taken = min(head.bytes, remaining)
            remaining -= taken
            if !head.exempt {
                state.consumed += taken
            }
            head.bytes -= taken
            if head.bytes == 0 {
                state.unconsumedHead += 1
            } else {
                state.unconsumed[state.unconsumedHead] = head
            }
        }
        if state.unconsumedHead > 64 && state.unconsumedHead * 2 > state.unconsumed.count {
            state.unconsumed.removeFirst(state.unconsumedHead)
            state.unconsumedHead = 0
        }
        if let oldest {
            let wait = now - oldest
            while let last = state.waits.last, last.wait >= wait {
                state.waits.removeLast()
            }
            state.waits.append((now, wait))
        }
        flows[flow] = state
    }

    /// The round trip of a command with a reply, other than a drain or its ping.
    func roundTripDidComplete(sentAt: TimeInterval, now: TimeInterval) {
        if quarantined || sentAt < quarantineEnd {
            return
        }
        takeRoundTripSample(now - sentAt, now: now)
    }

    /// The reply to a drain, or the end of a recovery block.
    func drainDidReply(now: TimeInterval) {
        guard !unansweredDrains.isEmpty else {
            return
        }
        let grantedWhenSent = unansweredDrains.removeFirst()
        // The framer's credit was zero, everything it sent before replying has arrived, and a
        // grant sent after the drain (only once a drain was abandoned, or to a flow that began
        // since) reached it afterward.
        for flow in Array(flows.keys) {
            let state = flows[flow]!
            flows[flow]!.granted = state.arrived + (state.granted - (grantedWhenSent[flow] ?? 0))
        }
        guard case .draining = drainState, unansweredDrains.isEmpty else {
            return
        }
        // Delay is measured on arrival, so the path is empty now.
        sendPing(now: now)
    }

    /// The reply to a ping, `roundTrip` seconds after it was written.
    func pingDidReply(roundTrip: TimeInterval, now: TimeInterval) {
        guard case .pinging = drainState else {
            roundTripDidComplete(sentAt: now - roundTrip, now: now)
            return
        }
        quarantined = false
        quarantineEnd = now
        takeRoundTripSample(roundTrip, now: now)
        endDrain(now: now)
    }

    /// The framer's safety valve fired: it granted itself credit, so the count is off.
    func valveDidOpen(now: TimeInterval) {
        statistics.valves += 1
        if case .idle = drainState {
            beginDrain(now: now, reset: false, sendCommand: true)
        }
    }

    /// Something invalidated the baselines, such as the Mac waking.
    func reset(now: TimeInterval) {
        base.reset()
        recent.removeAll()
        rateBytes = 0
        rateStart = nil
        rateWasLimited = false
        lastArrivalWasLimited = false
        if case .idle = drainState {
            beginDrain(now: now, reset: true, sendCommand: true)
        } else {
            drainIsReset = true
            quarantined = true
        }
    }

    // MARK: - The periodic step

    func tick(now: TimeInterval) {
        // At most a round trip: after a long gap (an idle session stops ticking; a busy main
        // thread delays the timer) growth and the drain schedule count no more than that.
        let elapsed = min(now - lastTick, rttMin(now: now))
        lastTick = now
        let windowLimited = now - lastLimitedArrival <= activeHorizon(now: now)
        limitedHistory.append((now, windowLimited ? elapsed : 0))
        limitedHistory.removeAll { $0.time < now - baselineWindow }
        if isDraining {
            checkDrainDeadline(now: now)
            return
        }
        adjustWindow(now: now, elapsed: elapsed, windowLimited: windowLimited)
        if !quarantined && drainIsDue(now: now) {
            beginDrain(now: now, reset: false, sendCommand: true)
            return
        }
        distribute(now: now, elapsed: elapsed)
        var granted = false
        for flow in flows.keys.sorted(by: Self.order) {
            granted = topUp(flow, now: now) || granted
        }
        if !granted && heartbeatIsDue(now: now) {
            statistics.heartbeats += 1
            grant(.leader, 0, now: now)
        }
    }

    // MARK: - Internals

    /// The leader first, then the others in a stable order.
    private static func order(_ a: Flow, _ b: Flow) -> Bool {
        func key(_ flow: Flow) -> (Int, Int32) {
            switch flow {
            case .leader:
                return (0, 0)
            case .it2:
                return (1, 0)
            case .pane(let pid):
                return (2, pid)
            }
        }
        return key(a) < key(b)
    }

    /// How recently the framer must have run out of credit for the session to count as
    /// window-limited. On a path shorter than the grant cadence the framer cannot run out more
    /// often than grants arrive, so the round trip is stretched to two grant intervals.
    private func activeHorizon(now: TimeInterval) -> TimeInterval {
        max(rttMin(now: now), 2 * tickInterval(now: now))
    }

    /// How recently a flow must have run out of credit, or had output arrive, to count as busy.
    /// A flood's output pauses while it waits for credit: a grant takes a round trip, and its
    /// bytes then wait behind up to a target of queue. On a slow path its frames also arrive
    /// far apart (4 KB takes 0.2 s at 20 KB/s, and longer when the path is shared), so the
    /// horizon adds two frames' transmission for each busy flow.
    private func busyHorizon(now: TimeInterval) -> TimeInterval {
        let busy = max(1, flows.values.filter(\.busy).count)
        let frames = deliveryRate(now: now).map { 2 * Double(busy * parameters.frameSize) / $0 } ?? 0
        return max(activeHorizon(now: now), rttMin(now: now) + target(now: now)) + frames
    }

    /// Grants the flow what its window allows, if that is worth a grant.
    @discardableResult
    private func topUp(_ flow: Flow, now: TimeInterval, force: Bool = false) -> Bool {
        guard let state = flows[flow] else {
            return false
        }
        let topUp = state.window - Double(state.outstanding)
        guard topUp > 0 && (force || topUp >= state.window / parameters.grantThresholdDivisor) else {
            return false
        }
        grant(flow, Int(topUp), now: now)
        return true
    }

    /// Sets each flow's window. A flow whose session falls behind gets a cap; flows that ran out
    /// of credit recently split what is left equally, and the others hold the floor.
    private func distribute(now: TimeInterval, elapsed: TimeInterval) {
        let floor = floor(now: now)
        let horizon = busyHorizon(now: now)
        for flow in flows.keys {
            adjustCap(of: flow, now: now, elapsed: elapsed, horizon: horizon, floor: floor)
        }
        // Busy: it ran out of credit recently, or it was busy and its output is still arriving.
        // Credit already granted cannot be taken back, so a flood that did not happen to run out
        // in the last round trip keeps its share; otherwise the others' shares would grow while
        // its credit was still on the path, and the total would overshoot W.
        for flow in flows.keys {
            let state = flows[flow]!
            flows[flow]!.busy = now - state.lastLimitedArrival <= horizon
                || (state.busy && now - state.lastArrival <= horizon)
        }
        var active = flows.keys.filter { flows[$0]!.busy }
        if active.isEmpty {
            // Nobody is using credit: everyone gets an equal share, ready for whatever starts.
            active = Array(flows.keys)
        }
        // An idle flow's credit sits unused in the framer rather than on the path, so the busy
        // flows split the whole window, and idle ones hold the floor besides. One that starts
        // sending adds at most the floor to the path before it counts as busy.
        var pool = window
        for flow in flows.keys where !active.contains(flow) {
            flows[flow]!.window = floor
        }
        // Water-filling: a flow capped below an equal share gets its cap, and the rest share
        // what it leaves.
        var remaining = active.sorted { (flows[$0]!.cap ?? .infinity) < (flows[$1]!.cap ?? .infinity) }
        while let first = remaining.first {
            let share = pool / Double(remaining.count)
            guard let cap = flows[first]!.cap, cap < share else {
                break
            }
            let capped = max(floor, cap)
            flows[first]!.window = capped
            pool -= capped
            remaining.removeFirst()
        }
        for flow in remaining {
            flows[flow]!.window = max(floor, pool / Double(remaining.count))
        }
    }

    /// LEDBAT-style, on how long the flow's bytes wait to be consumed rather than on the path.
    private func adjustCap(of flow: Flow,
                           now: TimeInterval,
                           elapsed: TimeInterval,
                           horizon: TimeInterval,
                           floor: Double) {
        guard let delay = consumptionDelay(of: flow, now: now) else {
            return
        }
        let rtt = rttMin(now: now)
        let target = target(now: now)
        var state = flows[flow]!
        if delay > target {
            if now - state.lastCapDecrease >= rtt {
                let current = min(state.cap ?? state.window, state.window)
                state.cap = max(floor, current * (1 - min(0.5, delay / target - 1)))
                state.lastCapDecrease = now
                statistics.capDecreases += 1
            }
        } else if let cap = state.cap, now - state.lastLimitedArrival <= horizon {
            let step = max(parameters.stepMinimum, cap / parameters.growthDivisor)
            let grown = cap + step * (elapsed / rtt)
            // Once it no longer binds, the session keeps up again.
            state.cap = grown >= window ? nil : grown
        }
        flows[flow] = state
    }

    private func silenceThreshold(now: TimeInterval) -> TimeInterval {
        max(parameters.silenceMinimum,
            parameters.silenceMultiplier * (rttMin(now: now) + target(now: now)))
    }

    private func adjustWindow(now: TimeInterval, elapsed: TimeInterval, windowLimited: Bool) {
        let rtt = rttMin(now: now)
        let target = target(now: now)
        if !slowStart && now - lastArrival > baselineWindow {
            // Idle for longer than L: probe again from the kept window.
            slowStart = true
            lastDoubling = now
        }
        if let dq = queueingDelay(now: now) {
            if slowStart {
                if dq > target / 2 {
                    slowStart = false
                } else if windowLimited && now - lastDoubling >= rtt {
                    window *= 2
                    lastDoubling = now
                }
            }
            if !slowStart {
                if dq < target {
                    if windowLimited {
                        let step = max(parameters.stepMinimum, window / parameters.growthDivisor)
                        window += step * (elapsed / rtt)
                    }
                } else if dq > target && now - lastDecrease >= rtt {
                    window *= 1 - min(0.5, dq / target - 1)
                    lastDecrease = now
                    statistics.decreases += 1
                }
            }
        }
        clampWindow(now: now)
    }

    private func clampWindow(now: TimeInterval) {
        var upper = parameters.absoluteCap
        if let rate = deliveryRate(now: now) {
            upper = min(upper,
                        parameters.rateBoundMultiplier * rate * (rttMin(now: now) + target(now: now)))
        }
        window = max(min(window, upper), floor(now: now))
    }

    private func heartbeatIsDue(now: TimeInterval) -> Bool {
        guard Double(outstanding) >= window / 2,
              now - lastGrant >= parameters.heartbeatInterval else {
            return false
        }
        // Outstanding credit alone is not evidence: an idle session always has it.
        return now - lastLimitedArrival <= parameters.heartbeatEvidence
            || Double(arrived - consumed) >= window / 4
    }

    private func drainIsDue(now: TimeInterval) -> Bool {
        let since = now - lastDrainEnd
        guard since > 0, since >= parameters.drainRepeat * lastDrainLength else {
            return false
        }
        // Out of credit for more than half the time since the last drain, looking back at
        // most L, so quiet minutes before a flood do not put its first drain off.
        let span = min(since, baselineWindow)
        let limited = limitedHistory.reduce(0) { $0 + $1.seconds }
        return limited > 0.5 * span
    }

    private func grant(_ flow: Flow, _ bytes: Int, now: TimeInterval) {
        flows[flow]?.granted += bytes
        lastGrant = now
        statistics.grants += 1
        send(.grant(flow, bytes))
    }

    private func takeRoundTripSample(_ seconds: TimeInterval, now: TimeInterval) {
        statistics.roundTripSamples += 1
        roundTrip.add(seconds, now: now, window: baselineWindow)
        lastRoundTrip = rttMin(now: now)
    }

    private func takeRateSample(now: TimeInterval, since start: TimeInterval) {
        let elapsed = now - start
        if elapsed > 0 {
            let sample = Double(rateBytes) / elapsed
            let estimate = deliveryRate(now: now)
            // An app-limited interval only shows how much the program wrote, so it counts
            // only when it beats an estimate from a window-limited one. Otherwise typing
            // would set a rate of a few bytes a second, and the rate bound would squeeze the
            // window a later flood starts from.
            if sample > 0 && (rateWasLimited || estimate.map { sample > $0 } ?? false) {
                rate.add(sample, now: now, window: baselineWindow)
                lastRate = deliveryRate(now: now)
            }
        }
        rateStart = now
        rateBytes = 0
        rateWasLimited = false
    }

    private func beginDrain(now: TimeInterval, reset: Bool, sendCommand: Bool) {
        statistics.drains += 1
        if reset {
            statistics.resetDrains += 1
            quarantined = true
        }
        drainState = .draining
        drainIsReset = reset
        drainSentAt = now
        windowBeforeDrain = window
        busyBeforeDrain = Set(flows.keys.filter { flows[$0]!.busy })
        unansweredDrains.append(flows.mapValues(\.granted))
        if sendCommand {
            send(.drain)
        }
    }

    private func sendPing(now: TimeInterval) {
        drainState = .pinging
        send(.ping)
    }

    private func checkDrainDeadline(now: TimeInterval) {
        if drainIsReset {
            // Abandoning it would leave no baseline to fall back on, and its backlog arrives
            // whether or not iTerm2 waits.
            return
        }
        let deadline = max(parameters.drainDeadlineMinimum,
                           parameters.drainDeadlineRTTs * rttMin(now: now))
        if now - drainSentAt > deadline {
            statistics.abandonedDrains += 1
            // Keep the old baseline and grant again. A late reply still resynchronizes.
            endDrain(now: now)
        }
    }

    private func endDrain(now: TimeInterval) {
        drainState = .idle
        lastDrainLength = now - drainSentAt
        lastDrainEnd = now
        limitedHistory.removeAll()
        window = windowBeforeDrain
        drainIsReset = false
        for flow in busyBeforeDrain {
            flows[flow]?.lastLimitedArrival = now
            flows[flow]?.lastArrival = now
        }
        busyBeforeDrain.removeAll()
        clampWindow(now: now)
        distribute(now: now, elapsed: 0)
        for flow in flows.keys.sorted(by: Self.order) {
            topUp(flow, now: now, force: true)
        }
    }
}

/// The least (or greatest) value over roughly the last `window` seconds, kept in two buckets
/// of half a window each. A new value counts at once.
struct WindowedExtreme {
    private let keepsMinimum: Bool
    private var current: Double?
    private var currentStart: TimeInterval?
    private var previous: Double?
    private var previousStart: TimeInterval?

    init(keepsMinimum: Bool) {
        self.keepsMinimum = keepsMinimum
    }

    mutating func reset() {
        current = nil
        currentStart = nil
        previous = nil
        previousStart = nil
    }

    mutating func add(_ value: Double, now: TimeInterval, window: TimeInterval) {
        rotate(now: now, window: window)
        current = better(current, value)
    }

    mutating func value(now: TimeInterval, window: TimeInterval) -> Double? {
        rotate(now: now, window: window)
        if let previous, let previousStart, now - previousStart <= window {
            return better(current, previous)
        }
        return current
    }

    private mutating func rotate(now: TimeInterval, window: TimeInterval) {
        guard let start = currentStart else {
            currentStart = now
            return
        }
        if now - start >= window / 2 {
            previous = current
            previousStart = start
            current = nil
            currentStart = now
        }
    }

    private func better(_ a: Double?, _ b: Double) -> Double {
        guard let a else {
            return b
        }
        return keepsMinimum ? min(a, b) : max(a, b)
    }
}

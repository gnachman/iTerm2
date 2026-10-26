//
//  Conductor+Flow.swift
//  iTerm2SharedARC
//
//  Flow control between the framer and iTerm2. The framer sends a program's output only with
//  credit that iTerm2 grants, so a flood waits in the remote pty, where Ctrl-C discards it,
//  rather than in ssh's buffers. FramerFlowController decides how much to grant; this extension
//  negotiates flow control with the framer, carries out the controller's commands, and tells it
//  about arrivals, consumption, round trips, drain replies and the framer's safety valve.
//
//  Version 2 gives the leader, each workgroup peer's pane and it2 credit of their own. A pane's
//  credit comes back when the pane's own session has executed its output (see
//  FramerPaneJobManager), and it2's when its data reaches the it2 demultiplexer. A framer that
//  predates version 2 has one flow: pane output then counts as the leader's, consumed as soon
//  as it is handed to the pane's session.
//
//  With nested SSH Integration every framer limits its own reads by its own credit, so each
//  conductor runs a controller for its framer once its parent's runs version 2. A child's
//  commands, grants included, reach its framer as keystrokes through its parent's.
//

import Foundation

extension Conductor {
    /// Why a conductor's framer is not paced, recorded when that was decided. The setting can
    /// change afterward without changing what was decided, so the reason is not worked out
    /// again from the current setting.
    enum FlowOffReason: Equatable {
        /// “Pace output from remote hosts” was off.
        case settingOff
        /// A test turned off flow control for nested framers.
        case nestedOffForTesting
        /// The parent does not frame this conductor's output.
        case parentDoesNotFrame
        /// Waiting for the parent to run flow control version 2.
        case waitingForParent
        /// The framer refused `flow on`.
        case unsupported
        /// `flow on` was aborted and not sent again.
        case aborted
    }

    /// A clock that never jumps and counts sleep, like the framer's.
    nonisolated static func monotonicNow() -> TimeInterval {
        return Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    /// Sent once the framer is running. An older framer fails it, and output stays
    /// uncontrolled, as before. A nested conductor waits until its parent's framer runs
    /// version 2; with any older framer in the chain only the outermost one is controlled.
    func startFlowControlIfPossible() {
        guard !flowOnPending else {
            return
        }
        // A framer that may have flow control on needs a controller whatever the setting.
        guard Self.flowControlAvailable || flowMayBeOn else {
            flowOffReason = .settingOff
            return
        }
        if let parent {
            guard Self.nestedFlowControlAvailableForTesting ?? true else {
                flowOffReason = .nestedOffForTesting
                return
            }
            guard parent.framing, parent.depth + 1 == depth else {
                DLog("The parent does not frame this conductor's output; no flow control")
                flowOffReason = .parentDoesNotFrame
                return
            }
            guard parent.flowController != nil, parent.flowVersion >= 2 else {
                DLog("Wait for the parent to run flow control version 2")
                flowOffReason = .waitingForParent
                parent.flowChildrenWaiting.add(self)
                return
            }
        }
        flowOffReason = nil
        // Listen before the framer can send a controlled frame: frames that follow the reply
        // in the stream can be parsed, and even executed, before the reply is handled here.
        // Missing them would leave credit counted as outstanding that the framer has spent.
        activateFlowLedgerIfPossible()
        sendFlowOn(.framerFlowOn)
    }

    private func sendFlowOn(_ command: Command) {
        flowOnPending = true
        flowMayBeOn = true
        send(command, .handleEphemeralCompletion(StringArray(), .init({ [weak self] string, status in
            self?.flowOnDidReply(string, status: status, command: command)
        })))
    }

    /// The reply's round trip becomes the controller's first sample once this returns (see
    /// flowCommandDidEnd). Nothing controlled had been sent yet, so it crossed an empty path.
    private func flowOnDidReply(_ reply: String, status: Int32, command: Command) {
        flowOnPending = false
        if status == Self.abortedStatus {
            // The connection ended, or the queue was reset before the framer answered. It may
            // have read `flow on` and be waiting for grants, so while the connection lasts send
            // it again; the new controller drains to learn what is in flight.
            DLog("flow on was aborted")
            stopFlowControl()
            guard !hasEnded, flowOnRetries < Self.maxFlowOnRetries else {
                flowOffReason = .aborted
                return
            }
            flowOnRetries += 1
            flowRestartingAfterRestore = true
            // Not yet: this runs while the queue is being dropped, and whatever dropped it
            // (a reset) sends next. Replies are matched by position, so `flow on` must follow
            // the reset's command, which absorbs replies to the aborted ones.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.hasEnded, self.flowController == nil else {
                    return
                }
                self.flowRestartingAfterRestore = true
                self.startFlowControlIfPossible()
            }
            return
        }
        flowOnRetries = 0
        if status != 0, command == .framerFlowOn, parent == nil {
            // A framer from an older iTerm2, found after a restart, speaks only version 1.
            // Nested framers are controlled only when all of them speak version 2.
            DLog("The framer does not speak flow control version 2 (status \(status): \(reply))")
            sendFlowOn(.framerFlowOnVersion1)
            return
        }
        guard status == 0, let (version, clock) = Self.flowVersionAndClock(fromReply: reply) else {
            DLog("The framer does not support flow control (status \(status): \(reply))")
            stopFlowControl()
            flowOffReason = .unsupported
            flowMayBeOn = false
            flowChildrenWaiting.removeAllObjects()
            return
        }
        let now = flowClock()
        startFlowController(version: version, clock: clock, recovering: false, now: now)
        if flowRestartingAfterRestore {
            // Frames sent with credit from before the restart are counted against the new
            // initial credit. A reset drain sets every count from what arrived, and samples
            // nothing until then.
            flowRestartingAfterRestore = false
            flowController?.reset(now: now, reason: "Flow control restarted with credit from before")
        }
    }

    /// Recovery found a framer with flow control on. It holds no credit now. The framer
    /// needs grants to send anything, so the controller runs whether or not flow control is
    /// available.
    func resumeFlowControl(afterRecoveryWith flow: String) {
        guard let (version, clock) = Self.flowVersionAndClock(fromReply: flow) else {
            DLog("Unrecognized flow control state in recovery: \(flow)")
            return
        }
        flowMayBeOn = true
        startFlowController(version: version, clock: clock, recovering: true, now: flowClock())
    }

    /// Resynchronizing after recovery is done, so everything the framer sent before its
    /// recovery block has arrived: that serves as the reply to the reset's drain. Called once
    /// the conductor can send again, since the drain continues with a ping.
    func flowRecoveryDidFinish() {
        flowController?.drainDidReply(now: flowClock())
    }

    /// After iTerm2 restarts, a conductor restored from its saved state has no controller,
    /// though its framer may still have flow control on and will stop once its leftover credit
    /// is spent. `flow on` again resets the framer's credit and starts a controller. Only the
    /// innermost conductor is told it resynchronized, so this restarts each one in the chain,
    /// outermost first; each nested one waits for its parent's.
    func restartFlowControlAfterResynchronizing() {
        var chain = [self]
        while let parent = chain.last?.parent {
            chain.append(parent)
        }
        for conductor in chain.reversed() where conductor.flowController == nil {
            DLog("Restart flow control after resynchronizing at depth \(conductor.depth)")
            conductor.flowRestartingAfterRestore = true
            conductor.startFlowControlIfPossible()
        }
    }

    static let maxFlowOnRetries = 3

    /// Parses "<version> <clock>", the reply to `flow on` and the value of `recovery: flow`.
    static func flowVersionAndClock(fromReply reply: String) -> (Int, String)? {
        let parts = reply.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        guard parts.count >= 2, let version = Int(parts[0]), (1...2).contains(version), !parts[1].isEmpty else {
            return nil
        }
        return (version, parts[1])
    }

    private func startFlowController(version: Int, clock: String, recovering: Bool, now: TimeInterval) {
        DLog("Start flow control version \(version) with the framer's \(clock) clock, recovering=\(recovering)")
        flowClockName = clock
        flowVersion = version
        let controller = FramerFlowController(now: now, recovering: recovering) { [weak self] command in
            self?.perform(flowCommand: command)
        }
        flowController = controller
        if version >= 2 {
            // The framer gives only the leader initial credit; the others are granted theirs.
            controller.flowDidStart(.it2, now: now)
            for pid in knownPanePIDs.union(panes.keys).sorted() {
                controller.flowDidStart(.pane(pid), now: now)
            }
        }
        activateFlowLedgerIfPossible()
        feedFlowController()
        scheduleFlowTick()
        if version >= 2 {
            let children = flowChildrenWaiting.allObjects
            flowChildrenWaiting.removeAllObjects()
            for child in children {
                child.startFlowControlIfPossible()
            }
        }
    }

    // MARK: - Flows

    private var paneFlowController: FramerFlowController? {
        guard flowVersion >= 2 else {
            return nil
        }
        return flowController
    }

    /// A pane is running on this conductor's framer: it needs credit to send anything.
    func flowPaneDidStart(_ pid: Int32) {
        paneFlowController?.flowDidStart(.pane(pid), now: flowClock())
    }

    func flowPaneDidEnd(_ pid: Int32) {
        // Its last output's arrival may still be in the ledger; take it first.
        feedFlowController()
        paneFlowController?.flowDidEnd(.pane(pid))
    }

    /// The pane's session executed `bytes` of its output.
    func flowPaneDidConsume(_ pid: Int32, bytes: Int, now: TimeInterval) {
        guard let controller = paneFlowController else {
            return
        }
        // The output's arrival was recorded in the leader's ledger before the output was even
        // handed to the pane's session, but the conductor may not have read it yet. Read it
        // first, or the controller would see consumption of bytes it does not know arrived.
        feedFlowController()
        controller.flowDidConsume(.pane(pid), bytes: bytes, now: now)
        if flowTimer == nil {
            scheduleFlowTick()
        }
    }

    /// it2 data reached the demultiplexer.
    func flowIT2DidConsume(bytes: Int) {
        guard let controller = paneFlowController else {
            return
        }
        // As for a pane: its arrival may still be waiting in the ledger.
        feedFlowController()
        controller.flowDidConsume(.it2, bytes: bytes, now: flowClock())
        if flowTimer == nil {
            scheduleFlowTick()
        }
    }

    /// Records made before the controller exists wait in the ledger until it does. A recovered
    /// conductor has no delegate yet when flow control resumes, so this is tried again on
    /// each tick.
    private func activateFlowLedgerIfPossible() {
        guard activeFlowLedger == nil,
              let ledger = delegate?.conductorFlowLedger?() else {
            return
        }
        activeFlowLedger = ledger
        ledger.activate(depth: depth, owner: self) { [weak self] in
            MainActor.assumeIsolated {
                self?.flowLedgerDidRecord()
            }
        }
    }

    /// The session parsed or executed a controlled frame while the controller was idle.
    private func flowLedgerDidRecord() {
        feedFlowController()
        if flowTimer == nil {
            scheduleFlowTick()
        }
    }

    private func feedFlowController() {
        guard let flowController, let ledger = activeFlowLedger else {
            return
        }
        for event in ledger.takeEvents(depth: depth) {
            switch event {
            case let .arrived(time, code, sendMilliseconds, bytes, flags, carrierMilliseconds):
                let flow: FramerFlowController.Flow
                if code == FramerFlowLedger.it2Flow {
                    flow = .it2
                } else if code > 0 && flowVersion >= 2 {
                    flow = .pane(code)
                } else {
                    flow = .leader
                }
                flowController.frameDidArrive(now: time,
                                              flow: flow,
                                              sendMilliseconds: sendMilliseconds,
                                              bytes: bytes,
                                              limited: flags & Self.flowFlagLimited != 0,
                                              exempt: flags & Self.flowFlagExempt != 0,
                                              carrierMilliseconds: carrierMilliseconds == 0 ? nil : carrierMilliseconds)
                if code > 0 && flowVersion < 2 {
                    // One flow: the pane's output is the leader's, and it leaves for the
                    // pane's session as soon as it arrives.
                    flowController.flowDidConsume(.leader, bytes: bytes, now: time)
                }
            case let .executed(time, bytes):
                flowController.flowDidConsume(.leader, bytes: bytes, now: time)
            }
        }
    }

    /// Flow flags in a frame's header (framer.py FLOW_FLAG_LIMITED and FLOW_FLAG_EXEMPT).
    static let flowFlagLimited: Int32 = 1
    static let flowFlagExempt: Int32 = 2

    func stopFlowControl() {
        if flowController != nil {
            DLog("Stop flow control")
        }
        flowController = nil
        flowClockName = nil
        flowRestartingAfterRestore = false
        parent?.flowChildrenWaiting.remove(self)
        activeFlowLedger?.deactivate(depth: depth, owner: self)
        activeFlowLedger = nil
        flowTimer?.invalidate()
        flowTimer = nil
    }

    private func perform(flowCommand command: FramerFlowController.Command) {
        switch command {
        case let .grant(flow, bytes):
            // No reply, so it is not queued: it goes out at once, between whole commands,
            // and the framer applies it as soon as it reads it.
            let arguments: [String]
            switch (flowVersion >= 2, flow) {
            case (false, .leader):
                arguments = ["grant", String(bytes)]
            case (false, _):
                // A framer of version 1 has one flow; only the leader's exists.
                return
            case (true, .leader):
                arguments = ["grant", "leader", String(bytes)]
            case (true, .it2):
                arguments = ["grant", "it2", String(bytes)]
            case (true, .pane(let pid)):
                arguments = ["grant", String(pid), String(bytes)]
            }
            let line = Self.encode(arguments: arguments, isFramer: true, linePrefix: "")
            if let parent {
                // Relayed by the parent as keystrokes, ahead of its queued commands as a typed
                // key is. The controller has counted the credit, so if the parent drops the
                // send the inner framer would wait for it forever.
                parent.sendKeys(Data((line + "\n").utf8), highPriority: true) { [weak self] in
                    self?.flowGrantWasLost()
                }
            } else {
                write(line, highPriority: true)
            }
        case .drain:
            send(.framerDrain, highPriority: true, .fireAndForget)
        case .ping:
            send(.framerPing, highPriority: true, .fireAndForget)
        }
    }

    /// Turning flow control on again resets the framer's credit, and the new controller
    /// drains to learn what is in flight.
    private func flowGrantWasLost() {
        guard flowController != nil else {
            return
        }
        DLog("A relayed grant was lost. Restart flow control at depth \(depth)")
        stopFlowControl()
        flowRestartingAfterRestore = true
        startFlowControlIfPossible()
    }

    /// A command's reply ended and its handler accepted it. Its round trip is a sample
    /// unless it is part of a drain.
    func flowCommandDidEnd(_ context: ExecutionContext) {
        guard let writtenAt = context.writtenAt else {
            return
        }
        let now = flowClock()
        if context.command != .framerDrain {
            // A drain's reply comes back behind everything the framer had sent, so it says
            // nothing about the path.
            roundTrips.append(RoundTrip(time: now, seconds: now - writtenAt))
            roundTrips.removeAll { $0.time < now - 60 }
        }
        guard let flowController else {
            return
        }
        switch context.command {
        case .framerDrain:
            // It came back behind everything the framer had sent, so it is not a sample.
            flowController.drainDidReply(now: now)
        case .framerPing:
            flowController.pingDidReply(roundTrip: now - writtenAt, now: now)
        default:
            flowController.roundTripDidComplete(sentAt: writtenAt, now: now)
        }
    }

    func flowValveDidOpen() {
        DLog("The framer's flow control safety valve opened")
        flowController?.valveDidOpen(now: flowClock())
    }

    // MARK: - Ticks

    func flowTick() {
        flowTimer = nil
        guard let flowController else {
            return
        }
        activateFlowLedgerIfPossible()
        feedFlowController()
        let now = flowClock()
        if let parent {
            // This framer's output is the parent's leader's.
            flowController.carrierWindow = parent.flowController?.window(of: .leader)
        }
        flowController.tick(now: now)
        if flowController.wantsTicks(now: now) {
            scheduleFlowTick()
        }
        // Otherwise the session is idle; the ledger wakes the conductor when output resumes.
    }

    private func scheduleFlowTick() {
        guard flowTicksAutomatically, let flowController else {
            return
        }
        flowTimer?.invalidate()
        let interval = flowController.tickInterval(now: flowClock())
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flowTick()
            }
        }
        // In the common modes, so grants keep going out while a menu is open, a window is
        // resized live, or a tab is dragged; the screen keeps drawing then too.
        RunLoop.main.add(timer, forMode: .common)
        flowTimer = timer
    }
}

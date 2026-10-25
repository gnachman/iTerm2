//
//  Conductor+SSHCommandRunning.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

@MainActor
extension Conductor: SSHCommandRunning {
    func registerProcess(_ pid: pid_t) {
        send(.framerRegister(pid: pid), .fireAndForget)
    }

    func deregisterProcess(_ pid: pid_t) {
        send(.framerDeregister(pid: pid), .fireAndForget)
    }

    func poll(_ completion: @escaping (Data) -> ()) {
        if queue.anySatisfies({ $0.command == .framerPoll }) {
            DLog("Declining to add second poll to queue")
            return
        }
        send(.framerPoll, .handlePoll(StringArray(), .init(completion)))
    }

    @objc
    func reset() {
        log("reset")
        forceReturnToGroundState()
        sendReset()
    }

    private func sendReset() {
        let code = UUID().uuidString
        switch framerVersion {
        case .v1:
            send(.framerReset1, .fireAndForget)
        case .v2:
            send(.framerReset2(code), .handleReset(expected: code, lines: StringArray()))
        case .none where framing:
            // Saved by an iTerm2 that did not record the framer's version. A framer from before
            // 3.6 rejects `reset2` without its code, which would leave the reset waiting
            // forever. Find where replies to earlier commands end first: the framer answers in
            // order, so after the marker comes back the next reply is `reset2`'s.
            let marker = Self.resetMarkerPath()
            send(.framerFile(.stat(path: Data(marker.utf8))),
                 .handleResetMarker(marker: marker, lines: StringArray()))
            send(.framerReset2(code), .handleProbedReset(code: code, lines: StringArray()))
        case .none:
            send(.framerReset1, .fireAndForget)
        }
        if autopollEnabled {
            send(.framerAutopoll, .fireAndForget)
            // The reset forgot every registration, and tmux panes on this host are tracked as
            // well as the login shell.
            sshProcessInfoProvider?.reregisterTrackedPIDs(including: framedPID)
        }
    }

    /// "/" spelled with "./" and "/" in a random order. It always exists, so a framer can stat
    /// it, and its reply spells the path as given, unlike any other reply.
    static func resetMarkerPath() -> String {
        var path = "/"
        for _ in 0..<48 {
            path += Bool.random() ? "./" : "/"
        }
        return path
    }

    /// Clears every depth's queue, then resets each, outermost first. Clearing a queue clears its
    /// ancestors' too, so a reset sent before a deeper queue was cleared would be aborted at once,
    /// and the reply to it, with nothing waiting for it, taken as the answer to the next command.
    @objc
    func resetTransitively() {
        log("reset transitively")
        forceReturnToGroundState()
        var chain = [Conductor]()
        var current: Conductor? = self
        while let conductor = current {
            chain.append(conductor)
            current = conductor.parent
        }
        // A conductor that does not frame, such as one whose host had no Python, has no framer to
        // reset; what it sent would be typed into whatever reads its terminal.
        for conductor in chain.reversed() where conductor.framing && !conductor.hasEnded {
            conductor.sendReset()
        }
    }

    func addBackgroundJob(_ pid: Int32, command: Command, completion: @escaping (Data, Int32) -> ()) {
        let context = ExecutionContext(command: command, handler: .handleBackgroundJob(StringArray(), .init(completion)))
        backgroundJobs[pid] = .executingPipeline(context, [])
        log("Added background job for pid \(pid), context \(context)")
    }

    @objc
    func runRemoteCommand(_ commandLine: String,
                          completion: @escaping (Data, Int32) -> ()) {
        runRemoteCommand(commandLine, started: nil, completion: completion)
    }

    /// `started` gets the job's pid once it runs, so the caller can end it with killRemoteJob.
    func runRemoteCommand(_ commandLine: String,
                          started: ((Int32) -> Void)?,
                          completion: @escaping (Data, Int32) -> ()) {
        if framedPID == 0 {
            completion(Data(), -1)
            return
        }

        // This command ends almost immediately, providing only the child process's pid as output,
        // but in actuality continues running in the background producing %output messages and
        // eventually %terminate.
        send(.framerRun(commandLine), .handleRunRemoteCommand(commandLine, .init(completion), started.map { .init($0) }))
    }

    /// Ends a job runRemoteCommand started: SIGTERM, or with `hangUp` a hangup, as closing a
    /// terminal does, which also ends an interactive shell (that ignores SIGTERM). A framer too
    /// old to hang up sends SIGTERM.
    func killRemoteJob(_ pid: Int32, hangUp: Bool) {
        send(.framerKill(pid: Int(pid), hangUp: hangUp), .fireAndForget)
    }
}

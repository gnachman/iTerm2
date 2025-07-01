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
        send(.framerPoll, .handlePoll(StringArray(), completion))
    }

    @objc
    func reset() {
        send(.framerReset, .fireAndForget)
        if autopollEnabled {
            send(.framerAutopoll, .fireAndForget)
            if let framedPID = framedPID {
                sshProcessInfoProvider?.register(trackedPID: framedPID)
            }
        }
    }

    @objc
    func resetTransitively() {
        parent?.reset()
        reset()
    }

    @objc
    func didResynchronize() {
        DLog("didResynchronize")
        forceReturnToGroundState()
        resetTransitively()
        DLog(self.debugDescription)
    }

    func addBackgroundJob(_ pid: Int32, command: Command, completion: @escaping (Data, Int32) -> ()) {
        let context = ExecutionContext(command: command, handler: .handleBackgroundJob(StringArray(), completion))
        backgroundJobs[pid] = .executingPipeline(context, [])
    }

    @objc
    func runRemoteCommand(_ commandLine: String,
                          completion: @escaping (Data, Int32) -> ()) {
        if framedPID == 0 {
            completion(Data(), -1)
            return
        }

        // This command ends almost immediately, providing only the child process's pid as output,
        // but in actuality continues running in the background producing %output messages and
        // eventually %terminate.
        send(.framerRun(commandLine), .handleRunRemoteCommand(commandLine, completion))
    }
}

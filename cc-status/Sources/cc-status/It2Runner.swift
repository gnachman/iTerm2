import Foundation

// Running it2, and deciding when a failure is worth a word.

/// Runs it2 on behalf of one hook event.
final class It2Runner {
    private let address: Address
    private let eventName: String
    private let agent: Agent
    // Whether this event may report trouble.
    //
    // A pane that will not resolve -- a tmux session iTerm2 is not attached to, or version skew after
    // an in-place update, where a new it2 briefly talks to an old app -- is a real failure for a
    // script but must not be reported once per tool call. So the per-tool-call events ask it2 for
    // silence, and the two session boundaries do not. The condition is persistent when it happens at
    // all, so it is already true at SessionStart: the user still learns about it, once at each end of
    // the session, instead of on every tool call or never. cc-status keeps no state, so the event
    // name is the only budget available.
    private let isSessionBoundary: Bool
    private let quietArgs: [String]

    init(address: Address, eventName: String, agent: Agent) {
        self.address = address
        self.eventName = eventName
        self.agent = agent
        self.isSessionBoundary = (eventName == "SessionStart" || eventName == "SessionEnd")
        self.quietArgs = self.isSessionBoundary ? [] : ["--quiet-if-unresolved"]
    }

    /// Apply an update. Every field is presence-gated, so an event that has nothing to say about a
    /// field leaves it alone rather than clearing it. One it2 invocation carries everything: the
    /// visible status, the parked background-task count and turn flag, the preconditions, and the
    /// expiration, because iTerm2 needs to see the count and the assertion together to decide
    /// whether an update is bookkeeping.
    ///
    /// Returns the status as it stood once the update landed when the update asked for it (see
    /// StatusUpdate.idleDetailIfTasksFinished), or nil otherwise, including when it2 could not be
    /// run or its answer could not be read.
    @discardableResult
    func send(_ update: StatusUpdate) -> CurrentStatus? {
        var statusArgs = [String]()
        if let status = update.status {
            statusArgs += optionArgs("--status", status)
        }
        if let dotColor = update.dotColor {
            statusArgs += optionArgs("--dot-color", dotColor)
        }
        if let textColor = update.textColor {
            statusArgs += optionArgs("--text-color", textColor)
        }
        // Pass --detail only when cc-status has an opinion; empty string explicitly clears.
        if let detail = update.detail {
            statusArgs += optionArgs("--detail", detail)
        }
        if let backgroundTasks = update.backgroundTasks {
            statusArgs += optionArgs("--background-tasks", String(backgroundTasks))
        }
        if let delta = update.backgroundTasksDelta {
            statusArgs += optionArgs("--background-tasks-delta", String(delta))
        }
        if let turnOpen = update.turnOpen {
            statusArgs += optionArgs("--turn-open", String(turnOpen))
        }
        if update.onlyWhenFinished {
            statusArgs += optionArgs("--if-turn-open", "false")
            statusArgs += optionArgs("--if-background-tasks", "0")
        }
        if update.expiresOnProgressEnd {
            statusArgs += optionArgs("--expires-on", "progress-end")
            statusArgs += optionArgs("--then-status", "idle")
            statusArgs += optionArgs("--then-dot-color", idleDot)
            statusArgs += optionArgs("--then-text-color", idleText)
            statusArgs += optionArgs("--then-detail", "")
        }
        guard !statusArgs.isEmpty else {
            return nil
        }
        // A guarded update may be dropped, and the status that comes back is
        // how to tell; the ring below waits for it.
        let wantStatus = update.idleDetailIfTasksFinished != nil
        let guarded = update.onlyWhenFinished
        if wantStatus || guarded {
            statusArgs.append("--json")
        }

        if agent == .codex, let status = update.status, !guarded {
            writeProgressRing(for: status)
        }

        let output = run(["set-status"] + address.args + quietArgs + statusArgs)
        guard let output, wantStatus || guarded else {
            return nil
        }
        let after = CurrentStatus(json: output)
        if agent == .codex, let status = update.status, guarded, after?.status == status {
            writeProgressRing(for: status)
        }

        // Any sub-agent finishing from here on sees this write and reports idle
        // itself. One that finished before it landed could not, or was covered by
        // it; the status that came back with the write says whether one did.
        if let idleDetail = update.idleDetailIfTasksFinished,
           let after, after.backgroundTasks == 0, after.turnOpen == false {
            var idle = StatusUpdate()
            idle.showIdle(detail: idleDetail)
            idle.onlyWhenFinished = true
            send(idle)
        }
        return wantStatus ? after : nil
    }

    /// Progress ring on the tab (OSC 9;4). Claude Code emits it itself, Codex CLI
    /// doesn't. Writing it to the agent's tty reaches the terminal without
    /// disturbing the TUI.
    private func writeProgressRing(for status: String) {
        guard let path = agentTTYPath(), let tty = FileHandle(forWritingAtPath: path) else {
            return
        }
        let seq = status == "working" ? "\u{1b}]9;4;3\u{7}" : "\u{1b}]9;4;0\u{7}"
        tty.write(Data(seq.utf8))
        tty.closeFile()
    }

    /// Run it2 and wait. Returns its trimmed stdout, or nil when it failed. Failures are reported on
    /// stderr but never fail the hook: a status update is cosmetic, and failing the hook over one
    /// would disrupt the session it is describing.
    private func run(_ arguments: [String]) -> String? {
        // Capture it2's stdout rather than leaving it attached: without --json it is chatter
        // ("Session status updated.") that nothing consumes, Claude Code feeds hook stdout back into
        // the model's context for some events, and Codex rejects non-JSON stdout from
        // SessionStart/Stop hooks. With --json it is the status this call was asked for.
        //
        // Capture stderr and print it only if the command actually failed, so a genuine problem still
        // arrives with it2's own explanation attached.
        //
        // What reaches here depends on the event, because quietArgs does. Per-tool-call events pass
        // --quiet-if-unresolved, so an unresolved pane writes nothing and exits 0 there, and only the
        // unexpected surfaces: a connection error, a usage error, the API being off. The two session
        // boundaries do not pass it, so an unresolved pane is reported there too -- deliberately, so a
        // persistent problem is discoverable once at each end of the session rather than never.
        //
        // Unresolved is decided in one place wherever the caller runs: TmuxPaneLocator inside
        // iTerm2, which logs it once per distinct address. A pane on the far side of ssh
        // integration takes the same path, because the call carries the conductor it arrived on
        // and the locator matches tmux servers on that connection (see TmuxPaneLocator).
        guard let result = runIt2(arguments) else {
            FileHandle.standardError.write(Data("cc-status: failed to run it2\n".utf8))
            return nil
        }
        guard result.status != 0 else {
            return result.stdout
        }
        // Report at session boundaries only.
        //
        // The failures a user actually hits here are persistent, not one-off: the API preference
        // turned off, the socket gone, or version skew after an in-place update -- iTerm2 swaps the
        // bundle while the old process keeps running, and it2 is resolved from the bundle on every
        // event, so a new CLI talks to an app without the functions it needs. Reporting per event
        // would put the same two lines in the transcript several times per tool call for the rest of
        // the session, which is the disruption this program exists to avoid. Reporting at the
        // boundary keeps a real problem discoverable -- these conditions are already true at
        // SessionStart -- without repeating it. cc-status keeps no state, so the event name is the
        // only budget available.
        guard isSessionBoundary else {
            return nil
        }
        if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
        FileHandle.standardError.write(Data("cc-status: it2 exited \(result.status) for \(eventName)\n".utf8))
        return nil
    }
}

/// What iTerm2 holds for the session, as `it2 set-status --json` and
/// `it2 session get-status` print it.
struct CurrentStatus {
    /// nil when nothing is displayed.
    var status: String?
    var backgroundTasks: Int
    /// nil when no hook has told iTerm2 about a turn yet.
    var turnOpen: Bool?

    init?(json: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let count = object["background_tasks"] as? Int else {
            return nil
        }
        status = object["status"] as? String
        backgroundTasks = max(0, count)
        turnOpen = object["turn_open"] as? Bool
    }
}

/// Runs it2 with `arguments` and waits, capturing both streams. nil when it could not be launched.
func runIt2(_ arguments: [String]) -> (status: Int32, stdout: String, stderr: String)? {
    let it2 = resolveIt2()
    let process = Process()
    process.executableURL = it2.executable
    process.arguments = it2.leadingArgs + arguments
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    do {
        try process.run()
    } catch {
        return nil
    }
    // Drain both before waiting: readDataToEndOfFile returns at EOF, which is process exit, and
    // reading after waitUntilExit would deadlock if it2 ever filled a pipe buffer. Each pipe is
    // drained on its own thread for the same reason: draining one to EOF while the other fills up
    // would block the child on the second.
    var stdoutData = Data()
    var stderrData = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    group.wait()
    process.waitUntilExit()
    return (process.terminationStatus,
            (String(data: stdoutData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            String(data: stderrData, encoding: .utf8) ?? "")
}

import Foundation

// Running it2, and deciding when a failure is worth a word.

/// Runs it2 on behalf of one hook event.
final class It2Runner {
    private let address: Address
    private let eventName: String
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

    init(address: Address, eventName: String) {
        self.address = address
        self.eventName = eventName
        self.isSessionBoundary = (eventName == "SessionStart" || eventName == "SessionEnd")
        self.quietArgs = self.isSessionBoundary ? [] : ["--quiet-if-unresolved"]
    }

    /// Apply an update. Every field is presence-gated, so an event that has nothing to say about a
    /// field leaves it alone rather than clearing it. One it2 invocation carries everything: the
    /// visible status, the parked background-task count, and the expiration, because iTerm2 needs
    /// to see the count and the assertion together to decide whether an update is bookkeeping.
    func send(_ update: StatusUpdate) {
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
        if update.expiresOnProgressEnd {
            statusArgs += optionArgs("--expires-on", "progress-end")
            statusArgs += optionArgs("--then-status", "idle")
            statusArgs += optionArgs("--then-dot-color", idleDot)
            statusArgs += optionArgs("--then-text-color", idleText)
            statusArgs += optionArgs("--then-detail", "")
        }
        guard !statusArgs.isEmpty else {
            return
        }
        run(["set-status"] + address.args + quietArgs + statusArgs)
    }

    /// Run it2 and wait. Failures are reported on stderr but never fail the hook: a status update is
    /// cosmetic, and failing the hook over one would disrupt the session it is describing.
    private func run(_ arguments: [String]) {
        let it2 = resolveIt2()
        let process = Process()
        process.executableURL = it2.executable
        process.arguments = it2.leadingArgs + arguments
        // Discard it2's stdout: it is chatter ("Session status updated.") that nothing consumes, and
        // Claude Code feeds hook stdout back into the model's context for some events, so leaving it
        // attached puts noise in the transcript.
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
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data("cc-status: failed to run it2: \(error)\n".utf8))
            return
        }
        // Drain before waiting: readDataToEndOfFile returns at EOF, which is process exit, and reading
        // after waitUntilExit would deadlock if it2 ever filled the pipe buffer.
        let capturedStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else {
            return
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
            return
        }
        if let text = String(data: capturedStderr, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            FileHandle.standardError.write(Data(text.utf8))
        }
        FileHandle.standardError.write(Data("cc-status: it2 exited \(process.terminationStatus) for \(eventName)\n".utf8))
    }
}

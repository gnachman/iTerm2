import Foundation
#if canImport(ProtobufRuntime)
import ProtobufRuntime  // standalone SwiftPM build; in-app the types come via the bridging header
#endif

// Saying what a hook event decided: the it2 invocations it takes, and where they go.

/// What one it2 invocation produced.
struct AgentHookCommandResult: Equatable {
    var status: Int32
    var stdout: String
    var stderr: String
}

/// Runs the it2 invocations the hook decides on. The production backend runs them through this
/// process's own command tree; tests substitute one that records the argv and keeps the state
/// iTerm2 would keep.
protocol AgentStatusBackend {
    /// Run `argv` (an it2 command line without the executable) and wait. nil means it could not
    /// be run at all. Throws only when the backend cannot continue at all, which the production
    /// backend never does.
    func run(_ argv: [String]) throws -> AgentHookCommandResult?
}

/// What iTerm2 holds for the session, as `it2 set-status --json` and `it2 session get-status`
/// print it.
struct CurrentAgentStatus {
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

/// Handles one hook event end to end: which session, what to say, saying it. This is the whole of
/// what `it2 handle-agent-hook` does once it has its inputs, kept free of the command tree so the
/// scenarios can drive it against a fake backend.
enum AgentHookHandler {
    /// - Parameters:
    ///   - payload: the hook's JSON, as the agent wrote it to the hook's stdin.
    ///   - environment: the hook's environment, wherever it ran.
    ///   - report: the hook's stderr, one line at a time. A hook prints nothing on stdout: Codex
    ///     rejects non-JSON stdout from some events, and Claude Code feeds it to the model.
    static func handle(payload: Data,
                       agent: AgentKind,
                       environment: [String: String],
                       originSessionID: String? = nil,
                       inProcess: Bool = false,
                       backend: AgentStatusBackend,
                       report: @escaping (String) -> Void) throws {
        guard let event = readAgentHookEvent(payload) else {
            return
        }
        guard let address = resolveAgentHookAddress(environment: environment,
                                                    originSessionID: originSessionID,
                                                    inProcess: inProcess) else {
            return
        }
        let runner = AgentHookRunner(address: address,
                                     eventName: event.name,
                                     agent: agent,
                                     backend: backend,
                                     report: report)
        guard let update = try runner.decide(json: event.json), !update.isEmpty else {
            // Nothing to say. This happens on a Codex SubagentStop that leaves work running: the
            // decrement already stored the new count and the display is deliberately unchanged,
            // so there is no reason to spend another round trip on a set-status carrying only an
            // address.
            return
        }
        try runner.send(update)
    }
}

/// Builds the it2 invocations for one hook event and runs them, deciding when a failure is worth
/// a word.
final class AgentHookRunner {
    let address: AgentHookAddress
    let eventName: String
    let agent: AgentKind
    private let backend: AgentStatusBackend
    private let report: (String) -> Void
    // Whether this event may report trouble.
    //
    // A pane that will not resolve -- a tmux session iTerm2 is not attached to, or version skew
    // after an in-place update -- is a real failure for a script but must not be reported once per
    // tool call. So the per-tool-call events ask it2 for silence, and the two session boundaries
    // do not. The condition is persistent when it happens at all, so it is already true at
    // SessionStart: the user still learns about it, once at each end of the session, instead of
    // on every tool call or never. The hook keeps no state, so the event name is the only budget
    // available.
    private let isSessionBoundary: Bool
    private let quietArgs: [String]

    init(address: AgentHookAddress,
         eventName: String,
         agent: AgentKind,
         backend: AgentStatusBackend,
         report: @escaping (String) -> Void) {
        self.address = address
        self.eventName = eventName
        self.agent = agent
        self.backend = backend
        self.report = report
        self.isSessionBoundary = (eventName == "SessionStart" || eventName == "SessionEnd")
        self.quietArgs = self.isSessionBoundary ? [] : ["--quiet-if-unresolved"]
    }

    /// Apply an update. Every field is presence-gated, so an event that has nothing to say about a
    /// field leaves it alone rather than clearing it. One it2 invocation carries everything: the
    /// visible status, the parked background-task count and turn flag, the preconditions, the
    /// expiration, and for Codex the progress ring, because iTerm2 needs to see the count and the
    /// assertion together to decide whether an update is bookkeeping, and a ring that travels with
    /// a guarded update is dropped along with it.
    ///
    /// Returns the status as it stood once the update landed when the update asked for it (see
    /// AgentStatusUpdate.endingIfTasksFinished), or nil otherwise, including when it2 could
    /// not be run or its answer could not be read.
    @discardableResult
    func send(_ update: AgentStatusUpdate) throws -> CurrentAgentStatus? {
        var statusArgs = [String]()
        if let status = update.status {
            statusArgs += shortcutOptionArgs("--status", status)
        }
        if let dotColor = update.dotColor {
            statusArgs += shortcutOptionArgs("--dot-color", dotColor)
        }
        if let textColor = update.textColor {
            statusArgs += shortcutOptionArgs("--text-color", textColor)
        }
        // Progress ring on the tab (OSC 9;4). Claude Code emits it itself, Codex CLI does not, so
        // the hook asks iTerm2 to draw it for the session in the same update. Working runs the
        // ring; waiting and idle stop it, including the stopped state for a permission prompt.
        if agent == .codex, let status = update.status {
            statusArgs += shortcutOptionArgs("--progress", status == "working" ? "running" : "stopped")
        }
        // Pass --detail only when the hook has an opinion; empty string explicitly clears.
        if let detail = update.detail {
            statusArgs += shortcutOptionArgs("--detail", detail)
        }
        if let backgroundTasks = update.backgroundTasks {
            statusArgs += shortcutOptionArgs("--background-tasks", String(backgroundTasks))
        }
        if let delta = update.backgroundTasksDelta {
            statusArgs += shortcutOptionArgs("--background-tasks-delta", String(delta))
        }
        if let turnOpen = update.turnOpen {
            statusArgs += shortcutOptionArgs("--turn-open", String(turnOpen))
        }
        if update.onlyWhenFinished {
            statusArgs += shortcutOptionArgs("--if-turn-open", "false")
            statusArgs += shortcutOptionArgs("--if-background-tasks", "0")
        }
        if update.expiresOnProgressEnd {
            statusArgs += shortcutOptionArgs("--expires-on", "progress-end")
            statusArgs += shortcutOptionArgs("--then-status", "idle")
            statusArgs += shortcutOptionArgs("--then-dot-color", AgentHookPalette.idleDot)
            statusArgs += shortcutOptionArgs("--then-text-color", AgentHookPalette.idleText)
            statusArgs += shortcutOptionArgs("--then-detail", "")
        }
        guard !statusArgs.isEmpty else {
            return nil
        }
        // A guarded update may be dropped, and the status that comes back is how to tell.
        let wantStatus = update.endingIfTasksFinished != nil
        let guarded = update.onlyWhenFinished
        if wantStatus || guarded {
            statusArgs.append("--json")
        }

        let output = try run(["set-status"] + address.args + quietArgs + statusArgs)
        guard let output, wantStatus || guarded else {
            return nil
        }
        let after = CurrentAgentStatus(json: output)

        // Any sub-agent finishing from here on sees this write and reports done itself. One that
        // finished before it landed could not, or was covered by it; the status that came back
        // with the write says whether one did.
        if let (ending, detail) = update.endingIfTasksFinished,
           let after, after.backgroundTasks == 0, after.turnOpen == false {
            var ended = AgentStatusUpdate()
            ended.showEnded(ending, detail: detail)
            ended.onlyWhenFinished = true
            try send(ended)
        }
        return wantStatus ? after : nil
    }

    /// Ask iTerm2 for the stored count. 0 when unavailable for any reason (no stored value, session
    /// gone, it2 failed): the safe default, since it just restores the pre-background-awareness
    /// behavior.
    func storedBackgroundTaskCount() throws -> Int {
        guard let output = try quietOutput(["session", "get-background-tasks"] + address.args),
              let count = Int(output) else {
            return 0
        }
        return max(0, count)
    }

    /// The status iTerm2 holds for the session, or nil when it could not be read.
    func storedStatus() throws -> CurrentAgentStatus? {
        guard let output = try quietOutput(["session", "get-status"] + address.args) else {
            return nil
        }
        return CurrentAgentStatus(json: output)
    }

    /// Adds to the stored background-task count and returns the status as it stands afterwards, or
    /// nil if the call failed or its answer could not be read. One it2 round trip, and atomic:
    /// iTerm2 applies the delta where the count lives, so two hooks changing it at once cannot
    /// lose one.
    func changeBackgroundTaskCount(by delta: Int) throws -> CurrentAgentStatus? {
        guard let output = try quietOutput(["set-status"] + address.args
                                           + shortcutOptionArgs("--background-tasks-delta", String(delta))
                                           + ["--json"]) else {
            return nil
        }
        return CurrentAgentStatus(json: output)
    }

    /// Trimmed stdout of an it2 subcommand, or nil if it failed. Always quiet: these reads happen
    /// mid-turn and a failure is not worth a word; each caller has a safe default instead.
    private func quietOutput(_ arguments: [String]) throws -> String? {
        guard let result = try backend.run(arguments + ["--quiet-if-unresolved"]), result.status == 0 else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run it2 and wait. Returns its trimmed stdout, or nil when it failed. Failures are reported on
    /// stderr but never fail the hook: a status update is cosmetic, and failing the hook over one
    /// would disrupt the session it is describing.
    ///
    /// What reaches here depends on the event, because quietArgs does. Per-tool-call events pass
    /// --quiet-if-unresolved, so an unresolved pane writes nothing and exits 0 there, and only the
    /// unexpected surfaces: a connection error, a usage error, the API being off. The two session
    /// boundaries do not pass it, so an unresolved pane is reported there too -- deliberately, so a
    /// persistent problem is discoverable once at each end of the session rather than never.
    private func run(_ arguments: [String]) throws -> String? {
        guard let result = try backend.run(arguments) else {
            report("handle-agent-hook: could not run it2")
            return nil
        }
        guard result.status != 0 else {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Report at session boundaries only. The failures a user actually hits here are
        // persistent, not one-off: the API preference turned off, the socket gone, or version
        // skew after an in-place update. Reporting per event would put the same lines in the
        // transcript several times per tool call for the rest of the session, which is the
        // disruption this program exists to avoid. Reporting at the boundary keeps a real problem
        // discoverable, since these conditions are already true at SessionStart, without
        // repeating it.
        guard isSessionBoundary else {
            return nil
        }
        for line in result.stderr.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                report(text)
            }
        }
        report("handle-agent-hook: it2 exited \(result.status) for \(eventName)")
        return nil
    }
}

// MARK: - Production backend

/// Runs the hook's it2 invocations through this process's own command tree, so the whole event is
/// one process locally and one round trip over ssh. Output is captured rather than passed through:
/// without --json it is chatter ("Session status updated.") that nothing consumes, and with --json
/// it is the status the call was asked for.
final class It2AgentStatusBackend: AgentStatusBackend {
    private let parent: IT2Context
    private let clients: SharedAPIClientFactory

    init(parent: IT2Context) {
        self.parent = parent
        self.clients = SharedAPIClientFactory(base: parent.makeClient)
    }

    func run(_ argv: [String]) throws -> AgentHookCommandResult? {
        var out: [String] = []
        var err: [String] = []
        let child = IT2Context(
            out: { out.append($0) },
            err: { err.append($0) },
            confirm: parent.confirm,
            makeClient: { [clients] in try clients.make() },
            installsSignalHandlers: false,
            isRemote: parent.isRemote,
            originIdentifier: parent.originIdentifier,
            // Inherited, or the hook's own sub-invocations would lose the default target and
            // fall back to whatever the user is looking at.
            originSessionID: parent.originSessionID,
            stdin: { Data() },
            environment: parent.environment
        )
        let status = runToExitCode(argv, child)
        return AgentHookCommandResult(status: status,
                                      stdout: out.joined(separator: "\n"),
                                      stderr: err.map { $0 + "\n" }.joined())
    }

    /// Close the connection the invocations shared. Idempotent.
    func finish() {
        clients.disconnect()
    }
}

/// Hands out API clients that share one connection, so several commands run back to back cost one
/// connect, and so that a command's own `disconnect()` (every command calls it when it is done)
/// does not tear down the connection the next command needs. Embedded in iTerm2 that connection
/// is the one channel the remote invocation has, and disconnecting it would end the invocation.
final class SharedAPIClientFactory {
    private let base: () throws -> APIClient
    private var shared: APIClient?

    init(base: @escaping () throws -> APIClient) {
        self.base = base
    }

    func make() throws -> APIClient {
        if shared == nil {
            shared = try base()
        }
        let client = APIClient(channel: NonDisconnectingChannel(shared!.channel))
        // Each sub-command gets a FRESH client over the shared channel, so anything that is not
        // carried here is silently lost. originSessionID is how a remote call with no explicit
        // target finds the session it arrived on; without it the hook's own sub-invocations
        // would fall back to the focused session, which is the misdelivery this prevents.
        client.originSessionID = shared!.originSessionID
        client.callerEnvironment = shared!.callerEnvironment
        client.originIdentifier = shared!.originIdentifier
        return client
    }

    func disconnect() {
        shared?.disconnect()
        shared = nil
    }
}

/// An APIChannel whose `disconnect()` does nothing, for clients that borrow a shared connection.
private final class NonDisconnectingChannel: APIChannel {
    private let inner: APIChannel

    init(_ inner: APIChannel) {
        self.inner = inner
    }

    func send(_ request: ITMClientOriginatedMessage) throws {
        try inner.send(request)
    }

    func receiveMessage() throws -> ITMServerOriginatedMessage {
        return try inner.receiveMessage()
    }

    func disconnect() {
    }
}

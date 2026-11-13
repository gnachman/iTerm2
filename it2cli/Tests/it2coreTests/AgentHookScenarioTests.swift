import XCTest
@testable import it2core

// End-to-end scenarios for `it2 handle-agent-hook`, ported from cc-status/tests/run.py.
//
// Recorded hook payloads (Resources/agent-hooks/<agent>/*.json, from Claude Code 2.1.201 and
// Codex CLI 0.154, paths scrubbed) are fed through the handler against a fake backend that logs
// every it2 invocation the handler would make and keeps the state the real one keeps: the
// displayed status, the background-task count and the turn flag. The expected invocations are
// the argv the handler hands to the it2 command tree, so a change in what the hook says to iTerm2
// shows up here as a changed argv.
//
// The progress ring is an argument of the status update (--progress) rather than an escape
// sequence written to the agent's tty, so it appears in the expected argv for Codex, whose ring
// the hook draws, and never for Claude Code, which draws its own.

/// What the fake it2 keeps between calls, and the knobs that stand in for races.
final class FakeAgentStatusBackend: AgentStatusBackend {
    struct Killed: Error {}

    private(set) var calls: [[String]] = []
    var status: String? = nil
    var backgroundTasks = 0
    var turnOpen: Bool? = nil
    /// Stands in for a sub-agent finishing while a status write is in flight: the count the
    /// handler read a moment ago is now stale.
    var finishOnStatusWrite = false
    /// Stands in for a prompt submitted between a --json answer and the caller's next write: its
    /// hook reopened the turn and wrote "working", which that write must not cover.
    var promptAfterJSON = false
    /// The same, for a prompt submitted between the first status answer (a read, or a --json
    /// write) and the write decided from it. Fires once.
    var promptAfterStatusRead = false
    /// Stands in for the session's own Stop landing between the first status answer and the
    /// write decided from it: the turn closed and background now shows. Fires once.
    var stopAfterStatusRead = false

    /// Applies whichever of the one-shot races above is armed, right after an answer was taken.
    private func raceAfterStatusAnswer() {
        if promptAfterStatusRead {
            promptAfterStatusRead = false
            status = "working"
            turnOpen = true
        }
        if stopAfterStatusRead {
            stopAfterStatusRead = false
            status = "background"
            turnOpen = false
        }
    }
    /// Stands in for the hook being killed on its timeout: once this many calls have been logged,
    /// the handler dies where it stands.
    var killAfter: Int? = nil

    func resetCalls() {
        calls = []
    }

    func run(_ argv: [String]) throws -> AgentHookCommandResult? {
        calls.append(argv)
        if let killAfter, calls.count >= killAfter {
            throw Killed()
        }
        switch (argv.first, argv.dropFirst().first) {
        case ("set-status", _):
            return setStatus(Array(argv.dropFirst()))
        case ("session", "get-background-tasks"):
            return AgentHookCommandResult(status: 0, stdout: "\(backgroundTasks)", stderr: "")
        case ("session", "get-status"):
            let answer = statusJSON()
            raceAfterStatusAnswer()
            return AgentHookCommandResult(status: 0, stdout: answer, stderr: "")
        default:
            return AgentHookCommandResult(status: 1, stdout: "", stderr: "fake it2: unexpected command: \(argv)")
        }
    }

    private func statusJSON() -> String {
        let status = self.status.map { "\"\($0)\"" } ?? "null"
        let turn = turnOpen.map { String($0) } ?? "null"
        return "{\"status\":\(status),\"detail\":null,\"background_tasks\":\(backgroundTasks),\"turn_open\":\(turn)}"
    }

    private func setStatus(_ args: [String]) -> AgentHookCommandResult {
        var newStatus: String? = nil
        var statusGiven = false
        var newCount: Int? = nil
        var delta: Int? = nil
        var newTurn: Bool? = nil
        var ifTurn: Bool? = nil
        var ifCount: Int? = nil
        var wantJSON = false
        var i = 0
        while i < args.count {
            let arg = args[i]
            func value(_ name: String) -> String? {
                if arg.hasPrefix(name + "=") {
                    return String(arg.dropFirst(name.count + 1))
                }
                if arg == name, i + 1 < args.count {
                    i += 1
                    return args[i]
                }
                return nil
            }
            if let v = value("--status") {
                statusGiven = true
                newStatus = v
            } else if let v = value("--background-tasks") {
                newCount = Int(v)
            } else if let v = value("--background-tasks-delta") {
                delta = Int(v)
            } else if let v = value("--turn-open") {
                newTurn = (v == "true")
            } else if let v = value("--if-turn-open") {
                ifTurn = (v == "true")
            } else if let v = value("--if-background-tasks") {
                ifCount = Int(v)
            } else if arg == "--json" {
                wantJSON = true
            }
            i += 1
        }
        // Preconditions are checked against the state as it stands and a failed one drops the
        // whole update. The real one does this atomically.
        var apply = true
        if let ifTurn, turnOpen != ifTurn {
            apply = false
        }
        if let ifCount, backgroundTasks != ifCount {
            apply = false
        }
        if apply {
            if statusGiven {
                status = newStatus
                if finishOnStatusWrite {
                    backgroundTasks = 0
                }
            }
            if let newCount {
                backgroundTasks = newCount
            }
            if let delta {
                backgroundTasks = max(0, backgroundTasks + delta)
            }
            if let newTurn {
                turnOpen = newTurn
            }
        }
        if wantJSON {
            let answer = statusJSON()
            if promptAfterJSON {
                status = "working"
                turnOpen = true
            }
            raceAfterStatusAnswer()
            return AgentHookCommandResult(status: 0, stdout: answer, stderr: "")
        }
        return AgentHookCommandResult(status: 0, stdout: "Session status updated.", stderr: "")
    }
}

final class AgentHookScenarioTests: XCTestCase {
    private static let session = "TEST-SESSION"
    private static let environment = [
        "TERM_SESSION_ID": "w0t0p0:" + session,
        // The handler reports nothing unless iTerm2 looks reachable; any IT2_SOCK satisfies that
        // gate, and the fake never dials it.
        "IT2_SOCK": "/tmp/unused.sock",
    ]

    // MARK: - Vocabulary, mirroring run.py

    private static let WORKING = ["--status=working", "--dot-color=#ff9500", "--text-color=#ff9500"]
    private static let WAITING = ["--status=waiting", "--dot-color=#5f87ff", "--text-color=#5f87ff"]
    private static let IDLE = ["--status=idle", "--dot-color=#00d75f", "--text-color=#888888"]
    private static let DONE = ["--status=done", "--dot-color=#00d75f", "--text-color=#00d75f"]
    private static let ERROR = ["--status=error", "--dot-color=#ff3b30", "--text-color=#ff3b30"]
    private static let BACKGROUND = ["--status=background", "--dot-color=#af5fff", "--text-color=#af5fff"]
    // Codex draws no ring of its own, so the hook asks iTerm2 for it in the same update.
    private static let cWORKING = WORKING + ["--progress=running"]
    private static let cWAITING = WAITING + ["--progress=stopped"]
    private static let cIDLE = IDLE + ["--progress=stopped"]
    private static let cDONE = DONE + ["--progress=stopped"]
    private static let cERROR = ERROR + ["--progress=stopped"]
    // Work the session started is still running, so the ring keeps going.
    private static let cBACKGROUND = BACKGROUND + ["--progress=running"]
    // What a Claude Code status scoped to the turn asks iTerm2 to do when the session's progress
    // protocol reports the turn ended. Never sent for Codex.
    private static let EXPIRES = ["--expires-on=progress-end", "--then-status=idle", "--then-dot-color=#00d75f",
                                  "--then-text-color=#888888", "--then-detail", ""]
    private static let ADDRESS = ["--session=" + session]
    private static let QUIET = ["--quiet-if-unresolved"]
    private static let TURN_OPEN = ["--turn-open=true"]
    private static let TURN_CLOSED = ["--turn-open=false"]
    private static let TURN_CLOSED_COUNTING = TURN_CLOSED + ["--json"]
    // A turn ending decided from a status read a round trip earlier: it carries what it assumed,
    // so iTerm2 drops it if a prompt reopened the turn in between.
    private static let IF_FINISHED = ["--if-turn-open=false", "--if-background-tasks=0", "--json"]

    private static func setStatus(_ args: [String]..., boundary: Bool = false) -> [String] {
        return ["set-status"] + ADDRESS + (boundary ? [] : QUIET) + args.flatMap { $0 }
    }

    private static func detail(_ text: String) -> [String] {
        return text.isEmpty ? ["--detail", ""] : ["--detail=" + text]
    }

    private static func getBackgroundTasks() -> [String] {
        return ["session", "get-background-tasks"] + ADDRESS + QUIET
    }

    private static func getStatus() -> [String] {
        return ["session", "get-status"] + ADDRESS + QUIET
    }

    // A write decided from a read that found the turn closed: dropped if a prompt reopened it.
    private static let IF_TURN_CLOSED = ["--if-turn-open=false", "--json"]
    // A Codex tool call's write: working only while the turn is open, and the status comes back.
    private static let IF_TURN_OPEN = ["--if-turn-open=true", "--json"]

    private static func storeBackgroundTasks(_ value: String) -> [String] {
        return ["set-status"] + ADDRESS + ["--background-tasks=" + value, "--json"] + QUIET
    }

    private static func backgroundTasksDelta(_ value: String) -> [String] {
        return ["set-status"] + ADDRESS + ["--background-tasks-delta=" + value, "--json"] + QUIET
    }

    private struct Flags: OptionSet {
        let rawValue: Int
        static let finishOnStatusWrite = Flags(rawValue: 1)
        static let promptAfterJSON = Flags(rawValue: 2)
        static let killAfterOne = Flags(rawValue: 4)
        static let promptAfterStatusRead = Flags(rawValue: 8)
        static let stopAfterStatusRead = Flags(rawValue: 16)
    }

    private enum Step {
        case hook(String, [[String]], Flags = [])
        case forgetStatus
        /// What iTerm2 does when the user types in a session showing a finished or failed turn:
        /// it becomes idle.
        case userTyped
        case expectStatus(String?)
        case expectBackgroundTasks(Int)
        case expectTurnOpen(Bool?)
    }

    private func payload(_ fixture: String) throws -> Data {
        let parts = fixture.split(separator: "/").map(String.init)
        let url = try XCTUnwrap(Bundle.module.url(forResource: parts[1],
                                                  withExtension: "json",
                                                  subdirectory: "agent-hooks/\(parts[0])"),
                                "missing fixture \(fixture)")
        return try Data(contentsOf: url)
    }

    private func run(_ name: String, _ steps: [Step], file: StaticString = #filePath, line: UInt = #line) throws {
        let backend = FakeAgentStatusBackend()
        for step in steps {
            switch step {
            case .forgetStatus:
                backend.status = nil
            case .userTyped:
                if backend.status == "done" || backend.status == "error" {
                    backend.status = "idle"
                }
            case .expectStatus(let expected):
                XCTAssertEqual(backend.status, expected, "\(name): displayed status", file: file, line: line)
            case .expectTurnOpen(let expected):
                XCTAssertEqual(backend.turnOpen, expected, "\(name): turn flag", file: file, line: line)
            case .expectBackgroundTasks(let expected):
                XCTAssertEqual(backend.backgroundTasks, expected, "\(name): stored count", file: file, line: line)
            case .hook(let fixture, let expected, let flags):
                backend.resetCalls()
                backend.finishOnStatusWrite = flags.contains(.finishOnStatusWrite)
                backend.promptAfterJSON = flags.contains(.promptAfterJSON)
                backend.promptAfterStatusRead = flags.contains(.promptAfterStatusRead)
                backend.stopAfterStatusRead = flags.contains(.stopAfterStatusRead)
                backend.killAfter = flags.contains(.killAfterOne) ? 1 : nil
                let agent: AgentKind = fixture.hasPrefix("codex/") ? .codex : .claude
                var stderr: [String] = []
                var killed = false
                do {
                    try AgentHookHandler.handle(payload: try payload(fixture),
                                                agent: agent,
                                                environment: Self.environment,
                                                backend: backend,
                                                report: { stderr.append($0) })
                } catch is FakeAgentStatusBackend.Killed {
                    killed = true
                }
                XCTAssertEqual(killed, flags.contains(.killAfterOne), "\(name): \(fixture) killed", file: file, line: line)
                XCTAssertEqual(backend.calls, expected, "\(name): \(fixture) it2 calls", file: file, line: line)
                if !killed {
                    XCTAssertEqual(stderr, [], "\(name): \(fixture) stderr", file: file, line: line)
                }
            }
        }
    }

    // MARK: - Codex

    func testCodexPlainTurn() throws {
        try run("codex: plain turn", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/PreToolUse-Bash", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN)]),
            .hook("codex/PostToolUse-Bash", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN)]),
            .hook("codex/Stop-hello", [Self.getBackgroundTasks(),
                                       Self.setStatus(Self.cDONE, Self.detail("HELLO"), Self.TURN_CLOSED)]),
        ])
    }

    func testCodexDetachedSubagentOutlivesTheParentTurn() throws {
        try run("codex: detached sub-agent outlives the parent turn", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/PreToolUse-spawn_agent", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            // Parent goes idle while the child runs: stay working, and learn from the same write
            // whether the child finished during it.
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                        Self.TURN_CLOSED_COUNTING)]),
            // Child finishes; nothing else will fire, so SubagentStop reports idle.
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1"),
                                         Self.setStatus(Self.cDONE, Self.detail("DONE"), Self.IF_FINISHED)]),
        ])
    }

    func testCodexSubagentFinishesWhileTheParentsStopIsBeingWritten() throws {
        try run("codex: sub-agent finishes while the parent's Stop is being written", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            // Stop read the count as 1, but by the time its status lands the child has finished.
            // The child saw the turn still open and stayed quiet, so nothing else will ever clear
            // the "working"; the count that comes back with the write catches it.
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                        Self.TURN_CLOSED_COUNTING),
                                         Self.setStatus(Self.cDONE, Self.detail("SPAWNED"), Self.IF_FINISHED)],
                  [.finishOnStatusWrite]),
        ])
    }

    func testCodexPromptLandsBeforeTheParentsDoneFollowUp() throws {
        try run("codex: a prompt lands before the parent's done follow-up", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            // As above, the child finished during the Stop's write, so a second write says idle.
            // But a new prompt was submitted before it landed and its hook wrote "working" with
            // the turn open. The idle was decided on a reading that is now stale, so it carries
            // that reading and iTerm2 drops it: the dot keeps showing the running turn, and the
            // ring, which travels in the same update, is left alone too.
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                        Self.TURN_CLOSED_COUNTING),
                                         Self.setStatus(Self.cDONE, Self.detail("SPAWNED"), Self.IF_FINISHED)],
                  [.finishOnStatusWrite, .promptAfterJSON]),
            .expectStatus("working"),
        ])
    }

    func testCodexPromptLandsBeforeASubagentsDone() throws {
        try run("codex: a prompt lands before a sub-agent's done", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                        Self.TURN_CLOSED_COUNTING)]),
            // The decrement's answer said the turn was closed and nothing was left, but a prompt
            // reopened it before the idle could land.
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1"),
                                         Self.setStatus(Self.cDONE, Self.detail("DONE"), Self.IF_FINISHED)],
                  [.promptAfterJSON]),
            .expectStatus("working"),
            .hook("codex/Stop-hello", [Self.getBackgroundTasks(),
                                       Self.setStatus(Self.cDONE, Self.detail("HELLO"), Self.TURN_CLOSED)]),
        ])
    }

    func testCodexWaitedSubagentFinishesInsideTheParentTurn() throws {
        try run("codex: waited sub-agent finishes inside the parent turn", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            // Turn still open: the decrement stored the zero and the display is the parent Stop's
            // business, so there is nothing left to send.
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1")]),
            .hook("codex/Stop-hello", [Self.getBackgroundTasks(),
                                       Self.setStatus(Self.cDONE, Self.detail("HELLO"), Self.TURN_CLOSED)]),
        ])
    }

    func testCodexEscCancelsTheTurn() throws {
        try run("codex: Esc cancels the turn", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/PreToolUse-Bash", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN)]),
            .hook("codex/Interrupt", [Self.getBackgroundTasks(),
                                      Self.setStatus(Self.cIDLE, Self.detail(""), Self.TURN_CLOSED)]),
        ])
    }

    func testCodexAFailedTurnsWorkFinishesDuringItsWriteAndItStillReadsError() throws {
        try run("codex: a failed turn's work finishes during its write and it still reads error", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/StopFailure", [Self.getBackgroundTasks(),
                                        Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                       Self.TURN_CLOSED_COUNTING),
                                        Self.setStatus(Self.cERROR, Self.detail(""), Self.IF_FINISHED)],
                  [.finishOnStatusWrite]),
        ])
    }

    func testCodexACancelledTurnsWorkFinishesDuringItsWriteAndItStillReadsIdle() throws {
        try run("codex: a cancelled turn's work finishes during its write and it still reads idle", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/Interrupt", [Self.getBackgroundTasks(),
                                      Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                     Self.TURN_CLOSED_COUNTING),
                                      Self.setStatus(Self.cIDLE, Self.detail(""), Self.IF_FINISHED)],
                  [.finishOnStatusWrite]),
        ])
    }

    func testCodexEscWhileADetachedSubagentRuns() throws {
        try run("codex: Esc while a detached sub-agent runs", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/Interrupt", [Self.getBackgroundTasks(),
                                      Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                     Self.TURN_CLOSED_COUNTING)]),
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1"),
                                         Self.setStatus(Self.cDONE, Self.detail("DONE"), Self.IF_FINISHED)]),
        ])
    }

    func testCodexDetachedSubagentIsRefusedPermissionAndStops() throws {
        try run("codex: detached sub-agent is refused permission and stops", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                        Self.TURN_CLOSED_COUNTING)]),
            // The child asks permission after the parent stopped; refusing it brings no
            // PostToolUse, so the "waiting" it left is the child's to clear when it stops.
            .hook("codex/PermissionRequest-apply_patch",
                  [Self.setStatus(Self.cWAITING, Self.detail("Allow Edit: Sources/cc-status/main.swift, tests/run.py?"))]),
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1"),
                                         Self.setStatus(Self.cDONE, Self.detail("DONE"), Self.IF_FINISHED)]),
        ])
    }

    func testCodexFailedTurnClearsTurnState() throws {
        try run("codex: failed turn clears turn state", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/StopFailure", [Self.getBackgroundTasks(),
                                        Self.setStatus(Self.cERROR, Self.detail(""), Self.TURN_CLOSED)]),
        ])
    }

    func testCodexSessionBoundaries() throws {
        try run("codex: session boundaries", [
            .hook("codex/SessionStart", [Self.setStatus(Self.cIDLE, Self.detail(""), ["--background-tasks=0"],
                                                        Self.TURN_CLOSED, boundary: true)]),
            .hook("codex/SessionEnd", [Self.setStatus(Self.cIDLE, Self.detail(""), ["--background-tasks=0"],
                                                      Self.TURN_CLOSED, boundary: true)]),
        ])
    }

    func testCodexApplyPatchPermissionNamesTheFiles() throws {
        try run("codex: apply_patch permission names the files", [
            .hook("codex/PermissionRequest-apply_patch",
                  [Self.setStatus(Self.cWAITING, Self.detail("Allow Edit: Sources/cc-status/main.swift, tests/run.py?"))]),
        ])
    }

    func testCodexSubagentStopsWithNoTurnOnRecord() throws {
        try run("codex: sub-agent stops with no turn on record", [
            // No UserPromptSubmit ever ran (hooks installed mid-session, or the session was
            // resumed), so the turn flag is unset. Unset is unknown, not closed: reporting idle
            // here would cut off a turn that is still going.
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1")]),
        ])
    }

    func testCodexUtilitySubagentRunsWhileTheSessionIsIdle() throws {
        try run("codex: utility sub-agent runs while the session is idle", [
            .hook("codex/SessionStart", [Self.setStatus(Self.cIDLE, Self.detail(""), ["--background-tasks=0"],
                                                        Self.TURN_CLOSED, boundary: true)]),
            .hook("codex/Stop-hello", [Self.getBackgroundTasks(),
                                       Self.setStatus(Self.cDONE, Self.detail("HELLO"), Self.TURN_CLOSED)]),
            // Codex runs utility sub-agents at the prompt; the status must stay done and keep the
            // root turn's message rather than take the utility's.
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1")]),
        ])
    }

    func testCodexSubagentStopsAfterTheDisplayWasCleared() throws {
        try run("codex: sub-agent stops after the display was cleared", [
            .hook("codex/SessionStart", [Self.setStatus(Self.cIDLE, Self.detail(""), ["--background-tasks=0"],
                                                        Self.TURN_CLOSED, boundary: true)]),
            .forgetStatus,
            // Nothing is displayed, so there is no stale "working" to correct; writing idle would
            // only show the utility agent's message.
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1")]),
        ])
    }

    func testCodexTwoSubagentsFinishTogetherAndTheSlowerWriteLandsLast() throws {
        try run("codex: two sub-agents finish together and the slower write lands last", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("2 background tasks running"),
                                                        Self.TURN_CLOSED_COUNTING)]),
            // This hook counted down to 1, but its sibling reached 0 and wrote idle before this
            // "working" landed. Nothing else will fire, so the status that comes back with the
            // write is what catches it.
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1"),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"), ["--if-turn-open=false", "--json"]),
                                         Self.setStatus(Self.cDONE, Self.detail("DONE"), Self.IF_FINISHED)],
                  [.finishOnStatusWrite]),
        ])
    }

    func testCodexEscKilledOnItsTimeoutStillLeavesTheTurnOpen() throws {
        try run("codex: Esc killed on its timeout still leaves the turn open", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            // Killed after the count read, before the status write. Nothing changed, so the flag
            // still says open: the worst case is a stale "working" that the next turn clears,
            // never a false idle.
            .hook("codex/Interrupt", [Self.getBackgroundTasks()], [.killAfterOne]),
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1")]),
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/Stop-hello", [Self.getBackgroundTasks(),
                                       Self.setStatus(Self.cDONE, Self.detail("HELLO"), Self.TURN_CLOSED)]),
        ])
    }

    func testCodexSubagentFinishesWhileTheTurnIsOpenAndAnotherRuns() throws {
        try run("codex: sub-agent finishes while the turn is open and another runs", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            // The parent is still in its turn, so it is working, not waiting on background work.
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1"),
                                         Self.setStatus(Self.cWORKING, Self.detail("1 background task running"),
                                                        Self.IF_TURN_OPEN)]),
            .expectStatus("working"),
        ])
    }

    func testCodexTheTurnEndsBeforeASubagentsWorkingUpdate() throws {
        try run("codex: the turn ends before a sub-agent's working update", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            // The decrement read the turn as open, but the parent's Stop landed before the
            // working write; its background is kept, and so is the decremented count.
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1"),
                                         Self.setStatus(Self.cWORKING, Self.detail("1 background task running"),
                                                        Self.IF_TURN_OPEN)],
                  [.stopAfterStatusRead]),
            .expectStatus("background"),
            .expectBackgroundTasks(1),
        ])
    }

    func testCodexPromptLandsBeforeABackgroundUpdate() throws {
        try run("codex: a prompt lands before a sub-agent's background update", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("2 background tasks running"),
                                                        Self.TURN_CLOSED_COUNTING)]),
            // The decrement said the turn was closed, but a prompt reopened it before the
            // background could land, and background must not cover its working.
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1"),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                        ["--if-turn-open=false", "--json"])],
                  [.promptAfterJSON]),
            .expectStatus("working"),
        ])
    }

    func testCodexCompactionMidTurnLeavesTheTurnOpen() throws {
        try run("codex: compaction mid-turn leaves the turn open", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/SessionStart-compact", []),
            // The turn is still open, so the sub-agent finishing leaves the display to the
            // parent's Stop rather than reporting done.
            .hook("codex/SubagentStop", [Self.backgroundTasksDelta("-1")]),
            .expectStatus("working"),
        ])
    }

    func testCodexADetachedSubagentsToolCallsDoNotReadAsWorking() throws {
        try run("codex: a detached sub-agent's tool calls do not read as working", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                        Self.TURN_CLOSED_COUNTING)]),
            // Codex cannot say whose tool call this is. The turn is closed, so working is
            // dropped and background stays, at the cost of the one write it always made.
            .hook("codex/PreToolUse-Bash", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN)]),
            .hook("codex/PostToolUse-Bash", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN)]),
            .expectStatus("background"),
        ])
    }

    func testCodexADetachedSubagentsGrantedPermissionGoesBackToBackground() throws {
        try run("codex: a detached sub-agent's granted permission goes back to background", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/SubagentStart", [Self.setStatus(["--background-tasks-delta=1"])]),
            .hook("codex/Stop-spawned", [Self.getBackgroundTasks(),
                                         Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                        Self.TURN_CLOSED_COUNTING)]),
            .hook("codex/PermissionRequest-apply_patch",
                  [Self.setStatus(Self.cWAITING, Self.detail("Allow Edit: Sources/cc-status/main.swift, tests/run.py?"))]),
            // Granted: the tool ran. Working is dropped, and the answer says to put background back.
            .hook("codex/PostToolUse-Bash", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN),
                                             Self.setStatus(Self.cBACKGROUND, Self.detail("1 background task running"),
                                                            ["--if-turn-open=false", "--json"])]),
            .expectStatus("background"),
        ])
    }

    func testCodexAToolCallWithNoTurnOnRecordReadsAsWorking() throws {
        try run("codex: a tool call with no turn on record reads as working", [
            // Hooks installed mid-session: the guarded write is dropped, so it says working
            // unguarded, as it always did.
            .hook("codex/PreToolUse-Bash", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN),
                                            Self.setStatus(Self.cWORKING, Self.detail(""))]),
            .expectStatus("working"),
        ])
    }

    func testCodexAUtilityToolCallAtAnIdlePromptChangesNothing() throws {
        try run("codex: a utility tool call at an idle prompt changes nothing", [
            .hook("codex/UserPromptSubmit", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.TURN_OPEN)]),
            .hook("codex/Stop-hello", [Self.getBackgroundTasks(),
                                       Self.setStatus(Self.cDONE, Self.detail("HELLO"), Self.TURN_CLOSED)]),
            .hook("codex/PreToolUse-Bash", [Self.setStatus(Self.cWORKING, Self.detail(""), Self.IF_TURN_OPEN)]),
            .expectStatus("done"),
        ])
    }

    func testCodexUnhandledSnakeCaseToolReadsAsWords() throws {
        try run("codex: an unhandled snake_case tool reads as words", [
            .hook("codex/PermissionRequest-read_file",
                  [Self.setStatus(Self.cWAITING, Self.detail("Allow Read File?"))]),
        ])
    }

    // MARK: - Claude Code

    func testClaudePlainTurnMakesNoExtraIt2Calls() throws {
        try run("claude: plain turn makes no extra it2 calls", [
            .hook("claude/UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/PreToolUse-Bash", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/PostToolUse-Bash", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/Stop-nobg", [Self.setStatus(Self.DONE, Self.detail("HELLO"), ["--background-tasks=0"], Self.TURN_CLOSED)]),
        ])
    }

    func testClaudeTheIdleNudgeLeavesAFinishedTurnAlone() throws {
        try run("claude: the idle nudge leaves a finished turn alone", [
            .hook("claude/Stop-nobg", [Self.setStatus(Self.DONE, Self.detail("HELLO"), ["--background-tasks=0"], Self.TURN_CLOSED)]),
            // The nudge has no message; re-sending done would wipe Stop's.
            .hook("claude/Notification-idle", [Self.getStatus()]),
            .expectStatus("done"),
        ])
    }

    func testClaudeTheIdleNudgeDoesNotUndoTheUserSeeingTheResult() throws {
        try run("claude: the idle nudge does not undo the user seeing the result", [
            .hook("claude/Stop-nobg", [Self.setStatus(Self.DONE, Self.detail("HELLO"), ["--background-tasks=0"], Self.TURN_CLOSED)]),
            .userTyped,
            .hook("claude/Notification-idle", [Self.getStatus()]),
            .expectStatus("idle"),
        ])
    }

    func testClaudeAFailedTurnReportsErrorAndTheNudgeKeepsIt() throws {
        try run("claude: a failed turn reports error and the nudge keeps it", [
            .hook("claude/UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/StopFailure", [Self.getBackgroundTasks(), Self.setStatus(Self.ERROR, Self.detail(""), Self.TURN_CLOSED)]),
            .hook("claude/Notification-idle", [Self.getStatus()]),
            .expectStatus("error"),
        ])
    }

    func testClaudeBackgroundWorkSurvivesTheIdleNudge() throws {
        try run("claude: background work survives the idle nudge", [
            .hook("claude/Stop-bg1", [Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                     ["--background-tasks=1"], Self.TURN_CLOSED)]),
            .expectStatus("background"),
            .hook("claude/Notification-idle", [Self.getStatus(),
                                               Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                              Self.TURN_CLOSED, Self.IF_TURN_CLOSED)]),
            // The stopping agent is still listed as running; excluded by agent_id.
            .hook("claude/SubagentStop-last", [Self.setStatus(["--background-tasks=0"])]),
            // The last of the background work finished after Stop, so its result is what the user
            // has not seen yet.
            .hook("claude/Notification-idle", [Self.getStatus(), Self.setStatus(Self.DONE, Self.detail(""), Self.TURN_CLOSED,
                                                                                 Self.IF_TURN_CLOSED)]),
        ])
    }

    func testClaudeABackgroundAgentsToolCallsDoNotReadAsWorking() throws {
        try run("claude: a background agent's tool calls do not read as working", [
            .hook("claude/UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/Stop-bg1", [Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                     ["--background-tasks=1"], Self.TURN_CLOSED)]),
            // Sub-agents run the session's hooks. Background already shows, so the read is all.
            .hook("claude/PreToolUse-subagent", [Self.getStatus()]),
            .hook("claude/PostToolUse-subagent", [Self.getStatus()]),
            .expectStatus("background"),
        ])
    }

    func testClaudeABackgroundAgentsPermissionPromptIsClearedByItsNextToolEvent() throws {
        try run("claude: a background agent's permission prompt is cleared by its next tool event", [
            .hook("claude/Stop-bg1", [Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                     ["--background-tasks=1"], Self.TURN_CLOSED)]),
            .hook("claude/PermissionRequest-Bash", [Self.setStatus(Self.WAITING, Self.detail("Allow Bash: rm -rf build?"), Self.EXPIRES)]),
            .expectStatus("waiting"),
            // Granted: the tool ran, and the session goes back to background, not to working.
            .hook("claude/PostToolUse-subagent", [Self.getStatus(),
                                                  Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                                 ["--if-turn-open=false", "--json"])]),
            .expectStatus("background"),
        ])
    }

    func testClaudeASubagentToolCallAtAnIdlePromptChangesNothing() throws {
        try run("claude: a sub-agent tool call at an idle prompt changes nothing", [
            .hook("claude/Stop-nobg", [Self.setStatus(Self.DONE, Self.detail("HELLO"), ["--background-tasks=0"], Self.TURN_CLOSED)]),
            // A utility agent with nothing counted: the turn's result stays on display.
            .hook("claude/PreToolUse-subagent", [Self.getStatus()]),
            .expectStatus("done"),
        ])
    }

    func testClaudeASubagentToolCallWithNoTurnOnRecordReadsAsWorking() throws {
        try run("claude: a sub-agent tool call with no turn on record reads as working", [
            // Hooks installed mid-session: the flag is unknown, so it says what it always said.
            .hook("claude/PreToolUse-subagent", [Self.getStatus(),
                                                 Self.setStatus(Self.WORKING, Self.detail(""), Self.EXPIRES)]),
            .expectStatus("working"),
        ])
    }

    func testClaudeASubagentToolCallMidTurnReadsAsWorking() throws {
        try run("claude: a sub-agent tool call mid-turn reads as working", [
            .hook("claude/UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/PreToolUse-subagent", [Self.getStatus(),
                                                 Self.setStatus(Self.WORKING, Self.detail(""), ["--if-turn-open=true"],
                                                                Self.EXPIRES, ["--json"])]),
            .expectStatus("working"),
        ])
    }

    func testClaudeOneOfTwoBackgroundAgentsFinishesAfterTheTurn() throws {
        try run("claude: one of two background agents finishes after the turn", [
            .hook("claude/Stop-bg2", [Self.setStatus(Self.BACKGROUND, Self.detail("2 background tasks running"),
                                                     ["--background-tasks=2"], Self.TURN_CLOSED)]),
            // The other is still running and the session is still free to take input.
            .hook("claude/SubagentStop-first", [Self.storeBackgroundTasks("1"),
                                                Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                               ["--if-turn-open=false", "--json"])]),
            .expectStatus("background"),
            .hook("claude/SubagentStop-last", [Self.setStatus(["--background-tasks=0"])]),
            .expectStatus("background"),
            .hook("claude/Notification-idle", [Self.getStatus(), Self.setStatus(Self.DONE, Self.detail(""), Self.TURN_CLOSED,
                                                                                 Self.IF_TURN_CLOSED)]),
        ])
    }

    func testClaudeOneOfTwoAgentsFinishesMidTurn() throws {
        try run("claude: one of two agents finishes mid-turn", [
            .hook("claude/UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/SubagentStop-first", [Self.storeBackgroundTasks("1"),
                                                Self.setStatus(Self.WORKING, Self.detail("1 background task running"),
                                                               ["--if-turn-open=true"],
                                                               Self.EXPIRES, ["--json"])]),
            .expectStatus("working"),
        ])
    }

    func testClaudeAPromptLandsBeforeASubagentsBackgroundUpdate() throws {
        try run("claude: a prompt lands before a sub-agent's background update", [
            .hook("claude/Stop-bg2", [Self.setStatus(Self.BACKGROUND, Self.detail("2 background tasks running"),
                                                     ["--background-tasks=2"], Self.TURN_CLOSED)]),
            // Read as closed, but the prompt's working landed before the write; it is kept.
            .hook("claude/SubagentStop-first", [Self.storeBackgroundTasks("1"),
                                                Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                               ["--if-turn-open=false", "--json"])],
                  [.promptAfterStatusRead]),
            .expectStatus("working"),
            // The display write was dropped, but the count was stored on its own.
            .expectBackgroundTasks(1),
        ])
    }

    func testClaudeTheTurnEndsBeforeASubagentsWorkingUpdate() throws {
        try run("claude: the turn ends before a sub-agent's working update", [
            .hook("claude/UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            // Read as open, but the session's Stop landed before the write; its background is kept.
            .hook("claude/SubagentStop-first", [Self.storeBackgroundTasks("1"),
                                                Self.setStatus(Self.WORKING, Self.detail("1 background task running"),
                                                               ["--if-turn-open=true"],
                                                               Self.EXPIRES, ["--json"])],
                  [.stopAfterStatusRead]),
            .expectStatus("background"),
            .expectBackgroundTasks(1),
        ])
    }

    // Recorded from Claude Code 2.1.322: a turn launches one background agent and ends; the agent
    // runs two Bash commands and hands back; Claude Code starts a turn of its own to reply.
    func testClaudeRecordedBackgroundAgentRun() throws {
        let subagentToolEvent = [Self.getStatus()]
        try run("claude: recorded background agent run", [
            .hook("claude/bgrun-01-UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/bgrun-02-PreToolUse-Agent", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/bgrun-03-SubagentStart", []),
            .hook("claude/bgrun-04-PostToolUse-Agent", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/bgrun-05-Stop", [Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                          ["--background-tasks=1"], Self.TURN_CLOSED)]),
            .expectStatus("background"),
            // The agent's own tool calls, which carry its agent_id.
            .hook("claude/bgrun-06-PreToolUse-Bash", subagentToolEvent),
            .hook("claude/bgrun-07-PostToolUse-Bash", subagentToolEvent),
            .hook("claude/bgrun-08-PreToolUse-Bash", subagentToolEvent),
            .hook("claude/bgrun-09-PostToolUse-Bash", subagentToolEvent),
            .hook("claude/bgrun-10-PreToolUse-SubagentHandback", subagentToolEvent),
            .hook("claude/bgrun-11-PostToolUse-SubagentHandback", subagentToolEvent),
            .expectStatus("background"),
            // Claude Code wakes to read the result, and that turn starts with UserPromptSubmit,
            // before the agent's SubagentStop.
            .hook("claude/bgrun-12-UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/bgrun-13-SubagentStop", [Self.setStatus(["--background-tasks=0"])]),
            .expectStatus("working"),
            .hook("claude/bgrun-14-Stop", [Self.setStatus(Self.DONE, Self.detail("Done."), ["--background-tasks=0"], Self.TURN_CLOSED)]),
            .expectStatus("done"),
        ])
    }

    func testClaudeCompactionMidTurnLeavesTheTurnOpen() throws {
        try run("claude: compaction mid-turn leaves the turn open", [
            .hook("claude/UserPromptSubmit", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/bgrun-02-PreToolUse-Agent", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            // Auto-compaction is not a session boundary: no idle, no reset, turn still open.
            .hook("claude/SessionStart-compact", []),
            .expectStatus("working"),
            // A foreground agent finishes while the background one keeps running. The main
            // loop is still in its turn, so this is working, not background.
            .hook("claude/SubagentStop-first", [Self.storeBackgroundTasks("1"),
                                                Self.setStatus(Self.WORKING, Self.detail("1 background task running"),
                                                               ["--if-turn-open=true"],
                                                               Self.EXPIRES, ["--json"])]),
            .expectStatus("working"),
        ])
    }

    func testClaudeASessionToolCallReopensAWronglyClosedTurn() throws {
        try run("claude: the session's own tool call reopens a wrongly closed turn", [
            .hook("claude/Stop-bg1", [Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                     ["--background-tasks=1"], Self.TURN_CLOSED)]),
            // Whatever closed the flag, a tool call of the session's own means a turn is running.
            .hook("claude/PreToolUse-Bash", [Self.setStatus(Self.WORKING, Self.detail(""), Self.TURN_OPEN, Self.EXPIRES)]),
            .hook("claude/PreToolUse-subagent", [Self.getStatus(),
                                                 Self.setStatus(Self.WORKING, Self.detail(""), ["--if-turn-open=true"],
                                                                Self.EXPIRES, ["--json"])]),
            .expectStatus("working"),
        ])
    }

    func testClaudeAPromptLandsBeforeTheIdleNudgesWrite() throws {
        try run("claude: a prompt lands before the idle nudge's write", [
            .hook("claude/Stop-bg1", [Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                     ["--background-tasks=1"], Self.TURN_CLOSED)]),
            // The nudge read a closed turn, but a prompt reopened it before its write landed.
            // The prompt's working, and its open turn, are kept.
            .hook("claude/Notification-idle", [Self.getStatus(),
                                               Self.setStatus(Self.BACKGROUND, Self.detail("1 background task running"),
                                                              Self.TURN_CLOSED, Self.IF_TURN_CLOSED)],
                  [.promptAfterStatusRead]),
            .expectStatus("working"),
            .expectTurnOpen(true),
        ])
    }

    func testClaudeAGrantedPermissionWithNothingCountedDoesNotLeaveWaitingUp() throws {
        try run("claude: a granted permission with nothing counted does not leave waiting up", [
            // A Claude Code that reports no background_tasks: the turn is closed and the count is 0.
            .hook("claude/Stop-legacy", [Self.setStatus(Self.DONE, Self.detail("HELLO"), Self.TURN_CLOSED)]),
            .hook("claude/PermissionRequest-Bash", [Self.setStatus(Self.WAITING, Self.detail("Allow Bash: rm -rf build?"), Self.EXPIRES)]),
            // A background agent asked, the user granted it, and its tool ran. Nothing is
            // counted, but an agent is plainly at work, and the prompt is no longer up.
            .hook("claude/PostToolUse-subagent", [Self.getStatus(),
                                                  Self.setStatus(Self.BACKGROUND, Self.detail(""),
                                                                 ["--if-turn-open=false", "--json"])]),
            .expectStatus("background"),
        ])
    }

    func testClaudePayloadsWithoutBackgroundTasks() throws {
        try run("claude: payloads without background_tasks (before 2.1.198)", [
            .hook("claude/Stop-legacy", [Self.setStatus(Self.DONE, Self.detail("HELLO"), Self.TURN_CLOSED)]),
            .hook("claude/SubagentStop-legacy", []),
        ])
    }

    func testClaudePermissionAndSessionBoundary() throws {
        try run("claude: permission and session boundary", [
            .hook("claude/PermissionRequest-Bash", [Self.setStatus(Self.WAITING, Self.detail("Allow Bash: rm -rf build?"), Self.EXPIRES)]),
            .hook("claude/SessionStart", [Self.setStatus(Self.IDLE, Self.detail(""), ["--background-tasks=0"], Self.TURN_CLOSED,
                                                          boundary: true)]),
        ])
    }

    // MARK: - Addressing and reachability

    // A pane address is passed through as the tmux pair, and TERM_SESSION_ID is ignored inside
    // tmux, where it names whichever session started the server.
    func testInsideTmuxTheAddressIsThePane() throws {
        let backend = FakeAgentStatusBackend()
        try AgentHookHandler.handle(payload: try payload("claude/UserPromptSubmit"),
                                    agent: .claude,
                                    environment: ["TERM_SESSION_ID": "w0t0p0:IGNORED",
                                                  "TMUX": "/private/tmp/tmux-501/default,52533,0",
                                                  "TMUX_PANE": "%3",
                                                  "IT2_SOCK": "/tmp/unused.sock"],
                                    backend: backend,
                                    report: { _ in })
        XCTAssertEqual(backend.calls, [["set-status", "--tmux=/private/tmp/tmux-501/default,52533,0", "--tmux-pane=%3"]
                                       + Self.QUIET + Self.WORKING + Self.detail("") + Self.TURN_OPEN + Self.EXPIRES])
    }

    // Inside tmux with an address that does not parse, nothing is reported: falling back to
    // TERM_SESSION_ID would paint an unrelated tab.
    func testMalformedTmuxAddressReportsNothing() throws {
        let backend = FakeAgentStatusBackend()
        try AgentHookHandler.handle(payload: try payload("claude/UserPromptSubmit"),
                                    agent: .claude,
                                    environment: ["TERM_SESSION_ID": "w0t0p0:ABC", "TMUX": "garbage", "IT2_SOCK": "/x"],
                                    backend: backend,
                                    report: { _ in })
        XCTAssertEqual(backend.calls, [])
    }

    // Inside Zellij nothing is reported, as in plain tmux: every pane inherits the TERM_SESSION_ID
    // of the session Zellij started in, so agents in different Zellij tabs would overwrite one
    // status (issue 13201). Not even a remote call's origin or a tmux pane inside Zellij is used.
    func testInsideZellijNothingIsReported() throws {
        let environments: [[String: String]] = [
            ["TERM_SESSION_ID": "w0t0p0:ABC", "ZELLIJ": "0", "IT2_SOCK": "/x"],
            ["TMUX": "/private/tmp/tmux-501/default,52533,0", "TMUX_PANE": "%3", "ZELLIJ": "0", "IT2_SOCK": "/x"],
        ]
        for environment in environments {
            let backend = FakeAgentStatusBackend()
            try AgentHookHandler.handle(payload: try payload("claude/UserPromptSubmit"),
                                        agent: .claude,
                                        environment: environment,
                                        backend: backend,
                                        report: { _ in })
            XCTAssertEqual(backend.calls, [], "\(environment)")
        }
        let backend = FakeAgentStatusBackend()
        try AgentHookHandler.handle(payload: try payload("claude/UserPromptSubmit"),
                                    agent: .claude,
                                    environment: ["ZELLIJ": "0"],
                                    originSessionID: "ORIGIN-GUID",
                                    inProcess: true,
                                    backend: backend,
                                    report: { _ in })
        XCTAssertEqual(backend.calls, [])
    }

    func testNothingToAddressReportsNothing() throws {
        let backend = FakeAgentStatusBackend()
        try AgentHookHandler.handle(payload: try payload("claude/UserPromptSubmit"),
                                    agent: .claude,
                                    environment: ["IT2_SOCK": "/x"],
                                    backend: backend,
                                    report: { _ in })
        XCTAssertEqual(backend.calls, [])
    }

    // A hook on a host reached through SSH Integration, in a plain shell: no tmux, and no
    // TERM_SESSION_ID, which does not cross ssh. It runs inside iTerm2, which knows the session the
    // call arrived on, so that is the address, and iTerm2 is reachable by definition even though
    // IT2_SOCK is not among the variables sent over. Before this the hook reported nothing.
    func testARemoteHookAddressesTheSessionItArrivedOn() throws {
        let backend = FakeAgentStatusBackend()
        try AgentHookHandler.handle(payload: try payload("claude/UserPromptSubmit"),
                                    agent: .claude,
                                    environment: ["IT2_PY": "/home/u/.iterm2/it2.abc.py"],
                                    originSessionID: "ORIGIN-GUID",
                                    backend: backend,
                                    report: { _ in })
        XCTAssertEqual(backend.calls, [["set-status", "--session=ORIGIN-GUID"]
                                       + Self.QUIET + Self.WORKING + Self.detail("") + Self.TURN_OPEN + Self.EXPIRES])
    }

    // In a remote tmux pane the pane address still wins: the origin is the session showing the
    // gateway's connection, not necessarily the pane's tab.
    func testARemoteTmuxPaneStillWinsOverTheOrigin() throws {
        let backend = FakeAgentStatusBackend()
        try AgentHookHandler.handle(payload: try payload("claude/UserPromptSubmit"),
                                    agent: .claude,
                                    environment: ["TMUX": "/tmp/tmux-1000/default,77,2", "TMUX_PANE": "%4"],
                                    originSessionID: "ORIGIN-GUID",
                                    backend: backend,
                                    report: { _ in })
        XCTAssertEqual(backend.calls, [["set-status", "--tmux=/tmp/tmux-1000/default,77,2", "--tmux-pane=%4"]
                                       + Self.QUIET + Self.WORKING + Self.detail("") + Self.TURN_OPEN + Self.EXPIRES])
    }

    // A remote hook in a tmux pane on a tmux integration connection: iTerm2 withholds the origin
    // (the gateway is never the pane's session), but the call still runs inside iTerm2, so it must
    // not depend on a local API socket existing.
    func testAnInProcessTmuxHookWithoutAnOriginIsStillReachable() {
        let address = resolveAgentHookAddress(environment: ["TMUX": "/tmp/tmux-1000/default,77,2",
                                                            "TMUX_PANE": "%4"],
                                              originSessionID: nil,
                                              inProcess: true,
                                              localSocketExists: { _ in false })
        XCTAssertEqual(address?.args, ["--tmux=/tmp/tmux-1000/default,77,2", "--tmux-pane=%4"])
        XCTAssertNil(resolveAgentHookAddress(environment: ["TMUX": "/tmp/tmux-1000/default,77,2",
                                                           "TMUX_PANE": "%4"],
                                             localSocketExists: { _ in false }),
                     "out of process with no socket, nothing could answer")
    }

    // A malformed pane address still reports nothing, origin or not: the pane path never falls
    // back to another address.
    func testARemoteMalformedTmuxAddressStillReportsNothing() throws {
        let backend = FakeAgentStatusBackend()
        try AgentHookHandler.handle(payload: try payload("claude/UserPromptSubmit"),
                                    agent: .claude,
                                    environment: ["TMUX": "garbage"],
                                    originSessionID: "ORIGIN-GUID",
                                    backend: backend,
                                    report: { _ in })
        XCTAssertEqual(backend.calls, [])
    }

    // A failed it2 call is reported on stderr only at the session boundaries, once, with it2's
    // own explanation attached; per-tool-call events stay silent.
    func testFailuresAreReportedOnlyAtSessionBoundaries() throws {
        final class FailingBackend: AgentStatusBackend {
            func run(_ argv: [String]) throws -> AgentHookCommandResult? {
                return AgentHookCommandResult(status: 2, stdout: "", stderr: "it2: cannot reach iTerm2\n")
            }
        }
        var reported: [String] = []
        try AgentHookHandler.handle(payload: try payload("claude/PreToolUse-Bash"),
                                    agent: .claude,
                                    environment: Self.environment,
                                    backend: FailingBackend(),
                                    report: { reported.append($0) })
        XCTAssertEqual(reported, [], "a per-tool-call event must not report")

        try AgentHookHandler.handle(payload: try payload("claude/SessionStart"),
                                    agent: .claude,
                                    environment: Self.environment,
                                    backend: FailingBackend(),
                                    report: { reported.append($0) })
        XCTAssertEqual(reported.count, 2, "got \(reported)")
        XCTAssertEqual(reported.first, "it2: cannot reach iTerm2")
        XCTAssertTrue(reported.last?.contains("exited 2 for SessionStart") == true, "got \(reported)")
    }
}

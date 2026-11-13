//
//  ClaudeCodeHookAndReportsTests.swift
//  ModernTests
//
//  Claude Code reports its own status through OSC 7501 (app=claude-code), and its hook reports
//  through `it2 set-status --agent claude`. With both present neither writes the tab status: the
//  report is the base and the hook's writes are kept only as facts (see ClaudeCodeStatusOverlay).
//  With only one present, that one drives, exactly as it would alone.
//
//  The hook writes below are the arguments `it2 handle-agent-hook` sends for each event, as pinned
//  by it2cli/Tests/it2coreTests/AgentHookScenarioTests.swift. The timings are from Claude Code
//  2.1.322 recorded on a test VM.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - What the hook sends

private enum Hook {
    private static let expires: [String: Any] = ["expires_on": "progress-end", "then_status": "idle",
                                                 "then_dot_color": "#00d75f", "then_text_color": "#888888",
                                                 "then_detail": ""]

    private static func marked(_ parameters: [String: Any]) -> [String: Any] {
        return parameters.merging(["agent": "claude"]) { $1 }
    }

    private static func working(detail: String = "") -> [String: Any] {
        return ["status": "working", "dot_color": "#ff9500", "text_color": "#ff9500", "detail": detail]
    }

    private static func background(_ count: Int) -> [String: Any] {
        return ["status": "background", "dot_color": "#af5fff", "text_color": "#af5fff",
                "detail": count == 1 ? "1 background task running" : "\(count) background tasks running"]
    }

    static let userPromptSubmit = marked(working().merging(expires) { $1 }.merging(["turn_open": NSNumber(value: true)]) { $1 })
    /// PreToolUse or PostToolUse of the session's own.
    static let toolUse = userPromptSubmit
    static let permissionRequest = marked(["status": "waiting", "dot_color": "#5f87ff", "text_color": "#5f87ff",
                                           "detail": "Allow Bash: touch /tmp/x?"].merging(expires) { $1 })

    /// Stop with work still running.
    static func stop(running count: Int) -> [String: Any] {
        return marked(background(count).merging(["background_tasks": NSNumber(value: count),
                                                 "turn_open": NSNumber(value: false)]) { $1 })
    }

    /// Stop with nothing running.
    static func stop(message: String) -> [String: Any] {
        return marked(["status": "done", "dot_color": "#00d75f", "text_color": "#00d75f", "detail": message,
                       "background_tasks": NSNumber(value: 0), "turn_open": NSNumber(value: false)])
    }

    /// The count a SubagentStop stores, in a write of its own.
    static func count(_ count: Int) -> [String: Any] {
        return marked(["background_tasks": NSNumber(value: count)])
    }

    /// The display write that follows the count when work remains and the turn read closed.
    static func backgroundIfTurnClosed(_ count: Int) -> [String: Any] {
        return marked(background(count).merging(["if_turn_open": NSNumber(value: false)]) { $1 })
    }

    static let sessionBoundary = marked(["status": "idle", "dot_color": "#00d75f", "text_color": "#888888", "detail": "",
                                         "background_tasks": NSNumber(value: 0), "turn_open": NSNumber(value: false)])
}

private func base64(_ string: String) -> String {
    return Data(string.utf8).base64EncodedString()
}

// MARK: - Tests

final class ClaudeCodeHookAndReportsTests: XCTestCase {
    private func report(_ body: String) -> ProgramStatusReport {
        return ProgramStatusReport.parse(body)!
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 5)
    }

    /// What `it2 set-status` asks for, as the function sees it. Returns the reply.
    @discardableResult
    private func setStatus(_ session: PTYSession,
                           _ parameters: [String: Any],
                           file: StaticString = #filePath,
                           line: UInt = #line) -> NSDictionary? {
        var reply: NSDictionary?
        SetStatusBuiltInFunction.apply(parameters, to: session) { result, error in
            XCTAssertNil(error, file: file, line: line)
            reply = result as? NSDictionary
        }
        return reply
    }

    private func reports(_ session: PTYSession, _ bodies: String...) {
        session.screenReportProgramStatusReports(bodies.map { report($0) })
    }

    /// A session in which Claude Code is reporting and has started a turn.
    private func claudeCodeSession() -> PTYSession {
        let session = PTYSession(synthetic: false)!
        reports(session, "state=working:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "working")
        return session
    }

    private func screenProgress(of session: PTYSession) -> VT100ScreenProgress {
        var progress = VT100ScreenProgress.stopped
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            progress = mutableState.progress
        })
        return progress
    }

    private func hex(_ color: iTermSRGBColor) -> String {
        func component(_ value: Double) -> Int {
            return Int((min(1, max(0, value)) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", component(color.r), component(color.g), component(color.b))
    }

    // MARK: Both present

    // Background agents: Claude Code keeps saying working for the whole wait. The hook knows the
    // turn ended.
    func testBackgroundAgentsShowBackgroundWhileClaudeCodeSaysWorking() {
        let session = claudeCodeSession()
        setStatus(session, Hook.userPromptSubmit)
        XCTAssertEqual(session.tabStatus?.statusText, "working")

        reports(session, "state=working:app=claude-code:id=a1:title=\(base64("Run the tests"))")
        setStatus(session, Hook.stop(running: 1))
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        XCTAssertEqual(session.tabStatus?.detailText, "1 background task running")
        XCTAssertEqual(session.tabStatus.map { hex($0.statusTextColor) }, "#af5fff")
        XCTAssertEqual(session.tabStatus.map { hex($0.indicatorColor) }, "#af5fff")

        // The agent finishes, and Claude Code starts a turn of its own to read the result.
        setStatus(session, Hook.count(0))
        reports(session, "state=clear:id=a1")
        setStatus(session, Hook.userPromptSubmit)
        XCTAssertEqual(session.tabStatus?.statusText, "working")

        setStatus(session, Hook.stop(message: "All tests pass."))
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertEqual(session.tabStatus?.detailText, "All tests pass.")
    }

    // Background shells: Claude Code says done as soon as the turn ends, and has no record for
    // the shell.
    func testBackgroundShellsShowBackgroundWhileClaudeCodeSaysDone() {
        let session = claudeCodeSession()
        setStatus(session, Hook.userPromptSubmit)
        setStatus(session, Hook.stop(running: 1))
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        XCTAssertEqual(session.tabStatus?.detailText, "1 background task running")
    }

    func testTheCountInBackgroundFollowsTheHook() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(running: 1))
        setStatus(session, Hook.count(2))
        setStatus(session, Hook.backgroundIfTurnClosed(2))
        XCTAssertEqual(session.tabStatus?.detailText, "2 background tasks running")
        setStatus(session, Hook.count(0))
        XCTAssertEqual(session.tabStatus?.statusText, "working")
    }

    // Claude Code reporting working again after the hook closed the turn means a new turn began,
    // whether or not the hook's own event for it arrives.
    func testClaudeCodeStartingATurnEndsBackgroundWithoutTheHook() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(running: 1))
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "background")

        reports(session, "state=working:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "working")
        XCTAssertNil(session.tabStatus?.turnOpen)
        // The count is the hook's and is left alone.
        XCTAssertEqual(session.tabStatus?.backgroundTasks, 1)
    }

    func testAPermissionPromptIsNeverCoveredByBackground() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(running: 1))
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        reports(session, "state=blocked:app=claude-code:kind=permission:msg=\(base64("approve Bash: touch /tmp/x"))")
        setStatus(session, Hook.permissionRequest)
        XCTAssertEqual(session.tabStatus?.statusText, "waiting")
        XCTAssertEqual(session.tabStatus?.detailText, "approve Bash: touch /tmp/x")

        // Approved: Claude Code goes back to working, but that is the wait resuming, not a new
        // turn. The session is still free to take input.
        reports(session, "state=working:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        XCTAssertEqual(session.tabStatus?.turnOpen, false)
    }

    // Pressing a key marks a finished result seen, which turns done idle. The message stays,
    // as it does when either source drives alone.
    func testSeeingADoneResultKeepsTheHooksMessage() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(message: "All tests pass."))
        reports(session, "state=done:app=claude-code")
        session.programStatusControllerIfPresent?.userDidPressKey()
        XCTAssertEqual(session.tabStatus?.statusText, "idle")
        XCTAssertEqual(session.tabStatus?.detailText, "All tests pass.")
    }

    // A hook write that changes no fact (every tool call sends one) is not a change to announce.
    func testAHookWriteThatChangesNoFactDoesNotRedrawAnything() {
        let session = claudeCodeSession()
        setStatus(session, Hook.userPromptSubmit)
        var changes = 0
        let observer = NotificationCenter.default.addObserver(
            forName: ProgramStatusController.recordsDidChangeNotificationName, object: nil, queue: nil) { _ in
                changes += 1
            }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        setStatus(session, Hook.toolUse)
        setStatus(session, Hook.toolUse)
        XCTAssertEqual(changes, 0)
        setStatus(session, Hook.stop(running: 1))
        XCTAssertGreaterThan(changes, 0)
    }

    // Esc fires no hook. Claude Code reports it.
    func testEscShowsIdle() {
        let session = claudeCodeSession()
        setStatus(session, Hook.userPromptSubmit)
        setStatus(session, Hook.toolUse)
        reports(session, "state=idle:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "idle")
    }

    func testTheHooksLastMessageIsForgottenWhenATurnOpens() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(message: "First answer."))
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.detailText, "First answer.")

        reports(session, "state=working:app=claude-code")
        setStatus(session, Hook.userPromptSubmit)
        // Claude Code's done arrives before the hook's Stop for this turn.
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertNil(session.tabStatus?.detailText)
        setStatus(session, Hook.stop(message: "Second answer."))
        XCTAssertEqual(session.tabStatus?.detailText, "Second answer.")
    }

    // /clear and a resumed session are session boundaries to the hook, which wipes its detail
    // there when it drives alone.
    func testASessionBoundaryForgetsTheLastMessage() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(message: "First answer."))
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.detailText, "First answer.")
        setStatus(session, Hook.sessionBoundary)
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertNil(session.tabStatus?.detailText)
    }

    // A turn Claude Code started without the hook's word for it is a new turn all the same, and
    // the message held from the one before is not its result.
    func testATurnTheHookDidNotAnnounceForgetsTheLastMessage() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(message: "First answer."))
        reports(session, "state=done:app=claude-code")
        reports(session, "state=working:app=claude-code")
        // The hook closes this turn without a message of its own.
        setStatus(session, ["turn_open": NSNumber(value: false), "agent": "claude"])
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertNil(session.tabStatus?.detailText)
    }

    func testClaudeCodesOwnDoneMessageWins() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(message: "From the hook."))
        reports(session, "state=done:app=claude-code:msg=\(base64("From Claude Code."))")
        XCTAssertEqual(session.tabStatus?.detailText, "From Claude Code.")
    }

    // What the hook's write would display is not applied while Claude Code reports: only its
    // count and turn flag are kept.
    func testAHookWriteChangesOnlyTheFactsWhileClaudeCodeReports() {
        let session = claudeCodeSession()
        let reply = setStatus(session, Hook.userPromptSubmit.merging(["detail": "from the hook", "progress": "running"]) { $1 })
        XCTAssertEqual(session.tabStatus?.statusText, "working")
        XCTAssertNil(session.tabStatus?.detailText)
        XCTAssertEqual(screenProgress(of: session), .stopped)
        XCTAssertEqual(session.tabStatus?.turnOpen, true)
        // The reply is the status as displayed, which is what the hook's reads expect.
        XCTAssertEqual(reply?["status"] as? String, "working")
        XCTAssertEqual(reply?["turn_open"] as? Bool, true)
    }

    // The hook guards a write with what it read a moment before. A write whose guard fails is
    // dropped whole, facts included, as it is without Claude Code reporting.
    func testAHookWriteWhosePreconditionFailsLeavesTheFactsAlone() {
        let session = claudeCodeSession()
        setStatus(session, Hook.userPromptSubmit)
        setStatus(session, Hook.stop(message: "done").merging(["if_turn_open": NSNumber(value: false),
                                                              "background_tasks": NSNumber(value: 5)]) { $1 })
        XCTAssertEqual(session.tabStatus?.turnOpen, true)
        XCTAssertEqual(session.tabStatus?.backgroundTasks, 0)
        reports(session, "state=done:app=claude-code")
        XCTAssertNil(session.tabStatus?.detailText)
    }

    func testCodexAndUnmarkedWritesStillApplyInFull() {
        let session = claudeCodeSession()
        setStatus(session, ["status": "done", "agent": "codex"])
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        setStatus(session, ["status": "mine"])
        XCTAssertEqual(session.tabStatus?.statusText, "mine")
    }

    // The Session Status tool lists Claude Code's own row with the same status the tab shows.
    func testTheRootRowInTheSessionStatusToolShowsBackground() throws {
        let session = claudeCodeSession()
        reports(session, "state=working:app=claude-code:id=a1:title=\(base64("Run the tests"))")
        setStatus(session, Hook.stop(running: 1))
        let records = try XCTUnwrap(session.programStatusControllerIfPresent?.displayRecords)
        let root = try XCTUnwrap(records.first { $0.isRoot })
        XCTAssertEqual(root.statusText, "background")
        XCTAssertEqual(root.detail, "1 background task running")
        // The agent's own row is Claude Code's to describe.
        let child = try XCTUnwrap(records.first { !$0.isRoot })
        XCTAssertEqual(child.statusText, "working")
    }

    func testAnInvalidWriteIsStillRefused() {
        let session = claudeCodeSession()
        var failed = false
        SetStatusBuiltInFunction.apply(["progress": "spinning", "agent": "claude"], to: session) { _, error in
            failed = error != nil
        }
        XCTAssertTrue(failed)
    }

    // MARK: Only one present

    func testTheHookAloneDrivesInFull() {
        let session = PTYSession(synthetic: false)!
        setStatus(session, Hook.userPromptSubmit)
        XCTAssertEqual(session.tabStatus?.statusText, "working")
        setStatus(session, Hook.stop(running: 1).merging(["progress": "running"]) { $1 })
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        XCTAssertEqual(session.tabStatus?.detailText, "1 background task running")
        XCTAssertEqual(screenProgress(of: session), .indeterminate)
    }

    func testClaudeCodesReportsAloneDriveInFull() {
        let session = claudeCodeSession()
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertNil(session.tabStatus?.detailText)
        reports(session, "state=working:app=claude-code")
        reports(session, "state=working:app=claude-code:id=a1:title=\(base64("Run the tests"))")
        XCTAssertEqual(session.tabStatus?.statusText, "working")
        XCTAssertEqual(session.tabStatus?.detailText, "Run the tests")
    }

    func testAnotherProgramsReportsDoNotTakeOverFromTheHook() {
        let session = PTYSession(synthetic: false)!
        reports(session, "state=working:app=make")
        setStatus(session, Hook.stop(message: "from the hook"))
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertEqual(session.tabStatus?.detailText, "from the hook")
    }

    // MARK: Moving between the two

    // Inside tmux, or before Claude Code's first report, the hook drives. What it stored carries
    // over when the reports begin.
    func testTheFirstReportKeepsWhatTheHookAlreadyStored() {
        let session = PTYSession(synthetic: false)!
        setStatus(session, Hook.stop(running: 2))
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        reports(session, "state=working:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        XCTAssertEqual(session.tabStatus?.detailText, "2 background tasks running")
    }

    // Claude Code sends a clear as it exits, and its SessionEnd hook lands a moment later. From
    // the clear on, the hook is on its own again.
    func testAfterClaudeCodeClearsTheHookDrivesAgain() {
        let session = claudeCodeSession()
        reports(session, "state=clear")
        XCTAssertEqual(session.programStatusControllerIfPresent?.claudeCodeIsReporting, false)
        setStatus(session, Hook.sessionBoundary)
        XCTAssertEqual(session.tabStatus?.statusText, "idle")
    }

    // However the clear is spelled, clearing its own record is Claude Code going away.
    func testAClearThatNamesClaudeCodeAlsoEndsIt() {
        let session = claudeCodeSession()
        reports(session, "state=clear:app=claude-code")
        XCTAssertEqual(session.programStatusControllerIfPresent?.claudeCodeIsReporting, false)
        setStatus(session, Hook.sessionBoundary)
        XCTAssertEqual(session.tabStatus?.statusText, "idle")
    }

    // A clear of one agent's record is not Claude Code going away.
    func testClearingAnAgentsRecordDoesNotEndIt() {
        let session = claudeCodeSession()
        reports(session, "state=working:app=claude-code:id=a1")
        reports(session, "state=clear:id=a1")
        XCTAssertEqual(session.programStatusControllerIfPresent?.claudeCodeIsReporting, true)
    }

    func testANewPromptEndsIt() {
        let session = claudeCodeSession()
        session.screenPromptDidStart(atLine: 0)
        drainMainQueue()
        XCTAssertEqual(session.programStatusControllerIfPresent?.claudeCodeIsReporting, false)
        setStatus(session, Hook.userPromptSubmit)
        XCTAssertEqual(session.tabStatus?.statusText, "working")
        XCTAssertEqual(session.tabStatus?.turnOpen, true)
    }

    // The prompt's cleanup runs after the reports around it. Claude Code started from that
    // prompt may report before the cleanup, and must not be forgotten by it.
    func testAReportAfterThePromptSurvivesThePromptsCleanup() {
        let session = PTYSession(synthetic: false)!
        session.screenPromptDidStart(atLine: 0)
        reports(session, "state=working:app=claude-code")
        drainMainQueue()
        XCTAssertEqual(session.programStatusControllerIfPresent?.claudeCodeIsReporting, true)
    }

    func testProgramExitEndsIt() {
        let session = claudeCodeSession()
        session.programStatusControllerIfPresent?.commandDidEnd()
        XCTAssertEqual(session.programStatusControllerIfPresent?.claudeCodeIsReporting, false)
    }

    func testAFullResetEndsIt() {
        let session = claudeCodeSession()
        session.screenRemoveProgramStatusRecords()
        XCTAssertEqual(session.programStatusControllerIfPresent?.claudeCodeIsReporting, false)
        setStatus(session, Hook.userPromptSubmit)
        XCTAssertEqual(session.tabStatus?.statusText, "working")
    }

    // What the hook parked describes the program that was running. If Claude Code goes away
    // without its SessionEnd hook landing (it was terminated, say) while work was counted, the
    // count and the closed turn must not survive into the next program: a Claude Code started
    // later, with no hook to correct them, would read as background for as long as it ran.
    func testFactsFromARunThatEndedDoNotCarryIntoTheNext() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(running: 1))
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        // Claude Code clears its record on the way out; no SessionEnd follows.
        reports(session, "state=clear")
        XCTAssertNil(session.tabStatus?.statusText)
        // Back at the shell.
        session.screenPromptDidStart(atLine: 0)
        drainMainQueue()
        XCTAssertEqual(session.tabStatus?.backgroundTasks ?? 0, 0)
        XCTAssertNil(session.tabStatus?.turnOpen)

        // A later run, this time with no hook.
        reports(session, "state=idle:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "idle")
        XCTAssertNil(session.tabStatus?.detailText)
    }

    // The same when the hook was driving alone and nothing is on display at the prompt.
    func testFactsParkedWithNothingDisplayedAreForgottenAtAPrompt() {
        let session = PTYSession(synthetic: false)!
        setStatus(session, ["background_tasks": NSNumber(value: 2), "turn_open": NSNumber(value: false), "agent": "claude"])
        XCTAssertEqual(session.tabStatus?.backgroundTasks, 2)
        session.screenPromptDidStart(atLine: 0)
        drainMainQueue()
        XCTAssertEqual(session.tabStatus?.backgroundTasks ?? 0, 0)
        XCTAssertNil(session.tabStatus?.turnOpen)
    }

    // A message the hook left during one run of Claude Code is not shown for the next.
    func testTheLastMessageDoesNotOutliveTheRun() {
        let session = claudeCodeSession()
        setStatus(session, Hook.stop(message: "From the first run."))
        reports(session, "state=clear")
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertNil(session.tabStatus?.detailText)
    }

    // The hook retries without --agent when an iTerm2 from before the argument refuses it, and
    // recognizes that refusal by the function's name followed by the first argument name in the
    // error (the names are listed in order, and "agent" sorts first). This pins the wording, with
    // an argument no version knows standing in for one an old version does not.
    func testACallWithAnUnknownArgumentIsRefusedNamingTheCall() {
        let refused = expectation(description: "refused")
        var reason = ""
        iTermScriptFunctionCall.callFunction(
            "iterm2.set_session_status(session_id: \"x\", status: \"working\", aaa_unknown: \"1\")",
            timeout: 1,
            sideEffectsAllowed: true,
            scope: iTermVariableScope(),
            retainSelf: true) { _, error, _ in
                let nsError = error as NSError?
                reason = [nsError?.localizedFailureReason, nsError?.localizedDescription]
                    .compactMap { $0 }.joined(separator: " ")
                refused.fulfill()
            }
        wait(for: [refused], timeout: 5)
        XCTAssertTrue(reason.contains("set_session_status(aaa_unknown"), reason)
    }
}

// MARK: - Notifications

private final class RecordNotificationSpySession: PTYSession {
    var recordNotifications = [String]()

    override func postProgramStatusNotification(withDescription description: String) {
        recordNotifications.append(description)
    }
}

/// A record is announced as what the tab shows for it. Claude Code says done the moment a turn
/// ends with a background shell still running; that is background, and not yet a result.
final class ClaudeCodeHookAndReportsNotificationTests: XCTestCase {
    private var savedPriorities = [StatusPriorityEntry]()

    override func setUp() {
        super.setUp()
        savedPriorities = StatusPrioritySettings.shared.entries
        StatusPrioritySettings.shared.restoreEntries([StatusPriorityEntry(pattern: "done", notify: true),
                                                      StatusPriorityEntry(pattern: "work"),
                                                      StatusPriorityEntry(pattern: "background"),
                                                      StatusPriorityEntry(pattern: "idle")])
    }

    override func tearDown() {
        StatusPrioritySettings.shared.restoreEntries(savedPriorities)
        super.tearDown()
    }

    private func setStatus(_ session: PTYSession, _ parameters: [String: Any]) {
        SetStatusBuiltInFunction.apply(parameters, to: session) { _, error in
            XCTAssertNil(error)
        }
    }

    private func reports(_ session: PTYSession, _ body: String) {
        session.screenReportProgramStatusReports([ProgramStatusReport.parse(body)!])
    }

    func testDoneUnderBackgroundIsNotAnnouncedAsDoneButTheRealOneIs() {
        let session = RecordNotificationSpySession(synthetic: false)!
        reports(session, "state=working:app=claude-code")
        setStatus(session, Hook.userPromptSubmit)
        setStatus(session, Hook.stop(running: 1))
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "background")
        XCTAssertEqual(session.recordNotifications, [])

        // The shell finishes and Claude Code takes a turn to say so.
        reports(session, "state=working:app=claude-code")
        setStatus(session, Hook.userPromptSubmit)
        setStatus(session, Hook.stop(message: "Done."))
        reports(session, "state=done:app=claude-code")
        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertEqual(session.recordNotifications.count, 1)
    }
}

// MARK: - Replays

/// Recorded runs, replayed in every order the two sources could really have arrived in. Reports
/// travel in the terminal's output and hook writes come from a separate process, so two events a
/// moment apart can land either way round; events further apart cannot. For each such order the
/// status at every checkpoint must be the same.
final class ClaudeCodeHookAndReportsReplayTests: XCTestCase {
    private enum Source {
        case report(String)
        case hook([String: Any])
    }

    private struct Event {
        /// Milliseconds from the start of the recording.
        var time: Int
        var source: Source

        var isReport: Bool {
            if case .report = source {
                return true
            }
            return false
        }
    }

    private struct Checkpoint {
        /// Everything up to and including this time has happened.
        var time: Int
        var status: String?
        var detail: String?
        /// Statuses the tab may pass through on the way here.
        var allowed: Set<String>
    }

    /// Two events from different sources closer together than this may arrive in either order.
    private let window = 300

    private func r(_ time: Int, _ body: String) -> Event {
        return Event(time: time, source: .report(body))
    }

    private func h(_ time: Int, _ parameters: [String: Any]) -> Event {
        return Event(time: time, source: .hook(parameters))
    }

    /// Every order of `events` (given in time order) that keeps each source's own order and
    /// keeps apart any two events more than `window` apart.
    private func orders(of events: [Event]) -> [[Event]] {
        var result = [[Event]]()
        var remaining = Array(events.indices)
        var current = [Int]()
        func canGoNext(_ candidate: Int) -> Bool {
            for other in remaining where other < candidate {
                if events[other].isReport == events[candidate].isReport {
                    return false
                }
                if events[candidate].time - events[other].time > window {
                    return false
                }
            }
            return true
        }
        func extend() {
            if remaining.isEmpty {
                result.append(current.map { events[$0] })
                return
            }
            for candidate in remaining where canGoNext(candidate) {
                remaining.removeAll { $0 == candidate }
                current.append(candidate)
                extend()
                current.removeLast()
                remaining.append(candidate)
                remaining.sort()
            }
        }
        extend()
        return result
    }

    private func apply(_ event: Event, to session: PTYSession) {
        switch event.source {
        case .report(let body):
            session.screenReportProgramStatusReports([ProgramStatusReport.parse(body)!])
        case .hook(let parameters):
            SetStatusBuiltInFunction.apply(parameters, to: session) { _, error in
                XCTAssertNil(error)
            }
        }
    }

    private func replay(_ name: String,
                        _ events: [Event],
                        _ checkpoints: [Checkpoint],
                        file: StaticString = #filePath,
                        line: UInt = #line) {
        var start = 0
        for checkpoint in checkpoints {
            // The checkpoint must fall in a quiet moment, or "everything up to here" would not
            // mean the same thing in every order.
            let before = events.filter { $0.time <= checkpoint.time }
            let after = events.filter { $0.time > checkpoint.time }
            if let last = before.last, let next = after.first {
                XCTAssertGreaterThan(next.time - last.time, window, "\(name): checkpoint at \(checkpoint.time) is not in a quiet moment", file: file, line: line)
            }
            let earlier = events.filter { $0.time <= start }
            let segment = events.filter { $0.time > start && $0.time <= checkpoint.time }
            let segmentOrders = orders(of: segment)
            XCTAssertFalse(segmentOrders.isEmpty, "\(name): no orders", file: file, line: line)
            for order in segmentOrders {
                let session = PTYSession(synthetic: false)!
                for event in earlier {
                    apply(event, to: session)
                }
                let described = order.map { $0.isReport ? "R\($0.time)" : "H\($0.time)" }.joined(separator: " ")
                for event in order {
                    apply(event, to: session)
                    if let status = session.tabStatus?.statusText {
                        XCTAssertTrue(checkpoint.allowed.contains(status),
                                      "\(name): passed through \(status) in order \(described)", file: file, line: line)
                    }
                }
                XCTAssertEqual(session.tabStatus?.statusText, checkpoint.status,
                               "\(name): status at \(checkpoint.time) in order \(described)", file: file, line: line)
                XCTAssertEqual(session.tabStatus?.detailText, checkpoint.detail,
                               "\(name): detail at \(checkpoint.time) in order \(described)", file: file, line: line)
            }
            start = checkpoint.time
        }
    }

    func testOrdersKeepEachSourcesOrderAndFarApartEventsApart() {
        let events = [r(0, "state=working"), h(10, [:]), h(20, [:]), r(30, "state=done"), h(1000, [:])]
        let all = orders(of: events).map { order in order.map { $0.time } }
        // The two reports keep their order, the hook writes keep theirs, and the last event is
        // too far from the rest to move.
        XCTAssertEqual(Set(all.map { $0.map(String.init).joined(separator: ",") }),
                       ["0,10,20,30,1000", "0,10,30,20,1000", "0,30,10,20,1000",
                        "10,0,20,30,1000", "10,0,30,20,1000", "10,20,0,30,1000"])
    }

    // A turn launches one background agent and ends; the agent works for 30 seconds; Claude Code
    // starts a turn of its own to read the result.
    func testBackgroundAgent() {
        let title = base64("Run work.sh in foreground")
        replay("background agent", [
            r(0, "state=working:app=claude-code"),
            h(15, Hook.userPromptSubmit),
            h(2157, Hook.toolUse),
            r(2220, "state=working:app=claude-code:id=a3:title=\(title)"),
            h(2225, Hook.toolUse),
            h(3438, Hook.stop(running: 1)),
            // A utility agent stops; the background agent is still listed.
            h(4753, Hook.count(1)),
            h(4760, Hook.backgroundIfTurnClosed(1)),
            // The agent finishes.
            h(34647, Hook.count(0)),
            r(34686, "state=clear:id=a3"),
            h(34713, Hook.userPromptSubmit),
            h(36035, Hook.stop(message: "DONE")),
            r(36061, "state=done:app=claude-code"),
            h(37595, Hook.count(0)),
        ], [
            Checkpoint(time: 3000, status: "working", detail: "Run work.sh in foreground", allowed: ["working"]),
            Checkpoint(time: 20000, status: "background", detail: "1 background task running", allowed: ["working", "background"]),
            Checkpoint(time: 35000, status: "working", detail: nil, allowed: ["working", "background"]),
            Checkpoint(time: 40000, status: "done", detail: "DONE", allowed: ["working", "done"]),
        ])
    }

    // A turn starts a background shell and ends; the shell runs for 30 seconds; Claude Code
    // starts a turn of its own when it finishes.
    func testBackgroundShell() {
        replay("background shell", [
            r(0, "state=working:app=claude-code"),
            h(16, Hook.userPromptSubmit),
            h(1301, Hook.toolUse),
            h(1366, Hook.toolUse),
            h(2394, Hook.stop(running: 1)),
            r(2426, "state=done:app=claude-code"),
            h(3847, Hook.count(1)),
            h(3854, Hook.backgroundIfTurnClosed(1)),
            // The shell finishes.
            r(31447, "state=working:app=claude-code"),
            h(31484, Hook.userPromptSubmit),
            h(32744, Hook.stop(message: "Done")),
            r(32774, "state=done:app=claude-code"),
            h(34115, Hook.count(0)),
        ], [
            Checkpoint(time: 2000, status: "working", detail: nil, allowed: ["working"]),
            // Claude Code's done and the hook's Stop are 32 ms apart. If the done lands first,
            // the tab says done until the Stop does: nothing has yet said work is still running.
            Checkpoint(time: 20000, status: "background", detail: "1 background task running", allowed: ["working", "done", "background"]),
            // Likewise the other way round at the start of the next turn: if the hook's prompt
            // lands first, the record still says done until Claude Code's working arrives.
            Checkpoint(time: 32000, status: "working", detail: nil, allowed: ["working", "done", "background"]),
            Checkpoint(time: 40000, status: "done", detail: "Done", allowed: ["working", "done"]),
        ])
    }

    func testPermissionPrompt() {
        let message = base64("approve Bash: touch /tmp/bgperm-test")
        replay("permission prompt", [
            r(0, "state=working:app=claude-code"),
            h(14, Hook.userPromptSubmit),
            h(1701, Hook.toolUse),
            r(1741, "state=blocked:app=claude-code:kind=permission:msg=\(message)"),
            h(1754, Hook.permissionRequest),
            // Approved.
            r(22360, "state=working:app=claude-code"),
            h(22403, Hook.toolUse),
            h(23421, Hook.stop(message: "Created the file.")),
            r(23448, "state=done:app=claude-code"),
        ], [
            Checkpoint(time: 10000, status: "waiting", detail: "approve Bash: touch /tmp/bgperm-test", allowed: ["working", "waiting"]),
            Checkpoint(time: 23000, status: "working", detail: nil, allowed: ["waiting", "working"]),
            Checkpoint(time: 30000, status: "done", detail: "Created the file.", allowed: ["working", "done"]),
        ])
    }

    // Esc fires no hook: only Claude Code says the turn stopped.
    func testEsc() {
        replay("Esc", [
            r(0, "state=working:app=claude-code"),
            h(15, Hook.userPromptSubmit),
            h(1256, Hook.toolUse),
            r(6362, "state=idle:app=claude-code"),
        ], [
            Checkpoint(time: 10000, status: "idle", detail: nil, allowed: ["working", "idle"]),
        ])
    }

    // An agent pauses on background shells of its own. Claude Code clears the agent's record
    // and reports done after a short turn; the hook counts the shells.
    func testAgentPausedOnItsOwnShells() {
        let title = base64("Run sleep and echo commands")
        replay("agent paused on its own shells", [
            r(0, "state=working:app=claude-code"),
            h(15, Hook.userPromptSubmit),
            r(2000, "state=working:app=claude-code:id=a3:title=\(title)"),
            h(3000, Hook.stop(running: 1)),
            // The agent's own turn ends with two shells running.
            h(12000, Hook.count(2)),
            h(12007, Hook.backgroundIfTurnClosed(2)),
            r(12040, "state=clear:id=a3"),
            h(12070, Hook.userPromptSubmit),
            h(14000, Hook.stop(running: 2)),
            r(14030, "state=done:app=claude-code"),
        ], [
            Checkpoint(time: 8000, status: "background", detail: "1 background task running", allowed: ["working", "background"]),
            Checkpoint(time: 13000, status: "working", detail: nil, allowed: ["working", "background"]),
            Checkpoint(time: 20000, status: "background", detail: "2 background tasks running", allowed: ["working", "done", "background"]),
        ])
    }
}

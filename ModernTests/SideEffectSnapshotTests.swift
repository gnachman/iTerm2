//
//  SideEffectSnapshotTests.swift
//  iTerm2
//
//  Side effects run on the main thread against the main thread's copy of the
//  screen state, which is refreshed only by a sync. The main thread can drain
//  a side effect that was enqueued after its last sync (for example from
//  performLightweightBlockWithJoinedThreads, which syncs and then drains). A
//  handler that reads screen state instead of values captured on the mutation
//  thread then sees the state from before the change that queued it. Issue
//  13184 was one of these. Each test here performs a change on the mutation
//  queue, drains side effects without syncing, and checks that what the
//  handler reads matches the mutation thread's state when the side effect was
//  queued. Where a handler reads screen state, the test makes the same reads;
//  where values are now passed to the handler, it checks those.
//

import XCTest
@testable import iTerm2SharedARC

private final class SnapshotSpy: SpyingScreenDelegate {
    var onCommandDidExit: (((any VT100ScreenMarkReading)?, CommandOutput?) -> Void)?
    var onStopScrolling: ((Int64) -> Void)?
    var onClearCapturedOutput: (() -> Void)?
    var onDidCaptureOutput: (() -> Void)?
    var onRevealComposer: (() -> Void)?
    var onMoveSelectionUp: ((Int32, VT100GridRect, Int64) -> Void)?
    var onUpdateBlock: ((String, iTermUpdateBlockAction) -> Void)?
    var onSetLabel: ((String, String, Int64) -> Void)?
    var onAppendString: ((String, UInt) -> Void)?
    var onPromptDidEnd: ((any VT100ScreenMarkReading, String?, VT100GridAbsCoord, String?, UInt) -> Void)?
    var onEnsureDefaultMode: (() -> Void)?
    /// The screen to sync when the token executor asks for one, as PTYSession
    /// does. FakeSession doesn't sync.
    weak var screenToSync: VT100Screen?

    override func screenSync(_ mutableState: VT100ScreenMutableState) {
        screenToSync?.synchronize(withConfig: screenConfiguration(),
                                  expect: nil,
                                  checkTriggers: .none,
                                  resetOverflow: false,
                                  mutableState: mutableState)
    }

    override func screenCommandDidExit(withCode code: Int32,
                                       keyReportingFlags: VT100TerminalKeyReportingFlags,
                                       mark maybeMark: (any VT100ScreenMarkReading)?,
                                       output: CommandOutput?) {
        onCommandDidExit?(maybeMark, output)
    }

    override func screenEnsureDefaultMode() {
        onEnsureDefaultMode?()
    }

    override func triggerSideEffectStopScrolling(atLine absLine: Int64) {
        onStopScrolling?(absLine)
    }

    override func screenClearCapturedOutput() {
        onClearCapturedOutput?()
    }

    override func triggerSideEffectDidCaptureOutput() {
        onDidCaptureOutput?()
    }

    override func screenRevealComposer(withPrompt prompt: [ScreenCharArray]) {
        onRevealComposer?()
    }

    override func screenMoveSelectionUp(by n: Int32, inRegion region: VT100GridRect, regionAbsTop: Int64) {
        onMoveSelectionUp?(n, region, regionAbsTop)
    }

    override func screenUpdateBlock(_ blockID: String, action: iTermUpdateBlockAction) {
        onUpdateBlock?(blockID, action)
    }

    override func screenSetLabel(_ label: String, forKey keyName: String, absLineOfCursor: Int64) {
        onSetLabel?(label, keyName, absLineOfCursor)
    }

    override func screenDidAppendString(toCurrentLine string: String,
                                        isPlainText plainText: Bool,
                                        foreground fg: screen_char_t,
                                        background bg: screen_char_t,
                                        atPrompt: Bool,
                                        encoding: UInt) {
        onAppendString?(string, encoding)
    }

    override func screenPromptDidEnd(withMark mark: any VT100ScreenMarkReading,
                                     command: String?,
                                     cursor: VT100GridAbsCoord,
                                     workingDirectory: String?,
                                     encoding: UInt) {
        super.screenPromptDidEnd(withMark: mark, command: command, cursor: cursor, workingDirectory: workingDirectory,
                                 encoding: encoding)
        onPromptDidEnd?(mark, command, cursor, workingDirectory, encoding)
    }
}

final class SideEffectSnapshotTests: XCTestCase {
    private var harness: TerminalTestHarness!
    private var spy: SnapshotSpy!
    /// Real sessions made by tests, released in tearDown.
    private var sessions: [PTYSession] = []
    /// Registrations that have the real sessions capture command output.
    private var consumers: [CommandOutputConsumer] = []

    override func setUp() {
        super.setUp()
        spy = SnapshotSpy()
        // Output is captured only while something consumes it, registered under the session guid
        // in the configuration. The configuration is loaded by the harness's first joined block.
        // Only a real sync clears its dirty flag, so clear it here or every later join would reload
        // it over a configuration a test installs itself.
        let harnessGuid = UUID().uuidString
        spy.configuration.sessionGuid = harnessGuid
        consumers.append(CommandOutput.addConsumer(forSessionReference: harnessGuid))
        spy.configuration.unlimitedScrollback = true
        spy.configuration.isDirty = true
        harness = TerminalTestHarness(delegate: spy)
        spy.configuration.isDirty = false
        spy.screenToSync = harness.screen
        harness.sync()
    }

    override func tearDown() {
        consumers = []
        sessions = []
        harness = nil
        spy = nil
        super.tearDown()
    }

    private var screen: VT100Screen {
        harness.screen
    }

    /// Runs `block` on the mutation queue, as the pty path does, so the main
    /// thread's copy of the state is not updated. Then drains side effects
    /// from the main thread without syncing first.
    private func mutateThenDrainBeforeSync(_ block: (VT100ScreenMutableState) -> Void) {
        let mutableState = harness.screen.mutableState
        mutationQueue(of: mutableState).sync {
            block(mutableState)
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)
    }

    /// The screen's mutation queue, which may be its own rather than the
    /// shared one.
    private func mutationQueue(of mutableState: VT100ScreenMutableState) -> DispatchQueue {
        mutableState.queueForTesting()
    }

    /// A real PTYSession whose screen reports to it, kept until tearDown. Unless `consumer` is
    /// false, something is registered as consuming its commands' output, as AI Chat or Codecierge
    /// would be, so it captures that output.
    private func makeSession(consumer: Bool = true) -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.screen.delegate = session
        sessions.append(session)
        if consumer {
            consumers.append(CommandOutput.addConsumer(forSessionReference: session.guid))
        }
        return session
    }

    /// Mutation queue. Puts a session's screen in a usable state.
    private func setUpTerminal(_ mutableState: VT100ScreenMutableState, of screen: VT100Screen) {
        mutableState.terminalEnabled = true
        mutableState.terminal!.termType = "xterm"
        screen.destructivelySetScreenWidth(80, height: 24, mutableState: mutableState)
    }

    /// Main queue. Changes a real session's own configuration, so later syncs keep the setting.
    /// A nil limit means unlimited scrollback.
    private func setScrollback(of session: PTYSession, limit: Int32?) {
        let config = session.screenConfiguration()
        config.unlimitedScrollback = limit == nil
        config.maxScrollbackLines = limit ?? 0
        config.isDirty = true
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setConfig(config)
        })
    }

    /// Mutation queue. Parses `string` and executes the resulting tokens.
    private func execute(_ string: String, in mutableState: VT100ScreenMutableState) {
        let bytes = Array(string.utf8)
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        bytes.withUnsafeBufferPointer { buf in
            parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        _ = parser.addParsedTokens(to: &vector)
        for i in 0..<CVectorCount(&vector) {
            let token = CVectorGetObject(&vector, i) as! VT100Token
            mutableState.terminal!.execute(token)
        }
        CVectorDestroy(&vector)
    }

    /// Mutation queue. Appends lines of text, enough to push some into
    /// scrollback so line numbers and the line count change.
    private func appendLines(_ count: Int,
                             prefix: String = "line",
                             in mutableState: VT100ScreenMutableState) {
        for i in 0..<count {
            mutableState.appendString(atCursor: "\(prefix) \(i)")
            mutableState.appendCarriageReturnLineFeed()
        }
    }

    /// Main queue. A prompt and command, synced to the main thread. Unless
    /// `finished` is false, the command also produces output and exits, which
    /// leaves it cached as the last command mark on both threads.
    private func runCommand(_ command: String, aid: String? = nil, finished: Bool = true) {
        harness.sendPromptStart(aid: aid)
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText(command)
        harness.sendCommandEnd()
        harness.newline()
        if finished {
            harness.appendText("output")
            harness.newline()
            harness.sendReturnCode(0, aid: aid)
        }
        harness.sync()
    }

    /// Mutation queue. Starts a new prompt and command since the last sync.
    private func startCommand(_ command: String, in mutableState: VT100ScreenMutableState) {
        mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
        mutableState.appendString(atCursor: "$ ")
        mutableState.terminalCommandDidStart()
        mutableState.appendString(atCursor: command)
        mutableState.terminalCommandDidEnd()
        mutableState.appendCarriageReturnLineFeed()
    }

    /// Mutation queue. The trigger callbacks are declared privately in
    /// Objective-C, so reach them through the protocol.
    private func triggerSession(_ mutableState: VT100ScreenMutableState) -> iTermTriggerSession {
        mutableState as AnyObject as! iTermTriggerSession
    }

    /// Mutation queue. What a Capture Output trigger does on a match.
    private func captureOutput(_ line: String, in mutableState: VT100ScreenMutableState) {
        let capturedOutput = CapturedOutput()
        capturedOutput.line = line
        capturedOutput.values = []
        triggerSession(mutableState).triggerSession(Trigger(), didCapture: capturedOutput)
    }

    /// Mutation queue. The absolute line the cursor is on.
    private func absLineOfCursor(_ mutableState: VT100ScreenMutableState) -> Int64 {
        Int64(mutableState.cursorY - 1 + mutableState.numberOfScrollbackLines) + mutableState.cumulativeScrollbackOverflow
    }

    private func capturedOutputCount(_ mark: any VT100ScreenMarkReading) -> Int {
        mark.capturedOutput?.count ?? 0
    }

    private func lines(_ range: VT100GridCoordRange) -> [Int32] {
        [range.start.y, range.end.y]
    }

    /// The output text AI Chat and Codecierge would read from a command-exit notification carrying
    /// `output`, as lines. Goes through CommandExitNotification, as they do.
    private func outputLines(_ output: CommandOutput) -> [String]? {
        outputLines(Notification(name: .PTYCommandDidExit, object: nil, userInfo: [
            PTYCommandDidExitUserInfoKeyCommand: "command",
            PTYCommandDidExitUserInfoKeyURL: URL(string: "iterm2:///")!,
            PTYCommandDidExitUserInfoKeyDataSource: output,
            PTYCommandDidExitUserInfoKeyStartLine: NSNumber(value: output.startLine),
            PTYCommandDidExitUserInfoKeyLineCount: NSNumber(value: output.lineCount),
            PTYCommandDidExitUserInfoKeyDroppedLineCount: NSNumber(value: output.droppedLineCount),
        ]))
    }

    /// The output text AI Chat and Codecierge would read from `note`, as lines, or nil when it
    /// carries no output.
    private func outputLines(_ note: Notification) -> [String]? {
        guard let userInfo = note.userInfo,
              let output = CommandExitNotification(userInfo: userInfo)?.output else {
            return nil
        }
        return output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Main queue. Runs a command to its exit in a real session and reports whether the exit
    /// notification carried the output.
    private func commandExitHasOutput(in session: PTYSession) -> Bool {
        let sessionScreen = session.screen
        let mutableState = sessionScreen.mutableState
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            if !mutableState.terminalEnabled {
                setUpTerminal(mutableState, of: sessionScreen)
            }
            startCommand("ls", in: mutableState)
        })
        var hadOutput = false
        let exited = expectation(forNotification: .PTYCommandDidExit, object: session.guid) { note in
            hadOutput = note.userInfo?[PTYCommandDidExitUserInfoKeyDataSource] != nil
            return true
        }
        mutationQueue(of: mutableState).sync {
            appendLines(1, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)
        wait(for: [exited], timeout: 10)
        return hadOutput
    }

    private func text(onLine line: Int32) -> String {
        screen.screenCharArray(forLine: line).stringValue
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Command exit (OSC 133 ; D)

    /// The output passed to screenCommandDidExitWithCode must have all of the
    /// output. Its lines come from a snapshot taken on the mutation thread,
    /// because the main thread's copy of the screen may not have the last of
    /// them. The output is saved in command history and AI Chat's record of
    /// the command.
    func testCommandExitOutput() {
        runCommand("ls", finished: false)
        var seen: [String]?
        spy.onCommandDidExit = { [unowned self] mark, output in
            guard mark != nil, let output else {
                return
            }
            seen = outputLines(output)
        }
        mutateThenDrainBeforeSync { mutableState in
            appendLines(5, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        XCTAssertEqual(seen.map { Array($0.prefix(5)) }, (0..<5).map { "output \($0)" },
                       "The output must include every line")
    }

    /// Same as testCommandExitOutput, through the close-by-aid path
    /// (closeAidMark:), which queues its own command-exit side effect.
    func testCommandExitOutputWithAid() {
        runCommand("ls", aid: "a1", finished: false)
        var seen: [String]?
        spy.onCommandDidExit = { [unowned self] mark, output in
            guard mark != nil, let output else {
                return
            }
            seen = outputLines(output)
        }
        mutateThenDrainBeforeSync { mutableState in
            appendLines(5, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: "a1")
        }
        XCTAssertEqual(seen.map { Array($0.prefix(5)) }, (0..<5).map { "output \($0)" },
                       "The output must include every line")
    }

    /// The output range is half-open: it ends where the next prompt begins.
    /// That prompt's line is not output and must not be captured.
    func testCommandExitOutputExcludesNextPrompt() {
        runCommand("ls", aid: "a1", finished: false)
        var seen: [String]?
        spy.onCommandDidExit = { [unowned self] mark, output in
            guard mark != nil, let output else {
                return
            }
            seen = outputLines(output)
        }
        mutateThenDrainBeforeSync { mutableState in
            appendLines(3, prefix: "output", in: mutableState)
            startCommand("second", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: "a1")
        }
        XCTAssertEqual(seen?.filter { !$0.isEmpty }, (0..<3).map { "output \($0)" },
                       "The next prompt's line must not be captured as output")
    }

    /// A new command mark reaches the main thread's cache before the next sync.
    /// Its doppelganger is already in the main thread's interval tree, since
    /// that addition was queued first, so the mark is usable there.
    func testMainThreadLastCommandMarkIsUsableBeforeSync() {
        runCommand("first")
        var expectedGuid: String?
        var expectedStart: Int32?
        mutateThenDrainBeforeSync { mutableState in
            startCommand("second", in: mutableState)
            appendLines(2, prefix: "output", in: mutableState)
            let mark = mutableState.lastCommandMark!
            expectedGuid = mark.guid
            expectedStart = mutableState.rangeOfOutput(forCommandMark: mark).start.y
        }
        let mark = screen.lastCommandMark()
        XCTAssertEqual(mark?.guid, expectedGuid)
        // Only the start: the end comes from the line count, which the main thread's copy doesn't
        // have yet.
        XCTAssertEqual(mark.map { screen.rangeOfOutput(forCommandMark: $0).start.y }, expectedStart,
                       "The main thread must be able to locate the mark's output")
    }

    /// With the cursor on the bottom row, the output range's end is one past
    /// the last line, which screenCharArrayForLine: wraps to the top row of
    /// the screen. That row must not be captured as output.
    func testCommandExitOutputWithCursorOnBottomRow() {
        runCommand("ls", finished: false)
        var seen: [String]?
        spy.onCommandDidExit = { [unowned self] mark, output in
            guard mark != nil, let output else {
                return
            }
            seen = outputLines(output)
        }
        mutateThenDrainBeforeSync { mutableState in
            appendLines(30, prefix: "output", in: mutableState)
            XCTAssertEqual(mutableState.cursorY, mutableState.height, "The cursor must be on the bottom row")
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        XCTAssertEqual(seen.map { Array($0.prefix(30)) }, (0..<30).map { "output \($0)" })
        XCTAssertEqual(seen?.dropFirst(30).filter { !$0.isEmpty }, [],
                       "Nothing but the output may be captured")
    }

    /// Only the last CommandOutput.maxLines lines are captured.
    func testCommandExitOutputKeepsOnlyTheLastLines() {
        runCommand("ls", finished: false)
        var seen: CommandOutput?
        spy.onCommandDidExit = { mark, output in
            guard mark != nil else {
                return
            }
            seen = output
        }
        let total = Int(CommandOutput.maxLines) + 50
        mutateThenDrainBeforeSync { mutableState in
            appendLines(total, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        guard let seen else {
            XCTFail("No output")
            return
        }
        guard let lines = outputLines(seen) else {
            XCTFail("No output text")
            return
        }
        XCTAssertEqual(seen.lineCount, CommandOutput.maxLines)
        XCTAssertGreaterThan(seen.droppedLineCount, 0)
        XCTAssertEqual(lines.first, CommandExitNotification.omittedLinesNote(seen.droppedLineCount),
                       "The text must say how many lines were left out")
        XCTAssertEqual(lines.dropFirst().first, "output \(seen.droppedLineCount)", "The kept lines must be the last ones")
        XCTAssertEqual(lines.last { !$0.isEmpty }, "output \(total - 1)")
    }

    /// With no next prompt yet, the output range runs through the empty line the cursor sits on.
    /// That line is not output: a command that prints exactly the cap's worth of lines must have
    /// nothing omitted.
    func testOutputOfExactlyTheCapHasNothingOmitted() {
        runCommand("ls", finished: false)
        var seen: CommandOutput?
        spy.onCommandDidExit = { mark, output in
            guard mark != nil else {
                return
            }
            seen = output
        }
        let total = Int(CommandOutput.maxLines)
        mutateThenDrainBeforeSync { mutableState in
            appendLines(total, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        XCTAssertEqual(seen?.lineCount, CommandOutput.maxLines)
        XCTAssertEqual(seen?.droppedLineCount, 0, "The empty line after the output is not output")
        let lines = seen.flatMap { outputLines($0) }
        XCTAssertEqual(lines?.first, "output 0")
        XCTAssertEqual(lines?.last { !$0.isEmpty }, "output \(total - 1)")
    }

    /// Output whose last line has no newline shares that line with the cursor. It holds output and
    /// is kept.
    func testOutputWithoutATrailingNewlineKeepsItsLastLine() {
        runCommand("ls", finished: false)
        var seen: CommandOutput?
        spy.onCommandDidExit = { mark, output in
            guard mark != nil else {
                return
            }
            seen = output
        }
        let fullLines = Int(CommandOutput.maxLines) - 1
        mutateThenDrainBeforeSync { mutableState in
            appendLines(fullLines, prefix: "output", in: mutableState)
            mutableState.appendString(atCursor: "partial")
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        XCTAssertEqual(seen?.lineCount, CommandOutput.maxLines)
        XCTAssertEqual(seen?.droppedLineCount, 0)
        let lines = seen.flatMap { outputLines($0) }
        XCTAssertEqual(lines?.first, "output 0")
        XCTAssertEqual(lines?.last { !$0.isEmpty }, "partial")
    }

    /// The scan past trailing blank lines stops after the cap's worth, so output ending in a long run
    /// of them costs no more to capture than output of any other kind. The blank lines left over are
    /// kept as output and the text before them counts as omitted.
    func testTrailingBlankLinesAreScannedOnlyUpToTheCap() {
        runCommand("ls", finished: false)
        var seen: CommandOutput?
        spy.onCommandDidExit = { mark, output in
            guard mark != nil else {
                return
            }
            seen = output
        }
        let blankLines = 3 * Int(CommandOutput.maxLines)
        mutateThenDrainBeforeSync { mutableState in
            mutableState.appendString(atCursor: "text")
            for _ in 0..<blankLines {
                mutableState.appendCarriageReturnLineFeed()
            }
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        guard let seen else {
            XCTFail("No output")
            return
        }
        XCTAssertEqual(seen.lineCount, CommandOutput.maxLines, "The scan must stop at the cap")
        XCTAssertGreaterThan(seen.droppedLineCount, 0, "The line of text counts as omitted")
        XCTAssertEqual(outputLines(seen)?.dropFirst().filter { !$0.isEmpty }, [])
    }

    /// Output whose start has scrolled out of the buffer counts the lost lines as omitted, as it
    /// does the lines left out to keep under the cap.
    func testOutputLostToScrollbackCountsAsOmitted() {
        let session = makeSession()
        let sessionScreen = session.screen
        setScrollback(of: session, limit: 10)
        let total = 100
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
            startCommand("ls", in: mutableState)
        })
        sessionScreen.waitForQueuedTokensForTesting()

        var userInfo: [AnyHashable: Any]?
        let exited = expectation(forNotification: .PTYCommandDidExit,
                                 object: session.guid) { note in
            userInfo = note.userInfo
            return true
        }
        let mutableState = sessionScreen.mutableState
        mutationQueue(of: mutableState).sync {
            appendLines(total, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: true)
        wait(for: [exited], timeout: 10)
        let dropped = (userInfo?[PTYCommandDidExitUserInfoKeyDroppedLineCount] as? NSNumber)?.intValue
        let kept = (userInfo?[PTYCommandDidExitUserInfoKeyLineCount] as? NSNumber)?.intValue
        XCTAssertLessThan(kept ?? total, total, "Some output must have scrolled off")
        XCTAssertEqual(dropped.flatMap { d in kept.map { d + $0 } }, total,
                       "The kept and omitted lines must add up to the whole output")
    }

    /// Captured before the next prompt exists, the output range used to start
    /// on the line after the prompt mark, which covers only the prompt's first
    /// line. A command with a continuation line then had that line reported as
    /// output. The output start recorded at FTCS C must be used instead.
    func testCommandExitOutputStartsAfterCommandContinuationLine() {
        var seen: [String]?
        spy.onCommandDidExit = { [unowned self] mark, output in
            guard mark != nil, let output else {
                return
            }
            seen = outputLines(output)
        }
        mutateThenDrainBeforeSync { mutableState in
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
            mutableState.appendString(atCursor: "echo \\")
            mutableState.appendCarriageReturnLineFeed()
            mutableState.appendString(atCursor: "continued")
            mutableState.terminalCommandDidEnd()
            mutableState.appendCarriageReturnLineFeed()
            appendLines(2, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        XCTAssertEqual(seen.map { Array($0.prefix(2)) }, ["output 0", "output 1"],
                       "The output must start after the command, not on its continuation line")
    }

    /// End to end with a real PTYSession: AI Chat and Codecierge read the
    /// output posted in PTYCommandDidExitNotification from its data source,
    /// and it must have every line.
    func testCommandExitNotificationOutputWithRealSession() {
        let session = makeSession()
        let sessionScreen = session.screen
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
            mutableState.appendString(atCursor: "ls")
            mutableState.terminalCommandDidEnd()
            mutableState.appendCarriageReturnLineFeed()
        })
        sessionScreen.waitForQueuedTokensForTesting()

        var lines: [String]?
        let exited = expectation(forNotification: .PTYCommandDidExit,
                                 object: session.guid) { [unowned self] note in
            lines = outputLines(note)
            return true
        }
        let mutableState = sessionScreen.mutableState
        mutationQueue(of: mutableState).sync {
            appendLines(5, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)
        wait(for: [exited], timeout: 10)
        XCTAssertEqual(lines.map { Array($0.prefix(5)) }, (0..<5).map { "output \($0)" },
                       "The posted output must have every line")
        XCTAssertFalse(lines?.contains("<missing>") ?? true, "Every output line must be readable")
    }

    /// The opposite case, with a full scrollback: lines scroll off between the
    /// FTCS D token and the side effect, and again after the side effect but
    /// before observers get the notification, which is posted asynchronously.
    /// The posted start line must still locate the command's output.
    func testCommandExitNotificationOutputAfterScrollbackOverflow() {
        let session = makeSession()
        let sessionScreen = session.screen
        setScrollback(of: session, limit: 10)
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
            // Fill the scrollback so later lines push lines off the top.
            self.appendLines(40, prefix: "filler", in: mutableState)
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
            mutableState.appendString(atCursor: "ls")
            mutableState.terminalCommandDidEnd()
            mutableState.appendCarriageReturnLineFeed()
        })
        sessionScreen.waitForQueuedTokensForTesting()

        var lines: [String]?
        let exited = expectation(forNotification: .PTYCommandDidExit,
                                 object: session.guid) { [unowned self] note in
            lines = outputLines(note)
            return true
        }
        let mutableState = sessionScreen.mutableState
        var overflowAtExit: Int64 = 0
        mutationQueue(of: mutableState).sync {
            appendLines(3, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
            overflowAtExit = mutableState.cumulativeScrollbackOverflow
            appendLines(5, prefix: "later", in: mutableState)
        }
        XCTAssertGreaterThan(mutableState.cumulativeScrollbackOverflow, overflowAtExit,
                             "Lines must scroll off between the exit and the side effect")
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: true)
        // More output and a sync before the posted notification is delivered.
        sessionScreen.performBlock(joinedThreads: { _, mutableState, _ in
            self.appendLines(5, prefix: "after", in: mutableState)
        })
        wait(for: [exited], timeout: 10)
        XCTAssertEqual(lines.map { Array($0.prefix(3)) }, (0..<3).map { "output \($0)" },
                       "The posted start line must locate the command's output")
    }

    // MARK: - Triggers

    /// The Stop Scrolling trigger passes the cursor's absolute line as of the
    /// match. PTYSession.triggerSideEffectStopScrollingAtLine clamps it to the
    /// lines its copy of the screen has rather than ignoring a line that
    /// arrived since the last sync.
    func testStopScrollingTriggerPassesCursorLine() {
        var seenLine: Int64?
        spy.onStopScrolling = { absLine in
            seenLine = absLine
        }
        var expectedLine: Int64?
        mutateThenDrainBeforeSync { mutableState in
            appendLines(40, in: mutableState)
            triggerSession(mutableState).triggerSession(Trigger(), saveCursorLineAndStopScrolling: true)
            expectedLine = absLineOfCursor(mutableState)
        }
        XCTAssertNotNil(expectedLine)
        XCTAssertEqual(seenLine, expectedLine)
    }

    /// A Fold trigger folds the lines from the named mark through the matched line, and its fold
    /// waits until the triggers for that line have all run. Triggers after it on the same line act
    /// on absolute line numbers, which the fold would otherwise shift under them: a Mark trigger on
    /// the same line must mark that line (which the fold then saves away with it), not the line
    /// that has the matched line's number once the fold has moved everything up.
    func testFoldTriggerWaitsForLaterTriggersOnTheLine() {
        harness.screen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            let config = spy.configuration
            config.triggerProfileDicts = [
                ["regex": "^START", "action": "iTermSetNamedMarkTrigger", "parameter": "top"],
                ["regex": "^END", "action": "iTermFoldTrigger", "parameter": "top"],
                ["regex": "^END", "action": "MarkTrigger", "parameter": NSNumber(value: 0)],
            ]
            config.isDirty = true
            mutableState.setConfig(config)
        })
        harness.send(Array("START\r\n".utf8))
        for i in 0..<5 {
            harness.send(Array("filler \(i)\r\n".utf8))
        }
        harness.send(Array("END\r\n".utf8))
        harness.sync()
        var placeholder: String?
        var lineAfterFold: String?
        var markedLinesAfterFold = [Int32]()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            placeholder = mutableState.screenCharArray(forLine: 0).stringValue.trimmingCharacters(in: .whitespaces)
            lineAfterFold = mutableState.screenCharArray(forLine: 1).stringValue.trimmingCharacters(in: .whitespaces)
            for line in 1..<mutableState.numberOfLines where !mutableState.objects(onLine: line, of: VT100ScreenMark.self).isEmpty {
                markedLinesAfterFold.append(line)
            }
        })
        XCTAssertEqual(placeholder, "START", "START through END fold into START’s line")
        XCTAssertEqual(lineAfterFold, "")
        XCTAssertEqual(markedLinesAfterFold, [], "The mark went with END into the fold, not onto the line with END’s old number")
    }

    /// Copy mode's cursor and the selection are placed against line numbers a fold changes, so the
    /// Fold trigger leaves copy mode before the lines move, as folding from the main thread does.
    func testFoldTriggerLeavesCopyModeBeforeFolding() {
        harness.screen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            let config = spy.configuration
            config.triggerProfileDicts = [
                ["regex": "^START", "action": "iTermSetNamedMarkTrigger", "parameter": "top"],
                ["regex": "^END", "action": "iTermFoldTrigger", "parameter": "top"],
            ]
            config.isDirty = true
            mutableState.setConfig(config)
        })
        let mutableState = harness.screen.mutableState
        var lineAfterStartWhenModeLeft: String?
        spy.onEnsureDefaultMode = {
            // Side effects run inside a join here, so the mutation thread's state can be read.
            lineAfterStartWhenModeLeft = mutableState.screenCharArray(forLine: 1).stringValue
                .trimmingCharacters(in: .whitespaces)
        }
        harness.send(Array("START\r\n".utf8))
        for i in 0..<5 {
            harness.send(Array("filler \(i)\r\n".utf8))
        }
        harness.send(Array("END\r\n".utf8))
        harness.sync()
        XCTAssertEqual(lineAfterStartWhenModeLeft, "filler 0",
                       "Copy mode must be left while the lines are still where it placed its cursor")
        var lineAfterStart: String?
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            lineAfterStart = mutableState.screenCharArray(forLine: 1).stringValue.trimmingCharacters(in: .whitespaces)
        })
        XCTAssertEqual(lineAfterStart, "", "The fold happened afterwards")
    }

    /// A control sequence that follows the matching line could change the lines about to fold, so
    /// the trigger pauses token execution until the fold has run. Text in the same token as the
    /// match is already on the screen (a token of text and newlines can only add lines after the
    /// match), but the erase that follows it is its own token and must wait: when copy mode is
    /// left, the line it erases is still there.
    func testFoldTriggerPausesLaterTokensUntilTheFold() {
        harness.screen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            let config = spy.configuration
            config.triggerProfileDicts = [
                ["regex": "^START", "action": "iTermSetNamedMarkTrigger", "parameter": "top"],
                ["regex": "^END", "action": "iTermFoldTrigger", "parameter": "top"],
            ]
            config.isDirty = true
            mutableState.setConfig(config)
        })
        let mutableState = harness.screen.mutableState
        var lineAfterEndWhenModeLeft: String?
        spy.onEnsureDefaultMode = {
            // Runs while token execution is paused, so the mutation thread's state can be read.
            lineAfterEndWhenModeLeft = mutableState.screenCharArray(forLine: 7).stringValue
                .trimmingCharacters(in: .whitespaces)
        }
        var text = "START\r\n"
        for i in 0..<5 {
            text += "filler \(i)\r\n"
        }
        // The erase (CSI 2 K) ends the text token and must not run before the fold.
        text += "END\r\nafter 0\u{1b}[2K\r\nafter 1\r\n"
        harness.send(Array(text.utf8))
        harness.sync()
        XCTAssertEqual(lineAfterEndWhenModeLeft, "after 0", "The erase after END must wait for the fold")
        var lines = [String]()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for line in 0..<3 {
                lines.append(mutableState.screenCharArray(forLine: Int32(line)).stringValue.trimmingCharacters(in: .whitespaces))
            }
        })
        XCTAssertEqual(lines, ["START", "", "after 1"], "The later tokens ran after the fold")
    }

    /// A running command's mark is the cached last command mark. Aborting the command removes the
    /// mark, so the cache must forget it, and the main thread's copy must too: the update queued
    /// when the mark was cached would otherwise run after the removal and install a mark that is
    /// no longer in the tree, and a sync would copy the stale cache over.
    func testAbortedCommandDoesNotLeaveItsMarkAsTheLastCommandMark() {
        runCommand("first")
        let first = screen.lastCommandMark()
        XCTAssertNotNil(first)
        var abortedGuid: String?
        var generation: Int?
        mutateThenDrainBeforeSync { mutableState in
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
            mutableState.appendString(atCursor: "second")
            mutableState.terminalCommandDidEnd()
            abortedGuid = mutableState.lastCommandMark?.guid
            mutableState.commandWasAborted()
            generation = (mutableState.value(forKey: "lastCommandMarkGeneration") as? NSNumber)?.intValue
        }
        XCTAssertNotNil(abortedGuid)
        XCTAssertNotEqual(abortedGuid, first?.guid, "The running command's mark was the last command mark")
        // The drain delivered the clearing too, not just the earlier update that set the mark.
        XCTAssertEqual((screen.immutableState.value(forKey: "lastCommandMarkGeneration") as? NSNumber)?.intValue,
                       generation,
                       "The main thread's copy must have seen the mark cleared")
        harness.sync()
        let after = screen.lastCommandMark()
        XCTAssertNotEqual(after?.guid, abortedGuid, "The aborted command's mark was removed")
        XCTAssertEqual(after?.guid, first?.guid)
    }

    /// Each thread fills its last command mark cache lazily and on its own, so the main thread's
    /// can hold a mark the mutation thread's doesn't. Aborting that command must still make the
    /// main thread forget the removed mark before the next sync.
    func testRemovedMarkIsForgottenByTheMainThreadWhenOnlyItCachedIt() {
        runCommand("first")
        let first = screen.lastCommandMark()
        XCTAssertNotNil(first)
        var secondGuid: String?
        mutateThenDrainBeforeSync { mutableState in
            startCommand("second", in: mutableState)
            secondGuid = mutableState.lastCommandMark?.guid
            // Something cleared this thread's cache and nothing here has read it since.
            mutableState.lastCommandMark = nil
        }
        XCTAssertNotNil(secondGuid)
        XCTAssertEqual(screen.lastCommandMark()?.guid, secondGuid,
                       "The main thread's lazy search finds the running command's mark and caches it")
        mutateThenDrainBeforeSync { mutableState in
            mutableState.commandWasAborted()
        }
        XCTAssertEqual(screen.lastCommandMark()?.guid, first?.guid,
                       "The aborted command's mark was removed, so the main thread must not keep it")
    }

    /// The same holds for any permanent removal, not just an abort: clearing the buffer removes
    /// prompt marks through the shared removal hook, which must make the main thread forget a
    /// removed mark only it had cached.
    func testMarkRemovedOutsideAnAbortIsForgottenByTheMainThread() {
        runCommand("first")
        let first = screen.lastCommandMark()
        XCTAssertNotNil(first)
        var secondGuid: String?
        mutateThenDrainBeforeSync { mutableState in
            startCommand("second", in: mutableState)
            secondGuid = mutableState.lastCommandMark?.guid
            mutableState.lastCommandMark = nil
        }
        XCTAssertNotNil(secondGuid)
        XCTAssertEqual(screen.lastCommandMark()?.guid, secondGuid,
                       "The main thread's lazy search finds the running command's mark and caches it")
        var removed = false
        mutateThenDrainBeforeSync { mutableState in
            if let mark = mutableState.lastPromptMark as? (any IntervalTreeObject) {
                removed = mutableState.removeObject(fromIntervalTree: mark)
            }
        }
        XCTAssertTrue(removed)
        XCTAssertEqual(screen.lastCommandMark()?.guid, first?.guid,
                       "The mark was removed, so the main thread must not keep it")
    }

    /// Closing a command by its aid makes its mark the last command mark. Aborting it by aid
    /// removes the mark, so both threads must forget it, as with the plain abort.
    func testAidAbortedCommandDoesNotLeaveItsMarkAsTheLastCommandMark() {
        runCommand("first")
        let first = screen.lastCommandMark()
        XCTAssertNotNil(first)
        harness.sendPromptStart(aid: "x1")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("second")
        harness.sendCommandEnd()
        harness.sync()
        XCTAssertEqual(screen.lastCommandMark()?.aid, "x1", "The running command's mark is the last command mark")
        harness.sendAbort(aid: "x1")
        harness.sync()
        XCTAssertNotEqual(screen.lastCommandMark()?.aid, "x1", "The aborted command's mark was removed")
        XCTAssertEqual(screen.lastCommandMark()?.guid, first?.guid)
    }

    /// ToolCapturedOutputView reloads from the main thread's last command mark
    /// (toolbeltLastCommandMark). If the command started since the last sync,
    /// that is still the previous command and the new captured line is missing.
    func testCaptureOutputTriggerSeesNewCommandMark() {
        runCommand("first")
        var seenGuid: String?
        var seenCount: Int?
        spy.onDidCaptureOutput = { [unowned self] in
            let mark = screen.lastCommandMark()
            seenGuid = mark?.guid
            seenCount = mark.map { capturedOutputCount($0) }
        }
        var expectedGuid: String?
        mutateThenDrainBeforeSync { mutableState in
            startCommand("second", in: mutableState)
            mutableState.appendString(atCursor: "error: something")
            mutableState.appendCarriageReturnLineFeed()
            captureOutput("error: something", in: mutableState)
            expectedGuid = mutableState.lastCommandMark?.guid
        }
        XCTAssertNotNil(expectedGuid)
        XCTAssertEqual(seenGuid, expectedGuid, "The tool must reload the command that captured output")
        XCTAssertEqual(seenCount, 1)
    }

    /// The main thread's last-command mark cache is updated by a side effect
    /// queued when the mutation thread's cache changes. A sync before the
    /// queue drains already copies the newest value, so an update queued
    /// earlier must not put back an older mark for the side effects after it.
    func testQueuedLastCommandMarkUpdateDoesNotReplaceNewerSyncedValue() {
        runCommand("first")
        let mutableState = harness.screen.mutableState
        var seenGuid: String?
        var expectedGuid: String?
        mutationQueue(of: mutableState).sync {
            startCommand("second", in: mutableState)
            mutableState.addSideEffect({ [unowned self] _ in
                seenGuid = screen.lastCommandMark()?.guid
            }, name: "observe last command mark")
            startCommand("third", in: mutableState)
            expectedGuid = mutableState.lastCommandMark?.guid
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: true)
        XCTAssertNotNil(expectedGuid)
        XCTAssertEqual(seenGuid, expectedGuid, "Side effects must see the mark the sync copied, not an older one")
    }

    /// The Fold trigger used to fold through the delegate, which read the
    /// placeholder line from the main thread's copy of the screen. Lines that
    /// arrived since the last sync weren't there yet. Now the range is fixed
    /// on the mutation thread, where the lines are, and the fold runs there
    /// once the side effect that leaves copy mode has sent it back.
    func testFoldTriggerFoldsLinesThatArrivedSinceTheLastSync() {
        var linesBefore: Int32 = 0
        var linesAfter: Int32 = 0
        var placeholder: String?
        var lineAfterFold: String?
        mutateThenDrainBeforeSync { mutableState in
            appendLines(40, in: mutableState)
            linesBefore = mutableState.numberOfLines
            let overflow = mutableState.cumulativeScrollbackOverflow
            triggerSession(mutableState).triggerSession(Trigger(), addNamedMarkWithName: "start", atAbsoluteLine: overflow + 30)
            triggerSession(mutableState).triggerSession(Trigger(), foldFromNamedMark: "start", toAbsoluteLine: overflow + 35)
        }
        // Runs the fold the drained side effect sent back to the mutation thread.
        harness.sync()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            linesAfter = mutableState.numberOfLines
            placeholder = mutableState.screenCharArray(forLine: 30).stringValue.trimmingCharacters(in: .whitespaces)
            lineAfterFold = mutableState.screenCharArray(forLine: 31).stringValue.trimmingCharacters(in: .whitespaces)
        })
        XCTAssertEqual(linesAfter, linesBefore - 5, "Lines 30 through 35 fold into one")
        XCTAssertEqual(placeholder, "line 30", "The fold placeholder must be the first folded line")
        XCTAssertEqual(lineAfterFold, "line 36", "The first line after the fold must follow the placeholder")
    }

    // MARK: - Auto composer

    /// The auto composer is placed using the main thread's cursor position and
    /// scrollback size (PTYSession's composer frame computation). They must
    /// include the prompt that caused the reveal, not the state from before it.
    func testRevealComposerSeesCurrentCursorAndScrollback() {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let config = VT100MutableScreenConfiguration()
            config.autoComposerEnabled = true
            mutableState.setConfig(config)
        })
        harness.sync()
        var seen: [Int64]?
        spy.onRevealComposer = { [unowned self] in
            // The prompt state machine may also reveal the composer at prompt
            // start. Keep the last reveal, which is the one after the prompt.
            seen = [Int64(screen.cursorY()),
                    Int64(screen.numberOfScrollbackLines()) + screen.totalScrollbackOverflow()]
        }
        var expected: [Int64]?
        mutateThenDrainBeforeSync { mutableState in
            appendLines(40, in: mutableState)
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
            (mutableState as AnyObject as! PromptStateMachineDelegate).promptStateMachineRevealComposer(prompt: [])
            expected = [Int64(mutableState.cursorY),
                        Int64(mutableState.numberOfScrollbackLines) + mutableState.cumulativeScrollbackOverflow]
        }
        XCTAssertNotNil(expected)
        XCTAssertEqual(seen, expected, "The composer must be placed using the current cursor and scrollback")
    }

    // MARK: - Selection in scroll regions

    /// The selection moves with a scrolling region, located by its absolute top
    /// row. That row must count lines that went into scrollback since the last
    /// sync, which the main thread's copy doesn't. Here CSI S scrolls a region.
    func testScrollUpInRegionUsesCurrentScrollback() {
        var seenOffset: Int64?
        spy.onMoveSelectionUp = { _, region, regionAbsTop in
            seenOffset = regionAbsTop - Int64(region.origin.y)
        }
        var expectedOffset: Int64?
        mutateThenDrainBeforeSync { mutableState in
            appendLines(40, in: mutableState)
            execute("\u{1b}[5;10r\u{1b}[2S", in: mutableState)
            expectedOffset = Int64(mutableState.numberOfScrollbackLines) + mutableState.cumulativeScrollbackOverflow
        }
        XCTAssertNotNil(expectedOffset)
        XCTAssertEqual(seenOffset, expectedOffset)
    }

    /// Same as testScrollUpInRegionUsesCurrentScrollback, for a linefeed at
    /// the bottom of the scroll region.
    func testLinefeedInRegionUsesCurrentScrollback() {
        var seenOffset: Int64?
        spy.onMoveSelectionUp = { _, region, regionAbsTop in
            seenOffset = regionAbsTop - Int64(region.origin.y)
        }
        var expectedOffset: Int64?
        mutateThenDrainBeforeSync { mutableState in
            appendLines(40, in: mutableState)
            execute("\u{1b}[5;10r\u{1b}[10;1H\n", in: mutableState)
            expectedOffset = Int64(mutableState.numberOfScrollbackLines) + mutableState.cumulativeScrollbackOverflow
        }
        XCTAssertNotNil(expectedOffset)
        XCTAssertEqual(seenOffset, expectedOffset)
    }

    // MARK: - OSC 1337 sequences

    /// OSC 1337 ; ClearCapturedOutput increments the clear count of the
    /// mutation thread's last command mark. ToolCapturedOutputView compares
    /// the clear count of the main thread's last command mark, so if the
    /// command started since the last sync it checks the wrong mark.
    func testClearCapturedOutputSeesClearedMark() {
        runCommand("first")
        var seenGuid: String?
        var seenClearCount: UInt?
        spy.onClearCapturedOutput = { [unowned self] in
            let mark = screen.lastCommandMark()
            seenGuid = mark?.guid
            seenClearCount = mark.map { UInt($0.clearCount) }
        }
        var expectedGuid: String?
        mutateThenDrainBeforeSync { mutableState in
            startCommand("second", in: mutableState)
            captureOutput("error: something", in: mutableState)
            execute("\u{1b}]1337;ClearCapturedOutput\u{07}", in: mutableState)
            expectedGuid = mutableState.lastCommandMark?.guid
        }
        XCTAssertNotNil(expectedGuid)
        XCTAssertEqual(seenGuid, expectedGuid, "The tool must check the mark that was cleared")
        XCTAssertEqual(seenClearCount, 1)
    }

    /// OSC 1337 ; UpdateBlock=id=...;action=fold. PTYTextView.foldBlock: finds
    /// the block's range and reads its lines from the main thread's copy of
    /// the screen, which doesn't have a block that arrived since the last sync.
    func testUpdateBlockFoldSeesBlock() {
        var seenRange: [Int32]?
        var seenFirstLine: String?
        spy.onUpdateBlock = { [unowned self] blockID, _ in
            let range = screen.rangeOfBlock(withID: blockID)
            seenRange = lines(range)
            seenFirstLine = range.start.x >= 0 ? text(onLine: range.start.y) : "<missing>"
        }
        var expectedRange: [Int32]?
        mutateThenDrainBeforeSync { mutableState in
            appendLines(40, in: mutableState)
            execute("\u{1b}]1337;Block=id=b1;attr=start\u{07}", in: mutableState)
            appendLines(3, prefix: "block", in: mutableState)
            execute("\u{1b}]1337;Block=id=b1;attr=end\u{07}", in: mutableState)
            execute("\u{1b}]1337;UpdateBlock=id=b1;action=fold\u{07}", in: mutableState)
            expectedRange = lines(mutableState.rangeOfBlock(withID: "b1"))
        }
        XCTAssertNotNil(expectedRange)
        XCTAssertEqual(seenRange, expectedRange)
        XCTAssertEqual(seenFirstLine, "block 0")
    }

    /// OSC 1337 ; SetKeyLabel=status=... PTYSession records the cursor's
    /// absolute line for “jump to status change”. The main thread's copy of
    /// the screen may not have that line yet, so it is passed in.
    func testStatusKeyLabelRecordsCurrentCursorLine() {
        var seenLine: Int64?
        spy.onSetLabel = { _, key, absLineOfCursor in
            guard key == "status" else {
                return
            }
            seenLine = absLineOfCursor
        }
        var expectedLine: Int64?
        mutateThenDrainBeforeSync { mutableState in
            appendLines(40, in: mutableState)
            execute("\u{1b}]1337;SetKeyLabel=status=busy\u{07}", in: mutableState)
            expectedLine = absLineOfCursor(mutableState)
        }
        XCTAssertNotNil(expectedLine)
        XCTAssertEqual(seenLine, expectedLine)
    }

    // MARK: - Logging

    /// Logged text must be encoded with the encoding in effect when it arrived.
    /// After ESC % @ (select Latin-1), the main thread's copy still has the old
    /// one until the next sync.
    func testLoggingUsesEncodingInEffectWhenTextArrived() {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let config = VT100MutableScreenConfiguration()
            config.loggingEnabled = true
            mutableState.setConfig(config)
            mutableState.terminal!.encoding = String.Encoding.utf8.rawValue
        })
        harness.sync()
        var seenEncoding: UInt?
        spy.onAppendString = { _, encoding in
            seenEncoding = encoding
        }
        var expectedEncoding: UInt?
        mutateThenDrainBeforeSync { mutableState in
            execute("\u{1b}%@", in: mutableState)
            expectedEncoding = mutableState.terminal!.encoding
            execute("é", in: mutableState)
        }
        XCTAssertEqual(expectedEncoding, String.Encoding.isoLatin1.rawValue)
        XCTAssertEqual(seenEncoding, expectedEncoding)
    }

    // MARK: - Prompt notifications

    /// OSC 133 ; B. The prompt notification falls back to the current command
    /// when the mark has none. The main thread's copy of the command range
    /// still holds the previous command's text when it ran entirely since the
    /// last sync, so the command is passed in.
    func testPromptEndSeesCurrentCommandRange() {
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("previous")
        harness.sync()
        var seenCommand: String??
        var seenCursorLine: Int64?
        spy.onPromptDidEnd = { _, command, cursor, _, _ in
            seenCommand = .some(command)
            seenCursorLine = cursor.y
        }
        var expectedCommand: String??
        var expectedCursorLine: Int64?
        mutateThenDrainBeforeSync { mutableState in
            mutableState.terminalCommandDidEnd()
            mutableState.appendCarriageReturnLineFeed()
            appendLines(3, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
            expectedCommand = .some(mutableState.command(in: mutableState.commandRange))
            expectedCursorLine = absLineOfCursor(mutableState)
        }
        XCTAssertNotNil(expectedCommand)
        XCTAssertEqual(seenCommand, expectedCommand)
        XCTAssertEqual(seenCursorLine, expectedCursorLine, "The cursor must be where it was when the prompt ended")
        XCTAssertNotEqual(seenCommand, .some("previous"), "The previous command must not be reported")
    }

    /// A prompt taller than four lines is recorded as its last four lines. The
    /// clamp used to set both ends of the range to line 4, so the prompt's text
    /// was line 4's and the directory reported with the prompt was whatever
    /// was in effect there.
    func testTallPromptKeepsItsLastLinesAndDirectory() {
        var seenDirectory: String??
        spy.onPromptDidEnd = { _, _, _, directory, _ in
            seenDirectory = .some(directory)
        }
        var promptEnd: Int64?
        var markEnd: Int64?
        var promptText: [String]?
        mutateThenDrainBeforeSync { mutableState in
            appendLines(30, in: mutableState)
            mutableState.setWorkingDirectory("/old", onAbsLine: 4, pushed: true, token: nil)
            // The prompt starts after a status glyph, so its range starts past the first column.
            mutableState.appendString(atCursor: "ab ")
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: false, aid: nil)
            mutableState.setWorkingDirectory("/prompt", onAbsLine: absLineOfCursor(mutableState), pushed: true, token: nil)
            appendLines(6, prefix: "prompt", in: mutableState)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
            promptEnd = absLineOfCursor(mutableState)
            // The mutation thread's mark: the main thread's twin is updated by a sync.
            let mark = mutableState.lastPromptMark
            markEnd = mark?.promptRange.end.y
            promptText = (mark?.promptText ?? []).map { $0.stringValue.trimmingCharacters(in: .whitespaces) }
        }
        XCTAssertNotNil(promptEnd)
        XCTAssertEqual(markEnd, promptEnd)
        XCTAssertEqual(promptText, ["prompt 3", "prompt 4", "prompt 5", "$"],
                       "The last four lines of the prompt, whole, up to the command")
        XCTAssertEqual(seenDirectory, .some("/prompt"))
    }

    /// The text of a prompt is logged in the terminal's encoding when the prompt ended. The main
    /// thread's copy of the encoding is from before a change made since the last sync.
    func testPromptEndPassesTheEncodingInEffect() {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminal!.encoding = String.Encoding.utf8.rawValue
        })
        harness.sync()
        var seenEncoding: UInt?
        spy.onPromptDidEnd = { _, _, _, _, encoding in
            seenEncoding = encoding
        }
        let changed = String.Encoding.isoLatin1.rawValue
        mutateThenDrainBeforeSync { mutableState in
            mutableState.terminal!.encoding = changed
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
        }
        XCTAssertNotEqual(screen.terminalEncoding, changed, "The main thread must not have the new encoding yet")
        XCTAssertEqual(seenEncoding, changed)
    }

    // MARK: - Capturing output only for consumers

    /// Only a session something consumes output from captures it. The mutation thread asks the
    /// registry when the command ends, so a consumer that came or went since the last sync counts,
    /// with no hand-off between the threads.
    func testOutputIsCapturedOnlyWhileTheSessionHasAConsumer() {
        let unwatched = makeSession(consumer: false)
        let watched = makeSession()
        XCTAssertFalse(commandExitHasOutput(in: unwatched))
        XCTAssertTrue(commandExitHasOutput(in: watched))
        consumers = []
        XCTAssertFalse(commandExitHasOutput(in: watched), "The consumer is gone")
    }

    /// A consumer is registered under a guid or stable ID. When the guid changes (a shell restart
    /// rotates it), whether the session captures output follows the new guid.
    func testCaptureFollowsTheGuid() {
        let session = makeSession()
        XCTAssertTrue(commandExitHasOutput(in: session))
        let newGuid = UUID().uuidString
        session.perform(NSSelectorFromString("setGuid:"), with: newGuid)
        XCTAssertFalse(commandExitHasOutput(in: session), "The consumer was registered under the old guid")
        consumers.append(CommandOutput.addConsumer(forSessionReference: newGuid))
        XCTAssertTrue(commandExitHasOutput(in: session))
    }

    /// A consumer registered under the session's stable ID, as AI Chat does, counts too.
    func testCaptureFollowsTheStableID() {
        let session = makeSession(consumer: false)
        XCTAssertFalse(commandExitHasOutput(in: session))
        consumers.append(CommandOutput.addConsumer(forSessionReference: session.stableID))
        XCTAssertTrue(commandExitHasOutput(in: session))
    }

    /// A consumer can be released off the main thread, when a background
    /// completion drops the last reference. The registration ends right there.
    func testConsumerReleasedOffTheMainThreadUnregisters() {
        let reference = UUID().uuidString
        var consumer: CommandOutputConsumer? = CommandOutput.addConsumer(forSessionReference: reference)
        XCTAssertTrue(CommandOutput.hasConsumers(forSessionReferences: [reference]))
        let released = expectation(description: "released")
        DispatchQueue.global().async {
            // Nothing else holds it, so this releases it off the main thread.
            consumer = nil
            released.fulfill()
        }
        wait(for: [released], timeout: 10)
        XCTAssertFalse(CommandOutput.hasConsumers(forSessionReferences: [reference]))
    }

    /// A command that ends while nothing consumes the session's output is
    /// posted without the output keys. The consumers' decoder reports no
    /// output, instead of crashing or dropping the
    /// command.
    func testCommandExitNotificationWithoutOutputDecodes() {
        let session = makeSession(consumer: false)
        let sessionScreen = session.screen
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
            startCommand("ls", in: mutableState)
        })
        var decoded: CommandExitNotification?
        var hadDataSource = true
        let exited = expectation(forNotification: .PTYCommandDidExit, object: session.guid) { note in
            let userInfo = note.userInfo ?? [:]
            hadDataSource = userInfo[PTYCommandDidExitUserInfoKeyDataSource] != nil
            decoded = CommandExitNotification(userInfo: userInfo)
            return true
        }
        let mutableState = sessionScreen.mutableState
        mutationQueue(of: mutableState).sync {
            appendLines(2, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)
        wait(for: [exited], timeout: 10)
        XCTAssertFalse(hadDataSource, "Nothing consumes this session's output, so none is captured")
        XCTAssertEqual(decoded?.command, "ls")
        XCTAssertNil(decoded?.output, "A consumer that registered after the command ended skips it")
    }

    /// An aborted command has no exit status. It must decode as none, not as 0, which would tell
    /// the AI the command succeeded.
    func testAbortedCommandDecodesWithoutAnExitCode() {
        let session = makeSession()
        let sessionScreen = session.screen
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
            startCommand("ls", in: mutableState)
        })
        var decoded: CommandExitNotification?
        let exited = expectation(forNotification: .PTYCommandDidExit, object: session.guid) { note in
            decoded = CommandExitNotification(userInfo: note.userInfo ?? [:])
            return true
        }
        let mutableState = sessionScreen.mutableState
        mutationQueue(of: mutableState).sync {
            mutableState.commandWasAborted()
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)
        wait(for: [exited], timeout: 10)
        XCTAssertEqual(decoded?.command, "ls")
        XCTAssertNil(decoded?.exitCode, "Aborted, so no exit status")
    }

    /// A command that exited decodes with its status.
    func testExitedCommandDecodesWithItsExitCode() {
        let userInfo: [AnyHashable: Any] = [
            PTYCommandDidExitUserInfoKeyCommand: "false",
            PTYCommandDidExitUserInfoKeyURL: URL(string: "iterm2:///command")!,
            PTYCommandDidExitUserInfoKeyExitCode: NSNumber(value: Int32(3)),
        ]
        XCTAssertEqual(CommandExitNotification(userInfo: userInfo)?.exitCode, 3)
    }

    /// Only the last lines of a long output are kept. The notification says
    /// how many were left out, and the decoded text starts by saying so.
    func testCommandExitNotificationNotesOmittedLines() {
        let session = makeSession()
        let sessionScreen = session.screen
        setScrollback(of: session, limit: nil)
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
            startCommand("ls", in: mutableState)
        })
        var decoded: CommandExitNotification?
        var dropped: Int32?
        let exited = expectation(forNotification: .PTYCommandDidExit, object: session.guid) { note in
            let userInfo = note.userInfo ?? [:]
            dropped = (userInfo[PTYCommandDidExitUserInfoKeyDroppedLineCount] as? NSNumber)?.int32Value
            decoded = CommandExitNotification(userInfo: userInfo)
            return true
        }
        let mutableState = sessionScreen.mutableState
        mutationQueue(of: mutableState).sync {
            appendLines(Int(CommandOutput.maxLines) + 50, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)
        wait(for: [exited], timeout: 10)
        guard let dropped, dropped > 0 else {
            XCTFail("Leading lines must be dropped: \(String(describing: dropped))")
            return
        }
        let expectedPrefix = CommandExitNotification.omittedLinesNote(dropped) + "\noutput \(dropped)\n"
        XCTAssertEqual(decoded?.output?.prefix(expectedPrefix.count).description, expectedPrefix,
                       "The text must say how many lines were left out, then continue with the first kept line")
    }

    // MARK: - GetPrompt

    /// GetPrompt reports the working directory of the prompt's line. The
    /// mark's prompt range is absolute while the directory lookup takes a line
    /// of the current contents, so once lines have scrolled off, the two
    /// numberings differ and the directory of a later line was reported.
    func testGetPromptResponseReportsDirectoryOfPromptLineAfterOverflow() {
        let session = makeSession(consumer: false)
        let sessionScreen = session.screen
        setScrollback(of: session, limit: 10)
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
            appendLines(40, prefix: "filler", in: mutableState)
            let promptAbsLine = absLineOfCursor(mutableState)
            mutableState.setWorkingDirectory("/prompt", onAbsLine: promptAbsLine, pushed: true, token: nil)
            startCommand("ls", in: mutableState)
            // As if the command changed directory on its second line of output. (A directory set
            // at the start of a line also counts as being on the line before it.)
            appendLines(1, prefix: "output", in: mutableState)
            mutableState.setWorkingDirectory("/output", onAbsLine: promptAbsLine + 2, pushed: true, token: nil)
            appendLines(2, prefix: "output", in: mutableState)
        })
        XCTAssertGreaterThan(sessionScreen.totalScrollbackOverflow(), 1, "Lines must have scrolled off")
        guard let mark = sessionScreen.lastPromptMark() else {
            XCTFail("No prompt mark")
            return
        }
        let response = session.perform(NSSelectorFromString("getPromptResponseForMark:"), with: mark)?
            .takeUnretainedValue() as? NSObject
        XCTAssertEqual(response?.value(forKey: "workingDirectory") as? String, "/prompt")
    }

    /// The note shown above the output agrees in number with the count. It comes from the string
    /// catalog's plural (the test host is the app, whose bundle has the compiled catalog), so this
    /// fails if the catalog entry loses its plural variations.
    func testOmittedLinesNoteAgreesInNumber() {
        XCTAssertEqual(CommandExitNotification.omittedLinesNote(1), "[1 earlier line of output omitted.]")
        XCTAssertEqual(CommandExitNotification.omittedLinesNote(2), "[2 earlier lines of output omitted.]")
    }

    /// Until its first sync loads the configuration a session has no guid. That is no reference
    /// at all, not an empty one: a consumer registered under an empty guid must not have every
    /// such session capture its output.
    func testSessionWithoutAGuidMatchesNoConsumer() {
        harness.screen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            let config = spy.configuration
            config.setValue(nil, forKey: "sessionGuid")
            config.isDirty = true
            mutableState.setConfig(config)
        })
        consumers.append(CommandOutput.addConsumer(forSessionReference: ""))
        runCommand("ls", finished: false)
        var exited = false
        var output: CommandOutput?
        spy.onCommandDidExit = { mark, captured in
            guard mark != nil else {
                return
            }
            exited = true
            output = captured
        }
        mutateThenDrainBeforeSync { mutableState in
            appendLines(1, prefix: "output", in: mutableState)
            mutableState.terminalReturnCode(ofLastCommandWas: 0, aid: nil)
        }
        XCTAssertTrue(exited)
        XCTAssertNil(output, "No reference, so nothing to match the empty-string consumer")
    }

    // MARK: - Folding

    /// Folding declines while an app owns the alternate screen, from the main thread (PTYTextView)
    /// as much as from the Fold trigger: the lines there are the app's, not scrollback.
    func testFoldFromTheMainThreadDeclinesInTheAlternateScreen() {
        harness.send(Array("\u{1b}[?1049h".utf8))
        for line in ["a", "b", "c"] {
            harness.send(Array("\(line)\r\n".utf8))
        }
        harness.sync()
        screen.foldAbsLineRange(NSRange(location: 0, length: 1))
        harness.sync()
        XCTAssertEqual(text(onLine: 0), "a")
        XCTAssertEqual(text(onLine: 1), "b", "A fold would have folded a and b into one line")
        XCTAssertEqual(text(onLine: 2), "c")
    }

    /// A consumer can come or go from inside a side effect, for example one
    /// that closes the session hosting a chat. The mutation thread sees the
    /// change at once when it next asks, with no join.
    func testConsumerChangeInsideASideEffectIsSeenByTheMutationThread() {
        let session = makeSession(consumer: false)
        let sessionScreen = session.screen
        let mutableState = sessionScreen.mutableState
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
        })
        let queue = mutationQueue(of: mutableState)
        let references = [session.guid]
        var consumer: CommandOutputConsumer?
        queue.sync {
            mutableState.addSideEffect({ _ in
                consumer = CommandOutput.addConsumer(forSessionReference: session.guid)
            }, name: "add consumer")
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)
        XCTAssertNotNil(consumer)
        XCTAssertTrue(queue.sync { CommandOutput.hasConsumers(forSessionReferences: references) })

        queue.sync {
            mutableState.addSideEffect({ _ in
                consumer = nil
            }, name: "remove consumer")
        }
        mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)
        XCTAssertNil(consumer)
        XCTAssertFalse(queue.sync { CommandOutput.hasConsumers(forSessionReferences: references) })
    }

    /// The scroll for a Stop Scrolling match waits for the sync after the
    /// match, which brings the matched line. A line the sync still doesn't
    /// have is dropped rather than left pending, or a later change in the
    /// line count would scroll to whatever then sits at that line.
    func testPendingStopScrollingLineIsDroppedAfterASync() {
        let session = makeSession(consumer: false)
        let sessionScreen = session.screen
        sessionScreen.performBlock(joinedThreads: { [unowned self] _, mutableState, _ in
            setUpTerminal(mutableState, of: sessionScreen)
        })
        let absent = Int64(sessionScreen.numberOfLines()) + 100
        session.triggerSideEffectStopScrolling(atLine: absent)
        XCTAssertEqual(session.value(forKey: "stopScrollingAbsLine") as? Int64, absent,
                       "The scroll waits for the next sync")
        session.sync()
        XCTAssertEqual(session.value(forKey: "stopScrollingAbsLine") as? Int64, -1,
                       "Nothing stays pending after a sync")
    }

    /// Text extraction probes the lines around the output while range
    /// checking. Each probe reads as the same empty line rather than a new one.
    func testCommandOutputSharesOneEmptyLine() {
        let output = CommandOutput(lines: [],
                                   startLine: 5,
                                   droppedLineCount: 0,
                                   width: 10,
                                   overflow: 0,
                                   remoteHost: nil,
                                   workingDirectory: nil)
        let before = output.screenCharArray(forLine: 0)
        XCTAssertEqual(before.length, 10)
        XCTAssertTrue(before === output.screenCharArray(forLine: 99))
    }
}

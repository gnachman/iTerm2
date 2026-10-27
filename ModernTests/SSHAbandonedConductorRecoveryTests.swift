//
//  SSHAbandonedConductorRecoveryTests.swift
//  iTerm2
//
//  F-354: when only the local it2ssh is killed, its ssh client keeps running and its
//  remote conductor keeps printing framer output (e.g., an autopoll report). Once the
//  user chooses Disconnect and the hook is forced off, that OSC 134 output arrived
//  outside any hook and started framer recovery, which typed base64 "recover" into the
//  local shell and left a recovery conductor holding the keyboard. A disconnected
//  connection's framer output must instead be ignored, and anything else it prints drawn.
//

import XCTest
@testable import iTerm2SharedARC

// Records everything the session would send to its pty without sending it.
private final class WriteCapturingSession: PTYSession {
    var writes = [String]()

    override func writeTaskNoBroadcast(_ string: String,
                                       encoding optionalEncoding: UInt,
                                       forceEncoding: Bool,
                                       reporting: Bool) {
        writes.append(string)
    }

    override func writeTask(_ string: String) {
        writes.append(string)
    }
}

@MainActor
final class SSHAbandonedConductorRecoveryTests: XCTestCase {
    private var session: WriteCapturingSession!
    private let rootID = "1234567890"
    private let nestedID = "555"
    private let recover = "recover".data(using: .utf8)!.base64EncodedString()

    override func setUp() {
        super.setUp()
        session = WriteCapturingSession(synthetic: false)
        let screen = session.screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            screen.destructivelySetScreenWidth(80, height: 24, mutableState: mutableState)
        })
    }

    override func tearDown() {
        session = nil
        super.tearDown()
    }

    // MARK: - Helpers

    // Feeds bytes through the session's own parser, as the pty would, executes the
    // tokens synchronously, and runs the resulting side effects.
    private func send(_ bytes: [UInt8]) {
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            guard let terminal else {
                return
            }
            bytes.withUnsafeBufferPointer { buf in
                terminal.parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
            }
            var vector = CVector()
            CVectorCreate(&vector, 100)
            _ = terminal.parser.addParsedTokens(to: &vector)
            for i in 0..<CVectorCount(&vector) {
                let token = CVectorGetObject(&vector, i) as! VT100Token
                terminal.execute(token)
            }
            CVectorDestroy(&vector)
        })
        sync()
    }

    private func send(_ string: String) {
        send(Array(string.utf8))
    }

    private func sync() {
        // Twice, so side effects that schedule more mutation get to finish.
        session.screen.performBlock(joinedThreads: { _, _, _ in })
        session.screen.performBlock(joinedThreads: { _, _, _ in })
    }

    private func osc134(_ payload: String) -> String {
        return "\u{1b}]134;:\(payload)\u{1b}\\"
    }

    private func hook(uniqueID: String) -> String {
        // token, it2ssh unique ID, boolean args (base64), separator, ssh args (base64).
        return "\u{1b}P2000pnone \(uniqueID) Ym9vbA== - ZXhhbXBsZS5jb20=\n"
    }

    // What the orphaned ssh client's remote conductor prints about once a second.
    private func autopollReport(id: String) -> String {
        return osc134("%autopoll \(id)") +
            "$begin ps\r\n" +
            "  PID COMMAND\r\n" +
            "$begin cpu\r\n" +
            "=1.14%\r\n" +
            osc134("%end \(id)")
    }

    private func screenText() -> String {
        return session.screen.compactLineDumpWithHistory()
    }

    private func forceUnhook(_ dcsID: String) {
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertTrue(terminal?.parser.forceUnhookDCSReturningSuccess(dcsID) ?? false)
        })
    }

    private func hookRoot() -> Conductor? {
        send(hook(uniqueID: rootID))
        let conductor = session.conductor
        XCTAssertNotNil(conductor)
        XCTAssertEqual(conductor?.clientUniqueID, rootID)
        session.writes.removeAll()
        return conductor
    }

    // Disconnect, followed by what its forced unhook does 3 seconds later when nothing
    // answers the quit.
    private func disconnect(_ conductor: Conductor?) {
        let dcsID = conductor?.dcsID ?? ""
        conductor?.quit()
        sync()
        forceUnhook(dcsID)
        session.writes.removeAll()
    }

    private func assertNothingWritten(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(session.writes, [], file: file, line: line)
    }

    private func assertRecoveryNotStarted(file: StaticString = #filePath, line: UInt = #line) {
        assertNothingWritten(file: file, line: line)
        XCTAssertFalse(screenText().contains("Recovering"), screenText(), file: file, line: line)
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertEqual(terminal?.framerRecoveryMode, VT100TerminalFramerRecoveryMode.none,
                           file: file, line: line)
        })
    }

    // MARK: - Tests

    // F-864: a connection that aborted is gone, but its it2ssh still prints EndSSH and waits for
    // a newline before giving the terminal back, as after a quit. An EndSSH nobody here started
    // is not answered: anything printed to the terminal can contain one.
    func testEndSSHAfterAnAbortIsAnswered() {
        let conductor = hookRoot()
        // PTYSession adopts the delegate protocol privately, in its implementation.
        _ = session.perform(NSSelectorFromString("conductorAbortWithReason:"), with: "test")
        if let dcsID = conductor?.dcsID {
            session.screen.performBlock(joinedThreads: { terminal, _, _ in
                _ = terminal?.parser.forceUnhookDCSReturningSuccess(dcsID)
            })
        }
        XCTAssertNil(session.conductor)
        session.writes.removeAll()
        send("\u{1b}]1337;EndSSH=777\u{07}")
        XCTAssertEqual(session.writes, [], "not this session's it2ssh")
        send("\u{1b}]1337;EndSSH=\(rootID)\u{07}")
        XCTAssertEqual(session.writes, ["\u{3}\n"])
    }

    // The control: framer output outside any hook for a connection that wasn't abandoned
    // (e.g., the parser lost sync) still starts recovery.
    func testUnhookedFramerOutputStillRecoversLiveConnection() {
        let conductor = hookRoot()
        forceUnhook(conductor?.dcsID ?? "")
        send(autopollReport(id: "9001"))
        XCTAssertTrue(session.writes.contains { $0.contains(recover) }, "\(session.writes)")
    }

    func testDisconnectedConnectionsFramerOutputDoesNotStartRecovery() {
        let conductor = hookRoot()
        disconnect(conductor)
        XCTAssertNil(session.conductor)

        send(autopollReport(id: "9001"))
        send("local% ")
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor)
        XCTAssertTrue(screenText().contains("local% "), screenText())
    }

    // Disconnect works before the framer starts, as when it2ssh is killed during setup: it
    // sends the pre-framer quit instead of refusing, the session lets go of the conductor,
    // and once the hook is forced off the local shell's output is drawn.
    func testDisconnectBeforeFramerStartsEndsConnection() {
        let conductor = hookRoot()
        XCTAssertEqual(conductor?.framing, false)
        let dcsID = conductor?.dcsID ?? ""
        session.textViewDisconnectSSH()
        sync()
        XCTAssertNil(session.conductor)
        let quit = "quit".data(using: .utf8)!.base64EncodedString()
        XCTAssertTrue(session.writes.contains { $0.contains(quit) }, "\(session.writes)")
        forceUnhook(dcsID)
        session.writes.removeAll()

        send(autopollReport(id: "9001"))
        send("local% ")
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor)
        XCTAssertTrue(screenText().contains("local% "), screenText())
    }

    // F-950: on a host without the framer's Python, conductor.sh unhooks and runs the login
    // shell, and then nothing reads conductor commands. The pre-framer quit would type a ^C
    // and a line of base64 into the remote shell and its foreground job. Disconnect is
    // unavailable then and writes nothing; the connection ends with ssh, through EndSSH.
    func testDisconnectAfterLoginWithoutFramerWritesNothing() {
        let conductor = hookRoot()
        XCTAssertEqual(conductor?.canQuit, true)
        XCTAssertTrue(session.textViewCanDisconnectSSH())
        // What conductor.sh prints before it execs the login shell.
        send("\u{1b}]135;:unhook\u{1b}\\")
        XCTAssertTrue(session.conductor === conductor)
        XCTAssertEqual(conductor?.framing, false)
        XCTAssertFalse(session.textViewCanDisconnectSSH())
        session.writes.removeAll()

        session.textViewDisconnectSSH()
        sync()
        assertNothingWritten()
        XCTAssertTrue(session.conductor === conductor)

        // Should Disconnect be chosen some other way, quit still writes nothing.
        conductor?.quit()
        sync()
        assertNothingWritten()
        XCTAssertNil(session.conductor)
    }

    // F-970: iTerm2 restarted and reattached to a job whose ssh died while it was down, so
    // the restored SSH Integration state is forgotten. The dead connection's unread framer
    // output then arrives outside any hook. It must not start recovery, which typed base64
    // “recover” into the local shell and left a recovery conductor holding the keyboard.
    func testUnreadFramerOutputAfterRestoreWithoutSSHDoesNotRecover() {
        _ = hookRoot()
        // PTYSession declares it in its implementation.
        _ = session.perform(NSSelectorFromString("forgetRestoredConductorWhoseSSHEnded"))
        sync()
        XCTAssertNil(session.conductor)
        session.writes.removeAll()

        send(autopollReport(id: "9001"))
        send("local% ")
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor)
        XCTAssertTrue(screenText().contains("local% "), screenText())

        // A new connection may recover again.
        send(hook(uniqueID: "4321"))
        XCTAssertEqual(session.conductor?.clientUniqueID, "4321")
    }

    // A new connection's framer output is its own, so it may recover again.
    func testNewConnectionAfterDisconnectCanRecover() {
        disconnect(hookRoot())

        send(hook(uniqueID: "777"))
        let conductor = session.conductor
        XCTAssertEqual(conductor?.clientUniqueID, "777")
        forceUnhook(conductor?.dcsID ?? "")
        session.writes.removeAll()
        send(autopollReport(id: "9001"))
        XCTAssertTrue(session.writes.contains { $0.contains(recover) }, "\(session.writes)")
    }

    // The nested control: unhooked framer output from a nested connection that wasn't
    // abandoned still starts recovery for it.
    func testUnhookedNestedFramerOutputStillRecoversLiveConnection() {
        _ = hookRoot()
        send(osc134("%output out1 100 -1 0") + hook(uniqueID: nestedID) + osc134("%end out1"))
        let nested = session.conductor
        XCTAssertEqual(nested?.clientUniqueID, nestedID)
        forceUnhook(nested?.dcsID ?? "")
        session.writes.removeAll()
        send(osc134("%output out2 100 -1 0") + autopollReport(id: "9001") + osc134("%end out2"))
        XCTAssertFalse(session.writes.isEmpty)
        XCTAssertTrue(screenText().contains("Recovering"), screenText())
    }

    // A nested connection's orphaned framer prints through its parent's framing. The
    // parent stays connected and no recovery starts for the disconnected child.
    func testDisconnectedNestedConnectionsFramerOutputDoesNotStartRecovery() {
        let root = hookRoot()
        send(osc134("%output out1 100 -1 0") + hook(uniqueID: nestedID) + osc134("%end out1"))
        XCTAssertEqual(session.conductor?.clientUniqueID, nestedID)
        disconnect(session.conductor)
        XCTAssertTrue(session.conductor === root)

        send(osc134("%output out2 100 -1 0") + autopollReport(id: "9001") + osc134("%end out2"))
        send(osc134("%output out3 100 -1 0") + "hostA% " + osc134("%end out3"))
        assertRecoveryNotStarted()
        XCTAssertTrue(session.conductor === root)
        XCTAssertTrue(screenText().contains("$begin ps"), screenText())
        XCTAssertTrue(screenText().contains("hostA% "), screenText())
    }
}


// MARK: - F-459: disconnecting while the remote streams output

// When it2ssh is killed while the remote is streaming output, the session has framed
// output queued at every stage: bytes not yet parsed, tokens parsed (with the old
// framing's depths) but not yet executed, and side effects requested but not yet
// performed. Nothing in any of them may start recovery, start a conductor, or write to
// the shell once the user chooses Disconnect.
@MainActor
final class SSHAbandonedStreamingConductorRecoveryTests: XCTestCase {
    private var session: WriteCapturingSession!
    private let rootID = "1234567890"
    private let nestedID = "555"
    private let recover = "recover".data(using: .utf8)!.base64EncodedString()

    override func setUp() {
        super.setUp()
        session = WriteCapturingSession(synthetic: false)
        let screen = session.screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            screen.destructivelySetScreenWidth(80, height: 24, mutableState: mutableState)
        })
    }

    override func tearDown() {
        session = nil
        super.tearDown()
    }

    // MARK: - Helpers

    // Parses bytes the way the pty reader does, without executing the tokens.
    private func parse(_ bytes: [UInt8]) -> [VT100Token] {
        var tokens = [VT100Token]()
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            guard let terminal else {
                return
            }
            bytes.withUnsafeBufferPointer { buf in
                terminal.parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
            }
            var vector = CVector()
            CVectorCreate(&vector, 100)
            _ = terminal.parser.addParsedTokens(to: &vector)
            for i in 0..<CVectorCount(&vector) {
                tokens.append(CVectorGetObject(&vector, i) as! VT100Token)
            }
            CVectorDestroy(&vector)
        })
        return tokens
    }

    private func parse(_ string: String) -> [VT100Token] {
        return parse(Array(string.utf8))
    }

    // Executes tokens parsed earlier. `then` runs on the main thread after they execute
    // but before the side effects they requested are performed.
    private func execute(_ tokens: [VT100Token], then: (() -> Void)? = nil) {
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            for token in tokens {
                terminal?.execute(token)
            }
            then?()
        })
        sync()
    }

    private func send(_ string: String) {
        execute(parse(string))
    }

    private func sync() {
        // Several times, so side effects that schedule more mutation get to finish.
        for _ in 0..<4 {
            session.screen.performBlock(joinedThreads: { _, _, _ in })
        }
    }

    private func osc134(_ payload: String) -> String {
        return "\u{1b}]134;:\(payload)\u{1b}\\"
    }

    private func hook(uniqueID: String) -> String {
        return "\u{1b}P2000pnone \(uniqueID) Ym9vbA== - ZXhhbXBsZS5jb20=\n"
    }

    private func autopollReport(id: String) -> String {
        return osc134("%autopoll \(id)") +
            "$begin ps\r\n" +
            "  PID COMMAND\r\n" +
            "$begin cpu\r\n" +
            "=1.14%\r\n" +
            osc134("%end \(id)")
    }

    // What `yes` prints through the root conductor's framing.
    private func framedYes(id: String, lines: Int) -> String {
        return osc134("%output \(id) 100 -1 0") +
            String(repeating: "y\r\n", count: lines) +
            osc134("%end \(id)")
    }

    private func screenText() -> String {
        return session.screen.compactLineDumpWithHistory()
    }

    private func forceUnhook(_ dcsID: String) {
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertTrue(terminal?.parser.forceUnhookDCSReturningSuccess(dcsID) ?? false)
        })
    }

    private func hookRoot() -> Conductor? {
        send(hook(uniqueID: rootID))
        let conductor = session.conductor
        XCTAssertNotNil(conductor)
        XCTAssertEqual(conductor?.clientUniqueID, rootID)
        session.writes.removeAll()
        return conductor
    }

    // Disconnect, followed by what its forced unhook does 3 seconds later when nothing
    // answers the quit. It may run while the terminal executes tokens, so the forced unhook
    // is queued as Disconnect's own is.
    private func disconnect(_ conductor: Conductor?) {
        let dcsID = conductor?.dcsID ?? ""
        conductor?.quit()
        session.screen.mutateAsynchronously { terminal, _, _ in
            _ = terminal?.parser.forceUnhookDCSReturningSuccess(dcsID)
        }
        session.writes.removeAll()
    }

    private func disconnectRoot() {
        disconnect(session.conductor)
    }

    private func assertRecoveryNotStarted(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(session.writes, [], file: file, line: line)
        XCTAssertFalse(screenText().contains("Recovering"), screenText(), file: file, line: line)
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertEqual(terminal?.framerRecoveryMode, VT100TerminalFramerRecoveryMode.none,
                           file: file, line: line)
        })
    }

    // The local shell's prompt is drawn afterward, so the parser is not left hooked.
    private func assertShellOutputIsDrawn(file: StaticString = #filePath, line: UInt = #line) {
        send("local% ")
        XCTAssertTrue(screenText().contains("local% "), screenText(), file: file, line: line)
        XCTAssertEqual(session.writes, [], file: file, line: line)
        XCTAssertNil(session.conductor, file: file, line: line)
    }

    // MARK: - Tests

    // The QA repro: the root conductor streams `yes` output. Some of it was parsed while
    // hooked but not yet executed when the connection is abandoned, and the rest (a frame
    // cut off mid-line, then an autopoll report) arrives after the forced unhook.
    func testStreamingOutputQueuedAtAbandonmentDoesNotRecover() {
        _ = hookRoot()
        let queued = parse(framedYes(id: "o1", lines: 500) +
                           framedYes(id: "o2", lines: 500) +
                           osc134("%output o3 100 -1 0") + "y\r\ny\r\ny")
        disconnectRoot()
        execute(queued)
        send("\r\ny\r\n" + osc134("%end o3") +
             framedYes(id: "o4", lines: 50) +
             autopollReport(id: "9001") +
             osc134("%end 9001"))
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor)
        assertShellOutputIsDrawn()
    }

    // The abandonment interrupts the parser in the middle of an OSC 134 line.
    func testAbandonmentMidOSCDoesNotRecover() {
        _ = hookRoot()
        let queued = parse(framedYes(id: "o1", lines: 20) + "\u{1b}]134;:%outp")
        disconnectRoot()
        execute(queued)
        send("ut o2 100 -1 0\u{1b}\\" + "y\r\ny\r\n" + osc134("%end o2") + autopollReport(id: "9001"))
        assertRecoveryNotStarted()
        assertShellOutputIsDrawn()
    }

    // A forced unhook can happen while a live connection's frame header is still arriving
    // (e.g., the hook was refused). The rest of the header is not drawn as text.
    func testForcedUnhookKeepsFrameHeaderThatIsStillArriving() {
        let conductor = hookRoot()
        send("\u{1b}]134;:%output o2 100")
        forceUnhook(conductor?.dcsID ?? "")
        send(" -1 0\u{1b}\\")
        XCTAssertFalse(screenText().contains("-1 0"), screenText())
        XCTAssertFalse(screenText().contains("o2"), screenText())
    }

    // A framer wrapper parsed inside the root's framing has the depth of the root's
    // children, not the refused outermost depth. It was parsed before the abandonment and
    // executes after it.
    func testWrapperParsedInsideAbandonedFramingDoesNotRecover() {
        _ = hookRoot()
        let queued = parse(osc134("%output o1 100 -1 0") +
                           autopollReport(id: "9001") +
                           osc134("%end o1"))
        disconnectRoot()
        execute(queued)
        assertRecoveryNotStarted()
        assertShellOutputIsDrawn()
    }

    // Same as above, but Disconnect ended the connection.
    func testRecoveryRequestedBeforeDisconnectDoesNotBegin() {
        let conductor = hookRoot()
        forceUnhook(conductor?.dcsID ?? "")
        let queued = parse(autopollReport(id: "9001"))
        execute(queued, then: {
            conductor?.quit()
        })
        session.writes.removeAll()
        sync()
        assertRecoveryNotStarted()
        send(autopollReport(id: "9002"))
        assertRecoveryNotStarted()
        assertShellOutputIsDrawn()
    }

    // A nested it2ssh's hook in the abandoned connection's output, parsed before the
    // abandonment, must not start a conductor (which would write to the local shell) or
    // lift the refusal.
    func testStaleNestedHookParsedBeforeAbandonmentDoesNotStartConductor() {
        _ = hookRoot()
        let queued = parse(osc134("%output o1 100 -1 0") +
                           hook(uniqueID: "888") +
                           osc134("%end o1"))
        disconnectRoot()
        execute(queued)
        XCTAssertNil(session.conductor)
        send(autopollReport(id: "9001"))
        assertRecoveryNotStarted()
        assertShellOutputIsDrawn()
    }

    // As above, but the terminal executed the stale hook before it learned of the
    // abandonment, and the session abandoned the connection before the hook's side
    // effect ran.
    func testStaleNestedHookExecutedBeforeAbandonmentDoesNotStartConductor() {
        _ = hookRoot()
        let queued = parse(osc134("%output o1 100 -1 0") +
                           hook(uniqueID: "888") +
                           osc134("%end o1"))
        execute(queued, then: { [unowned self] in
            self.disconnectRoot()
        })
        XCTAssertNil(session.conductor)
        session.writes.removeAll()
        send(autopollReport(id: "9001"))
        assertRecoveryNotStarted()
        assertShellOutputIsDrawn()
    }

    // The abandoned connection's own hook can't start a conductor or lift the refusal.
    func testHookByAbandonedConnectionDoesNotLiftRefusal() {
        _ = hookRoot()
        disconnectRoot()
        sync()
        send(hook(uniqueID: rootID))
        XCTAssertNil(session.conductor)
        send(autopollReport(id: "9001"))
        assertRecoveryNotStarted()
        assertShellOutputIsDrawn()
    }

    // A nested connection's abandonment refuses its own depth and deeper ones, while the
    // root (still connected) can recover.
    func testNestedAbandonmentLeavesRootRecoverable() {
        let root = hookRoot()
        send(osc134("%output out1 100 -1 0") + hook(uniqueID: nestedID) + osc134("%end out1"))
        XCTAssertEqual(session.conductor?.clientUniqueID, nestedID)
        disconnect(session.conductor)
        sync()
        XCTAssertTrue(session.conductor === root)
        session.writes.removeAll()
        send(osc134("%output out2 100 -1 0") + autopollReport(id: "9001") + osc134("%end out2"))
        XCTAssertEqual(session.writes, [])
        forceUnhook(root?.dcsID ?? "")
        send(autopollReport(id: "9002"))
        XCTAssertTrue(session.writes.contains { $0.contains(recover) }, "\(session.writes)")
    }

    // A new connection's hook was executed before the terminal learned of the old one's
    // abandonment, and the session handled the abandonment before the new hook. The new
    // connection must still be able to recover.
    func testNewConnectionHookedDuringAbandonmentCanRecover() {
        let old = hookRoot()
        forceUnhook(old?.dcsID ?? "")
        let queued = parse(hook(uniqueID: "777"))
        execute(queued, then: { [unowned self] in
            self.disconnectRoot()
        })
        let conductor = session.conductor
        XCTAssertEqual(conductor?.clientUniqueID, "777")
        forceUnhook(conductor?.dcsID ?? "")
        session.writes.removeAll()
        send(autopollReport(id: "9001"))
        XCTAssertTrue(session.writes.contains { $0.contains(recover) }, "\(session.writes)")
    }

    // The connection lost sync and recovered, and the terminal is waiting for the
    // recovered connection's boundary when that connection is abandoned.
    func testAbandonmentWhileSyncingAfterRecoveryLeavesRecovery() {
        let conductor = hookRoot()
        forceUnhook(conductor?.dcsID ?? "")
        send(autopollReport(id: "9001"))
        XCTAssertTrue(session.writes.contains { $0.contains(recover) }, "\(session.writes)")
        send(osc134("begin-recovery") +
             osc134("recovery: version 1") +
             osc134("recovery: login 100") +
             osc134("recovery: dcsID d1") +
             osc134("recovery: sshargs ZXhhbXBsZS5jb20=") +
             osc134("recovery: boolArgs Ym9vbA==") +
             osc134("recovery: clientUniqueID 4242") +
             osc134("end-recovery"))
        XCTAssertEqual(session.conductor?.clientUniqueID, "4242")
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertEqual(terminal?.framerRecoveryMode, VT100TerminalFramerRecoveryMode.syncing)
        })

        disconnect(session.conductor)
        sync()
        session.writes.removeAll()
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertEqual(terminal?.framerRecoveryMode, VT100TerminalFramerRecoveryMode.none)
        })
        send(autopollReport(id: "9002"))
        XCTAssertEqual(session.writes, [])
        assertShellOutputIsDrawn()
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertEqual(terminal?.framerRecoveryMode, VT100TerminalFramerRecoveryMode.none)
        })
    }

    // After an abandonment a new connection hooks, loses sync, and recovers.
    func testNewConnectionAfterStreamingAbandonmentCanRecover() {
        _ = hookRoot()
        let queued = parse(framedYes(id: "o1", lines: 100))
        disconnectRoot()
        execute(queued)
        send(hook(uniqueID: "777"))
        let conductor = session.conductor
        XCTAssertEqual(conductor?.clientUniqueID, "777")
        forceUnhook(conductor?.dcsID ?? "")
        session.writes.removeAll()
        send(autopollReport(id: "9001"))
        XCTAssertTrue(session.writes.contains { $0.contains(recover) }, "\(session.writes)")
    }
}

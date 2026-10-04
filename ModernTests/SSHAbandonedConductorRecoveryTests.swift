//
//  SSHAbandonedConductorRecoveryTests.swift
//  iTerm2
//
//  F-354: when only the local it2ssh is killed, its ssh client keeps running and its
//  remote conductor keeps printing framer output (e.g., an autopoll report). Once the
//  connection is abandoned and its hook removed, that OSC 134 output arrived outside
//  any hook and started framer recovery, which typed base64 "recover" into the local
//  shell and left a recovery conductor holding the keyboard. An abandoned connection's
//  framer output must instead be ignored, and anything else it prints drawn.
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

    // The control: framer output outside any hook for a connection that wasn't abandoned
    // (e.g., the parser lost sync) still starts recovery.
    func testUnhookedFramerOutputStillRecoversLiveConnection() {
        let conductor = hookRoot()
        forceUnhook(conductor?.dcsID ?? "")
        send(autopollReport(id: "9001"))
        XCTAssertTrue(session.writes.contains { $0.contains(recover) }, "\(session.writes)")
    }

    func testAbandonedConnectionsFramerOutputDoesNotStartRecovery() {
        _ = hookRoot()
        session.abandonSSH(throughClientUniqueID: rootID)
        sync()
        XCTAssertNil(session.conductor)

        send(autopollReport(id: "9001"))
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor, "no recovery conductor may take over the keyboard")
        XCTAssertTrue(screenText().contains("$begin ps"), screenText())

        // A second report, and then the local shell's prompt, are drawn too: the parser is
        // not hooked.
        send(autopollReport(id: "9002"))
        send("local% ")
        assertRecoveryNotStarted()
        XCTAssertTrue(screenText().contains("local% "), screenText())
        XCTAssertNil(session.conductor)
    }

    // If the hook was already gone when the connection was abandoned, its framer's output
    // still must not start recovery.
    func testAbandonedConnectionWithoutHookDoesNotRecover() {
        let conductor = hookRoot()
        forceUnhook(conductor?.dcsID ?? "")
        session.abandonSSH(throughClientUniqueID: rootID)
        sync()
        send(autopollReport(id: "9001"))
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor)
    }

    // Disconnect, followed by its forced unhook, also abandons the connection.
    func testDisconnectedConnectionsFramerOutputDoesNotStartRecovery() {
        let conductor = hookRoot()
        let dcsID = conductor?.dcsID ?? ""
        conductor?.quit()
        sync()
        XCTAssertNil(session.conductor)
        // What the forced unhook does 3 seconds later when nothing answers the quit.
        forceUnhook(dcsID)
        session.writes.removeAll()

        send(autopollReport(id: "9001"))
        send("local% ")
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor)
        XCTAssertTrue(screenText().contains("local% "), screenText())
    }

    // A new connection's framer output is its own, so it may recover again.
    func testNewConnectionAfterAbandonmentCanRecover() {
        _ = hookRoot()
        session.abandonSSH(throughClientUniqueID: rootID)
        sync()

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
    // parent stays connected and no recovery starts for the abandoned child.
    func testAbandonedNestedConnectionsFramerOutputDoesNotStartRecovery() {
        let root = hookRoot()
        send(osc134("%output out1 100 -1 0") + hook(uniqueID: nestedID) + osc134("%end out1"))
        XCTAssertEqual(session.conductor?.clientUniqueID, nestedID)
        session.abandonSSH(throughClientUniqueID: nestedID)
        sync()
        XCTAssertTrue(session.conductor === root)
        session.writes.removeAll()

        send(osc134("%output out2 100 -1 0") + autopollReport(id: "9001") + osc134("%end out2"))
        send(osc134("%output out3 100 -1 0") + "hostA% " + osc134("%end out3"))
        assertRecoveryNotStarted()
        XCTAssertTrue(session.conductor === root)
        XCTAssertTrue(screenText().contains("$begin ps"), screenText())
        XCTAssertTrue(screenText().contains("hostA% "), screenText())
    }
}


// MARK: - F-459: abandoning while the remote streams output

// When it2ssh is killed while the remote is streaming output, the session has framed
// output queued at every stage: bytes not yet parsed, tokens parsed (with the old
// framing's depths) but not yet executed, and side effects requested but not yet
// performed. Nothing in any of them may start recovery, start a conductor, or write to
// the shell once the connection is abandoned.
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

    private func abandonRoot() {
        session.abandonSSH(throughClientUniqueID: rootID)
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
        abandonRoot()
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
        abandonRoot()
        execute(queued)
        send("ut o2 100 -1 0\u{1b}\\" + "y\r\ny\r\n" + osc134("%end o2") + autopollReport(id: "9001"))
        assertRecoveryNotStarted()
        assertShellOutputIsDrawn()
    }

    // F-553: the ssh client died partway through writing a frame header, so the last thing
    // parsed while hooked is an OSC 134 that will never be terminated. The hook was waiting
    // for the rest of it. Once the connection is abandoned, the local shell's output must
    // not be taken as the rest of that OSC. It is drawn from its first line break on.
    func testUnterminatedFrameHeaderBeforeAbandonmentDoesNotSwallowShellOutput() {
        _ = hookRoot()
        let queued = parse(framedYes(id: "o1", lines: 20) + "\u{1b}]134;:%output o2")
        abandonRoot()
        execute(queued)
        send("\r\nlocal% ")
        XCTAssertTrue(screenText().contains("local% "), screenText())
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor)
    }

    // As above, but with only part of the OSC's introducer.
    func testUnterminatedFrameHeaderIntroducerBeforeAbandonmentDoesNotSwallowShellOutput() {
        _ = hookRoot()
        let queued = parse(framedYes(id: "o1", lines: 20) + "\u{1b}]134")
        abandonRoot()
        execute(queued)
        send("\r\nlocal% ")
        XCTAssertTrue(screenText().contains("local% "), screenText())
        assertRecoveryNotStarted()
    }

    // The cut-off header arrives after the forced unhook (it was still in the pty when the
    // connection was abandoned). The shell's output that follows is drawn from its first
    // new line on.
    func testUnterminatedFrameHeaderAfterAbandonmentDoesNotSwallowShellOutput() {
        _ = hookRoot()
        abandonRoot()
        sync()
        send(framedYes(id: "o1", lines: 5) + "\u{1b}]134;:%output o2")
        send("\r\nlocal% ")
        XCTAssertTrue(screenText().contains("local% "), screenText())
        assertRecoveryNotStarted()
        XCTAssertNil(session.conductor)
    }

    // The shell's first output after the cut-off header is an escape sequence (zsh with
    // shell integration reports the killed command's end), parsed after the forced unhook.
    func testUnterminatedFrameHeaderInterruptedByShellOSCAfterAbandonment() {
        _ = hookRoot()
        abandonRoot()
        sync()
        send(framedYes(id: "o1", lines: 5) + "\u{1b}]134;:%output o2")
        send("\u{1b}]0;title\u{07}local% ")
        XCTAssertTrue(screenText().contains("local% "), screenText())
        XCTAssertFalse(screenText().contains("title"), screenText())
        assertRecoveryNotStarted()
    }

    // As above, but the header was parsed while hooked, and the shell's output arrived but
    // wasn't parsed yet when the forced unhook ran.
    func testUnterminatedFrameHeaderInterruptedByShellOSCBeforeAbandonment() {
        _ = hookRoot()
        let queued = parse(framedYes(id: "o1", lines: 20) + "\u{1b}]134;:%output o2")
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            let bytes = Array("\u{1b}]0;title\u{07}local% ".utf8)
            bytes.withUnsafeBufferPointer { buf in
                terminal?.parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
            }
        })
        abandonRoot()
        execute(queued)
        send("\r\n")
        XCTAssertTrue(screenText().contains("local% "), screenText())
        XCTAssertFalse(screenText().contains("title"), screenText())
        assertRecoveryNotStarted()
    }

    // A framer reply that isn't a frame header may span lines (e.g., a Python traceback).
    // Outside the hook it is still one OSC, not drawn.
    func testMultilineFramerReplyOutsideHookIsNotDrawn() {
        _ = hookRoot()
        abandonRoot()
        sync()
        send(osc134("first line\r\nsecond line"))
        send("\r\nlocal% ")
        XCTAssertFalse(screenText().contains("second line"), screenText())
        XCTAssertTrue(screenText().contains("local% "), screenText())
        assertRecoveryNotStarted()
    }

    // A reply may also start with % (e.g., an environment variable's value). Only the
    // framer's notification headers end at a line break.
    func testMultilineFramerReplyStartingWithPercentOutsideHookIsNotDrawn() {
        _ = hookRoot()
        abandonRoot()
        sync()
        send(osc134("%output-like value\r\nsecond line"))
        send("\r\nlocal% ")
        XCTAssertFalse(screenText().contains("second line"), screenText())
        XCTAssertTrue(screenText().contains("local% "), screenText())
        assertRecoveryNotStarted()
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
        abandonRoot()
        execute(queued)
        assertRecoveryNotStarted()
        assertShellOutputIsDrawn()
    }

    // The terminal executed framer output that starts recovery (the hook was already
    // gone) and then the session abandoned the connection before the recovery's side
    // effect ran.
    func testRecoveryRequestedBeforeAbandonmentDoesNotBegin() {
        let conductor = hookRoot()
        forceUnhook(conductor?.dcsID ?? "")
        let queued = parse(autopollReport(id: "9001"))
        execute(queued, then: { [unowned self] in
            self.abandonRoot()
        })
        assertRecoveryNotStarted()
        // Later framer output is ignored too, and the shell's output is drawn.
        send(autopollReport(id: "9002"))
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
        abandonRoot()
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
            self.abandonRoot()
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
        abandonRoot()
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
        session.abandonSSH(throughClientUniqueID: nestedID)
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
            self.abandonRoot()
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

        session.abandonSSH(throughClientUniqueID: "4242")
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
        abandonRoot()
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

// MARK: - F-554: an abandoned connection writes nothing

// Records what a conductor writes.
private final class WriteRecordingConductorDelegate: NSObject, ConductorDelegate {
    var written = ""

    func conductorWrite(string: String) {
        written += string
    }
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    func conductorRequestIT2Authorization(guid: String,
                                          displayName: String,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {
        completion(false, false, false)
    }
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    let guid = "write-recording-delegate"
}

// After killing it2ssh while the remote streamed output, iTerm2 typed YXV0b3BvbGw= (base64
// of “autopoll”) into the local shell. Once a connection is abandoned, nothing that
// happens to its conductor afterward may write a command for it.
@MainActor
final class SSHAbandonedConductorWriteTests: XCTestCase {
    private let autopoll = "autopoll".data(using: .utf8)!.base64EncodedString()
    private var conductors = [Conductor]()
    private var delegates = [WriteRecordingConductorDelegate]()

    override func tearDown() {
        for conductor in conductors {
            ConductorRegistry.instance.remove(conductorGUID: conductor.guid,
                                              sshIdentity: conductor.sshIdentity)
        }
        conductors = []
        delegates = []
        super.tearDown()
    }

    private func makeConductor(parent: Conductor?,
                               delegate: WriteRecordingConductorDelegate) -> Conductor {
        let conductor = Conductor("f554.example.com", boolArgs: "", dcsID: "dcs",
                                  clientUniqueID: "cid\(conductors.count)",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: parent)
        // The conductor holds its delegate weakly.
        delegates.append(delegate)
        conductor.delegate = delegate
        // Framing with a login shell running, as after a successful it2ssh handshake.
        conductor.framedPID = 4242
        conductors.append(conductor)
        drain()
        return conductor
    }

    private static func inFlight(_ conductor: Conductor) -> Int {
        switch conductor.state {
        case .willExecutePipeline(let contexts):
            return contexts.count
        case .executingPipeline(_, let pending):
            return 1 + pending.count
        case .ground, .unhooked, .recovery, .recovered:
            return 0
        }
    }

    // Delivers the remote's %end for every command in flight (e.g., registering the login
    // shell), so the next command is written at once.
    private func drain() {
        for _ in 0..<100 {
            guard let busy = conductors.first(where: { Self.inFlight($0) > 0 }) else {
                return
            }
            busy.handleCommandEnd(identifier: "id", type: "f", status: 0, depth: busy.depth)
        }
        XCTFail("Commands are still in flight")
    }

    // What the framer's autopoll report ends with. The conductor answers it by asking for
    // the next one (after registering the login shell to poll, the first time).
    private func deliverAutopollEOF(to conductor: Conductor) {
        conductor.handleSideChannelOutput("EOF",
                                          pid: SSH_OUTPUT_AUTOPOLL_PID,
                                          channel: 1,
                                          depth: conductor.depth)
        drain()
    }

    // The control: a live connection asks for the next autopoll report.
    func testLiveConnectionRequestsAutopoll() {
        let delegate = WriteRecordingConductorDelegate()
        let conductor = makeConductor(parent: nil, delegate: delegate)
        delegate.written = ""
        deliverAutopollEOF(to: conductor)
        XCTAssertTrue(delegate.written.contains(autopoll), delegate.written)
    }

    // An autopoll report parsed before the abandonment and handled after it, while the
    // session still holds the conductor.
    func testAbandonedConnectionDoesNotRequestAutopoll() {
        let delegate = WriteRecordingConductorDelegate()
        let conductor = makeConductor(parent: nil, delegate: delegate)
        delegate.written = ""
        conductor.abandon()
        deliverAutopollEOF(to: conductor)
        conductor.sendKeys("ls\r".data(using: .utf8)!)
        XCTAssertEqual(delegate.written, "")
    }

    // A nested connection's commands go through its parent, which is still connected, to
    // the remote shell that ran the nested it2ssh.
    func testAbandonedNestedConnectionDoesNotWriteThroughParent() {
        let delegate = WriteRecordingConductorDelegate()
        let parent = makeConductor(parent: nil, delegate: delegate)
        let child = makeConductor(parent: parent, delegate: WriteRecordingConductorDelegate())
        delegate.written = ""
        deliverAutopollEOF(to: child)
        XCTAssertFalse(delegate.written.isEmpty, "a live nested connection writes through its parent")

        let otherDelegate = WriteRecordingConductorDelegate()
        let liveParent = makeConductor(parent: nil, delegate: otherDelegate)
        let abandonedChild = makeConductor(parent: liveParent,
                                           delegate: WriteRecordingConductorDelegate())
        otherDelegate.written = ""
        abandonedChild.abandon()
        deliverAutopollEOF(to: abandonedChild)
        XCTAssertEqual(otherDelegate.written, "")
    }
}

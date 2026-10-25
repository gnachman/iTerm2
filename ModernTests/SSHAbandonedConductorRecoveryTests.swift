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


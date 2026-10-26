//
//  SSHNestedConnectionEndTests.swift
//  iTerm2
//
//  How a nested SSH Integration connection (an it2ssh run on a host that is itself
//  reached with it2ssh) ends without disturbing the connection it is nested in.
//
//  F-708 (and F-705 on master): a nested conductor that the session tears down right away,
//  because its it2ssh's arguments couldn't be read or because the user disconnected it,
//  left its hook in place. The hook's own unhook, which arrives later, was then handled by
//  the outer conductor, which took it as its own end and sent nothing more, so the tab
//  stopped responding. The inner it2ssh's EndSSH went unanswered too, leaving it waiting
//  with echo off in the outer host's shell.
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

private final class RecordingConductorDelegate: NSObject, ConductorDelegate {
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
                                          completion: @escaping (Bool, Bool) -> Void) {
        completion(false, false)
    }
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    let guid = "recording-delegate"
}

@MainActor
final class SSHNestedConnectionEndTests: XCTestCase {
    private var extraConductors = [Conductor]()
    private var session: WriteCapturingSession!
    private let rootID = "1234567890"
    private let nestedID = "555"
    // The outer framer's pid for its login shell, where the inner it2ssh runs.
    private let loginShellPID: Int32 = 100

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
        var conductor = session.conductor
        while let current = conductor {
            ConductorRegistry.instance.remove(conductorGUID: current.guid,
                                              sshIdentity: current.sshIdentity)
            conductor = current.parent
        }
        for conductor in extraConductors {
            ConductorRegistry.instance.remove(conductorGUID: conductor.guid,
                                              sshIdentity: conductor.sshIdentity)
        }
        extraConductors = []
        session = nil
        super.tearDown()
    }

    // MARK: - Helpers

    // Feeds bytes through the session's own parser, as the pty would, executes the
    // tokens synchronously, and runs the resulting side effects.
    private func send(_ string: String) {
        let bytes = Array(string.utf8)
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

    // Output of the outer framer's login shell (where the inner it2ssh runs).
    private func framed(_ id: String, _ payload: String) -> String {
        return osc134("%output \(id) \(loginShellPID) -1 0") + payload + osc134("%end \(id)")
    }

    // What it2ssh prints once its ssh exits.
    private func endSSH(_ uniqueID: String) -> String {
        return "\u{1b}]1337;EndSSH=\(uniqueID)\u{07}"
    }

    // An outer connection whose framer runs the login shell, with nothing in flight.
    private func hookFramingRoot() -> Conductor {
        send(hook(uniqueID: rootID))
        let root = session.conductor!
        XCTAssertEqual(root.clientUniqueID, rootID)
        root.framedPID = loginShellPID
        root.forceReturnToGroundState()
        session.writes.removeAll()
        return root
    }

    // An it2ssh run in the outer host's login shell.
    private func hookNested(in root: Conductor) -> Conductor {
        send(framed("out1", hook(uniqueID: nestedID)))
        let nested = session.conductor!
        XCTAssertEqual(nested.clientUniqueID, nestedID)
        XCTAssertTrue(nested.parent === root)
        XCTAssertEqual(nested.depth, root.depth + 1)
        return nested
    }

    private static func isUnhooked(_ conductor: Conductor) -> Bool {
        if case .unhooked = conductor.state {
            return true
        }
        return false
    }

    private func assertRootIsLive(_ root: Conductor,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        XCTAssertTrue(session.conductor === root, file: file, line: line)
        XCTAssertFalse(Self.isUnhooked(root), "the outer connection was taken for ended", file: file, line: line)
    }

    // MARK: - F-705

    // The control: the inner connection ends on its own. The outer one carries on and
    // it2ssh's EndSSH is answered so it exits.
    func testNestedConnectionThatEndsLeavesParentLive() {
        let root = hookFramingRoot()
        let nested = hookNested(in: root)
        nested.forceReturnToGroundState()
        session.writes.removeAll()

        send(framed("out2", endSSH(nestedID)))
        assertRootIsLive(root)
        XCTAssertTrue(session.writes.contains("\u{03}\n"), "\(session.writes)")
    }

    func testDisconnectingNestedConnectionLeavesParentLive() {
        let root = hookFramingRoot()
        let nested = hookNested(in: root)
        nested.forceReturnToGroundState()
        session.writes.removeAll()

        // Shell > ssh > Disconnect on the inner hop.
        nested.quit()
        sync()
        assertRootIsLive(root)
        XCTAssertFalse(session.writes.isEmpty, "the inner conductor's quit goes through the outer framer")
        session.writes.removeAll()

        // The inner framer quits, its hook ends, ssh exits, and it2ssh prints EndSSH and
        // waits for a line before it exits.
        send(framed("out2", osc134("unhook")))
        assertRootIsLive(root)
        send(framed("out3", endSSH(nestedID)))
        assertRootIsLive(root)
        XCTAssertEqual(session.writes, ["\u{03}\n"])

        // The outer connection still sends what is typed.
        session.writes.removeAll()
        root.forceReturnToGroundState()
        root.sendKeys("ls\r".data(using: .utf8)!)
        XCTAssertFalse(session.writes.isEmpty)
    }

    // it2ssh's EndSSH can come before the inner framer's unhook: it ends the hook too.
    func testDisconnectedNestedConnectionsEndSSHEndsItsHook() {
        let root = hookFramingRoot()
        let nested = hookNested(in: root)
        nested.forceReturnToGroundState()
        nested.quit()
        sync()
        session.writes.removeAll()

        send(framed("out2", endSSH(nestedID)))
        assertRootIsLive(root)
        XCTAssertEqual(session.writes, ["\u{03}\n"])
        send(framed("out3", "hostA% "))
        XCTAssertTrue(session.screen.compactLineDumpWithHistory().contains("hostA% "))
    }

    // MARK: - F-708

    // A nested it2ssh whose arguments can't be read: its conductor is told to quit at once.
    // The inner it2ssh's EndSSH must be answered and the outer connection must carry on.
    func testUnreadableNestedHookEndsAndLeavesParentLive() {
        let root = hookFramingRoot()
        // Boolean arguments that are not UTF-8.
        send(framed("out1", "\u{1b}P2000pnone \(nestedID) /w== - ZXhhbXBsZS5jb20=\n"))
        assertRootIsLive(root)
        let quit = "quit".data(using: .utf8)!.base64EncodedString()
        XCTAssertTrue(Self.relayedPayloads(session.writes.joined()).contains { $0.contains(quit) },
                      "the inner conductor is told to quit: \(session.writes)")
        session.writes.removeAll()

        send(framed("out2", endSSH(nestedID)))
        assertRootIsLive(root)
        XCTAssertTrue(session.writes.contains("\u{03}\n"), "\(session.writes)")
        send(framed("out3", "hostA% "))
        XCTAssertTrue(session.screen.compactLineDumpWithHistory().contains("hostA% "))
        session.writes.removeAll()
        root.forceReturnToGroundState()
        root.sendKeys("ls\r".data(using: .utf8)!)
        XCTAssertFalse(session.writes.isEmpty, "keys reach the outer connection")
    }

    // MARK: - F-709

    private func makeFramingConductor(_ delegate: RecordingConductorDelegate) -> Conductor {
        let conductor = Conductor("f709.example.com", boolArgs: "", dcsID: "dcs",
                                  clientUniqueID: "c709",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
        conductor.delegate = delegate
        conductor.framedPID = loginShellPID
        extraConductors.append(conductor)
        return conductor
    }

    private func deliverAutopollEOF(to conductor: Conductor) {
        conductor.handleSideChannelOutput("EOF", pid: SSH_OUTPUT_AUTOPOLL_PID, channel: 1,
                                          depth: conductor.depth)
    }

    // The framer answers everything in flight.
    private func drain(_ conductor: Conductor) {
        for _ in 0..<20 {
            switch conductor.state {
            case .willExecutePipeline, .executingPipeline:
                conductor.handleCommandEnd(identifier: "id", type: "f", status: 0, depth: conductor.depth)
            default:
                return
            }
        }
    }

    // The control: a live connection asks for the next autopoll report.
    func testLiveConnectionAsksForNextAutopoll() {
        let delegate = RecordingConductorDelegate()
        let conductor = makeFramingConductor(delegate)
        deliverAutopollEOF(to: conductor)
        drain(conductor)
        let autopoll = "autopoll".data(using: .utf8)!.base64EncodedString()
        XCTAssertTrue(delegate.written.contains(autopoll), delegate.written)
    }

    // The login shell exited, so the framer quits and ssh exits soon after. An autopoll
    // report that arrives meanwhile must not be answered: the request would be written after
    // ssh exited and typed into the local terminal (YXV0b3BvbGw=, base64 “autopoll”).
    func testNothingIsWrittenAfterTheLoginShellExits() {
        let delegate = RecordingConductorDelegate()
        let conductor = makeFramingConductor(delegate)
        // Registers the login shell to poll, the first time.
        deliverAutopollEOF(to: conductor)
        drain(conductor)
        delegate.written = ""
        conductor.handleTerminate(loginShellPID, code: 0, depth: conductor.depth)
        XCTAssertFalse(delegate.written.isEmpty, "the framer is told to quit")
        delegate.written = ""

        // Before and after the framer answers the quit.
        deliverAutopollEOF(to: conductor)
        conductor.handleCommandEnd(identifier: "id", type: "f", status: 0, depth: conductor.depth)
        deliverAutopollEOF(to: conductor)
        conductor.sendKeys("x".data(using: .utf8)!)
        XCTAssertEqual(delegate.written, "")
    }

    // F-783: keys typed after the inner login shell exited, before its it2ssh's EndSSH, go to
    // the outer host's shell once it2ssh has the newline it waits for.
    func testKeysTypedAfterLoginShellExitGoToTheShellThatTakesOver() {
        let root = hookFramingRoot()
        let nested = hookNested(in: root)
        nested.framedPID = 200
        nested.forceReturnToGroundState()
        nested.handleTerminate(200, code: 0, depth: nested.depth)
        root.forceReturnToGroundState()
        session.writes.removeAll()

        nested.sendKeys("ls\r".data(using: .utf8)!)
        XCTAssertTrue(Self.relayedPayloads(session.writes.joined()).filter { $0 == "ls\r" }.isEmpty,
                      "\(session.writes)")

        send(framed("out2", endSSH(nestedID)))
        assertRootIsLive(root)
        // The outer framer answers what it was already doing.
        drain(root)
        let newline = session.writes.firstIndex(of: "\u{03}\n")
        XCTAssertNotNil(newline, "\(session.writes)")
        let after = Array(session.writes[((newline ?? 0) + 1)...])
        XCTAssertTrue(after.contains("ls\r") || Self.relayedPayloads(after.joined()) == ["ls\r"],
                      "\(session.writes)")
    }

    // F-787: under an outer connection without a framer, a nested conductor has the outer's
    // depth. Its late unhook after Disconnect still isn't the outer's end.
    func testDisconnectedConnectionUnderNonFramingParentLeavesParentLive() {
        send(hook(uniqueID: rootID))
        let root = session.conductor!
        // The outer conductor ran the login shell without a framer and its hook ended.
        let rootDCSID = root.dcsID
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertTrue(terminal?.parser.forceUnhookDCSReturningSuccess(rootDCSID) ?? false)
        })
        root.forceReturnToGroundState()
        send(hook(uniqueID: nestedID))
        let nested = session.conductor!
        XCTAssertTrue(nested.parent === root)
        XCTAssertEqual(nested.depth, root.depth)
        nested.framedPID = 200
        nested.forceReturnToGroundState()

        nested.quit()
        sync()
        XCTAssertTrue(session.conductor === root)
        session.writes.removeAll()
        // it2ssh's EndSSH ends the nested hook.
        send(endSSH(nestedID))
        XCTAssertTrue(session.conductor === root)
        XCTAssertFalse(Self.isUnhooked(root), "the outer connection was taken for ended")
        XCTAssertTrue(session.writes.contains("\u{03}\n"), "\(session.writes)")
    }

    // F-781: Disconnect after the login shell exited must not send a second quit.
    func testQuitAfterLoginShellExitSendsOneQuit() {
        let delegate = RecordingConductorDelegate()
        let conductor = makeFramingConductor(delegate)
        deliverAutopollEOF(to: conductor)
        drain(conductor)
        delegate.written = ""
        conductor.handleTerminate(loginShellPID, code: 0, depth: conductor.depth)
        conductor.handleCommandEnd(identifier: "id", type: "f", status: 0, depth: conductor.depth)
        conductor.quit()
        drain(conductor)
        let quit = "quit".data(using: .utf8)!.base64EncodedString()
        XCTAssertEqual(delegate.written.components(separatedBy: quit).count - 1, 1, delegate.written)
    }

    // F-781: Disconnect while the quit sent for the login shell's exit still waits in the
    // queue must not cancel it, since no other quit is sent.
    func testQuitWaitingInQueueSurvivesDisconnect() {
        let delegate = RecordingConductorDelegate()
        let conductor = makeFramingConductor(delegate)
        deliverAutopollEOF(to: conductor)
        drain(conductor)
        // Something in flight that nothing can be pipelined behind.
        conductor.send(.framerAutopoll, .fireAndForget)
        delegate.written = ""
        conductor.handleTerminate(loginShellPID, code: 0, depth: conductor.depth)
        conductor.quit()
        drain(conductor)
        let quit = "quit".data(using: .utf8)!.base64EncodedString()
        XCTAssertEqual(delegate.written.components(separatedBy: quit).count - 1, 1, delegate.written)
    }

    // The payloads of the framer `send` commands in what was written, decoded the way
    // framer.py does.
    private static func relayedPayloads(_ written: String) -> [String] {
        var result = [String]()
        var args = [String]()
        for line in written.components(separatedBy: "\n") {
            if !line.isEmpty {
                if let last = args.last, last.hasSuffix("\\") {
                    args[args.count - 1] = String(last.dropLast()) + line
                } else {
                    args.append(line)
                }
            } else if !args.isEmpty {
                let decoded = args.map { arg -> String in
                    guard let data = Data(base64Encoded: arg) else {
                        return "<undecodable \(arg)>"
                    }
                    return String(data: data, encoding: .isoLatin1) ?? ""
                }
                // The payload is base64 again inside its argument.
                if decoded.first == "send", decoded.count == 3,
                   let payload = Data(base64Encoded: decoded[2]) {
                    result.append(String(data: payload, encoding: .isoLatin1) ?? "")
                }
                args = []
            }
        }
        return result
    }
}

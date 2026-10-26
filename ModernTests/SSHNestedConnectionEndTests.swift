//
//  SSHNestedConnectionEndTests.swift
//  iTerm2
//
//  How a nested SSH Integration connection (an it2ssh run on a host that is itself
//  reached with it2ssh) ends without disturbing the connection it is nested in.
//
//  F-705: Disconnect on the inner hop unhooked the inner conductor right away. The inner
//  hook's own unhook, which arrives later, was then handled by the outer conductor, which
//  took it as its own end: it stopped flow control and sent nothing more, so nothing more
//  was drawn. The inner it2ssh's EndSSH went unanswered too, leaving it waiting with echo
//  off in the outer host's shell.
//
//  F-703: commands for the inner connection that were still queued for the outer framer
//  when the inner connection ended were sent anyway, and the outer host's shell read
//  them as a command line (YXV0b3BvbGw=, base64 “autopoll”).
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
final class SSHNestedConnectionEndTests: XCTestCase {
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
        XCTAssertFalse(root.hasEnded, "the outer connection was taken for ended", file: file, line: line)
        XCTAssertFalse(Self.isUnhooked(root), file: file, line: line)
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

//
//  SSHMayHaveEndedKeysTests.swift
//  iTerm2
//
//  F-820: while the “SSH connection … ended unexpectedly” announcement is up, keys typed
//  went as framed send-keys to the suspect connection, relayed through the framers it was
//  nested in. They are now held until the user decides: on Disconnect they go to the shell
//  that takes over; if the connection ends normally, they go to the shell that takes over
//  once its it2ssh exits; otherwise to the connection itself.
//

import XCTest
@testable import iTerm2SharedARC

// Records what the session's conductors send without sending it. Typed keys take the
// session's own route.
private final class ConductorWriteCapturingSession: PTYSession {
    var writes = [String]()

    override func writeTaskNoBroadcast(_ string: String) {
        writes.append(string)
    }
}

@MainActor
final class SSHMayHaveEndedKeysTests: XCTestCase {
    private var session: ConductorWriteCapturingSession!
    private let rootID = "1234567890"
    private let nestedID = "555"

    override func setUp() {
        super.setUp()
        session = ConductorWriteCapturingSession(synthetic: false)
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
        session.screen.performBlock(joinedThreads: { _, _, _ in })
        session.screen.performBlock(joinedThreads: { _, _, _ in })
    }

    private func osc134(_ payload: String) -> String {
        return "\u{1b}]134;:\(payload)\u{1b}\\"
    }

    private func hook(uniqueID: String) -> String {
        return "\u{1b}P2000pnone \(uniqueID) Ym9vbA== - ZXhhbXBsZS5jb20=\n"
    }

    private func framed(_ id: String, _ payload: String) -> String {
        return osc134("%output \(id) 100 -1 0") + payload + osc134("%end \(id)")
    }

    // An outer connection with a framer, and one nested in it whose shell's prompt appeared
    // unframed, as when its it2ssh is killed.
    private func makeSuspectNestedConnection() -> (Conductor, Conductor) {
        send(hook(uniqueID: rootID))
        let root = session.conductor!
        root.framedPID = 100
        root.forceReturnToGroundState()
        send(framed("out1", hook(uniqueID: nestedID)))
        let nested = session.conductor!
        XCTAssertTrue(nested.parent === root)
        nested.framedPID = 200
        nested.forceReturnToGroundState()
        session.writes.removeAll()
        send(framed("out2", "\u{1b}]133;A\u{07}hostA% "))
        return (root, nested)
    }

    // The outer framer answers what it was doing.
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

    // Typed keys as payloads of the framer `send` commands written, innermost wrapping removed.
    private static func sentKeys(_ written: String) -> [String] {
        var result = [String]()
        var args = [String]()
        for line in written.components(separatedBy: "\n") {
            if !line.isEmpty {
                args.append(line)
            } else if !args.isEmpty {
                let decoded = args.map { String(data: Data(base64Encoded: $0) ?? Data(), encoding: .isoLatin1) ?? "" }
                if decoded.first == "send", decoded.count == 3,
                   let payload = Data(base64Encoded: decoded[2]) {
                    result.append(String(data: payload, encoding: .isoLatin1) ?? "")
                }
                args = []
            }
        }
        return result
    }

    func testKeysAreHeldWhileTheAnnouncementIsUp() {
        let (_, _) = makeSuspectNestedConnection()
        session.writeTask("ls\r")
        XCTAssertEqual(Self.sentKeys(session.writes.joined()), [], "\(session.writes)")
    }

    // Abandoned without the button, as when iTerm2 finds the it2ssh dead: the held keys still
    // go to the shell that took over.
    func testAbandoningGivesHeldKeysToTheShellThatTookOver() {
        let (root, _) = makeSuspectNestedConnection()
        session.writeTask("ls\r")
        session.abandonSSH(throughClientUniqueID: nestedID)
        XCTAssertTrue(session.conductor === root)
        drain(root)
        XCTAssertEqual(Self.sentKeys(session.writes.joined()), ["ls\r"], "\(session.writes)")
    }

    func testHeldKeysGoToTheShellThatTakesOverWhenTheConnectionEnds() {
        let (root, _) = makeSuspectNestedConnection()
        session.writeTask("ls\r")
        // The nested it2ssh was alive after all; its connection ends and it prints EndSSH.
        send(framed("out3", "\u{1b}]1337;EndSSH=\(nestedID)\u{07}"))
        XCTAssertTrue(session.conductor === root)
        drain(root)
        // First the line that releases it2ssh, then the held keys.
        let newline = session.writes.firstIndex(of: "\u{03}\n")
        XCTAssertNotNil(newline, "\(session.writes)")
        XCTAssertEqual(Self.sentKeys(session.writes[..<(newline ?? 0)].joined()), [], "\(session.writes)")
        XCTAssertEqual(Self.sentKeys(session.writes[((newline ?? 0) + 1)...].joined()), ["ls\r"],
                       "\(session.writes)")
    }
}

//
//  ConductorIT2CommandTests.swift
//  iTerm2
//
//  Pins the wire format of the it2 proxy framer commands. framer.py's mainloop
//  splits a command into newline-separated, individually base64-encoded args and
//  dispatches on the first (see handle_it2listen/handle_it2send/handle_it2close in
//  OtherResources/framer.py, covered by tests/framer_it2_test.py). The Swift side
//  must therefore emit exactly "it2listen\n<path>", "it2send\n<connid>\n<base64>",
//  and "it2close\n<connid>".
//

import XCTest
@testable import iTerm2SharedARC

final class ConductorIT2CommandTests: XCTestCase {

    func testIT2ListenStringValue() {
        let cmd = Conductor.Command.framerIT2Listen(path: "/tmp/it2.sock")
        XCTAssertEqual(cmd.stringValue, "it2listen\n/tmp/it2.sock")
        XCTAssertTrue(cmd.isFramer)
    }

    func testIT2SendStringValueBase64EncodesData() {
        // base64("hi") == "aGk=". framer b64-decodes arg[1] back to the raw bytes.
        let cmd = Conductor.Command.framerIT2Send(connid: "c5", data: Data("hi".utf8))
        XCTAssertEqual(cmd.stringValue, "it2send\nc5\naGk=")
        XCTAssertTrue(cmd.isFramer)
    }

    func testIT2SendRoundTripsArbitraryBytes() {
        let bytes = Data((0...255).map { UInt8($0) })
        let cmd = Conductor.Command.framerIT2Send(connid: "conn9", data: bytes)
        let parts = cmd.stringValue.components(separatedBy: "\n")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], "it2send")
        XCTAssertEqual(parts[1], "conn9")
        XCTAssertEqual(Data(base64Encoded: parts[2]), bytes)
    }

    func testIT2CloseStringValue() {
        let cmd = Conductor.Command.framerIT2Close(connid: "c5")
        XCTAssertEqual(cmd.stringValue, "it2close\nc5")
        XCTAssertTrue(cmd.isFramer)
    }

    // The it2 auth nonce + socket path must survive conductor state restoration, or
    // it2-over-ssh would silently stop working after a restore. (The separate SSH
    // recovery path re-reads them from the framer env; see didResynchronize.)
    func testIT2NonceAndSocketPersistAcrossRestorableStateCoding() throws {
        let state = Conductor.RestorableState(
            sshargs: "localhost",
            varsToSend: [:],
            clientVars: [:],
            payloads: [],
            initialDirectory: nil,
            shouldInjectShellIntegration: true,
            parsedSSHArguments: ParsedSSHArguments("localhost", booleanArgs: "",
                                                   hostnameFinder: iTermHostnameFinder()),
            depth: 0,
            parentState: nil,
            framedPID: nil,
            state: .ground,
            queue: [],
            boolArgs: "",
            dcsID: "dcs",
            clientUniqueID: "cid",
            modifiedVars: nil,
            modifiedCommandArgs: nil,
            homeDirectory: "/home/u",
            shell: "/bin/zsh",
            uname: nil,
            _terminalConfiguration: nil,
            discoveredHostname: nil,
            it2Nonce: "the-nonce",
            it2SocketPath: "/home/u/.iterm2/it2/abc.sock")
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(Conductor.RestorableState.self, from: data)
        XCTAssertEqual(decoded.it2Nonce, "the-nonce")
        XCTAssertEqual(decoded.it2SocketPath, "/home/u/.iterm2/it2/abc.sock")
    }
}

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
}

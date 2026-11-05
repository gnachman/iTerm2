//
//  TerminalCommandCodingTests.swift
//  iTerm2
//
//  Created by George Nachman on 11/5/26.
//

import XCTest
@testable import iTerm2SharedARC

/// Terminal commands are saved in the chat database and sent to the companion app, so older builds
/// must still be able to read them.
final class TerminalCommandCodingTests: XCTestCase {
    /// TerminalCommand as older builds declare it, with a required exit code.
    private struct OldTerminalCommand: Codable {
        var username: String?
        var hostname: String?
        var directory: String?
        var command: String
        var output: String
        var exitCode: Int32
        var url: URL
    }

    private func command(exitCode: Int32?) -> TerminalCommand {
        TerminalCommand(username: "user",
                        hostname: "host",
                        directory: "/tmp",
                        command: "ls",
                        output: "a\nb",
                        exitCode: exitCode,
                        url: URL(string: "iterm2:///command")!)
    }

    private func roundTrip(_ command: TerminalCommand) throws -> TerminalCommand {
        try JSONDecoder().decode(TerminalCommand.self, from: JSONEncoder().encode(command))
    }

    func testExitCodeRoundTrips() throws {
        let decoded = try roundTrip(command(exitCode: 3))
        XCTAssertEqual(decoded.exitCode, 3)
        XCTAssertEqual(decoded.command, "ls")
        XCTAssertEqual(decoded.output, "a\nb")
        XCTAssertEqual(decoded.username, "user")
        XCTAssertEqual(decoded.hostname, "host")
        XCTAssertEqual(decoded.directory, "/tmp")
        XCTAssertEqual(decoded.url, URL(string: "iterm2:///command")!)
    }

    func testAbortedCommandRoundTrips() throws {
        XCTAssertNil(try roundTrip(command(exitCode: nil)).exitCode)
    }

    /// An exit status of 0 is not an abort.
    func testZeroExitCodeIsNotAnAbort() throws {
        XCTAssertEqual(try roundTrip(command(exitCode: 0)).exitCode, 0)
    }

    /// Older builds decode the exit code as required, so an aborted command must still carry one.
    func testOlderBuildsDecodeAnAbortedCommand() throws {
        let data = try JSONEncoder().encode(command(exitCode: nil))
        let old = try JSONDecoder().decode(OldTerminalCommand.self, from: data)
        XCTAssertEqual(old.exitCode, 0)
        XCTAssertEqual(old.command, "ls")
    }

    /// What older builds wrote reads as having exited.
    func testOlderBuildsEncodingDecodes() throws {
        let old = OldTerminalCommand(username: nil,
                                     hostname: nil,
                                     directory: nil,
                                     command: "ls",
                                     output: "",
                                     exitCode: 2,
                                     url: URL(string: "iterm2:///command")!)
        let decoded = try JSONDecoder().decode(TerminalCommand.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(decoded.exitCode, 2)
    }
}

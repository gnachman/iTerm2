//
//  ConductorCommandEncodingTests.swift
//  iTerm2 ModernTests
//
//  How the conductor writes a framer command: each argument base64-encoded on its own line,
//  long lines continued with a trailing backslash, and a blank line to end the command.
//  framer.py's mainloop reads it back the way `decode` below does.
//

import XCTest
@testable import iTerm2SharedARC

final class ConductorCommandEncodingTests: XCTestCase {
    /// framer.py's mainloop: a line ending in a backslash continues on the next line, and a
    /// blank line ends the command. Returns the commands it would run.
    private func decode(_ text: String) -> [[String]] {
        var commands = [[String]]()
        var args = [String]()
        for line in text.components(separatedBy: "\n").dropLast() {
            if line.isEmpty {
                commands.append(args.map(decodeArgument))
                args = []
            } else if let last = args.last, last.hasSuffix("\\") {
                args[args.count - 1] = String(last.dropLast()) + line
            } else {
                args.append(line)
            }
        }
        XCTAssertEqual(args, [], "unterminated command")
        return commands
    }

    /// Python's b64decode, unlike Data(base64Encoded:), reads "=" as empty.
    private func decodeArgument(_ line: String) -> String {
        if line == "=" {
            return ""
        }
        guard let data = Data(base64Encoded: line), let string = String(data: data, encoding: .utf8) else {
            XCTFail("undecodable argument \(line)")
            return ""
        }
        return string
    }

    private func wire(_ arguments: [String]) -> String {
        // write() adds the newline that makes the blank line.
        return Conductor.encode(arguments: arguments, isFramer: true, linePrefix: "") + "\n"
    }

    func testEveryArgumentLengthRoundTrips() {
        // Covers cuts at, just before, and just after every argument boundary.
        for n in 0..<400 {
            let arguments = ["file", "suggest", "a", "/", "/" + String(repeating: "p", count: n),
                             "r", "10"]
            XCTAssertEqual(decode(wire(arguments)), [arguments], "n=\(n)")
        }
    }

    func testEmptyArgumentDoesNotEndTheCommand() {
        let arguments = ["getenv", "", "PATH"]
        XCTAssertEqual(decode(wire(arguments)), [arguments])
    }

    func testRegistrationCommandsUseTheFramersNames() {
        // framer.py's HANDLERS has "register" and "deregister".
        XCTAssertEqual(Conductor.Command.framerRegister(pid: 7).wireArguments, ["register", "7"])
        XCTAssertEqual(Conductor.Command.framerDeregister(pid: 7).wireArguments, ["deregister", "7"])
    }

    func testLongArgumentIsContinued() {
        let long = String(repeating: "x", count: 1000)
        let text = wire(["run", long])
        XCTAssertTrue(text.components(separatedBy: "\n").allSatisfy { $0.count <= 129 })
        XCTAssertEqual(decode(text), [["run", long]])
    }
}

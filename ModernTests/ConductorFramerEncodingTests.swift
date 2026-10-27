//
//  ConductorFramerEncodingTests.swift
//  iTerm2
//
//  Round-trips framer commands through Conductor.encodeForWire and a decoder that
//  follows framer.py's mainloop: each physical line that is not empty either
//  continues the previous argument (when that argument ends with a backslash, which
//  is dropped) or starts a new one; an empty line ends the command, and every
//  argument is then base64-decoded. Long arguments are split into lines of at most
//  128 characters plus the backslash, so an empty line must never appear inside a
//  command or framer.py cuts it in two.
//

import XCTest
@testable import iTerm2SharedARC

final class ConductorFramerEncodingTests: XCTestCase {

    // Mirrors mainloop() in OtherResources/framer.py. Returns one array of decoded
    // arguments per command found in `wire`, plus any argument lines left over after
    // the last empty line.
    private func framerDecode(_ wire: String) -> (commands: [[String]], leftover: [String]) {
        var commands = [[String]]()
        var args = [String]()
        var lines = wire.components(separatedBy: "\n")
        // The wire ends with a newline, so the final component is the empty text
        // after it, not a line framer.py reads.
        if lines.last == "" {
            lines.removeLast()
        }
        for line in lines {
            if !line.isEmpty {
                if let last = args.last, last.hasSuffix("\\") {
                    args[args.count - 1] = String(last.dropLast()) + line
                } else {
                    args.append(line)
                }
            } else {
                commands.append(args.map { arg in
                    guard let data = Data(base64Encoded: arg),
                          let string = String(data: data, encoding: .utf8) else {
                        return "<undecodable: \(arg)>"
                    }
                    return string
                })
                args = []
            }
        }
        return (commands, args)
    }

    private func assertRoundTrips(_ command: Conductor.Command,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        // Conductor.write(_:) appends a newline, producing the empty line that ends
        // the command.
        let wire = Conductor.encodeForWire(command, linePrefix: "") + "\n"
        let expected = command.stringValue.components(separatedBy: "\n")
        let (commands, leftover) = framerDecode(wire)
        XCTAssertEqual(commands, [expected], file: file, line: line)
        XCTAssertEqual(leftover, [], file: file, line: line)
        for physicalLine in wire.components(separatedBy: "\n") {
            XCTAssertLessThanOrEqual(physicalLine.count, 129, file: file, line: line)
        }
    }

    // Each argument's base64 length is a multiple of 4, so the newline after the
    // fifth argument lands at offset 128 when the first five encoded arguments plus
    // their four separating newlines total 128 characters.
    func testNewlineExactlyAtOffset128() {
        // base64("login") is 8 characters; a 78-character cwd encodes to 104; each
        // one-character arg encodes to 4. 8 + 104 + 4 + 4 + 4 + 4 newlines == 128.
        let cwd = String(repeating: "c", count: 78)
        let command = Conductor.Command.framerLogin(cwd: cwd, args: ["a", "b", "c", "d"])
        let joined = command.stringValue.components(separatedBy: "\n")
            .map(\.base64Encoded)
            .joined(separator: "\n")
        let offset = joined.index(joined.startIndex, offsetBy: 128)
        XCTAssertEqual(joined[offset], "\n", "Test setup should put a newline at offset 128")
        assertRoundTrips(command)
    }

    // Sweeps argument lengths so newlines land on every offset near 128 and 256,
    // including just before and after each boundary.
    func testNewlinesAtEveryOffsetRoundTrip() {
        for cwdLength in 1...300 {
            for argCount in 1...9 {
                let command = Conductor.Command.framerLogin(
                    cwd: String(repeating: "x", count: cwdLength),
                    args: (0..<argCount).map { String(repeating: "y", count: $0 % 4 + 1) })
                assertRoundTrips(command)
            }
        }
    }

    func testLongSingleArgumentRoundTrips() {
        let data = Data((0..<2000).map { UInt8($0 % 256) })
        assertRoundTrips(.framerIT2Send(connid: "conn1", data: data))
    }

    func testFramerSaveWithManyVariablesRoundTrips() {
        var dict = [String: String]()
        for i in 0..<40 {
            dict["VAR\(i)"] = String(repeating: "v", count: i * 3)
        }
        assertRoundTrips(.framerSave(dict))
    }

    // An interactive session whose injected shell needed arguments (bash's --posix) asks the
    // framer to exec that shell as the login shell, so ~/.profile runs in the interactive shell.
    func testInjectedInteractiveBashExecsTheShellAsLoginShell() {
        let args = Conductor.framerLoginArgs(modifiedCommandArgs: ["/bin/bash", "--posix"],
                                             commandArgs: [])
        XCTAssertEqual(args, ["--iterm2-exec-login", "/bin/bash", "--posix"])
        let command = Conductor.Command.framerLogin(cwd: "$HOME", args: args)
        XCTAssertEqual(command.stringValue, "login\n$HOME\n--iterm2-exec-login\n/bin/bash\n--posix")
        assertRoundTrips(command)
    }

    // A command the user gave keeps going through the login shell's -c.
    func testCustomCommandKeepsTheOldForm() {
        XCTAssertEqual(Conductor.framerLoginArgs(modifiedCommandArgs: ["/bin/bash", "--posix", "-l"],
                                                 commandArgs: ["/bin/bash", "-l"]),
                       ["/bin/bash", "--posix", "-l"])
        XCTAssertEqual(Conductor.framerLoginArgs(modifiedCommandArgs: nil,
                                                 commandArgs: ["ls", "-l"]),
                       ["ls", "-l"])
    }

    // Env-only injection (zsh, fish, xonsh, nu) and no injection: the login shell, interactively.
    func testPlainSessionWithoutInjectedArgumentsSendsNoArgs() {
        XCTAssertEqual(Conductor.framerLoginArgs(modifiedCommandArgs: [], commandArgs: []), [])
        XCTAssertEqual(Conductor.framerLoginArgs(modifiedCommandArgs: nil, commandArgs: []), [])
    }
}

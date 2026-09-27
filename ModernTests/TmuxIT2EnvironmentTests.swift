//
//  TmuxIT2EnvironmentTests.swift
//  ModernTests
//
//  The commands a tmux controller sends on attach and detach so that `it2` inside a pane reaches
//  the connection currently showing it: one global user option per attached client, keyed by the
//  hex-encoded tmux client name, holding a tagged, hex-encoded JSON record. Pure string building;
//  never talks to tmux. The readers (it2.py, it2cli's TmuxOwnership) have their own tests against
//  the same wire form, so a change here that breaks them shows up on both sides.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxIT2EnvironmentTests: XCTestCase {
    private func hex(_ string: String) -> String {
        return Data(string.utf8).map { String(format: "%02x", $0) }.joined()
    }

    // "/dev/pts/3" is a real tmux client name, and no character of it survives into the option
    // name: the mapping is hex both ways so it2 and the detach handler can invert it.
    func testOptionNameIsHexOfClientName() {
        XCTAssertEqual(TmuxController.it2ClientOptionName(forTmuxClientName: "/dev/pts/3"),
                       "@it2_client_2f6465762f7074732f33")
    }

    func testRemoteRecordIsTaggedHexOfSortedJSON() {
        let command = TmuxController.commandAdvertisingIT2ClientRecord(
            ["sock": "/home/u/.iterm2/it2/abc.sock", "nonce": "deadbeef"],
            tmuxClientName: "/dev/pts/3")
        let json = "{\"nonce\":\"deadbeef\",\"sock\":\"/home/u/.iterm2/it2/abc.sock\"}"
        XCTAssertEqual(command, "set -g @it2_client_2f6465762f7074732f33 \"c_\(hex(json))\"")
    }

    func testLocalRecord() {
        let command = TmuxController.commandAdvertisingIT2ClientRecord(["suite": "iTerm2"],
                                                                       tmuxClientName: "/dev/ttys004")
        XCTAssertEqual(command, "set -g @it2_client_\(hex("/dev/ttys004")) \"c_\(hex("{\"suite\":\"iTerm2\"}"))\"")
    }

    // The value is hex, so nothing in a socket path or client name can end or escape the quoted
    // argument, and nothing needs escaping.
    func testAwkwardCharactersNeverReachTheWire() {
        let command = TmuxController.commandAdvertisingIT2ClientRecord(
            ["sock": "/tmp/od\"d\\path $HOME/it2.sock"],
            tmuxClientName: "client-\"1\"")
        XCTAssertNotNil(command)
        let body = command!.dropFirst("set -g ".count)
        XCTAssertTrue(body.allSatisfy { $0.isHexDigit || $0 == "@" || $0 == "_" || $0 == "\"" || $0 == " " || $0.isLetter },
                      "got \(command!)")
        XCTAssertFalse(body.contains("$"))
        XCTAssertFalse(body.contains("\\"))
    }

    func testWithdrawUnsetsTheSameOption() {
        XCTAssertEqual(TmuxController.commandWithdrawingIT2ClientRecord(forTmuxClientName: "/dev/pts/3"),
                       "set -gu @it2_client_2f6465762f7074732f33")
    }

    // The value must round-trip through the reader's rules: strip the tag, hex-decode, parse JSON.
    func testRecordRoundTrips() throws {
        let record = ["nonce": "deadbeef", "sock": "/home/u/.iterm2/it2/abc.sock"]
        let command = try XCTUnwrap(TmuxController.commandAdvertisingIT2ClientRecord(record,
                                                                                     tmuxClientName: "/dev/pts/3"))
        let value = try XCTUnwrap(command.split(separator: "\"").dropFirst().first)
        XCTAssertTrue(value.hasPrefix("c_"))
        let hexBody = value.dropFirst(2)
        var bytes = [UInt8]()
        var index = hexBody.startIndex
        while index < hexBody.endIndex {
            let next = hexBody.index(index, offsetBy: 2)
            bytes.append(UInt8(hexBody[index..<next], radix: 16)!)
            index = next
        }
        let decoded = try JSONSerialization.jsonObject(with: Data(bytes)) as? [String: String]
        XCTAssertEqual(decoded, record)
    }
}

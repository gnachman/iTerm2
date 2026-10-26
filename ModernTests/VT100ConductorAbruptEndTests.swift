//
//  VT100ConductorAbruptEndTests.swift
//  iTerm2
//
//  When an it2ssh connection dies abruptly (sshd killed, local ssh killed), the
//  framer never gets to send its OSC 135 unhook, so the conductor DCS hook stayed
//  in place forever. The local it2ssh still prints OSC 1337;EndSSH=<id> (BEL
//  terminated) once ssh exits, but the hooked parser swallowed it along with
//  everything after it, including the local shell's prompt, wedging the session.
//  These tests verify that the hook treats it2ssh's EndSSH as an implicit unhook
//  and leaves the EndSSH OSC for the regular parser to execute.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100ConductorAbruptEndTests: XCTestCase {
    private let clientUniqueID = "1234567890"

    private func parse(_ bytes: [UInt8], parser: VT100Parser) -> [VT100Token] {
        bytes.withUnsafeBufferPointer { buf in
            parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        _ = parser.addParsedTokens(to: &vector)
        var tokens = [VT100Token]()
        for i in 0..<CVectorCount(&vector) {
            tokens.append(CVectorGetObject(&vector, i) as! VT100Token)
        }
        return tokens
    }

    // A parser hooked into conductor mode the way conductor.sh does it:
    // "<token> <it2ssh unique id> <bool args> - <ssh args>".
    private func makeHookedParser() -> VT100Parser {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        let tokens = parse(Array("\u{1b}P2000pnone \(clientUniqueID) Ym9vbA== - c3No\n".utf8), parser: p)
        XCTAssertTrue(tokens.contains { $0.type == SSH_INIT })
        return p
    }

    private func osc134(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]134;:\(payload)\u{1b}\\".utf8)
    }

    private func osc135(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]135;:\(payload)\u{1b}\\".utf8)
    }

    // Exactly what it2ssh prints after ssh exits.
    private func endSSH(_ id: String) -> [UInt8] {
        return Array("\u{1b}]1337;EndSSH=\(id)\u{07}".utf8)
    }

    private func text(_ tokens: [VT100Token]) -> String {
        return tokens.compactMap { token -> String? in
            if token.type == VT100_ASCIISTRING {
                return token.stringForAsciiData()
            }
            if token.type == VT100_STRING {
                return token.string
            }
            return nil
        }.joined()
    }

    private func types(_ tokens: [VT100Token]) -> String {
        return tokens.map { "\($0)" }.joined(separator: "\n")
    }

    // Asserts the tokens contain an SSH_UNHOOK, then the EndSSH key-value token, and
    // that the local shell's output after it is parsed as regular text.
    private func assertUnhookedAndEnded(_ tokens: [VT100Token],
                                        localText: String,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) {
        let unhookIndex = tokens.firstIndex { $0.type == SSH_UNHOOK }
        let endIndex = tokens.firstIndex { $0.type == XTERMCC_SET_KVP && $0.kvpKey == "EndSSH" }
        XCTAssertNotNil(unhookIndex, "expected SSH_UNHOOK in:\n\(types(tokens))", file: file, line: line)
        XCTAssertNotNil(endIndex, "expected EndSSH in:\n\(types(tokens))", file: file, line: line)
        if let unhookIndex, let endIndex {
            XCTAssertLessThan(unhookIndex, endIndex, "unhook must precede EndSSH, as on a clean exit",
                              file: file, line: line)
            XCTAssertEqual(tokens[endIndex].kvpValue, clientUniqueID, file: file, line: line)
            XCTAssertEqual(text(Array(tokens[(endIndex + 1)...])), localText, file: file, line: line)
        }
    }

    // F-120/F-269: connection dies between frames. ssh's own "Connection closed" goes
    // to the tty unframed, then it2ssh prints EndSSH, then the local shell's prompt.
    func testEndSSHInGroundStateUnhooks() {
        let parser = makeHookedParser()
        var stream = osc134("%output out1 100 -1 0")
        stream += Array("remote% ".utf8)
        stream += osc134("%end out1")
        let before = parse(stream, parser: parser)
        XCTAssertEqual(text(before), "remote% ")

        var after = Array("Connection to 127.0.0.1 closed.\r\n".utf8)
        after += endSSH(clientUniqueID)
        after += Array("local% ".utf8)
        assertUnhookedAndEnded(parse(after, parser: parser), localText: "local% ")

        // Subsequent output is no longer intercepted by the hook.
        XCTAssertEqual(text(parse(Array("echo AFTER25".utf8), parser: parser)), "echo AFTER25")
    }

    // Same, but terminated with ST instead of BEL.
    func testSTTerminatedEndSSHInGroundStateUnhooks() {
        let parser = makeHookedParser()
        var after = Array("\u{1b}]1337;EndSSH=\(clientUniqueID)\u{1b}\\".utf8)
        after += Array("local% ".utf8)
        assertUnhookedAndEnded(parse(after, parser: parser), localText: "local% ")
    }

    // The connection dies partway through a framer OSC, so the next escape sequence
    // starts inside an unterminated OSC 134.
    func testEndSSHAfterTruncatedFramerOSCUnhooks() {
        let parser = makeHookedParser()
        _ = parse(Array("\u{1b}]134;:%output out1 100 -1 0".utf8), parser: parser)
        var after = Array("Connection to 127.0.0.1 closed.\r\n".utf8)
        after += endSSH(clientUniqueID)
        after += Array("local% ".utf8)
        assertUnhookedAndEnded(parse(after, parser: parser), localText: "local% ")
    }

    // An EndSSH for some other connection is ignored, and framing continues.
    func testEndSSHWithWrongIDInGroundStateIsIgnored() {
        let parser = makeHookedParser()
        var stream = endSSH("999")
        stream += osc134("%output out1 100 -1 0")
        stream += Array("still framed".utf8)
        stream += osc134("%end out1")
        let tokens = parse(stream, parser: parser)
        XCTAssertFalse(tokens.contains { $0.type == SSH_UNHOOK }, types(tokens))
        XCTAssertEqual(text(tokens), "still framed")
    }

    // Other BEL-terminated OSC 1337 sequences are still ignored while hooked.
    func testOtherOSC1337InGroundStateIsIgnored() {
        let parser = makeHookedParser()
        var stream = Array("\u{1b}]1337;SetMark\u{07}".utf8)
        stream += osc134("%output out1 100 -1 0")
        stream += Array("still framed".utf8)
        stream += osc134("%end out1")
        let tokens = parse(stream, parser: parser)
        XCTAssertFalse(tokens.contains { $0.type == SSH_UNHOOK }, types(tokens))
        XCTAssertEqual(text(tokens), "still framed")
    }

    // After restoring a session, the parser is hooked in recovery mode and never saw
    // the SSH_INIT line, so it accepts any EndSSH outside a frame.
    func testEndSSHInRecoveryModeUnhooks() {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        let tree: NSDictionary = [NSNumber(value: 100): ["dcs-id", NSDictionary()] as NSArray]
        _ = parser.startConductorRecoveryMode(withID: "dcs-id", tree: tree as! [AnyHashable: Any], clientUniqueID: nil)
        let tokens = parse(endSSH(clientUniqueID) + Array("local% ".utf8), parser: parser)
        assertUnhookedAndEnded(tokens, localText: "local% ")
    }

    // A restored session knows its it2ssh's unique ID from the restored conductor. With
    // it, an EndSSH that cuts off a %output frame unhooks, as it does before restoration.
    func testEndSSHInTruncatedOutputFrameInRecoveryModeWithKnownIDUnhooks() {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        let tree: NSDictionary = [NSNumber(value: 100): ["dcs-id", NSDictionary()] as NSArray]
        _ = parser.startConductorRecoveryMode(withID: "dcs-id",
                                              tree: tree as! [AnyHashable: Any],
                                              clientUniqueID: clientUniqueID)
        let tokens = parse(osc134("%output out1 100 -1 0") + Array("T66LI".utf8) +
                           endSSH(clientUniqueID) + Array("local% ".utf8),
                           parser: parser)
        assertUnhookedAndEnded(tokens, localText: "local% ")
    }

    // When the outermost conductor isn't framing, the nested it2ssh hooks the top-level
    // parser directly, so the outermost it2ssh's ID must not be required there.
    func testEndSSHInRecoveryModeWithNonFramingRootUnhooks() {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        let inner: NSDictionary = [NSNumber(value: 100): ["inner", NSDictionary()] as NSArray]
        let tree: NSDictionary = [NSNumber(value: 0): ["outer", inner] as NSArray]
        _ = parser.startConductorRecoveryMode(withID: "outer",
                                              tree: tree as! [AnyHashable: Any],
                                              clientUniqueID: "outer-it2ssh")
        // The EndSSH carries the inner it2ssh's ID.
        let tokens = parse(endSSH(clientUniqueID) + Array("local% ".utf8), parser: parser)
        assertUnhookedAndEnded(tokens, localText: "local% ")
    }

    // A nested it2ssh's EndSSH relayed inside %output still doesn't unhook a restored
    // session's parser.
    func testOtherEndSSHInOutputFrameInRecoveryModeDoesNotUnhook() {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        let tree: NSDictionary = [NSNumber(value: 100): ["dcs-id", NSDictionary()] as NSArray]
        _ = parser.startConductorRecoveryMode(withID: "dcs-id",
                                              tree: tree as! [AnyHashable: Any],
                                              clientUniqueID: clientUniqueID)
        let tokens = parse(osc134("%output out1 100 -1 0") + endSSH("nested") +
                           Array("still framed".utf8) + osc134("%end out1"),
                           parser: parser)
        XCTAssertFalse(tokens.contains { $0.type == SSH_UNHOOK }, types(tokens))
    }

    // An EndSSH inside a cut-off %output frame can be split across reads.
    func testEndSSHInTruncatedOutputFrameSplitAcrossReads() {
        let parser = makeHookedParser()
        _ = parse(osc134("%output out1 100 -1 0") + Array("partial".utf8), parser: parser)
        let full = endSSH(clientUniqueID) + Array("local% ".utf8)
        let cut = 12
        let first = parse(Array(full[..<cut]), parser: parser)
        XCTAssertFalse(first.contains { $0.type == SSH_UNHOOK })
        assertUnhookedAndEnded(parse(Array(full[cut...]), parser: parser), localText: "local% ")
    }

    // The EndSSH OSC can arrive split across reads.
    func testEndSSHSplitAcrossReads() {
        let parser = makeHookedParser()
        let full = endSSH(clientUniqueID) + Array("local% ".utf8)
        let cut = 10
        let first = parse(Array(full[..<cut]), parser: parser)
        XCTAssertFalse(first.contains { $0.type == SSH_UNHOOK })
        assertUnhookedAndEnded(parse(Array(full[cut...]), parser: parser), localText: "local% ")
    }

    // Connection dies while a pre-framer command is running (body state).
    func testEndSSHInBodyStateUnhooks() {
        let parser = makeHookedParser()
        let begun = parse(osc135("begin abc"), parser: parser)
        XCTAssertTrue(begun.contains { $0.type == SSH_BEGIN })
        let tokens = parse(endSSH(clientUniqueID) + Array("local% ".utf8), parser: parser)
        assertUnhookedAndEnded(tokens, localText: "local% ")
    }

    // Connection dies in the middle of a %output frame, so its %end never arrives.
    func testEndSSHInTruncatedOutputFrameUnhooks() {
        let parser = makeHookedParser()
        var stream = osc134("%output out1 100 -1 0")
        stream += Array("partial".utf8)
        _ = parse(stream, parser: parser)
        let tokens = parse(endSSH(clientUniqueID) + Array("local% ".utf8), parser: parser)
        assertUnhookedAndEnded(tokens, localText: "local% ")
    }

    // A nested it2ssh on the remote host prints its own EndSSH, which reaches us inside
    // a %output frame. It belongs to the child and must not unhook this conductor.
    func testNestedEndSSHInsideOutputDoesNotUnhook() {
        let parser = makeHookedParser()
        var stream = osc134("%output out1 100 -1 0")
        stream += endSSH("999")
        stream += Array("inner".utf8)
        stream += osc134("%end out1")
        stream += osc134("%output out2 100 -1 0")
        stream += Array("still framed".utf8)
        stream += osc134("%end out2")
        let tokens = parse(stream, parser: parser)
        XCTAssertFalse(tokens.contains { $0.type == SSH_UNHOOK }, types(tokens))
        XCTAssertEqual(text(tokens), "innerstill framed")
    }
}

//
//  VT100ConductorForceUnhookTests.swift
//  iTerm2
//
//  F-482: when the local it2ssh process is killed, nothing ever sends the framer's
//  unhook or it2ssh's EndSSH, so the conductor DCS hook swallows the local shell's
//  output forever. Disconnect must be able to force the hook off by its DCS ID.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100ConductorForceUnhookTests: XCTestCase {
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

    // Returns the parser and the DCS ID of its conductor hook.
    private func makeHookedParser() -> (VT100Parser, String) {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        let tokens = parse(Array("\u{1b}P2000pnone 1234567890 Ym9vbA== - c3No\n".utf8), parser: p)
        XCTAssertTrue(tokens.contains { $0.type == SSH_INIT })
        let hookToken = tokens.first { $0.type == DCS_SSH_HOOK }
        XCTAssertNotNil(hookToken)
        return (p, hookToken?.string ?? "")
    }

    func testForceUnhookWithMatchingIDRestoresPlainParsing() {
        let (parser, dcsID) = makeHookedParser()
        // The local shell's prompt is swallowed while hooked.
        XCTAssertEqual(text(parse(Array("local% ".utf8), parser: parser)), "")

        XCTAssertTrue(parser.forceUnhookDCSReturningSuccess(dcsID))
        XCTAssertEqual(text(parse(Array("local% ".utf8), parser: parser)), "local% ")
    }

    func testForceUnhookWithOtherIDDoesNothing() {
        let (parser, _) = makeHookedParser()
        XCTAssertFalse(parser.forceUnhookDCSReturningSuccess("not-the-id"))
        XCTAssertEqual(text(parse(Array("local% ".utf8), parser: parser)), "")
    }

    private func osc134(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]134;:\(payload)\u{1b}\\".utf8)
    }

    // A nested it2ssh dies on the remote host: its conductor's hook lives in the parser
    // for the remote shell's %output, and Disconnect must be able to remove it.
    func testForceUnhookNestedConductor() {
        let (parser, _) = makeHookedParser()
        var hook = osc134("%output out1 100 -1 0")
        hook += Array("\u{1b}P2000pnone 555 Ym9vbA== - c3No\n".utf8)
        hook += osc134("%end out1")
        let hookToken = parse(hook, parser: parser).first { $0.type == DCS_SSH_HOOK }
        let nestedID = hookToken?.string ?? ""
        XCTAssertFalse(nestedID.isEmpty)

        var output = osc134("%output out2 100 -1 0")
        output += Array("hostA% ".utf8)
        output += osc134("%end out2")
        XCTAssertEqual(text(parse(output, parser: parser)), "")

        XCTAssertTrue(parser.forceUnhookDCSReturningSuccess(nestedID))
        output = osc134("%output out3 100 -1 0")
        output += Array("hostA% ".utf8)
        output += osc134("%end out3")
        XCTAssertEqual(text(parse(output, parser: parser)), "hostA% ")
    }

    func testForceUnhookIsIdempotent() {
        let (parser, dcsID) = makeHookedParser()
        XCTAssertTrue(parser.forceUnhookDCSReturningSuccess(dcsID))
        XCTAssertFalse(parser.forceUnhookDCSReturningSuccess(dcsID))
    }
}

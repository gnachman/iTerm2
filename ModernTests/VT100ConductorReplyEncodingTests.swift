//
//  VT100ConductorReplyEncodingTests.swift
//  iTerm2 ModernTests
//
//  framer.py writes the text of its replies and notifications as UTF-8, so the conductor
//  parser must read OSC 134 payloads as UTF-8: a remote PATH, a runpy result, or an error
//  message naming a path can have non-ASCII text.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100ConductorReplyEncodingTests: XCTestCase {
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

    private func makeHookedParser() -> VT100Parser {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        _ = parse(Array("\u{1b}P2000p0 boolargs -\n".utf8), parser: p)
        return p
    }

    private func osc134(_ payload: [UInt8]) -> [UInt8] {
        return Array("\u{1b}]134;:".utf8) + payload + Array("\u{1b}\\".utf8)
    }

    private func replyLines(_ line: [UInt8]) -> [String] {
        let parser = makeHookedParser()
        let stream = osc134(Array("begin r1".utf8)) + osc134(line) + osc134(Array("end r1 0 r".utf8))
        let tokens = parse(stream, parser: parser)
        XCTAssertEqual(tokens.filter { $0.type == SSH_END }.count, 1, "\(tokens.map { $0.type })")
        return tokens.filter { $0.type == SSH_LINE }.map { $0.string ?? "" }
    }

    func testUTF8ReplyTextArrivesIntact() {
        let text = "/Users/zoë/bin:/opt/café ☕"
        XCTAssertEqual(replyLines(Array(text.utf8)), [text])
    }

    func testBytesThatAreNotUTF8StillArriveOneCharacterApiece() {
        XCTAssertEqual(replyLines([0x61, 0xff, 0x62]), ["a\u{ff}b"])
    }
}

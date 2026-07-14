//
//  VT100ConductorIT2ParserTests.swift
//  iTerm2
//
//  Verifies that a framer "%it2" conductor frame is delivered to the terminal as
//  a single SSH_IT2 token carrying the whole line. Unlike %output (which is fed
//  back through a child VT100Parser and can be split across many VT100_STRING
//  tokens), an it2 frame must never be fragmented: the demux reconstructs a
//  length-prefixed binary protocol from these payloads, so a partial line would
//  corrupt it. This is the regression test for the "deliver whole, no re-parse"
//  design of SSH_IT2.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100ConductorIT2ParserTests: XCTestCase {

    // Feed raw bytes to a parser and return all produced tokens.
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

    // A parser already hooked into conductor mode, ready to accept OSC 134 frames.
    private func makeHookedParser() -> VT100Parser {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        // ESC P 2000 p establishes the SSH conductor hook; the first line after it
        // is the SSH_INIT payload, after which the parser is in the ground state
        // and consumes OSC 134 framer frames.
        let hook = Array("\u{1b}P2000p0 boolargs -\n".utf8)
        _ = parse(hook, parser: p)
        return p
    }

    private func osc134(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]134;:\(payload)\u{1b}\\".utf8)
    }

    func testIT2FrameDeliveredWhole() {
        let parser = makeHookedParser()
        // A payload comfortably larger than the ~1KB boundary at which the %output
        // re-parse path would have split output into multiple tokens.
        let b64 = String(repeating: "QUJD", count: 1024)  // 4096 base64 chars
        let payload = "conn5 data \(b64)"
        let tokens = parse(osc134("%it2 \(payload)"), parser: parser)

        let it2 = tokens.filter { $0.type == SSH_IT2 }
        XCTAssertEqual(it2.count, 1, "expected exactly one SSH_IT2 token, got \(tokens.map { $0.type })")
        XCTAssertEqual(it2.first?.string, payload, "the whole %it2 line must arrive intact")
    }

    func testIT2OpenAndCloseFrames() {
        let parser = makeHookedParser()
        let tokens = parse(osc134("%it2 conn5 open") + osc134("%it2 conn5 close"),
                           parser: parser)
        let it2 = tokens.filter { $0.type == SSH_IT2 }
        XCTAssertEqual(it2.map { $0.string }, ["conn5 open", "conn5 close"])
    }

    func testIT2FrameSplitAcrossReadsIsReassembled() {
        let parser = makeHookedParser()
        let b64 = String(repeating: "QUJD", count: 256)  // 1024 base64 chars
        let payload = "conn7 data \(b64)"
        let full = osc134("%it2 \(payload)")
        // Split mid-payload across two putStreamData calls: the parser must block
        // until the ST terminator arrives and still emit exactly one whole token.
        let cut = full.count / 2
        let first = parse(Array(full[..<cut]), parser: parser)
        XCTAssertTrue(first.filter { $0.type == SSH_IT2 }.isEmpty,
                      "no it2 token should be emitted before the frame is complete")
        let second = parse(Array(full[cut...]), parser: parser)
        let it2 = second.filter { $0.type == SSH_IT2 }
        XCTAssertEqual(it2.count, 1)
        XCTAssertEqual(it2.first?.string, payload)
    }

    func testNestedIT2FrameGetsChildDepth() {
        // A %it2 frame from a nested ssh (B) arrives wrapped in the outer (A)
        // conductor's %output. The SSH_OUTPUT re-parse must still yield one intact
        // SSH_IT2 token AND tag it with the child depth, so Conductor.handleIT2
        // routes it to the conductor at the right nesting level.
        let parser = makeHookedParser()  // outer conductor, depth 0
        // The %output body is the inner conductor's own byte stream: its DCS hook,
        // its init line, then a %it2 frame.
        var inner = Array("\u{1b}P2000p0 boolargs -\n".utf8)
        inner += osc134("%it2 conn5 open")
        var stream = osc134("%output out1 100 -1 0")  // identifier pid channel depth
        stream += inner
        stream += osc134("%end out1")
        let tokens = parse(stream, parser: parser)

        let it2 = tokens.filter { $0.type == SSH_IT2 }
        XCTAssertEqual(it2.count, 1, "one SSH_IT2 out of the nested stream: \(tokens.map { $0.type })")
        XCTAssertEqual(it2.first?.string, "conn5 open")
        // SSHInfo's depth/valid are C bitfields (not visible to Swift as fields), so
        // read them through the inline description helper.
        let info = SSHInfoDescription(it2.first!.sshInfo)
        XCTAssertFalse(info.contains("invalid"), "nested token must carry valid ssh info: \(info)")
        XCTAssertTrue(info.contains("depth=1"), "nested token must be at child depth 1: \(info)")
    }
}

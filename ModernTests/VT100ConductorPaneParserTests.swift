//
//  VT100ConductorPaneParserTests.swift
//  iTerm2
//
//  A pane process (framer `pane`, a workgroup peer's program run through the leader's framer)
//  sends its output as %output on the pane channel. Those bytes belong to another session's
//  terminal, so the leader's parser must hand them over untouched as one SSH_OUTPUT token:
//  never parse them into the leader's screen, never turn them into side-channel text, and
//  keep them at any nesting depth, tagged with the depth of the framer that sent them.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100ConductorPaneParserTests: XCTestCase {
    private let paneChannel = Int32(SSH_OUTPUT_PANE_CHANNEL)

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

    private func osc134(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]134;:\(payload)\u{1b}\\".utf8)
    }

    private func paneOutput(_ tokens: [VT100Token]) -> [VT100Token] {
        return tokens.filter { $0.type == SSH_OUTPUT && $0.csi.pointee.p.1 == paneChannel }
    }

    // Anything that would land in the leader's screen or in the conductor's side channel.
    private func leaked(_ tokens: [VT100Token]) -> [VT100Token] {
        return tokens.filter { !VT100TokenTypeIsSSHMeta($0.type) && $0.type != DCS_SSH_HOOK }
    }

    // Terminal output, escape sequences and all, including bytes that are not UTF-8.
    private let payload: [UInt8] = Array("\u{1b}[31mred\u{1b}[m\r\n\u{1b}[?1049h".utf8) + [0xff, 0x41]

    func testPaneOutputIsHandedOverUntouched() {
        let parser = makeHookedParser()
        let tokens = parse(osc134("%output out1 4242 3 0") + payload + osc134("%end out1"),
                           parser: parser)

        let output = paneOutput(tokens)
        XCTAssertEqual(output.count, 1, "one token: \(tokens.map { $0.type })")
        XCTAssertEqual(output.first?.csi.pointee.p.0, 4242)
        XCTAssertEqual(output.first?.savedData, Data(payload))
        XCTAssertEqual(leaked(tokens).map { $0.type }, [])
    }

    func testPaneOutputDoesNotDisturbTheLoginShellsOutput() {
        let parser = makeHookedParser()
        var stream = osc134("%output out1 100 -1 0") + Array("leader".utf8) + osc134("%end out1")
        stream += osc134("%output out2 4242 3 0") + payload + osc134("%end out2")
        stream += osc134("%output out3 100 -1 0") + Array(" again".utf8) + osc134("%end out3")
        let tokens = parse(stream, parser: parser)

        XCTAssertEqual(paneOutput(tokens).map { $0.savedData }, [Data(payload)])
        let leaderText = tokens
            .filter { $0.type == VT100_ASCIISTRING || $0.type == VT100_STRING || $0.type == VT100_GANG }
            .map { $0.string ?? $0.stringForAsciiData() }
            .joined()
        XCTAssertEqual(leaderText, "leader again")
    }

    func testPaneOutputSplitAcrossReadsArrivesWhole() {
        let parser = makeHookedParser()
        let full = osc134("%output out1 4242 3 0") + payload + osc134("%end out1")
        let cut = osc134("%output out1 4242 3 0").count + 4
        let first = parse(Array(full[..<cut]), parser: parser)
        let second = parse(Array(full[cut...]), parser: parser)

        XCTAssertEqual(paneOutput(first), [])
        XCTAssertEqual(paneOutput(second).map { $0.savedData }, [Data(payload)])
        XCTAssertEqual(leaked(first + second).map { $0.type }, [])
    }

    func testNestedPaneOutputCarriesTheInnerFramersDepth() {
        // A pane on the inner host of a two-hop connection: its %output comes from the inner
        // framer, inside the outer framer's login-shell output.
        let parser = makeHookedParser()
        var inner = Array("\u{1b}P2000p0 boolargs -\n".utf8)
        inner += osc134("%output in1 777 3 1") + payload + osc134("%end in1")
        let tokens = parse(osc134("%output out1 100 -1 0") + inner + osc134("%end out1"),
                           parser: parser)

        let output = paneOutput(tokens)
        XCTAssertEqual(output.count, 1, "one token: \(tokens.map { $0.type })")
        XCTAssertEqual(output.first?.csi.pointee.p.0, 777)
        XCTAssertEqual(output.first?.savedData, Data(payload))
        let info = output.first.map { SSHInfoDescription($0.sshInfo) } ?? ""
        XCTAssertTrue(info.contains("depth=1"), "inner framer's depth: \(info)")
        XCTAssertEqual(leaked(tokens).map { $0.type }, [])
    }
}

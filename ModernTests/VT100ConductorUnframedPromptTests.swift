//
//  VT100ConductorUnframedPromptTests.swift
//  iTerm2
//
//  F-482: when an it2ssh process dies without sending EndSSH, the shell it was
//  started from prints its prompt into a conductor hook that only expects framed
//  output. A shell-integration prompt mark outside the framing is the best sign
//  that this happened, so the hook reports it (once) as SSH_UNFRAMED_PROMPT.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100ConductorUnframedPromptTests: XCTestCase {
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
        let tokens = parse(Array("\u{1b}P2000pnone 1234567890 Ym9vbA== - c3No\n".utf8), parser: p)
        XCTAssertTrue(tokens.contains { $0.type == SSH_INIT })
        return p
    }

    private func osc134(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]134;:\(payload)\u{1b}\\".utf8)
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

    private func unframedPrompts(_ tokens: [VT100Token]) -> [VT100Token] {
        return tokens.filter { $0.type == SSH_UNFRAMED_PROMPT }
    }

    // What bash with iTerm2 shell integration prints when it2ssh dies under it.
    private let localPrompt = Array("\u{1b}]133;D;137\u{07}\u{1b}]133;A\u{07}local% \u{1b}]133;B\u{07}".utf8)

    func testBELTerminatedPromptMarkInGroundStateIsReported() {
        let parser = makeHookedParser()
        let tokens = parse(localPrompt, parser: parser)
        let prompts = unframedPrompts(tokens)
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.sshInfo.valid, 0, "the outermost hook’s token has depth 0")
    }

    func testSTTerminatedPromptMarkInGroundStateIsReported() {
        let parser = makeHookedParser()
        let tokens = parse(Array("\u{1b}]133;A\u{1b}\\local% ".utf8), parser: parser)
        XCTAssertEqual(unframedPrompts(tokens).count, 1)
    }

    func testOtherShellIntegrationMarksAreNotReported() {
        let parser = makeHookedParser()
        let tokens = parse(Array("\u{1b}]133;D;0\u{07}\u{1b}]133;B\u{07}\u{1b}]133;C\u{07}".utf8), parser: parser)
        XCTAssertTrue(unframedPrompts(tokens).isEmpty)
    }

    func testPromptMarkIsReportedOnlyOncePerHook() {
        let parser = makeHookedParser()
        XCTAssertEqual(unframedPrompts(parse(localPrompt, parser: parser)).count, 1)
        XCTAssertTrue(unframedPrompts(parse(localPrompt, parser: parser)).isEmpty)
    }

    func testFramingContinuesAfterUnframedPrompt() {
        let parser = makeHookedParser()
        var stream = localPrompt
        stream += osc134("%output out1 100 -1 0")
        stream += Array("remote% ".utf8)
        stream += osc134("%end out1")
        let tokens = parse(stream, parser: parser)
        XCTAssertEqual(unframedPrompts(tokens).count, 1)
        XCTAssertEqual(text(tokens), "remote% ")
    }

    // The remote shell's own prompt marks arrive inside %output and are not unframed.
    func testPromptMarkInsideOutputFrameIsNotReported() {
        let parser = makeHookedParser()
        var stream = osc134("%output out1 100 -1 0")
        stream += Array("\u{1b}]133;A\u{07}remote% ".utf8)
        stream += osc134("%end out1")
        let tokens = parse(stream, parser: parser)
        XCTAssertTrue(unframedPrompts(tokens).isEmpty)
        XCTAssertEqual(text(tokens), "remote% ")
    }

    // A nested it2ssh that dies on the remote host leaves the remote shell's prompt
    // outside the nested conductor's framing; that is reported at depth 1.
    func testNestedUnframedPromptIsReportedAtChildDepth() {
        let parser = makeHookedParser()
        var hook = osc134("%output out1 100 -1 0")
        hook += Array("\u{1b}P2000pnone 555 Ym9vbA== - c3No\n".utf8)
        hook += osc134("%end out1")
        let hookTokens = parse(hook, parser: parser)
        XCTAssertTrue(hookTokens.contains { $0.type == SSH_INIT && $0.sshInfo.valid != 0 && $0.sshInfo.depth == 1 },
                      "\(hookTokens)")

        var prompt = osc134("%output out2 100 -1 0")
        prompt += Array("\u{1b}]133;A\u{07}hostA% ".utf8)
        prompt += osc134("%end out2")
        let prompts = unframedPrompts(parse(prompt, parser: parser))
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.sshInfo.valid, 1)
        XCTAssertEqual(prompts.first?.sshInfo.depth, 1)
    }
}

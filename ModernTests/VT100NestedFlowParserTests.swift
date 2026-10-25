//
//  VT100NestedFlowParserTests.swift
//  iTerm2
//
//  With nested SSH Integration (it2ssh host1, then it2ssh host2 from inside), each framer runs
//  flow control on its own reads. The inner framer's frames travel inside the outer framer's.
//  The parser keeps each controlled inner frame's token, tagged with the inner framer's depth and
//  with the time the outer framer sent the frame that carried its first line: the inner frame's
//  delay over its own hop is that time less the inner framer's send time. The first line, not the
//  last byte, so that the reading holds no time spent transmitting the frame itself; a wait in
//  the outer host's pty delays its first line as much as the rest.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100NestedFlowParserTests: XCTestCase {
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
        // The vector holds a retain on each token; the array holds its own.
        for token in tokens {
            Unmanaged.passUnretained(token).release()
        }
        CVectorDestroy(&vector)
        return tokens
    }

    private let hook: [UInt8] = Array("\u{1b}P2000p0 boolargs -\n".utf8)

    private func makeHookedParser() -> VT100Parser {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        _ = parse(hook, parser: p)
        return p
    }

    private func osc134(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]134;:\(payload)\u{1b}\\".utf8)
    }

    /// A login-shell frame from the framer at `depth`, with flow fields when `sendMs` is given.
    private func frame(_ id: String, depth: Int, sendMs: Int64?, _ body: [UInt8]) -> [UInt8] {
        let flow = sendMs.map { " \($0) 1" } ?? ""
        return osc134("%output \(id) 100 -1 \(depth)\(flow)") + body + osc134("%end \(id)")
    }

    private func frames(_ tokens: [VT100Token]) -> [VT100Token] {
        return tokens.filter { $0.type == SSH_OUTPUT }
    }

    private func depth(_ token: VT100Token) -> Int32 {
        return token.sshInfo.valid != 0 ? token.sshInfo.depth : 0
    }

    private func text(_ tokens: [VT100Token]) -> String {
        return tokens
            .filter { $0.type == VT100_ASCIISTRING || $0.type == VT100_STRING || $0.type == VT100_GANG }
            .map { $0.string ?? $0.stringForAsciiData() }
            .joined()
    }

    // The inner frame is counted at its own depth, with the outer frame's send time, after its
    // contents and before the outer frame, which counts its bytes at depth 0 as before.
    func testAControlledInnerFrameIsKeptWithItsCarriersSendTime() throws {
        let parser = makeHookedParser()
        let inner = hook + frame("in1", depth: 1, sendMs: 5_000, Array("hello".utf8))
        let tokens = parse(frame("out1", depth: 0, sendMs: 9_000, inner), parser: parser)

        let found = frames(tokens)
        XCTAssertEqual(found.count, 2, "\(tokens.map { $0.type })")
        let (innerToken, outerToken) = (found[0], found[1])
        XCTAssertEqual(depth(innerToken), 1)
        XCTAssertTrue(innerToken.sshFlowControlled)
        XCTAssertEqual(innerToken.sshSendMilliseconds, 5_000)
        XCTAssertEqual(innerToken.sshCarrierSendMilliseconds, 9_000)
        XCTAssertEqual(innerToken.savedData, Data("hello".utf8))
        XCTAssertEqual(depth(outerToken), 0)
        XCTAssertEqual(outerToken.sshSendMilliseconds, 9_000)
        XCTAssertEqual(outerToken.sshCarrierSendMilliseconds, 0, "nothing carries the outermost frame")

        let innerIndex = try XCTUnwrap(tokens.firstIndex { $0 === innerToken })
        let textIndex = try XCTUnwrap(tokens.firstIndex {
            $0.type == VT100_ASCIISTRING || $0.type == VT100_STRING || $0.type == VT100_GANG
        })
        XCTAssertLessThan(textIndex, innerIndex, "the inner frame's contents run first")
        XCTAssertEqual(text(tokens), "hello")
    }

    // A framer without flow control on: its frames are unwrapped and dropped, as before.
    func testAnUncontrolledInnerFrameIsNotKept() {
        let parser = makeHookedParser()
        let inner = hook + frame("in1", depth: 1, sendMs: nil, Array("hello".utf8))
        let tokens = parse(frame("out1", depth: 0, sendMs: 9_000, inner), parser: parser)

        XCTAssertEqual(frames(tokens).map { depth($0) }, [0])
        XCTAssertEqual(text(tokens), "hello")
    }

    // An inner frame split across two outer frames takes the send time of the one that carried
    // its first line.
    func testAnInnerFrameSplitAcrossOuterFramesTakesTheFirstCarrier() {
        let parser = makeHookedParser()
        let inner = hook + frame("in1", depth: 1, sendMs: 5_000, Array("hello".utf8))
        let cut = inner.count - 6
        let first = parse(frame("out1", depth: 0, sendMs: 9_000, Array(inner[..<cut])), parser: parser)
        let second = parse(frame("out2", depth: 0, sendMs: 9_040, Array(inner[cut...])), parser: parser)

        XCTAssertEqual(frames(first).map { depth($0) }, [0])
        let innerTokens = frames(second).filter { depth($0) == 1 }
        XCTAssertEqual(innerTokens.count, 1)
        XCTAssertEqual(innerTokens.first?.sshCarrierSendMilliseconds, 9_000)
    }

    // Its first line in the second outer frame, it takes that one's time.
    func testAnInnerFrameBeginningInALaterOuterFrameTakesThatOnesTime() {
        let parser = makeHookedParser()
        let previous = hook + frame("in0", depth: 1, sendMs: 4_000, Array("a".utf8))
        let next = frame("in1", depth: 1, sendMs: 5_000, Array("hello".utf8))
        _ = parse(frame("out1", depth: 0, sendMs: 9_000, previous), parser: parser)
        let tokens = parse(frame("out2", depth: 0, sendMs: 9_040, next), parser: parser)
        XCTAssertEqual(frames(tokens).filter { depth($0) == 1 }.map { $0.sshCarrierSendMilliseconds }, [9_040])
    }

    // A frame cut inside its first line takes the outer frame that completed the line.
    func testAnInnerFrameWhoseFirstLineIsSplitTakesTheFrameThatCompletedIt() {
        let parser = makeHookedParser()
        let inner = hook + frame("in1", depth: 1, sendMs: 5_000, Array("hello".utf8))
        let cut = hook.count + 12
        _ = parse(frame("out1", depth: 0, sendMs: 9_000, Array(inner[..<cut])), parser: parser)
        let tokens = parse(frame("out2", depth: 0, sendMs: 9_040, Array(inner[cut...])), parser: parser)
        XCTAssertEqual(frames(tokens).filter { depth($0) == 1 }.map { $0.sshCarrierSendMilliseconds }, [9_040])
    }

    // Three hops: each frame takes the send time of the frame directly around it, so each hop
    // is measured on its own.
    func testEachDepthTakesTheSendTimeOfTheFrameAroundIt() {
        let parser = makeHookedParser()
        let innermost = hook + frame("in2", depth: 2, sendMs: 1_000, Array("deep".utf8))
        let middle = hook + frame("in1", depth: 1, sendMs: 5_000, innermost)
        let tokens = parse(frame("out1", depth: 0, sendMs: 9_000, middle), parser: parser)

        let found = frames(tokens)
        XCTAssertEqual(found.map { depth($0) }, [2, 1, 0])
        XCTAssertEqual(found.map { $0.sshCarrierSendMilliseconds }, [5_000, 9_000, 0])
        XCTAssertEqual(text(tokens), "deep")
    }

    // An outer framer without flow control says nothing about when it sent: no carrier time.
    func testAnUncontrolledCarrierGivesNoTime() {
        let parser = makeHookedParser()
        let inner = hook + frame("in1", depth: 1, sendMs: 5_000, Array("hello".utf8))
        let tokens = parse(frame("out1", depth: 0, sendMs: nil, inner), parser: parser)

        let innerTokens = frames(tokens).filter { depth($0) == 1 }
        XCTAssertEqual(innerTokens.count, 1)
        XCTAssertEqual(innerTokens.first?.sshCarrierSendMilliseconds, 0)
    }

    // A program on host1 can print a tmux passthrough wrap of a fake framer stream. It stays
    // inert: the hook needs a newline before any frame, and a wrap ends at the first one.
    func testAWrappedFakeFramerStreamInsideAFrameDoesNotCrash() {
        let parser = makeHookedParser()
        let fake = hook + frame("fake", depth: 0, sendMs: nil, Array("spoof".utf8))
        let escaped = fake.flatMap { $0 == 0x1b ? [0x1b, 0x1b] : [$0] }
        let wrap = Array("\u{1b}Ptmux;".utf8) + escaped + Array("\u{1b}\\".utf8)
        let tokens = parse(frame("out1", depth: 0, sendMs: 9_000, wrap), parser: parser)
        XCTAssertEqual(frames(tokens).filter { depth($0) == 0 }.count, 1, "the real frame is intact")
    }

    // it2 data from an inner framer travels in the outer frame too.
    func testInnerIT2DataTakesItsCarriersSendTime() {
        let parser = makeHookedParser()
        let inner = hook + osc134("%it2 conn1 data aGk= 5000 0")
        let tokens = parse(frame("out1", depth: 0, sendMs: 9_000, inner), parser: parser)
        let it2 = tokens.filter { $0.type == SSH_IT2 }
        XCTAssertEqual(it2.count, 1, "\(tokens.map { $0.type })")
        XCTAssertEqual(it2.first.map { depth($0) }, 1)
        XCTAssertEqual(it2.first?.sshCarrierSendMilliseconds, 9_000)
    }

    // Recovering a nested connection hooks a parser at each depth. Only the outermost one's
    // boundary ends recovery: the inner ones numbered theirs from zero too, so theirs matched,
    // and each resynchronized the conductors again, clearing queues and dropping keys typed
    // after the first, Ctrl-C included.
    func testOnlyTheOutermostParserLeavesRecoveryWithABoundary() {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        let inner: NSDictionary = [NSNumber(value: 456): ["inner-login", [:] as NSDictionary]]
        let number = parser.startConductorRecoveryMode(withID: "outer-dcs",
                                                       tree: [NSNumber(value: 123): ["inner-dcs", inner]],
                                                       clientUniqueID: nil)
        let tokens = parse([], parser: parser) +
            // The outer framer's next frame for its login process reaches the inner parser.
            parse(osc134("%output out 123 -1 0") + Array("hello".utf8) + osc134("%end out"), parser: parser)
        let boundaries = tokens.filter { $0.type == SSH_RECOVERY_BOUNDARY }
        XCTAssertEqual(boundaries.count, 1)
        XCTAssertEqual(boundaries.first?.csi.pointee.p.0, Int32(number))
        XCTAssertEqual(boundaries.first?.sshInfo.valid, 0, "the outermost parser's")
    }
}

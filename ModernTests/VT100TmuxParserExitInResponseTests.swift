//
//  VT100TmuxParserExitInResponseTests.swift
//  ModernTests
//
//  A tmux control-mode response is everything between %begin and the matching
//  %end. Only tmux 1.8 ever put a %exit inside such a block (with no closing
//  guard), and the parser works around that by ending tmux mode when it sees
//  one. On any newer server a %exit line inside a block is response data, for
//  example capture-pane output from a pane whose scrollback holds raw
//  control-mode text. Treating it as a real exit unhooked the parser and
//  printed the rest of the protocol stream as plain text.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100TmuxParserExitInResponseTests: XCTestCase {

    private func parse(_ string: String, parser: VT100Parser) -> [VT100Token] {
        let bytes = Array(string.utf8)
        bytes.withUnsafeBufferPointer { buf in
            parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        defer { CVectorDestroy(&vector) }
        _ = parser.addParsedTokens(to: &vector)
        var tokens = [VT100Token]()
        for i in 0..<CVectorCount(&vector) {
            tokens.append(CVectorGetObject(&vector, i) as! VT100Token)
        }
        return tokens
    }

    // Enters tmux control mode the way tmux -CC does.
    private func makeHookedParser() -> VT100Parser {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        let tokens = parse("\u{1b}P1000p", parser: parser)
        XCTAssertEqual(tokens.filter { $0.type == DCS_TMUX_HOOK }.count, 1)
        return parser
    }

    private let response = "%begin 1 1 1\r\nsome text\r\n%exit\r\nmore text\r\n%end 1 1 1\r\n"
    private let trailer = "%output %1 hi\r\n"

    private func tmuxLines(_ tokens: [VT100Token]) -> [String] {
        return tokens.filter { $0.type == TMUX_LINE }.compactMap { $0.string }
    }

    // A server known to be 1.9 or later: the %exit line is data, the block
    // closes at its %end, and the parser stays hooked for what follows.
    func testExitInsideResponseIsDataOnModernServer() {
        let parser = makeHookedParser()
        parser.setTmuxServerMayOmitEndGuardBeforeExit(false)

        let tokens = parse(response + trailer, parser: parser)

        XCTAssertEqual(tokens.filter { $0.type == TMUX_EXIT }.count, 0,
                       "a %exit inside a block must not end tmux mode, got \(tokens.map { $0.type })")
        XCTAssertEqual(tmuxLines(tokens),
                       ["%begin 1 1 1", "some text", "%exit", "more text", "%end 1 1 1", "%output %1 hi"])
        XCTAssertEqual(tokens.filter { $0.type == VT100_ASCIISTRING || $0.type == VT100_STRING }.count, 0,
                       "nothing may leak out as printable text")
    }

    // A real %exit, outside any block, still ends tmux mode on a modern server.
    func testExitOutsideResponseStillExitsOnModernServer() {
        let parser = makeHookedParser()
        parser.setTmuxServerMayOmitEndGuardBeforeExit(false)

        let tokens = parse("%begin 1 1 1\r\nx\r\n%end 1 1 1\r\n%exit\r\n", parser: parser)

        XCTAssertEqual(tokens.filter { $0.type == TMUX_EXIT }.count, 1,
                       "got \(tokens.map { $0.type })")
    }

    // tmux over SSH integration: the outer parser is hooked to the SSH conductor
    // and the tmux stream arrives inside %output frames, re-parsed by a child
    // parser that holds the tmux hook. The flag set on the outer parser has to
    // reach that child.
    func testExitInsideResponseIsDataOnModernServerOverSSH() {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        _ = parse("\u{1b}P2000p0 boolargs -\n", parser: parser)

        func framed(_ inner: String) -> String {
            // identifier pid channel depth, then the remote bytes, then the end frame.
            return "\u{1b}]134;:%output out1 100 -1 0\u{1b}\\" + inner + "\u{1b}]134;:%end out1\u{1b}\\"
        }
        // The remote tmux enters control mode; this creates the child parser and hooks it.
        let hookTokens = parse(framed("\u{1b}P1000p"), parser: parser)
        XCTAssertEqual(hookTokens.filter { $0.type == DCS_TMUX_HOOK }.count, 1,
                       "got \(hookTokens.map { $0.type })")

        // The version becomes known after the hook exists, as in real life.
        parser.setTmuxServerMayOmitEndGuardBeforeExit(false)

        let tokens = parse(framed(response + trailer), parser: parser)

        XCTAssertEqual(tokens.filter { $0.type == TMUX_EXIT }.count, 0,
                       "the child parser must have received the flag, got \(tokens.map { $0.type })")
        XCTAssertEqual(tmuxLines(tokens),
                       ["%begin 1 1 1", "some text", "%exit", "more text", "%end 1 1 1", "%output %1 hi"])
    }

    // Until the version is known the tmux 1.8 workaround stays in force: a %exit
    // inside a block ends tmux mode.
    func testExitInsideResponseExitsWhenVersionUnknown() {
        let parser = makeHookedParser()

        let tokens = parse(response + trailer, parser: parser)

        XCTAssertEqual(tokens.filter { $0.type == TMUX_EXIT }.count, 1,
                       "got \(tokens.map { $0.type })")
        XCTAssertEqual(tmuxLines(tokens), ["%begin 1 1 1", "some text"])
    }
}

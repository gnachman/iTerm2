//
//  VT100DCSParserTests.swift
//  ModernTests
//
//  Ported from the legacy iTerm2XCTests/VT100DCSParserTest.m. Drives
//  VT100DCSParser directly through an iTermParserContext and checks the token
//  type plus the parser's internal state machine (exposed through the Testing
//  category), then covers the tmux and sixel hooks through a full VT100Parser.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100DCSParserTests: XCTestCase {
    private var parser = VT100DCSParser()
    private var savedState = NSMutableDictionary()
    // The context as it was left after the most recent decode. Only datalen and rmlen are
    // meaningful once the input buffer has gone away.
    private var lastContext = iTermParserContext()

    private let esc = "\u{1b}"
    private let st = "\u{1b}\\"

    override func setUp() {
        super.setUp()
        parser = VT100DCSParser()
        savedState = NSMutableDictionary()
    }

    // MARK: - Helpers

    private func decode(_ string: String) -> VT100Token {
        var bytes = Array(string.utf8)
        let token = VT100Token()
        bytes.withUnsafeMutableBufferPointer { buf in
            var context = iTermParserContextMake(buf.baseAddress, Int32(buf.count))
            parser.decode(from: &context,
                          token: token,
                          encoding: String.Encoding.utf8.rawValue,
                          savedState: savedState)
            lastContext = context
        }
        return token
    }

    // Decodes ESC P followed by `body`.
    private func dcs(_ body: String) -> VT100Token {
        return decode(esc + "P" + body)
    }

    private func parameters() -> [String]? {
        return parser.parameters as? [String]
    }

    private func hexEncoded(_ s: String) -> String {
        return s.utf16.map { String(format: "%02x", Int($0)) }.joined()
    }

    // Feeds a byte stream through a full VT100Parser and returns every token it produced.
    private func parse(_ bytes: [UInt8], parser: VT100Parser) -> [VT100Token] {
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

    private func makeFullParser() -> VT100Parser {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        return p
    }

    // MARK: - State machine

    func testDCS() {
        let token = dcs("")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .entry)
    }

    func testDCSControl() {
        let token = dcs("\n")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .entry)
    }

    func testDCSBackspace() {
        let token = dcs("\u{7f}")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .entry)
    }

    func testDCSIntermediate() {
        let token = dcs(" ")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .intermediate)
    }

    func testDCSMultipleIntermediates() {
        let token = dcs(" !")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .intermediate)
    }

    func testDCSIntermediateIgnore() {
        let token = dcs(" 0")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .ignore)
    }

    func testDCSIntermediateIgnoreIgnore() {
        let token = dcs(" 01")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .ignore)
    }

    func testDCSIntermediateIgnoreMany() {
        // LF, EM, FS are all ignored while in the ignore state.
        let token = dcs(" 0\n\u{19}\u{1c}0")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .ignore)
    }

    func testDCSIntermediateIgnoreIgnoreEsc() {
        let token = dcs(" 01" + esc)
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .dcsEscape)
    }

    func testDCSIntermediateIgnoreIgnoreST() {
        let token = dcs(" 01" + st)
        XCTAssertEqual(token.type, VT100_INVALID_SEQUENCE)
        XCTAssertEqual(parser.state, .ground)
    }

    func testDCSIntermediateIgnoreIgnoreEscAsciiST() {
        // Enter ignore, then dcs escape, then passthrough, then ground; should still be invalid.
        let token = dcs(" 01" + esc + "abc" + st)
        XCTAssertEqual(token.type, VT100_INVALID_SEQUENCE)
        XCTAssertEqual(parser.state, .ground)
    }

    func testDCSIntermediatePassthrough() {
        let token = dcs(" x")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .passthrough)
    }

    func testDCSIntermediatePassthroughEsc() {
        let token = dcs(" x" + esc)
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .dcsEscape)
    }

    func testDCSIntermediatePassthroughST() {
        let token = dcs(" x" + st)
        XCTAssertEqual(token.type, VT100_NOTSUPPORT)
        XCTAssertEqual(parser.state, .ground)
    }

    func testDCSIgnore() {
        let token = dcs(":")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .ignore)
    }

    func testDCSParam() {
        let token = dcs("1")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .param)
    }

    func testDCSMultipleParameters() {
        // Control characters (LF, DEL) inside the parameter list are ignored.
        let token = dcs("12\n3;45\u{7f}6;;0")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .param)
        XCTAssertEqual(parameters(), ["123", "456", "", "0"])
    }

    func testDCSParamIgnoreColon() {
        let token = dcs("1:")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .ignore)
    }

    func testDCSParamIgnoreLT() {
        let token = dcs("1<")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .ignore)
    }

    func testDCSPrivate() {
        let token = dcs("<1;2")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .param)
        XCTAssertEqual(parser.privateMarkers, "<")
        XCTAssertEqual(parameters(), ["1", "2"])
    }

    func testDCSParamIntermediate() {
        let token = dcs("1;2 ")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .intermediate)
        XCTAssertEqual(parameters(), ["1", "2"])
        XCTAssertEqual(parser.intermediateString, " ")
    }

    func testDCSParamPassthrough() {
        let token = dcs("1;2Abc~")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .passthrough)
        XCTAssertEqual(parameters(), ["1", "2"])
        XCTAssertEqual(parser.data, "Abc~")
    }

    func testDCSCatchesBinaryGarbage() {
        // LF is allowed in passthrough but EM is not; everything from EM on is garbage.
        let token = dcs("Abc\n\u{19}\u{1c}\u{7f}~")
        XCTAssertEqual(token.type, VT100_BINARY_GARBAGE)
        XCTAssertEqual(parser.state, .passthrough)
        XCTAssertEqual(parameters(), [])
        XCTAssertEqual(parser.data, "Abc\n")
    }

    func testDCSPassthroughEsc() {
        let token = dcs("Abcd" + esc)
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(parser.state, .dcsEscape)
        XCTAssertEqual(parser.data, "Abcd")
    }

    func testDCSPassthroughST() {
        let token = dcs("Abcd" + st)
        XCTAssertEqual(token.type, VT100_NOTSUPPORT)
        XCTAssertEqual(parser.state, .ground)
        XCTAssertEqual(parser.data, "Abcd")
    }

    func testDCSEverything() {
        let token = dcs("<0;1;!\"abc" + st)
        XCTAssertEqual(token.type, VT100_NOTSUPPORT)
        XCTAssertEqual(parser.state, .ground)
        XCTAssertEqual(parser.privateMarkers, "<")
        XCTAssertEqual(parameters(), ["0", "1", ""])
        XCTAssertEqual(parser.intermediateString, "!\"")
        XCTAssertEqual(parser.data, "abc")
    }

    // MARK: - Recognized sequences

    func testDCSRequestTermcapTerminfo() {
        let token = dcs("+q" + hexEncoded("TN") + st)
        XCTAssertEqual(token.type, DCS_REQUEST_TERMCAP_TERMINFO)
    }

    func testDECRQSS() {
        let token = dcs("$q q" + st)
        XCTAssertEqual(token.type, DCS_DECRQSS)
        XCTAssertEqual(token.string, " q")
    }

    // MARK: - tmux hook

    func testDCSEnterTmuxIntegration() {
        XCTAssertFalse(parser.isHooked)
        var token = dcs("1000p" + st)
        XCTAssertEqual(token.type, DCS_TMUX_HOOK)
        XCTAssertTrue(parser.isHooked)
        // The hook consumes through the 'p'; the ST is left for the tmux parser.
        XCTAssertEqual(lastContext.datalen, 2)
        savedState.removeAllObjects()

        token = decode("%exit\n")
        XCTAssertEqual(token.type, TMUX_EXIT)
        XCTAssertFalse(parser.isHooked)
        XCTAssertEqual(lastContext.datalen, 0)
        XCTAssertEqual(parser.state, .ground)
    }

    func testDCSTmuxHookWaitsForFinalByte() {
        XCTAssertFalse(parser.isHooked)
        let token = dcs("1000")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertFalse(parser.isHooked)
        XCTAssertEqual(lastContext.datalen, 6)
    }

    func testDCSTmuxHookAccumulatesLineAcrossReads() {
        var token = dcs("1000p")
        XCTAssertEqual(token.type, DCS_TMUX_HOOK)
        XCTAssertTrue(parser.isHooked)
        XCTAssertEqual(lastContext.datalen, 0)
        savedState.removeAllObjects()

        token = decode("abc")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertTrue(parser.isHooked)
        XCTAssertEqual(lastContext.datalen, 0)

        token = decode("def\r\n")
        XCTAssertEqual(token.type, TMUX_LINE)
        XCTAssertEqual(token.string, "abcdef")
        XCTAssertTrue(parser.isHooked)
        XCTAssertEqual(lastContext.datalen, 0)
    }

    func testDCSTmuxHookPassesSingleEscapeThrough() {
        var token = dcs("1000p")
        XCTAssertEqual(token.type, DCS_TMUX_HOOK)
        savedState.removeAllObjects()

        // Technically DCS should take ESC ESC as input to produce ESC as output, but that's not how
        // tmux works so we have a hack that in tmux mode only a single ESC is treated as an ESC.
        let s = esc + "[1m"
        token = decode(s + "\n")
        XCTAssertEqual(token.type, TMUX_LINE)
        XCTAssertEqual(token.string, s)
    }

    func testDCSTmuxHookEmptyLine() {
        var token = dcs("1000p")
        XCTAssertEqual(token.type, DCS_TMUX_HOOK)
        savedState.removeAllObjects()

        token = decode("\n")
        XCTAssertEqual(token.type, TMUX_LINE)
        XCTAssertEqual(token.string, "")
    }

    func testDCSTmuxHookEmptyLineWithCarriageReturns() {
        var token = dcs("1000p")
        XCTAssertEqual(token.type, DCS_TMUX_HOOK)
        savedState.removeAllObjects()

        token = decode("\r\r\r\n")
        XCTAssertEqual(token.type, TMUX_LINE)
        XCTAssertEqual(token.string, "")
    }

    func testDCSTmuxHookEmptyLineSplitInTwo() {
        var token = dcs("1000p")
        XCTAssertEqual(token.type, DCS_TMUX_HOOK)
        savedState.removeAllObjects()

        token = decode("\r")
        XCTAssertEqual(token.type, VT100_WAIT)
        token = decode("\n")
        XCTAssertEqual(token.type, TMUX_LINE)
        XCTAssertEqual(token.string, "")
    }

    func testDCSTmuxHookExitWithCRLF() {
        var token = dcs("1000p")
        XCTAssertEqual(token.type, DCS_TMUX_HOOK)
        XCTAssertTrue(parser.isHooked)
        savedState.removeAllObjects()

        token = decode("%exit\r\n")
        XCTAssertEqual(token.type, TMUX_EXIT)
        XCTAssertFalse(parser.isHooked)
        XCTAssertEqual(lastContext.datalen, 0)
    }

    func testDCSTmuxWrap() {
        let token = dcs("tmux;" + esc + esc + "[1m" + st)
        XCTAssertEqual(token.type, DCS_TMUX_CODE_WRAP)
        XCTAssertEqual(token.string, esc + "[1m")
    }

    // MARK: - Saved state

    func testDCSSavedState() {
        // Splitting the sequence at every possible point must produce the same parse, with the
        // first part's progress carried over through the saved state dictionary. The bytes of the
        // first part are replaced by dashes on the second call to prove they come from saved state.
        let whole = Array((esc + "P<0;1;!\"abc" + st).utf8)
        for i in 2..<whole.count {
            parser = VT100DCSParser()
            savedState = NSMutableDictionary()

            let head = String(decoding: whole[..<i], as: UTF8.self)
            var token = decode(head)
            XCTAssertEqual(token.type, VT100_WAIT, "split at \(i)")

            let tail = String(decoding: whole[i...], as: UTF8.self)
            token = decode(String(repeating: "-", count: i) + tail)
            XCTAssertEqual(parser.state, .ground, "split at \(i)")
            XCTAssertEqual(parser.privateMarkers, "<", "split at \(i)")
            XCTAssertEqual(parameters(), ["0", "1", ""], "split at \(i)")
            XCTAssertEqual(parser.intermediateString, "!\"", "split at \(i)")
            XCTAssertEqual(parser.data, "abc", "split at \(i)")
        }
    }

    // MARK: - Through the full VT100Parser

    func testParserWithDCSTmuxWrap() {
        let tokens = parse(Array((esc + "Ptmux;" + esc + esc + "[1m" + st).utf8), parser: makeFullParser())
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.type, VT100CSI_SGR)
    }

    func testIssue9070() {
        // A large sixel payload fed in 1024-byte chunks must yield one token that skips the
        // introducer and one DCS_SIXEL token, not a stream of garbage.
        var data: [UInt8] = [0x1b, 0x50, 0x30, 0x3b, 0x30, 0x3b, 0x38, 0x71]
        data += [UInt8](repeating: 0, count: 4453 * 43)
        data += [0x1b, 0x5c]

        let fullParser = makeFullParser()
        var tokens = [VT100Token]()
        var offset = 0
        while offset < data.count {
            let count = min(1024, data.count - offset)
            tokens += parse(Array(data[offset..<(offset + count)]), parser: fullParser)
            offset += count
        }
        XCTAssertEqual(tokens.count, 2, "got \(tokens.map { $0.type })")
        XCTAssertEqual(tokens.first?.type, VT100_SKIP)
        XCTAssertEqual(tokens.last?.type, DCS_SIXEL)
    }
}

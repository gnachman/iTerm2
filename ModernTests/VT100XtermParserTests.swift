//
//  VT100XtermParserTests.swift
//  ModernTests
//
//  Ported from the legacy iTerm2XCTests/VT100XtermParserTest.m. Drives
//  VT100XtermParser (OSC sequences) directly through an iTermParserContext,
//  including the saved-state path used when a sequence arrives in pieces and
//  the multitoken path used by OSC 1337 File= transfers.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100XtermParserTests: XCTestCase {
    private var savedState = NSMutableDictionary()
    private var incidentals = CVector()
    // The context as it was left after the most recent decode. Only datalen and rmlen are
    // meaningful once the input buffer has gone away.
    private var lastContext = iTermParserContext()

    private let esc = "\u{1b}"
    private let bel = "\u{07}"
    private let st = "\u{1b}\\"

    override func setUp() {
        super.setUp()
        savedState = NSMutableDictionary()
        CVectorCreate(&incidentals, 1)
    }

    override func tearDown() {
        CVectorDestroy(&incidentals)
        super.tearDown()
    }

    // MARK: - Helpers

    private func decode(_ string: String) -> VT100Token {
        var bytes = Array(string.utf8)
        let token = VT100Token()
        bytes.withUnsafeMutableBufferPointer { buf in
            var context = iTermParserContextMake(buf.baseAddress, Int32(buf.count))
            VT100XtermParser.decode(from: &context,
                                    incidentals: &incidentals,
                                    token: token,
                                    encoding: String.Encoding.utf8.rawValue,
                                    savedState: savedState)
            lastContext = context
        }
        return token
    }

    // Decodes ESC ] followed by `body`.
    private func osc(_ body: String) -> VT100Token {
        return decode(esc + "]" + body)
    }

    private func incidental(_ index: Int32) -> VT100Token? {
        guard index < CVectorCount(&incidentals) else {
            return nil
        }
        return CVectorGetObject(&incidentals, index) as? VT100Token
    }

    private func assertFileHeader(_ token: VT100Token?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(token?.type, XTERMCC_MULTITOKEN_HEADER_SET_KVP, file: file, line: line)
        XCTAssertEqual(token?.kvpKey, "File", file: file, line: line)
        XCTAssertEqual(token?.kvpValue, "blah;foo=bar", file: file, line: line)
    }

    private func assertBody(_ token: VT100Token?, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(token?.type, XTERMCC_MULTITOKEN_BODY, file: file, line: line)
        XCTAssertEqual(token?.string, expected, file: file, line: line)
    }

    // MARK: - Window title

    func testNoModeYet() {
        var token = osc("")
        XCTAssertEqual(token.type, VT100_WAIT)

        // In case saved state gets used, verify it can continue from there.
        token = osc("0;title" + bel)
        XCTAssertEqual(token.type, XTERMCC_WINICON_TITLE)
        XCTAssertEqual(token.string, "title")
    }

    func testWellFormedSetWindowTitleTerminatedByBell() {
        let token = osc("0;title" + bel)
        XCTAssertEqual(token.type, XTERMCC_WINICON_TITLE)
        XCTAssertEqual(token.string, "title")
    }

    func testWellFormedSetWindowTitleTerminatedByST() {
        let token = osc("0;title" + st)
        XCTAssertEqual(token.type, XTERMCC_WINICON_TITLE)
        XCTAssertEqual(token.string, "title")
    }

    func testIgnoreEmbeddedOSC() {
        let token = osc("0;ti" + esc + "]tle" + bel)
        XCTAssertEqual(token.type, XTERMCC_WINICON_TITLE)
        XCTAssertEqual(token.string, "title")
    }

    func testIgnoreEmbeddedOSCTwoPart_OutOfDataAfterBracket() {
        // Running out of data just after an embedded ESC ] hits a special path.
        var token = osc("0;ti" + esc + "]")
        XCTAssertEqual(token.type, VT100_WAIT)

        token = osc("0;ti" + esc + "]tle" + bel)
        XCTAssertEqual(token.type, XTERMCC_WINICON_TITLE)
        XCTAssertEqual(token.string, "title")
    }

    func testIgnoreEmbeddedOSCTwoPart_OutOfDataAfterEsc() {
        // Running out of data just after an embedded ESC hits a special path.
        var token = osc("0;ti" + esc)
        XCTAssertEqual(token.type, VT100_WAIT)

        token = osc("0;ti" + esc + "]tle" + bel)
        XCTAssertEqual(token.type, XTERMCC_WINICON_TITLE)
        XCTAssertEqual(token.string, "title")
    }

    func testFailOnEmbeddedEscapePlusCharacter() {
        let token = osc("0;ti" + esc + "c")
        XCTAssertEqual(token.type, VT100_NOTSUPPORT)
    }

    func testNonstandardLinuxSetPalette() {
        let token = osc("Pa123456")
        XCTAssertEqual(token.type, XTERMCC_SET_PALETTE)
        XCTAssertEqual(token.string, "a123456")
    }

    func testUnsupportedFirstParameterNoTerminator() {
        XCTAssertEqual(osc("x").type, VT100_WAIT)
    }

    func testUnsupportedFirstParameter() {
        XCTAssertEqual(osc("x" + bel).type, VT100_NOTSUPPORT)
    }

    func testPartialNonstandardLinuxSetPalette() {
        XCTAssertEqual(osc("Pa12345").type, VT100_WAIT)
    }

    func testCancelAbortsOSC() {
        XCTAssertEqual(osc("0\u{18}").type, VT100_NOTSUPPORT)
    }

    func testSubstituteAbortsOSC() {
        XCTAssertEqual(osc("0\u{1a}").type, VT100_NOTSUPPORT)
    }

    // MARK: - Multitoken (OSC 1337 File=)

    func testUnfinishedMultitoken() {
        let token = osc("1337;File=blah;foo=bar:abc")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 2)
        assertFileHeader(incidental(0))
        assertBody(incidental(1), "abc")
    }

    func testCompleteMultitoken() {
        let token = osc("1337;File=blah;foo=bar:abc" + bel)
        XCTAssertEqual(token.type, XTERMCC_MULTITOKEN_END)
        XCTAssertEqual(CVectorCount(&incidentals), 2)
        assertFileHeader(incidental(0))
        assertBody(incidental(1), "abc")
    }

    func testCompleteMultitokenInMultiplePasses() {
        var token = osc("1337;File=blah;")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 0)

        // Give it some more header
        token = osc("1337;File=blah;foo=bar")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 0)

        // Give it the final colon so the header can be parsed
        token = osc("1337;File=blah;foo=bar:")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 1)
        assertFileHeader(incidental(0))

        // Give it some body.
        token = osc("1337;File=blah;foo=bar:a")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 2)
        assertBody(incidental(1), "a")

        // More body
        token = osc("1337;File=blah;foo=bar:abc")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 3)
        assertBody(incidental(2), "bc")

        // Start finishing up
        token = osc("1337;File=blah;foo=bar:abc" + esc)
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 3)

        // And, done.
        token = osc("1337;File=blah;foo=bar:abc" + st)
        XCTAssertEqual(token.type, XTERMCC_MULTITOKEN_END)
        XCTAssertEqual(CVectorCount(&incidentals), 3)
    }

    func testLateFailureMultitokenInMultiplePasses() {
        var token = osc("1337;File=blah;")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 0)

        // Give it some more header
        token = osc("1337;File=blah;foo=bar")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 0)

        // Give it the final colon so the header can be parsed
        token = osc("1337;File=blah;foo=bar:")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 1)
        assertFileHeader(incidental(0))

        // Give it some body.
        token = osc("1337;File=blah;foo=bar:a")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 2)
        assertBody(incidental(1), "a")

        // More body
        token = osc("1337;File=blah;foo=bar:abc")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 3)
        assertBody(incidental(2), "bc")

        // Now a bogus character (SUB).
        token = osc("1337;File=blah;foo=bar:abc\u{1a}")
        XCTAssertEqual(token.type, VT100_NOTSUPPORT)
    }

    func testUnfinishedMultitokenWithDeprecatedMode() {
        let token = osc("50;File=blah;foo=bar:abc")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertEqual(CVectorCount(&incidentals), 2)
        assertFileHeader(incidental(0))
        assertBody(incidental(1), "abc")
    }

    // MARK: - Partial sequences and saved state

    func testUnterminatedOSCWaits() {
        XCTAssertEqual(osc("0;foo").type, VT100_WAIT)
    }

    func testUnterminatedOSCWaits_2() {
        XCTAssertEqual(osc("0").type, VT100_WAIT)
    }

    func testMultiPartOSC() {
        // Pass in a partial escape code. The already-parsed data should be saved in the saved-state
        // dictionary.
        var token = osc("0;foo")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertGreaterThan(savedState.count, 0)

        // Give it a more-formed code. The first three characters have changed. Normally they would be
        // the same, but it's done here to ensure that they are ignored.
        token = osc("0;XXXbar")
        XCTAssertEqual(token.type, VT100_WAIT)
        XCTAssertGreaterThan(savedState.count, 0)

        // Now a fully-formed code. The entire string value must come from saved state.
        token = osc("0;XXXXXX" + bel)
        XCTAssertEqual(token.type, XTERMCC_WINICON_TITLE)
        XCTAssertEqual(token.string, "foobar")
    }

    func testEmbeddedColon() {
        let token = osc("1;foo:bar" + bel)
        XCTAssertEqual(token.type, XTERMCC_ICON_TITLE)
        XCTAssertEqual(token.string, "foo:bar")
    }

    func testUnsupportedMode() {
        XCTAssertEqual(osc("999;foo" + bel).type, VT100_NOTSUPPORT)
    }

    func testBelAfterEmbeddedOSC() {
        let token = osc("1;" + esc + "]" + bel)
        XCTAssertEqual(token.type, XTERMCC_ICON_TITLE)
        XCTAssertEqual(token.string, "")
    }

    func testIgnoreEmbeddedOSCWhenFailing() {
        let token = osc("x" + esc + "]" + bel)
        XCTAssertEqual(token.type, VT100_NOTSUPPORT)
        XCTAssertEqual(iTermParserNumberOfBytesConsumed(&lastContext), 6)
    }

    // MARK: - Regression tests

    // Bug 3371
    func testDefaultModeForDtermCodes() {
        let token = osc(";Foo" + bel)
        XCTAssertEqual(token.type, XTERMCC_WINICON_TITLE)
        XCTAssertEqual(token.string, "Foo")
    }

    func testOverflow() {
        XCTAssertEqual(osc("9999999999;foo" + bel).type, VT100_NOTSUPPORT)
    }
}

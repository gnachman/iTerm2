//
//  VT100SixelParserTests.swift
//  iTerm2
//
//  Regression tests for how the sixel DCS hook handles the String Terminator.
//  A well-formed sixel ends with ST = ESC \. Some tools emit a doubled-up
//  terminator ESC ESC \ (see issue 12259); the hook used to treat the second
//  ESC as a broken sequence and discard the entire image, printing the stray
//  trailing \ to the screen. It now renders the accumulated pixels and lets the
//  unexpected byte(s) reparse as a fresh sequence, matching xterm/real hardware.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100SixelParserTests: XCTestCase {

    // Feed raw bytes to a parser and return all produced tokens.
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

    private func makeParser() -> VT100Parser {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        return p
    }

    // Concatenation of any printable text the tokens would have written to the
    // screen. Used to prove no stray terminator byte leaked out as text.
    private func printableOutput(_ tokens: [VT100Token]) -> String {
        var result = ""
        for token in tokens {
            switch token.type {
            case VT100_STRING:
                result += token.string ?? ""
            case VT100_ASCIISTRING:
                result += token.stringForAsciiData()
            default:
                break
            }
        }
        return result
    }

    private func sixelTokens(_ tokens: [VT100Token]) -> [VT100Token] {
        return tokens.filter { $0.type == DCS_SIXEL }
    }

    // A minimal but valid sixel body: define color register 0, select it, emit a
    // few sixels. The exact pixels are irrelevant to terminator handling; the
    // parser just accumulates bytes until it sees ESC.
    private let body = "#0;2;0;0;0#0~~~$-~~~"

    private func introducer() -> String {
        return "\u{1b}Pq\(body)"
    }

    // A clean ST terminator must still yield exactly one sixel token and print
    // nothing.
    func testCleanTerminator() {
        let stream = Array("\(introducer())\u{1b}\\".utf8)
        let tokens = parse(stream, parser: makeParser())

        XCTAssertEqual(sixelTokens(tokens).count, 1,
                       "one DCS_SIXEL expected, got \(tokens.map { $0.type })")
        XCTAssertEqual(printableOutput(tokens), "",
                       "a clean sixel must not print any stray text")
    }

    // The reported bug: a doubled-up terminator ESC ESC \. Must render the image
    // (not discard it) and must not print the trailing backslash. The rendered
    // data must be byte-for-byte identical to the clean-terminator case.
    func testDoubledEscTerminatorRendersAndPrintsNothing() {
        let clean = parse(Array("\(introducer())\u{1b}\\".utf8), parser: makeParser())
        let doubled = parse(Array("\(introducer())\u{1b}\u{1b}\\".utf8), parser: makeParser())

        let doubledSixels = sixelTokens(doubled)
        XCTAssertEqual(doubledSixels.count, 1,
                       "ESC ESC \\ must still produce one DCS_SIXEL, got \(doubled.map { $0.type })")
        XCTAssertEqual(printableOutput(doubled), "",
                       "the doubled terminator must not leak a stray backslash to the screen")
        XCTAssertEqual(doubledSixels.first?.savedData,
                       sixelTokens(clean).first?.savedData,
                       "the rendered image data must match the clean-terminator case")
    }

    // A real aborting escape sequence (no ST) must render the accumulated image
    // AND still execute: the whole ESC [ 2 J is put back and reparsed, so the
    // clear-display runs and nothing prints as literal text.
    func testAbortingEscapeSequenceRendersSixelAndExecutes() {
        let stream = Array("\(introducer())\u{1b}[2J".utf8)
        let tokens = parse(stream, parser: makeParser())

        XCTAssertEqual(sixelTokens(tokens).count, 1,
                       "the image must render even with an aborting terminator")
        XCTAssertEqual(printableOutput(tokens), "",
                       "the aborting escape must reparse and execute, not print as text")
        XCTAssertTrue(tokens.contains { $0.type == VT100CSI_ED },
                      "the ESC [ 2 J must reparse into an erase-display token: \(tokens.map { $0.type })")
    }

    // A fresh DCS immediately following (no ST) must also survive: two sixels in a
    // row where the first is terminated by the second's introducer.
    func testAbortingDCSRendersBothImages() {
        let stream = Array("\u{1b}Pq\(body)\u{1b}\u{1b}Pq\(body)\u{1b}\\".utf8)
        let tokens = parse(stream, parser: makeParser())
        XCTAssertEqual(sixelTokens(tokens).count, 2,
                       "an aborting fresh DCS must not swallow the first image: \(tokens.map { $0.type })")
        XCTAssertEqual(printableOutput(tokens), "")
    }

    // Binary output that merely contains ESC P ... q with no sixel body and a
    // malformed terminator must emit nothing: no broken-image glyph, no decode.
    func testEmptyBodyWithMalformedTerminatorEmitsNothing() {
        // ESC P q  ESC A  -- introducer with no body, aborted by an escape.
        let tokens = parse(Array("\u{1b}Pq\u{1b}A".utf8), parser: makeParser())
        XCTAssertTrue(sixelTokens(tokens).isEmpty,
                      "an empty-body sixel must not produce a DCS_SIXEL: \(tokens.map { $0.type })")
    }

    // The doubled terminator split across two reads exercises the code path where
    // the first ESC was consumed in a prior putStreamData call and the hook
    // re-enters in its post-ESC state. The backtrack must still be in-bounds.
    func testDoubledEscTerminatorSplitAcrossReads() {
        let parser = makeParser()
        // First read ends immediately after the first ESC of the terminator.
        let first = parse(Array("\(introducer())\u{1b}".utf8), parser: parser)
        XCTAssertTrue(sixelTokens(first).isEmpty,
                      "no sixel token should be emitted before the terminator completes")
        // Second read supplies the doubled ESC and the backslash.
        let second = parse(Array("\u{1b}\\".utf8), parser: parser)
        XCTAssertEqual(sixelTokens(second).count, 1,
                       "the sixel must render once the split terminator arrives")
        XCTAssertEqual(printableOutput(second), "",
                       "the split doubled terminator must not print a stray backslash")
    }

    // Under OSC 1337 CopyToClipboard capture, the parser normally overwrites every
    // token's savedData with the raw stream slice. A DCS_SIXEL whose data the hook
    // already assembled (and which, in the split doubled-terminator case, consumed
    // zero bytes in its final read) must not be clobbered with an empty/partial
    // slice. See issue 12259 follow-up.
    func testSavedDataSurvivesCopyToClipboardCapture() {
        // Reference image from a clean terminator, no capture active.
        let clean = sixelTokens(parse(Array("\(introducer())\u{1b}\\".utf8),
                                       parser: makeParser())).first?.savedData
        XCTAssertNotNil(clean)

        let parser = makeParser()
        // Begin clipboard capture, which turns on savedData recording.
        _ = parse(Array("\u{1b}]1337;CopyToClipboard=name\u{07}".utf8), parser: parser)
        // Split doubled terminator so the final read consumes zero bytes.
        _ = parse(Array("\(introducer())\u{1b}".utf8), parser: parser)
        let tokens = parse(Array("\u{1b}\\".utf8), parser: parser)

        let sixel = sixelTokens(tokens).first
        XCTAssertNotNil(sixel, "the image must render even during clipboard capture")
        XCTAssertEqual(sixel?.savedData, clean,
                       "clipboard capture must not clobber the hook-assembled sixel data")
    }
}

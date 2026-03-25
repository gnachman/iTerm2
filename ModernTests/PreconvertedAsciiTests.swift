//
//  PreconvertedAsciiTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/24/26.
//

import XCTest
@testable import iTerm2SharedARC

final class PreconvertedAsciiTests: XCTestCase {

    // MARK: - Helpers

    /// Feed raw bytes to a parser and return all produced tokens.
    private func parse(_ bytes: [UInt8], parser: VT100Parser? = nil) -> [VT100Token] {
        let p = parser ?? makeParser()
        bytes.withUnsafeBufferPointer { buf in
            p.putStreamData(buf.baseAddress, length: Int32(buf.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        _ = p.addParsedTokens(to: &vector)
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

    private func defaultConfig() -> VT100StringConversionConfig {
        return VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(false),
            normalization: .none,
            unicodeVersion: 9,
            softAlternateScreenMode: ObjCBool(false)
        )
    }

    /// Extract VT100_ASCIISTRING tokens from a token array.
    private func asciiTokens(_ tokens: [VT100Token]) -> [VT100Token] {
        return tokens.filter { $0.type == VT100_ASCIISTRING }
    }

    /// Extract VT100_MIXED_ASCII_CR_LF tokens from a token array.
    private func mixedAsciiTokens(_ tokens: [VT100Token]) -> [VT100Token] {
        return tokens.filter { $0.type == VT100_MIXED_ASCII_CR_LF }
    }

    /// Compute fg screen_char_t from a rendition, matching VT100Terminal.foregroundColorCode.
    private func fgFromRendition(_ rendition: VT100GraphicRendition,
                                 protectedMode: Bool = false) -> screen_char_t {
        var c = screen_char_t()
        var r = rendition
        VT100GraphicRenditionUpdateForeground(&r, true, protectedMode, &c)
        return c
    }

    /// Compute bg screen_char_t from a rendition.
    private func bgFromRendition(_ rendition: VT100GraphicRendition) -> screen_char_t {
        var c = screen_char_t()
        var r = rendition
        VT100GraphicRenditionUpdateBackground(&r, true, &c)
        return c
    }

    /// Compare foreground color fields of two screen_char_t values.
    private func assertForegroundEqual(
        _ a: screen_char_t, _ b: screen_char_t,
        file: StaticString = #file, line: UInt = #line
    ) {
        XCTAssertEqual(a.foregroundColor, b.foregroundColor, "foregroundColor", file: file, line: line)
        XCTAssertEqual(a.fgGreen, b.fgGreen, "fgGreen", file: file, line: line)
        XCTAssertEqual(a.fgBlue, b.fgBlue, "fgBlue", file: file, line: line)
        XCTAssertEqual(a.foregroundColorMode, b.foregroundColorMode, "foregroundColorMode", file: file, line: line)
        XCTAssertEqual(a.bold, b.bold, "bold", file: file, line: line)
        XCTAssertEqual(a.italic, b.italic, "italic", file: file, line: line)
        XCTAssertEqual(a.underline, b.underline, "underline", file: file, line: line)
    }

    /// Compare background color fields of two screen_char_t values.
    private func assertBackgroundEqual(
        _ a: screen_char_t, _ b: screen_char_t,
        file: StaticString = #file, line: UInt = #line
    ) {
        XCTAssertEqual(a.backgroundColor, b.backgroundColor, "backgroundColor", file: file, line: line)
        XCTAssertEqual(a.bgGreen, b.bgGreen, "bgGreen", file: file, line: line)
        XCTAssertEqual(a.bgBlue, b.bgBlue, "bgBlue", file: file, line: line)
        XCTAssertEqual(a.backgroundColorMode, b.backgroundColorMode, "backgroundColorMode", file: file, line: line)
    }

    // MARK: - Test 1: Default rendition produces zeroed fg/bg

    func testDefaultRenditionASCII() {
        // Plain ASCII with no prior SGR should have the default (zero) rendition
        // baked into the screen_char_t buffer.
        let bytes: [UInt8] = Array("Hello, world!".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let data = ascii[0].asciiData
        let sc = data.pointee.screenChars!
        XCTAssertEqual(Int(sc.pointee.length), 13)

        // With default rendition, fg/bg fields should match VT100GraphicRenditionInitialize output.
        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)
        let expectedBg = bgFromRendition(defaultRendition)

        for i in 0..<Int(sc.pointee.length) {
            let ch = sc.pointee.buffer![i]
            // Code should be the ASCII byte.
            XCTAssertEqual(ch.code, UInt16(bytes[i]), "code mismatch at index \(i)")
            assertForegroundEqual(ch, expectedFg)
            assertBackgroundEqual(ch, expectedBg)
        }
    }

    // MARK: - Test 2: SGR bold+red then ASCII

    func testSGRBoldRedThenASCII() {
        // ESC[1;31m sets bold + red foreground, then ASCII text.
        let bytes: [UInt8] = Array("\u{1b}[1;31mHello".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.bold, 1, "should be bold")
        XCTAssertEqual(Int(ch.foregroundColor), Int(COLORCODE_RED.rawValue))
        XCTAssertEqual(Int(ch.foregroundColorMode), Int(ColorModeNormal.rawValue))
    }

    // MARK: - Test 3: SGR reset before ASCII

    func testSGRResetBeforeASCII() {
        // Set bold+red, then reset, then ASCII. The ASCII should have default rendition.
        let bytes: [UInt8] = Array("\u{1b}[1;31m\u{1b}[0mHello".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.bold, 0)
        XCTAssertEqual(ch.italic, 0)

        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    // MARK: - Test 4: 256-color SGR

    func testSGR256ColorASCII() {
        // ESC[38;5;196m sets 256-color foreground to index 196.
        let bytes: [UInt8] = Array("\u{1b}[38;5;196mABC".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.foregroundColor, 196)
    }

    // MARK: - Test 5: 24-bit color SGR

    func testSGR24BitColorASCII() {
        // ESC[38;2;255;128;0m sets 24-bit foreground.
        let bytes: [UInt8] = Array("\u{1b}[38;2;255;128;0mXYZ".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.foregroundColor, 255)
        XCTAssertEqual(ch.fgGreen, 128)
        XCTAssertEqual(ch.fgBlue, 0)
        XCTAssertEqual(Int(ch.foregroundColorMode), Int(ColorMode24bit.rawValue))
    }

    // MARK: - Test 6: Background color

    func testSGRBackgroundColorASCII() {
        // ESC[44m sets blue background.
        let bytes: [UInt8] = Array("\u{1b}[44mABC".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(Int(ch.backgroundColor), Int(COLORCODE_BLUE.rawValue))
        XCTAssertEqual(Int(ch.backgroundColorMode), Int(ColorModeNormal.rawValue))
    }

    // MARK: - Test 7: Reverse video

    func testReverseVideoASCII() {
        // ESC[31;7m sets red fg + reverse.
        let bytes: [UInt8] = Array("\u{1b}[31;7mABC".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        var rendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&rendition)
        rendition.fgColorCode = Int32(COLORCODE_RED.rawValue)
        rendition.fgColorMode = ColorModeNormal
        rendition.reversed = ObjCBool(true)
        let expectedFg = fgFromRendition(rendition)
        let expectedBg = bgFromRendition(rendition)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        assertForegroundEqual(ch, expectedFg)
        assertBackgroundEqual(ch, expectedBg)
    }

    // MARK: - Test 8: Multiple SGR tokens between ASCII strings

    func testMultipleSGRBetweenASCIIStrings() {
        // Bold then "Hello", italic then "World"
        let bytes: [UInt8] = Array("\u{1b}[1mHello\u{1b}[3mWorld".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 2)

        let sc1 = ascii[0].asciiData.pointee.screenChars!
        let ch1 = sc1.pointee.buffer![0]
        XCTAssertEqual(ch1.bold, 1)
        XCTAssertEqual(ch1.italic, 0)

        let sc2 = ascii[1].asciiData.pointee.screenChars!
        let ch2 = sc2.pointee.buffer![0]
        XCTAssertEqual(ch2.bold, 1)
        XCTAssertEqual(ch2.italic, 1)
    }

    // MARK: - Test 9: All characters in buffer get the same fg/bg

    func testAllCharsGetSameFGBG() {
        let bytes: [UInt8] = Array("\u{1b}[32mabcdefghij".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let first = sc.pointee.buffer![0]
        for i in 1..<Int(sc.pointee.length) {
            let ch = sc.pointee.buffer![i]
            assertForegroundEqual(ch, first)
            assertBackgroundEqual(ch, first)
        }
    }

    // MARK: - Test 10: Character codes are preserved after adding fg/bg

    func testCharacterCodesPreserved() {
        let text = "Hello, world! 0123456789"
        let bytes: [UInt8] = Array(("\u{1b}[1;34m" + text).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let data = ascii[0].asciiData
        let sc = data.pointee.screenChars!
        XCTAssertEqual(Int(sc.pointee.length), text.count)
        let textBytes = Array(text.utf8)
        for i in 0..<Int(sc.pointee.length) {
            XCTAssertEqual(sc.pointee.buffer![i].code, UInt16(textBytes[i]),
                           "code mismatch at index \(i)")
        }
    }

    // MARK: - Test 11: Rendition stamp is stored on ScreenChars

    func testRenditionStampStored() {
        // After SGR bold+red, the rendition stamp on ScreenChars should reflect that.
        let bytes: [UInt8] = Array("\u{1b}[1;31mABC".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        XCTAssertTrue(sc.pointee.rendition.bold.boolValue, "rendition should be bold")
        XCTAssertEqual(sc.pointee.rendition.fgColorCode, Int32(COLORCODE_RED.rawValue))
        XCTAssertEqual(sc.pointee.rendition.fgColorMode, ColorModeNormal)
    }

    // MARK: - Test 12: Default rendition stamp

    func testDefaultRenditionStamp() {
        // ASCII with no prior SGR should still have a stamp with default rendition.
        let bytes: [UInt8] = Array("Hello".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!

        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
    }

    // MARK: - Test 13: Push/pop SGR with ASCII

    func testPushPopSGRASCII() {
        // XTPUSHSGR, set red, XTPOPSGR, then ASCII. Should have default rendition.
        let bytes: [UInt8] = Array("\u{1b}[#{\u{1b}[31m\u{1b}[#}Hello".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)

        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    // MARK: - Test 14: Large ASCII string (dynamic allocation)

    func testLargeASCIIString() {
        // A string longer than kStaticScreenCharsCount (16) to exercise the dynamic allocation path.
        let text = String(repeating: "X", count: 200)
        let bytes: [UInt8] = Array(("\u{1b}[33m" + text).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        XCTAssertEqual(Int(sc.pointee.length), 200)

        for i in 0..<200 {
            let ch = sc.pointee.buffer![i]
            XCTAssertEqual(ch.code, UInt16(0x58), "code at \(i)")
            XCTAssertEqual(Int(ch.foregroundColor), Int(COLORCODE_YELLOW.rawValue), "fg at \(i)")
        }
    }

    // MARK: - Test 15: Mixed ASCII CR/LF token gets colors

    func testMixedASCIICRLFTokenGetsColors() {
        // "abc\r\ndef" produces a VT100_MIXED_ASCII_CR_LF token.
        // The screen_char_t buffer should have fg/bg baked in.
        let bytes: [UInt8] = Array("\u{1b}[35mabc\r\ndef".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let mixed = mixedAsciiTokens(tokens)
        XCTAssertEqual(mixed.count, 1)

        let sc = mixed[0].asciiData.pointee.screenChars!
        // "abc\r\ndef" = 8 chars in the buffer
        XCTAssertEqual(Int(sc.pointee.length), 8)

        // All should have magenta foreground
        for i in 0..<Int(sc.pointee.length) {
            let ch = sc.pointee.buffer![i]
            XCTAssertEqual(Int(ch.foregroundColor), Int(COLORCODE_MAGENTA.rawValue),
                           "fg at \(i)")
        }
    }

    // MARK: - Test 16: Color desync detection

    func testColorDesyncDetection() {
        // Parse ASCII with default rendition. Then simulate the mutation
        // thread having a different rendition (bold+red). The rendition
        // stamp should NOT match, signaling desync.
        let bytes: [UInt8] = Array("Hello".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!

        // Build what the mutation thread would compute.
        var mutationRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&mutationRendition)
        mutationRendition.bold = ObjCBool(true)
        mutationRendition.fgColorCode = Int32(COLORCODE_RED.rawValue)
        mutationRendition.fgColorMode = ColorModeNormal

        let mutFg = fgFromRendition(mutationRendition)
        let stampFg = fgFromRendition(sc.pointee.rendition,
                                      protectedMode: sc.pointee.protectedMode.boolValue)

        // The stamp fg should differ from the mutation side fg.
        XCTAssertNotEqual(stampFg.bold, mutFg.bold)
        XCTAssertNotEqual(stampFg.foregroundColor, mutFg.foregroundColor)
    }

    // MARK: - Test 17: Italic + underline attributes

    func testItalicUnderlineASCII() {
        // ESC[3;4m sets italic + underline.
        let bytes: [UInt8] = Array("\u{1b}[3;4mABC".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.italic, 1)
        XCTAssertEqual(ch.underline, 1)
    }

    // MARK: - Test 18: DECSC/DECRC shadow state with ASCII

    func testDECSCDECRCWithASCII() {
        // Save cursor (which also saves SGR), set red, restore cursor, then ASCII.
        // ESC 7 = DECSC, ESC 8 = DECRC
        let bytes: [UInt8] = Array("\u{1b}7\u{1b}[31m\u{1b}8Hello".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)

        let ch = sc.pointee.buffer![0]
        // After restore, should be back to default.
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    // MARK: - Test 19: Faint attribute

    func testFaintASCII() {
        // ESC[2m sets faint.
        let bytes: [UInt8] = Array("\u{1b}[2mABC".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.faint, 1)
    }

    // MARK: - Test 20: Invisible attribute

    func testInvisibleASCII() {
        // ESC[8m sets invisible.
        let bytes: [UInt8] = Array("\u{1b}[8mABC".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let ascii = asciiTokens(tokens)
        XCTAssertEqual(ascii.count, 1)

        let sc = ascii[0].asciiData.pointee.screenChars!
        let ch = sc.pointee.buffer![0]
        XCTAssertEqual(ch.invisible, 1)
    }
}

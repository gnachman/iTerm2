//
//  PreconvertedStringTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/22/26.
//

import XCTest
@testable import iTerm2SharedARC

final class PreconvertedStringTests: XCTestCase {

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

    /// Convenience: run StringToScreenChars on a space-prefixed string as a reference.
    private func referenceConvert(
        _ string: String,
        fg: screen_char_t = screen_char_t(),
        bg: screen_char_t = screen_char_t(),
        ambiguousIsDoubleWidth: Bool = false,
        normalization: iTermUnicodeNormalization = .none,
        unicodeVersion: Int = 9,
        softAlternateScreenMode: Bool = false
    ) -> (buffer: [screen_char_t], foundDwc: Bool, rtlFound: Bool) {
        let normalized = (string as NSString).normalized(normalization) as String
        let augmented = " " + normalized
        var len = Int32(augmented.count * 3)
        var buffer = [screen_char_t](repeating: screen_char_t(), count: Int(len))
        var dwc: ObjCBool = false
        var rtl: ObjCBool = false

        buffer.withUnsafeMutableBufferPointer { bufPtr in
            StringToScreenChars(
                augmented,
                bufPtr.baseAddress,
                fg,
                bg,
                &len,
                ambiguousIsDoubleWidth,
                nil,
                &dwc,
                normalization,
                unicodeVersion,
                softAlternateScreenMode,
                &rtl
            )
        }
        return (Array(buffer[0..<Int(len)]), dwc.boolValue, rtl.boolValue)
    }

    /// Compute fg screen_char_t from a rendition, matching VT100Terminal.foregroundColorCode
    private func fgFromRendition(_ rendition: VT100GraphicRendition, protectedMode: Bool = false) -> screen_char_t {
        var c = screen_char_t()
        var r = rendition
        VT100GraphicRenditionUpdateForeground(&r, true, protectedMode, &c)
        return c
    }

    /// Compute bg screen_char_t from a rendition
    private func bgFromRendition(_ rendition: VT100GraphicRendition) -> screen_char_t {
        var c = screen_char_t()
        var r = rendition
        VT100GraphicRenditionUpdateBackground(&r, true, &c)
        return c
    }

    /// Extract VT100_STRING tokens from a token array.
    private func stringTokens(_ tokens: [VT100Token]) -> [VT100Token] {
        return tokens.filter { $0.type == VT100_STRING }
    }

    /// Compare two screen_char_t values for equality in code and complexChar fields.
    private func assertScreenCharCodeEqual(
        _ a: screen_char_t, _ b: screen_char_t,
        file: StaticString = #file, line: UInt = #line
    ) {
        XCTAssertEqual(a.code, b.code, "code mismatch", file: file, line: line)
        XCTAssertEqual(a.complexChar, b.complexChar, "complexChar mismatch", file: file, line: line)
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

    // MARK: - Test 1: Basic non-ASCII conversion

    func testBasicNonASCII() {
        let bytes: [UInt8] = Array("你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertGreaterThan(pre.pointee.length, 0)

        let ref = referenceConvert("你好世界")
        XCTAssertEqual(Int(pre.pointee.length), ref.buffer.count)
        for i in 0..<Int(pre.pointee.length) {
            assertScreenCharCodeEqual(pre.pointee.buffer![i], ref.buffer[i])
        }
        XCTAssertEqual(pre.pointee.foundDwc.boolValue, ref.foundDwc)
        XCTAssertEqual(pre.pointee.rtlFound.boolValue, ref.rtlFound)
    }

    // MARK: - Test 2: SGR then string

    func testSGRThenString() {
        let bytes: [UInt8] = Array("\u{1b}[1;31m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertGreaterThan(pre.pointee.length, 1)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 1)
        XCTAssertEqual(Int(ch.foregroundColor), Int(COLORCODE_RED.rawValue))
        XCTAssertEqual(Int(ch.foregroundColorMode), Int(ColorModeNormal.rawValue))
    }

    // MARK: - Test 3: SGR reset

    func testSGRReset() {
        let bytes: [UInt8] = Array("\u{1b}[1;31m\u{1b}[0m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertGreaterThan(pre.pointee.length, 1)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 0)
        XCTAssertEqual(ch.italic, 0)

        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    // MARK: - Test 4: 256-color SGR

    func testSGR256Color() {
        let bytes: [UInt8] = Array("\u{1b}[38;5;196m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertGreaterThan(pre.pointee.length, 1)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.foregroundColor, 196)
    }

    // MARK: - Test 5: 24-bit color SGR

    func testSGR24BitColor() {
        let bytes: [UInt8] = Array("\u{1b}[38;2;255;128;0m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertGreaterThan(pre.pointee.length, 1)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.foregroundColor, 255)
        XCTAssertEqual(ch.fgGreen, 128)
        XCTAssertEqual(ch.fgBlue, 0)
        XCTAssertEqual(Int(ch.foregroundColorMode), Int(ColorMode24bit.rawValue))
    }

    // MARK: - Test 6: Reverse video

    func testReverseVideo() {
        let bytes: [UInt8] = Array("\u{1b}[31;7m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        var rendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&rendition)
        rendition.fgColorCode = Int32(COLORCODE_RED.rawValue)
        rendition.fgColorMode = ColorModeNormal
        rendition.reversed = ObjCBool(true)
        let expectedFg = fgFromRendition(rendition)
        let expectedBg = bgFromRendition(rendition)

        let ch = pre.pointee.buffer![1]
        assertForegroundEqual(ch, expectedFg)
        assertBackgroundEqual(ch, expectedBg)
    }

    // MARK: - Test 7: Multiple SGR tokens between strings

    func testMultipleSGRBetweenStrings() {
        let bytes: [UInt8] = Array("\u{1b}[1m你好世界\u{1b}[3m漢字漢字".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 2)

        let pre1 = strings[0].preconvertedStringData
        XCTAssertTrue(pre1.pointee.valid.boolValue)
        let ch1 = pre1.pointee.buffer![1]
        XCTAssertEqual(ch1.bold, 1)
        XCTAssertEqual(ch1.italic, 0)

        let pre2 = strings[1].preconvertedStringData
        XCTAssertTrue(pre2.pointee.valid.boolValue)
        let ch2 = pre2.pointee.buffer![1]
        XCTAssertEqual(ch2.bold, 1)
        XCTAssertEqual(ch2.italic, 1)
    }

    // MARK: - Test 8: Color desync detection (medium path)

    func testColorDesyncDetection() {
        let bytes: [UInt8] = Array("你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        var actualRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&actualRendition)
        actualRendition.bold = ObjCBool(true)
        actualRendition.fgColorCode = Int32(COLORCODE_RED.rawValue)
        actualRendition.fgColorMode = ColorModeNormal

        let actualFg = fgFromRendition(actualRendition)
        let actualBg = bgFromRendition(actualRendition)

        let stampFg = fgFromRendition(pre.pointee.rendition, protectedMode: pre.pointee.protectedMode.boolValue)

        // Confirm desync
        XCTAssertNotEqual(stampFg.bold, actualFg.bold)

        // Simulate medium path: apply color fixup
        for i in 0..<Int(pre.pointee.length) {
            CopyForegroundColor(&pre.pointee.buffer![i], actualFg)
            CopyBackgroundColor(&pre.pointee.buffer![i], actualBg)
        }

        let ch = pre.pointee.buffer![1]
        assertForegroundEqual(ch, actualFg)
        assertBackgroundEqual(ch, actualBg)
    }

    // MARK: - Test 9: Config mismatch detection (slow path)

    func testConfigMismatchDetection() {
        let bytes: [UInt8] = Array("你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertEqual(Int(pre.pointee.config.unicodeVersion), 9)

        // Mutation side has unicodeVersion=16 → config mismatch → should use slow path
        let configMatch = (pre.pointee.config.ambiguousIsDoubleWidth.boolValue == false &&
                          pre.pointee.config.normalization == .none &&
                          pre.pointee.config.unicodeVersion == 16 &&
                          pre.pointee.config.softAlternateScreenMode.boolValue == false)
        XCTAssertFalse(configMatch, "Config should not match when unicode version differs")
    }

    // MARK: - Test 10: Combining mark at start of string

    func testCombiningMarkAtStart() {
        let bytes: [UInt8] = Array("\u{0301}你好世".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ref = referenceConvert("\u{0301}你好世")
        XCTAssertEqual(Int(pre.pointee.length), ref.buffer.count)
        XCTAssertNotEqual(ref.buffer[0].complexChar, 0, "First char should be complex (space + combining mark)")
        assertScreenCharCodeEqual(pre.pointee.buffer![0], ref.buffer[0])
    }

    // MARK: - Test 11: Combining mark with no predecessor (column 0)

    func testCombiningMarkNoPredecessor() {
        let bytes: [UInt8] = Array("你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        let pre = strings[0].preconvertedStringData

        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertEqual(pre.pointee.buffer![0].complexChar, 0,
                       "Non-combining first char: space should remain separate (not complex)")
    }

    // MARK: - Test 12: Double-width characters

    func testDoubleWidthCharacters() {
        let bytes: [UInt8] = Array("漢字漢字".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertTrue(pre.pointee.foundDwc.boolValue)

        // Buffer: [space] [漢][DWC_RIGHT] [字][DWC_RIGHT] [漢][DWC_RIGHT] [字][DWC_RIGHT] = 9
        XCTAssertEqual(Int(pre.pointee.length), 9)
        XCTAssertEqual(pre.pointee.buffer![2].code, UInt16(DWC_RIGHT))
    }

    // MARK: - Test 13: Mixed single and double width

    func testMixedSingleDoubleWidth() {
        let bytes: [UInt8] = Array("α漢β你".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ref = referenceConvert("α漢β你")
        XCTAssertEqual(Int(pre.pointee.length), ref.buffer.count)
    }

    // MARK: - Test 14: RTL detection

    func testRTLDetection() {
        let bytes: [UInt8] = Array("مرحبا".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ref = referenceConvert("مرحبا")
        XCTAssertEqual(pre.pointee.rtlFound.boolValue, ref.rtlFound)
    }

    // MARK: - Test 15: Empty string

    func testEmptyString() {
        let bytes: [UInt8] = Array("\u{1b}[1m".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 0)
    }

    // MARK: - Test 16: Push/pop SGR

    func testPushPopSGR() {
        // XTPUSHSGR = ESC[#{, XTPOPSGR = ESC[#}
        let bytes: [UInt8] = Array("\u{1b}[#{".utf8) +
                              Array("\u{1b}[31m".utf8) +
                              Array("\u{1b}[#}".utf8) +
                              Array("你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    // MARK: - Test 17: softAlternateScreenMode

    func testSoftAlternateScreenMode() {
        let bytes: [UInt8] = Array("你好世界".utf8)
        let parser = makeParser()
        parser.update(VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(false),
            normalization: .none,
            unicodeVersion: 9,
            softAlternateScreenMode: ObjCBool(true)
        ))
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertTrue(pre.pointee.config.softAlternateScreenMode.boolValue)
    }

    // MARK: - Test 18: Large string (dynamic allocation)

    func testLargeString() {
        let cjk = String(repeating: "你", count: 40)
        let bytes: [UInt8] = Array(cjk.utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        // 1 (space) + 40 * 2 (char + DWC_RIGHT) = 81, which exceeds
        // kStaticPreconvertedScreenCharsCount (64), so a dynamic buffer must have been used.
        XCTAssertEqual(Int(pre.pointee.length), 81)

        // Verify the content is correct by spot-checking the last character
        XCTAssertEqual(pre.pointee.buffer![80].code, UInt16(DWC_RIGHT))
    }

    // MARK: - Test: Rendition stamp is stored correctly

    func testRenditionStampStored() {
        let bytes: [UInt8] = Array("\u{1b}[1;3;31m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        XCTAssertTrue(pre.pointee.rendition.bold.boolValue)
        XCTAssertTrue(pre.pointee.rendition.italic.boolValue)
        XCTAssertEqual(pre.pointee.rendition.fgColorCode, Int32(COLORCODE_RED.rawValue))
        XCTAssertEqual(pre.pointee.rendition.fgColorMode, ColorModeNormal)
    }

    // MARK: - Test: Config stamp is stored correctly

    func testConfigStampStored() {
        let bytes: [UInt8] = Array("你好世界".utf8)
        let parser = makeParser()
        parser.update(VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(true),
            normalization: .NFC,
            unicodeVersion: 16,
            softAlternateScreenMode: ObjCBool(true)
        ))
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertTrue(pre.pointee.config.ambiguousIsDoubleWidth.boolValue)
        XCTAssertEqual(pre.pointee.config.normalization, .NFC)
        XCTAssertEqual(Int(pre.pointee.config.unicodeVersion), 16)
        XCTAssertTrue(pre.pointee.config.softAlternateScreenMode.boolValue)
    }

    // MARK: - Test: RIS resets shadow rendition

    func testRISResetsRendition() {
        // Set bold+red, then RIS (ESC c), then non-ASCII
        let bytes: [UInt8] = Array("\u{1b}[1;31m\u{1b}c你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        // Rendition stamp should be reset to defaults
        XCTAssertFalse(pre.pointee.rendition.bold.boolValue)

        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 0)
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    // MARK: - Test: DECSTR resets shadow rendition

    func testDECSTRResetsRendition() {
        // Set bold+red, then DECSTR (ESC[!p), then non-ASCII
        let bytes: [UInt8] = Array("\u{1b}[1;31m\u{1b}[!p你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        XCTAssertFalse(pre.pointee.rendition.bold.boolValue)

        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 0)
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    // MARK: - Test: DECSCA protected mode enabled

    func testDECSCAProtectedModeEnabled() {
        // DECSCA enable: ESC[1"q
        let bytes: [UInt8] = Array("\u{1b}[1\"q你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertTrue(pre.pointee.protectedMode.boolValue)
        XCTAssertEqual(pre.pointee.buffer![1].guarded, 1)
    }

    // MARK: - Test: DECSCA protected mode disabled

    func testDECSCAProtectedModeDisabled() {
        // Enable then disable: ESC[1"q ESC[0"q
        let bytes: [UInt8] = Array("\u{1b}[1\"q\u{1b}[0\"q你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertFalse(pre.pointee.protectedMode.boolValue)
        XCTAssertEqual(pre.pointee.buffer![1].guarded, 0)
    }

    // MARK: - Test: SGR stack overflow (push beyond 10)

    func testSGRStackOverflow() {
        // Push 10 times with bold, then push 11th (should be dropped), set italic, pop once.
        // After pop, should get back to the 10th push (bold, no italic).
        var seq = ""
        // Start with bold
        seq += "\u{1b}[1m"
        // Push 10 times
        for _ in 0..<10 {
            seq += "\u{1b}[#{"
        }
        // 11th push (should be silently dropped)
        seq += "\u{1b}[#{"
        // Set italic (this modifies current rendition but won't be saved since push was dropped)
        seq += "\u{1b}[3m"
        // Pop once — should restore to state at 10th push (bold, no italic)
        seq += "\u{1b}[#}"
        seq += "你好世界"

        let bytes: [UInt8] = Array(seq.utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 1, "Should have bold from the state at 10th push")
        XCTAssertEqual(ch.italic, 0, "Italic should not be present after pop")
    }

    // MARK: - Test: SGR pop on empty stack

    func testSGRPopOnEmptyStack() {
        // Pop without any push, then send non-ASCII
        let bytes: [UInt8] = Array("\u{1b}[#}你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        // Should still have default rendition (no crash, no corruption)
        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 0)
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
    }

    // MARK: - Test: Nested push/pop SGR

    func testNestedPushPopSGR() {
        // Push, set bold, push, set italic, pop → bold only, send string A
        // Pop → default, send string B
        let combined =
            "\u{1b}[#{" +      // push (save default)
            "\u{1b}[1m" +      // set bold
            "\u{1b}[#{" +      // push (save bold)
            "\u{1b}[3m" +      // set italic
            "\u{1b}[#}" +      // pop → restore bold (no italic)
            "你好世界" +
            "\u{1b}[#}" +      // pop → restore default
            "漢字漢字"
        let bytes: [UInt8] = Array(combined.utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 2)

        // First string: bold=1, italic=0
        let pre1 = strings[0].preconvertedStringData
        XCTAssertTrue(pre1.pointee.valid.boolValue)
        let ch1 = pre1.pointee.buffer![1]
        XCTAssertEqual(ch1.bold, 1)
        XCTAssertEqual(ch1.italic, 0)

        // Second string: bold=0, italic=0 (default)
        let pre2 = strings[1].preconvertedStringData
        XCTAssertTrue(pre2.pointee.valid.boolValue)
        let ch2 = pre2.pointee.buffer![1]
        XCTAssertEqual(ch2.bold, 0)
        XCTAssertEqual(ch2.italic, 0)
    }

    // MARK: - Test: Background color SGR

    func testSGRBackgroundColor() {
        // 24-bit background: ESC[48;2;10;20;30m
        let bytes: [UInt8] = Array("\u{1b}[48;2;10;20;30m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.backgroundColor, 10)
        XCTAssertEqual(ch.bgGreen, 20)
        XCTAssertEqual(ch.bgBlue, 30)
        XCTAssertEqual(Int(ch.backgroundColorMode), Int(ColorMode24bit.rawValue))
    }

    // MARK: - Test: Ambiguous width character with ambiguousIsDoubleWidth

    func testAmbiguousWidthDoubleWidth() {
        // U+2190 LEFT ARROW is East Asian ambiguous width
        let arrow = "\u{2190}\u{2191}\u{2192}\u{2193}"

        // With ambiguousIsDoubleWidth=true → should be double width
        let parser1 = makeParser()
        parser1.update(VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(true),
            normalization: .none,
            unicodeVersion: 9,
            softAlternateScreenMode: ObjCBool(false)
        ))
        let tokens1 = parse(Array(arrow.utf8), parser: parser1)
        let strings1 = stringTokens(tokens1)
        XCTAssertEqual(strings1.count, 1)

        let pre1 = strings1[0].preconvertedStringData
        XCTAssertTrue(pre1.pointee.valid.boolValue)
        XCTAssertTrue(pre1.pointee.foundDwc.boolValue, "Ambiguous char should be DWC when ambiguousIsDoubleWidth=true")
        // Buffer should contain DWC_RIGHT
        let hasDwcRight1 = (0..<Int(pre1.pointee.length)).contains { pre1.pointee.buffer![$0].code == UInt16(DWC_RIGHT) }
        XCTAssertTrue(hasDwcRight1)

        // With ambiguousIsDoubleWidth=false → should be single width
        let parser2 = makeParser()
        parser2.update(VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(false),
            normalization: .none,
            unicodeVersion: 9,
            softAlternateScreenMode: ObjCBool(false)
        ))
        let tokens2 = parse(Array(arrow.utf8), parser: parser2)
        let strings2 = stringTokens(tokens2)
        XCTAssertEqual(strings2.count, 1)

        let pre2 = strings2[0].preconvertedStringData
        XCTAssertTrue(pre2.pointee.valid.boolValue)
        XCTAssertFalse(pre2.pointee.foundDwc.boolValue, "Ambiguous char should not be DWC when ambiguousIsDoubleWidth=false")
    }

    // MARK: - Test: Normalization NFC affects output

    func testNormalizationNFCAffectsOutput() {
        // Use a fully non-ASCII NFD string: ü decomposed as U+00FC → U+0075 is ASCII,
        // so instead use a non-ASCII base: か (U+304B) + combining dakuten (U+3099) → が in NFC
        let nfdString = "\u{304B}\u{3099}\u{304B}\u{3099}"  // か + combining dakuten × 2

        // With NFC normalization: should compose to が
        let parser1 = makeParser()
        parser1.update(VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(false),
            normalization: .NFC,
            unicodeVersion: 9,
            softAlternateScreenMode: ObjCBool(false)
        ))
        let tokens1 = parse(Array(nfdString.utf8), parser: parser1)
        let strings1 = stringTokens(tokens1)
        XCTAssertEqual(strings1.count, 1)
        let pre1 = strings1[0].preconvertedStringData
        XCTAssertTrue(pre1.pointee.valid.boolValue)

        let ref1 = referenceConvert(nfdString, normalization: .NFC)
        XCTAssertEqual(Int(pre1.pointee.length), ref1.buffer.count)
        for i in 0..<Int(pre1.pointee.length) {
            assertScreenCharCodeEqual(pre1.pointee.buffer![i], ref1.buffer[i])
        }

        // With no normalization: combining mark merges with prepended space → different result
        let parser2 = makeParser()
        parser2.update(VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(false),
            normalization: .none,
            unicodeVersion: 9,
            softAlternateScreenMode: ObjCBool(false)
        ))
        let tokens2 = parse(Array(nfdString.utf8), parser: parser2)
        let strings2 = stringTokens(tokens2)
        XCTAssertEqual(strings2.count, 1)
        let pre2 = strings2[0].preconvertedStringData
        XCTAssertTrue(pre2.pointee.valid.boolValue)

        let ref2 = referenceConvert(nfdString, normalization: .none)
        XCTAssertEqual(Int(pre2.pointee.length), ref2.buffer.count)
        for i in 0..<Int(pre2.pointee.length) {
            assertScreenCharCodeEqual(pre2.pointee.buffer![i], ref2.buffer[i])
        }
    }

    // MARK: - Test: ASCII string is not preconverted

    func testASCIIStringNotPreconverted() {
        let bytes: [UInt8] = Array("hello".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)

        // Pure ASCII should produce VT100_ASCIISTRING, not VT100_STRING
        let asciiTokens = tokens.filter { $0.type == VT100_ASCIISTRING }
        XCTAssertGreaterThan(asciiTokens.count, 0, "ASCII input should produce VT100_ASCIISTRING tokens")

        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 0, "ASCII input should not produce VT100_STRING tokens")

        // The preconvertedStringData on the ascii token should not be valid
        for token in asciiTokens {
            XCTAssertFalse(token.preconvertedStringData.pointee.valid.boolValue,
                          "ASCII tokens should not have valid preconverted data")
        }
    }

    // MARK: - Test: Emoji preconversion

    func testEmojiPreconversion() {
        // U+1F600 GRINNING FACE (outside BMP, requires surrogate pairs in UTF-16)
        let bytes: [UInt8] = Array("😀你好世".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ref = referenceConvert("😀你好世")
        XCTAssertEqual(Int(pre.pointee.length), ref.buffer.count)
        for i in 0..<Int(pre.pointee.length) {
            assertScreenCharCodeEqual(pre.pointee.buffer![i], ref.buffer[i])
        }
    }

    // MARK: - Test: Multiple combining marks

    func testMultipleCombiningMarks() {
        // Use a fully non-ASCII base char so the parser doesn't split at ASCII boundary.
        // か (U+304B) + combining dakuten (U+3099) + combining handakuten (U+309A)
        let str = "\u{304B}\u{3099}\u{309A}\u{304B}\u{3099}\u{309A}"
        let bytes: [UInt8] = Array(str.utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ref = referenceConvert(str)
        XCTAssertEqual(Int(pre.pointee.length), ref.buffer.count)
        for i in 0..<Int(pre.pointee.length) {
            assertScreenCharCodeEqual(pre.pointee.buffer![i], ref.buffer[i])
        }
    }

    // MARK: - Test: SGR underline

    func testSGRUnderline() {
        let bytes: [UInt8] = Array("\u{1b}[4m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.underline, 1)
    }

    // MARK: - Test: SGR strikethrough

    func testSGRStrikethrough() {
        let bytes: [UInt8] = Array("\u{1b}[9m你好世界".utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.strikethrough, 1)
    }

    // MARK: - Test: DECSC/DECRC saves and restores shadow rendition

    func testDECSCDECRCBasic() {
        // Set bold, DECSC (save), set italic, DECRC (restore), then non-ASCII.
        // After restore, should have bold but NOT italic.
        let bytes: [UInt8] = Array((
            "\u{1b}[1m" +    // bold
            "\u{1b}7" +      // DECSC (save)
            "\u{1b}[3m" +    // italic
            "\u{1b}8" +      // DECRC (restore)
            "你好世界"
        ).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        // Shadow should have restored to bold-only (no italic)
        XCTAssertTrue(pre.pointee.rendition.bold.boolValue)
        XCTAssertFalse(pre.pointee.rendition.italic.boolValue)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 1)
        XCTAssertEqual(ch.italic, 0)
    }

    func testDECSCDECRCWithColor() {
        // Set red, DECSC, set blue, DECRC → should be red
        let bytes: [UInt8] = Array((
            "\u{1b}[31m" +   // red fg
            "\u{1b}7" +      // DECSC
            "\u{1b}[34m" +   // blue fg
            "\u{1b}8" +      // DECRC
            "你好世界"
        ).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(Int(ch.foregroundColor), Int(COLORCODE_RED.rawValue))
        XCTAssertEqual(Int(ch.foregroundColorMode), Int(ColorModeNormal.rawValue))
    }

    func testDECSCDECRCProtectedMode() {
        // Enable protected mode, DECSC, disable protected mode, DECRC → should be protected
        let bytes: [UInt8] = Array((
            "\u{1b}[1\"q" +  // DECSCA enable
            "\u{1b}7" +      // DECSC
            "\u{1b}[0\"q" +  // DECSCA disable
            "\u{1b}8" +      // DECRC
            "你好世界"
        ).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)
        XCTAssertTrue(pre.pointee.protectedMode.boolValue)
        XCTAssertEqual(pre.pointee.buffer![1].guarded, 1)
    }

    func testDECRCWithoutDECSCUsesDefaults() {
        // DECRC without prior DECSC restores to initial (default) state
        let bytes: [UInt8] = Array((
            "\u{1b}[1;31m" + // bold + red
            "\u{1b}8" +      // DECRC (no prior save)
            "你好世界"
        ).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        // Saved rendition was initialized to defaults, so restore goes to defaults
        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 0)
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    func testANSIRCPRestoresShadow() {
        // ANSI RCP (CSI u) should also restore the shadow
        let bytes: [UInt8] = Array((
            "\u{1b}[1m" +    // bold
            "\u{1b}7" +      // DECSC (save)
            "\u{1b}[3m" +    // italic
            "\u{1b}[u" +     // ANSICSI_RCP (restore)
            "你好世界"
        ).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 1)
        XCTAssertEqual(ch.italic, 0)
    }

    // MARK: - Test: DECSC/DECRC desync detection

    func testDECSCDesyncDetectedByRenditionMismatch() {
        // Simulate the case where the shadow's single-slot save/restore diverges
        // from reality (e.g., alt-screen switch between save and restore).
        // The desync detection should catch this via the rendition stamp.
        //
        // Sequence: DECSC (saves default), set bold+red, output string.
        // At this point the shadow has bold+red but the saved slot has defaults.
        // If we then DECRC, the shadow restores to defaults. The preconverted
        // buffer will use default colors. If the real terminal had a different
        // saved rendition (e.g., from an alt-screen save), the mutation thread
        // would detect the mismatch via canUsePreconvertedData: and fall back.
        //
        // We verify that the stamp reflects the shadow's state so that any
        // real-terminal divergence is detectable.

        // First: set bold+red, then DECSC, then output
        let bytes1: [UInt8] = Array((
            "\u{1b}[1;31m" + // bold + red
            "\u{1b}7" +      // DECSC (saves bold+red in shadow)
            "你好世界"
        ).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens1 = parse(bytes1, parser: parser)
        let strings1 = stringTokens(tokens1)
        XCTAssertEqual(strings1.count, 1)

        let pre1 = strings1[0].preconvertedStringData
        XCTAssertTrue(pre1.pointee.valid.boolValue)

        // The stamp should reflect bold+red (the current rendition at preconvert time)
        XCTAssertTrue(pre1.pointee.rendition.bold.boolValue)
        XCTAssertEqual(pre1.pointee.rendition.fgColorCode, Int32(COLORCODE_RED.rawValue))

        // Now: change to green, then DECRC (restores bold+red from shadow slot), output
        let bytes2: [UInt8] = Array((
            "\u{1b}[32m" +   // green fg
            "\u{1b}8" +      // DECRC (restores bold+red)
            "好世界你"
        ).utf8)
        let tokens2 = parse(bytes2, parser: parser)
        let strings2 = stringTokens(tokens2)
        XCTAssertEqual(strings2.count, 1)

        let pre2 = strings2[0].preconvertedStringData
        XCTAssertTrue(pre2.pointee.valid.boolValue)

        // The stamp should reflect the RESTORED rendition (bold+red), not green
        XCTAssertTrue(pre2.pointee.rendition.bold.boolValue)
        XCTAssertEqual(pre2.pointee.rendition.fgColorCode, Int32(COLORCODE_RED.rawValue))

        // The buffer colors should also be bold+red
        let ch = pre2.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 1)
        XCTAssertEqual(Int(ch.foregroundColor), Int(COLORCODE_RED.rawValue))

        // Now verify desync detection: compute fg/bg from the stamp's rendition
        // and from a hypothetical "real" rendition that differs (e.g., green).
        // They should NOT be equal, proving the desync would be detected.
        let stampFg = fgFromRendition(pre2.pointee.rendition,
                                       protectedMode: pre2.pointee.protectedMode.boolValue)
        var differentRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&differentRendition)
        differentRendition.fgColorCode = Int32(COLORCODE_GREEN.rawValue)
        differentRendition.fgColorMode = ColorModeNormal
        let differentFg = fgFromRendition(differentRendition)

        // The stamp's fg should differ from the hypothetical "real" fg
        XCTAssertNotEqual(stampFg.foregroundColor, differentFg.foregroundColor,
                         "Desync between shadow and real rendition must be detectable")
    }

    func testRISResetsSavedShadow() {
        // DECSC, then RIS — the saved shadow should be reset too.
        // Subsequent DECRC should restore to defaults, not the pre-RIS state.
        let bytes: [UInt8] = Array((
            "\u{1b}[1;31m" + // bold + red
            "\u{1b}7" +      // DECSC (saves bold+red)
            "\u{1b}c" +      // RIS (resets everything)
            "\u{1b}8" +      // DECRC (should restore to defaults, not bold+red)
            "你好世界"
        ).utf8)
        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(bytes, parser: parser)
        let strings = stringTokens(tokens)
        XCTAssertEqual(strings.count, 1)

        let pre = strings[0].preconvertedStringData
        XCTAssertTrue(pre.pointee.valid.boolValue)

        // After RIS + DECRC, should be at defaults
        var defaultRendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&defaultRendition)
        let expectedFg = fgFromRendition(defaultRendition)

        let ch = pre.pointee.buffer![1]
        XCTAssertEqual(ch.bold, 0)
        XCTAssertEqual(ch.foregroundColor, expectedFg.foregroundColor)
        XCTAssertEqual(ch.foregroundColorMode, expectedFg.foregroundColorMode)
    }

    // MARK: - Test: Config update takes effect midstream

    func testConfigUpdateMidstream() {
        let parser = makeParser()
        parser.update(defaultConfig())

        // First parse: unicodeVersion=9
        let bytes1: [UInt8] = Array("你好世界".utf8)
        let tokens1 = parse(bytes1, parser: parser)
        let strings1 = stringTokens(tokens1)
        XCTAssertEqual(strings1.count, 1)
        let pre1 = strings1[0].preconvertedStringData
        XCTAssertTrue(pre1.pointee.valid.boolValue)
        XCTAssertEqual(Int(pre1.pointee.config.unicodeVersion), 9)

        // Update config to unicodeVersion=16
        parser.update(VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(false),
            normalization: .none,
            unicodeVersion: 16,
            softAlternateScreenMode: ObjCBool(false)
        ))

        // Second parse: should use unicodeVersion=16
        let bytes2: [UInt8] = Array("好世界你".utf8)
        let tokens2 = parse(bytes2, parser: parser)
        let strings2 = stringTokens(tokens2)
        XCTAssertEqual(strings2.count, 1)
        let pre2 = strings2[0].preconvertedStringData
        XCTAssertTrue(pre2.pointee.valid.boolValue)
        XCTAssertEqual(Int(pre2.pointee.config.unicodeVersion), 16)
    }

    // MARK: - Async Preconversion Tests

    func testAsyncPreconversionProducesValidData() {
        // Create an async conversion directly and resolve it.
        var rendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&rendition)
        rendition.bold = true
        let config = defaultConfig()

        let string: NSString = "你好世界你好世界"  // 8 chars, meets threshold
        let conv = iTermAsyncStringConversion(string: string,
                                               stringLength: string.length,
                                               rendition: rendition,
                                               protectedMode: false,
                                               config: config)
        let result = conv.resolve()
        XCTAssertTrue(result.pointee.valid.boolValue)
        XCTAssertGreaterThan(result.pointee.length, 0)

        // Verify content matches reference conversion.
        let ref = referenceConvert(string as String)
        // Async result includes leading space: space + string characters.
        // referenceConvert also includes leading space.
        XCTAssertEqual(Int(result.pointee.length), ref.buffer.count)

        // Verify rendition stamp.
        XCTAssertTrue(result.pointee.rendition.bold.boolValue)
    }

    func testAsyncResolveWhenAlreadyComplete() {
        // Dispatch, wait a bit for background queue, then resolve.
        var rendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&rendition)
        let config = defaultConfig()

        let asyncString1: NSString = "你好世界你好世界"
        let conv = iTermAsyncStringConversion(string: asyncString1,
                                               stringLength: asyncString1.length,
                                               rendition: rendition,
                                               protectedMode: false,
                                               config: config)
        // Give the serial queue time to complete.
        Thread.sleep(forTimeInterval: 0.1)

        let result = conv.resolve()
        XCTAssertTrue(result.pointee.valid.boolValue)
    }

    func testAsyncResolveCalledTwice() {
        // Calling resolve twice should return the same result.
        var rendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&rendition)
        let config = defaultConfig()

        let asyncString2: NSString = "你好世界你好世界"
        let conv = iTermAsyncStringConversion(string: asyncString2,
                                               stringLength: asyncString2.length,
                                               rendition: rendition,
                                               protectedMode: false,
                                               config: config)
        let result1 = conv.resolve()
        let result2 = conv.resolve()
        XCTAssertEqual(result1, result2)
        XCTAssertTrue(result1.pointee.valid.boolValue)
    }

    func testAsyncCompletionHandlerCalled() {
        var rendition = VT100GraphicRendition()
        VT100GraphicRenditionInitialize(&rendition)
        let config = defaultConfig()

        let expectation = XCTestExpectation(description: "completion handler called")
        let asyncString3: NSString = "你好世界你好世界"
        let conv = iTermAsyncStringConversion(string: asyncString3,
                                               stringLength: asyncString3.length,
                                               rendition: rendition,
                                               protectedMode: false,
                                               config: config)
        conv.completionHandler = {
            expectation.fulfill()
        }
        // Resolve to unblock if needed.
        _ = conv.resolve()
        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Test: Space augmentation vs predecessor augmentation for all combining marks

    /// Exhaustively tests that space-augmented StringToScreenChars output (used by
    /// preconversion) matches predecessor-augmented output for every non-base character
    /// in Unicode's BMP. For each non-base character C, we compare:
    ///   StringToScreenChars(" C你好") — as preconversion does (space augmentation)
    ///   StringToScreenChars("eC你好") — as the original algorithm does (real predecessor)
    /// The characters after the augmented prefix (i.e., 你好) must produce identical
    /// screen_char_t output. If they ever differ, the preconversion predecessor fixup
    /// cannot compensate, and a bug exists.
    func testSpaceVsPredecessorAugmentationForAllCombiningMarks() {
        let tail = "你好"  // Suffix to verify the rest of the buffer matches
        var failures: [(UInt32, String)] = []

        // Collect all non-base code points: BMP via CharacterSet, supplementary via scalar property.
        var nonBaseCodePoints: [UInt32] = []

        // BMP non-base characters
        let nonBase = CharacterSet.nonBaseCharacters as NSCharacterSet
        for cp: UInt32 in 0x0300..<0xFFFF {
            if nonBase.characterIsMember(unichar(cp)) {
                nonBaseCodePoints.append(cp)
            }
        }
        // Supplementary plane combining marks (Unicode General_Category Mn, Mc, Me)
        // Check all allocated supplementary ranges for combining properties.
        let supplementaryRanges: [(UInt32, UInt32)] = [
            (0x10000, 0x1005D),    // Linear B, Cypriot
            (0x10A00, 0x10A3F),    // Kharoshthi
            (0x11000, 0x1107F),    // Brahmi
            (0x11080, 0x110CF),    // Kaithi
            (0x11100, 0x1114F),    // Chakma
            (0x11180, 0x111DF),    // Sharada
            (0x11300, 0x1137F),    // Grantha
            (0x11480, 0x114DF),    // Tirhuta
            (0x11580, 0x115FF),    // Siddham
            (0x11600, 0x1165F),    // Modi
            (0x11700, 0x1174F),    // Ahom
            (0x11A00, 0x11A4F),    // Zanabazar Square
            (0x11C00, 0x11C6F),    // Bhaiksuki
            (0x11D00, 0x11D5F),    // Masaram Gondi
            (0x16B00, 0x16B8F),    // Pahawh Hmong
            (0x16F00, 0x16F9F),    // Miao
            (0x1BC00, 0x1BC9F),    // Duployan
            (0x1D165, 0x1D1AD),    // Musical symbols combining marks
            (0x1DA00, 0x1DA8B),    // Signwriting
            (0x1E000, 0x1E02A),    // Glagolitic supplement
            (0x1E900, 0x1E95F),    // Adlam
            (0xE0100, 0xE01EF),    // Variation selectors supplement
        ]
        for (start, end) in supplementaryRanges {
            for cp in start...end {
                guard let scalar = Unicode.Scalar(cp) else { continue }
                // Check if it's a combining character (Mn, Mc, Me)
                if scalar.properties.generalCategory == .nonspacingMark ||
                   scalar.properties.generalCategory == .spacingMark ||
                   scalar.properties.generalCategory == .enclosingMark {
                    nonBaseCodePoints.append(cp)
                }
            }
        }

        for codePoint in nonBaseCodePoints {
            guard let scalar = Unicode.Scalar(codePoint) else { continue }
            let mark = String(scalar)

            let spaceAugmented = " " + mark + tail
            let predAugmented = "e" + mark + tail

            // Convert both
            var spaceLen = Int32(spaceAugmented.count * 3)
            var spaceBuf = [screen_char_t](repeating: screen_char_t(), count: Int(spaceLen))
            var spaceDwc: ObjCBool = false

            spaceBuf.withUnsafeMutableBufferPointer { bufPtr in
                StringToScreenChars(spaceAugmented, bufPtr.baseAddress, screen_char_t(), screen_char_t(),
                                    &spaceLen, false, nil, &spaceDwc, .none, 9, false, nil)
            }

            var predLen = Int32(predAugmented.count * 3)
            var predBuf = [screen_char_t](repeating: screen_char_t(), count: Int(predLen))
            var predDwc: ObjCBool = false

            predBuf.withUnsafeMutableBufferPointer { bufPtr in
                StringToScreenChars(predAugmented, bufPtr.baseAddress, screen_char_t(), screen_char_t(),
                                    &predLen, false, nil, &predDwc, .none, 9, false, nil)
            }

            // Find where the tail (你好) starts in each buffer by skipping the augmented prefix.
            // The prefix is 1 composed character (space/e + mark), possibly followed by DWC_RIGHT.
            // We compare from the first 你 character onward.
            let spaceTail = Array(spaceBuf[0..<Int(spaceLen)])
            let predTail = Array(predBuf[0..<Int(predLen)])

            // Find the index of the first 你 in each buffer.
            let niCode = ("你" as NSString).character(at: 0)
            guard let spaceNiIdx = spaceTail.firstIndex(where: { $0.code == niCode }),
                  let predNiIdx = predTail.firstIndex(where: { $0.code == niCode }) else {
                failures.append((codePoint,
                    String(format: "U+%04X: couldn't find tail character 你", codePoint)))
                continue
            }

            let spaceRest = Array(spaceTail[spaceNiIdx...])
            let predRest = Array(predTail[predNiIdx...])

            if spaceRest.count != predRest.count {
                failures.append((codePoint,
                    String(format: "U+%04X: tail length differs: space=%d pred=%d",
                           codePoint, spaceRest.count, predRest.count)))
                continue
            }

            for i in 0..<spaceRest.count {
                if spaceRest[i].code != predRest[i].code ||
                   spaceRest[i].complexChar != predRest[i].complexChar {
                    failures.append((codePoint,
                        String(format: "U+%04X: tail[%d] differs: space=(code=%d,complex=%d) pred=(code=%d,complex=%d)",
                               codePoint, i,
                               spaceRest[i].code, spaceRest[i].complexChar,
                               predRest[i].code, predRest[i].complexChar)))
                    break
                }
            }
        }

        XCTAssertEqual(failures.count, 0,
                       "Found \(failures.count) of \(nonBaseCodePoints.count) non-base characters " +
                       "(BMP + supplementary) where space vs predecessor augmentation " +
                       "produces different tail output:\n" +
                       failures.prefix(20).map(\.1).joined(separator: "\n"))
    }

    // MARK: - Test: Combining mark in separate token combines with predecessor

    /// Verifies the core correctness property: when "e" is written to the screen and then
    /// a combining mark arrives in a separate token with preconverted data (space-augmented),
    /// the predecessor fixup correctly combines the mark with "e" on the grid.
    func testCombiningMarkInSeparateTokenCombinesWithPredecessor() {
        let part2 = "\u{0301}你好世界"  // combining acute + CJK

        // --- Screen A: original algorithm (no preconversion) ---
        var dumpA: String?
        let sessionA = FakeSession()
        let screenA = VT100Screen()
        sessionA.screen = screenA
        screenA.delegate = sessionA
        screenA.performBlock(joinedThreads: { _, mutableState, _ in
            guard let ms = mutableState else { return }
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screenA.destructivelySetScreenWidth(20, height: 5, mutableState: ms)
            ms.appendString(atCursor: "e")
            ms.appendString(atCursor: part2)
            dumpA = ms.currentGrid.compactLineDump()
        })

        // --- Screen B: preconversion path ---
        var dumpB: String?
        let sessionB = FakeSession()
        let screenB = VT100Screen()
        sessionB.screen = screenB
        screenB.delegate = sessionB

        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(Array(part2.utf8), parser: parser)
        let strTokens = stringTokens(tokens)
        XCTAssertEqual(strTokens.count, 1)
        let tokenPre = strTokens[0].preconvertedStringData
        XCTAssertTrue(tokenPre.pointee.valid.boolValue)

        let prePtr = UnsafeMutablePointer<PreconvertedStringData>.allocate(capacity: 1)
        prePtr.initialize(to: tokenPre.pointee)
        let tokenStaticBuf = UnsafeMutablePointer<screen_char_t>(
            OpaquePointer(UnsafeMutableRawPointer(tokenPre).advanced(
                by: MemoryLayout<PreconvertedStringData>.offset(of: \PreconvertedStringData.staticBuffer)!)))
        if tokenPre.pointee.buffer == tokenStaticBuf {
            let preStaticBuf = UnsafeMutablePointer<screen_char_t>(
                OpaquePointer(UnsafeMutableRawPointer(prePtr).advanced(
                    by: MemoryLayout<PreconvertedStringData>.offset(of: \PreconvertedStringData.staticBuffer)!)))
            prePtr.pointee.buffer = preStaticBuf
        }
        tokenPre.pointee.valid = ObjCBool(false)
        tokenPre.pointee.buffer = nil

        screenB.performBlock(joinedThreads: { _, mutableState, _ in
            guard let ms = mutableState else { return }
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screenB.destructivelySetScreenWidth(20, height: 5, mutableState: ms)
            ms.appendString(atCursor: "e")
            ms.appendString(atCursor: part2, preconvertedData: prePtr)
            dumpB = ms.currentGrid.compactLineDump()
        })
        iTermPreconvertedStringDataFree(prePtr)
        prePtr.deinitialize(count: 1)
        prePtr.deallocate()

        // Both should show U (complex char = e + accent) at position 0, then CJK.
        // 'U' in compactLineDump means complexChar=YES — the combining mark merged with "e".
        XCTAssertNotNil(dumpA)
        XCTAssertNotNil(dumpB)
        XCTAssertTrue(dumpA!.hasPrefix("U"), "Original: predecessor should be complex (e + accent)")
        XCTAssertTrue(dumpB!.hasPrefix("U"), "Preconverted: predecessor should be complex (e + accent)")
        XCTAssertEqual(dumpA, dumpB, "Preconversion should match original algorithm")
    }

    // MARK: - Test: Multiple combining marks in separate token combine with predecessor

    /// Verifies that when "e" is on the screen and a second token arrives starting with
    /// multiple combining marks (acute + cedilla), all marks merge with the predecessor.
    func testMultipleCombiningMarksInSeparateTokenCombineWithPredecessor() {
        let part2 = "\u{0301}\u{0327}你好世界"  // combining acute + combining cedilla + CJK

        // --- Screen A: original algorithm (no preconversion) ---
        var dumpA: String?
        let sessionA = FakeSession()
        let screenA = VT100Screen()
        sessionA.screen = screenA
        screenA.delegate = sessionA
        screenA.performBlock(joinedThreads: { _, mutableState, _ in
            guard let ms = mutableState else { return }
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screenA.destructivelySetScreenWidth(20, height: 5, mutableState: ms)
            ms.appendString(atCursor: "e")
            ms.appendString(atCursor: part2)
            dumpA = ms.currentGrid.compactLineDump()
        })

        // --- Screen B: preconversion path ---
        var dumpB: String?
        let sessionB = FakeSession()
        let screenB = VT100Screen()
        sessionB.screen = screenB
        screenB.delegate = sessionB

        let parser = makeParser()
        parser.update(defaultConfig())
        let tokens = parse(Array(part2.utf8), parser: parser)
        let strTokens = stringTokens(tokens)
        XCTAssertEqual(strTokens.count, 1)
        let tokenPre = strTokens[0].preconvertedStringData
        XCTAssertTrue(tokenPre.pointee.valid.boolValue)

        let prePtr = UnsafeMutablePointer<PreconvertedStringData>.allocate(capacity: 1)
        prePtr.initialize(to: tokenPre.pointee)
        let tokenStaticBuf = UnsafeMutablePointer<screen_char_t>(
            OpaquePointer(UnsafeMutableRawPointer(tokenPre).advanced(
                by: MemoryLayout<PreconvertedStringData>.offset(of: \PreconvertedStringData.staticBuffer)!)))
        if tokenPre.pointee.buffer == tokenStaticBuf {
            let preStaticBuf = UnsafeMutablePointer<screen_char_t>(
                OpaquePointer(UnsafeMutableRawPointer(prePtr).advanced(
                    by: MemoryLayout<PreconvertedStringData>.offset(of: \PreconvertedStringData.staticBuffer)!)))
            prePtr.pointee.buffer = preStaticBuf
        }
        tokenPre.pointee.valid = ObjCBool(false)
        tokenPre.pointee.buffer = nil

        screenB.performBlock(joinedThreads: { _, mutableState, _ in
            guard let ms = mutableState else { return }
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screenB.destructivelySetScreenWidth(20, height: 5, mutableState: ms)
            ms.appendString(atCursor: "e")
            ms.appendString(atCursor: part2, preconvertedData: prePtr)
            dumpB = ms.currentGrid.compactLineDump()
        })
        iTermPreconvertedStringDataFree(prePtr)
        prePtr.deinitialize(count: 1)
        prePtr.deallocate()

        // Both should show U (complex char = e + acute + cedilla) at position 0, then CJK.
        XCTAssertNotNil(dumpA)
        XCTAssertNotNil(dumpB)
        XCTAssertTrue(dumpA!.hasPrefix("U"), "Original: predecessor should be complex (e + acute + cedilla)")
        XCTAssertTrue(dumpB!.hasPrefix("U"), "Preconverted: predecessor should be complex (e + acute + cedilla)")
        XCTAssertEqual(dumpA, dumpB, "Preconversion should match original algorithm")
    }

    // MARK: - Test: Hangul Jamo composition with preconversion (regression)

    /// Regression test: verifies the preconversion path produces the same screen content
    /// as the original algorithm for Hangul Jamo L followed by V.
    func testHangulJamoCompositionWithPreconversion() {
        let part1 = "\u{1100}"              // Jamo L (ㄱ)
        let part2 = "\u{1161}你好世界"       // Jamo V (ㅏ) + CJK

        let nfcConfig = VT100StringConversionConfig(
            ambiguousIsDoubleWidth: ObjCBool(false),
            normalization: .NFC,
            unicodeVersion: 9,
            softAlternateScreenMode: ObjCBool(false)
        )

        // --- Screen A: original algorithm (no preconversion, NFC normalization) ---
        var dumpA: String?
        let sessionA = FakeSession()
        sessionA.configuration.normalization = .NFC
        sessionA.configuration.isDirty = true
        let screenA = VT100Screen()
        sessionA.screen = screenA
        screenA.delegate = sessionA
        screenA.performBlock(joinedThreads: { _, mutableState, _ in
            guard let ms = mutableState else { return }
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screenA.destructivelySetScreenWidth(20, height: 5, mutableState: ms)
            ms.appendString(atCursor: part1)
            ms.appendString(atCursor: part2)
            dumpA = ms.currentGrid.compactLineDump()
        })

        // --- Screen B: preconversion path (NFC normalization) ---
        var dumpB: String?
        let sessionB = FakeSession()
        sessionB.configuration.normalization = .NFC
        sessionB.configuration.isDirty = true
        let screenB = VT100Screen()
        sessionB.screen = screenB
        screenB.delegate = sessionB

        // Create preconverted data via parser with NFC normalization.
        // Copy into a heap-allocated struct so the token can be released without
        // invalidating the pointer. This also avoids Swift ARC issues with
        // capturing the token's internal pointer across the performBlock closure.
        let parser = makeParser()
        parser.update(nfcConfig)
        let tokens = parse(Array(part2.utf8), parser: parser)
        let strTokens = stringTokens(tokens)
        XCTAssertEqual(strTokens.count, 1, "Should produce one VT100_STRING token")
        let tokenPre = strTokens[0].preconvertedStringData
        XCTAssertTrue(tokenPre.pointee.valid.boolValue, "Preconverted data should be valid")

        // Deep-copy to a heap allocation we fully control.
        let prePtr = UnsafeMutablePointer<PreconvertedStringData>.allocate(capacity: 1)
        prePtr.initialize(to: tokenPre.pointee)
        // If the buffer points to the token's inline staticBuffer, fix up the self-referential
        // pointer to point to OUR staticBuffer instead.
        let tokenStaticBuf = UnsafeMutablePointer<screen_char_t>(
            OpaquePointer(UnsafeMutableRawPointer(tokenPre).advanced(
                by: MemoryLayout<PreconvertedStringData>.offset(of: \PreconvertedStringData.staticBuffer)!)))
        if tokenPre.pointee.buffer == tokenStaticBuf {
            let preStaticBuf = UnsafeMutablePointer<screen_char_t>(
                OpaquePointer(UnsafeMutableRawPointer(prePtr).advanced(
                    by: MemoryLayout<PreconvertedStringData>.offset(of: \PreconvertedStringData.staticBuffer)!)))
            prePtr.pointee.buffer = preStaticBuf
        }
        // Mark the token's copy invalid so its dealloc doesn't double-free the buffer.
        tokenPre.pointee.valid = ObjCBool(false)
        tokenPre.pointee.buffer = nil

        screenB.performBlock(joinedThreads: { _, mutableState, _ in
            guard let ms = mutableState else { return }
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screenB.destructivelySetScreenWidth(20, height: 5, mutableState: ms)
            ms.appendString(atCursor: part1)
            ms.appendString(atCursor: part2, preconvertedData: prePtr)
            dumpB = ms.currentGrid.compactLineDump()
        })
        iTermPreconvertedStringDataFree(prePtr)
        prePtr.deinitialize(count: 1)
        prePtr.deallocate()

        XCTAssertNotNil(dumpA)
        XCTAssertNotNil(dumpB)

        // Both paths produce the same result. Hangul Jamo L+V composition under NFC
        // does not happen in either path because normalization is applied to the string
        // BEFORE the predecessor is prepended, and StringToScreenChars does not
        // re-normalize. So this test serves as a regression test: if the preconversion
        // path ever diverges from the original, this will catch it.
        XCTAssertEqual(dumpA, dumpB,
                       "Screen content should match.\n" +
                       "  Original:     \(dumpA ?? "nil")\n" +
                       "  Preconverted: \(dumpB ?? "nil")")
    }
}

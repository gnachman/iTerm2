//
//  CharsetTests.swift
//  iTerm2
//
//  Tests for character set handling: enumerateComposedCharacters:,
//  StringToScreenChars, ComplexCharRegistry, and String.mayContainRTL.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Helpers

/// Build a string from an array of Unicode scalar values (supports supplementary plane).
private func stringFromCodePoints(_ codePoints: [UInt32]) -> String {
    return String(codePoints.compactMap { Unicode.Scalar($0) }.map { Character($0) })
}


/// Call StringToScreenChars and return the result buffer, length, and rtlFound flag.
private func callStringToScreenChars(
    _ s: String,
    ambiguousIsDoubleWidth: Bool = false,
    unicodeVersion: Int = 9,
    softAlternateScreenMode: Bool = false
) -> (buf: [screen_char_t], len: Int, rtlFound: Bool) {
    let nsString = s as NSString
    let bufSize = max(nsString.length * 2 + 1, 4)
    let malloced = malloc(bufSize * MemoryLayout<screen_char_t>.size)!
    let buffer = malloced.assumingMemoryBound(to: screen_char_t.self)
    defer { free(malloced) }

    let fg = screen_char_t()
    let bg = screen_char_t()
    var len = Int32(0)
    var foundDwc: ObjCBool = false
    var rtlFound: ObjCBool = false

    withUnsafeMutablePointer(to: &len) { lenPtr in
        withUnsafeMutablePointer(to: &foundDwc) { foundDwcPtr in
            withUnsafeMutablePointer(to: &rtlFound) { rtlFoundPtr in
                StringToScreenChars(
                    s,
                    buffer,
                    fg,
                    bg,
                    lenPtr,
                    ambiguousIsDoubleWidth,
                    nil,
                    foundDwcPtr,
                    .none,
                    unicodeVersion,
                    softAlternateScreenMode,
                    rtlFoundPtr
                )
            }
        }
    }

    let count = Int(len)
    var result = [screen_char_t]()
    for i in 0..<count {
        result.append(buffer[i])
    }
    return (result, count, rtlFound.boolValue)
}

/// Get the string representation for a screen_char_t.
private func screenCharString(_ c: screen_char_t) -> String? {
    return CharToStr(c.code, c.complexChar != 0) as String?
}

// MARK: - Section 1: enumerateComposedCharacters Tests

final class EnumerateComposedCharactersTests: XCTestCase {

    // Collects segments from enumerateComposedCharacters.
    private struct Segment {
        let range: NSRange
        let simple: unichar      // non-zero when range.length == 1
        let complexString: String?
    }

    private func segments(of string: String) -> [Segment] {
        var result = [Segment]()
        (string as NSString).enumerateComposedCharacters { range, simple, complex, stop in
            // When range.length == 1, the ObjC code sets simple to the character and complexString to nil.
            // However, due to NS_ASSUME_NONNULL, complexString imports as non-optional String in Swift,
            // so we use range.length to distinguish simple from complex segments.
            if range.length == 1 {
                result.append(Segment(range: range, simple: simple, complexString: nil))
            } else {
                result.append(Segment(range: range, simple: 0, complexString: complex))
            }
        }
        return result
    }

    // MARK: 1.1 Basic Segmentation

    /// 1.1.1 Empty string produces no segments.
    func testBasic_empty() {
        let segs = segments(of: "")
        XCTAssertEqual(segs.count, 0)
    }

    /// 1.1.2 Single ASCII character.
    func testBasic_singleASCII() {
        let segs = segments(of: "A")
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].simple, unichar(0x41))
        XCTAssertNil(segs[0].complexString)
    }

    /// 1.1.3 Multiple ASCII characters.
    func testBasic_multipleASCII() {
        let segs = segments(of: "abc")
        XCTAssertEqual(segs.count, 3)
        XCTAssertEqual(segs[0].simple, unichar(0x61))
        XCTAssertEqual(segs[1].simple, unichar(0x62))
        XCTAssertEqual(segs[2].simple, unichar(0x63))
    }

    /// 1.1.4 Single BMP non-ASCII (CJK 一).
    func testBasic_singleBMPNonASCII() {
        let segs = segments(of: "\u{4E00}")
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].simple, unichar(0x4E00))
    }

    /// 1.1.5 Supplementary plane character (😀 U+1F600).
    func testBasic_supplementaryPlane() {
        let segs = segments(of: "\u{1F600}")
        XCTAssertEqual(segs.count, 1)
        // Supplementary characters require a surrogate pair → complexString
        XCTAssertNotNil(segs[0].complexString)
    }

    // MARK: 1.2 Aggressive Base Character Detection

    /// 1.2.1 Tamil: aggressive=YES splits on second base character and spacing combining mark.
    /// Input: 0B95 0BCD 0B95 0BC1
    /// With codePointsWithOwnCell, both 0B95 (base char) and 0BC1 (spacing combining mark)
    /// are exceptions, producing 3 segments.
    func testAggressive_tamilSplit() {
        let s = stringFromCodePoints([0x0B95, 0x0BCD, 0x0B95, 0x0BC1])
        let segs = segments(of: s)
        XCTAssertEqual(segs.count, 3, "Expected three segments: 0B95+0BCD, 0B95, 0BC1")

        // First segment: 0B95 0BCD
        let first = (s as NSString).substring(with: segs[0].range)
        XCTAssertEqual(first, stringFromCodePoints([0x0B95, 0x0BCD]))

        // Second segment: 0B95
        let second = (s as NSString).substring(with: segs[1].range)
        XCTAssertEqual(second, stringFromCodePoints([0x0B95]))

        // Third segment: 0BC1 (spacing combining mark with own cell)
        let third = (s as NSString).substring(with: segs[2].range)
        XCTAssertEqual(third, stringFromCodePoints([0x0BC1]))
    }

    // 1.2.2 (aggressive=NO) — skipped: dispatch_once caches the exceptions set
    // with the default aggressiveBaseCharacterDetection=YES. Testing non-aggressive
    // mode requires a separate process or refactoring the dispatch_once.

    /// 1.2.3 Spacing combining mark gets own cell (aggressive=YES).
    /// Input: 0B95 0BC6
    func testAggressive_spacingCombiningMarkSplit() {
        let s = stringFromCodePoints([0x0B95, 0x0BC6])
        let segs = segments(of: s)
        XCTAssertEqual(segs.count, 2, "Spacing combining mark 0BC6 should get its own segment")

        let first = (s as NSString).substring(with: segs[0].range)
        XCTAssertEqual(first, stringFromCodePoints([0x0B95]))

        let second = (s as NSString).substring(with: segs[1].range)
        XCTAssertEqual(second, stringFromCodePoints([0x0BC6]))
    }

    // MARK: 1.3 Non-Aggressive — Halfwidth Katakana

    // 1.3.1 and 1.3.2 (aggressive=NO) — skipped: same dispatch_once limitation.

    /// 1.3.3 FF9E is also split in aggressive mode (it is in codePointsWithOwnCell).
    func testAggressive_halfwidthKatakanaVoicedMark() {
        let s = stringFromCodePoints([0x3046, 0xFF9E])
        let segs = segments(of: s)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].simple, unichar(0x3046))

        let second = (s as NSString).substring(with: segs[1].range)
        XCTAssertEqual(second, stringFromCodePoints([0xFF9E]))
    }

    // MARK: 1.4 ZWJ Prevents Splitting

    /// 1.4.1 Woman cook ZWJ sequence stays as one segment.
    func testZWJ_womanCook() {
        // 👩‍🍳 = U+1F469 U+200D U+1F373
        let s = stringFromCodePoints([0x1F469, 0x200D, 0x1F373])
        let segs = segments(of: s)
        XCTAssertEqual(segs.count, 1, "ZWJ sequence must stay as one segment")
    }

    /// 1.4.2 Multi-ZWJ emoji sequence.
    func testZWJ_multiZWJ() {
        // 👨‍❤️‍👨 = U+1F468 U+200D U+2764 U+FE0F U+200D U+1F468
        let s = stringFromCodePoints([0x1F468, 0x200D, 0x2764, 0xFE0F, 0x200D, 0x1F468])
        let segs = segments(of: s)
        XCTAssertEqual(segs.count, 1, "Multi-ZWJ emoji sequence must stay as one segment")
    }

    // MARK: 1.5 Edge Cases

    /// 1.5.1 Valid supplementary character produces one complex segment.
    func testEdge_validSupplementary() {
        let s = "\u{1F600}" // 😀
        let segs = segments(of: s)
        XCTAssertEqual(segs.count, 1)
        XCTAssertNotNil(segs[0].complexString)
    }

    /// 1.5.3 Long composed sequence (> kMaxParts) — enumerateComposedCharacters
    /// itself does not truncate. StringToScreenChars does.
    func testEdge_longComposedSequence() {
        // Build a string with a base char + 25 combining marks (> kMaxParts=20 UTF-16 units)
        var codePoints: [UInt32] = [0x0041] // 'A'
        for _ in 0..<25 {
            codePoints.append(0x0300) // combining grave accent
        }
        let s = stringFromCodePoints(codePoints)
        let segs = segments(of: s)
        // enumerateComposedCharacters returns the full cluster
        XCTAssertEqual(segs.count, 1)
        // The complexString should contain all code points
        XCTAssertNotNil(segs[0].complexString)
        XCTAssertEqual((segs[0].complexString! as NSString).length, 26)
    }
}

// MARK: - Section 2: StringToScreenChars Tests

final class StringToScreenCharsTests: XCTestCase {

    // MARK: 2.1 Ignorable Characters (BMP)

    /// 2.1.1 U+00AD soft hyphen is ignorable.
    func testIgnorable_softHyphen() {
        let s = "A\u{00AD}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    /// 2.1.2 U+034F combining grapheme joiner.
    /// Although 034F has Default_Ignorable_Code_Point, it is a combining mark (gc=Mn) that
    /// joins with the preceding character in grapheme cluster segmentation. The ignorable
    /// check only applies to standalone simple characters, so 034F combined with A produces
    /// a complex character.
    func testIgnorable_combiningGraphemeJoiner() {
        let s = "A\u{034F}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        // First cell is A+034F as a complex char
        XCTAssertEqual(buf[0].complexChar, 1)
        let nsStr = screenCharString(buf[0])! as NSString
        XCTAssertEqual(nsStr.length, 2)
        XCTAssertEqual(nsStr.character(at: 0), unichar(0x41))   // A
        XCTAssertEqual(nsStr.character(at: 1), unichar(0x034F)) // CGJ
        // Second cell is B
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    /// 2.1.3 U+061C Arabic letter mark is ignorable.
    func testIgnorable_arabicLetterMark() {
        let s = "A\u{061C}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    /// 2.1.4 U+2060 word joiner is ignorable.
    func testIgnorable_wordJoiner() {
        let s = "A\u{2060}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    /// 2.1.5 U+FEFF BOM/ZWNBSP is ignorable.
    func testIgnorable_bom() {
        let s = "A\u{FEFF}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    /// 2.1.6 U+FFF0 (unassigned ignorable) is ignorable.
    func testIgnorable_fff0() {
        let s = "A\u{FFF0}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    // MARK: 2.2 Zero-Width Space (U+200B)

    // Default zeroWidthSpaceAdvancesCursor=YES, so 200B is NOT ignorable.
    // 2.2.1 (zeroWidthSpaceAdvancesCursor=NO) — skipped due to dispatch_once caching.

    /// 2.2.2 zeroWidthSpaceAdvancesCursor=YES: 200B gets its own cell.
    func testZWS_advancesCursor() {
        let s = "A\u{200B}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 3)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x200B))
        XCTAssertEqual(buf[2].code, unichar(0x42))
    }

    // MARK: 2.3 Zero-Width Non-Joiner (U+200C)

    /// 2.3.1 ZWNJ is appended to previous character.
    func testZWNJ_appendedToPrevious() {
        let s = "A\u{200C}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        // First cell should be complex (A + ZWNJ)
        XCTAssertEqual(buf[0].complexChar, 1)
        let nsStr = screenCharString(buf[0])! as NSString
        XCTAssertEqual(nsStr.length, 2, "Expected A + ZWNJ (2 UTF-16 code units)")
        XCTAssertEqual(nsStr.character(at: 0), unichar(0x41))
        XCTAssertEqual(nsStr.character(at: 1), unichar(0x200C))
        // Second cell is B
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    /// 2.3.2 ZWNJ at start of string (no previous character).
    func testZWNJ_atStart() {
        let s = "\u{200C}A"
        let (buf, len, _) = callStringToScreenChars(s)
        // ZWNJ at j=0 falls through to ignorable check and is skipped.
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].code, unichar(0x41))
    }

    // MARK: 2.4 Ignorable Characters (Supplementary Plane)

    /// 2.4.1 U+E0001 language tag is ignorable.
    func testIgnorableSupp_languageTag() {
        let s = "A\u{E0001}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    /// 2.4.2 U+1BCA0 shorthand format control is ignorable.
    func testIgnorableSupp_shorthandFormatControl() {
        let s = "A\u{1BCA0}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    /// 2.4.3 U+1D173 musical symbol begin beam is ignorable.
    func testIgnorableSupp_musicalSymbol() {
        let s = "A\u{1D173}B"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(0x42))
    }

    // MARK: 2.5 Spacing Combining Marks

    /// 2.5.1 Standalone spacing combining mark 0BC6 (aggressive=YES, old behavior).
    func testSpacingCombiningMark_0BC6_aggressive() {
        let s = stringFromCodePoints([0x0BC6])
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        // Old code always treats spacing combining marks as complex with spacingCombiningMark=YES
        XCTAssertEqual(buf[0].complexChar, 1)
        XCTAssertTrue(ComplexCharCodeIsSpacingCombiningMark(buf[0].code))
    }

    /// 2.5.2 Standalone spacing combining mark 0BC6 (old behavior: always promoted).
    /// In the old code, this is treated the same regardless of aggressiveBaseCharacterDetection.
    func testSpacingCombiningMark_0BC6_oldBehavior() {
        // With the old code, spacing combining marks are always promoted
        let s = stringFromCodePoints([0x0BC6])
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].complexChar, 1)
        XCTAssertTrue(ComplexCharCodeIsSpacingCombiningMark(buf[0].code))
    }

    /// 2.5.3 Devanagari visarga U+0903.
    func testSpacingCombiningMark_devanagariVisarga() {
        let s = stringFromCodePoints([0x0903])
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].complexChar, 1)
        XCTAssertTrue(ComplexCharCodeIsSpacingCombiningMark(buf[0].code))
    }

    /// 2.5.4 Bengali anusvara U+0982.
    func testSpacingCombiningMark_bengaliAnusvara() {
        let s = stringFromCodePoints([0x0982])
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].complexChar, 1)
        XCTAssertTrue(ComplexCharCodeIsSpacingCombiningMark(buf[0].code))
    }

    // MARK: 2.6 Emoji + VS16

    // Default: vs16Supported=NO, vs16SupportedInPrimaryScreen=YES.
    // With softAlternateScreenMode=NO → shouldSupportVS16=YES.
    // With softAlternateScreenMode=YES → shouldSupportVS16=NO.

    /// 2.6.1 Heart + VS16 → double-width.
    func testEmojiVS16_heartWithVS16() {
        let s = stringFromCodePoints([0x2764, 0xFE0F])
        let (buf, len, _) = callStringToScreenChars(s, softAlternateScreenMode: false)
        // Double-width: base char + DWC_RIGHT
        XCTAssertEqual(len, 2)
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(buf[1]))
    }

    /// 2.6.2 Heart without VS16 → single-width.
    func testEmojiVS16_heartWithoutVS16() {
        let s = stringFromCodePoints([0x2764])
        let (_, len, _) = callStringToScreenChars(s, softAlternateScreenMode: false)
        XCTAssertEqual(len, 1)
    }

    /// 2.6.3 Index pointing up + VS16 → double-width.
    func testEmojiVS16_indexPointingUp() {
        let s = stringFromCodePoints([0x261D, 0xFE0F])
        let (buf, len, _) = callStringToScreenChars(s, softAlternateScreenMode: false)
        XCTAssertEqual(len, 2)
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(buf[1]))
    }

    /// 2.6.4 Index pointing up + skin tone modifier.
    /// With aggressive base character detection, the skin tone modifier (U+1F3FB)
    /// is in codePointsWithOwnCell and gets split from the base emoji. Each becomes
    /// its own cell(s).
    func testEmojiVS16_indexPointingUpSkinTone() {
        let s = stringFromCodePoints([0x261D, 0x1F3FB])
        let (buf, len, _) = callStringToScreenChars(s, softAlternateScreenMode: false)
        // Aggressive mode splits them: 261D (possibly double-width) + 1F3FB (double-width)
        XCTAssertGreaterThanOrEqual(len, 2)
        // Verify at least one cell contains the base emoji
        let firstIsComplex = buf[0].complexChar != 0
        if !firstIsComplex {
            XCTAssertEqual(buf[0].code, unichar(0x261D))
        }
    }

    /// 2.6.5 VS16 not supported (softAlternateScreenMode=YES) → single-width.
    func testEmojiVS16_notSupported() {
        let s = stringFromCodePoints([0x2764, 0xFE0F])
        let (_, len, _) = callStringToScreenChars(s, softAlternateScreenMode: true)
        XCTAssertEqual(len, 1)
    }

    /// 2.6.6 Supplementary emoji + VS16 → double-width (already DW by default).
    func testEmojiVS16_supplementaryEmoji() {
        let s = stringFromCodePoints([0x1F600, 0xFE0F])
        let (buf, len, _) = callStringToScreenChars(s, softAlternateScreenMode: false)
        // 😀 is already double-width; VS16 doesn't change that
        XCTAssertEqual(len, 2)
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(buf[1]))
    }

    // MARK: 2.7 Skin Tone Modifiers

    // With aggressive base character detection, skin tone modifiers (U+1F3FB-1F3FF)
    // are in codePointsWithOwnCell and get split from the base emoji during
    // enumerateComposedCharacters. Each part gets its own cell(s).

    /// 2.7.1 Hand + medium skin tone (split by aggressive mode).
    func testSkinTone_medium() {
        let s = stringFromCodePoints([0x270B, 0x1F3FD])
        let (buf, len, _) = callStringToScreenChars(s, softAlternateScreenMode: false)
        // 270B and 1F3FD are split; each may be double-width
        XCTAssertGreaterThanOrEqual(len, 2)
        // Verify the base emoji is present
        XCTAssertTrue(buf[0].code == unichar(0x270B) || buf[0].complexChar != 0)
    }

    /// 2.7.2 Hand + lightest skin tone (split by aggressive mode).
    func testSkinTone_lightest() {
        let s = stringFromCodePoints([0x270B, 0x1F3FB])
        let (buf, len, _) = callStringToScreenChars(s, softAlternateScreenMode: false)
        XCTAssertGreaterThanOrEqual(len, 2)
        XCTAssertTrue(buf[0].code == unichar(0x270B) || buf[0].complexChar != 0)
    }

    /// 2.7.3 Hand + darkest skin tone (split by aggressive mode).
    func testSkinTone_darkest() {
        let s = stringFromCodePoints([0x270B, 0x1F3FF])
        let (buf, len, _) = callStringToScreenChars(s, softAlternateScreenMode: false)
        XCTAssertGreaterThanOrEqual(len, 2)
        XCTAssertTrue(buf[0].code == unichar(0x270B) || buf[0].complexChar != 0)
    }

    // MARK: 2.8 RTL Detection

    /// 2.8.1 Pure ASCII → no RTL.
    func testRTL_pureASCII() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi) }
        let (_, _, rtl) = callStringToScreenChars("Hello")
        XCTAssertFalse(rtl)
    }

    /// 2.8.2 Hebrew alef → RTL found.
    func testRTL_hebrew() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi) }
        let s = stringFromCodePoints([0x05D0])
        let (_, _, rtl) = callStringToScreenChars(s)
        XCTAssertTrue(rtl)
    }

    /// 2.8.3 Arabic alef → RTL found.
    func testRTL_arabic() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi) }
        let s = stringFromCodePoints([0x0627])
        let (_, _, rtl) = callStringToScreenChars(s)
        XCTAssertTrue(rtl)
    }

    /// 2.8.4 Bidi disabled → always NO.
    func testRTL_disabled() {
        iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi)
        let s = stringFromCodePoints([0x05D0])
        let (_, _, rtl) = callStringToScreenChars(s)
        XCTAssertFalse(rtl)
    }

    /// 2.8.5 Mixed LTR/RTL → RTL found.
    func testRTL_mixed() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi) }
        let s = "Hello " + stringFromCodePoints([0x05D0]) + " world"
        let (_, _, rtl) = callStringToScreenChars(s)
        XCTAssertTrue(rtl)
    }

    /// 2.8.6 Supplementary RTL (Cypriot syllable U+10800).
    func testRTL_supplementary() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi) }
        let s = stringFromCodePoints([0x10800])
        let (_, _, rtl) = callStringToScreenChars(s)
        XCTAssertTrue(rtl)
    }

    /// 2.8.7 Bidi formatting character (RLE U+202B).
    func testRTL_bidiFormatting() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi) }
        let s = stringFromCodePoints([0x202B])
        let (_, _, rtl) = callStringToScreenChars(s)
        XCTAssertTrue(rtl)
    }

    // MARK: 2.9 Surrogate Handling

    /// 2.9.1 Lone low surrogate → U+FFFD.
    func testSurrogate_loneLow() {
        // Construct a string with a lone low surrogate by using NSString directly
        var chars: [unichar] = [0xDC00]
        let s = NSString(characters: &chars, length: 1) as String
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].code, unichar(UNICODE_REPLACEMENT_CHAR))
    }

    /// 2.9.2 Lone high surrogate mid-string → U+FFFD.
    func testSurrogate_loneHighMidString() {
        var chars: [unichar] = [0x41, 0xD800, 0x42]
        let s = NSString(characters: &chars, length: 3) as String
        let (buf, len, _) = callStringToScreenChars(s)
        // Should produce A, FFFD, B
        XCTAssertGreaterThanOrEqual(len, 3)
        XCTAssertEqual(buf[0].code, unichar(0x41))
        XCTAssertEqual(buf[1].code, unichar(UNICODE_REPLACEMENT_CHAR))
        XCTAssertEqual(buf[2].code, unichar(0x42))
    }

    /// 2.9.3 Valid surrogate pair → decoded as U+1F600.
    func testSurrogate_validPair() {
        let s = "\u{1F600}"
        let (buf, len, _) = callStringToScreenChars(s)
        // 😀 is double-width → 2 cells
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].complexChar, 1)
        // Verify the complex string represents U+1F600
        let str = screenCharString(buf[0])!
        XCTAssertEqual(str, "\u{1F600}")
    }

    // MARK: 2.10 Private-Use Area

    /// 2.10.1 ITERM2_PRIVATE_BEGIN → U+FFFD.
    func testPrivateUse_begin() {
        var chars: [unichar] = [unichar(ITERM2_PRIVATE_BEGIN)]
        let s = NSString(characters: &chars, length: 1) as String
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].code, unichar(UNICODE_REPLACEMENT_CHAR))
    }

    /// 2.10.2 ITERM2_PRIVATE_END → U+FFFD.
    func testPrivateUse_end() {
        var chars: [unichar] = [unichar(ITERM2_PRIVATE_END)]
        let s = NSString(characters: &chars, length: 1) as String
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].code, unichar(UNICODE_REPLACEMENT_CHAR))
    }

    // MARK: 2.11 Double-Width Characters

    /// 2.11.1 CJK ideograph 一 → double-width.
    func testDoubleWidth_cjk() {
        let s = "\u{4E00}"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0x4E00))
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(buf[1]))
    }

    /// 2.11.2 Hangul syllable 가 → double-width.
    func testDoubleWidth_hangul() {
        let s = "\u{AC00}"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 2)
        XCTAssertEqual(buf[0].code, unichar(0xAC00))
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(buf[1]))
    }

    /// 2.11.3 ASCII A → single-width.
    func testDoubleWidth_ascii() {
        let s = "A"
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].code, unichar(0x41))
    }

    // MARK: 2.12 Curly Quote Variation Selectors

    /// 2.12.1 Left double quote + VS0 → single-width.
    func testCurlyQuote_leftDoubleVS0() {
        let s = stringFromCodePoints([0x201C, 0xFE00])
        let (_, len, _) = callStringToScreenChars(s, unicodeVersion: 9)
        XCTAssertEqual(len, 1)
    }

    /// 2.12.2 Left double quote + VS1 → double-width.
    func testCurlyQuote_leftDoubleVS1() {
        let s = stringFromCodePoints([0x201C, 0xFE01])
        let (buf, len, _) = callStringToScreenChars(s, unicodeVersion: 9)
        XCTAssertEqual(len, 2)
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(buf[1]))
    }

    /// 2.12.3 Left single quote + VS0 → single-width.
    func testCurlyQuote_leftSingleVS0() {
        let s = stringFromCodePoints([0x2018, 0xFE00])
        let (_, len, _) = callStringToScreenChars(s, unicodeVersion: 9)
        XCTAssertEqual(len, 1)
    }

    /// 2.12.4 Right single quote + VS1 → double-width.
    func testCurlyQuote_rightSingleVS1() {
        let s = stringFromCodePoints([0x2019, 0xFE01])
        let (buf, len, _) = callStringToScreenChars(s, unicodeVersion: 9)
        XCTAssertEqual(len, 2)
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(buf[1]))
    }

    // MARK: 2.13 Kitty Image Placeholder

    /// 2.13.1 U+10EEEE → image=YES, virtualPlaceholder=YES, single-width.
    func testKittyPlaceholder() {
        let s = stringFromCodePoints([0x10EEEE])
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        XCTAssertEqual(buf[0].image, 1)
        XCTAssertEqual(buf[0].virtualPlaceholder, 1)
    }
}

// MARK: - Section 3: ComplexCharRegistry — Spacing Combining Mark Detection

final class SpacingCombiningMarkTests: XCTestCase {

    /// 3.1 U+0BC6 is a spacing combining mark.
    func testSpacingCombiningMark_0BC6() {
        let s = stringFromCodePoints([0x0B95, 0x0BC6])
        // Register as complex char and check
        let (buf, len, _) = callStringToScreenChars(s)
        // Find the cell that represents 0BC6 (should be a separate cell due to aggressive splitting)
        // With aggressive mode, 0B95 and 0BC6 are separate.
        // 0BC6 should be marked as spacing combining mark.
        XCTAssertGreaterThanOrEqual(len, 1)
        let lastIdx = len - 1
        if buf[lastIdx].complexChar != 0 {
            XCTAssertTrue(ComplexCharCodeIsSpacingCombiningMark(buf[lastIdx].code))
        }
    }

    /// 3.2 U+0BCD is NOT a spacing combining mark (it's gc=Mn, non-spacing).
    func testNotSpacingCombiningMark_0BCD() {
        let s = stringFromCodePoints([0x0B95, 0x0BCD])
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertGreaterThanOrEqual(len, 1)
        for i in 0..<len {
            if buf[i].complexChar != 0 {
                XCTAssertFalse(ComplexCharCodeIsSpacingCombiningMark(buf[i].code),
                               "0BCD should not be flagged as spacing combining mark")
            }
        }
    }

    /// 3.3 Plain ASCII does not contain spacing combining marks.
    func testNotSpacingCombiningMark_ascii() {
        let s = "AB"
        let (buf, len, _) = callStringToScreenChars(s)
        for i in 0..<len {
            XCTAssertEqual(buf[i].complexChar, 0)
        }
    }

    /// 3.4 Supplementary spacing combining mark (Brahmi U+11000).
    /// In the current code, the spacing combining mark check in StringToScreenChars
    /// only applies to BMP characters in the simple path. Supplementary characters
    /// go through the complex path where spacingCombiningMark is not set.
    func testSpacingCombiningMark_supplementary() {
        let s = stringFromCodePoints([0x11000])
        let (buf, len, _) = callStringToScreenChars(s)
        XCTAssertEqual(len, 1)
        // Supplementary chars are always complex (surrogate pair)
        XCTAssertEqual(buf[0].complexChar, 1)
        // Current code does NOT flag supplementary spacing combining marks
        XCTAssertFalse(ComplexCharCodeIsSpacingCombiningMark(buf[0].code),
                       "Current code does not detect supplementary spacing combining marks")
    }
}

// MARK: - Section 4: String.mayContainRTL

final class MayContainRTLTests: XCTestCase {

    /// 4.1 Pure ASCII → false.
    func testMayContainRTL_ascii() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi) }
        XCTAssertFalse("Hello".mayContainRTL)
    }

    /// 4.2 Hebrew letter → true.
    func testMayContainRTL_hebrew() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi) }
        XCTAssertTrue("\u{05D0}".mayContainRTL)
    }

    /// 4.3 Bidi disabled → false even with Hebrew.
    func testMayContainRTL_disabled() {
        iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi)
        XCTAssertFalse("\u{05D0}".mayContainRTL)
    }
}

// MARK: - Section 6: Performance Smoke Tests

final class CharsetPerformanceTests: XCTestCase {

    /// 6.1 10,000-character ASCII string.
    func testPerf_ascii() {
        let s = String(repeating: "A", count: 10_000)
        measure {
            _ = callStringToScreenChars(s)
        }
    }

    /// 6.2 10,000-character CJK string.
    func testPerf_cjk() {
        let s = String(repeating: "\u{4E00}", count: 10_000)
        measure {
            _ = callStringToScreenChars(s)
        }
    }

    /// 6.3 1,000-character mixed emoji/ZWJ string.
    func testPerf_emojiZWJ() {
        let emoji = "\u{1F469}\u{200D}\u{1F373}" // 👩‍🍳
        let s = String(repeating: emoji, count: 1_000)
        measure {
            _ = callStringToScreenChars(s)
        }
    }

    /// 6.4 10,000-character Tamil string (aggressive splitting).
    func testPerf_tamil() {
        let tamil = stringFromCodePoints([0x0B95, 0x0BCD, 0x0B95, 0x0BC1])
        let s = String(repeating: tamil, count: 2_500) // ~10,000 chars
        measure {
            let nsStr = s as NSString
            nsStr.enumerateComposedCharacters { _, _, _, _ in }
        }
    }
}

import XCTest
@testable import iTerm2SharedARC

final class iTermExternalAttributeSerializationTests: XCTestCase {

    // MARK: - Helpers

    private func makeDualRGB(_ rl: Int32, _ gl: Int32, _ bl: Int32,
                             _ rd: Int32, _ gd: Int32, _ bd: Int32) -> iTermDualModeColor {
        var d = iTermDualModeColor()
        d.valid = ObjCBool(true)
        d.light = VT100TerminalColorValue(red: rl, green: gl, blue: bl, mode: ColorMode24bit,
                                          hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        d.dark = VT100TerminalColorValue(red: rd, green: gd, blue: bd, mode: ColorMode24bit,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        return d
    }

    private func makeDualIndexed(_ nl: Int32, _ nd: Int32) -> iTermDualModeColor {
        var d = iTermDualModeColor()
        d.valid = ObjCBool(true)
        d.light = VT100TerminalColorValue(red: nl, green: 0, blue: 0, mode: ColorModeNormal,
                                          hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        d.dark = VT100TerminalColorValue(red: nd, green: 0, blue: 0, mode: ColorModeNormal,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        return d
    }

    private func dualEqual(_ a: iTermDualModeColor, _ b: iTermDualModeColor) -> Bool {
        if a.valid.boolValue != b.valid.boolValue { return false }
        if !a.valid.boolValue { return true }
        return a.light.red == b.light.red && a.light.green == b.light.green &&
               a.light.blue == b.light.blue && a.light.mode == b.light.mode &&
               a.dark.red == b.dark.red && a.dark.green == b.dark.green &&
               a.dark.blue == b.dark.blue && a.dark.mode == b.dark.mode
    }

    private func makeAttribute(hasUC: Bool = false,
                               uc: VT100TerminalColorValue = VT100TerminalColorValue(),
                               url: iTermURL? = nil,
                               blockIDList: String? = nil,
                               controlCode: NSNumber? = nil,
                               dualFg: iTermDualModeColor = iTermDualModeColor(),
                               dualBg: iTermDualModeColor = iTermDualModeColor()) -> iTermExternalAttribute? {
        return iTermExternalAttribute(havingUnderlineColor: hasUC,
                                      underlineColor: uc,
                                      url: url,
                                      blockIDList: blockIDList,
                                      controlCode: controlCode,
                                      dualModeForeground: dualFg,
                                      dualModeBackground: dualBg)
    }

    // MARK: - TLV round-trip

    func testTLVRoundTripDefaultIsNil() {
        XCTAssertNil(makeAttribute())
    }

    func testTLVRoundTripUnderlineColorOnly() {
        let uc = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        guard let ea = makeAttribute(hasUC: true, uc: uc) else {
            XCTFail("expected non-nil attribute"); return
        }
        guard let decoded = iTermExternalAttribute.fromData(ea.data()) else {
            XCTFail("expected decode to succeed"); return
        }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 11)
        XCTAssertEqual(decoded.underlineColor.green, 22)
        XCTAssertEqual(decoded.underlineColor.blue, 33)
        XCTAssertEqual(decoded.underlineColor.mode, ColorMode24bit)
        XCTAssertFalse(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertFalse(decoded.dualModeForeground.valid.boolValue)
        XCTAssertFalse(decoded.dualModeBackground.valid.boolValue)
    }

    func testTLVRoundTripDualModeUnderlineRGB() {
        let uc = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                         hasDarkVariant: true, redDark: 44, greenDark: 55, blueDark: 66)
        guard let ea = makeAttribute(hasUC: true, uc: uc) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute.fromData(ea.data()) else { XCTFail(); return }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 11)
        XCTAssertEqual(decoded.underlineColor.green, 22)
        XCTAssertEqual(decoded.underlineColor.blue, 33)
        XCTAssertEqual(decoded.underlineColor.mode, ColorMode24bit)
        XCTAssertTrue(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(decoded.underlineColor.redDark, 44)
        XCTAssertEqual(decoded.underlineColor.greenDark, 55)
        XCTAssertEqual(decoded.underlineColor.blueDark, 66)
    }

    func testTLVRoundTripDualModeUnderlineIndexed() {
        let uc = VT100TerminalColorValue(red: 208, green: 0, blue: 0, mode: ColorModeNormal,
                                         hasDarkVariant: true, redDark: 120, greenDark: 0, blueDark: 0)
        guard let ea = makeAttribute(hasUC: true, uc: uc) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute.fromData(ea.data()) else { XCTFail(); return }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 208)
        XCTAssertEqual(decoded.underlineColor.mode, ColorModeNormal)
        XCTAssertTrue(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(decoded.underlineColor.redDark, 120)
    }

    // Dual-mode underline must round-trip cleanly even when fg/bg dual mode
    // is also set — the v5 trailer comes after v4, so if v4 elision is wrong
    // the underline dark variant gets misread.
    func testTLVRoundTripDualUnderlineWithDualFgBg() {
        let uc = VT100TerminalColorValue(red: 1, green: 2, blue: 3, mode: ColorMode24bit,
                                         hasDarkVariant: true, redDark: 4, greenDark: 5, blueDark: 6)
        let fg = makeDualRGB(10, 20, 30, 40, 50, 60)
        let bg = makeDualIndexed(70, 80)
        guard let ea = makeAttribute(hasUC: true, uc: uc, dualFg: fg, dualBg: bg) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute.fromData(ea.data()) else { XCTFail(); return }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertTrue(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(decoded.underlineColor.redDark, 4)
        XCTAssertEqual(decoded.underlineColor.greenDark, 5)
        XCTAssertEqual(decoded.underlineColor.blueDark, 6)
        XCTAssertTrue(dualEqual(decoded.dualModeForeground, fg))
        XCTAssertTrue(dualEqual(decoded.dualModeBackground, bg))
    }

    func testTLVRoundTripDualModeFgRGBOnly() {
        let fg = makeDualRGB(1, 2, 3, 4, 5, 6)
        guard let ea = makeAttribute(dualFg: fg) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute.fromData(ea.data()) else { XCTFail(); return }
        XCTAssertFalse(decoded.hasUnderlineColor)
        XCTAssertTrue(dualEqual(decoded.dualModeForeground, fg))
        XCTAssertFalse(decoded.dualModeBackground.valid.boolValue)
    }

    func testTLVRoundTripDualModeFgIndexedOnly() {
        let fg = makeDualIndexed(208, 120)
        guard let ea = makeAttribute(dualFg: fg) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute.fromData(ea.data()) else { XCTFail(); return }
        XCTAssertTrue(dualEqual(decoded.dualModeForeground, fg))
        XCTAssertEqual(decoded.dualModeForeground.light.mode, ColorModeNormal)
        XCTAssertEqual(decoded.dualModeForeground.dark.mode, ColorModeNormal)
    }

    func testTLVRoundTripDualModeBgOnly() {
        let bg = makeDualRGB(10, 20, 30, 40, 50, 60)
        guard let ea = makeAttribute(dualBg: bg) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute.fromData(ea.data()) else { XCTFail(); return }
        XCTAssertFalse(decoded.dualModeForeground.valid.boolValue)
        XCTAssertTrue(dualEqual(decoded.dualModeBackground, bg))
    }

    func testTLVRoundTripAllFields() {
        let uc = VT100TerminalColorValue(red: 9, green: 8, blue: 7, mode: ColorMode24bit,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        let fg = makeDualRGB(1, 2, 3, 4, 5, 6)
        let bg = makeDualIndexed(13, 14)
        guard let ea = makeAttribute(hasUC: true, uc: uc, blockIDList: "id1,id2",
                                     controlCode: 0x42, dualFg: fg, dualBg: bg) else {
            XCTFail(); return
        }
        guard let decoded = iTermExternalAttribute.fromData(ea.data()) else { XCTFail(); return }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 9)
        XCTAssertEqual(decoded.underlineColor.green, 8)
        XCTAssertEqual(decoded.underlineColor.blue, 7)
        XCTAssertEqual(decoded.blockIDList, "id1,id2")
        XCTAssertEqual(decoded.controlCodeNumber, 0x42)
        XCTAssertTrue(dualEqual(decoded.dualModeForeground, fg))
        XCTAssertTrue(dualEqual(decoded.dualModeBackground, bg))
    }

    // MARK: - TLV tail elision

    // Adding dual-mode trailing bytes only happens when the data is non-default.
    // Verify the without-dual form encodes to a strictly shorter blob.
    func testTLVTailElidedWhenNoDualMode() {
        let uc = VT100TerminalColorValue(red: 1, green: 0, blue: 0, mode: ColorMode24bit,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        let withoutDual = makeAttribute(hasUC: true, uc: uc)!
        let withDual = makeAttribute(hasUC: true, uc: uc, dualFg: makeDualRGB(1,2,3,4,5,6))!
        XCTAssertLessThan(withoutDual.data().count, withDual.data().count)
    }

    // Underline color without a dark variant must be byte-identical to what
    // pre-dual-underline iTerm2 wrote. This pins the "rarely used, no bloat"
    // invariant — a regression here would expand every saved scrollback EA.
    func testTLVUnderlineWithoutDarkVariantIsByteIdenticalToLegacyForm() {
        let uc = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        guard let ea = makeAttribute(hasUC: true, uc: uc) else { XCTFail(); return }
        let actual = ea.data()

        // Hand-encode what pre-dual-underline iTerm2 would have written for
        // the same EA: the v1 underline block, then the deprecated urlCode
        // and v3 placeholders, with no v4 / v5 trailers.
        let expected = iTermTLVEncoder()
        expected.encode(true)                              // hasUnderlineColor
        expected.encode(Int32(11))
        expected.encode(Int32(22))
        expected.encode(Int32(33))
        expected.encode(Int32(ColorMode24bit.rawValue))
        expected.encodeUnsignedInt(UInt32.max)             // deprecated urlCode
        expected.encodeData(Data())                        // blockIDList
        expected.encode(Int32(-1))                         // controlCode

        XCTAssertEqual(actual, expected.data)
    }

    // MARK: - TLV backward compat

    // A blob produced by the pre-dual-mode encoder must still decode correctly.
    // This guards against a future change breaking saved scrollback.
    func testTLVDecodesPreDualModeBlob() {
        let encoder = iTermTLVEncoder()
        encoder.encode(true)                              // hasUnderlineColor
        encoder.encode(Int32(11))                         // red
        encoder.encode(Int32(22))                         // green
        encoder.encode(Int32(33))                         // blue
        encoder.encode(Int32(ColorMode24bit.rawValue))    // mode
        encoder.encodeUnsignedInt(UInt32.max)             // deprecated urlCode
        encoder.encodeData("block-1".data(using: .utf8)!)
        encoder.encode(Int32(0x07))                       // controlCode

        guard let decoded = iTermExternalAttribute.fromData(encoder.data) else {
            XCTFail("expected pre-dual-mode blob to decode"); return
        }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 11)
        XCTAssertEqual(decoded.underlineColor.green, 22)
        XCTAssertEqual(decoded.underlineColor.blue, 33)
        XCTAssertEqual(decoded.blockIDList, "block-1")
        XCTAssertEqual(decoded.controlCodeNumber, 7)
        XCTAssertFalse(decoded.dualModeForeground.valid.boolValue)
        XCTAssertFalse(decoded.dualModeBackground.valid.boolValue)
    }

    // The minimal pre-dual-mode shape (everything default) decodes to nil.
    func testTLVDecodesPreDualModeMinimalReturnsNil() {
        let encoder = iTermTLVEncoder()
        encoder.encode(false)
        encoder.encodeUnsignedInt(UInt32.max)
        encoder.encodeData(Data())
        encoder.encode(Int32(-1))
        XCTAssertNil(iTermExternalAttribute.fromData(encoder.data))
    }

    // A blob produced by the post-dual-fg/bg encoder but BEFORE we added
    // dual-mode underline support must still decode without claiming a dark
    // variant. The v5 trailer is append-at-end and missing trailing bytes
    // mean "no dual underline".
    func testTLVDecodesPreDualUnderlineBlob() {
        // Mirror the pre-dual-underline encoder: hasUnderlineColor=YES, the 4
        // underline ints, deprecated urlCode, blockData, controlCode, lineAttr,
        // and a v4 dual-fg block. Stop there — no v5 trailer.
        let encoder = iTermTLVEncoder()
        encoder.encode(true)                              // hasUnderlineColor
        encoder.encode(Int32(11))                         // red
        encoder.encode(Int32(22))                         // green
        encoder.encode(Int32(33))                         // blue
        encoder.encode(Int32(ColorMode24bit.rawValue))    // mode
        encoder.encodeUnsignedInt(UInt32.max)             // deprecated urlCode
        encoder.encodeData(Data())                        // blockIDList
        encoder.encode(Int32(-1))                         // controlCode
        encoder.encodeData(Data())                        // url
        encoder.encode(Int32(0))                          // lineAttribute
        encoder.encode(true)                              // hasDualFg
        // dual fg light + dark (8 ints)
        encoder.encode(Int32(1)); encoder.encode(Int32(2)); encoder.encode(Int32(3)); encoder.encode(Int32(ColorMode24bit.rawValue))
        encoder.encode(Int32(4)); encoder.encode(Int32(5)); encoder.encode(Int32(6)); encoder.encode(Int32(ColorMode24bit.rawValue))
        encoder.encode(false)                             // hasDualBg
        // No v5 trailer.

        guard let decoded = iTermExternalAttribute.fromData(encoder.data) else {
            XCTFail("expected pre-v5 blob to decode"); return
        }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 11)
        XCTAssertFalse(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertTrue(decoded.dualModeForeground.valid.boolValue)
        XCTAssertFalse(decoded.dualModeBackground.valid.boolValue)
    }

    // MARK: - Dictionary form

    func testDictionaryRoundTripDualModeFg() {
        let fg = makeDualRGB(7, 8, 9, 70, 80, 90)
        guard let ea = makeAttribute(dualFg: fg) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute(dictionary: ea.dictionaryValue) else {
            XCTFail(); return
        }
        XCTAssertTrue(dualEqual(decoded.dualModeForeground, fg))
        XCTAssertFalse(decoded.dualModeBackground.valid.boolValue)
    }

    func testDictionaryRoundTripDualModeUnderlineRGB() {
        let uc = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                         hasDarkVariant: true, redDark: 44, greenDark: 55, blueDark: 66)
        guard let ea = makeAttribute(hasUC: true, uc: uc) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute(dictionary: ea.dictionaryValue) else {
            XCTFail(); return
        }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 11)
        XCTAssertTrue(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(decoded.underlineColor.redDark, 44)
        XCTAssertEqual(decoded.underlineColor.greenDark, 55)
        XCTAssertEqual(decoded.underlineColor.blueDark, 66)
    }

    func testDictionaryRoundTripDualModeUnderlineIndexed() {
        let uc = VT100TerminalColorValue(red: 208, green: 0, blue: 0, mode: ColorModeNormal,
                                         hasDarkVariant: true, redDark: 120, greenDark: 0, blueDark: 0)
        guard let ea = makeAttribute(hasUC: true, uc: uc) else { XCTFail(); return }
        guard let decoded = iTermExternalAttribute(dictionary: ea.dictionaryValue) else {
            XCTFail(); return
        }
        XCTAssertTrue(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(decoded.underlineColor.red, 208)
        XCTAssertEqual(decoded.underlineColor.redDark, 120)
        XCTAssertEqual(decoded.underlineColor.mode, ColorModeNormal)
    }

    // A pre-dual-mode dict (no "dmf"/"dmb" keys) decodes correctly.
    func testDictionaryDecodesPreDualMode() {
        let dict: [String: Any] = [
            "uc": [Int(ColorMode24bit.rawValue), 11, 22, 33],
            "b": "block-2",
            "cc": 5,
        ]
        guard let decoded = iTermExternalAttribute(dictionary: dict) else {
            XCTFail("expected pre-dual-mode dict to decode"); return
        }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 11)
        XCTAssertFalse(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(decoded.blockIDList, "block-2")
        XCTAssertEqual(decoded.controlCodeNumber, 5)
        XCTAssertFalse(decoded.dualModeForeground.valid.boolValue)
        XCTAssertFalse(decoded.dualModeBackground.valid.boolValue)
    }

    // Old-form 4-element underline arrays must continue to decode without
    // claiming a dark variant, alongside the new 7-element form.
    func testDictionaryDecodesPreDualUnderlineArray() {
        let dict: [String: Any] = [
            "uc": [Int(ColorMode24bit.rawValue), 11, 22, 33],  // 4-element legacy form
        ]
        guard let decoded = iTermExternalAttribute(dictionary: dict) else {
            XCTFail("expected legacy underline dict to decode"); return
        }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 11)
        XCTAssertEqual(decoded.underlineColor.green, 22)
        XCTAssertEqual(decoded.underlineColor.blue, 33)
        XCTAssertFalse(decoded.underlineColor.hasDarkVariant.boolValue)
    }

    // A new EA constructed with a dark-variant underline color, then
    // round-tripped through a 4-element legacy dict, must come back
    // single-color — the legacy decoder path must NOT preserve stale dark
    // variant state. Pins the defensive clear in iTermDecodeColorValueArray.
    func testDictionaryLegacyArrayClearsDarkVariantState() {
        let withDark = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                               hasDarkVariant: true, redDark: 44, greenDark: 55, blueDark: 66)
        guard let ea = makeAttribute(hasUC: true, uc: withDark) else { XCTFail(); return }
        // Build a dict that uses the legacy 4-element form (simulating data
        // from a version of iTerm2 without dual underline).
        var dict = ea.dictionaryValue
        dict["uc"] = [Int(ColorMode24bit.rawValue), 11, 22, 33]
        guard let decoded = iTermExternalAttribute(dictionary: dict) else {
            XCTFail(); return
        }
        XCTAssertTrue(decoded.hasUnderlineColor)
        XCTAssertEqual(decoded.underlineColor.red, 11)
        XCTAssertFalse(decoded.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(decoded.underlineColor.redDark, 0)
        XCTAssertEqual(decoded.underlineColor.greenDark, 0)
        XCTAssertEqual(decoded.underlineColor.blueDark, 0)
    }

    func testDictionaryEmptyReturnsNil() {
        XCTAssertNil(iTermExternalAttribute(dictionary: [:]))
    }
}

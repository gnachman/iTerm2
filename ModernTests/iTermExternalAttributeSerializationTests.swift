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
        XCTAssertFalse(decoded.dualModeForeground.valid.boolValue)
        XCTAssertFalse(decoded.dualModeBackground.valid.boolValue)
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
        XCTAssertEqual(decoded.blockIDList, "block-2")
        XCTAssertEqual(decoded.controlCodeNumber, 5)
        XCTAssertFalse(decoded.dualModeForeground.valid.boolValue)
        XCTAssertFalse(decoded.dualModeBackground.valid.boolValue)
    }

    func testDictionaryEmptyReturnsNil() {
        XCTAssertNil(iTermExternalAttribute(dictionary: [:]))
    }
}

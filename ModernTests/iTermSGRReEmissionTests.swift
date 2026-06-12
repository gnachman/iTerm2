//
//  iTermSGRReEmissionTests.swift
//  ModernTests
//
//  Tests for +[VT100Terminal sgrCodesForCharacter:externalAttributes:],
//  specifically dual-mode underline color re-emission (SGR 58:12 / 58:13).
//

import XCTest
@testable import iTerm2SharedARC

final class iTermSGRReEmissionTests: XCTestCase {

    private func emptyChar() -> screen_char_t {
        return screen_char_t()
    }

    private func makeUnderlineEA(_ uc: VT100TerminalColorValue) -> iTermExternalAttribute {
        return iTermExternalAttribute(havingUnderlineColor: true,
                                      underlineColor: uc,
                                      url: nil,
                                      blockIDList: nil,
                                      controlCode: nil,
                                      dualModeForeground: iTermDualModeColor(),
                                      dualModeBackground: iTermDualModeColor())!
    }

    // The class method is declared without nonnull annotations in Obj-C, so
    // Swift bridges the return as Optional. Unwrap it for the assertion site.
    private func codes(for ea: iTermExternalAttribute) -> NSOrderedSet {
        guard let result = VT100Terminal.sgrCodes(forCharacter: emptyChar(),
                                                  externalAttributes: ea) else {
            XCTFail("expected non-nil SGR code set"); return NSOrderedSet()
        }
        return result
    }

    private func anyHasPrefix(_ codes: NSOrderedSet, _ prefix: String) -> Bool {
        for obj in codes {
            if let s = obj as? String, s.hasPrefix(prefix) { return true }
        }
        return false
    }

    // SGR 58 single-color path — the existing fallback emission must not regress.
    func testSGRSingleUnderlineRGBEmits58_2() {
        let uc = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        let result = codes(for: makeUnderlineEA(uc))
        XCTAssertTrue(result.contains("58:2:11:22:33"))
        XCTAssertFalse(anyHasPrefix(result, "58:12"))
    }

    func testSGRSingleUnderlineIndexedEmits58_5() {
        let uc = VT100TerminalColorValue(red: 208, green: 0, blue: 0, mode: ColorModeNormal,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        let result = codes(for: makeUnderlineEA(uc))
        XCTAssertTrue(result.contains("58:5:208"))
        XCTAssertFalse(anyHasPrefix(result, "58:13"))
    }

    // Dual-mode RGB underline must emit BOTH the universal-fallback 58:2 and a
    // chained 58:12. Order matters: fallback first so non-supporting parsers
    // land on a usable color, then dual-mode-aware parsers pick up the override.
    func testSGRDualUnderlineRGBEmitsFallbackAndChained() {
        let uc = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                         hasDarkVariant: true, redDark: 44, greenDark: 55, blueDark: 66)
        let result = codes(for: makeUnderlineEA(uc))
        XCTAssertTrue(result.contains("58:2:11:22:33"))
        XCTAssertTrue(result.contains("58:12:11:22:33:44:55:66"))
    }

    func testSGRDualUnderlineIndexedEmitsFallbackAndChained() {
        let uc = VT100TerminalColorValue(red: 208, green: 0, blue: 0, mode: ColorModeNormal,
                                         hasDarkVariant: true, redDark: 120, greenDark: 0, blueDark: 0)
        let result = codes(for: makeUnderlineEA(uc))
        XCTAssertTrue(result.contains("58:5:208"))
        XCTAssertTrue(result.contains("58:13:208:120"))
    }
}

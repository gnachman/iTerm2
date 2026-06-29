//
//  iTermGraphicRenditionRoundTripTests.swift
//  ModernTests
//
//  Round-trip tests for VT100GraphicRendition through the dictionary form
//  used by DECSC/DECRC saved cursors and stateDictionary state restoration.
//
//  These pin that dual-mode foreground, background, and underline color all
//  survive save/restore — without these tests the dark variants are silently
//  dropped and a restored cursor decays to single-color SGR.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermGraphicRenditionRoundTripTests: XCTestCase {

    private func roundTrip(_ rendition: VT100GraphicRendition) -> VT100GraphicRendition {
        guard let dict = VT100Terminal.dictionary(for: rendition) else {
            XCTFail("expected dict"); return VT100GraphicRendition()
        }
        return VT100Terminal.graphicRendition(from: dict)
    }

    func testDualModeFgRoundTrip() {
        var r = VT100GraphicRendition()
        r.fgColorCode = 11; r.fgGreen = 22; r.fgBlue = 33; r.fgColorMode = ColorMode24bit
        r.hasDualModeFg = true
        r.fgDarkColorCode = 44; r.fgDarkGreen = 55; r.fgDarkBlue = 66; r.fgDarkColorMode = ColorMode24bit

        let restored = roundTrip(r)
        XCTAssertTrue(restored.hasDualModeFg.boolValue)
        XCTAssertEqual(restored.fgDarkColorCode, 44)
        XCTAssertEqual(restored.fgDarkGreen, 55)
        XCTAssertEqual(restored.fgDarkBlue, 66)
        XCTAssertEqual(restored.fgDarkColorMode, ColorMode24bit)
    }

    func testDualModeBgRoundTrip() {
        var r = VT100GraphicRendition()
        r.bgColorCode = 200; r.bgGreen = 0; r.bgBlue = 0; r.bgColorMode = ColorModeNormal
        r.hasDualModeBg = true
        r.bgDarkColorCode = 16; r.bgDarkColorMode = ColorModeNormal

        let restored = roundTrip(r)
        XCTAssertTrue(restored.hasDualModeBg.boolValue)
        XCTAssertEqual(restored.bgDarkColorCode, 16)
        XCTAssertEqual(restored.bgDarkColorMode, ColorModeNormal)
    }

    func testDualModeUnderlineRoundTrip() {
        var r = VT100GraphicRendition()
        r.hasUnderlineColor = true
        r.underlineColor = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                                    hasDarkVariant: true, redDark: 44, greenDark: 55, blueDark: 66)

        let restored = roundTrip(r)
        XCTAssertTrue(restored.hasUnderlineColor.boolValue)
        XCTAssertTrue(restored.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(restored.underlineColor.redDark, 44)
        XCTAssertEqual(restored.underlineColor.greenDark, 55)
        XCTAssertEqual(restored.underlineColor.blueDark, 66)
    }

    // A pre-dual-mode dictionary (no dual-mode keys) must restore to a
    // single-color rendition without any phantom dark variants. Pins
    // backward compatibility for state files written by older iTerm2.
    func testPreDualModeDictRestoresAsSingleColor() {
        // Mirror a dict written by code that knew nothing about dual mode.
        let dict: [String: Any] = [
            "Bold": false, "Blink": false, "Invisible": false,
            "Underline": false, "Strikethrough": false, "Underline Style": 0,
            "Reversed": false, "Faint": false, "Italic": false,
            "FG Color/Red": 11, "FG Green": 22, "FG Blue": 33, "FG Mode": Int(ColorMode24bit.rawValue),
            "BG Color/Red": 0, "BG Green": 0, "BG Blue": 0, "BG Mode": Int(ColorModeAlternate.rawValue),
            "Has underline color": true,
            "Underline Color/Red": 99, "Underline Green": 0, "Underline Blue": 0,
            "Underline Mode": Int(ColorModeNormal.rawValue),
        ]
        let restored = VT100Terminal.graphicRendition(from: dict)
        XCTAssertFalse(restored.hasDualModeFg.boolValue)
        XCTAssertFalse(restored.hasDualModeBg.boolValue)
        XCTAssertTrue(restored.hasUnderlineColor.boolValue)
        XCTAssertFalse(restored.underlineColor.hasDarkVariant.boolValue)
        XCTAssertEqual(restored.underlineColor.redDark, 0)
        XCTAssertEqual(restored.underlineColor.greenDark, 0)
        XCTAssertEqual(restored.underlineColor.blueDark, 0)
    }

    // No dual-mode state should leak into the dict when the rendition has
    // none. Future readers must observe identical-shape output to what
    // pre-dual-mode iTerm2 wrote (modulo new keys having NSNull / absence).
    func testSingleColorRenditionEncodesWithoutDualKeys() {
        var r = VT100GraphicRendition()
        r.fgColorCode = 11; r.fgGreen = 22; r.fgBlue = 33; r.fgColorMode = ColorMode24bit
        r.bgColorMode = ColorModeAlternate

        guard let dict = VT100Terminal.dictionary(for: r) else { XCTFail(); return }
        // The "has dual" flags must not claim a dual-mode value — either
        // absent or false. This protects against future readers seeing
        // hasDualModeFg=YES with stale fgDark* fields.
        if let fg = dict["Has Dual Mode FG"] as? NSNumber {
            XCTAssertFalse(fg.boolValue)
        }
        if let bg = dict["Has Dual Mode BG"] as? NSNumber {
            XCTAssertFalse(bg.boolValue)
        }
        if let ul = dict["Has Dark Underline"] as? NSNumber {
            XCTAssertFalse(ul.boolValue)
        }
    }
}

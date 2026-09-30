//
//  PTYSessionProtoStyleAndTabColorTests.swift
//  iTerm2 ModernTests
//
//  Ported from PTYSessionTest.m: the per-appearance tab color lookups in
//  iTermProfilePreferences, and +[PTYSession protoStyleForCharacter:externalAttributes:] for
//  cells whose color is dual-mode (ColorModeExternal). The paste tests from that file are not
//  here because they need to replace the session's private paste helper.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionProtoStyleAndTabColorTests: XCTestCase {
    private let lightTabColorKey = KEY_TAB_COLOR + COLORS_LIGHT_MODE_SUFFIX
    private let darkTabColorKey = KEY_TAB_COLOR + COLORS_DARK_MODE_SUFFIX
    private let lightUseTabColorKey = KEY_USE_TAB_COLOR + COLORS_LIGHT_MODE_SUFFIX
    private let darkUseTabColorKey = KEY_USE_TAB_COLOR + COLORS_DARK_MODE_SUFFIX

    // MARK: - Helpers

    private func encodedColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSDictionary? {
        let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
        return ITAddressBookMgr.encode(color) as NSDictionary?
    }

    private func tabColor(dark: Bool, profile: [String: Any]) -> NSDictionary? {
        return iTermProfilePreferences.object(forTabColorKey: KEY_TAB_COLOR, dark: dark, profile: profile) as? NSDictionary
    }

    private func usesTabColor(dark: Bool, profile: [String: Any]) -> Bool {
        return iTermProfilePreferences.bool(forTabColorKey: KEY_USE_TAB_COLOR, dark: dark, profile: profile)
    }

    private func colorValue(red: Int32 = 0, green: Int32 = 0, blue: Int32 = 0, mode: ColorMode) -> VT100TerminalColorValue {
        return VT100TerminalColorValue(red: red, green: green, blue: blue, mode: mode,
                                       hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
    }

    private func dualModeColor(light: VT100TerminalColorValue, dark: VT100TerminalColorValue) -> iTermDualModeColor {
        return iTermDualModeColor(valid: true, light: light, dark: dark)
    }

    private func externalAttribute(dualModeForeground: iTermDualModeColor = iTermDualModeColor(),
                                   dualModeBackground: iTermDualModeColor = iTermDualModeColor(),
                                   file: StaticString = #filePath,
                                   line: UInt = #line) -> iTermExternalAttribute? {
        let ea = iTermExternalAttribute(havingUnderlineColor: false,
                                        underlineColor: VT100TerminalColorValue(),
                                        url: nil,
                                        blockIDList: nil,
                                        controlCode: nil,
                                        dualModeForeground: dualModeForeground,
                                        dualModeBackground: dualModeBackground)
        XCTAssertNotNil(ea, "Expected an external attribute", file: file, line: line)
        return ea
    }

    /// An external attribute that carries something other than dual-mode colors (an underline
    /// color), so its dual-mode colors are invalid. The proto path treats that the same as a
    /// missing attribute: -dualModeForeground.valid is NO either way.
    private func attributeWithoutDualModeColors(file: StaticString = #filePath,
                                                line: UInt = #line) -> iTermExternalAttribute? {
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: colorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit),
                                        url: nil,
                                        blockIDList: nil,
                                        controlCode: nil,
                                        dualModeForeground: iTermDualModeColor(),
                                        dualModeBackground: iTermDualModeColor())
        XCTAssertNotNil(ea, "Expected an external attribute", file: file, line: line)
        return ea
    }

    // MARK: - Tab color per appearance

    func testTabColorFallsBackToOppositeMode() throws {
        let lightColor = try XCTUnwrap(encodedColor(red: 1, green: 0.25, blue: 0))
        let profile: [String: Any] = [
            KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: true,
            lightUseTabColorKey: true,
            lightTabColorKey: lightColor,
        ]

        XCTAssertTrue(usesTabColor(dark: true, profile: profile))
        XCTAssertEqual(tabColor(dark: true, profile: profile), lightColor)
    }

    func testTabColorPrefersCurrentModeWhenExplicitlySet() throws {
        let lightColor = try XCTUnwrap(encodedColor(red: 1, green: 0.25, blue: 0))
        let darkColor = try XCTUnwrap(encodedColor(red: 0.1, green: 0.2, blue: 0.9))
        let profile: [String: Any] = [
            KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: true,
            lightUseTabColorKey: true,
            lightTabColorKey: lightColor,
            darkUseTabColorKey: true,
            darkTabColorKey: darkColor,
        ]

        XCTAssertTrue(usesTabColor(dark: true, profile: profile))
        XCTAssertEqual(tabColor(dark: true, profile: profile), darkColor)
    }

    func testTabColorFallsBackToSharedKey() throws {
        let sharedColor = try XCTUnwrap(encodedColor(red: 0.4, green: 0.8, blue: 0.2))
        let profile: [String: Any] = [
            KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: true,
            KEY_USE_TAB_COLOR: true,
            KEY_TAB_COLOR: sharedColor,
        ]

        XCTAssertTrue(usesTabColor(dark: true, profile: profile))
        XCTAssertEqual(tabColor(dark: true, profile: profile), sharedColor)
    }

    func testTabColorDoesNotFallBackPastExplicitDisabledMode() throws {
        let lightColor = try XCTUnwrap(encodedColor(red: 1, green: 0.25, blue: 0))
        let profile: [String: Any] = [
            KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: true,
            lightUseTabColorKey: true,
            lightTabColorKey: lightColor,
            darkUseTabColorKey: false,
        ]

        XCTAssertFalse(usesTabColor(dark: true, profile: profile))
    }

    // MARK: - Dual-mode SGR proto reporting

    // Regression test: a cell with ColorModeExternal whose light variant is indexed (via
    // CSI 38:13:Nl:Nd m) carries the palette index in foregroundColor with fgGreen/fgBlue = 0.
    // Reporting it as RGB(N,0,0) was wrong; the proto API must emit fgStandard=N from the
    // external attribute's light variant.
    func testProtoStyleForDualModeIndexedForeground() throws {
        var c = screen_char_t()
        c.foregroundColor = 208  // palette index Nl
        c.foregroundColorMode = ColorModeExternal.rawValue
        c.backgroundColorMode = ColorModeAlternate.rawValue

        let dual = dualModeColor(light: colorValue(red: 208, mode: ColorModeNormal),
                                 dark: colorValue(red: 33, mode: ColorModeNormal))
        let ea = try XCTUnwrap(externalAttribute(dualModeForeground: dual))

        let style = PTYSession.protoStyle(forCharacter: c, externalAttributes: ea)

        XCTAssertEqual(style.fgColorOneOfCase, .fgStandard)
        XCTAssertEqual(style.fgStandard, 208)
    }

    // Companion: a cell with ColorModeExternal whose light variant is 24-bit RGB (via
    // CSI 38:12:Rl:Gl:Bl:Rd:Gd:Bd m) should report the light RGB.
    func testProtoStyleForDualModeRGBForeground() throws {
        var c = screen_char_t()
        c.foregroundColor = 17  // light R
        c.fgGreen = 133  // light G
        c.fgBlue = 177  // light B
        c.foregroundColorMode = ColorModeExternal.rawValue
        c.backgroundColorMode = ColorModeAlternate.rawValue

        let dual = dualModeColor(light: colorValue(red: 17, green: 133, blue: 177, mode: ColorMode24bit),
                                 dark: colorValue(red: 200, green: 200, blue: 255, mode: ColorMode24bit))
        let ea = try XCTUnwrap(externalAttribute(dualModeForeground: dual))

        let style = PTYSession.protoStyle(forCharacter: c, externalAttributes: ea)

        XCTAssertEqual(style.fgColorOneOfCase, .fgRgb)
        XCTAssertEqual(style.fgRgb.red, 17)
        XCTAssertEqual(style.fgRgb.green, 133)
        XCTAssertEqual(style.fgRgb.blue, 177)
    }

    // Regression: an External cell whose external attribute has no valid dual-mode color
    // (e.g. corrupted state) must fall back to the cell's stored RGB rather than reporting
    // black. The legacy test passed nil for the attribute; the nil and invalid cases share the
    // same path.
    func testProtoStyleForDualModeInvalidEAFallsBackToCellBytesForForeground() throws {
        var c = screen_char_t()
        c.foregroundColor = 17
        c.fgGreen = 133
        c.fgBlue = 177
        c.foregroundColorMode = ColorModeExternal.rawValue
        c.backgroundColorMode = ColorModeAlternate.rawValue

        let ea = try XCTUnwrap(attributeWithoutDualModeColors())
        let style = PTYSession.protoStyle(forCharacter: c, externalAttributes: ea)

        XCTAssertEqual(style.fgColorOneOfCase, .fgRgb)
        XCTAssertEqual(style.fgRgb.red, 17)
        XCTAssertEqual(style.fgRgb.green, 133)
        XCTAssertEqual(style.fgRgb.blue, 177)
    }

    func testProtoStyleForDualModeInvalidEAFallsBackToCellBytesForBackground() throws {
        var c = screen_char_t()
        c.foregroundColorMode = ColorModeAlternate.rawValue
        c.backgroundColor = 99
        c.bgGreen = 88
        c.bgBlue = 77
        c.backgroundColorMode = ColorModeExternal.rawValue

        let ea = try XCTUnwrap(attributeWithoutDualModeColors())
        let style = PTYSession.protoStyle(forCharacter: c, externalAttributes: ea)

        XCTAssertEqual(style.bgColorOneOfCase, .bgRgb)
        XCTAssertEqual(style.bgRgb.red, 99)
        XCTAssertEqual(style.bgRgb.green, 88)
        XCTAssertEqual(style.bgRgb.blue, 77)
    }

    func testProtoStyleForDualModeIndexedBackground() throws {
        var c = screen_char_t()
        c.foregroundColorMode = ColorModeAlternate.rawValue
        c.backgroundColor = 33
        c.backgroundColorMode = ColorModeExternal.rawValue

        let dual = dualModeColor(light: colorValue(red: 33, mode: ColorModeNormal),
                                 dark: colorValue(red: 17, mode: ColorModeNormal))
        let ea = try XCTUnwrap(externalAttribute(dualModeBackground: dual))

        let style = PTYSession.protoStyle(forCharacter: c, externalAttributes: ea)

        XCTAssertEqual(style.bgColorOneOfCase, .bgStandard)
        XCTAssertEqual(style.bgStandard, 33)
    }
}

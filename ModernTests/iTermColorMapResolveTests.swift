//
//  iTermColorMapResolveTests.swift
//  ModernTests
//
//  Tests for iTermColorMap.resolvedColorValue: and resolvedDualModeColor:.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermColorMapResolveTests: XCTestCase {

    private func makeMap(backgroundIsDark: Bool) -> iTermColorMap {
        let map = iTermColorMap()
        // setColor:forKey: with kColorMapBackground updates _backgroundBrightness
        // from the color's perceivedBrightness. Pick saturated black or white
        // for an unambiguous threshold (perceivedBrightness uses BT.709).
        let bg = backgroundIsDark ? NSColor.black : NSColor.white
        map.setColor(bg, forKey: Int32(kColorMapBackground))
        return map
    }

    func testResolvedColorValuePassesThroughWhenNoDarkVariant() {
        let map = makeMap(backgroundIsDark: false)
        let v = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                        hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        let r = map.resolvedColorValue(v)
        XCTAssertFalse(r.hasDarkVariant.boolValue)
        XCTAssertEqual(r.red, 11)
        XCTAssertEqual(r.green, 22)
        XCTAssertEqual(r.blue, 33)
    }

    func testResolvedColorValuePicksLightOnLightBackground() {
        let map = makeMap(backgroundIsDark: false)
        let v = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                        hasDarkVariant: true, redDark: 44, greenDark: 55, blueDark: 66)
        let r = map.resolvedColorValue(v)
        XCTAssertFalse(r.hasDarkVariant.boolValue)
        XCTAssertEqual(r.red, 11)
        XCTAssertEqual(r.green, 22)
        XCTAssertEqual(r.blue, 33)
    }

    func testResolvedColorValuePicksDarkOnDarkBackground() {
        let map = makeMap(backgroundIsDark: true)
        let v = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                        hasDarkVariant: true, redDark: 44, greenDark: 55, blueDark: 66)
        let r = map.resolvedColorValue(v)
        XCTAssertFalse(r.hasDarkVariant.boolValue)
        XCTAssertEqual(r.red, 44)
        XCTAssertEqual(r.green, 55)
        XCTAssertEqual(r.blue, 66)
    }

    // The 24-bit fast path in fastColorForKey:colorSpace: must be bit-identical to
    // the full colorUsingColorSpace: conversion when the target space is the app's
    // native 8-bit space, since it skips that conversion.
    func test24BitFastPathMatchesConversionInNativeSpace() {
        let map = iTermColorMap()
        let native: NSColorSpace = iTermAdvancedSettingsModel.p3() ? .displayP3 : .sRGB
        let red: Int32 = 200, green: Int32 = 100, blue: Int32 = 50
        let key = iTermColorMap.keyFor8bitRed(red, green: green, blue: blue)

        let fast = map.fastColor(forKey: key, colorSpace: native)

        guard let color = NSColor(red, green: green, blue: blue)
            .usingColorSpace(native) else {
            XCTFail("reference conversion failed")
            return
        }
        XCTAssertEqual(fast.x, Float(color.redComponent), accuracy: 1e-5, "red")
        XCTAssertEqual(fast.y, Float(color.greenComponent), accuracy: 1e-5, "green")
        XCTAssertEqual(fast.z, Float(color.blueComponent), accuracy: 1e-5, "blue")
        XCTAssertEqual(fast.w, 1, accuracy: 1e-5, "alpha")
    }

    // The mode field must survive resolution — both light and dark share it.
    func testResolvedColorValuePreservesMode() {
        let map = makeMap(backgroundIsDark: true)
        let v = VT100TerminalColorValue(red: 7, green: 0, blue: 0, mode: ColorModeNormal,
                                        hasDarkVariant: true, redDark: 9, greenDark: 0, blueDark: 0)
        let r = map.resolvedColorValue(v)
        XCTAssertEqual(r.mode, ColorModeNormal)
        XCTAssertEqual(r.red, 9)
    }
}

// -[iTermColorMap savedColorsSlot], which XTPUSHCOLORS pushes and which SSH Integration saves as
// the terminal's state when a conductor hooks, for a map that has the four colors and for one that
// lacks one of them (a profile whose color value is not a color dictionary leaves its key unset).
final class iTermColorMapSavedColorsSlotTests: XCTestCase {
    private let colors: [(key: Int32, color: NSColor)] = [
        (kColorMapForeground, NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
        (kColorMapBackground, NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
        (kColorMapSelectedText, NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),
        (kColorMapSelection, NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)),
    ]

    private func makeMap(lacking missing: Int32? = nil) -> iTermColorMap {
        let map = iTermColorMap()
        for (key, color) in colors where key != missing {
            map.setColor(color, forKey: key)
        }
        return map
    }

    /// The slot's four colors, keyed like the map. Read into optionals, which see a nil class
    /// reference as nil whatever the declared type.
    private func slotColors(_ slot: SavedColorsSlot) -> [Int32: NSColor?] {
        let text: NSColor? = slot.text
        let background: NSColor? = slot.background
        let selectionText: NSColor? = slot.selectionText
        let selectionBackground: NSColor? = slot.selectionBackground
        return [kColorMapForeground: text,
                kColorMapBackground: background,
                kColorMapSelectedText: selectionText,
                kColorMapSelection: selectionBackground]
    }

    func testASlotOfAMapWithItsFourColorsHoldsThemAndRoundTrips() throws {
        let map = makeMap()
        let slot = try XCTUnwrap(map.savedColorsSlot())
        let decoded = try XCTUnwrap(SavedColorsSlot.from(data: try XCTUnwrap(slot.plist)))
        for (key, _) in colors {
            let expected = map.color(forKey: key)
            XCTAssertEqual(slotColors(slot)[key] ?? nil, expected, "key \(key)")
            XCTAssertEqual((slotColors(decoded)[key] ?? nil)?.hexString(), expected?.hexString(), "key \(key)")
        }
    }

    func testASlotOfAMapLackingAColorHasNoneForIt() throws {
        for (missing, _) in colors {
            let slot = try XCTUnwrap(makeMap(lacking: missing).savedColorsSlot())
            for (key, _) in colors {
                let color = slotColors(slot)[key] ?? nil
                if key == missing {
                    XCTAssertNil(color, "missing \(missing)")
                } else {
                    XCTAssertNotNil(color, "missing \(missing), key \(key)")
                }
            }
        }
    }

    // A missing color is written as CodableColor's fallback form holding a keyed archive with
    // nothing in it, which does not decode, so the whole slot fails to decode: SSH Integration
    // then restores none of the saved indexed colors when the conductor ends.
    func testASlotLackingAColorIsWrittenAsAnEmptyArchiveAndDoesNotDecode() throws {
        let emptyArchive = NSKeyedArchiver(requiringSecureCoding: true).encodedData
        let fields = ["_text", "_background", "_selectionText", "_selectionBackground"]
        for ((missing, _), field) in zip(colors, fields) {
            let slot = try XCTUnwrap(makeMap(lacking: missing).savedColorsSlot())
            let data = try XCTUnwrap(slot.plist, "missing \(missing)")
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let written = try XCTUnwrap(plist[field] as? [String: Any], "missing \(missing)")
            XCTAssertEqual(written as NSDictionary, ["fallback": emptyArchive] as NSDictionary, "missing \(missing)")
            for other in fields where other != field {
                XCTAssertEqual((plist[other] as? [String: Any])?.keys.sorted(), ["hexString"], "missing \(missing), \(other)")
            }
            XCTAssertNil(SavedColorsSlot.from(data: data), "missing \(missing)")
        }
    }

    // XTPUSHCOLORS's stack is saved with the terminal's state. One such slot in it makes the whole
    // stack fail to decode, so a restored session's stack is empty.
    func testAStackHoldingASlotLackingAColorDoesNotDecode() throws {
        let stack = SavedColors()
        stack.push(try XCTUnwrap(makeMap().savedColorsSlot()))
        XCTAssertNotNil(SavedColors.from(data: try XCTUnwrap(stack.plist)))
        stack.push(try XCTUnwrap(makeMap(lacking: kColorMapSelection).savedColorsSlot()))
        XCTAssertNil(SavedColors.from(data: try XCTUnwrap(stack.plist)))
    }
}

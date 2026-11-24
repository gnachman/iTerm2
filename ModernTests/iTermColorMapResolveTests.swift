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
    // nothing in it. It decodes as a missing color, and the rest of the slot still decodes.
    func testASlotLackingAColorIsWrittenAsAnEmptyArchiveAndDecodesWithoutIt() throws {
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
            let decoded = try XCTUnwrap(SavedColorsSlot.from(data: data), "missing \(missing)")
            for (key, _) in colors {
                let color = slotColors(decoded)[key] ?? nil
                if key == missing {
                    XCTAssertNil(color, "missing \(missing)")
                } else {
                    XCTAssertNotNil(color, "missing \(missing), key \(key)")
                }
            }
            XCTAssertEqual(decoded.indexedColors.count, slot.indexedColors.count, "missing \(missing)")
        }
    }

    // XTPUSHCOLORS's stack is saved with the terminal's state. A slot lacking a color must not
    // stop the stack from decoding, or a restored session's stack comes back empty.
    func testAStackHoldingASlotLackingAColorDecodes() throws {
        let stack = SavedColors()
        stack.push(try XCTUnwrap(makeMap().savedColorsSlot()))
        XCTAssertNotNil(SavedColors.from(data: try XCTUnwrap(stack.plist)))
        stack.push(try XCTUnwrap(makeMap(lacking: kColorMapSelection).savedColorsSlot()))
        let decoded = try XCTUnwrap(SavedColors.from(data: try XCTUnwrap(stack.plist)))
        XCTAssertEqual(decoded.used, 2)
    }
}

// The two places a saved colors slot is read back, driven through the real code: SSH Integration's
// conductor ending, and a restored session's XTPUSHCOLORS stack. In both, the screen's color map
// lacks one of the four colors (as when a profile's value for it is not a color dictionary).
final class SavedColorsSlotMissingColorRestoreTests: XCTestCase {
    private let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    // XTPOPCOLORS restores indexed colors 16 and up through the color map; 0-15 go through the
    // profile (screenRestoreColorsFromSlot:), so use one above 15.
    private let indexedKey = kColorMap8bitBase + 20

    private func feed(_ harness: TerminalTestHarness, _ string: String) {
        harness.send(Array(string.utf8))
        harness.sync()
    }

    /// Gives the map three of the four colors (no selection color) and sets the indexed color.
    private func setColorsLackingSelection(_ harness: TerminalTestHarness, indexed: NSColor) {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setColor(self.red, forKey: Int32(kColorMapForeground))
            mutableState.setColor(self.blue, forKey: Int32(kColorMapBackground))
            mutableState.setColor(self.red, forKey: Int32(kColorMapSelectedText))
            // NSNull removes the key, as setColorsFromDictionary: does for the app.
            mutableState.setColorsFrom([NSNumber(value: kColorMapSelection): NSNull()],
                                       harmonize: false)
            mutableState.setColor(indexed, forKey: Int32(self.indexedKey))
        })
        harness.sync()
    }

    private func setIndexed(_ harness: TerminalTestHarness, _ color: NSColor) {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setColor(color, forKey: Int32(self.indexedKey))
        })
        harness.sync()
    }

    private func indexedHex(_ harness: TerminalTestHarness) -> String? {
        var hex: String?
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            hex = mutableState.colorMap.color(forKey: self.indexedKey)?.hexString()
        })
        return hex
    }

    // SSH Integration saves the terminal's state when a conductor hooks and puts it back when the
    // conductor ends. The saved colors must come back even though the map lacked one color.
    func testSSHIntegrationRestoresSavedColorsWhenTheMapLackedAColor() throws {
        let harness = TerminalTestHarness()
        setColorsLackingSelection(harness, indexed: red)
        var saved: [AnyHashable: Any]?
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            saved = mutableState.savedState() as? [AnyHashable: Any]
        })
        let savedState = try XCTUnwrap(saved)

        setIndexed(harness, blue)
        XCTAssertEqual(indexedHex(harness), blue.hexString())

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.restore(fromSavedState: savedState)
        })
        harness.sync()
        XCTAssertEqual(indexedHex(harness), red.hexString(),
                       "the conductor ending must restore the saved indexed color")
    }

    // XTPUSHCOLORS's stack is saved with the terminal's state. After a restore, XTPOPCOLORS must
    // still find the pushed slot even though the map lacked one color when it was pushed.
    func testRestoredSessionKeepsXTPUSHCOLORSStackWhenTheMapLackedAColor() throws {
        let source = TerminalTestHarness()
        setColorsLackingSelection(source, indexed: red)
        feed(source, "\u{1b}[#P")
        var state: [AnyHashable: Any]?
        source.screen.performBlock(joinedThreads: { terminal, _, _ in
            state = terminal?.stateDictionary as? [AnyHashable: Any]
        })
        let stateDictionary = try XCTUnwrap(state)

        let destination = TerminalTestHarness()
        destination.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.setStateFrom(stateDictionary)
        })
        destination.sync()
        setIndexed(destination, blue)

        feed(destination, "\u{1b}[#Q")
        XCTAssertEqual(indexedHex(destination), red.hexString(),
                       "XTPOPCOLORS after a restore must pop the slot pushed before it")
    }
}

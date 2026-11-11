//
//  iTermTabGroupColorChooserTests.swift
//  iTerm2XCTests
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabGroupColorChooserTests: XCTestCase {
    private func index(inUse: Set<Int>, parent: Int? = nil, count: Int, palette: Int = 7) -> Int {
        return iTermTabGroupColorChooser.index(paletteCount: palette,
                                               inUse: inUse,
                                               parentIndex: parent,
                                               groupCount: count)
    }

    func testFirstGroupGetsFirstColor() {
        XCTAssertEqual(index(inUse: [], count: 0), 0)
    }

    func testSkipsColorsInUse() {
        XCTAssertEqual(index(inUse: [0, 1], count: 2), 2)
    }

    func testReusesColorFreedByClosedGroup() {
        // Blue (0) was closed; green (1) remains. Cycling by count would pick
        // green again.
        XCTAssertEqual(index(inUse: [1], count: 1), 0)
    }

    func testSubgroupAvoidsParentColor() {
        // The parent is the only group and has blue.
        XCTAssertEqual(index(inUse: [0], parent: 0, count: 1), 1)
    }

    func testSubgroupAvoidsParentColorWhenPaletteExhausted() {
        // Every color is taken and cycling lands on the parent's color.
        XCTAssertEqual(index(inUse: Set(0..<7), parent: 3, count: 10), 4)
    }

    func testCyclesWhenPaletteExhausted() {
        XCTAssertEqual(index(inUse: Set(0..<7), count: 9), 2)
    }

    func testSingleEntryPaletteStillReturnsIt() {
        XCTAssertEqual(index(inUse: [0], parent: 0, count: 1, palette: 1), 0)
    }

    func testMatchesColorsAcrossColorSpaces() {
        let palette = [NSColor.systemBlue, NSColor.systemGreen, NSColor.systemOrange]
        // Stored group colors are converted out of the catalog color space.
        let blue = NSColor.systemBlue.usingColorSpace(.displayP3)!
        let green = NSColor.systemGreen.usingColorSpace(.sRGB)!
        let chosen = iTermTabGroupColorChooser.color(palette: palette,
                                                     inUseColors: [blue, green],
                                                     parentColor: blue,
                                                     groupCount: 2)
        XCTAssertEqual(chosen, NSColor.systemOrange)
    }

    // A group colored in dark appearance must still count as using its palette
    // entry after switching to light, and the other way around.
    func testMatchesColorsFrozenInEitherAppearance() {
        let lightBlue = NSColor(srgbRed: 0, green: 122 / 255.0, blue: 1, alpha: 1)
        let darkBlue = NSColor(srgbRed: 10 / 255.0, green: 132 / 255.0, blue: 1, alpha: 1)
        let blue = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkBlue : lightBlue
        }
        let palette = [blue, NSColor.systemGreen, NSColor.systemOrange]
        for frozen in [lightBlue, darkBlue] {
            let chosen = iTermTabGroupColorChooser.color(palette: palette,
                                                         inUseColors: [frozen],
                                                         parentColor: frozen,
                                                         groupCount: 1)
            XCTAssertEqual(chosen, NSColor.systemGreen, "frozen \(frozen)")
        }
    }

    // A sub-group never takes its parent's color, even when the parent's color
    // was frozen in the other appearance and every other entry is taken.
    func testSubgroupAvoidsParentColorFrozenInOtherAppearance() {
        let palette = [NSColor.systemBlue, NSColor.systemGreen]
        var darkBlue: NSColor?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            darkBlue = NSColor.systemBlue.usingColorSpace(.sRGB)
        }
        let green = NSColor.systemGreen.usingColorSpace(.sRGB)!
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            let chosen = iTermTabGroupColorChooser.color(palette: palette,
                                                         inUseColors: [darkBlue!, green],
                                                         parentColor: darkBlue,
                                                         groupCount: 2)
            XCTAssertEqual(chosen, NSColor.systemGreen)
        }
    }
}

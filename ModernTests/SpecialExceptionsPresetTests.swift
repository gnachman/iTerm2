import XCTest
@testable import iTerm2SharedARC

final class SpecialExceptionsPresetTests: XCTestCase {
    private func makeDistinctFonts() -> [NSFont] {
        let candidates = [
            "Menlo",
            "Monaco",
            "Courier",
            "Courier New",
            "Helvetica",
            "Times New Roman"
        ]
        var fonts: [NSFont] = []
        for candidate in candidates {
            guard let font = NSFont(name: candidate, size: 12),
                  let familyName = font.familyName else {
                continue
            }
            if fonts.allSatisfy({ $0.familyName != familyName }) {
                fonts.append(font)
            }
            if fonts.count == 3 {
                return fonts
            }
        }
        XCTFail("Expected at least three distinct fonts for the font table tests")
        let fallback = NSFont.userFixedPitchFont(ofSize: 12)!
        return [fallback, fallback, fallback]
    }

    private func makeFontTable(entries: [FontTable.Entry] = []) -> (FontTable, [NSFont]) {
        let fonts = makeDistinctFonts()
        let ascii = PTYFontInfo(font: fonts[0])
        let nonAscii = PTYFontInfo(font: fonts[1])
        let configString = entries.isEmpty ? nil : FontTable.Config(entries: entries).stringValue
        let table = FontTable(defaultFont: ascii,
                              nonAsciiFont: nonAscii,
                              configString: configString,
                              browserZoom: 1.0)
        return (table, fonts)
    }

    private func familyName(for codePoint: UTF32Char, in table: FontTable) -> String? {
        var remapped = codePoint
        return table.font(for: codePoint, remapped: &remapped).font.familyName
    }

    func testPresetCatalogMatchesExpectedRanges() {
        XCTAssertEqual(SpecialExceptionRangePreset.han.range, 0x4E00...0x9FFF)
        XCTAssertEqual(SpecialExceptionRangePreset.hiraganaKatakana.range, 0x3040...0x30FF)
        XCTAssertEqual(SpecialExceptionRangePreset.hangulSyllables.range, 0xAC00...0xD7AF)
        XCTAssertEqual(SpecialExceptionRangePreset.arabic.range, 0x0600...0x06FF)
        XCTAssertEqual(SpecialExceptionRangePreset.cyrillic.range, 0x0400...0x04FF)
        XCTAssertEqual(SpecialExceptionRangePreset.greek.range, 0x0370...0x03FF)
        XCTAssertEqual(SpecialExceptionRangePreset.privateUseArea.range, 0xE000...0xF8FF)
    }

    func testPresetMenuOrderIsAlphabetical() {
        XCTAssertEqual(SpecialExceptionRangePreset.menuOrder.map(\.title), [
            "Arabic",
            "Cyrillic",
            "Greek (Greek and Coptic)",
            "Han (CJK Unified Ideographs)",
            "Hangul Syllables",
            "Hiragana/Katakana",
            "Private Use Area",
        ])
    }

    func testNoConfigPreservesLegacyNonAsciiFallbackBehavior() {
        let (table, fonts) = makeFontTable()

        XCTAssertEqual(familyName(for: 0x41, in: table), fonts[0].familyName)
        XCTAssertEqual(familyName(for: 0x4E2D, in: table), fonts[1].familyName)
    }

    func testExplicitPresetOverridesLegacyNonAsciiFallback() {
        let ruleFont = makeDistinctFonts()[2]
        var entry = SpecialExceptionRangePreset.han.entry
        entry.fontName = ruleFont.fontName

        let (table, fonts) = makeFontTable(entries: [entry])

        XCTAssertEqual(familyName(for: 0x4E2D, in: table), ruleFont.familyName)
        XCTAssertEqual(familyName(for: 0x3042, in: table), fonts[1].familyName)
    }

    func testGreekPresetOverridesLegacyNonAsciiFallback() {
        let ruleFont = makeDistinctFonts()[2]
        var entry = SpecialExceptionRangePreset.greek.entry
        entry.fontName = ruleFont.fontName

        let (table, fonts) = makeFontTable(entries: [entry])

        XCTAssertEqual(familyName(for: 0x03A9, in: table), ruleFont.familyName)
        XCTAssertEqual(familyName(for: 0x0416, in: table), fonts[1].familyName)
    }

    func testPresetEntriesDoNotRemapCodePoints() {
        var entry = SpecialExceptionRangePreset.privateUseArea.entry
        entry.fontName = makeDistinctFonts()[2].fontName
        let (table, _) = makeFontTable(entries: [entry])

        let codePoint: UTF32Char = 0xE0B0
        var remapped = codePoint
        _ = table.font(for: codePoint, remapped: &remapped)

        XCTAssertEqual(remapped, codePoint)
    }
}

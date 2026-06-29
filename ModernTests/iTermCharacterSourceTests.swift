//
//  iTermCharacterSourceTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/14/26.
//
//  Tests that verify character sources generate valid bitmaps for various character types.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermCharacterSourceTests: XCTestCase {

    // MARK: - Test Fixtures

    private var context: CGContext!
    private var colorSpace: CGColorSpace!
    private var fontTable: FontTable!
    private var descriptor: iTermCharacterSourceDescriptor!
    private var attributes: iTermCharacterSourceAttributes!

    private let scale: CGFloat = 2.0  // Retina
    private let cellWidth: CGFloat = 16.0  // 8.0 * scale
    private let cellHeight: CGFloat = 32.0  // 16.0 * scale
    private let radius: Int32 = 2  // iTermTextureMapMaxCharacterParts / 2
    private let maxParts: Int = 5  // radius * 2 + 1

    override func setUp() {
        super.setUp()

        colorSpace = CGColorSpaceCreateDeviceRGB()

        // Create font table with a standard monospace font
        let font = NSFont(name: "Menlo", size: 12) ?? NSFont.userFixedPitchFont(ofSize: 12)!
        let fontInfo = PTYFontInfo(font: font)
        fontTable = FontTable(ascii: fontInfo, nonAscii: nil, browserZoom: 1.0)

        // Create bitmap context large enough for 5x5 cells
        let contextWidth = cellWidth * CGFloat(maxParts)
        let contextHeight = cellHeight * CGFloat(maxParts)

        context = CGContext(
            data: nil,
            width: Int(contextWidth),
            height: Int(contextHeight),
            bitsPerComponent: 8,
            bytesPerRow: Int(contextWidth) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        // Initialize context to transparent
        context.clear(CGRect(x: 0, y: 0, width: contextWidth, height: contextHeight))

        // Use the test helper to create descriptor and attributes
        descriptor = iTermCharacterSourceTestHelper.descriptor(
            with: fontTable,
            scale: scale,
            glyphSize: CGSize(width: cellWidth, height: cellHeight)
        )

        attributes = iTermCharacterSourceTestHelper.defaultAttributes()
    }

    override func tearDown() {
        context = nil
        colorSpace = nil
        fontTable = nil
        descriptor = nil
        attributes = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Draws a character and verifies a valid bitmap is generated
    private func verifyBitmapGenerated(forCharacter character: String, description: String) {
        guard let source = iTermCharacterSourceTestHelper.characterSource(
            withCharacter: character,
            descriptor: descriptor,
            attributes: attributes,
            radius: radius,
            context: context
        ) else {
            XCTFail("Failed to create character source for \(description)")
            return
        }

        // Trigger drawing and get the frame
        let frame = iTermCharacterSourceTestHelper.drawAndGetFrame(for: source)

        // Verify a valid frame was returned (non-zero)
        XCTAssertFalse(frame.isEmpty, "Frame should not be empty for \(description) (\(character))")
        XCTAssertGreaterThan(frame.width, 0, "Frame width should be > 0 for \(description)")
        XCTAssertGreaterThan(frame.height, 0, "Frame height should be > 0 for \(description)")
    }

    // MARK: - ASCII Character Tests

    func testASCIIUppercase() {
        verifyBitmapGenerated(forCharacter: "A", description: "ASCII uppercase A")
    }

    func testASCIILowercase() {
        verifyBitmapGenerated(forCharacter: "g", description: "ASCII lowercase g (descender)")
    }

    func testASCIIDigit() {
        verifyBitmapGenerated(forCharacter: "0", description: "ASCII digit 0")
    }

    func testASCIIPunctuation() {
        verifyBitmapGenerated(forCharacter: "@", description: "ASCII at symbol")
    }

    // MARK: - Non-ASCII Latin Tests

    func testAccentedLatin() {
        verifyBitmapGenerated(forCharacter: "\u{00E9}", description: "accented e (e-acute)")
    }

    func testUmlaut() {
        verifyBitmapGenerated(forCharacter: "\u{00FC}", description: "u with umlaut")
    }

    // MARK: - CJK Character Tests

    func testChineseCharacter() {
        verifyBitmapGenerated(forCharacter: "\u{4E2D}", description: "Chinese character zhong")
    }

    func testJapaneseHiragana() {
        verifyBitmapGenerated(forCharacter: "\u{3042}", description: "Japanese hiragana a")
    }

    func testJapaneseKatakana() {
        verifyBitmapGenerated(forCharacter: "\u{30A2}", description: "Japanese katakana a")
    }

    func testKoreanHangul() {
        verifyBitmapGenerated(forCharacter: "\u{D55C}", description: "Korean hangul han")
    }

    // MARK: - Combining Mark Tests

    func testCombiningMark() {
        // e followed by combining acute accent
        verifyBitmapGenerated(forCharacter: "e\u{0301}", description: "e with combining acute accent")
    }

    func testMultipleCombiningMarks() {
        // a with combining grave accent and combining tilde
        verifyBitmapGenerated(forCharacter: "a\u{0300}\u{0303}", description: "a with multiple combining marks")
    }

    func testCombiningEnclosingCircle() {
        // A with combining enclosing circle
        verifyBitmapGenerated(forCharacter: "A\u{20DD}", description: "A with combining enclosing circle")
    }

    // MARK: - Arabic and RTL Tests

    func testBismillah() {
        // The Bismillah ligature
        verifyBitmapGenerated(forCharacter: "\u{FDFD}", description: "Bismillah")
    }

    func testArabicCharacter() {
        verifyBitmapGenerated(forCharacter: "\u{0639}", description: "Arabic letter ain")
    }

    func testHebrewCharacter() {
        verifyBitmapGenerated(forCharacter: "\u{05D0}", description: "Hebrew letter aleph")
    }

    // MARK: - Other Script Tests

    func testThaiCharacter() {
        verifyBitmapGenerated(forCharacter: "\u{0E01}", description: "Thai letter ko kai")
    }

    func testThaiWithVowelMark() {
        // Thai character with above vowel mark
        verifyBitmapGenerated(forCharacter: "\u{0E01}\u{0E34}", description: "Thai with vowel mark")
    }

    func testDevanagariCharacter() {
        verifyBitmapGenerated(forCharacter: "\u{0905}", description: "Devanagari letter a")
    }

    func testGreekCharacter() {
        verifyBitmapGenerated(forCharacter: "\u{03A9}", description: "Greek capital omega")
    }

    func testCyrillicCharacter() {
        verifyBitmapGenerated(forCharacter: "\u{0414}", description: "Cyrillic letter de")
    }

    // MARK: - Symbol Tests

    func testMathSymbol() {
        verifyBitmapGenerated(forCharacter: "\u{2211}", description: "summation symbol")
    }

    func testArrow() {
        verifyBitmapGenerated(forCharacter: "\u{2192}", description: "rightwards arrow")
    }

    // MARK: - Emoji Tests

    func testEmoji() {
        verifyBitmapGenerated(forCharacter: "\u{1F600}", description: "grinning face emoji")
    }

    func testEmojiWithSkinTone() {
        verifyBitmapGenerated(forCharacter: "\u{1F44B}\u{1F3FD}", description: "waving hand medium skin tone")
    }

    func testFamilyEmoji() {
        // Family emoji (ZWJ sequence)
        verifyBitmapGenerated(forCharacter: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", description: "family emoji")
    }

    func testFlagEmoji() {
        // US Flag emoji (regional indicator symbols)
        verifyBitmapGenerated(forCharacter: "\u{1F1FA}\u{1F1F8}", description: "US flag emoji")
    }

    // MARK: - Edge Case Tests

    func testZalgoText() {
        // Text with many combining diacritical marks (Zalgo-style)
        verifyBitmapGenerated(forCharacter: "H\u{0300}\u{0301}\u{0302}\u{0303}\u{0304}", description: "Zalgo-style H")
    }

    func testSurrogatePairEmoji() {
        // Emoji outside BMP
        verifyBitmapGenerated(forCharacter: "\u{1F389}", description: "party popper emoji")
    }

    // MARK: - Context Clearing Tests

    /// Helper to verify that after drawing a character, the context is properly cleared
    private func verifyClearingWorks(forCharacter character: String, description: String) {
        guard let source = iTermCharacterSourceTestHelper.characterSource(
            withCharacter: character,
            descriptor: descriptor,
            attributes: attributes,
            radius: radius,
            context: context
        ) else {
            XCTFail("Failed to create character source for \(description)")
            return
        }

        let contextSize = CGSize(width: cellWidth * CGFloat(maxParts),
                                 height: cellHeight * CGFloat(maxParts))

        let isCleared = iTermCharacterSourceTestHelper.drawAndVerifyClearing(
            for: source,
            context: context,
            contextSize: contextSize
        )

        if !isCleared {
            let remainingBounds = iTermCharacterSourceTestHelper.pixelBounds(
                in: context,
                size: contextSize
            )
            XCTFail("Context not cleared for \(description) (\(character)). Remaining pixels at: \(remainingBounds)")
        }
    }

    func testClearingASCII() {
        verifyClearingWorks(forCharacter: "A", description: "ASCII uppercase A")
    }

    func testClearingCJK() {
        verifyClearingWorks(forCharacter: "\u{4E2D}", description: "Chinese character zhong")
    }

    func testClearingCombiningMarks() {
        verifyClearingWorks(forCharacter: "e\u{0301}", description: "e with combining acute accent")
    }

    func testClearingCurlyQuote() {
        // This was a failing case - curly quote with antialiasing
        verifyClearingWorks(forCharacter: "'", description: "curly quote")
    }

    func testClearingEmoji() {
        verifyClearingWorks(forCharacter: "\u{1F600}", description: "grinning face emoji")
    }

    func testClearingArabic() {
        verifyClearingWorks(forCharacter: "\u{0639}", description: "Arabic letter ain")
    }

    func testClearingBismillah() {
        verifyClearingWorks(forCharacter: "\u{FDFD}", description: "Bismillah ligature")
    }

    // MARK: - Exhaustive Font Tests

    /// Characters to test - alphabet plus challenging glyphs with descenders, ascenders, etc.
    private static let testCharacters: [(String, String)] = {
        var chars: [(String, String)] = []

        // Lowercase alphabet (includes descenders: g, j, p, q, y)
        for c in "abcdefghijklmnopqrstuvwxyz" {
            chars.append((String(c), "lowercase \(c)"))
        }

        // Uppercase alphabet
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            chars.append((String(c), "uppercase \(c)"))
        }

        // Digits
        for c in "0123456789" {
            chars.append((String(c), "digit \(c)"))
        }

        // Common punctuation with varying heights
        let punctuation = "!@#$%^&*()_+-=[]{}|;':\",./<>?`~"
        for c in punctuation {
            chars.append((String(c), "punctuation \(c)"))
        }

        // Accented Latin characters
        chars.append(("\u{00E9}", "e-acute"))
        chars.append(("\u{00E0}", "a-grave"))
        chars.append(("\u{00F1}", "n-tilde"))
        chars.append(("\u{00FC}", "u-umlaut"))
        chars.append(("\u{00E7}", "c-cedilla"))
        chars.append(("\u{00E5}", "a-ring"))

        // Characters with descenders in various scripts
        chars.append(("\u{03C1}", "Greek rho"))  // ρ
        chars.append(("\u{03B7}", "Greek eta"))  // η
        chars.append(("\u{03BC}", "Greek mu"))   // μ
        chars.append(("\u{0440}", "Cyrillic er")) // р
        chars.append(("\u{0443}", "Cyrillic u"))  // у

        // Arabic (can have complex shaping)
        chars.append(("\u{0639}", "Arabic ain"))
        chars.append(("\u{0642}", "Arabic qaf"))

        // CJK
        chars.append(("\u{4E2D}", "Chinese zhong"))
        chars.append(("\u{3042}", "Hiragana a"))
        chars.append(("\u{D55C}", "Korean han"))

        // Thai with marks (complex rendering)
        chars.append(("\u{0E01}\u{0E34}", "Thai with vowel"))

        // Combining marks
        chars.append(("e\u{0301}", "e with combining acute"))
        chars.append(("o\u{0302}", "o with combining circumflex"))

        return chars
    }()

    /// Tests clearing for all characters with a specific font and attributes
    private func testClearingAllCharacters(
        fontName: String,
        fontSize: CGFloat,
        bold: Bool,
        italic: Bool
    ) -> [(character: String, description: String)] {
        var failures: [(String, String)] = []

        guard let font = NSFont(name: fontName, size: fontSize) else {
            return failures
        }

        let fontInfo = PTYFontInfo(font: font)
        let testFontTable = FontTable(ascii: fontInfo, nonAscii: nil, browserZoom: 1.0)

        let testDescriptor = iTermCharacterSourceTestHelper.descriptor(
            with: testFontTable,
            scale: scale,
            glyphSize: CGSize(width: cellWidth, height: cellHeight)
        )

        let testAttributes = iTermCharacterSourceTestHelper.attributes(withBold: bold, italic: italic)

        let contextSize = CGSize(width: cellWidth * CGFloat(maxParts),
                                 height: cellHeight * CGFloat(maxParts))

        for (character, description) in Self.testCharacters {
            // Clear context before each character
            context.clear(CGRect(origin: .zero, size: contextSize))

            guard let source = iTermCharacterSourceTestHelper.characterSource(
                withCharacter: character,
                descriptor: testDescriptor,
                attributes: testAttributes,
                radius: radius,
                context: context
            ) else {
                continue  // Some characters may not be supported by font
            }

            let isCleared = iTermCharacterSourceTestHelper.drawAndVerifyClearing(
                for: source,
                context: context,
                contextSize: contextSize
            )

            if !isCleared {
                let attrDesc = (bold ? "bold " : "") + (italic ? "italic " : "")
                failures.append((character, "\(attrDesc)\(description) in \(fontName)"))
            }
        }

        return failures
    }

    /// Exhaustive test of all fonts - run manually with:
    /// tools/run_tests.expect ModernTests/iTermCharacterSourceTests/DISABLED_testClearingWithAllFonts
    func DISABLED_testClearingWithAllFonts() {
        let fontManager = NSFontManager.shared
        let allFonts = fontManager.availableFontFamilies

        var allFailures: [(character: String, description: String)] = []
        var testedFonts = 0

        for family in allFonts {
            guard let members = fontManager.availableMembers(ofFontFamily: family) else {
                continue
            }

            // Test first member of each family (usually Regular)
            if let firstMember = members.first,
               let fontName = firstMember[0] as? String {

                // Test regular
                let regularFailures = testClearingAllCharacters(
                    fontName: fontName,
                    fontSize: 12,
                    bold: false,
                    italic: false
                )
                allFailures.append(contentsOf: regularFailures)

                // Test with fake italic (the problematic case)
                let italicFailures = testClearingAllCharacters(
                    fontName: fontName,
                    fontSize: 12,
                    bold: false,
                    italic: true
                )
                allFailures.append(contentsOf: italicFailures)

                // Test with fake bold
                let boldFailures = testClearingAllCharacters(
                    fontName: fontName,
                    fontSize: 12,
                    bold: true,
                    italic: false
                )
                allFailures.append(contentsOf: boldFailures)

                // Test with both
                let boldItalicFailures = testClearingAllCharacters(
                    fontName: fontName,
                    fontSize: 12,
                    bold: true,
                    italic: true
                )
                allFailures.append(contentsOf: boldItalicFailures)

                testedFonts += 1
            }
        }

        print("Tested \(testedFonts) fonts with \(Self.testCharacters.count) characters each")
        print("Total combinations: \(testedFonts * Self.testCharacters.count * 4)")

        if !allFailures.isEmpty {
            print("Failures (\(allFailures.count)):")
            for (char, desc) in allFailures.prefix(50) {  // Limit output
                print("  '\(char)': \(desc)")
            }
            if allFailures.count > 50 {
                print("  ... and \(allFailures.count - 50) more")
            }
            XCTFail("Found \(allFailures.count) clearing failures across \(testedFonts) fonts")
        }
    }

    /// Test specifically for AppleColorEmoji '1' - a known edge case
    func testClearingAppleColorEmojiDigitOne() {
        guard let font = NSFont(name: "AppleColorEmoji", size: 12) else {
            XCTFail("AppleColorEmoji font not available")
            return
        }

        let fontInfo = PTYFontInfo(font: font)
        let testFontTable = FontTable(ascii: fontInfo, nonAscii: nil, browserZoom: 1.0)

        let testDescriptor = iTermCharacterSourceTestHelper.descriptor(
            with: testFontTable,
            scale: scale,
            glyphSize: CGSize(width: cellWidth, height: cellHeight)
        )

        let contextSize = CGSize(width: cellWidth * CGFloat(maxParts),
                                 height: cellHeight * CGFloat(maxParts))
        let bold = false
        let italic = false
        let attrName = "regular"
        // Clear context
        context.clear(CGRect(origin: .zero, size: contextSize))

        let testAttributes = iTermCharacterSourceTestHelper.attributes(withBold: bold, italic: italic)

        guard let source = iTermCharacterSourceTestHelper.characterSource(
            withCharacter: "1",
            descriptor: testDescriptor,
            attributes: testAttributes,
            radius: radius,
            context: context
        ) else {
            XCTFail("Failed to create character source for AppleColorEmoji '1' (\(attrName))")
            return
        }

        let isCleared = iTermCharacterSourceTestHelper.drawAndVerifyClearing(
            for: source,
            context: context,
            contextSize: contextSize
        )

        if !isCleared {
            let remainingBounds = iTermCharacterSourceTestHelper.pixelBounds(
                in: context,
                size: contextSize
            )
            XCTFail("Context not cleared for AppleColorEmoji '1' (\(attrName)). Remaining pixels at: \(remainingBounds)")
        }
    }

    // MARK: - Double-Width Line Tests

    /// Creates a CGContext and character source for double-width rendering.
    /// Uses radius=5 (iTermTextureMapMaxCharacterParts) like production, with
    /// maxParts=11. The context is sized to exactly maxParts * glyphSize so
    /// bitmapForPart byte-row extraction aligns with the draw offset.
    private func makeDoubleWidthSource(
        character: String
    ) -> (source: iTermCharacterSource, context: CGContext)? {
        let dwRadius: Int32 = 5  // iTermTextureMapMaxCharacterParts
        let dwMaxParts = Int(dwRadius) * 2 + 1  // 11
        let dwContextWidth = cellWidth * CGFloat(dwMaxParts)
        let dwContextHeight = cellHeight * CGFloat(dwMaxParts)

        guard let dwContext = CGContext(
            data: nil,
            width: Int(dwContextWidth),
            height: Int(dwContextHeight),
            bitsPerComponent: 8,
            bytesPerRow: Int(dwContextWidth) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        dwContext.clear(CGRect(x: 0, y: 0, width: dwContextWidth, height: dwContextHeight))

        guard let source = iTermCharacterSourceTestHelper.doubleWidthCharacterSource(
            withCharacter: character,
            descriptor: descriptor,
            attributes: attributes,
            radius: dwRadius,
            context: dwContext
        ) else {
            return nil
        }
        return (source, dwContext)
    }

    /// Helper: counts total non-zero pixels across all parts of a character source.
    private func totalNonZeroPixels(in source: iTermCharacterSource) -> Int {
        guard let parts = source.parts else { return 0 }
        var total = 0
        for part in parts {
            total += iTermCharacterSourceTestHelper.source(
                source, nonZeroPixelCountForPart: part.int32Value)
        }
        return total
    }

    /// Verify that a double-width rendering has visible pixels across its parts.
    /// This is the core regression test for the post-processing stride bug:
    /// if performPostProcessing doesn't account for the context's row stride
    /// being wider than _size, the extracted bitmaps come out blank.
    func testDoubleWidthBitmapHasContent() {
        guard let (source, _) = makeDoubleWidthSource(character: "A") else {
            XCTFail("Failed to create double-width source for 'A'")
            return
        }

        let total = totalNonZeroPixels(in: source)
        XCTAssertGreaterThan(total, 0,
            "Double-width 'A' should have visible pixels across its parts")
    }

    /// Verify that the 2x horizontal stretch causes the glyph to use more
    /// than one part (overflow into a neighbor cell).
    func testDoubleWidthBitmapOverflowsRight() {
        guard let (source, _) = makeDoubleWidthSource(character: "A") else {
            XCTFail("Failed to create double-width source for 'A'")
            return
        }

        guard let parts = source.parts else {
            XCTFail("No parts for double-width 'A'")
            return
        }

        // Count how many parts have content
        var partsWithContent = 0
        for part in parts {
            if iTermCharacterSourceTestHelper.source(
                source, hasBitmapContentForPart: part.int32Value) {
                partsWithContent += 1
            }
        }
        XCTAssertGreaterThan(partsWithContent, 1,
            "Double-width 'A' should have content in multiple parts (got \(partsWithContent))")
    }

    /// Compare single-width and double-width renderings of the same character.
    /// The double-width glyph is 2x stretched horizontally, so the total number
    /// of non-zero pixels across all parts should be roughly twice the
    /// single-width total (within a tolerance for antialiasing differences).
    func testDoubleWidthPixelCountApproximatelyDoublesSingleWidth() {
        // Single-width rendering
        guard let swSource = iTermCharacterSourceTestHelper.characterSource(
            withCharacter: "A",
            descriptor: descriptor,
            attributes: attributes,
            radius: radius,
            context: context
        ) else {
            XCTFail("Failed to create single-width source for 'A'")
            return
        }
        let swPixels = totalNonZeroPixels(in: swSource)
        XCTAssertGreaterThan(swPixels, 0, "Single-width 'A' should have pixels")

        // Double-width rendering
        guard let (dwSource, _) = makeDoubleWidthSource(character: "A") else {
            XCTFail("Failed to create double-width source for 'A'")
            return
        }
        let dwPixels = totalNonZeroPixels(in: dwSource)

        // The 2x horizontal stretch should roughly double the pixel count.
        // Allow wide tolerance (1.2x to 3x) for antialiasing differences.
        let ratio = Double(dwPixels) / Double(swPixels)
        XCTAssertGreaterThan(ratio, 1.2,
            "Double-width should have significantly more pixels than single-width " +
            "(got \(dwPixels) vs \(swPixels), ratio=\(ratio))")
        XCTAssertLessThan(ratio, 3.0,
            "Double-width pixel count should be reasonable " +
            "(got \(dwPixels) vs \(swPixels), ratio=\(ratio))")
    }

    /// Test several characters at double width to make sure they all produce content.
    /// Uses characters that fill their cell well (ascenders + wide strokes).
    func testDoubleWidthVariousCharacters() {
        // Use characters known to have substantial coverage in the center cell.
        // Characters with primarily descenders (g) or narrow strokes may need
        // the full production pipeline (including asciiOffset) to align correctly.
        let testChars = ["A", "W", "M", "X", "H"]
        for ch in testChars {
            guard let (source, _) = makeDoubleWidthSource(character: ch) else {
                XCTFail("Failed to create double-width source for '\(ch)'")
                continue
            }

            let total = totalNonZeroPixels(in: source)
            XCTAssertGreaterThan(total, 0,
                "Double-width '\(ch)' should have visible pixels across its parts")
        }
    }

    // MARK: - Double-Height Line Tests

    /// Creates a CGContext and character source for double-height rendering.
    private func makeDoubleHeightSource(
        character: String,
        lineAttribute: iTermLineAttribute
    ) -> (source: iTermCharacterSource, context: CGContext)? {
        let dhRadius: Int32 = 5  // iTermTextureMapMaxCharacterParts
        let dhMaxParts = Int(dhRadius) * 2 + 1  // 11
        let dhContextWidth = cellWidth * CGFloat(dhMaxParts)
        let dhContextHeight = cellHeight * CGFloat(dhMaxParts)

        guard let dhContext = CGContext(
            data: nil,
            width: Int(dhContextWidth),
            height: Int(dhContextHeight),
            bitsPerComponent: 8,
            bytesPerRow: Int(dhContextWidth) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        dhContext.clear(CGRect(x: 0, y: 0, width: dhContextWidth, height: dhContextHeight))

        let factory: (String, iTermCharacterSourceDescriptor, iTermCharacterSourceAttributes, Int32, CGContext) -> iTermCharacterSource?
        switch lineAttribute {
        case .doubleHeightTop:
            factory = iTermCharacterSourceTestHelper.doubleHeightTopCharacterSource(withCharacter:descriptor:attributes:radius:context:)
        case .doubleHeightBottom:
            factory = iTermCharacterSourceTestHelper.doubleHeightBottomCharacterSource(withCharacter:descriptor:attributes:radius:context:)
        default:
            return nil
        }
        guard let source = factory(character, descriptor, attributes, dhRadius, dhContext) else {
            return nil
        }
        return (source, dhContext)
    }

    /// Verify that double-height top rendering has visible pixels.
    func testDoubleHeightTopBitmapHasContent() {
        guard let (source, _) = makeDoubleHeightSource(
            character: "A", lineAttribute: .doubleHeightTop
        ) else {
            XCTFail("Failed to create double-height-top source for 'A'")
            return
        }

        let total = totalNonZeroPixels(in: source)
        XCTAssertGreaterThan(total, 0,
            "Double-height-top 'A' should have visible pixels across its parts")
    }

    /// Verify that double-height bottom rendering has visible pixels.
    func testDoubleHeightBottomBitmapHasContent() {
        guard let (source, _) = makeDoubleHeightSource(
            character: "A", lineAttribute: .doubleHeightBottom
        ) else {
            XCTFail("Failed to create double-height-bottom source for 'A'")
            return
        }

        let total = totalNonZeroPixels(in: source)
        XCTAssertGreaterThan(total, 0,
            "Double-height-bottom 'A' should have visible pixels across its parts")
    }

    /// Top and bottom use the same part positions (dy=0) but contain
    /// different pixel content because the atlas stores separate entries
    /// for each lineAttribute. Verify both have content and it differs.
    func testDoubleHeightTopAndBottomHaveDifferentContent() {
        guard let (topSource, _) = makeDoubleHeightSource(
            character: "A", lineAttribute: .doubleHeightTop
        ) else {
            XCTFail("Failed to create double-height-top source")
            return
        }
        guard let (bottomSource, _) = makeDoubleHeightSource(
            character: "A", lineAttribute: .doubleHeightBottom
        ) else {
            XCTFail("Failed to create double-height-bottom source")
            return
        }

        let topPixels = totalNonZeroPixels(in: topSource)
        let bottomPixels = totalNonZeroPixels(in: bottomSource)
        XCTAssertGreaterThan(topPixels, 0, "Top should have pixels")
        XCTAssertGreaterThan(bottomPixels, 0, "Bottom should have pixels")

        // The parts use the same grid positions (dy=0) but the atlas stores
        // separate entries per lineAttribute, so pixel content differs.
    }

    /// The combined pixel count of top + bottom should approximate the
    /// double-width pixel count (since DECDHL is 2x in both dimensions).
    func testDoubleHeightCombinedPixelsExceedDoubleWidth() {
        guard let (topSource, _) = makeDoubleHeightSource(
            character: "A", lineAttribute: .doubleHeightTop
        ) else {
            XCTFail("Failed to create double-height-top source")
            return
        }
        guard let (bottomSource, _) = makeDoubleHeightSource(
            character: "A", lineAttribute: .doubleHeightBottom
        ) else {
            XCTFail("Failed to create double-height-bottom source")
            return
        }
        guard let (dwSource, _) = makeDoubleWidthSource(character: "A") else {
            XCTFail("Failed to create double-width source")
            return
        }

        let topPixels = totalNonZeroPixels(in: topSource)
        let bottomPixels = totalNonZeroPixels(in: bottomSource)
        let dwPixels = totalNonZeroPixels(in: dwSource)
        let combinedPixels = topPixels + bottomPixels

        // Double-height renders at 2x both dimensions → ~4x single-width pixels.
        // Double-width is 2x horizontal only → ~2x single-width pixels.
        // Combined DH should be significantly more than DW.
        XCTAssertGreaterThan(combinedPixels, dwPixels,
            "Combined double-height pixels (\(combinedPixels)) should exceed " +
            "double-width pixels (\(dwPixels))")
    }

    /// Verify several characters produce content in both top and bottom halves.
    func testDoubleHeightVariousCharacters() {
        let testChars = ["A", "W", "M", "g", "y"]  // Include descender chars
        for ch in testChars {
            for attr: iTermLineAttribute in [.doubleHeightTop, .doubleHeightBottom] {
                let name = attr == .doubleHeightTop ? "top" : "bottom"
                guard let (source, _) = makeDoubleHeightSource(
                    character: ch, lineAttribute: attr
                ) else {
                    XCTFail("Failed to create double-height-\(name) source for '\(ch)'")
                    continue
                }

                let total = totalNonZeroPixels(in: source)
                XCTAssertGreaterThan(total, 0,
                    "Double-height-\(name) '\(ch)' should have visible pixels")
            }
        }
    }

    /// Quick test with just a few common fonts for CI
    func testClearingWithCommonFonts() {
        let commonFonts = [
            "Menlo",
            "Monaco",
            "SF Mono",
            "Courier",
            "Helvetica",
            "Arial",
            "Times New Roman"
        ]

        var allFailures: [(character: String, description: String)] = []

        for fontName in commonFonts {
            // Test with fake italic specifically (the bug we fixed)
            let failures = testClearingAllCharacters(
                fontName: fontName,
                fontSize: 12,
                bold: false,
                italic: true
            )
            allFailures.append(contentsOf: failures)
        }

        if !allFailures.isEmpty {
            for (char, desc) in allFailures {
                print("FAIL: '\(char)': \(desc)")
            }
            XCTFail("Found \(allFailures.count) clearing failures")
        }
    }
}

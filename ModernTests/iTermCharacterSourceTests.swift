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
}

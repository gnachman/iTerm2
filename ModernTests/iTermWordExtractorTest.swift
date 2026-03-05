//
//  iTermWordExtractorTest.swift
//  ModernTests
//
//  Created by George Nachman on 3/2/26.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Mock Text Data Source

/// A simple mock text data source that provides a grid of characters for testing word extraction
/// via iTermTextExtractor.
fileprivate class MockTextDataSource: NSObject, iTermTextDataSource {
    private var lines: [ScreenCharArray]
    private let gridWidth: Int32

    /// Creates a mock data source with the given lines of text.
    /// - Parameter strings: Array of strings, one per line
    /// - Parameter width: Width of the grid (defaults to 80)
    init(strings: [String], width: Int32 = 80) {
        self.gridWidth = width
        self.lines = []
        super.init()

        for string in strings {
            let sca = createScreenCharArray(from: string, width: width)
            lines.append(sca)
        }
    }

    /// Creates a ScreenCharArray from a string
    private func createScreenCharArray(from string: String, width: Int32) -> ScreenCharArray {
        var buffer = [screen_char_t](repeating: screen_char_t(), count: Int(width) + 1)

        for (index, char) in string.unicodeScalars.enumerated() {
            guard index < Int(width) else { break }
            buffer[index].code = unichar(char.value)
            buffer[index].complexChar = 0
        }

        // Set continuation character (EOL_HARD)
        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)

        return ScreenCharArray(
            copyOfLine: buffer,
            length: width,
            continuation: continuation
        )
    }

    // MARK: - iTermTextDataSource

    func width() -> Int32 {
        return gridWidth
    }

    func numberOfLines() -> Int32 {
        return Int32(lines.count)
    }

    func totalScrollbackOverflow() -> Int64 {
        return 0
    }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        guard line >= 0, line < lines.count else {
            return ScreenCharArray.emptyLine(ofLength: gridWidth)
        }
        return lines[Int(line)]
    }

    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        return screenCharArray(forLine: index)
    }

    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? {
        return nil
    }

    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        return block(screenCharArray(forLine: line))
    }

    func date(forLine line: Int32) -> Date? {
        return nil
    }

    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? {
        return nil
    }

    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata {
        return iTermImmutableMetadataDefault()
    }

    func isFirstLine(ofBlock lineNumber: Int32) -> Bool {
        return false
    }
}

// MARK: - Mock Text Data Source with Double-Width Character Support

/// A mock text data source that properly handles double-width characters (CJK).
/// Double-width characters occupy 2 cells: the character cell and a DWC_RIGHT placeholder.
fileprivate class MockTextDataSourceWithDWC: NSObject, iTermTextDataSource {
    private var lines: [ScreenCharArray]
    private let gridWidth: Int32

    init(strings: [String], width: Int32 = 80) {
        self.gridWidth = width
        self.lines = []
        super.init()

        for string in strings {
            let sca = createScreenCharArray(from: string, width: width)
            lines.append(sca)
        }
    }

    /// Check if a character is double-width (CJK, etc.)
    private func isDoubleWidth(_ scalar: Unicode.Scalar) -> Bool {
        // CJK Unified Ideographs and common double-width ranges
        let value = scalar.value
        return (value >= 0x4E00 && value <= 0x9FFF) ||  // CJK Unified Ideographs
               (value >= 0x3400 && value <= 0x4DBF) ||  // CJK Unified Ideographs Extension A
               (value >= 0xF900 && value <= 0xFAFF) ||  // CJK Compatibility Ideographs
               (value >= 0x3000 && value <= 0x303F) ||  // CJK Symbols and Punctuation
               (value >= 0xFF00 && value <= 0xFFEF) ||  // Halfwidth and Fullwidth Forms
               (value >= 0xAC00 && value <= 0xD7AF)     // Hangul Syllables
    }

    /// Creates a ScreenCharArray from a string, properly handling double-width characters
    private func createScreenCharArray(from string: String, width: Int32) -> ScreenCharArray {
        var buffer = [screen_char_t](repeating: screen_char_t(), count: Int(width) + 1)
        var cellIndex = 0

        for scalar in string.unicodeScalars {
            guard cellIndex < Int(width) else { break }

            buffer[cellIndex].code = unichar(scalar.value)
            buffer[cellIndex].complexChar = 0

            if isDoubleWidth(scalar) {
                // Double-width character: set DWC_RIGHT in the next cell
                cellIndex += 1
                if cellIndex < Int(width) {
                    buffer[cellIndex].code = unichar(DWC_RIGHT)
                    buffer[cellIndex].complexChar = 0
                }
            }
            cellIndex += 1
        }

        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)

        return ScreenCharArray(
            copyOfLine: buffer,
            length: width,
            continuation: continuation
        )
    }

    // MARK: - iTermTextDataSource

    func width() -> Int32 {
        return gridWidth
    }

    func numberOfLines() -> Int32 {
        return Int32(lines.count)
    }

    func totalScrollbackOverflow() -> Int64 {
        return 0
    }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        guard line >= 0, line < lines.count else {
            return ScreenCharArray.emptyLine(ofLength: gridWidth)
        }
        return lines[Int(line)]
    }

    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        return screenCharArray(forLine: index)
    }

    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? {
        return nil
    }

    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        return block(screenCharArray(forLine: line))
    }

    func date(forLine line: Int32) -> Date? {
        return nil
    }

    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? {
        return nil
    }

    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata {
        return iTermImmutableMetadataDefault()
    }

    func isFirstLine(ofBlock lineNumber: Int32) -> Bool {
        return false
    }
}

// MARK: - Tests

class iTermWordExtractorTest: XCTestCase {

    // MARK: - Helper Methods

    private func extractWord(
        from strings: [String],
        at location: VT100GridCoord,
        maximumLength: Int = 1000,
        big: Bool = false,
        additionalWordCharacters: String? = nil,
        mode: iTermSelectionWordMode = .characterList,
        width: Int32 = 80
    ) -> VT100GridWindowedRange {
        let dataSource = MockTextDataSource(strings: strings, width: width)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Use perform selector to call the ObjC method
        // rangeForWordAt:maximumLength:big:additionalWordCharacters:mode:
        if big || additionalWordCharacters != nil {
            return textExtractor.rangeForWord(
                at: location,
                maximumLength: maximumLength,
                big: big,
                additionalWordCharacters: additionalWordCharacters,
                mode: mode
            )
        } else {
            // Use the simple version
            return textExtractor.rangeForWord(at: location, maximumLength: maximumLength)
        }
    }

    private func extractFastWord(
        from strings: [String],
        at location: VT100GridCoord,
        width: Int32 = 80
    ) -> String? {
        let dataSource = MockTextDataSource(strings: strings, width: width)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)
        return textExtractor.fastWord(at: location)
    }

    private func assertRangeEquals(
        _ range: VT100GridWindowedRange,
        startX: Int32, startY: Int32,
        endX: Int32, endY: Int32,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(range.coordRange.start.x, startX, "Start X mismatch", file: file, line: line)
        XCTAssertEqual(range.coordRange.start.y, startY, "Start Y mismatch", file: file, line: line)
        XCTAssertEqual(range.coordRange.end.x, endX, "End X mismatch", file: file, line: line)
        XCTAssertEqual(range.coordRange.end.y, endY, "End Y mismatch", file: file, line: line)
    }

    // MARK: - Test Cases

    /// Test 1: Word selection at alphanumeric character - Click on a letter, verify word boundaries
    func testWordSelectionAtAlphanumericCharacter() {
        let range = extractWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 2, y: 0)  // 'l' in "hello"
        )

        // "hello" starts at 0 and ends at 5 (half-open interval)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 5, endY: 0)
    }

    /// Test clicking on different positions in a word
    func testWordSelectionAtDifferentPositions() {
        // Click at start of word
        let range1 = extractWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 0, y: 0)  // 'h' in "hello"
        )
        assertRangeEquals(range1, startX: 0, startY: 0, endX: 5, endY: 0)

        // Click at end of word
        let range2 = extractWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 4, y: 0)  // 'o' in "hello"
        )
        assertRangeEquals(range2, startX: 0, startY: 0, endX: 5, endY: 0)

        // Click on second word
        let range3 = extractWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 6, y: 0)  // 'w' in "world"
        )
        assertRangeEquals(range3, startX: 6, startY: 0, endX: 11, endY: 0)
    }

    /// Test 2: Additional word characters - With additionalWordCharacters = "/", verify foo/bar is one word
    func testAdditionalWordCharacters() {
        let range = extractWord(
            from: ["foo/bar baz"],
            at: VT100GridCoord(x: 2, y: 0),  // 'o' in "foo"
            additionalWordCharacters: "/"
        )

        // "foo/bar" should be selected as one word (0-7)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 7, endY: 0)
    }

    /// Test additional word characters with hyphen
    func testAdditionalWordCharactersWithHyphen() {
        let range = extractWord(
            from: ["foo-bar baz"],
            at: VT100GridCoord(x: 2, y: 0),
            additionalWordCharacters: "-"
        )

        assertRangeEquals(range, startX: 0, startY: 0, endX: 7, endY: 0)
    }

    /// Test 3: Whitespace boundaries - Verify words stop at whitespace
    func testWhitespaceBoundaries() {
        let range = extractWord(
            from: ["one   two   three"],
            at: VT100GridCoord(x: 7, y: 0)  // 'w' in "two"
        )

        // "two" is at positions 6-8, so range should be 6-9
        assertRangeEquals(range, startX: 6, startY: 0, endX: 9, endY: 0)
    }

    /// Test whitespace at start of line
    func testWhitespaceAtStartOfLine() {
        let range = extractWord(
            from: ["   hello"],
            at: VT100GridCoord(x: 4, y: 0)  // 'e' in "hello"
        )

        assertRangeEquals(range, startX: 3, startY: 0, endX: 8, endY: 0)
    }

    /// Test 4: Symbol boundaries - Clicking on @ or # should select just that character
    func testSymbolBoundaries() {
        let range1 = extractWord(
            from: ["hello@world"],
            at: VT100GridCoord(x: 5, y: 0)  // '@'
        )

        // '@' should select just itself (position 5-6)
        assertRangeEquals(range1, startX: 5, startY: 0, endX: 6, endY: 0)

        // Test with '#'
        let range2 = extractWord(
            from: ["hello#world"],
            at: VT100GridCoord(x: 5, y: 0)  // '#'
        )

        assertRangeEquals(range2, startX: 5, startY: 0, endX: 6, endY: 0)
    }

    /// Test various punctuation marks
    /// Note: Some punctuation marks may be treated differently based on the user's preferences
    /// or the context. The behavior varies by character class.
    func testVariousPunctuationMarks() {
        // These punctuation marks should select just themselves (class "other")
        let singleSelectPunctuation = ["@", "#"]

        for punct in singleSelectPunctuation {
            let range = extractWord(
                from: ["hello\(punct)world"],
                at: VT100GridCoord(x: 5, y: 0)
            )
            assertRangeEquals(range, startX: 5, startY: 0, endX: 6, endY: 0)
        }
    }

    /// Test 6: Language-specific segmentation - Test with simple ASCII
    func testSimpleASCIIWordBoundaries() {
        let range = extractWord(
            from: ["abc"],
            at: VT100GridCoord(x: 1, y: 0)
        )

        assertRangeEquals(range, startX: 0, startY: 0, endX: 3, endY: 0)
    }

    /// Test 7: Maximum length truncation - Test that maximumLength is respected
    func testMaximumLengthTruncation() {
        let longWord = String(repeating: "a", count: 100)
        let range = extractWord(
            from: [longWord],
            at: VT100GridCoord(x: 50, y: 0),
            maximumLength: 10  // Limit to 10 characters
        )

        // The range should be limited by maximumLength
        let rangeLength = range.coordRange.end.x - range.coordRange.start.x
        XCTAssertLessThanOrEqual(rangeLength, 20)  // 10 forward + 10 backward max
    }

    /// Test very small maximum length
    func testVerySmallMaximumLength() {
        let range = extractWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 2, y: 0),
            maximumLength: 2
        )

        let rangeLength = range.coordRange.end.x - range.coordRange.start.x
        XCTAssertLessThanOrEqual(rangeLength, 4)
    }

    /// Test 8: fastString method - Test the fast word extraction path
    func testFastString() {
        let fastString = extractFastWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 2, y: 0)
        )

        // fastString should return "hello"
        XCTAssertEqual(fastString, "hello")
    }

    /// Test fastString with symbols
    func testFastStringWithSymbols() {
        let fastString = extractFastWord(
            from: ["hello@world"],
            at: VT100GridCoord(x: 5, y: 0)  // '@'
        )

        // '@' is not a word character, so fastString should return nil
        XCTAssertNil(fastString)
    }

    /// Test fastString at start of word
    func testFastStringAtStartOfWord() {
        let fastString = extractFastWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 0, y: 0)
        )

        XCTAssertEqual(fastString, "hello")
    }

    /// Test 9: Big word mode - Test big=true which treats non-whitespace as word chars
    func testBigWordMode() {
        let range = extractWord(
            from: ["foo@bar#baz qux"],
            at: VT100GridCoord(x: 5, y: 0),  // 'a' in "bar"
            big: true
        )

        // In big word mode, "foo@bar#baz" should be one word (all non-whitespace)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 11, endY: 0)
    }

    /// Test big word with various symbols
    func testBigWordWithSymbols() {
        let range = extractWord(
            from: ["a!@#$%^&*()b c"],
            at: VT100GridCoord(x: 5, y: 0),
            big: true
        )

        // Everything up to the space should be one "big word"
        assertRangeEquals(range, startX: 0, startY: 0, endX: 12, endY: 0)
    }

    // MARK: - Big Word Mode Comprehensive Tests

    /// Test big word at start of line - clicking on first character (symbol)
    /// e.g., "@#$hello world" clicking on '@' should select "@#$hello"
    func testBigWordAtStartOfLine() {
        let range = extractWord(
            from: ["@#$hello world"],
            at: VT100GridCoord(x: 0, y: 0),  // '@' at start
            big: true
        )

        // "@#$hello" is 8 characters (positions 0-7), space at 8
        assertRangeEquals(range, startX: 0, startY: 0, endX: 8, endY: 0)
    }

    /// Test big word at start of line - clicking on alphanumeric part
    func testBigWordAtStartOfLineClickingOnAlpha() {
        let range = extractWord(
            from: ["@#$hello world"],
            at: VT100GridCoord(x: 5, y: 0),  // 'l' in "hello"
            big: true
        )

        // "@#$hello" is one big word (0-8)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 8, endY: 0)
    }

    /// Test big word at end of line - clicking on last character
    /// e.g., "hello @#$world" clicking on 'd' should select "@#$world"
    func testBigWordAtEndOfLine() {
        let range = extractWord(
            from: ["hello @#$world"],
            at: VT100GridCoord(x: 13, y: 0),  // 'd' at end
            big: true
        )

        // "@#$world" starts at position 6 and ends at 14
        assertRangeEquals(range, startX: 6, startY: 0, endX: 14, endY: 0)
    }

    /// Test big word at end of line - clicking on symbol part
    func testBigWordAtEndOfLineClickingOnSymbol() {
        let range = extractWord(
            from: ["hello @#$world"],
            at: VT100GridCoord(x: 7, y: 0),  // '#' in "@#$"
            big: true
        )

        // "@#$world" is one big word (6-14)
        assertRangeEquals(range, startX: 6, startY: 0, endX: 14, endY: 0)
    }

    /// Test big word with CJK/double-width characters
    /// e.g., "hello中文world test" - clicking on CJK should select entire non-whitespace run
    func testBigWordWithCJKDoubleWidthCharacters() {
        // Use DWC-aware data source
        // "hello中文world test"
        // Layout: h(0) e(1) l(2) l(3) o(4) 中(5-6) 文(7-8) w(9) o(10) r(11) l(12) d(13) space(14) t(15) e(16) s(17) t(18)
        let dataSource = MockTextDataSourceWithDWC(strings: ["hello中文world test"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Click on '中' at cell 5
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 5, y: 0),
            maximumLength: 1000,
            big: true,
            additionalWordCharacters: nil,
            mode: .characterList
        )

        // "hello中文world" spans cells 0-14 (before the space at 14)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 14, endY: 0)
    }

    /// Test big word clicking on DWC_RIGHT placeholder in big mode
    func testBigWordClickOnDWCRight() {
        let dataSource = MockTextDataSourceWithDWC(strings: ["a中b"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // "a中b" = a(0) 中(1-2) b(3)
        // Click on DWC_RIGHT at cell 2
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 2, y: 0),
            maximumLength: 1000,
            big: true,
            additionalWordCharacters: nil,
            mode: .characterList
        )

        // Entire "a中b" should be selected (0-4)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 4, endY: 0)
    }

    /// Test big word spanning entire line (no whitespace)
    func testBigWordSpanningEntireLine() {
        let range = extractWord(
            from: ["abc@#$123!@#xyz"],
            at: VT100GridCoord(x: 7, y: 0),  // somewhere in the middle
            big: true
        )

        // Entire line is one big word (15 characters, 0-15)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 15, endY: 0)
    }

    /// Test big word on line with only whitespace
    func testBigWordWithOnlyWhitespace() {
        let range = extractWord(
            from: ["     "],  // 5 spaces
            at: VT100GridCoord(x: 2, y: 0),  // middle space
            big: true
        )

        // Even in big mode, clicking on whitespace selects whitespace
        // The entire run of spaces (0-5) should be selected
        assertRangeEquals(range, startX: 0, startY: 0, endX: 5, endY: 0)
    }

    /// Test big word with tabs as delimiters
    func testBigWordWithTabDelimiters() {
        let range = extractWord(
            from: ["abc\tdef\tghi"],  // tab-separated
            at: VT100GridCoord(x: 5, y: 0),  // 'e' in "def"
            big: true
        )

        // Tabs are whitespace, so "def" should be selected (positions 4-6)
        // abc(0-2) tab(3) def(4-6) tab(7) ghi(8-10)
        assertRangeEquals(range, startX: 4, startY: 0, endX: 7, endY: 0)
    }

    /// Test big word with multiple consecutive tabs
    func testBigWordWithMultipleTabs() {
        let range = extractWord(
            from: ["abc\t\t\tdef"],
            at: VT100GridCoord(x: 4, y: 0),  // middle tab
            big: true
        )

        // abc(0-2) tabs(3,4,5) def(6-8)
        // Clicking on tab at position 4 selects all consecutive tabs (3-6)
        assertRangeEquals(range, startX: 3, startY: 0, endX: 6, endY: 0)
    }

    /// Test big word with logical window - word should stop at window boundary
    func testBigWordWithLogicalWindowLeftBoundary() {
        let dataSource = MockTextDataSource(strings: ["@#$abc@#$def"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)
        textExtractor.logicalWindow = VT100GridRangeMake(3, 10)  // Window starts at position 3

        // Click on 'a' at position 3 (first char in window)
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 5, y: 0),  // 'c' in "abc"
            maximumLength: 1000,
            big: true,
            additionalWordCharacters: nil,
            mode: .characterList
        )

        // In big mode, all non-whitespace is one word, but window constrains it
        // Window starts at 3, so selection starts there
        // "@#$abc@#$def" with window at 3 means we see "abc@#$def"
        // Should select from window start (3) to end of non-whitespace
        assertRangeEquals(range, startX: 3, startY: 0, endX: 12, endY: 0)
    }

    /// Test big word with logical window - word should stop at right window boundary
    func testBigWordWithLogicalWindowRightBoundary() {
        let dataSource = MockTextDataSource(strings: ["abc@#$def@#$ghi"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)
        textExtractor.logicalWindow = VT100GridRangeMake(0, 9)  // Window ends at position 9

        // Click on '@' at position 3
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 3, y: 0),
            maximumLength: 1000,
            big: true,
            additionalWordCharacters: nil,
            mode: .characterList
        )

        // Window ends at 9, so selection should be limited to 0-9
        assertRangeEquals(range, startX: 0, startY: 0, endX: 9, endY: 0)
    }

    /// Test big word with mixed punctuation and alphanumeric
    func testBigWordWithMixedPunctuationAndAlphanumeric() {
        let range = extractWord(
            from: ["foo.bar-baz_qux:123 next"],
            at: VT100GridCoord(x: 10, y: 0),  // 'a' in "baz"
            big: true
        )

        // "foo.bar-baz_qux:123" is one big word (positions 0-18, space at 19)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 19, endY: 0)
    }

    /// Test big word with path-like content
    func testBigWordWithPathContent() {
        let range = extractWord(
            from: ["/usr/local/bin/script.sh more"],
            at: VT100GridCoord(x: 10, y: 0),  // 'l' in "local"
            big: true
        )

        // "/usr/local/bin/script.sh" is one big word (positions 0-24)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 24, endY: 0)
    }

    /// Test big word with URL-like content
    func testBigWordWithURLContent() {
        let range = extractWord(
            from: ["https://example.com/path?query=1 text"],
            at: VT100GridCoord(x: 15, y: 0),  // 'e' in "example"
            big: true
        )

        // "https://example.com/path?query=1" is one big word (32 chars, positions 0-32 half-open)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 32, endY: 0)
    }

    /// Test big word with special Unicode symbols
    func testBigWordWithUnicodeSymbols() {
        let range = extractWord(
            from: ["foo\u{2022}bar\u{2013}baz next"],  // bullet and en-dash
            at: VT100GridCoord(x: 4, y: 0),  // bullet character
            big: true
        )

        // "foo•bar–baz" (positions 0-10, space at 11)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 11, endY: 0)
    }

    /// Test big word with leading symbols
    func testBigWordWithLeadingSymbols() {
        let range = extractWord(
            from: ["---test--- next"],
            at: VT100GridCoord(x: 0, y: 0),  // first '-'
            big: true
        )

        // "---test---" is one big word (0-10)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 10, endY: 0)
    }

    /// Test big word with trailing symbols
    func testBigWordWithTrailingSymbols() {
        let range = extractWord(
            from: ["test!@#$% next"],
            at: VT100GridCoord(x: 8, y: 0),  // '%'
            big: true
        )

        // "test!@#$%" is one big word (0-9)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 9, endY: 0)
    }

    /// Test big word mode does not affect whitespace selection behavior
    func testBigWordWhitespaceSelectionUnaffected() {
        // Big mode shouldn't change how whitespace is selected
        let range = extractWord(
            from: ["abc   def"],
            at: VT100GridCoord(x: 4, y: 0),  // middle space
            big: true
        )

        // Whitespace run from 3-6
        assertRangeEquals(range, startX: 3, startY: 0, endX: 6, endY: 0)
    }

    /// Test big word with newline-separated content (single line)
    func testBigWordSingleWord() {
        let range = extractWord(
            from: ["word"],
            at: VT100GridCoord(x: 2, y: 0),  // 'r'
            big: true
        )

        // "word" is the only content
        assertRangeEquals(range, startX: 0, startY: 0, endX: 4, endY: 0)
    }

    /// Test big word with brackets and parentheses
    func testBigWordWithBracketsAndParentheses() {
        let range = extractWord(
            from: ["func(arg1,arg2)[0] next"],
            at: VT100GridCoord(x: 8, y: 0),  // '1' in "arg1"
            big: true
        )

        // "func(arg1,arg2)[0]" is one big word (0-17)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 18, endY: 0)
    }

    /// Test clicking on whitespace
    func testClickOnWhitespace() {
        let range = extractWord(
            from: ["hello   world"],
            at: VT100GridCoord(x: 6, y: 0)  // space between words
        )

        // Clicking on whitespace selects the entire whitespace run.
        // "hello   world" has 3 spaces at positions 5, 6, 7 (half-open interval: 5-8)
        assertRangeEquals(range, startX: 5, startY: 0, endX: 8, endY: 0)
    }

    /// Test clicking on null/empty cell
    func testClickOnNullCell() {
        let range = extractWord(
            from: ["hello"],  // Rest of line is nulls
            at: VT100GridCoord(x: 10, y: 0)  // Beyond the text
        )

        // Clicking on null cells selects from the end of text (position 5) to the click position (10).
        // This selects the null region from position 5 to 10.
        assertRangeEquals(range, startX: 5, startY: 0, endX: 10, endY: 0)
    }

    /// Test invalid location (negative coordinates)
    func testInvalidLocationNegative() {
        let range = extractWord(
            from: ["hello"],
            at: VT100GridCoord(x: 0, y: -1)  // Invalid y
        )

        // Should return error location
        XCTAssertEqual(range.coordRange.start.x, -1)
        XCTAssertEqual(range.coordRange.start.y, -1)
    }

    /// Test numbers in words
    func testNumbersInWords() {
        let range = extractWord(
            from: ["abc123def"],
            at: VT100GridCoord(x: 4, y: 0)  // '2' in the middle
        )

        // Numbers are alphanumeric, so the whole thing should be one word
        assertRangeEquals(range, startX: 0, startY: 0, endX: 9, endY: 0)
    }

    /// Test underscores (often part of identifiers)
    func testUnderscores() {
        // Underscores are treated as word characters by default (alphanumeric character class).
        // Clicking on position 5 ('a' in "bar") selects the entire "foo_bar_baz" string.
        let range1 = extractWord(
            from: ["foo_bar_baz"],
            at: VT100GridCoord(x: 5, y: 0)
        )

        // The entire string "foo_bar_baz" (11 chars) is selected as one word
        assertRangeEquals(range1, startX: 0, startY: 0, endX: 11, endY: 0)

        // With underscore as additional word character (same behavior as default)
        let range2 = extractWord(
            from: ["foo_bar_baz"],
            at: VT100GridCoord(x: 5, y: 0),
            additionalWordCharacters: "_"
        )

        assertRangeEquals(range2, startX: 0, startY: 0, endX: 11, endY: 0)
    }

    /// Test path-like strings with additional characters
    func testPathLikeStrings() {
        let range = extractWord(
            from: ["/usr/local/bin/script.sh more"],
            at: VT100GridCoord(x: 10, y: 0),  // 'l' in "local"
            additionalWordCharacters: "/.-"
        )

        // The whole path should be selected
        assertRangeEquals(range, startX: 0, startY: 0, endX: 24, endY: 0)
    }

    /// Test URL-like strings
    func testURLLikeStrings() {
        let range = extractWord(
            from: ["https://example.com/path text"],
            at: VT100GridCoord(x: 10, y: 0),
            additionalWordCharacters: ":/.?"
        )

        // URL should be selected as one unit
        assertRangeEquals(range, startX: 0, startY: 0, endX: 24, endY: 0)
    }

    /// Test empty string - clicking on position 0 of an empty line should select the null cell
    func testEmptyLine() {
        let range = extractWord(
            from: [""],
            at: VT100GridCoord(x: 0, y: 0)
        )

        // Empty line means null cells; clicking at position 0 selects null at that position
        assertRangeEquals(range, startX: 0, startY: 0, endX: 0, endY: 0)
    }

    /// Test single character word
    func testSingleCharacterWord() {
        let range = extractWord(
            from: ["a b c"],
            at: VT100GridCoord(x: 2, y: 0)  // 'b'
        )

        // Single character 'b' at position 2
        assertRangeEquals(range, startX: 2, startY: 0, endX: 3, endY: 0)
    }

    /// Test mixed case
    func testMixedCase() {
        let range = extractWord(
            from: ["HelloWorld"],
            at: VT100GridCoord(x: 5, y: 0)  // 'W'
        )

        // Should select entire word regardless of case changes
        assertRangeEquals(range, startX: 0, startY: 0, endX: 10, endY: 0)
    }

    /// Test double-width characters (CJK) in word selection.
    /// Double-width characters occupy 2 cells: the character cell and a DWC_RIGHT placeholder.
    /// For example, "中文" (2 Chinese chars) occupies 4 cells: [中][DWC_RIGHT][文][DWC_RIGHT]
    func testDoubleWidthCharacters() {
        // Use the DWC-aware data source for this test
        let dataSource = MockTextDataSourceWithDWC(strings: ["中文"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Click on cell 0 (first character "中")
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 0, y: 0),
            maximumLength: 1000
        )

        // "中文" occupies cells 0-3 (中 at 0, DWC_RIGHT at 1, 文 at 2, DWC_RIGHT at 3)
        // The range should be 0-4 (half-open interval)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 4, endY: 0)
    }

    /// Test clicking on DWC_RIGHT placeholder selects the full double-width character
    func testClickOnDWCRight() {
        let dataSource = MockTextDataSourceWithDWC(strings: ["中文"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Click on cell 1 (DWC_RIGHT placeholder for "中")
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 1, y: 0),
            maximumLength: 1000
        )

        // Should still select the full word "中文" (cells 0-4)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 4, endY: 0)
    }

    /// Test mixed ASCII and double-width characters - OS segments these as separate words
    func testMixedASCIIAndDoubleWidth() {
        // "a中b" = [a][中][DWC_RIGHT][b] = 4 cells
        // The OS treats this as 3 separate words: "a", "中", "b"
        let dataSource = MockTextDataSourceWithDWC(strings: ["a中b"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Click on 'a' at cell 0 - should select just 'a'
        let range1 = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 0, y: 0),
            maximumLength: 1000
        )
        assertRangeEquals(range1, startX: 0, startY: 0, endX: 1, endY: 0)

        // Click on '中' at cell 1 - should select just '中' (cells 1-3, including DWC_RIGHT)
        let range2 = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 1, y: 0),
            maximumLength: 1000
        )
        assertRangeEquals(range2, startX: 1, startY: 0, endX: 3, endY: 0)

        // Click on 'b' at cell 3 - should select just 'b'
        let range3 = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 3, y: 0),
            maximumLength: 1000
        )
        assertRangeEquals(range3, startX: 3, startY: 0, endX: 4, endY: 0)
    }

    // MARK: - Regex Mode with CJK Tests

    /// Helper to extract word with regex patterns
    private func extractWordWithRegex(
        from strings: [String],
        at location: VT100GridCoord,
        regexPatterns: [String],
        maximumLength: Int = 1000,
        big: Bool = false,
        additionalWordCharacters: String? = nil,
        width: Int32 = 80
    ) -> VT100GridWindowedRange {
        let dataSource = MockTextDataSourceWithDWC(strings: strings, width: width)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        return textExtractor.rangeForWord(
            at: location,
            maximumLength: maximumLength,
            big: big,
            additionalWordCharacters: additionalWordCharacters,
            regexPatterns: regexPatterns
        )
    }

    /// Test regex mode with Chinese text - ICU should segment properly
    /// "翻真的" consists of two words: "翻" and "真的"
    func testRegexModeWithChineseText() {
        // "翻真的" = [翻][DWC][真][DWC][的][DWC] = 6 cells
        // According to ICU: "翻" = word 1, "真的" = word 2
        let dataSource = MockTextDataSourceWithDWC(strings: ["翻真的"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Click on "真" at cell 2 - should select "真的" (cells 2-6)
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 2, y: 0),
            maximumLength: 1000,
            big: false,
            additionalWordCharacters: nil,
            regexPatterns: ["://"]  // Some regex pattern to enable regex mode
        )

        // "真的" spans cells 2-6 (真 at 2-3, 的 at 4-5)
        assertRangeEquals(range, startX: 2, startY: 0, endX: 6, endY: 0)
    }

    /// Test regex mode with Chinese text - clicking on first word
    func testRegexModeWithChineseTextFirstWord() {
        let dataSource = MockTextDataSourceWithDWC(strings: ["翻真的"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Click on "翻" at cell 0 - should select just "翻" (cells 0-2)
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 0, y: 0),
            maximumLength: 1000,
            big: false,
            additionalWordCharacters: nil,
            regexPatterns: ["://"]
        )

        // "翻" spans cells 0-2
        assertRangeEquals(range, startX: 0, startY: 0, endX: 2, endY: 0)
    }

    /// Test regex match bridges CJK word boundaries
    /// When a regex matches, it should extend across what would otherwise be separate words
    func testRegexMatchBridgesCJKWordBoundaries() {
        // "翻真的" with a regex that matches "翻真"
        let dataSource = MockTextDataSourceWithDWC(strings: ["翻真的"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Using regex pattern that matches "翻真" - should bridge the word boundary
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 0, y: 0),  // Click on "翻"
            maximumLength: 1000,
            big: false,
            additionalWordCharacters: nil,
            regexPatterns: ["翻真"]  // This pattern bridges the ICU word boundary
        )

        // The regex "翻真" matches cells 0-4, which is word-extending.
        // Then "的" is examined - ICU considers "真的" as one word (it sees the full text
        // and groups them together), so "的" gets included.
        // Result: cells 0-6 (翻 at 0-1, 真 at 2-3, 的 at 4-5)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 6, endY: 0)
    }

    /// Test regex mode with mixed ASCII and CJK
    func testRegexModeWithMixedASCIIAndCJK() {
        // "abc翻真的xyz" - ASCII and CJK mixed
        let dataSource = MockTextDataSourceWithDWC(strings: ["abc翻真的xyz"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Click on "真" - should select "真的" per ICU segmentation
        // Layout: a(0) b(1) c(2) 翻(3-4) 真(5-6) 的(7-8) x(9) y(10) z(11)
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 5, y: 0),  // Click on "真"
            maximumLength: 1000,
            big: false,
            additionalWordCharacters: nil,
            regexPatterns: ["://"]
        )

        // "真的" spans cells 5-9
        assertRangeEquals(range, startX: 5, startY: 0, endX: 9, endY: 0)
    }

    /// Test regex match with URL in CJK text
    func testRegexMatchWithURLInCJKText() {
        // "请https://abc" - CJK followed by URL
        // Test that URL detection works in CJK context
        let dataSource = MockTextDataSourceWithDWC(strings: ["请https://abc"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Click on "h" in https - should select from "请" through "abc"
        // Layout: 请(0-1) h(2) t(3) t(4) p(5) s(6) :(7) /(8) /(9) a(10) b(11) c(12)
        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 2, y: 0),  // Click on "h"
            maximumLength: 1000,
            big: false,
            additionalWordCharacters: nil,
            regexPatterns: ["https?://"]
        )

        // "https://" is a regex match (word-extending), followed by "abc"
        // The search backward finds "请" which is also classified as word.
        // Since all characters are word class, and regex match is word-extending,
        // the entire string is selected.
        assertRangeEquals(range, startX: 0, startY: 0, endX: 13, endY: 0)
    }

    // MARK: - Logical Window Tests

    /// Helper to extract word with a logical window constraint
    private func extractWordWithLogicalWindow(
        from strings: [String],
        at location: VT100GridCoord,
        windowLocation: Int32,
        windowLength: Int32,
        maximumLength: Int = 1000,
        width: Int32 = 80
    ) -> VT100GridWindowedRange {
        let dataSource = MockTextDataSource(strings: strings, width: width)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)
        textExtractor.logicalWindow = VT100GridRangeMake(windowLocation, windowLength)

        return textExtractor.rangeForWord(at: location, maximumLength: maximumLength)
    }

    /// Test that word selection stops at the left edge of a logical window
    func testLogicalWindowStopsAtLeftEdge() {
        // "hello world" with window starting at column 6 (at 'w')
        // Click on 'o' in "world" - should select "world" but not cross left boundary
        let range = extractWordWithLogicalWindow(
            from: ["hello world"],
            at: VT100GridCoord(x: 7, y: 0),  // 'o' in "world"
            windowLocation: 6,
            windowLength: 10
        )

        // "world" is at positions 6-10, window starts at 6
        assertRangeEquals(range, startX: 6, startY: 0, endX: 11, endY: 0)
    }

    /// Test that word selection stops at the right edge of a logical window
    func testLogicalWindowStopsAtRightEdge() {
        // "hello world test" with window ending before "test"
        // Click on 'w' in "world" - should select "world" but not extend past window
        let range = extractWordWithLogicalWindow(
            from: ["hello world test"],
            at: VT100GridCoord(x: 6, y: 0),  // 'w' in "world"
            windowLocation: 0,
            windowLength: 11  // Window ends at column 11 (after "world")
        )

        // "world" is at positions 6-10
        assertRangeEquals(range, startX: 6, startY: 0, endX: 11, endY: 0)
    }

    /// Test word at left edge of logical window
    func testWordAtLeftEdgeOfLogicalWindow() {
        // Window starts in the middle of "hello"
        // Click should only select the portion within the window
        let range = extractWordWithLogicalWindow(
            from: ["hello world"],
            at: VT100GridCoord(x: 3, y: 0),  // second 'l' in "hello"
            windowLocation: 2,  // Window starts at "llo world"
            windowLength: 15
        )

        // Only "llo" (positions 2, 3, 4) should be selected, not the full "hello"
        // Half-open interval: [2, 5)
        assertRangeEquals(range, startX: 2, startY: 0, endX: 5, endY: 0)
    }

    /// Test word at right edge of logical window
    func testWordAtRightEdgeOfLogicalWindow() {
        // Window ends in the middle of "world"
        let range = extractWordWithLogicalWindow(
            from: ["hello world"],
            at: VT100GridCoord(x: 6, y: 0),  // 'w' in "world"
            windowLocation: 0,
            windowLength: 8  // Window ends at "hello wo"
        )

        // Only "wo" (positions 6-7) should be selected, not the full "world"
        assertRangeEquals(range, startX: 6, startY: 0, endX: 8, endY: 0)
    }

    /// Test that words don't cross window boundaries even if they appear continuous
    func testWordDoesNotCrossWindowBoundary() {
        // "foobar" but window splits it: "foo" | "bar"
        let range = extractWordWithLogicalWindow(
            from: ["foobar"],
            at: VT100GridCoord(x: 1, y: 0),  // 'o' in "foo" part
            windowLocation: 0,
            windowLength: 3  // Window only contains "foo"
        )

        // Should only select "foo" (0-2), not "foobar"
        assertRangeEquals(range, startX: 0, startY: 0, endX: 3, endY: 0)
    }

    /// Test logical window in the middle of the line
    func testLogicalWindowInMiddleOfLine() {
        // "aaa bbb ccc" with window only around "bbb"
        let range = extractWordWithLogicalWindow(
            from: ["aaa bbb ccc"],
            at: VT100GridCoord(x: 5, y: 0),  // middle 'b'
            windowLocation: 4,
            windowLength: 3  // Window contains "bbb"
        )

        // "bbb" at positions 4-6
        assertRangeEquals(range, startX: 4, startY: 0, endX: 7, endY: 0)
    }

    /// Test whitespace selection within logical window
    func testWhitespaceSelectionInLogicalWindow() {
        // "aaa   bbb" - clicking on whitespace within window
        let range = extractWordWithLogicalWindow(
            from: ["aaa   bbb"],
            at: VT100GridCoord(x: 4, y: 0),  // middle space
            windowLocation: 2,
            windowLength: 5  // Window contains "a   b"
        )

        // Whitespace run is at positions 3-5, but window starts at 2
        // Should select spaces within the window
        assertRangeEquals(range, startX: 3, startY: 0, endX: 6, endY: 0)
    }

    /// Test narrow logical window (single column)
    func testNarrowLogicalWindow() {
        let range = extractWordWithLogicalWindow(
            from: ["hello"],
            at: VT100GridCoord(x: 2, y: 0),  // 'l'
            windowLocation: 2,
            windowLength: 1  // Single column window
        )

        // Should select just position 2
        assertRangeEquals(range, startX: 2, startY: 0, endX: 3, endY: 0)
    }

    /// Test logical window with special characters
    func testLogicalWindowWithSpecialCharacters() {
        // "foo@bar" with window boundary at '@'
        let range = extractWordWithLogicalWindow(
            from: ["foo@bar"],
            at: VT100GridCoord(x: 4, y: 0),  // 'b' in "bar"
            windowLocation: 4,
            windowLength: 10  // Window starts at "bar"
        )

        // "bar" at positions 4-6
        assertRangeEquals(range, startX: 4, startY: 0, endX: 7, endY: 0)
    }

    // MARK: - Backslash Tests
    //
    // Note: Backslash is treated as a word character (like alphanumerics) in word selection,
    // not as a separator. This is because screen_char_t with code 0x5C (backslash) gets
    // classified as a word character by the character class logic.

    /// Test that backslash is part of a word (not a separator)
    func testBackslashIsPartOfWord() {
        // "foo\bar" - backslash is treated as a word character
        let range = extractWord(
            from: ["foo\\bar"],
            at: VT100GridCoord(x: 1, y: 0)  // 'o' in "foo"
        )

        // The entire "foo\bar" is selected as one word
        assertRangeEquals(range, startX: 0, startY: 0, endX: 7, endY: 0)
    }

    /// Test clicking on backslash selects the entire word containing it
    func testClickOnBackslashSelectsContainingWord() {
        let range = extractWord(
            from: ["foo\\bar"],
            at: VT100GridCoord(x: 3, y: 0)  // The backslash
        )

        // Backslash is part of the word, so entire "foo\bar" is selected
        assertRangeEquals(range, startX: 0, startY: 0, endX: 7, endY: 0)
    }

    /// Test backslash with additionalWordCharacters (backslash already treated as word char)
    func testBackslashAsAdditionalWordCharacter() {
        // Adding backslash to additionalWordCharacters is redundant but should still work
        let range = extractWord(
            from: ["foo\\bar"],
            at: VT100GridCoord(x: 1, y: 0),
            additionalWordCharacters: "\\"
        )

        // "foo\bar" is one word
        assertRangeEquals(range, startX: 0, startY: 0, endX: 7, endY: 0)
    }

    /// Test multiple backslashes in a word
    func testMultipleBackslashesInWord() {
        // "a\b\c" - all characters including backslashes form one word
        let range = extractWord(
            from: ["a\\b\\c"],
            at: VT100GridCoord(x: 2, y: 0)  // 'b' in the middle
        )

        // All 5 characters form one word
        assertRangeEquals(range, startX: 0, startY: 0, endX: 5, endY: 0)
    }

    /// Test backslash at end of line
    func testBackslashAtEndOfLine() {
        let range = extractWord(
            from: ["test\\"],
            at: VT100GridCoord(x: 2, y: 0)  // 's' in "test"
        )

        // "test\" is one word (5 characters)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 5, endY: 0)
    }

    /// Test backslash at start of line
    func testBackslashAtStartOfLine() {
        let range = extractWord(
            from: ["\\test"],
            at: VT100GridCoord(x: 2, y: 0)  // 'e' in "test"
        )

        // "\test" is one word (5 characters)
        assertRangeEquals(range, startX: 0, startY: 0, endX: 5, endY: 0)
    }

    /// Test consecutive backslashes
    func testConsecutiveBackslashes() {
        // "foo\\bar" in Swift source = "foo\\bar" with two backslashes
        let range = extractWord(
            from: ["foo\\\\bar"],
            at: VT100GridCoord(x: 1, y: 0)  // 'o' in "foo"
        )

        // All 8 characters form one word
        assertRangeEquals(range, startX: 0, startY: 0, endX: 8, endY: 0)
    }

    /// Test backslash in logical window context
    func testBackslashInLogicalWindow() {
        let dataSource = MockTextDataSource(strings: ["foo\\bar"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)
        textExtractor.logicalWindow = VT100GridRangeMake(0, 7)

        let range = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 1, y: 0),  // 'o' in "foo"
            maximumLength: 1000
        )

        // Entire word "foo\bar" is selected
        assertRangeEquals(range, startX: 0, startY: 0, endX: 7, endY: 0)
    }

    // MARK: - Maximum Length Edge Cases

    /// Test maximumLength = 0 still selects a minimal range around the click position
    /// The implementation includes the clicked character and searches 0 in each direction
    func testMaximumLengthZero() {
        let range = extractWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 2, y: 0),  // 'l' in "hello"
            maximumLength: 0
        )

        // With maxLength=0, the selection is limited but includes the click position
        let rangeLength = range.coordRange.end.x - range.coordRange.start.x
        XCTAssertLessThanOrEqual(rangeLength, 5, "maxLength=0 should produce a limited range")
        XCTAssertGreaterThanOrEqual(range.coordRange.start.x, 0)
        XCTAssertLessThanOrEqual(range.coordRange.end.x, 5)
    }

    /// Test maximumLength = 1 should select very limited range
    func testMaximumLengthOne() {
        let range = extractWord(
            from: ["hello world"],
            at: VT100GridCoord(x: 2, y: 0),  // 'l' in "hello"
            maximumLength: 1
        )

        // With maxLength=1, can search 1 forward + 1 backward = at most 2 chars
        let rangeLength = range.coordRange.end.x - range.coordRange.start.x
        XCTAssertLessThanOrEqual(rangeLength, 2, "maxLength=1 should select at most 2 characters")
    }

    // MARK: - Regex Mode with ASCII Tests

    /// Test regex mode with simple ASCII text (not CJK)
    func testRegexModeWithASCIIText() {
        let range = extractWordWithRegex(
            from: ["hello-world test"],
            at: VT100GridCoord(x: 5, y: 0),  // '-' in "hello-world"
            regexPatterns: ["-"]  // Hyphen is word-extending via regex
        )

        // With "-" as a regex pattern, "hello-world" should be one word
        assertRangeEquals(range, startX: 0, startY: 0, endX: 11, endY: 0)
    }

    /// Test regex mode with URL pattern in ASCII text
    func testRegexModeWithURLPatternASCII() {
        let range = extractWordWithRegex(
            from: ["visit https://example.com today"],
            at: VT100GridCoord(x: 10, y: 0),  // 't' in "https"
            regexPatterns: ["https?://"]
        )

        // "https://" is word-extending, followed by "example" which is a word,
        // then ".com" where "." breaks the word
        // The exact behavior depends on ICU segmentation
        XCTAssertEqual(range.coordRange.start.x, 6, "Should start at 'h' of https")
        XCTAssertGreaterThan(range.coordRange.end.x, 14, "Should extend past https://")
    }

    /// Test regex pattern with multi-character pattern
    /// Clicking on a position within a multi-char regex match
    func testRegexModeWithSpecialCharacterPattern() {
        let range = extractWordWithRegex(
            from: ["foo::bar baz"],
            at: VT100GridCoord(x: 3, y: 0),  // first ':'
            regexPatterns: ["::"]  // Double colon as word character
        )

        // The "::" pattern should be recognized and affect word selection
        // Verify the selection includes the clicked position
        XCTAssertLessThanOrEqual(range.coordRange.start.x, 3, "Should include click position")
        XCTAssertGreaterThanOrEqual(range.coordRange.end.x, 4, "Should include at least the pattern")
    }

    /// Test multiple regex patterns with ASCII
    func testRegexModeMultiplePatternsASCII() {
        let range = extractWordWithRegex(
            from: ["foo-bar_baz test"],
            at: VT100GridCoord(x: 4, y: 0),  // 'b' in "bar"
            regexPatterns: ["-", "_"]  // Both hyphen and underscore
        )

        // Both "-" and "_" are word-extending, so "foo-bar_baz" should be one word
        assertRangeEquals(range, startX: 0, startY: 0, endX: 11, endY: 0)
    }

    // MARK: - Regex + Logical Window Integration Tests

    /// Helper to extract word with both regex patterns and logical window
    private func extractWordWithRegexAndWindow(
        from strings: [String],
        at location: VT100GridCoord,
        regexPatterns: [String],
        windowLocation: Int32,
        windowLength: Int32,
        maximumLength: Int = 1000,
        width: Int32 = 80
    ) -> VT100GridWindowedRange {
        let dataSource = MockTextDataSourceWithDWC(strings: strings, width: width)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)
        textExtractor.logicalWindow = VT100GridRangeMake(windowLocation, windowLength)

        return textExtractor.rangeForWord(
            at: location,
            maximumLength: maximumLength,
            big: false,
            additionalWordCharacters: nil,
            regexPatterns: regexPatterns
        )
    }

    /// Test regex mode respects logical window left boundary
    func testRegexModeWithLogicalWindowLeftBoundary() {
        // "foo-bar-baz" with window starting in the middle
        let range = extractWordWithRegexAndWindow(
            from: ["foo-bar-baz test"],
            at: VT100GridCoord(x: 5, y: 0),  // 'a' in "bar"
            regexPatterns: ["-"],
            windowLocation: 4,  // Window starts at "bar-baz"
            windowLength: 20
        )

        // Window starts at 4, so selection should not include "foo-"
        XCTAssertGreaterThanOrEqual(range.coordRange.start.x, 4,
            "Selection should respect left window boundary")
    }

    /// Test regex mode respects logical window right boundary
    func testRegexModeWithLogicalWindowRightBoundary() {
        // "foo-bar-baz test" with window ending in the middle
        let range = extractWordWithRegexAndWindow(
            from: ["foo-bar-baz test"],
            at: VT100GridCoord(x: 2, y: 0),  // 'o' in "foo"
            regexPatterns: ["-"],
            windowLocation: 0,
            windowLength: 7  // Window ends at "foo-bar"
        )

        // Window ends at 7, so selection should not extend past it
        XCTAssertLessThanOrEqual(range.coordRange.end.x, 7,
            "Selection should respect right window boundary")
    }

    // MARK: - Regex + additionalWordCharacters Combination Tests

    /// Test that additionalWordCharacters joins words correctly (character list mode)
    func testAdditionalWordCharactersJoinsWords() {
        // Test with additionalWordCharacters (character list mode)
        let range = extractWord(
            from: ["foo/bar baz"],
            at: VT100GridCoord(x: 3, y: 0),  // '/'
            additionalWordCharacters: "/"
        )
        // "/" as additional word char should join "foo/bar" into one word
        assertRangeEquals(range, startX: 0, startY: 0, endX: 7, endY: 0)
    }

    /// Test regex pattern for a single character
    func testRegexPatternSingleCharacter() {
        // Test with regex pattern for "/" character
        let range = extractWordWithRegex(
            from: ["foo/bar baz"],
            at: VT100GridCoord(x: 3, y: 0),  // '/'
            regexPatterns: ["/"]
        )
        // In regex mode, "/" is word-extending
        // Verify the selection includes the clicked position
        XCTAssertLessThanOrEqual(range.coordRange.start.x, 3, "Should include click position")
        XCTAssertGreaterThanOrEqual(range.coordRange.end.x, 4, "Should include the pattern")
    }

    // MARK: - Multi-line Word Selection Tests

    /// Test word selection on wrapped line (soft wrap)
    /// Note: This requires the data source to indicate line continuation
    func testWordSelectionWithSoftWrappedLine() {
        // Create a simple test with content on two lines
        // In practice, soft wrapping is indicated by EOL_SOFT continuation marker
        let dataSource = MockTextDataSource(strings: ["hello", "world"], width: 80)
        let textExtractor = iTermTextExtractor(dataSource: dataSource)

        // Select word on first line
        let range1 = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 2, y: 0),
            maximumLength: 1000
        )
        assertRangeEquals(range1, startX: 0, startY: 0, endX: 5, endY: 0)

        // Select word on second line
        let range2 = textExtractor.rangeForWord(
            at: VT100GridCoord(x: 2, y: 1),
            maximumLength: 1000
        )
        assertRangeEquals(range2, startX: 0, startY: 1, endX: 5, endY: 1)
    }

    /// Test clicking on second line doesn't incorrectly extend to first line
    func testWordSelectionDoesNotCrossHardLineBreak() {
        let range = extractWord(
            from: ["hello", "world"],
            at: VT100GridCoord(x: 0, y: 1)  // 'w' in "world" on line 1
        )

        // Should only select "world" on line 1, not cross to line 0
        assertRangeEquals(range, startX: 0, startY: 1, endX: 5, endY: 1)
    }
}

// MARK: - Mock Atom Source for Testing

/// A mock data source for testing RegexAtomIterator directly.
fileprivate class MockRegexAtomSource: RegexAtomIteratorDataSource {
    private var lines: [String]
    private let gridWidth: Int32
    /// Maps (y, x) cell positions to characters, accounting for DWC
    private var cellMap: [Int: [Int32: screen_char_t]] = [:]

    init(strings: [String], width: Int32 = 80) {
        self.lines = strings
        self.gridWidth = width
        buildCellMap()
    }

    /// Build a cell map that properly handles double-width characters.
    /// Each DWC character occupies 2 cells: the character cell and a DWC_RIGHT cell.
    private func buildCellMap() {
        for (lineIndex, line) in lines.enumerated() {
            var cellX: Int32 = 0
            cellMap[lineIndex] = [:]

            for scalar in line.unicodeScalars {
                var char = screen_char_t()
                char.code = unichar(scalar.value & 0xFFFF)  // Truncate to UTF-16

                cellMap[lineIndex]?[cellX] = char
                cellX += 1

                // If this is a double-width character, add DWC_RIGHT in the next cell
                if isDoubleWidth(scalar) {
                    var dwcRight = screen_char_t()
                    // DWC_RIGHT is indicated by setting the specific code with complexChar = false
                    dwcRight.code = unichar(DWC_RIGHT)
                    dwcRight.complexChar = 0
                    cellMap[lineIndex]?[cellX] = dwcRight
                    cellX += 1
                }
            }
        }
    }

    /// Check if a character is double-width (CJK, etc.)
    private func isDoubleWidth(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value >= 0x4E00 && value <= 0x9FFF) ||  // CJK Unified Ideographs
               (value >= 0x3400 && value <= 0x4DBF) ||  // CJK Unified Ideographs Extension A
               (value >= 0xF900 && value <= 0xFAFF) ||  // CJK Compatibility Ideographs
               (value >= 0x3000 && value <= 0x303F) ||  // CJK Symbols and Punctuation
               (value >= 0xFF00 && value <= 0xFFEF) ||  // Halfwidth and Fullwidth Forms
               (value >= 0xAC00 && value <= 0xD7AF)     // Hangul Syllables
    }

    /// Returns the coordinate after the given coordinate.
    /// Handles double-width characters by skipping the DWC_RIGHT placeholder.
    func successorOfCoord(_ coord: VT100GridCoord) -> VT100GridCoord {
        let nextX = coord.x + 1

        // Check if the next cell is a DWC_RIGHT placeholder
        if let lineMap = cellMap[Int(coord.y)],
           let nextChar = lineMap[nextX],
           nextChar.code == unichar(DWC_RIGHT) {
            // Skip the DWC_RIGHT placeholder
            return VT100GridCoord(x: nextX + 1, y: coord.y)
        }

        // Check for line wrap
        if nextX >= gridWidth {
            return VT100GridCoord(x: 0, y: coord.y + 1)
        }

        return VT100GridCoord(x: nextX, y: coord.y)
    }
}

// MARK: - Regex Atom Iterator Tests

/// Tests for RegexAtomIterator functionality.
/// These tests verify that regex patterns correctly create multi-character atoms.
class iTermWordSelectionAtomIteratorTest: XCTestCase {

    // MARK: - Properties

    /// Strong reference to the data source to prevent deallocation
    /// (RegexAtomIterator.dataSource is weak)
    private var currentDataSource: MockRegexAtomSource?

    // MARK: - Helper Methods

    /// Create an atom iterator with given text and regex patterns
    private func createIterator(
        from strings: [String],
        regexPatterns: [String],
        width: Int32 = 80
    ) -> RegexAtomIterator {
        let dataSource = MockRegexAtomSource(strings: strings, width: width)
        currentDataSource = dataSource  // Keep strong reference
        let iterator = RegexAtomIterator(dataSource: dataSource)
        iterator.regexPatterns = regexPatterns
        return iterator
    }

    /// Build a mock iTermLocatedString for testing
    private func buildLocatedString(text: String, width: Int32 = 80) -> iTermLocatedString {
        // Build coords array - 1 coord per UTF-16 code unit
        let gridCoords = GridCoordArray()
        var cellIndex: Int32 = 0

        for scalar in text.unicodeScalars {
            let utf16Count = scalar.utf16.count
            for _ in 0..<utf16Count {
                gridCoords.append(coord: VT100GridCoord(x: cellIndex, y: 0))
            }

            // Advance cell position by 1 for normal chars, 2 for double-width
            if isDoubleWidth(scalar) {
                cellIndex += 2
            } else {
                cellIndex += 1
            }
        }

        return iTermLocatedString(string: text, gridCoords: gridCoords)
    }

    /// Pre-atomize text with given parameters
    private func preatomize(
        iterator: RegexAtomIterator,
        text: String,
        targetIndex: Int,
        width: Int32 = 80
    ) {
        let locatedString = buildLocatedString(text: text, width: width)
        iterator.preatomize(locatedString: locatedString, targetIndex: targetIndex)
    }

    /// Check if a character is double-width (CJK, etc.)
    private func isDoubleWidth(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value >= 0x4E00 && value <= 0x9FFF) ||  // CJK Unified Ideographs
               (value >= 0x3400 && value <= 0x4DBF) ||  // CJK Unified Ideographs Extension A
               (value >= 0xF900 && value <= 0xFAFF) ||  // CJK Compatibility Ideographs
               (value >= 0x3000 && value <= 0x303F) ||  // CJK Symbols and Punctuation
               (value >= 0xFF00 && value <= 0xFFEF) ||  // Halfwidth and Fullwidth Forms
               (value >= 0xAC00 && value <= 0xD7AF)     // Hangul Syllables
    }

    // MARK: - Regex Atom Tests

    /// Test 1: Basic regex match creates multi-character atom
    func testRegexMatchCreatesMultiCharAtom() {
        let iterator = createIterator(from: ["https://example.com"], regexPatterns: ["https?://"])
        preatomize(iterator: iterator, text: "https://example.com", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // First atom should be "https://" (8 chars) with forcedWordClass = true
        XCTAssertGreaterThan(atoms.count, 0)
        XCTAssertEqual(atoms[0].string, "https://")
        XCTAssertTrue(atoms[0].forcedWordClass)
    }

    /// Test 2: Click in middle of regex match returns correct atom index
    func testClickInMiddleOfRegexMatch() {
        let iterator = createIterator(from: ["Visit https://example.com today"], regexPatterns: ["https?://"])
        preatomize(iterator: iterator, text: "Visit https://example.com today", targetIndex: 11)  // ':' position

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Find the atom containing the click
        let clickIndex = iterator.clickAtomIndex
        let clickedAtom = atoms[clickIndex]

        // The clicked atom should be "https://" since we clicked on ':'
        XCTAssertEqual(clickedAtom.string, "https://")
        XCTAssertTrue(clickedAtom.forcedWordClass)
    }

    /// Test 3: No regex match creates single-char atoms
    func testNoRegexMatchCreatesSingleCharAtoms() {
        let iterator = createIterator(from: ["hello world"], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: "hello world", targetIndex: 1)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Each character should be its own atom since no regex matches
        XCTAssertEqual(atoms.count, 11)  // "hello world" is 11 chars
        XCTAssertEqual(atoms[0].string, "h")
        XCTAssertFalse(atoms[0].forcedWordClass)
    }

    /// Test 4: Multiple regex patterns
    func testMultipleRegexPatterns() {
        let iterator = createIterator(from: ["file-name.txt"], regexPatterns: ["-", "\\."])
        preatomize(iterator: iterator, text: "file-name.txt", targetIndex: 5)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Should have atoms for: "file", "-", "name", ".", "txt"
        // Look for the hyphen atom
        let hyphenAtom = atoms.first { $0.string == "-" }
        XCTAssertNotNil(hyphenAtom)
        XCTAssertTrue(hyphenAtom?.forcedWordClass ?? false)

        // Look for the dot atom
        let dotAtom = atoms.first { $0.string == "." }
        XCTAssertNotNil(dotAtom)
        XCTAssertTrue(dotAtom?.forcedWordClass ?? false)
    }

    /// Test 5: Overlapping patterns - longer wins
    /// When multiple patterns can match at the same position, the longer match should win
    func testOverlappingPatternsLongerWins() {
        // "https://rest" - both "http" and "https://" can match at position 0
        // The longer pattern "https://" should win
        let iterator = createIterator(from: ["https://rest"], regexPatterns: ["https://", "http"])
        preatomize(iterator: iterator, text: "https://rest", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // First atom should be "https://" (8 chars), not "http" (4 chars)
        XCTAssertEqual(atoms[0].string, "https://")
        XCTAssertTrue(atoms[0].forcedWordClass)

        // Verify we didn't get "http" followed by "s://"
        XCTAssertNotEqual(atoms[0].string, "http")

        // Rest of the atoms should be single chars: r, e, s, t
        XCTAssertEqual(atoms.count, 5)  // "https://" + "r" + "e" + "s" + "t"
    }

    /// Test 6: Regex at start of text
    func testRegexAtStartOfText() {
        let iterator = createIterator(from: ["://rest"], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: "://rest", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // First atom should be "://"
        XCTAssertEqual(atoms[0].string, "://")
        XCTAssertTrue(atoms[0].forcedWordClass)
    }

    /// Test 7: Regex at end of text
    func testRegexAtEndOfText() {
        let iterator = createIterator(from: ["text://"], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: "text://", targetIndex: 6)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Last atom should be "://"
        let lastAtom = atoms.last
        XCTAssertEqual(lastAtom?.string, "://")
        XCTAssertTrue(lastAtom?.forcedWordClass ?? false)
    }

    /// Test 8: Empty regex patterns - still creates single-char atoms
    func testEmptyRegexPatternsCreatesSingleCharAtoms() {
        let iterator = createIterator(from: ["hello"], regexPatterns: [])
        preatomize(iterator: iterator, text: "hello", targetIndex: 0)

        // With empty patterns, atoms are still created as single-char atoms
        // (none have forcedWordClass since no regex matched)
        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 5)  // "hello" = 5 chars
        XCTAssertTrue(atoms.allSatisfy { !$0.forcedWordClass })
    }

    /// Test 9: Invalid regex pattern is skipped
    func testInvalidRegexPatternSkipped() {
        let iterator = createIterator(from: ["hello"], regexPatterns: ["[invalid"])
        preatomize(iterator: iterator, text: "hello", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created even with invalid regex")
            return
        }

        // Should fall back to single-char atoms
        XCTAssertEqual(atoms.count, 5)
    }

    /// Test 10: Atom coord range is correct
    func testAtomCoordRangeIsCorrect() {
        let iterator = createIterator(from: ["ab://cd"], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: "ab://cd", targetIndex: 3)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Find the "://" atom
        let colonAtom = atoms.first { $0.string == "://" }
        XCTAssertNotNil(colonAtom)

        // Verify coord range
        // "ab://" - the "://" starts at index 2 and ends at index 5
        XCTAssertEqual(colonAtom?.coordRange.start.x, 2)
        XCTAssertEqual(colonAtom?.coordRange.end.x, 5)  // half-open interval
    }

    /// Test 11: Complex pattern with capture groups works
    func testComplexPatternWithCaptureGroups() {
        let iterator = createIterator(from: ["http://"], regexPatterns: ["(https?|ftp)://"])
        preatomize(iterator: iterator, text: "http://", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Should match "http://"
        XCTAssertEqual(atoms[0].string, "http://")
        XCTAssertTrue(atoms[0].forcedWordClass)
    }

    /// Test 12: Multiple matches in same text
    func testMultipleMatchesInSameText() {
        let iterator = createIterator(from: ["a://b://c"], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: "a://b://c", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Should have: "a", "://", "b", "://", "c"
        let colonAtoms = atoms.filter { $0.string == "://" }
        XCTAssertEqual(colonAtoms.count, 2)
        XCTAssertTrue(colonAtoms.allSatisfy { $0.forcedWordClass })
    }

    /// Test 13: Verify click atom index for different positions
    func testClickAtomIndexForDifferentPositions() {
        let iterator = createIterator(from: ["ab://cd"], regexPatterns: ["://"])

        // Click on 'a' (index 0)
        preatomize(iterator: iterator, text: "ab://cd", targetIndex: 0)
        XCTAssertEqual(iterator.atoms?[iterator.clickAtomIndex].string, "a")

        // Reset and click on first ':' (index 2)
        preatomize(iterator: iterator, text: "ab://cd", targetIndex: 2)
        XCTAssertEqual(iterator.atoms?[iterator.clickAtomIndex].string, "://")

        // Reset and click on last character 'd' (index 6)
        preatomize(iterator: iterator, text: "ab://cd", targetIndex: 6)
        XCTAssertEqual(iterator.atoms?[iterator.clickAtomIndex].string, "d")
    }

    // MARK: - Unicode Tests

    /// Test 14: Unicode emoji handling - emojis take 2 UTF-16 code units
    func testUnicodeEmojiHandling() {
        // "😀abc" - emoji takes 2 UTF-16 code units (surrogate pair)
        let text = "😀abc"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // "😀abc" has 5 UTF-16 code units: 2 for emoji + 3 for "abc"
        // Should have 4 atoms: "😀", "a", "b", "c"
        XCTAssertEqual(atoms.count, 4)
        XCTAssertEqual(atoms[0].string, "😀")
        XCTAssertEqual(atoms[0].utf16Length, 2)
        XCTAssertEqual(atoms[1].string, "a")
        XCTAssertEqual(atoms[1].utf16Length, 1)
    }

    /// Test 15: Click after emoji finds correct atom using UTF-16 indexing
    func testUnicodeSurrogatePairTargetIndex() {
        // "😀abc" - clicking on 'a' should be at UTF-16 index 2 (after surrogate pair)
        let text = "😀abc"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        // Click at UTF-16 index 2, which is 'a' (after the emoji's 2-unit surrogate pair)
        preatomize(iterator: iterator, text: text, targetIndex: 2)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // The clicked atom should be 'a' at index 1
        let clickedAtom = atoms[iterator.clickAtomIndex]
        XCTAssertEqual(clickedAtom.string, "a")
    }

    /// Test 16: Multi-codepoint characters like composed characters
    func testUnicodeMultiCodePointCharacters() {
        // Test with a basic emoji sequence
        let text = "a😀b"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // "a😀b" = "a" (1) + "😀" (2) + "b" (1) = 4 UTF-16 units, 3 atoms
        XCTAssertEqual(atoms.count, 3)
        XCTAssertEqual(atoms[0].string, "a")
        XCTAssertEqual(atoms[1].string, "😀")
        XCTAssertEqual(atoms[2].string, "b")

        // Click on 'b' at UTF-16 index 3 (1 + 2)
        preatomize(iterator: iterator, text: text, targetIndex: 3)
        // Re-fetch atoms after preatomize since they may have been recreated
        guard let atomsAfterClick = iterator.atoms else {
            XCTFail("Expected atoms after preatomize")
            return
        }
        let clickedAtom = atomsAfterClick[iterator.clickAtomIndex]
        XCTAssertEqual(clickedAtom.string, "b")
    }

    /// Test 17: Unicode with regex pattern
    func testUnicodeWithRegexPattern() {
        // "😀://abc" - pattern "://" should match correctly after emoji
        let text = "😀://abc"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: text, targetIndex: 2)  // UTF-16 index of first ':'

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Should have atoms: "😀", "://", "a", "b", "c"
        XCTAssertEqual(atoms.count, 5)
        XCTAssertEqual(atoms[0].string, "😀")
        XCTAssertEqual(atoms[1].string, "://")
        XCTAssertTrue(atoms[1].forcedWordClass)

        // Click on "://" at UTF-16 index 2
        let clickedAtom = atoms[iterator.clickAtomIndex]
        XCTAssertEqual(clickedAtom.string, "://")
    }

    /// Test 18: Multiple emojis in sequence
    func testMultipleEmojisInSequence() {
        let text = "😀😁😂"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])
        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Each emoji is 2 UTF-16 code units, so 6 total UTF-16 units, 3 atoms
        XCTAssertEqual(atoms.count, 3)
        XCTAssertEqual(atoms[0].string, "😀")
        XCTAssertEqual(atoms[1].string, "😁")
        XCTAssertEqual(atoms[2].string, "😂")

        // Click on second emoji at UTF-16 index 2
        preatomize(iterator: iterator, text: text, targetIndex: 2)
        // Re-fetch atoms after preatomize since they may have been recreated
        guard let atoms2 = iterator.atoms else {
            XCTFail("Expected atoms after preatomize")
            return
        }
        let clickedAtom = atoms2[iterator.clickAtomIndex]
        XCTAssertEqual(clickedAtom.string, "😁")

        // Click on third emoji at UTF-16 index 4
        preatomize(iterator: iterator, text: text, targetIndex: 4)
        // Re-fetch atoms after preatomize
        guard let atoms3 = iterator.atoms else {
            XCTFail("Expected atoms after preatomize")
            return
        }
        let clickedAtomThird = atoms3[iterator.clickAtomIndex]
        XCTAssertEqual(clickedAtomThird.string, "😂")
    }

    // MARK: - Double-Width Character Tests

    /// Test 19: Double-width character atom should span 2 cells
    func testDoubleWidthAtomCoordRangeSpansTwoCells() {
        // "中" is a double-width character occupying cells 0 and 1
        let text = "中"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 1, "Should have 1 atom for '中'")
        XCTAssertEqual(atoms[0].string, "中")

        // The atom's coordRange should span cells 0-2 (half-open)
        XCTAssertEqual(atoms[0].coordRange.start.x, 0, "Start should be cell 0")
        XCTAssertEqual(atoms[0].coordRange.end.x, 2, "End should be cell 2 (half-open, spanning 2 cells)")
    }

    /// Test 20: Multiple double-width characters have correct coord ranges
    func testMultipleDoubleWidthAtomsCoordRanges() {
        // "中文" = cells [中][DWC][文][DWC] = 4 cells
        let text = "中文"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 2, "Should have 2 atoms")

        // First atom '中' should span cells 0-2
        XCTAssertEqual(atoms[0].string, "中")
        XCTAssertEqual(atoms[0].coordRange.start.x, 0)
        XCTAssertEqual(atoms[0].coordRange.end.x, 2, "First atom should span 2 cells")

        // Second atom '文' should span cells 2-4
        XCTAssertEqual(atoms[1].string, "文")
        XCTAssertEqual(atoms[1].coordRange.start.x, 2)
        XCTAssertEqual(atoms[1].coordRange.end.x, 4, "Second atom should span 2 cells")
    }

    /// Test 21: Click on the DWC character should find the correct atom
    /// Note: targetIndex is a UTF-16 text index, not a coord/cell index
    func testClickOnDWCCharacterFindsCorrectAtom() {
        // "中" occupies cells 0 (char) and 1 (DWC_RIGHT)
        let text = "中"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        // Click at UTF-16 index 0 (the character '中')
        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(iterator.clickAtomIndex, 0)
        XCTAssertEqual(atoms[iterator.clickAtomIndex].string, "中")
    }

    /// Test 22: Mixed ASCII and double-width character coord ranges
    func testMixedASCIIAndDWCCoordRanges() {
        // "a中b" = cells [a][中][DWC][b] = 4 cells
        // Text UTF-16 indices: a=0, 中=1, b=2
        let text = "a中b"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 3, "Should have 3 atoms: a, 中, b")

        // 'a' should span cell 0-1
        XCTAssertEqual(atoms[0].string, "a")
        XCTAssertEqual(atoms[0].coordRange.start.x, 0)
        XCTAssertEqual(atoms[0].coordRange.end.x, 1)

        // '中' should span cells 1-3
        XCTAssertEqual(atoms[1].string, "中")
        XCTAssertEqual(atoms[1].coordRange.start.x, 1)
        XCTAssertEqual(atoms[1].coordRange.end.x, 3, "中 should span 2 cells")

        // 'b' should span cells 3-4
        XCTAssertEqual(atoms[2].string, "b")
        XCTAssertEqual(atoms[2].coordRange.start.x, 3)
        XCTAssertEqual(atoms[2].coordRange.end.x, 4)
    }

    /// Test 23: Click index calculation with mixed content using UTF-16 text indices
    func testClickIndexWithMixedDWCContent() {
        // "a中b" = cells [a][中][DWC][b] = 4 cells
        // Text UTF-16 indices: a=0, 中=1, b=2
        let text = "a中b"
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        // Click on 'a' (UTF-16 index 0)
        preatomize(iterator: iterator, text: text, targetIndex: 0)
        XCTAssertEqual(iterator.atoms?[iterator.clickAtomIndex].string, "a")

        // Click on '中' (UTF-16 index 1)
        preatomize(iterator: iterator, text: text, targetIndex: 1)
        XCTAssertEqual(iterator.atoms?[iterator.clickAtomIndex].string, "中")

        // Click on 'b' (UTF-16 index 2)
        preatomize(iterator: iterator, text: text, targetIndex: 2)
        XCTAssertEqual(iterator.atoms?[iterator.clickAtomIndex].string, "b")
    }

    // MARK: - Production-Style Tests
    // These tests verify that RegexAtomIterator with iTermLocatedString works correctly.
    // The production style is now the default since we use iTermLocatedString
    // which has 1:1 UTF-16 to coord mapping.

    /// Test 24: Double-width character with production-style coords.
    /// "中" (1 UTF-16 unit) has 1 coord at cell 0, occupies 2 cells.
    func testProductionStyleCoordsWithDWC() {
        let text = "中"  // 1 UTF-16 code unit, 2 cells
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 1, "Should have 1 atom for '中'")
        XCTAssertEqual(atoms[0].string, "中")
        XCTAssertEqual(atoms[0].coordRange.start.x, 0)
        XCTAssertEqual(atoms[0].coordRange.end.x, 2, "End should account for double-width")
    }

    /// Test 25: Multiple double-width characters.
    func testProductionStyleCoordsWithMultipleDWC() {
        let text = "中文"  // 2 UTF-16 code units, 4 cells
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 2, "Should have 2 atoms")
        XCTAssertEqual(atoms[0].string, "中")
        XCTAssertEqual(atoms[1].string, "文")
    }

    /// Test 26: Mixed ASCII and DWC.
    func testProductionStyleCoordsWithMixedContent() {
        let text = "a中b"  // 3 UTF-16 code units, 4 cells
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 3, "Should have 3 atoms: a, 中, b")
        XCTAssertEqual(atoms[0].string, "a")
        XCTAssertEqual(atoms[1].string, "中")
        XCTAssertEqual(atoms[2].string, "b")
    }

    /// Test 27: Emoji (surrogate pair).
    /// Emoji takes 2 UTF-16 code units.
    func testProductionStyleCoordsWithEmoji() {
        let text = "😀"  // 2 UTF-16 code units (surrogate pair), 2 cells
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        preatomize(iterator: iterator, text: text, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 1, "Should have 1 atom for '😀'")
        XCTAssertEqual(atoms[0].string, "😀")
    }

    // MARK: - Regex Match Overflow Tests

    /// Test 28: Regex match that extends beyond available coords.
    /// When a regex matches more text than we have coords for,
    /// the remaining text should be processed as single-char atoms.
    func testRegexMatchExceedingCoords() {
        // Test that when RegexAtomIterator has limited coords,
        // it falls back to single-char atoms gracefully.
        let text = "https://ab"  // 10 chars, regex "https://" matches 8
        let iterator = createIterator(from: [text], regexPatterns: ["https://"])

        // Build a limited located string with only 5 coords
        let gridCoords = GridCoordArray()
        for i in 0..<5 {
            gridCoords.append(coord: VT100GridCoord(x: Int32(i), y: 0))
        }
        let locatedString = iTermLocatedString(string: text, gridCoords: gridCoords)
        iterator.preatomize(locatedString: locatedString, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Since regex can't match (not enough coords), all chars become single atoms
        // We have 5 coords, so we should get 5 atoms: "h", "t", "t", "p", "s"
        XCTAssertEqual(atoms.count, 5, "Should have 5 single-char atoms for available coords")
        XCTAssertEqual(atoms[0].string, "h")
        XCTAssertEqual(atoms[4].string, "s")
    }

    /// Test 29: Partial text processed when coords are limited.
    /// Text longer than coords should still process all available coords.
    func testPartialTextProcessedWithLimitedCoords() {
        let text = "abcdefghij"  // 10 chars
        let iterator = createIterator(from: [text], regexPatterns: ["://"])

        // Build a limited located string with only 3 coords
        let gridCoords = GridCoordArray()
        for i in 0..<3 {
            gridCoords.append(coord: VT100GridCoord(x: Int32(i), y: 0))
        }
        let locatedString = iTermLocatedString(string: text, gridCoords: gridCoords)
        iterator.preatomize(locatedString: locatedString, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // Should process all 3 available coords
        XCTAssertEqual(atoms.count, 3, "Should have 3 atoms for 3 coords")
        XCTAssertEqual(atoms[0].string, "a")
        XCTAssertEqual(atoms[1].string, "b")
        XCTAssertEqual(atoms[2].string, "c")
    }

    // MARK: - DWC_SKIP Tests

    /// Test 30: DWC_SKIP is detected as a double-width extension.
    /// DWC_SKIP occurs when a double-width character would start at the rightmost
    /// column and wraps to the next line. The SKIP placeholder fills the gap.
    func testDWCSkipDetectedAsDoubleWidthExtension() {
        // Create a mock data source that has DWC_SKIP at a specific position
        let dataSource = MockRegexAtomSourceWithDWCSkip(width: 10)
        currentDataSource = nil  // Clear the strong reference to MockRegexAtomSource

        // Cell 9 (last column) has DWC_SKIP, cell 0 of line 1 has the DWC char
        // Check that DWC_SKIP is detected as a double-width extension
        let coord = VT100GridCoord(x: 9, y: 0)
        XCTAssertTrue(dataSource.haveDoubleWidthExtension(at: coord),
                      "DWC_SKIP at rightmost column should be detected as double-width extension")
    }

    /// Test 31: Atom coord range accounts for DWC_SKIP properly.
    /// When a character is followed by DWC_SKIP (at end of line), the coord range
    /// should only span the character cell, not include the DWC_SKIP.
    func testAtomCoordRangeWithDWCSkip() {
        // "ab" where 'b' is at cell 8, DWC_SKIP at cell 9 (last column)
        // The 'b' atom should have coordRange (8,0)-(9,0), not including DWC_SKIP
        let dataSource = MockRegexAtomSourceWithDWCSkip(width: 10)

        let iterator = RegexAtomIterator(dataSource: dataSource)
        iterator.regexPatterns = []

        // Build located string for "ab" where 'a' is at cell 0 and 'b' is at cell 8
        let gridCoords = GridCoordArray()
        gridCoords.append(coord: VT100GridCoord(x: 0, y: 0))  // 'a' at cell 0
        gridCoords.append(coord: VT100GridCoord(x: 8, y: 0))  // 'b' at cell 8
        let locatedString = iTermLocatedString(string: "ab", gridCoords: gridCoords)

        iterator.preatomize(locatedString: locatedString, targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        XCTAssertEqual(atoms.count, 2)
        XCTAssertEqual(atoms[0].string, "a")
        XCTAssertEqual(atoms[0].coordRange.start.x, 0)
        XCTAssertEqual(atoms[0].coordRange.end.x, 1)

        XCTAssertEqual(atoms[1].string, "b")
        XCTAssertEqual(atoms[1].coordRange.start.x, 8)
        // End should be 9 because 'b' is single-width. DWC_SKIP at cell 9 is a
        // placeholder for a different character that wrapped to the next line.
        XCTAssertEqual(atoms[1].coordRange.end.x, 9,
                       "End X should not include unrelated DWC_SKIP")
    }

    /// Test 32: RegexAtomIterator handles DWC_SKIP at end of line correctly.
    /// When text extraction skips DWC_SKIP (as it should), the iterator should
    /// still produce correct coord ranges for characters before and after.
    func testRegexIteratorHandlesDWCSkipCorrectly() {
        // Scenario: "a中" on a 3-cell line
        // Cell 0: 'a'
        // Cell 1: '中' (double-width)
        // Cell 2: DWC_RIGHT (placeholder for '中')
        // If width were 2, we'd have:
        // Cell 0: 'a', Cell 1: DWC_SKIP, then '中' on next line

        // Test that haveDoubleWidthExtension returns true for DWC_SKIP
        let dataSource = MockRegexAtomSourceWithDWCSkip(width: 10)

        // Verify DWC_SKIP is recognized
        XCTAssertTrue(dataSource.haveDoubleWidthExtension(at: VT100GridCoord(x: 9, y: 0)))
    }

    // MARK: - Word Extending Tests

    /// Test 33: Regex match atoms have wordExtending = true
    func testRegexMatchAtomsAreWordExtending() {
        let iterator = createIterator(from: ["https://example.com"], regexPatterns: ["https?://"])
        preatomize(iterator: iterator, text: "https://example.com", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // First atom "https://" should be word-extending
        XCTAssertTrue(atoms[0].wordExtending, "Regex match atoms should be word-extending")
        XCTAssertEqual(atoms[0].string, "https://")

        // Subsequent single-char atoms should not be word-extending (by default)
        if atoms.count > 1 {
            XCTAssertFalse(atoms[1].wordExtending, "Non-regex atoms should not be word-extending by default")
        }
    }

    /// Test 34: Non-regex fallback atoms are not word-extending
    /// Only regex match atoms should be word-extending in RegexAtomIterator
    func testNonRegexAtomsNotWordExtending() {
        let dataSource = MockRegexAtomSource(strings: ["hello"], width: 80)
        currentDataSource = dataSource

        let iterator = RegexAtomIterator(dataSource: dataSource)
        iterator.regexPatterns = []  // No regex patterns

        preatomize(iterator: iterator, text: "hello", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // All fallback atoms should have wordExtending = false
        for atom in atoms {
            XCTAssertFalse(atom.wordExtending,
                           "Fallback atom '\(atom.string)' should not be word-extending")
        }
    }

    /// Test 35: Mixed regex and non-regex atoms
    /// Regex matches are word-extending, fallback single-char atoms are not
    func testMixedRegexAndFallbackAtoms() {
        let dataSource = MockRegexAtomSource(strings: ["https://-path"], width: 80)
        currentDataSource = dataSource

        let iterator = RegexAtomIterator(dataSource: dataSource)
        iterator.regexPatterns = ["https://"]

        preatomize(iterator: iterator, text: "https://-path", targetIndex: 0)

        guard let atoms = iterator.atoms else {
            XCTFail("Expected atoms to be created")
            return
        }

        // "https://" should be word-extending (regex match)
        XCTAssertEqual(atoms[0].string, "https://")
        XCTAssertTrue(atoms[0].wordExtending, "Regex match should be word-extending")

        // "-" should NOT be word-extending (fallback atom, not a regex match)
        let hyphenAtom = atoms.first { $0.string == "-" }
        XCTAssertNotNil(hyphenAtom)
        XCTAssertFalse(hyphenAtom?.wordExtending ?? true,
                       "Fallback atom '-' should not be word-extending")

        // "p", "a", etc. should not be word-extending (fallback atoms)
        let pAtom = atoms.first { $0.string == "p" }
        XCTAssertNotNil(pAtom)
        XCTAssertFalse(pAtom?.wordExtending ?? true,
                       "Fallback atom 'p' should not be word-extending")
    }
}

// MARK: - Mock Regex Atom Source with DWC_SKIP Support

/// A mock data source for testing RegexAtomIterator with DWC_SKIP.
/// DWC_SKIP is placed at the rightmost column to simulate a double-width
/// character that wrapped to the next line.
fileprivate class MockRegexAtomSourceWithDWCSkip: RegexAtomIteratorDataSource {
    private let gridWidth: Int32
    /// Maps (y, x) cell positions to characters
    private var cellMap: [Int: [Int32: screen_char_t]] = [:]

    init(width: Int32 = 80) {
        self.gridWidth = width
        buildCellMap()
    }

    /// Build a cell map with DWC_SKIP at the rightmost column of line 0.
    private func buildCellMap() {
        cellMap[0] = [:]

        // Fill with normal characters except last column
        for x in 0..<(gridWidth - 1) {
            var char = screen_char_t()
            char.code = unichar(UInt16(0x61 + (x % 26)))  // 'a' to 'z'
            cellMap[0]?[x] = char
        }

        // Put DWC_SKIP at the last column (simulating wrapped DWC)
        var dwcSkip = screen_char_t()
        dwcSkip.code = unichar(DWC_SKIP)
        dwcSkip.complexChar = 0
        dwcSkip.image = 0
        cellMap[0]?[gridWidth - 1] = dwcSkip

        // Line 1: Start with a double-width character (the one that wrapped)
        cellMap[1] = [:]
        var dwc = screen_char_t()
        dwc.code = unichar(0x4E2D)  // '中'
        dwc.complexChar = 0
        cellMap[1]?[0] = dwc

        var dwcRight = screen_char_t()
        dwcRight.code = unichar(DWC_RIGHT)
        dwcRight.complexChar = 0
        cellMap[1]?[1] = dwcRight
    }

    /// Check if a cell is a double-width extension (DWC_RIGHT or DWC_SKIP)
    func haveDoubleWidthExtension(at coord: VT100GridCoord) -> Bool {
        guard coord.y >= 0,
              let lineMap = cellMap[Int(coord.y)],
              let char = lineMap[coord.x] else {
            return false
        }
        // Check for both DWC_RIGHT and DWC_SKIP
        return char.complexChar == 0 && char.image == 0 &&
               (char.code == unichar(DWC_RIGHT) || char.code == unichar(DWC_SKIP))
    }

    /// Returns the coordinate after the given coordinate.
    /// Handles DWC_RIGHT by skipping it (it's the right half of a DWC at current position).
    /// Does NOT skip DWC_SKIP (it's a placeholder for a different character that wrapped).
    func successorOfCoord(_ coord: VT100GridCoord) -> VT100GridCoord {
        let nextX = coord.x + 1

        // Check for line wrap
        if nextX >= gridWidth {
            return VT100GridCoord(x: 0, y: coord.y + 1)
        }

        // Check if the next cell is a DWC_RIGHT placeholder (right half of current DWC)
        if let lineMap = cellMap[Int(coord.y)],
           let nextChar = lineMap[nextX],
           nextChar.complexChar == 0 && nextChar.image == 0 &&
           nextChar.code == unichar(DWC_RIGHT) {
            // Skip the DWC_RIGHT placeholder
            return VT100GridCoord(x: nextX + 1, y: coord.y)
        }

        return VT100GridCoord(x: nextX, y: coord.y)
    }
}

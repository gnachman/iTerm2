//
//  ExtendURLSearchResultsTests.swift
//  ModernTests
//
//  Tests for PTYTextView.extendURLSearchResultsAcrossSoftBoundaries
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Mock Text Data Source with Divider Support

/// A mock text data source that can include column dividers for testing soft boundary detection.
fileprivate class MockDataSourceWithDividers: NSObject, iTermTextDataSource {
    private var lines: [ScreenCharArray]
    private let gridWidth: Int32
    private let gridHeight: Int32

    /// Creates a mock data source with the given lines of text.
    /// Use "|" or "│" in your strings to represent dividers. Lines whose index is in
    /// `softWrappedLineIndices` end with EOL_SOFT (i.e. they wrap onto the next line);
    /// all other lines end with a hard newline.
    init(strings: [String], width: Int32 = 80, softWrappedLineIndices: Set<Int> = [],
         imageColumnsByLine: [Int: Set<Int>] = [:],
         complexColumnsByLine: [Int: [Int: [unichar]]] = [:]) {
        self.gridWidth = width
        self.gridHeight = Int32(strings.count)
        self.lines = []
        super.init()

        for (index, string) in strings.enumerated() {
            let soft = softWrappedLineIndices.contains(index)
            let sca = createScreenCharArray(from: string, width: width, softWrapped: soft,
                                            imageColumns: imageColumnsByLine[index] ?? [],
                                            complexColumns: complexColumnsByLine[index] ?? [:])
            lines.append(sca)
        }
    }

    private func createScreenCharArray(from string: String, width: Int32, softWrapped: Bool,
                                       imageColumns: Set<Int>,
                                       complexColumns: [Int: [unichar]]) -> ScreenCharArray {
        var buffer = [screen_char_t](repeating: screen_char_t(), count: Int(width) + 1)

        for (index, char) in string.unicodeScalars.enumerated() {
            guard index < Int(width) else { break }
            buffer[index].code = unichar(char.value)
            buffer[index].complexChar = 0
            if imageColumns.contains(index) {
                // An image cell: code is a url-legal codepoint here, but image==1 must still
                // terminate the URL run.
                buffer[index].image = 1
            }
            if let codePoints = complexColumns[index], let base = codePoints.first {
                // A complex (composed grapheme / non-BMP) cell: seed with the base code point, then
                // append the rest so the cell decodes to the full grapheme via ScreenCharToStr.
                var cell = buffer[index]
                cell.code = base
                cell.complexChar = 0
                for codePoint in codePoints.dropFirst() {
                    AppendToChar(&cell, codePoint)
                }
                buffer[index] = cell
            }
        }

        var continuation = screen_char_t()
        continuation.code = unichar(softWrapped ? EOL_SOFT : EOL_HARD)

        return ScreenCharArray(
            copyOfLine: buffer,
            length: width,
            continuation: continuation
        )
    }

    // MARK: - iTermTextDataSource

    func width() -> Int32 { gridWidth }
    func height() -> Int32 { gridHeight }
    func numberOfLines() -> Int32 { Int32(lines.count) }
    func totalScrollbackOverflow() -> Int64 { 0 }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        guard line >= 0, line < lines.count else {
            return ScreenCharArray.emptyLine(ofLength: gridWidth)
        }
        return lines[Int(line)]
    }

    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        return screenCharArray(forLine: index)
    }

    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? { nil }

    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        return block(screenCharArray(forLine: line))
    }

    func date(forLine line: Int32) -> Date? { nil }

    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? { nil }

    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata {
        return iTermImmutableMetadataDefault()
    }

    func isFirstLine(ofBlock lineNumber: Int32) -> Bool { false }
}

// MARK: - Tests

class ExtendURLSearchResultsTests: XCTestCase {

    /// Test that a URL ending at a soft boundary (divider) is extended to include continuation.
    func testURLExtendedAcrossDivider() {
        // Create a mock with a vertical divider at column 19
        // URL starts at column 0 and wraps at the divider
        // Need 8 lines for divider detection to work
        //                    0         1         2         3
        //                    0123456789012345678901234567890123456789
        let lines = [
            "https://example.com│right pane content  ",  // line 0: URL ends at column 18
            "/path/to/resource  │more right content  ",  // line 1: URL continues at column 0
            "some other content │right content       ",  // line 2
            "more left content  │more right          ",  // line 3
            "still left         │still right         ",  // line 4
            "sixth left         │sixth right         ",  // line 5
            "seventh left       │seventh right       ",  // line 6
            "eighth left        │eighth right        ",  // line 7
        ]

        let dataSource = MockDataSourceWithDividers(strings: lines, width: 40)

        // Create a search result for just the first part of the URL (ends at column 18)
        _ = SearchResult(fromX: 0, y: 0, toX: 18, y: 0)!

        // Create a text view mock or use the extractor directly
        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.restrictToLogicalWindow(including: VT100GridCoord(x: 0, y: 0))

        // Verify the logical window was detected
        XCTAssertTrue(extractor.hasLogicalWindow, "Should detect logical window from divider")
        XCTAssertEqual(extractor.logicalWindow.location, 0)
        XCTAssertEqual(extractor.logicalWindow.length, 19) // 0-18 inclusive = 19 chars
    }

    /// Test that a URL not at a soft boundary is not modified.
    func testURLNotAtBoundaryUnchanged() {
        let lines = [
            "https://example.com/path   more text    ",  // URL ends in middle of line
        ]

        let dataSource = MockDataSourceWithDividers(strings: lines, width: 40)

        // Create a search result that doesn't end at a boundary
        let result = SearchResult(fromX: 0, y: 0, toX: 23, y: 0)!
        let originalEndX = result.internalEndX
        let originalEndY = result.internalAbsEndY

        // Without a divider, the logical window should span the full width
        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.restrictToLogicalWindow(including: VT100GridCoord(x: 0, y: 0))

        // No divider means no logical window restriction
        XCTAssertFalse(extractor.hasLogicalWindow, "Should not detect logical window without divider")

        // Result should remain unchanged
        XCTAssertEqual(result.internalEndX, originalEndX)
        XCTAssertEqual(result.internalAbsEndY, originalEndY)
    }

    /// Test divider detection with box-drawing characters.
    func testDividerDetectionWithBoxDrawing() {
        // Use box-drawing vertical line character (│ = U+2502)
        let lines = [
            "left content       │right content       ",
            "more left          │more right          ",
            "still left         │still right         ",
            "fourth left        │fourth right        ",
            "fifth left         │fifth right         ",
            "sixth left         │sixth right         ",
            "seventh left       │seventh right       ",
            "eighth left        │eighth right        ",
        ]

        let dataSource = MockDataSourceWithDividers(strings: lines, width: 40)
        let extractor = iTermTextExtractor(dataSource: dataSource)

        // Check divider detection at middle row
        let dividerCoord = VT100GridCoord(x: 19, y: 4)
        XCTAssertTrue(extractor.character(atCoordIsColumnDivider: dividerCoord),
                      "Should detect box-drawing divider character")

        // Restrict to logical window in left pane
        extractor.restrictToLogicalWindow(including: VT100GridCoord(x: 5, y: 4))
        XCTAssertTrue(extractor.hasLogicalWindow)
        XCTAssertEqual(extractor.logicalWindow.location, 0)
        XCTAssertEqual(extractor.logicalWindow.length, 19)
    }

    /// Test that multi-line URL continuation works.
    func testMultiLineURLContinuation() {
        // A URL that spans 3 lines within a soft boundary
        let lines = [
            "https://example.com│",
            "/very/long/path/tha│",
            "t/continues/here   │",
            "normal text        │",
            "more text          │",
            "even more text     │",
            "line seven         │",
            "line eight         │",
        ]

        let dataSource = MockDataSourceWithDividers(strings: lines, width: 20)
        let extractor = iTermTextExtractor(dataSource: dataSource)

        // Verify the logical window
        extractor.restrictToLogicalWindow(including: VT100GridCoord(x: 0, y: 0))
        XCTAssertTrue(extractor.hasLogicalWindow)
        XCTAssertEqual(extractor.logicalWindow.length, 19)
    }

    /// Test with pipe character as divider.
    func testPipeCharacterDivider() {
        let lines = [
            "left pane content  |right pane content  ",
            "more left content  |more right content  ",
            "third left content |third right content ",
            "fourth left content|fourth right content",
            "fifth left content |fifth right content ",
            "sixth left content |sixth right content ",
            "seventh left       |seventh right       ",
            "eighth left        |eighth right        ",
        ]

        let dataSource = MockDataSourceWithDividers(strings: lines, width: 40)
        let extractor = iTermTextExtractor(dataSource: dataSource)

        // Check divider detection
        let dividerCoord = VT100GridCoord(x: 19, y: 4)
        XCTAssertTrue(extractor.character(atCoordIsColumnDivider: dividerCoord),
                      "Should detect pipe character as divider")
    }
}

// MARK: - Forward-walk URL extension

/// Tests for -[iTermTextExtractor locatedStringByWalkingForwardFrom:characterSet:maxChars:respectHardNewlines:],
/// which extends a URL match past the fixed capture window so long URLs get fully linkified.
/// Reuses MockDataSourceWithDividers above (plain strings, no dividers).
class URLForwardWalkTests: XCTestCase {
    // iTermTextExtractor holds its data source weakly, so keep the mocks alive for the test.
    private var retainedSources: [MockDataSourceWithDividers] = []

    private func urlLikeCharacterSet() -> CharacterSet {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "/:._-")
        return set
    }

    private func extractor(_ lines: [String], width: Int32, softWrapped: Set<Int> = []) -> iTermTextExtractor {
        let source = MockDataSourceWithDividers(strings: lines, width: width, softWrappedLineIndices: softWrapped)
        retainedSources.append(source)
        return iTermTextExtractor(dataSource: source)
    }

    // Walks from the end of a full (soft-wrapped) line onto the next line, stopping at a separator.
    func testWalkAcrossSoftWrapStopsAtSeparator() {
        let ex = extractor(["abcdefghij", "klmno pqr "], width: 10, softWrapped: [0])
        let result = ex.locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                                      characterSet: urlLikeCharacterSet(),
                                                      maxChars: 10000,
                                                      respectHardNewlines: true)
        XCTAssertEqual(result.string, "klmno")
    }

    // The collected coordinates are 1:1 with the characters and land on the continuation line.
    func testWalkRecordsCoordinates() {
        let ex = extractor(["abcdefghij", "klmno pqr "], width: 10, softWrapped: [0])
        let result = ex.locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                                      characterSet: urlLikeCharacterSet(),
                                                      maxChars: 10000,
                                                      respectHardNewlines: true)
        XCTAssertEqual(result.gridCoords.count, 5)
        guard result.gridCoords.count == 5 else { return }
        XCTAssertEqual(result.gridCoords.coord(at: 0).x, 0)
        XCTAssertEqual(result.gridCoords.coord(at: 0).y, 1)
        XCTAssertEqual(result.gridCoords.coord(at: 4).x, 4)
    }

    // maxChars caps the walk.
    func testWalkStopsAtMaxChars() {
        let ex = extractor(["abcdefghij", "klmnopqrst"], width: 10, softWrapped: [0])
        let result = ex.locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                                      characterSet: urlLikeCharacterSet(),
                                                      maxChars: 3,
                                                      respectHardNewlines: true)
        XCTAssertEqual(result.string, "klm")
    }

    // A hard line break stops the walk when respectHardNewlines is on, but not when it is off:
    // a URL that fills a hard-terminated line must not be joined to the next line's text.
    func testWalkStopsAtHardNewline() {
        let stops = extractor(["abcdefghij", "klmnopqrst"], width: 10)  // line 0 ends EOL_HARD
            .locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                           characterSet: urlLikeCharacterSet(),
                                           maxChars: 10000,
                                           respectHardNewlines: true)
        XCTAssertEqual(stops.length, 0)

        let crosses = extractor(["abcdefghij", "klmnopqrst"], width: 10)
            .locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                           characterSet: urlLikeCharacterSet(),
                                           maxChars: 10000,
                                           respectHardNewlines: false)
        XCTAssertEqual(crosses.string, "klmnopqrst")
    }

    // An image cell terminates the walk even when its underlying code is a url-legal character,
    // so an inline image is never linkified as part of a URL.
    func testWalkStopsAtImageCell() {
        // Line 1 is all url-legal letters, but column 2 ('m') is an image cell.
        let source = MockDataSourceWithDividers(strings: ["abcdefghij", "klmnopqrst"], width: 10,
                                                softWrappedLineIndices: [0],
                                                imageColumnsByLine: [1: [2]])
        retainedSources.append(source)
        let ex = iTermTextExtractor(dataSource: source)
        let result = ex.locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                                      characterSet: urlLikeCharacterSet(),
                                                      maxChars: 10000,
                                                      respectHardNewlines: true)
        XCTAssertEqual(result.string, "kl")
    }

    // A composed grapheme (e.g. an IDN host character) whose code points are all in the set is
    // collected as its full decoded string, not truncated the way a blanket complex-char stop was.
    // ('a' + combining acute are both members: .alphanumerics includes Letters and Marks.)
    func testWalkIncludesComposedGraphemeInSet() {
        // Line 1: 'k', a composed 'a'+combining-acute at column 1, 'l', then a space.
        let source = MockDataSourceWithDividers(strings: ["abcdefghij", "k?l mnopqr"], width: 10,
                                                softWrappedLineIndices: [0],
                                                complexColumnsByLine: [1: [1: [0x0061, 0x0301]]])
        retainedSources.append(source)
        let ex = iTermTextExtractor(dataSource: source)
        let result = ex.locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                                      characterSet: urlLikeCharacterSet(),
                                                      maxChars: 10000,
                                                      respectHardNewlines: true)
        // "k" + "a" + combining acute + "l", stopping at the space.
        XCTAssertEqual(result.string, "k\u{0061}\u{0301}l")
        // One grid coord per UTF-16 unit; the composed cell contributes two, both at (1, 1).
        XCTAssertEqual(result.gridCoords.count, 4)
        guard result.gridCoords.count == 4 else { return }
        XCTAssertEqual(result.gridCoords.coord(at: 1).x, 1)
        XCTAssertEqual(result.gridCoords.coord(at: 2).x, 1)
        XCTAssertEqual(result.gridCoords.coord(at: 3).x, 2)
    }

    // A complex (here non-BMP) cell whose decoded character is outside the set stops the walk. An
    // emoji is a surrogate pair (two UTF-16 units) and is not in a plain url-like set.
    func testWalkStopsAtComplexCharOutsideSet() {
        // Column 1 holds 😀 (U+1F600 = surrogate pair D83D DE00).
        let source = MockDataSourceWithDividers(strings: ["abcdefghij", "k?l mnopqr"], width: 10,
                                                softWrappedLineIndices: [0],
                                                complexColumnsByLine: [1: [1: [0xD83D, 0xDE00]]])
        retainedSources.append(source)
        let ex = iTermTextExtractor(dataSource: source)
        let result = ex.locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                                      characterSet: urlLikeCharacterSet(),
                                                      maxChars: 10000,
                                                      respectHardNewlines: true)
        XCTAssertEqual(result.string, "k")
    }

    // An immediate separator, and running off the end of the buffer, both yield empty results.
    func testWalkEmptyCases() {
        let atSeparator = extractor(["abcdefghij", " klmnopqr "], width: 10, softWrapped: [0])
            .locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                           characterSet: urlLikeCharacterSet(), maxChars: 10000,
                                           respectHardNewlines: true)
        XCTAssertEqual(atSeparator.length, 0)

        let atBufferEnd = extractor(["abcdefghij"], width: 10)
            .locatedStringByWalkingForward(from: VT100GridCoord(x: 9, y: 0),
                                           characterSet: urlLikeCharacterSet(), maxChars: 10000,
                                           respectHardNewlines: true)
        XCTAssertEqual(atBufferEnd.length, 0)
    }
}

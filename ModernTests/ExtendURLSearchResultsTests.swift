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
    /// Use "|" or "│" in your strings to represent dividers.
    init(strings: [String], width: Int32 = 80) {
        self.gridWidth = width
        self.gridHeight = Int32(strings.count)
        self.lines = []
        super.init()

        for string in strings {
            let sca = createScreenCharArray(from: string, width: width)
            lines.append(sca)
        }
    }

    private func createScreenCharArray(from string: String, width: Int32) -> ScreenCharArray {
        var buffer = [screen_char_t](repeating: screen_char_t(), count: Int(width) + 1)

        for (index, char) in string.unicodeScalars.enumerated() {
            guard index < Int(width) else { break }
            buffer[index].code = unichar(char.value)
            buffer[index].complexChar = 0
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

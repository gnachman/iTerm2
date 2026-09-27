//
//  BidiSelectionCrashGuardTests.swift
//  ModernTests
//
//  Selection auto-scroll passes a y below the top of the buffer (negative) and
//  the mouse-overflow path can pass one past the end. Converting such a coord
//  to logical must NOT fetch that line: in the real line buffer that asserts and
//  aborts (the drag-to-scroll crash). This mock flags any out-of-range fetch, so
//  the test fails if the guard in -logicalCoordForVisualCoord: is ever removed.
//

import XCTest
@testable import iTerm2SharedARC

private class GuardMockDataSource: NSObject, iTermTextDataSource {
    private let lines: [ScreenCharArray]
    private let gridWidth: Int32
    var badLineFetched = false

    init(strings: [String], width: Int32 = 80) {
        self.gridWidth = width
        var built = [ScreenCharArray]()
        for string in strings {
            var buffer = [screen_char_t](repeating: screen_char_t(), count: Int(width) + 1)
            for (index, scalar) in string.unicodeScalars.enumerated() where index < Int(width) {
                buffer[index].code = unichar(scalar.value)
            }
            var continuation = screen_char_t()
            continuation.code = unichar(EOL_HARD)
            built.append(ScreenCharArray(copyOfLine: buffer, length: width, continuation: continuation))
        }
        self.lines = built
        super.init()
    }

    func width() -> Int32 { gridWidth }
    func numberOfLines() -> Int32 { Int32(lines.count) }
    func totalScrollbackOverflow() -> Int64 { 0 }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        if line < 0 || line >= Int32(lines.count) {
            badLineFetched = true
            return ScreenCharArray.emptyLine(ofLength: gridWidth)
        }
        return lines[Int(line)]
    }
    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        screenCharArray(forLine: index)
    }
    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? { nil }
    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        block(screenCharArray(forLine: line))
    }
    func date(forLine line: Int32) -> Date? { nil }
    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? { nil }
    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata { iTermImmutableMetadataDefault() }
    func isFirstLine(ofBlock lineNumber: Int32) -> Bool { false }
}

class BidiSelectionCrashGuardTests: XCTestCase {
    func testConversionDoesNotFetchOutOfRangeLine() {
        let ds = GuardMockDataSource(strings: ["سلام دنیا"])  // one line, indices [0, 1)
        let extractor = iTermTextExtractor(dataSource: ds)
        extractor.supportBidi = true

        // Below the top (auto-scroll up) and past the end (mouse overflow).
        _ = extractor.logicalCoord(forVisualCoord: VT100GridCoord(x: 0, y: -1))
        _ = extractor.logicalCoord(forVisualCoord: VT100GridCoord(x: 5, y: 100))
        XCTAssertFalse(ds.badLineFetched,
                       "conversion fetched an out-of-range line, which asserts in the real line buffer")

        // Out-of-range lines convert to themselves (identity), so the selection
        // model still gets a usable coordinate.
        let below = extractor.logicalCoord(forVisualCoord: VT100GridCoord(x: 3, y: -1))
        XCTAssertEqual(below.x, 3)
        XCTAssertEqual(below.y, -1)
        let past = extractor.logicalCoord(forVisualCoord: VT100GridCoord(x: 7, y: 100))
        XCTAssertEqual(past.x, 7)
        XCTAssertEqual(past.y, 100)
    }
}

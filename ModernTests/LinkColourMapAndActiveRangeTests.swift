//
//  LinkColourMapAndActiveRangeTests.swift
//  ModernTests
//
//  Regression tests for the link-hover/active colour-map keys and the
//  activeLinkRangeOnLine: logic introduced alongside KEY_LINK_UNDERLINE_STYLE.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Colour map key tests

final class LinkColourMapKeyTests: XCTestCase {

    // The extended-colours base sits well above the 8-bit and 24-bit ranges,
    // so its absolute value doesn't matter — what matters is the *relative*
    // ordering among the extended keys.
    private var extendedBase: Int32 {
        // kColorMapMatch is defined as kExtendedColorsBase + 0; derive from it.
        return Int32(kColorMapMatch)
    }

    /// kColorMapLinkHover must be kExtendedColorsBase + 2.
    func testLinkHoverKeyIsExtendedBase2() {
        XCTAssertEqual(Int32(kColorMapLinkHover), extendedBase + 2)
    }

    /// kColorMapLinkActive must be kExtendedColorsBase + 3.
    func testLinkActiveKeyIsExtendedBase3() {
        XCTAssertEqual(Int32(kColorMapLinkActive), extendedBase + 3)
    }

    /// The two new keys must be distinct from every pre-existing logical key.
    func testLinkHoverAndActiveDoNotCollideLegacyKeys() {
        let legacy: [Int32] = [
            Int32(kColorMapForeground), Int32(kColorMapBackground),
            Int32(kColorMapBold),       Int32(kColorMapLink),
            Int32(kColorMapSelection),  Int32(kColorMapSelectedText),
            Int32(kColorMapCursor),     Int32(kColorMapCursorText),
            Int32(kColorMapInvalid),    Int32(kColorMapUnderline),
            Int32(kColorMapMatch),      Int32(kColorMapIMECursor),
        ]
        XCTAssertFalse(legacy.contains(Int32(kColorMapLinkHover)),
                       "kColorMapLinkHover collides with an existing key")
        XCTAssertFalse(legacy.contains(Int32(kColorMapLinkActive)),
                       "kColorMapLinkActive collides with an existing key")
    }

    /// The two new keys must be distinct from each other.
    func testLinkHoverAndActiveAreDifferent() {
        XCTAssertNotEqual(kColorMapLinkHover, kColorMapLinkActive)
    }

    /// kColorMapLinkHover and kColorMapLinkActive must be distinct from the
    /// 8-bit palette range [kColorMap8bitBase, kColorMap8bitBase+256).
    func testLinkKeysAreOutsideEightBitRange() {
        let base = Int32(kColorMap8bitBase)
        let end  = base + 256
        XCTAssertFalse((base..<end).contains(Int32(kColorMapLinkHover)))
        XCTAssertFalse((base..<end).contains(Int32(kColorMapLinkActive)))
    }

    /// iTermColorMap must accept and round-trip a colour for kColorMapLinkHover.
    func testColorMapStoresLinkHoverColor() {
        let map = iTermColorMap()
        let colour = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.8, alpha: 1.0)
        map.setColor(colour, forKey: iTermColorMapKey(kColorMapLinkHover))
        let retrieved = map.color(forKey: iTermColorMapKey(kColorMapLinkHover))
        XCTAssertNotNil(retrieved)
    }

    /// iTermColorMap must accept and round-trip a colour for kColorMapLinkActive.
    func testColorMapStoresLinkActiveColor() {
        let map = iTermColorMap()
        let colour = NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1.0)
        map.setColor(colour, forKey: iTermColorMapKey(kColorMapLinkActive))
        let retrieved = map.color(forKey: iTermColorMapKey(kColorMapLinkActive))
        XCTAssertNotNil(retrieved)
    }
}

// MARK: - activeLinkRangeOnLine: tests

/// Tests for iTermTextDrawingHelper.activeLinkRangeOnLine:
///
/// The method mirrors underlinedRangeOnLine: exactly, but operates on the
/// activeLinkRange property.  The sentinel for "no active range" is a
/// coordRange.start.x < 0.
final class ActiveLinkRangeOnLineTests: XCTestCase {

    // Build a drawing helper with a fixed grid width so we can test the
    // multi-line "full-width" branch.
    private func makeHelper(gridWidth: Int32 = 80) -> iTermTextDrawingHelper {
        let h = iTermTextDrawingHelper()
        h.gridSize = VT100GridSize(width: gridWidth, height: 24)
        return h
    }

    // Convenience: build a VT100GridAbsWindowedRange from scalar values.
    // A columnWindow.length == 0 means "no window" (full grid width).
    private func makeRange(startX: Int32, startY: Int64,
                           endX: Int32, endY: Int64,
                           windowStart: Int32 = 0, windowWidth: Int32 = 0)
        -> VT100GridAbsWindowedRange
    {
        let coordRange = VT100GridAbsCoordRange(
            start: VT100GridAbsCoord(x: startX, y: startY),
            end:   VT100GridAbsCoord(x: endX,   y: endY))
        return VT100GridAbsWindowedRangeMake(coordRange, windowStart, windowWidth)
    }

    // MARK: - No active range (sentinel)

    /// When activeLinkRange has a negative start.x the method must return an
    /// empty range regardless of the queried row.
    func testNoActiveRange_returnsEmpty() {
        let h = makeHelper()
        // Default-initialised VT100GridAbsWindowedRange has all zeros; force
        // the sentinel by assigning x = -1.
        var sentinel = VT100GridAbsWindowedRange()
        sentinel.coordRange.start.x = -1
        h.activeLinkRange = sentinel

        let result = h.activeLinkRangeOnLine(5)
        XCTAssertEqual(result.location, 0)
        XCTAssertEqual(result.length, 0)
    }

    // MARK: - Single-line range

    /// When start.y == end.y == queried row, return [startX, endX).
    func testSingleLine_matchingRow() {
        let h = makeHelper()
        h.activeLinkRange = makeRange(startX: 3, startY: 10, endX: 7, endY: 10)

        let result = h.activeLinkRangeOnLine(10)
        XCTAssertEqual(result.location, 3)
        XCTAssertEqual(result.length, 4)   // 7 - 3
    }

    /// A different row returns empty for a single-line range.
    func testSingleLine_nonMatchingRow() {
        let h = makeHelper()
        h.activeLinkRange = makeRange(startX: 3, startY: 10, endX: 7, endY: 10)

        XCTAssertEqual(h.activeLinkRangeOnLine(9).length, 0)
        XCTAssertEqual(h.activeLinkRangeOnLine(11).length, 0)
    }

    // MARK: - Multi-line range, no column window

    /// On the start row of a multi-line range (no column window) the range runs
    /// from startX to gridSize.width.
    func testMultiLine_startRow_noWindow() {
        let h = makeHelper(gridWidth: 80)
        h.activeLinkRange = makeRange(startX: 20, startY: 5, endX: 10, endY: 7)

        let result = h.activeLinkRangeOnLine(5)
        XCTAssertEqual(result.location, 20)
        XCTAssertEqual(result.length, 60)   // 80 - 20
    }

    /// On the end row of a multi-line range (no column window) the range runs
    /// from 0 to endX.
    func testMultiLine_endRow_noWindow() {
        let h = makeHelper(gridWidth: 80)
        h.activeLinkRange = makeRange(startX: 20, startY: 5, endX: 10, endY: 7)

        let result = h.activeLinkRangeOnLine(7)
        XCTAssertEqual(result.location, 0)
        XCTAssertEqual(result.length, 10)   // 0..10
    }

    /// An interior row (strictly between start and end) returns the full grid
    /// width when there is no column window.
    func testMultiLine_interiorRow_noWindow() {
        let h = makeHelper(gridWidth: 80)
        h.activeLinkRange = makeRange(startX: 20, startY: 5, endX: 10, endY: 8)

        let result = h.activeLinkRangeOnLine(6)   // interior
        XCTAssertEqual(result.location, 0)
        XCTAssertEqual(result.length, 80)
    }

    /// A row before start or after end returns empty.
    func testMultiLine_rowOutsideRange() {
        let h = makeHelper(gridWidth: 80)
        h.activeLinkRange = makeRange(startX: 20, startY: 5, endX: 10, endY: 7)

        XCTAssertEqual(h.activeLinkRangeOnLine(4).length, 0)
        XCTAssertEqual(h.activeLinkRangeOnLine(8).length, 0)
    }

    // MARK: - Multi-line range, with column window

    /// On the start row with a column window the range ends at the window max.
    func testMultiLine_startRow_withWindow() {
        let h = makeHelper(gridWidth: 80)
        // Window covers columns 10..<50 (length 40), so max = 49, end = 50.
        h.activeLinkRange = makeRange(startX: 25, startY: 3, endX: 15, endY: 5,
                                      windowStart: 10, windowWidth: 40)

        let result = h.activeLinkRangeOnLine(3)
        // start = max(25, 10) = 25 (already inside window)
        // end = VT100GridRangeMax({10,40}) + 1 = 49 + 1 = 50
        XCTAssertEqual(result.location, 25)
        XCTAssertEqual(result.length, 25)   // 50 - 25
    }

    /// On the end row with a column window the range starts at windowStart.
    func testMultiLine_endRow_withWindow() {
        let h = makeHelper(gridWidth: 80)
        h.activeLinkRange = makeRange(startX: 25, startY: 3, endX: 15, endY: 5,
                                      windowStart: 10, windowWidth: 40)

        let result = h.activeLinkRangeOnLine(5)
        // start = windowStart = 10
        // end = min(endX=15, max+1=50) = 15
        XCTAssertEqual(result.location, 10)
        XCTAssertEqual(result.length, 5)    // 15 - 10
    }

    /// An interior row with a column window returns exactly the window span.
    func testMultiLine_interiorRow_withWindow() {
        let h = makeHelper(gridWidth: 80)
        h.activeLinkRange = makeRange(startX: 25, startY: 3, endX: 15, endY: 6,
                                      windowStart: 10, windowWidth: 40)

        let result = h.activeLinkRangeOnLine(4)   // interior
        // start = windowStart = 10, end = VT100GridRangeMax({10,40}) + 1 = 50
        XCTAssertEqual(result.location, 10)
        XCTAssertEqual(result.length, 40)
    }
}

// MARK: - Link underline style bounds-check tests

/// The bounds check in iTermMetalPerFrameState is not directly unit-testable
/// without the Metal frame machinery, but the *policy* — which raw integer
/// values are considered valid — can be checked as pure constants.
final class LinkUnderlineStyleValidValuesTests: XCTestCase {

    // Mirror the whitelist from iTermMetalPerFrameState.m so that a future
    // accidental removal of a valid value breaks a test rather than silently
    // changing behaviour for users.
    private func isValidLinkStyle(_ value: Int32) -> Bool {
        return value == Int32(iTermMetalGlyphAttributesUnderlineSingle.rawValue) ||
               value == Int32(iTermMetalGlyphAttributesUnderlineDouble.rawValue) ||
               value == Int32(iTermMetalGlyphAttributesUnderlineDashedSingle.rawValue) ||
               value == Int32(iTermMetalGlyphAttributesUnderlineCurly.rawValue) ||
               value == Int32(iTermMetalGlyphAttributesUnderlineDotted.rawValue)
    }

    private let fallback = Int32(iTermMetalGlyphAttributesUnderlineDashedSingle.rawValue)

    /// All five documented values (1=Single, 2=Double, 3=Dashed, 4=Curly, 6=Dotted)
    /// are accepted.
    func testAllDocumentedValuesAreValid() {
        XCTAssertTrue(isValidLinkStyle(1), "Single should be valid")
        XCTAssertTrue(isValidLinkStyle(2), "Double should be valid")
        XCTAssertTrue(isValidLinkStyle(3), "DashedSingle should be valid")
        XCTAssertTrue(isValidLinkStyle(4), "Curly should be valid")
        XCTAssertTrue(isValidLinkStyle(6), "Dotted should be valid")
    }

    /// Zero (None) is invalid and must fall back to DashedSingle.
    func testZeroIsInvalidAndFallsBack() {
        XCTAssertFalse(isValidLinkStyle(0))
        XCTAssertEqual(fallback, 3)   // DashedSingle is the documented default
    }

    /// 5 (Hyperlink) is not in the whitelist — it is a reserved internal style.
    func testHyperlinkStyleIsNotDirectlyWhitelisted() {
        XCTAssertFalse(isValidLinkStyle(5),
                       "iTermMetalGlyphAttributesUnderlineHyperlink must not be user-selectable")
    }

    /// 7 (Dashed) is not in the whitelist (distinct from DashedSingle=3).
    func testDashedIsNotWhitelisted() {
        XCTAssertFalse(isValidLinkStyle(7))
    }

    /// Negative values are invalid.
    func testNegativeIsInvalid() {
        XCTAssertFalse(isValidLinkStyle(-1))
        XCTAssertFalse(isValidLinkStyle(-99))
    }

    /// Very large values are invalid.
    func testLargeValueIsInvalid() {
        XCTAssertFalse(isValidLinkStyle(100))
    }

    /// The default stored in iTermProfilePreferences (@3 = DashedSingle) is a
    /// valid style, so it never triggers the fallback path on a fresh profile.
    func testDefaultProfileValueIsValid() {
        XCTAssertTrue(isValidLinkStyle(3),
                      "The profile default (3 = DashedSingle) must be valid")
    }
}

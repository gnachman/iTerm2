//
//  iTermUnderlineSpanTests.swift
//  ModernTests
//
//  Tests for computeUnderlineSpansFromAttributes: in iTermTextRendererTransientState.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermUnderlineSpanTests: XCTestCase {

    // MARK: - Helpers

    private func makeHelper() -> iTermUnderlineSpanTestHelper {
        return iTermUnderlineSpanTestHelper()
    }

    private func makeAttributes(count: Int) -> [iTermMetalGlyphAttributes] {
        return [iTermMetalGlyphAttributes](repeating: iTermMetalGlyphAttributes(), count: count)
    }

    private func makeLine(count: Int) -> [screen_char_t] {
        return [screen_char_t](repeating: screen_char_t(), count: count)
    }

    private func makeNonASCIILine(count: Int) -> [screen_char_t] {
        var line = makeLine(count: count)
        for i in 0..<count { line[i].code = 0x4E2D }
        return line
    }

    private func spans(from data: NSMutableData) -> [iTermMetalUnderlineSpan] {
        let spanSize = MemoryLayout<iTermMetalUnderlineSpan>.size
        let count = data.length / spanSize
        guard count > 0 else { return [] }
        var result = [iTermMetalUnderlineSpan]()
        for i in 0..<count {
            var span = iTermMetalUnderlineSpan()
            (data as NSData).getBytes(&span, range: NSRange(location: i * spanSize, length: spanSize))
            result.append(span)
        }
        return result
    }

    private func callComputeSpans(
        helper: iTermUnderlineSpanTestHelper,
        attrs: inout [iTermMetalGlyphAttributes],
        line: inout [screen_char_t],
        row: Int32 = 0,
        markedRange: NSRange = NSRange(location: NSNotFound, length: 0),
        inverseLUT: UnsafeMutablePointer<Int32>? = nil,
        inverseLUTLen: Int32 = 0,
        underlines: NSMutableData,
        strikethroughs: NSMutableData
    ) {
        helper.computeSpans(
            from: &attrs,
            count: Int32(attrs.count),
            row: row,
            markedRangeOnLine: markedRange,
            line: &line,
            lineLength: Int32(line.count),
            inverseLUT: inverseLUT,
            inverseLUTLen: inverseLUTLen,
            underlineSpans: underlines,
            strikethroughSpans: strikethroughs
        )
    }

    private let red = simd_make_float4(1, 0, 0, 1)
    private let green = simd_make_float4(0, 1, 0, 1)
    private let yellow = simd_make_float4(1, 1, 0, 1)  // iTermAnnotationUnderlineColor

    // MARK: - Tests

    func testNoUnderlines() {
        let h = makeHelper()
        var attrs = makeAttributes(count: 10)
        var line = makeLine(count: 10)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        XCTAssertEqual(underlines.length, 0)
        XCTAssertEqual(strikethroughs.length, 0)
    }

    func testSingleUnderlineSpan() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        var attrs = makeAttributes(count: 10)
        for i in 2...5 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle }
        var line = makeLine(count: 10)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line, row: 3,
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].row, 3)
        XCTAssertEqual(s[0].startColumn, 2)
        XCTAssertEqual(s[0].endColumn, 5)
        XCTAssertEqual(s[0].style, iTermMetalGlyphAttributesUnderlineSingle)
        XCTAssert(simd_equal(s[0].color, red))
        XCTAssertEqual(strikethroughs.length, 0)
    }

    func testStyleChangeSplitsSpan() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        var attrs = makeAttributes(count: 6)
        for i in 0...2 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle }
        for i in 3...5 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineDouble }
        var line = makeLine(count: 6)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].startColumn, 0)
        XCTAssertEqual(s[0].endColumn, 2)
        XCTAssertEqual(s[0].style, iTermMetalGlyphAttributesUnderlineSingle)
        XCTAssertEqual(s[1].startColumn, 3)
        XCTAssertEqual(s[1].endColumn, 5)
        XCTAssertEqual(s[1].style, iTermMetalGlyphAttributesUnderlineDouble)
    }

    func testColorChangeSplitsSpan() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        var attrs = makeAttributes(count: 6)
        for i in 0..<6 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle }
        for i in 3...5 {
            attrs[i].hasUnderlineColor = true
            attrs[i].underlineColor = green
        }
        var line = makeLine(count: 6)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 2)
        XCTAssert(simd_equal(s[0].color, red))
        XCTAssert(simd_equal(s[1].color, green))
    }

    func testStrikethroughSpan() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        var attrs = makeAttributes(count: 5)
        for i in 1...3 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineStrikethrough }
        var line = makeLine(count: 5)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        XCTAssertEqual(underlines.length, 0)
        let s = spans(from: strikethroughs)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].startColumn, 1)
        XCTAssertEqual(s[0].endColumn, 3)
        XCTAssertEqual(s[0].style, iTermMetalGlyphAttributesUnderlineStrikethrough)
    }

    func testUnderlineAndStrikethroughTogether() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        var attrs = makeAttributes(count: 4)
        for i in 0..<4 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineStrikethroughAndSingle }
        var line = makeLine(count: 4)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        let u = spans(from: underlines)
        let st = spans(from: strikethroughs)
        XCTAssertEqual(u.count, 1)
        XCTAssertEqual(st.count, 1)
        XCTAssertEqual(u[0].style, iTermMetalGlyphAttributesUnderlineSingle)
        XCTAssertEqual(st[0].style, iTermMetalGlyphAttributesUnderlineStrikethrough)
    }

    func testMarkedRangeCreatesUnderline() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        var attrs = makeAttributes(count: 10)
        var line = makeLine(count: 10)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         markedRange: NSRange(location: 3, length: 4),
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].startColumn, 3)
        XCTAssertEqual(s[0].endColumn, 6)
        XCTAssertEqual(s[0].style, iTermMetalGlyphAttributesUnderlineSingle)
    }

    func testAnnotationUsesYellowColor() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        var attrs = makeAttributes(count: 4)
        for i in 0..<4 {
            attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle
            attrs[i].annotation = true
        }
        var line = makeLine(count: 4)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 1)
        XCTAssert(simd_equal(s[0].color, yellow))
    }

    func testNonASCIIUsesNonASCIIDescriptor() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        h.nonAsciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: green)
        var attrs = makeAttributes(count: 4)
        for i in 0..<4 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle }
        var line = makeNonASCIILine(count: 4)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 1)
        XCTAssert(simd_equal(s[0].color, green))
    }

    func testInverseLUTMapsVisualToLogical() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        h.nonAsciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: green)
        var attrs = makeAttributes(count: 4)
        for i in 0..<4 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle }
        var line = makeLine(count: 4)
        line[2].code = 0x4E2D  // logical index 2 is non-ASCII
        // visual 0->logical 0, visual 1->logical 2 (non-ASCII), visual 2->logical 1, visual 3->logical 3
        var inverseLUT: [Int32] = [0, 2, 1, 3]
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         inverseLUT: &inverseLUT, inverseLUTLen: 4,
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 3)
        XCTAssert(simd_equal(s[0].color, red))   // col 0: ASCII
        XCTAssert(simd_equal(s[1].color, green))  // col 1: maps to logical 2, non-ASCII
        XCTAssert(simd_equal(s[2].color, red))   // cols 2-3: ASCII
    }

    func testGapInUnderlineProducesSeparateSpans() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        var attrs = makeAttributes(count: 8)
        for i in 0...2 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle }
        for i in 5...7 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle }
        var line = makeLine(count: 8)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].startColumn, 0)
        XCTAssertEqual(s[0].endColumn, 2)
        XCTAssertEqual(s[1].startColumn, 5)
        XCTAssertEqual(s[1].endColumn, 7)
    }

    func testFallbackToForegroundColorWhenDescriptorColorInvalid() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: simd_make_float4(0, 0, 0, 0))
        var attrs = makeAttributes(count: 3)
        for i in 0..<3 {
            attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle
            attrs[i].foregroundColor = green
        }
        var line = makeLine(count: 3)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        callComputeSpans(helper: h, attrs: &attrs, line: &line,
                         underlines: underlines, strikethroughs: strikethroughs)

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 1)
        XCTAssert(simd_equal(s[0].color, green))
    }

    func testMultipleRowsAppendToSameData() {
        let h = makeHelper()
        h.asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor(offset: 0, thickness: 1, color: red)
        let underlines = NSMutableData()
        let strikethroughs = NSMutableData()

        for row in 0..<3 {
            var attrs = makeAttributes(count: 4)
            for i in 0..<4 { attrs[i].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle }
            var line = makeLine(count: 4)
            callComputeSpans(helper: h, attrs: &attrs, line: &line, row: Int32(row),
                             underlines: underlines, strikethroughs: strikethroughs)
        }

        let s = spans(from: underlines)
        XCTAssertEqual(s.count, 3)
        for row in 0..<3 {
            XCTAssertEqual(s[row].row, Int32(row))
            XCTAssertEqual(s[row].startColumn, 0)
            XCTAssertEqual(s[row].endColumn, 3)
        }
    }
}

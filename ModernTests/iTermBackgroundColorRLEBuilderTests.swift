import XCTest
@testable import iTerm2SharedARC

// MARK: - Mocks

private class MockPerFrameState: NSObject {
    @objc func unprocessedColorForBackgroundColorKey(_ colorKey: UnsafeMutableRawPointer,
                                                     isDefault: UnsafeMutablePointer<ObjCBool>) -> SIMD4<Float> {
        isDefault.pointee = true
        return SIMD4<Float>(0.1, 0.1, 0.1, 1.0)
    }
}

private class MockColorMap: NSObject {
    @objc func fastProcessedBackgroundColor(forBackgroundColor color: SIMD4<Float>) -> SIMD4<Float> {
        return color
    }
}

private class MockBidiInfo: NSObject {
    private let _lut: UnsafeMutablePointer<Int32>
    private let _count: Int32

    init(lut: [Int32]) {
        _count = Int32(lut.count)
        _lut = .allocate(capacity: lut.count)
        _lut.initialize(from: lut, count: lut.count)
    }
    deinit { _lut.deallocate() }
    @objc var lut: UnsafePointer<Int32> { UnsafePointer(_lut) }
    @objc var numberOfCells: Int32 { _count }
}

// MARK: - Tests

final class iTermBackgroundColorRLEBuilderTests: XCTestCase {

    private struct RLE {
        let origin: Int
        let count: Int
        let logicalOrigin: Int
    }

    private func makeLine(width: Int, spacerPositions: Set<Int> = [], bgGroups: [Int: UInt32] = [:]) -> [screen_char_t] {
        var line = [screen_char_t](repeating: screen_char_t(), count: width)
        for i in spacerPositions where i < width {
            ScreenCharSetDWL_SPACER(&line[i])
        }
        for (x, bg) in bgGroups where x < width {
            line[x].backgroundColor = bg
        }
        return line
    }

    private func buildRLEs(
        width: Int,
        spacerPositions: Set<Int> = [],
        bgGroups: [Int: UInt32] = [:],
        bidiLUT: [Int32]? = nil,
        lineAttribute: iTermLineAttribute = .singleWidth
    ) -> [RLE] {
        var line = makeLine(width: width, spacerPositions: spacerPositions, bgGroups: bgGroups)

        var rles = [iTermMetalBackgroundColorRLE](repeating: iTermMetalBackgroundColorRLE(), count: width)

        var maxVisual = width
        if let lut = bidiLUT {
            for v in lut { maxVisual = max(maxVisual, Int(v) + 1) }
        }
        var attributes = [iTermMetalGlyphAttributes](repeating: iTermMetalGlyphAttributes(), count: maxVisual)
        var unprocessed = [SIMD4<Float>](repeating: .zero, count: width)

        let mockSelf = MockPerFrameState()
        let mockColorMap = MockColorMap()
        let mockBidi: MockBidiInfo? = bidiLUT.map { MockBidiInfo(lut: $0) }

        let count = iTermGetMetalBackgroundColors(
            unsafeBitCast(mockSelf, to: iTermMetalPerFrameState.self),
            &line, &rles, &attributes, &unprocessed,
            Int32(width), nil, nil,
            unsafeBitCast(mockColorMap, to: AnyObject.self) as! any iTermColorMapReading,
            unsafeBitCast(mockBidi, to: iTermBidiDisplayInfo?.self),
            lineAttribute)

        return (0..<Int(count)).map { i in
            RLE(origin: Int(rles[i].origin),
                count: Int(rles[i].count),
                logicalOrigin: Int(rles[i].logicalOrigin))
        }
    }

    // MARK: - Basic (non-DWL, no bidi)

    func testSingleColorLTR() {
        let r = buildRLEs(width: 5)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 5)
    }

    func testTwoColorsLTR() {
        let r = buildRLEs(width: 6, bgGroups: [3: 1, 4: 1, 5: 1])
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 3)
        XCTAssertEqual(r[1].origin, 3)
        XCTAssertEqual(r[1].count, 3)
    }

    // MARK: - Non-DWL bidi (RTL)

    func testSingleColorRTL() {
        let r = buildRLEs(width: 5, bidiLUT: [4, 3, 2, 1, 0])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 5)
    }

    func testTwoColorsRTL() {
        let r = buildRLEs(width: 5, bgGroups: [3: 1, 4: 1],
                          bidiLUT: [4, 3, 2, 1, 0])
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].origin, 2)
        XCTAssertEqual(r[0].count, 3)
        XCTAssertEqual(r[1].origin, 0)
        XCTAssertEqual(r[1].count, 2)
    }

    // MARK: - DWL LTR (with spacers)

    func testDWLSingleColorLTR() {
        let r = buildRLEs(width: 6, spacerPositions: [1, 3, 5],
                          lineAttribute: .doubleWidth)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 6)
    }

    func testDWLTwoColorsLTR() {
        let r = buildRLEs(width: 8, spacerPositions: [1, 3, 5, 7],
                          bgGroups: [4: 1, 6: 1],
                          lineAttribute: .doubleWidth)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 4)
        XCTAssertEqual(r[1].origin, 4)
        XCTAssertEqual(r[1].count, 4)
    }

    // MARK: - DWL RTL (Arabic — the scary case)

    func testDWLSingleColorRTL() {
        let lut: [Int32] = [8, 9, 6, 7, 4, 5, 2, 3, 0, 1]
        let r = buildRLEs(width: 10, spacerPositions: [1, 3, 5, 7, 9],
                          bidiLUT: lut, lineAttribute: .doubleWidth)
        XCTAssertEqual(r.count, 1,
                       "All same-color RTL DWL chars should be one RLE")
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 10)
    }

    func testDWLTwoColorsRTL() {
        let lut: [Int32] = [8, 9, 6, 7, 4, 5, 2, 3, 0, 1]
        let r = buildRLEs(width: 10, spacerPositions: [1, 3, 5, 7, 9],
                          bgGroups: [6: 1, 8: 1],
                          bidiLUT: lut, lineAttribute: .doubleWidth)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].origin, 4)
        XCTAssertEqual(r[0].count, 6)
        XCTAssertEqual(r[1].origin, 0)
        XCTAssertEqual(r[1].count, 4)
    }

    // MARK: - DWL mixed bidi

    func testDWLMixedBidiSameColor() {
        let lut: [Int32] = [0, 1, 2, 3, 6, 7, 4, 5]
        let r = buildRLEs(width: 8, spacerPositions: [1, 3, 5, 7],
                          bidiLUT: lut, lineAttribute: .doubleWidth)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 4)
        XCTAssertEqual(r[1].origin, 4)
        XCTAssertEqual(r[1].count, 4)
    }

    // MARK: - DECDHL

    func testDECDHLTopSingleColor() {
        let r = buildRLEs(width: 6, spacerPositions: [1, 3, 5],
                          lineAttribute: .doubleHeightTop)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 6)
    }

    func testDECDHLBottomSingleColor() {
        let r = buildRLEs(width: 6, spacerPositions: [1, 3, 5],
                          lineAttribute: .doubleHeightBottom)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 6)
    }

    // MARK: - Edge cases

    func testSingleCharDWL() {
        let r = buildRLEs(width: 2, spacerPositions: [1],
                          lineAttribute: .doubleWidth)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 2)
    }

    func testNonDWLVisualGapSplitsRLE() {
        let r = buildRLEs(width: 3, bidiLUT: [0, 1, 5])
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].origin, 0)
        XCTAssertEqual(r[0].count, 2)
        XCTAssertEqual(r[1].origin, 5)
        XCTAssertEqual(r[1].count, 1)
    }
}

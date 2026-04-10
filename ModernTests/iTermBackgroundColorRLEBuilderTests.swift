import XCTest
@testable import iTerm2SharedARC

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
        let helper = iTermBackgroundColorRLETestHelper()

        var results = [iTermTestBackgroundRLE](repeating: iTermTestBackgroundRLE(), count: width)

        let count: Int32
        if var lut = bidiLUT {
            count = helper.buildRLEs(forLine: &line, width: Int32(width),
                                     results: &results, maxResults: Int32(width),
                                     bidiLUT: &lut, bidiLUTLen: Int32(lut.count),
                                     lineAttribute: lineAttribute)
        } else {
            count = helper.buildRLEs(forLine: &line, width: Int32(width),
                                     results: &results, maxResults: Int32(width),
                                     bidiLUT: nil, bidiLUTLen: 0,
                                     lineAttribute: lineAttribute)
        }
        return (0..<Int(count)).map { i in
            RLE(origin: Int(results[i].origin),
                count: Int(results[i].count),
                logicalOrigin: Int(results[i].logicalOrigin))
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

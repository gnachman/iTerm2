//
//  CoreTextGlyphAlignmentTests.swift
//  ModernTests
//
//  The legacy (CoreGraphics) renderer moves each glyph CoreText produced into
//  its grid column. A pre-base vowel sign, like Devanagari ि in “त्रि”, is
//  stored after its consonant but CoreText draws it first. Placing it at its
//  own column drew the word as त्र ि. QA finding F-081.
//

import XCTest
import CoreText
@testable import iTerm2SharedARC

class CoreTextGlyphAlignmentTests: XCTestCase {
    private func helper() -> iTermCoreTextLineRenderingHelper {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "x"))
        return iTermCoreTextLineRenderingHelper(line: line, string: "x", drawInCellIndex: Data())
    }

    private func align(glyphToChar: [CFIndex],
                       positions: [CGFloat],
                       advances: [CGFloat],
                       xOrigins: [CGFloat],
                       displayCells: [Int32]) -> [CGFloat] {
        var points = positions.map { CGPoint(x: $0, y: 0) }
        let sizes = advances.map { CGSize(width: $0, height: 0) }
        var lastMaxExtent: CGFloat = 0
        glyphToChar.withUnsafeBufferPointer { g in
            xOrigins.withUnsafeBufferPointer { x in
                sizes.withUnsafeBufferPointer { a in
                    displayCells.withUnsafeBufferPointer { d in
                        points.withUnsafeMutableBufferPointer { p in
                            helper().alignGlyphsToGrid(glyphIndex: g.baseAddress!,
                                                       length: Int32(g.count),
                                                       xOriginsForCharacters: x.baseAddress!,
                                                       alignToZero: false,
                                                       positions: p.baseAddress!,
                                                       advances: a.baseAddress!,
                                                       lastMaxExtent: &lastMaxExtent,
                                                       characterIndexToDisplayCell: d.baseAddress!)
                        }
                    }
                }
            }
        }
        return points.map { $0.x }
    }

    // CoreText's real output for a pre-base matra: the matra glyph comes first
    // and is positioned left of the conjunct even though its character is last.
    func testCoreTextDrawsPreBaseMatraBeforeConjunct() {
        let font = NSFont(name: "Menlo", size: 12)!
        let string = "त्रि"
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        var matraX: CGFloat?
        var conjunctX: CGFloat?
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                if indices[i] == 3 { matraX = positions[i].x }
                if indices[i] == 0 { conjunctX = positions[i].x }
            }
        }
        guard let matraX, let conjunctX else {
            return XCTFail("expected separate glyphs for the matra and the conjunct")
        }
        XCTAssertLessThan(matraX, conjunctX)
    }

    // त ् र ि: त and its virama share cell 0; र is cell 1; the spacing mark ि
    // is drawn in its base's column (1). CoreText emits [ि at 0, त्र at 6].
    func testPreBaseMatraStaysLeftOfItsConjunct() {
        let cell: CGFloat = 7
        let result = align(glyphToChar: [3, 0],
                           positions: [0, 6],
                           advances: [6, 10],
                           xOrigins: [0, 0, cell, cell],
                           displayCells: [0, 0, 1, 1])
        let matra = result[0]
        let conjunct = result[1]
        XCTAssertLessThan(matra, conjunct, "the matra must be drawn before the conjunct")
        XCTAssertEqual(matra, 0, "the cluster starts at its first cell")
        XCTAssertEqual(conjunct, 6, "CoreText's spacing inside the cluster is kept")
    }

    // A left-to-right island inside a right-to-left line: CoreText lays out
    // “8)” as [8 at 0, ) at 7] but the line places ) in column 4 and 8 in
    // column 5. Each glyph must land in its own column.
    func testReversedIslandIsUnpiledByColumn() {
        let cell: CGFloat = 7
        let result = align(glyphToChar: [0, 1],
                           positions: [0, 7],
                           advances: [7, 7],
                           xOrigins: [5 * cell, 4 * cell],
                           displayCells: [5, 4])
        XCTAssertEqual(result[0], 5 * cell)
        XCTAssertEqual(result[1], 4 * cell)
    }

    // Plain left-to-right text with a combining mark keeps one glyph per column
    // and the mark on its base.
    func testLTRWithCombiningMark() {
        let cell: CGFloat = 7
        let result = align(glyphToChar: [0, 1, 2],
                           positions: [0, 1, 7],
                           advances: [7, 0, 7],
                           xOrigins: [0, 0, cell],
                           displayCells: [0, 0, 1])
        XCTAssertEqual(result, [0, 1, cell])
    }
}

//
//  CoreTextLineRenderingHelper.swift
//  iTerm2
//
//  Created by George Nachman on 11/22/24.
//

@objc
extension iTermCoreTextLineRenderingHelper {
    @objc(alignGlyphsToGridWithGlyphIndex:length:xOriginsForCharacters:alignToZero:positions:advances:lastMaxExtent:characterIndexToDisplayCell:)
    func alignGlyphsToGrid(glyphIndex glyphIndexToCharacterIndex: UnsafePointer<CFIndex>,
                           length glyphCount: Int32,
                           xOriginsForCharacters: UnsafePointer<CGFloat>,
                           alignToZero: Bool,
                           positions: UnsafeMutablePointer<CGPoint>,
                           advances: UnsafePointer<CGSize>,
                           lastMaxExtent: UnsafeMutablePointer<CGFloat>,
                           characterIndexToDisplayCell: UnsafePointer<Int32>) {

        // Maps glyph index to glyph index sorted by left-to-right position.
        let permutation = (0..<Int(glyphCount)).sorted { lhs, rhs in
            let ld = characterIndexToDisplayCell[Int(glyphIndexToCharacterIndex[lhs])]
            let rd = characterIndexToDisplayCell[Int(glyphIndexToCharacterIndex[rhs])]
            if ld != rd {
                return ld < rd
            }

            let le = positions[lhs].x + advances[lhs].width
            let re = positions[rhs].x + advances[rhs].width
            if le != re {
                return le < re
            }

            return lhs < rhs
        }

        var lastDisplayColumn = Int32(-1)
        var maxExtent = lastMaxExtent.pointee

        // Baseline for the current display column: the run-space x of that
        // column's first (leftmost) glyph. Anchoring to the column's own base
        // glyph, rather than to the previous glyph's trailing edge, is what
        // makes a run whose display order runs opposite to its glyph order lay
        // out correctly. That happens for an LTR island embedded in an RTL line,
        // e.g. a "8)" or "10)" list marker: its digits and paren are a single
        // left-to-right run, but the surrounding RTL line places that run's
        // columns right-to-left, so the glyphs must be un-piled column by
        // column. The permutation visits columns left-to-right and, within a
        // column, the base glyph before its combining marks, so each glyph keeps
        // its offset from the base and combining marks still land on their base.
        var columnBaseline = maxExtent

        for i in 0..<Int(glyphCount) {
            let j = permutation[i]
            let c = glyphIndexToCharacterIndex[j]
            let displayColumn = characterIndexToDisplayCell[c]
            let savedPosition = positions[j].x
            if displayColumn != lastDisplayColumn {
                columnBaseline = savedPosition
            }
            if alignToZero {
                positions[j].x = savedPosition - columnBaseline
            } else {
                positions[j].x = xOriginsForCharacters[c] + (savedPosition - columnBaseline)
            }
            lastDisplayColumn = displayColumn
            maxExtent = max(maxExtent, savedPosition + advances[j].width)
        }
        lastMaxExtent.pointee = maxExtent
    }
}

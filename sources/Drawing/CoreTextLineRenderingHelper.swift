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
        var lastColumnExtent = maxExtent

        // It is *super* sketchy to use maxExtent for this. positions[0].x is probably a better
        // choice. This matches the pre-bidi logic, but I am pretty sure it was wrong. I'm just
        // waiting for a reproducible case to fix this.
        var lastGlyphExtent = maxExtent

        for i in 0..<Int(glyphCount) {
            let j = permutation[i]
            let c = glyphIndexToCharacterIndex[j]
            let displayColumn = characterIndexToDisplayCell[c]
            if displayColumn != lastDisplayColumn {
                lastColumnExtent = lastGlyphExtent
            }
            let savedPosition = positions[j].x
            if alignToZero {
                positions[j].x -= lastColumnExtent
            } else {
                positions[j].x += xOriginsForCharacters[c] - lastColumnExtent
            }
            lastDisplayColumn = displayColumn
            lastGlyphExtent = savedPosition + advances[j].width
            maxExtent = max(maxExtent, lastGlyphExtent)
        }
        lastMaxExtent.pointee = maxExtent
    }
}

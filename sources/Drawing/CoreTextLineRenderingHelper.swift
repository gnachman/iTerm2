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

            // Within a display column, order by DECREASING advance so the BASE glyph
            // (nonzero advance) comes before its zero-advance combining marks. The
            // previous tie-break sorted by TRAILING edge (position.x + advance),
            // which for a zero-advance mark is just its own x and so sorted the mark
            // ahead of the base; columnBaseline was then taken from the mark, shifting
            // the base glyph when Core Text gave the mark a nonzero x offset (Arabic
            // base + haraka) and diverging from Metal, which anchors the cluster by
            // cell. Base-first keeps the existing comment (base before its marks) true.
            if advances[lhs].width != advances[rhs].width {
                return advances[lhs].width > advances[rhs].width
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
        //
        // Columns are gathered into groups first. A pre-base vowel sign (like
        // Devanagari ि in “त्रि”) is stored after its consonant, so it gets a
        // later column, but CoreText draws it to the left of that consonant. It
        // joins the preceding group, which then starts at the vowel sign's x, so
        // the cluster keeps CoreText's internal layout instead of the sign being
        // pushed past the consonant. The test requires a later character than
        // any in the group, which a reversed LTR island (whose later columns
        // hold earlier characters) never satisfies.
        struct Group {
            var baseline: CGFloat
            var anchorCharacter: CFIndex
            var maxCharacter: CFIndex
        }
        var groups = [Group]()
        var groupForGlyph = [Int](repeating: 0, count: Int(glyphCount))

        for i in 0..<Int(glyphCount) {
            let j = permutation[i]
            let c = glyphIndexToCharacterIndex[j]
            let displayColumn = characterIndexToDisplayCell[c]
            let savedPosition = positions[j].x
            if displayColumn != lastDisplayColumn {
                if var group = groups.last,
                   savedPosition < group.baseline,
                   c > group.maxCharacter {
                    group.baseline = savedPosition
                    group.maxCharacter = c
                    groups[groups.count - 1] = group
                } else {
                    groups.append(Group(baseline: savedPosition, anchorCharacter: c, maxCharacter: c))
                }
            } else {
                groups[groups.count - 1].maxCharacter = max(groups[groups.count - 1].maxCharacter, c)
            }
            groupForGlyph[j] = groups.count - 1
            lastDisplayColumn = displayColumn
            maxExtent = max(maxExtent, savedPosition + advances[j].width)
        }

        for i in 0..<Int(glyphCount) {
            let j = permutation[i]
            let c = glyphIndexToCharacterIndex[j]
            let group = groups[groupForGlyph[j]]
            let savedPosition = positions[j].x
            if alignToZero {
                positions[j].x = savedPosition - group.baseline
            } else {
                // Glyphs in their group's first column use their own character's
                // origin, as before. A pre-base sign uses the group's.
                let anchor = characterIndexToDisplayCell[c] == characterIndexToDisplayCell[group.anchorCharacter] ? c : group.anchorCharacter
                positions[j].x = xOriginsForCharacters[anchor] + (savedPosition - group.baseline)
            }
        }
        lastMaxExtent.pointee = maxExtent
    }
}

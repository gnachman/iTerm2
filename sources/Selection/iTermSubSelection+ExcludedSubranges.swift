//
//  iTermSubSelection+ExcludedSubranges.swift
//  iTerm2SharedARC
//
//  Build a disjoint set of character-mode subselections by subtracting a
//  list of excluded subranges from an outer abs coord range. Used by
//  "Select Current Command" so PS2 prefix cells and right-prompt cells
//  don't get dragged into the clipboard, but the helper itself is generic
//  and knows nothing about the OSC 133 prompt model.
//
//  The set arithmetic lives on VT100GridAbsCoordRange.subtracting(_:)
//  (VT100GridTypes+Swift.swift) and is tested in isolation. This file
//  is responsible for the RC → abs-range resolution, the iTermSubSelection
//  wrapping, and the `connected` flag that decides whether copied text
//  gets a newline between two pieces.
//

import Foundation

@objc extension iTermSubSelection {
    /// Subtract every resolvable cell of every range in `excludedSubranges`
    /// from `range` and return the disjoint pieces wrapped as
    /// character-mode iTermSubSelections.
    ///
    /// - Subranges whose endpoints aren't currently resolvable
    ///   (status != .valid) are silently skipped.
    /// - `connected` is set to YES on a piece iff the *next* piece's first
    ///   included row equals this piece's last included row, so copied
    ///   text gets no inter-piece newline for same-row siblings (content
    ///   straddling a right-prompt) and a newline for pieces that cross a
    ///   row boundary (PS2-style multi-line input).
    /// - Returns `[]` when `range` is invalid, empty, or fully covered by
    ///   the exclusions.
    @objc(subSelectionsInRange:excludingSubranges:width:)
    static func subSelections(in range: VT100GridAbsCoordRange,
                              excluding excludedSubranges: [ResilientCoordinateRange]?,
                              width: Int32) -> [iTermSubSelection] {
        let excludedAbsRanges: [VT100GridAbsCoordRange] = (excludedSubranges ?? [])
            .compactMap { r in
                guard r.start.status == .valid, r.end.status == .valid else {
                    return nil
                }
                return r.absRange
            }
        let pieces = range.subtracting(excludedAbsRanges)
        return pieces.enumerated().map { (i, piece) in
            let sub = iTermSubSelection(absRange: VT100GridAbsWindowedRangeMake(piece, 0, 0),
                                        mode: .kiTermSelectionModeCharacter,
                                        width: width)
            if i + 1 < pieces.count {
                let next = pieces[i + 1]
                // `piece.end` is exclusive: a piece covering row Y entirely
                // has end.y == Y + 1 with end.x == 0, so the last
                // *included* row is end.y - 1 in that case, otherwise end.y.
                let lastIncludedRow = (piece.end.x > 0) ? piece.end.y : piece.end.y - 1
                sub.connected = (lastIncludedRow == next.start.y)
            }
            return sub
        }
    }
}

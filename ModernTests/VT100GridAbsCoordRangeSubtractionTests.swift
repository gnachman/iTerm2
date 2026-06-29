//
//  VT100GridAbsCoordRangeSubtractionTests.swift
//  iTerm2
//
//  Exhaustive tests for VT100GridAbsCoordRange.subtracting(_:) — the pure
//  set-arithmetic helper that powers selection clipping. The cases below
//  exist to flush out the two recurring set-subtraction hazards: duplicate
//  components and empty components. They cover trivial / boundary inputs,
//  single and multiple exclusions in every position, overlap / nesting /
//  duplicates / unsorted input, exclusions that extend past either end of
//  the outer range, exclusions that are individually empty, and
//  multi-row outer ranges.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100GridAbsCoordRangeSubtractionTests: XCTestCase {

    // MARK: - Helpers

    /// Build an abs coord range with half-open semantics: [start, end).
    private func r(_ sx: Int, _ sy: Int, _ ex: Int, _ ey: Int) -> VT100GridAbsCoordRange {
        return VT100GridAbsCoordRangeMake(Int32(sx), Int64(sy), Int32(ex), Int64(ey))
    }

    /// Equality-by-value check (VT100GridAbsCoordRangeEquals isn't great
    /// when one side is freshly constructed; this just compares fields).
    private func eq(_ a: VT100GridAbsCoordRange, _ b: VT100GridAbsCoordRange) -> Bool {
        return a.start.x == b.start.x && a.start.y == b.start.y
            && a.end.x == b.end.x && a.end.y == b.end.y
    }

    private func assertPieces(_ got: [VT100GridAbsCoordRange],
                              _ expected: [VT100GridAbsCoordRange],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, expected.count,
                       "piece count mismatch: got \(got), expected \(expected)",
                       file: file, line: line)
        for (i, (g, e)) in zip(got, expected).enumerated() {
            XCTAssertTrue(eq(g, e),
                          "piece \(i) mismatch: got \(g.description), expected \(e.description)",
                          file: file, line: line)
        }
    }

    /// Sanity invariants every result must hold:
    /// - No empty pieces (start < end).
    /// - No two pieces share a cell (sorted by start, each piece.end <= next.start).
    /// - All pieces lie strictly inside `outer`.
    /// - Pieces appear in row-major order (sorted by start).
    private func assertWellFormed(_ pieces: [VT100GridAbsCoordRange],
                                  inside outer: VT100GridAbsCoordRange,
                                  file: StaticString = #filePath, line: UInt = #line) {
        for p in pieces {
            XCTAssertTrue(p.start < p.end, "empty piece in output: \(p.description)",
                          file: file, line: line)
            XCTAssertFalse(p.start < outer.start, "piece below outer start: \(p.description)",
                           file: file, line: line)
            XCTAssertFalse(outer.end < p.end, "piece above outer end: \(p.description)",
                           file: file, line: line)
        }
        for i in 1..<pieces.count {
            XCTAssertFalse(pieces[i - 1].end > pieces[i].start,
                           "pieces overlap or out of order at \(i): \(pieces[i - 1].description) vs \(pieces[i].description)",
                           file: file, line: line)
        }
    }

    // MARK: - Trivial / invalid inputs

    func test_emptyOuter_returnsEmpty() {
        let outer = r(5, 0, 5, 0)  // start == end
        XCTAssertTrue(outer.subtracting([]).isEmpty)
        XCTAssertTrue(outer.subtracting([r(0, 0, 10, 0)]).isEmpty)
    }

    func test_invalidOuter_returnsEmpty() {
        XCTAssertTrue(r(-1, -1, 10, 0).subtracting([]).isEmpty)
        XCTAssertTrue(r(0, -1, 10, 0).subtracting([]).isEmpty)
        XCTAssertTrue(r(-1, 0, 10, 0).subtracting([]).isEmpty)
    }

    func test_outerWithNoExclusions_returnsOuter() {
        let outer = r(0, 0, 10, 0)
        assertPieces(outer.subtracting([]), [outer])
        assertWellFormed(outer.subtracting([]), inside: outer)
    }

    func test_emptyExclusionInList_isIgnored() {
        let outer = r(0, 0, 10, 0)
        let empty = r(3, 0, 3, 0)
        assertPieces(outer.subtracting([empty]), [outer])
    }

    // MARK: - Single exclusion, single-row outer

    func test_exclusionInMiddle_splitsInTwo() {
        let outer = r(0, 0, 10, 0)
        let pieces = outer.subtracting([r(4, 0, 7, 0)])
        assertPieces(pieces, [r(0, 0, 4, 0), r(7, 0, 10, 0)])
        assertWellFormed(pieces, inside: outer)
    }

    func test_exclusionAtStart_clipsLeading() {
        let outer = r(2, 0, 10, 0)
        let pieces = outer.subtracting([r(2, 0, 5, 0)])
        assertPieces(pieces, [r(5, 0, 10, 0)])
    }

    func test_exclusionAtEnd_clipsTrailing() {
        let outer = r(0, 0, 10, 0)
        let pieces = outer.subtracting([r(7, 0, 10, 0)])
        assertPieces(pieces, [r(0, 0, 7, 0)])
    }

    func test_exclusionCoversWhole_returnsEmpty() {
        let outer = r(2, 0, 8, 0)
        assertPieces(outer.subtracting([r(2, 0, 8, 0)]), [])
    }

    func test_exclusionLargerThanOuter_returnsEmpty() {
        let outer = r(2, 0, 8, 0)
        assertPieces(outer.subtracting([r(0, 0, 100, 0)]), [])
    }

    // MARK: - Out-of-bounds exclusions are ignored

    func test_exclusionEntirelyBeforeOuter_isNoOp() {
        let outer = r(10, 0, 20, 0)
        let pieces = outer.subtracting([r(0, 0, 5, 0)])
        assertPieces(pieces, [outer])
    }

    func test_exclusionEntirelyAfterOuter_isNoOp() {
        let outer = r(0, 0, 10, 0)
        let pieces = outer.subtracting([r(50, 0, 60, 0)])
        assertPieces(pieces, [outer])
    }

    func test_exclusionAdjacentBeforeOuter_isNoOp() {
        // [0,5) and outer starts at 5 — exclusion is exactly adjacent on
        // the low side, doesn't overlap.
        let outer = r(5, 0, 10, 0)
        let pieces = outer.subtracting([r(0, 0, 5, 0)])
        assertPieces(pieces, [outer])
    }

    func test_exclusionAdjacentAfterOuter_isNoOp() {
        // outer ends at 10, exclusion [10,15) — adjacent on the high side.
        let outer = r(0, 0, 10, 0)
        let pieces = outer.subtracting([r(10, 0, 15, 0)])
        assertPieces(pieces, [outer])
    }

    func test_exclusionStraddlesStart_clipsLeft() {
        let outer = r(5, 0, 15, 0)
        let pieces = outer.subtracting([r(0, 0, 8, 0)])
        assertPieces(pieces, [r(8, 0, 15, 0)])
    }

    func test_exclusionStraddlesEnd_clipsRight() {
        let outer = r(5, 0, 15, 0)
        let pieces = outer.subtracting([r(12, 0, 25, 0)])
        assertPieces(pieces, [r(5, 0, 12, 0)])
    }

    // MARK: - Multiple exclusions

    func test_twoDisjointExclusionsInMiddle_threePieces() {
        let outer = r(0, 0, 20, 0)
        let pieces = outer.subtracting([r(4, 0, 6, 0), r(12, 0, 14, 0)])
        assertPieces(pieces, [r(0, 0, 4, 0), r(6, 0, 12, 0), r(14, 0, 20, 0)])
        assertWellFormed(pieces, inside: outer)
    }

    func test_unsortedInput_sortedInternally() {
        let outer = r(0, 0, 20, 0)
        let pieces = outer.subtracting([r(12, 0, 14, 0), r(4, 0, 6, 0)])
        assertPieces(pieces, [r(0, 0, 4, 0), r(6, 0, 12, 0), r(14, 0, 20, 0)])
    }

    // MARK: - Adjacency: two exclusions touching at one point

    func test_adjacentExclusionsNoGap_producesTwoOuterPieces() {
        // [3,5) and [5,10) — no cell between them — should NOT emit an
        // empty piece between them.
        let outer = r(0, 0, 15, 0)
        let pieces = outer.subtracting([r(3, 0, 5, 0), r(5, 0, 10, 0)])
        assertPieces(pieces, [r(0, 0, 3, 0), r(10, 0, 15, 0)])
        assertWellFormed(pieces, inside: outer)
    }

    // MARK: - Overlap and containment

    func test_overlappingExclusions_treatedAsUnion() {
        // [3,8) and [5,12) overlap on [5,8) → union [3,12).
        let outer = r(0, 0, 20, 0)
        let pieces = outer.subtracting([r(3, 0, 8, 0), r(5, 0, 12, 0)])
        assertPieces(pieces, [r(0, 0, 3, 0), r(12, 0, 20, 0)])
    }

    func test_nestedExclusion_outerWins() {
        // [3,15) contains [6,10) — output should match just [3,15).
        let outer = r(0, 0, 20, 0)
        let pieces = outer.subtracting([r(3, 0, 15, 0), r(6, 0, 10, 0)])
        assertPieces(pieces, [r(0, 0, 3, 0), r(15, 0, 20, 0)])
    }

    func test_nestedExclusionReversedOrder() {
        // Same as above with nested-first ordering.
        let outer = r(0, 0, 20, 0)
        let pieces = outer.subtracting([r(6, 0, 10, 0), r(3, 0, 15, 0)])
        assertPieces(pieces, [r(0, 0, 3, 0), r(15, 0, 20, 0)])
    }

    func test_duplicateExclusions_sameAsOne() {
        let outer = r(0, 0, 20, 0)
        let pieces = outer.subtracting([r(5, 0, 10, 0), r(5, 0, 10, 0), r(5, 0, 10, 0)])
        assertPieces(pieces, [r(0, 0, 5, 0), r(10, 0, 20, 0)])
        assertWellFormed(pieces, inside: outer)
    }

    func test_threeOverlappingExclusionsCovering_returnsEmpty() {
        let outer = r(0, 0, 20, 0)
        let pieces = outer.subtracting([r(0, 0, 8, 0), r(5, 0, 15, 0), r(12, 0, 20, 0)])
        assertPieces(pieces, [])
    }

    // MARK: - Multi-row outer

    func test_multiRowOuter_exclusionOnMiddleRow() {
        // Outer covers rows 0-2 (end at row 2 col 0 — exclusive).
        // Exclude all of row 1 by ex = (0,1) → (0,2).
        let outer = r(0, 0, 0, 3)  // start (0,0), end (0,3) exclusive
        let pieces = outer.subtracting([r(0, 1, 0, 2)])
        assertPieces(pieces, [r(0, 0, 0, 1), r(0, 2, 0, 3)])
        assertWellFormed(pieces, inside: outer)
    }

    func test_multiRowOuter_exclusionSpansRowBoundary() {
        // Outer (0,0) → (0,3). Exclusion (5,0) → (5,1) — straddles end of
        // row 0 into row 1.
        let outer = r(0, 0, 0, 3)
        let pieces = outer.subtracting([r(5, 0, 5, 1)])
        // First piece is row 0 cols 0..5; gap is row 0 col 5 → row 1 col 5
        // (excluded); resumes at row 1 col 5 through end of outer.
        assertPieces(pieces, [r(0, 0, 5, 0), r(5, 1, 0, 3)])
        assertWellFormed(pieces, inside: outer)
    }

    func test_multiRowOuter_twoExclusionsOneOnEachRow() {
        // Outer (0,0) → (0,3). PS2 prefix on row 1 (0,1)→(2,1), and
        // right-prompt on row 0 (8,0)→(10,0).
        let outer = r(0, 0, 0, 3)
        let pieces = outer.subtracting([r(8, 0, 10, 0), r(0, 1, 2, 1)])
        assertPieces(pieces, [r(0, 0, 8, 0), r(10, 0, 0, 1), r(2, 1, 0, 3)])
        assertWellFormed(pieces, inside: outer)
    }

    // MARK: - Hazards: ensure no duplicate, no empty in pathological cases

    func test_cascadingOverlaps_noDuplicates() {
        // Each exclusion overlaps the next. Union covers [3,30).
        let outer = r(0, 0, 40, 0)
        let pieces = outer.subtracting([
            r(3, 0, 12, 0),
            r(10, 0, 20, 0),
            r(18, 0, 30, 0),
        ])
        assertPieces(pieces, [r(0, 0, 3, 0), r(30, 0, 40, 0)])
        assertWellFormed(pieces, inside: outer)
    }

    func test_exclusionMatchingOuterStart_noEmptyLeadingPiece() {
        let outer = r(5, 0, 15, 0)
        let pieces = outer.subtracting([r(5, 0, 10, 0)])
        // Must NOT have an empty leading piece (5,0)→(5,0).
        assertPieces(pieces, [r(10, 0, 15, 0)])
        assertWellFormed(pieces, inside: outer)
    }

    func test_exclusionMatchingOuterEnd_noEmptyTrailingPiece() {
        let outer = r(0, 0, 10, 0)
        let pieces = outer.subtracting([r(5, 0, 10, 0)])
        // Must NOT have an empty trailing piece (10,0)→(10,0).
        assertPieces(pieces, [r(0, 0, 5, 0)])
        assertWellFormed(pieces, inside: outer)
    }

    func test_exclusionExactlyMatchingOuter_returnsEmpty() {
        let outer = r(0, 0, 10, 0)
        let pieces = outer.subtracting([r(0, 0, 10, 0)])
        XCTAssertTrue(pieces.isEmpty)
    }

    func test_multipleExclusionsMatchingOuterExactly_returnsEmpty() {
        let outer = r(0, 0, 10, 0)
        let pieces = outer.subtracting([
            r(0, 0, 10, 0),
            r(0, 0, 10, 0),
            r(0, 0, 10, 0),
        ])
        XCTAssertTrue(pieces.isEmpty)
    }

    func test_mixedValidAndInvalidExclusions_filtersInvalid() {
        // The invalid (empty) exclusions must be dropped without
        // affecting the valid one.
        let outer = r(0, 0, 20, 0)
        let pieces = outer.subtracting([
            r(7, 0, 7, 0),  // empty
            r(8, 0, 12, 0),
            r(15, 0, 15, 0),  // empty
        ])
        assertPieces(pieces, [r(0, 0, 8, 0), r(12, 0, 20, 0)])
        assertWellFormed(pieces, inside: outer)
    }
}

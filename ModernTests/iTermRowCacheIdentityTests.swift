//
//  iTermRowCacheIdentityTests.swift
//  ModernTests
//
//  Tests for the collision-free identities that key the per-row draw cache:
//  the grid's per-line content generation, iTermColorMap generation propagation
//  on copy, and the config-generation tracker's exact comparison.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermRowCacheIdentityTests: XCTestCase {

    // MARK: - Grid line content generation

    private func makeGrid() -> VT100Grid {
        return VT100Grid(size: VT100GridSize(width: 5, height: 3), delegate: nil)!
    }

    func testGridLineGenerationAdvancesWhenMarkedDirty() {
        let grid = makeGrid()
        let before = grid.generation(forLine: 0)
        grid.markCharDirty(true, at: VT100GridCoord(x: 0, y: 0), updateTimestamp: false)
        XCTAssertNotEqual(before, grid.generation(forLine: 0))
    }

    func testGridLineGenerationIsStableWithoutChange() {
        let grid = makeGrid()
        grid.markCharDirty(true, at: VT100GridCoord(x: 0, y: 0), updateTimestamp: false)
        XCTAssertEqual(grid.generation(forLine: 0), grid.generation(forLine: 0))
    }

    // Generations must be unique across lines, since the cache keys content on
    // the generation value alone (within a source).
    func testGridLineGenerationsAreDistinctAcrossLines() {
        let grid = makeGrid()
        grid.markCharDirty(true, at: VT100GridCoord(x: 0, y: 0), updateTimestamp: false)
        grid.markCharDirty(true, at: VT100GridCoord(x: 0, y: 1), updateTimestamp: false)
        XCTAssertNotEqual(grid.generation(forLine: 0), grid.generation(forLine: 1))
    }

    // The grid copy is what feeds the renderer, so the line generation must
    // survive copying, else all static lines revert to 0 and collide.
    func testGridLineGenerationSurvivesGridCopy() {
        let grid = makeGrid()
        grid.markCharDirty(true, at: VT100GridCoord(x: 0, y: 0), updateTimestamp: false)
        let g = grid.generation(forLine: 0)
        XCTAssertNotEqual(g, 0)
        let copy = grid.copy() as! VT100Grid
        XCTAssertEqual(copy.generation(forLine: 0), g)
    }

    func testDistinctGridLineGenerationsSurviveGridCopy() {
        let grid = makeGrid()
        grid.markCharDirty(true, at: VT100GridCoord(x: 0, y: 0), updateTimestamp: false)
        grid.markCharDirty(true, at: VT100GridCoord(x: 0, y: 1), updateTimestamp: false)
        let copy = grid.copy() as! VT100Grid
        XCTAssertEqual(copy.generation(forLine: 0), grid.generation(forLine: 0))
        XCTAssertEqual(copy.generation(forLine: 1), grid.generation(forLine: 1))
        XCTAssertNotEqual(copy.generation(forLine: 0), copy.generation(forLine: 1))
    }

    // copyDirtyFromGrid: is the per-frame sync into the immutable grid the
    // renderer reads. On a scroll it copies shifted content into fixed dest
    // slots (screenTop_ is not propagated), so the dest must adopt the source's
    // generation even for lines whose own dirty range is empty, or it would
    // report stale identities. The existing -copy test doesn't exercise this.
    func testCopyDirtyFromGridMirrorsGenerationForScrolledCleanLines() {
        let source = VT100Grid(size: VT100GridSize(width: 4, height: 4), delegate: nil)!
        let dest = VT100Grid(size: VT100GridSize(width: 4, height: 4), delegate: nil)!
        for y in Int32(0)..<4 {
            source.markCharDirty(true, at: VT100GridCoord(x: 0, y: y), updateTimestamp: false)
        }
        // Clear dirty but keep generations (setDirty:NO doesn't bump).
        source.markAllCharsDirty(false, updateTimestamps: false)
        // didScroll copies content even though the lines are now clean.
        dest.copyDirty(from: source, didScroll: true)
        for y in Int32(0)..<4 {
            XCTAssertEqual(dest.generation(forLine: y), source.generation(forLine: y),
                           "dest line \(y) must mirror the source generation")
        }
    }

    // The fast-path scroll rotates screenTop_ and blanks the recycled bottom
    // lines; those lineInfos previously held (and drew) the top rows, so their
    // generation must be advanced or the cache would render them as ghosts of
    // the old top content.
    func testFastPathScrollAdvancesGenerationOfBlankedLines() {
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: 4, height: height), delegate: nil)!
        for y in 0..<height {
            grid.markCharDirty(true, at: VT100GridCoord(x: 0, y: y), updateTimestamp: false)
        }
        let maxBefore = (0..<height).map { grid.generation(forLine: $0) }.max()!
        grid.cursor = VT100GridCoord(x: 0, y: height - 1)
        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.fastPathScrollLinesAtAndAboveCursor(into: lineBuffer)
        for y in 0..<height {
            XCTAssertGreaterThan(grid.generation(forLine: y), maxBefore)
        }
    }

    // MARK: - iTermColorMap generation propagates on copy

    func testColorMapCopyPreservesGeneration() {
        let map = iTermColorMap()
        map.setColor(.red, forKey: Int32(kColorMapForeground))
        let g = map.generation
        let copy = map.copy() as! iTermColorMap
        XCTAssertEqual(copy.generation, g)
    }

    func testColorMapCopyIsIndependentOfLaterMutation() {
        let map = iTermColorMap()
        let copy = map.copy() as! iTermColorMap
        let copyGeneration = copy.generation
        map.setColor(.blue, forKey: Int32(kColorMapForeground))
        XCTAssertEqual(copy.generation, copyGeneration)   // copy unaffected
        XCTAssertNotEqual(map.generation, copyGeneration) // original advanced
    }

    // MARK: - Config-generation tracker (exact, collision-free comparison)

    func testConfigGenerationStableForIdenticalInputs() {
        let tracker = iTermConfigGenerationTracker()
        var inputs = iTermRowRenderInputs()
        let colorSpace = NSColorSpace.sRGB
        let g1 = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        let g2 = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        XCTAssertEqual(g1, g2)
    }

    func testConfigGenerationAdvancesWhenScalarChanges() {
        let tracker = iTermConfigGenerationTracker()
        var inputs = iTermRowRenderInputs()
        let colorSpace = NSColorSpace.sRGB
        let g1 = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        inputs.reverseVideo = true
        let g2 = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        XCTAssertNotEqual(g1, g2)
    }

    func testConfigGenerationAdvancesWhenColorMapGenerationChanges() {
        let tracker = iTermConfigGenerationTracker()
        var inputs = iTermRowRenderInputs()
        let colorSpace = NSColorSpace.sRGB
        let g1 = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        inputs.colorMapGeneration = 42
        let g2 = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        XCTAssertNotEqual(g1, g2)
    }

    func testConfigGenerationAdvancesWhenColorSpaceChanges() {
        let tracker = iTermConfigGenerationTracker()
        var inputs = iTermRowRenderInputs()
        let g1 = tracker.generation(for: &inputs, colorSpace: .sRGB, fontTable: nil)
        let g2 = tracker.generation(for: &inputs, colorSpace: .genericRGB, fontTable: nil)
        XCTAssertNotEqual(g1, g2)
    }

    // It's a monotonic counter, not a hash: reverting inputs yields a fresh value
    // rather than reusing the old one. Acceptable because config changes rarely.
    func testConfigGenerationDoesNotReuseValueAfterRevert() {
        let tracker = iTermConfigGenerationTracker()
        var inputs = iTermRowRenderInputs()
        let colorSpace = NSColorSpace.sRGB
        let a = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        inputs.reverseVideo = true
        _ = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        inputs.reverseVideo = false
        let c = tracker.generation(for: &inputs, colorSpace: colorSpace, fontTable: nil)
        XCTAssertNotEqual(a, c)
    }
}

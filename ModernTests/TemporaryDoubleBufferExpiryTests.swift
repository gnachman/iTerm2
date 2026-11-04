//
//  TemporaryDoubleBufferExpiryTests.swift
//  iTerm2
//
//  The flicker fixer (temporary double buffer) draws a saved copy of the grid
//  while the screen is being redrawn. While a saved grid is swapped in, only
//  its own dirty bits decide which rows get repainted. When a saved grid that
//  was drawn expires, every row has to be repainted with the real grid's
//  contents. If the cursor is hidden again (or a new synchronized update
//  begins) before the next sync, the next saved grid has to carry that
//  request. Otherwise rows that changed while the first saved grid was on
//  screen keep showing stale content in the legacy renderer, which repaints
//  only dirty rects.
//

import XCTest
@testable import iTerm2SharedARC

final class TemporaryDoubleBufferExpiryTests: XCTestCase {
    func test_snapshotTakenAfterExpiryRepaintsEveryRow() {
        let width: Int32 = 80
        let height: Int32 = 24
        let harness = TerminalTestHarness(width: Int(width), height: Int(height))
        harness.feedEscapeSequence(Array("hello\r\nworld\r\n".utf8))
        harness.sync()

        var undirtyRows = [Int32]()
        // Everything happens in one join so the saved grid's expiration timer, which runs on the
        // mutation queue, can't fire partway through.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let buffer = mutableState.unconditionalTemporaryDoubleBuffer

            // A saved grid is taken and then drawn by a sync, which also clears the mutable
            // grid's dirty bits.
            buffer.startExplicitly()
            buffer.drewSavedGrid = true
            mutableState.currentGrid.markAllCharsDirty(false, updateTimestamps: false)

            // It expires, then a new one is taken before the next sync.
            buffer.resetExplicitly()
            buffer.startExplicitly()

            guard let grid = buffer.savedState?.grid else {
                XCTFail("Expected a saved grid")
                return
            }
            for y in 0..<height {
                let range = grid.dirtyRange(forLine: y)
                if range.location != 0 || range.length < width {
                    undirtyRows.append(y)
                }
            }
            buffer.resetExplicitly()
        })

        XCTAssertEqual(undirtyRows, [],
                       "A saved grid taken after a drawn one expired must mark every row for repaint")
    }
}

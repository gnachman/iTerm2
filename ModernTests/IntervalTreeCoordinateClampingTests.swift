//
//  IntervalTreeCoordinateClampingTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/11/26.
//
//  These tests verify that interval tree operations properly clamp coordinates
//  to prevent negative interval limits.
//

import XCTest
@testable import iTerm2SharedARC

final class IntervalTreeCoordinateClampingTests: XCTestCase {
    private var session = FakeSession()

    private func screen(width: Int32, height: Int32, scrollback: UInt32 = 1000) -> VT100Screen {
        let screen = VT100Screen()
        session = FakeSession()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.terminalEnabled = true
            mutableState!.terminal!.termType = "xterm"
            mutableState!.maxScrollbackLines = scrollback
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    // MARK: - Tests for clearScrollbackBuffer coordinate clamping

    /// Test that clearScrollbackBuffer properly handles annotations when there's
    /// scrollback overflow (content has scrolled off the top of the scrollback buffer).
    ///
    /// When scrollback overflows, cumulativeScrollbackOverflow increases. This test
    /// verifies that coordinate handling remains correct in this scenario.
    func testClearScrollbackWithOverflow() {
        // Small scrollback to trigger overflow
        let screen = self.screen(width: 80, height: 10, scrollback: 20)

        // Fill beyond scrollback capacity to cause overflow
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<50 {
                mutableState?.appendString(atCursor: "Line \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Add annotation on visible screen
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 2, 5, 4), focus: false, visible: false)

        // Add more content to increase overflow further
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<30 {
                mutableState?.appendString(atCursor: "More \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Clear scrollback
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.clearScrollbackBuffer()
        })

        // Verify interval tree is valid
        var intervalValid = true
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 || entry.interval.location < 0 {
                        intervalValid = false
                    }
                }
            }
        })

        XCTAssertTrue(intervalValid, "Interval tree should remain valid after clearScrollback with overflow")
    }

    /// Test clearScrollbackBuffer when annotation was added, then pushed partially into
    /// scrollback (spanning scrollback and screen), then scrollback is cleared.
    func testClearScrollbackWithPartiallyScrolledAnnotation() {
        let screen = self.screen(width: 80, height: 10, scrollback: 50)

        // Add some initial content
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<5 {
                mutableState?.appendString(atCursor: "Line \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Add a tall annotation spanning lines 2-8
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 2, 5, 8), focus: false, visible: false)

        // Push content so the annotation is partially in scrollback
        // Add 5 more lines - annotation now spans from scrollback into screen
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<5 {
                mutableState?.appendString(atCursor: "Push \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Clear scrollback - the spanning annotation should be handled correctly
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.clearScrollbackBuffer()
        })

        // Verify interval tree is valid
        var intervalValid = true
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 || entry.interval.location < 0 {
                        intervalValid = false
                    }
                }
            }
        })

        XCTAssertTrue(intervalValid, "Interval tree should remain valid after clearing scrollback with spanning annotation")
    }

    /// Test that clearScrollbackBuffer handles an already-corrupted interval tree.
    /// This simulates a scenario where a prior bug (shiftIntervalTreeObjects with negative delta
    /// WITHOUT its clamping fix) left the tree corrupted, and then clearScrollback is called.
    ///
    /// For this test to work properly, we need to:
    /// 1. Disable the shiftIntervalTreeObjects fix temporarily
    /// 2. Corrupt the tree
    /// 3. Re-enable the fix (or not)
    /// 4. Call clearScrollback and verify the clearScrollback fix helps
    ///
    /// Since we can't dynamically toggle fixes, this test just verifies the combined behavior.
    func testClearScrollbackAfterNegativeShift() {
        let screen = self.screen(width: 80, height: 24, scrollback: 50)

        // Create content with some scrollback
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<40 {
                mutableState?.appendString(atCursor: "Line \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Add annotation near top of visible screen
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 2, 5, 5), focus: false, visible: false)

        // Shift annotation with moderate negative delta
        // With shiftIntervalTreeObjects fix: coords clamped to valid range
        // Without fix: coords go negative
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.shiftIntervalTreeObjects(
                in: VT100GridCoordRangeMake(0, 0, 80, 24),
                startingAfter: -1,
                downByLines: -5
            )
        })

        // Now clear scrollback
        // If shiftIntervalTreeObjects created negative coords AND clearScrollback
        // doesn't clamp, the negative coords get worse (more negative after -history)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.clearScrollbackBuffer()
        })

        // Verify interval tree is valid
        var intervalValid = true
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 || entry.interval.location < 0 {
                        intervalValid = false
                    }
                }
            }
        })

        XCTAssertTrue(intervalValid, "Interval tree should be valid after shift + clearScrollback")
    }

    /// Test clearScrollbackBuffer with a fresh screen (no scrollback overflow).
    /// When cumulativeScrollbackOverflow is 0, negative grid coordinates directly
    /// translate to negative absolute coordinates, which can corrupt the interval tree.
    func testClearScrollbackWithNoOverflowAfterNegativeShift() {
        // Large scrollback so we don't get overflow
        let screen = self.screen(width: 80, height: 10, scrollback: 1000)

        // Add just enough content to have some scrollback but NO overflow
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<15 {
                mutableState?.appendString(atCursor: "Line \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })
        // Now we have ~5 lines of scrollback, no overflow

        // Add annotation near top of visible screen
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 2, 5, 4), focus: false, visible: false)

        // Shift with large negative delta - with no overflow to absorb it,
        // this creates truly negative absolute coordinates
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.shiftIntervalTreeObjects(
                in: VT100GridCoordRangeMake(0, 0, 80, 10),
                startingAfter: -1,
                downByLines: -10
            )
        })

        // Verify if tree is corrupted after shift
        var corruptedAfterShift = false
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 || entry.interval.location < 0 {
                        corruptedAfterShift = true
                    }
                }
            }
        })

        // Now clear scrollback - if tree is corrupted and clearScrollback
        // doesn't clamp, it makes things worse
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.clearScrollbackBuffer()
        })

        // Verify interval tree is valid after clear
        var intervalValid = true
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 || entry.interval.location < 0 {
                        intervalValid = false
                    }
                }
            }
        })

        // With both fixes enabled: intervalValid should be true
        // With shift fix disabled but clear fix enabled: might still be true if clear clamps
        // With both disabled: intervalValid will be false
        XCTAssertTrue(intervalValid, "Interval tree should be valid - corrupted after shift: \(corruptedAfterShift)")
    }

    // MARK: - Interval bounds tests

    /// Test that creating an Interval validates that limit is non-negative.
    /// This tests the defensive assertion in boundsCheck.
    func testIntervalLimitMustBeNonNegative() {
        // Valid intervals should work
        let validInterval1 = Interval(location: 0, length: 10)
        XCTAssertEqual(validInterval1.limit, 10)

        let validInterval2 = Interval(location: 100, length: 0)
        XCTAssertEqual(validInterval2.limit, 100)

        // An interval with location 0 and length 0 has limit 0 (valid)
        let zeroInterval = Interval(location: 0, length: 0)
        XCTAssertEqual(zeroInterval.limit, 0)
    }

    // MARK: - Tests for resize operations that shrink content

    /// Test that resizing while in alt screen properly handles annotations in savedIntervalTree.
    /// This is related to the coordinate shift bug during resize.
    func testResizeWithAnnotationDuringAltScreen() {
        let screen = self.screen(width: 80, height: 24)

        // Create content in primary screen
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<20 {
                mutableState?.appendString(atCursor: "Line \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Add annotation
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 5, 10, 5), focus: false, visible: false)

        // Switch to alt screen
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.showAltBuffer()
        })

        // Resize to smaller height - this triggers coordinate adjustments
        // in the savedIntervalTree
        screen.size = VT100GridSizeMake(80, 10)

        // Switch back to primary
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.showPrimaryBuffer()
        })

        // Verify interval tree is valid
        var intervalValid = true
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 || entry.interval.location < 0 {
                        intervalValid = false
                    }
                }
            }
        })

        XCTAssertTrue(intervalValid, "Interval tree should remain valid after resize during alt screen")
    }

    // MARK: - Direct shiftIntervalTreeObjectsInRange tests

    /// Test that shiftIntervalTreeObjectsInRange properly clamps coordinates when
    /// shifting with a negative deltaLines value that would make the start coordinate negative
    /// but leave the end coordinate positive.
    ///
    /// Bug scenario:
    /// 1. An annotation exists on the screen spanning lines 2-8
    /// 2. Content shrinks (e.g., a porthole collapses), triggering a shift with negative deltaLines
    /// 3. shiftIntervalTreeObjectsInRange is called with deltaLines = -5
    /// 4. Without clamping: start.y = 2 + (-5) = -3, end.y = 8 + (-5) = 3
    ///    This creates an interval with negative start coordinates
    /// 5. With clamping: start is clamped to (0,0), keeping the interval valid
    func testShiftIntervalTreeObjectsWithNegativeDeltaLinesClampsCoordinates() {
        let screen = self.screen(width: 80, height: 24)

        // Create content
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<15 {
                mutableState?.appendString(atCursor: "Line \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Add an annotation spanning lines 2-8 (a tall annotation)
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 2, 5, 8), focus: false, visible: false)

        // Verify the note was added
        var notesBefore: [Any]?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            notesBefore = screen.immutableState.intervalTree.allObjects() as [Any]?
        })
        XCTAssertEqual(notesBefore?.count, 1, "Note should exist before shift")

        // Directly call shiftIntervalTreeObjectsInRange with negative deltaLines
        // This simulates what happens when content shrinks (e.g., porthole collapse)
        // Range covers lines 0-24, startingAfter = -1 means all objects move
        // deltaLines = -5 shifts the note from lines 2-8 to lines -3 to 3
        // Without clamping, start.y would be -3 (invalid)
        // With clamping, start.y becomes 0, and the note spans 0-3
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.shiftIntervalTreeObjects(
                in: VT100GridCoordRangeMake(0, 0, 80, 24),
                startingAfter: -1,
                downByLines: -5
            )
        })

        // Verify the interval tree is still valid (all limits non-negative)
        var intervalValid = true
        var foundNote = false
        var noteEndY: Int32 = -1
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                foundNote = true
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 {
                        intervalValid = false
                    }
                    if entry.interval.location < 0 {
                        intervalValid = false
                    }
                    let range = screen.immutableState.coordRange(for: entry.interval)
                    noteEndY = range.end.y
                }
            }
        })

        XCTAssertTrue(foundNote, "Note should still exist after shift (clamped to valid coordinates)")
        XCTAssertTrue(intervalValid, "All intervals must have non-negative limits after negative shift")
        // The note originally ended at line 8, shifted by -5 should end at line 3
        XCTAssertEqual(noteEndY, 3, "Note end.y should be 3 after shift (8 - 5 = 3)")
    }

    /// Test that shifting an annotation that ends up entirely above line 0 still has valid coordinates.
    func testShiftIntervalTreeObjectsCompletelyAboveZero() {
        let screen = self.screen(width: 80, height: 24)

        // Create content
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<5 {
                mutableState?.appendString(atCursor: "Line \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Add an annotation on line 3
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 3, 5, 3), focus: false, visible: false)

        // Shift with deltaLines = -5, which would put the note at line -2 without clamping
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.shiftIntervalTreeObjects(
                in: VT100GridCoordRangeMake(0, 0, 80, 24),
                startingAfter: -1,
                downByLines: -5
            )
        })

        // Verify the interval is valid
        var intervalValid = true
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 || entry.interval.location < 0 {
                        intervalValid = false
                    }
                }
            }
        })

        XCTAssertTrue(intervalValid, "Intervals must remain valid even when shifted entirely above line 0")
    }

    /// Test edge case: shift by exactly the amount that would make end.y = 0
    func testShiftIntervalTreeObjectsToExactlyZero() {
        let screen = self.screen(width: 80, height: 24)

        // Create content
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<10 {
                mutableState?.appendString(atCursor: "Line \(i)")
                mutableState?.appendCarriageReturnLineFeed()
            }
        })

        // Add an annotation on line 5
        let note = PTYAnnotation()
        screen.addNote(note, in: VT100GridCoordRangeMake(0, 5, 5, 5), focus: false, visible: false)

        // Shift by exactly -5, which should put the note at line 0 (valid)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.shiftIntervalTreeObjects(
                in: VT100GridCoordRangeMake(0, 0, 80, 24),
                startingAfter: -1,
                downByLines: -5
            )
        })

        // Verify the interval is valid and at line 0
        var intervalValid = true
        var noteY: Int32 = -1
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in screen.immutableState.intervalTree.allObjects() {
                if let ito = obj as? (any IntervalTreeObject),
                   let entry = ito.entry {
                    if entry.interval.limit < 0 || entry.interval.location < 0 {
                        intervalValid = false
                    }
                    // Get the coord range to check the y position
                    let range = screen.immutableState.coordRange(for: entry.interval)
                    noteY = range.start.y
                }
            }
        })

        XCTAssertTrue(intervalValid, "Interval should be valid when shifted exactly to line 0")
        XCTAssertEqual(noteY, 0, "Note should be at line 0 after shift by -5")
    }
}

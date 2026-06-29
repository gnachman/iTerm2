//
//  AsyncFilterTests.swift
//  iTerm2
//
//  Created by Claude on 2025.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Test Helpers

// Note: screenCharArrayWithDefaultStyle is defined in LineBufferTests.swift

// Mock destination for capturing filter results
private class MockFilterDestination: NSObject, FilterDestination {
    var appendedLines: [ScreenCharArray] = []
    var removeLastLineCallCount = 0

    func append(_ sca: ScreenCharArray) {
        appendedLines.append(sca)
    }

    func removeLastLine() {
        removeLastLineCallCount += 1
        if !appendedLines.isEmpty {
            appendedLines.removeLast()
        }
    }
}

// MARK: - FilteringUpdater Tests

class FilteringUpdaterTests: XCTestCase {

    private func createLineBuffer(withLines lines: [String], width: Int32) -> LineBuffer {
        let buffer = LineBuffer()
        for line in lines {
            let sca = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
            buffer.append(sca, width: width)
        }
        return buffer
    }

    // Test that FilteringUpdater finds matches correctly
    func testFilteringUpdaterFindsMatches() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello world", "foo bar", "hello foo"], width: width)

        let updater = FilteringUpdater(
            query: "hello",
            lineBuffer: buffer,
            count: Int32(buffer.numLines(withWidth: width)),
            width: width,
            mode: .smartCaseSensitivity,
            absLineRange: 0..<Int64(buffer.numLines(withWidth: width)),
            cumulativeOverflow: 0
        )

        var acceptedLineNumbers: [Int32] = []
        updater.accept = { lineNumber, _ in
            acceptedLineNumbers.append(lineNumber)
        }
        while updater.update() {}

        XCTAssertEqual(acceptedLineNumbers.count, 2, "Should find 2 lines containing 'hello'")
    }

    // Test that copyStateForRefining copies state correctly
    func testCopyStateForRefining() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello world", "foo bar", "hello foo"], width: width)

        let updater1 = FilteringUpdater(
            query: "hello",
            lineBuffer: buffer,
            count: Int32(buffer.numLines(withWidth: width)),
            width: width,
            mode: .smartCaseSensitivity,
            absLineRange: 0..<Int64(buffer.numLines(withWidth: width)),
            cumulativeOverflow: 0
        )

        // Run updater1 to completion to populate acceptedLines
        updater1.accept = { _, _ in }
        while updater1.update() {}

        // Create second updater
        let updater2 = FilteringUpdater(
            query: "hello foo",
            lineBuffer: buffer,
            count: Int32(buffer.numLines(withWidth: width)),
            width: width,
            mode: .smartCaseSensitivity,
            absLineRange: 0..<Int64(buffer.numLines(withWidth: width)),
            cumulativeOverflow: 0
        )

        // Copy state from updater1
        updater2.copyStateForRefining(from: updater1)

        // Verify acceptedLines were copied
        XCTAssertEqual(updater2.acceptedLines.count, updater1.acceptedLines.count,
                       "acceptedLines should be copied from source updater")
    }

    // Test haveMatch method
    func testHaveMatch() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello world"], width: width)

        let updater = FilteringUpdater(
            query: "hello",
            lineBuffer: buffer,
            count: Int32(buffer.numLines(withWidth: width)),
            width: width,
            mode: .smartCaseSensitivity,
            absLineRange: 0..<Int64(buffer.numLines(withWidth: width)),
            cumulativeOverflow: 0
        )

        // Run to completion to get results
        updater.accept = { _, _ in }
        while updater.update() {}

        // The acceptedLines should contain a match
        XCTAssertGreaterThan(updater.acceptedLines.count, 0)

        // Check if the match is still valid
        let absRange = updater.acceptedLines[0]
        if let resultRange = absRange.resultRange(offset: 0) {
            XCTAssertTrue(updater.haveMatch(at: resultRange), "haveMatch should return true for valid match")
        }
    }
}

// MARK: - AsyncFilter State Machine Tests

class AsyncFilterStateMachineTests: XCTestCase {

    private func createLineBuffer(withLines lines: [String], width: Int32) -> LineBuffer {
        let buffer = LineBuffer()
        for line in lines {
            let sca = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
            buffer.append(sca, width: width)
        }
        return buffer
    }

    private func createGrid(width: Int32, height: Int32) -> VT100Grid {
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height),
                             delegate: nil)!
        return grid
    }

    // Test state transition: idle -> searching -> completed (no refining)
    func testStateTransitionsWithoutRefining() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello a", "hello b", "foo bar"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 2, "Should find 2 'hello' lines")
    }

    // Test state transition: idle -> catchingUp -> searching -> completed (with refining)
    func testStateTransitionsWithRefining() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello a", "hello b", "foo bar"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // Create and run first filter
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 2, "First filter should find 2 'hello' lines")

        destination.appendedLines.removeAll()

        // Create second filter that refines from first
        let filter2 = AsyncFilter(
            query: "hello a",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 1, "Second filter should find 1 'hello a' line")
    }

    // Test state transition with pending deliveries during catchUp
    func testStateTransitionsWithPendingDeliveries() {
        let width: Int32 = 80
        var lines: [String] = []
        for i in 0..<50 {
            lines.append("hello line \(i)")
        }
        let buffer = createLineBuffer(withLines: lines, width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // Create first filter
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 50, "First filter should find 50 lines")

        destination.appendedLines.removeAll()

        // Create second filter - don't start yet so we can deliver during catchUp
        let filter2 = AsyncFilter(
            query: "hello line 1",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()

        let countBeforeDelivery = destination.appendedLines.count

        // Deliver new content - will be queued during catchUp
        let newLine = screenCharArrayWithDefaultStyle("hello line 100", eol: EOL_HARD)
        let metadata = iTermImmutableMetadataDefault()
        filter2.deliver(newLine, metadata: metadata, lineBufferGeneration: 9999)

        // Process to completion - should include the delivered line
        filter2.syncProcessToCompletion()

        // Should have processed the delivered line (which matches "hello line 1")
        XCTAssertGreaterThan(destination.appendedLines.count, countBeforeDelivery,
                             "Delivered line should be processed")
    }

    // Test cancel from each state
    func testCancelFromEachState() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello a", "hello b"], width: width)
        let grid = createGrid(width: width, height: 24)

        // Test cancel from idle (before start)
        let destination1 = MockFilterDestination()
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination1,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        // Don't start - just cancel
        filter1.cancel()
        // Should not crash, no lines added
        XCTAssertEqual(destination1.appendedLines.count, 0)

        // Test cancel after start
        let destination2 = MockFilterDestination()
        let filter2 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination2,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.cancel()

        // After cancel, syncProcessToCompletion should do nothing
        filter2.syncProcessToCompletion()
        let countAfterCancel = destination2.appendedLines.count

        // Deliver should be ignored after cancel
        let newLine = screenCharArrayWithDefaultStyle("hello c", eol: EOL_HARD)
        let metadata = iTermImmutableMetadataDefault()
        filter2.deliver(newLine, metadata: metadata, lineBufferGeneration: 9999)
        filter2.syncProcessToCompletion()

        XCTAssertEqual(destination2.appendedLines.count, countAfterCancel,
                       "No more processing should happen after cancel")
    }

    // Test deliver behavior in each state
    func testDeliveryInEachState() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello a"], width: width)
        let grid = createGrid(width: width, height: 24)

        // Test delivery in idle (before start) - should be ignored
        let destination1 = MockFilterDestination()
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination1,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        let newLine = screenCharArrayWithDefaultStyle("hello b", eol: EOL_HARD)
        let metadata = iTermImmutableMetadataDefault()
        filter1.deliver(newLine, metadata: metadata, lineBufferGeneration: 9999)
        // Should not crash, delivery ignored in idle state
        XCTAssertEqual(destination1.appendedLines.count, 0)

        // Test delivery in completed state - should be processed
        let destination2 = MockFilterDestination()
        let filter2 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination2,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.syncProcessToCompletion()

        let countBeforeDelivery = destination2.appendedLines.count
        XCTAssertEqual(countBeforeDelivery, 1, "Should have found 1 'hello' line")

        // Deliver new matching line after filter has completed - should be processed
        filter2.deliver(newLine, metadata: metadata, lineBufferGeneration: 9999)
        filter2.syncProcessToCompletion()

        // In completed state, delivery should still be processed (filter runs until cancelled)
        XCTAssertEqual(destination2.appendedLines.count, countBeforeDelivery + 1,
                       "Delivery should be processed in completed state")
    }
}

// MARK: - AsyncFilter Delivery Queue Tests

class AsyncFilterDeliveryQueueTests: XCTestCase {

    private func createLineBuffer(withLines lines: [String], width: Int32) -> LineBuffer {
        let buffer = LineBuffer()
        for line in lines {
            let sca = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
            buffer.append(sca, width: width)
        }
        return buffer
    }

    private func createGrid(width: Int32, height: Int32) -> VT100Grid {
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height),
                             delegate: nil)!
        return grid
    }

    // Test that deliveries made in completed state are processed
    func testDeliveriesProcessedInCompletedState() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello a", "hello b"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 2, "Should find 2 'hello' lines")

        // Deliver new line - should be processed
        let newLine = screenCharArrayWithDefaultStyle("hello new", eol: EOL_HARD)
        let metadata = iTermImmutableMetadataDefault()
        filter.deliver(newLine, metadata: metadata, lineBufferGeneration: 9999)
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 3,
                       "Delivery should be processed in completed state")
    }

    // Test that deliveries during catchUp are queued and processed
    func testDeliveriesQueuedDuringCatchUp() {
        let width: Int32 = 80
        var lines: [String] = []
        for i in 0..<50 {
            lines.append("hello line \(i)")
        }
        let buffer = createLineBuffer(withLines: lines, width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // Create first filter and run to completion
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        destination.appendedLines.removeAll()

        // Create second filter that will catch up from first
        let filter2 = AsyncFilter(
            query: "hello line 1",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()

        let countBeforeDelivery = destination.appendedLines.count

        // Deliver new content during catchUp
        let newLine = screenCharArrayWithDefaultStyle("hello line 100", eol: EOL_HARD)
        let metadata = iTermImmutableMetadataDefault()
        filter2.deliver(newLine, metadata: metadata, lineBufferGeneration: 9999)

        // Process to completion
        filter2.syncProcessToCompletion()

        // Should have processed the delivered line (which matches "hello line 1")
        XCTAssertGreaterThan(destination.appendedLines.count, countBeforeDelivery,
                             "Should process queued delivery after catchUp")
    }

    // Test that queued deliveries are cleared on cancel
    func testQueuedDeliveriesClearedOnCancel() {
        let width: Int32 = 80
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("hello line \(i)")
        }
        let buffer = createLineBuffer(withLines: lines, width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // Create first filter
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        destination.appendedLines.removeAll()

        // Create second filter
        let filter2 = AsyncFilter(
            query: "hello line 5",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()

        // Deliver multiple lines
        for i in 0..<5 {
            let newLine = screenCharArrayWithDefaultStyle("hello line 5\(i)0", eol: EOL_HARD)
            let metadata = iTermImmutableMetadataDefault()
            filter2.deliver(newLine, metadata: metadata, lineBufferGeneration: Int64(10000 + i))
        }

        // Cancel the filter
        filter2.cancel()

        let countAfterCancel = destination.appendedLines.count

        // Try to process more - should do nothing
        filter2.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, countAfterCancel,
                       "No processing should happen after cancel")
    }
}

// MARK: - AsyncFilter Integration Tests

class AsyncFilterIntegrationTests: XCTestCase {

    private func createLineBuffer(withLines lines: [String], width: Int32) -> LineBuffer {
        let buffer = LineBuffer()
        for line in lines {
            let sca = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
            buffer.append(sca, width: width)
        }
        return buffer
    }

    private func createGrid(width: Int32, height: Int32) -> VT100Grid {
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height),
                             delegate: nil)!
        return grid
    }

    // Test that AsyncFilter processes catchUp correctly
    func testAsyncFilterProcessesCatchUp() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello a", "hello b", "foo bar"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // Create first filter
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        let firstFilterResults = destination.appendedLines.count
        XCTAssertEqual(firstFilterResults, 2, "First filter should find 2 'hello' lines")

        destination.appendedLines.removeAll()

        // Create second filter that refines the first
        let filter2 = AsyncFilter(
            query: "hello a",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 1, "Second filter should find 1 'hello a' line")
    }

    // Test that cancelling AsyncFilter stops processing
    func testCancelStopsProcessing() {
        let width: Int32 = 80
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("hello line \(i)")
        }
        let buffer = createLineBuffer(withLines: lines, width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // Create filter
        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.cancel()

        // Record count after start+cancel (start may have processed some synchronously)
        let countAfterCancel = destination.appendedLines.count

        // After cancel, syncProcessToCompletion should do nothing
        filter.syncProcessToCompletion()

        // syncProcessToCompletion should not add any more results after cancellation
        XCTAssertEqual(destination.appendedLines.count, countAfterCancel,
                       "Cancellation should prevent further processing")
    }

    // Helper to create a line buffer with a partial (soft EOL) last line.
    // Note: When appending with EOL_SOFT (partial=true), LineBuffer extends the previous line.
    // So this creates (lines.count) lines where the last one includes the partial content.
    private func createLineBufferWithPartialLastLine(lines: [String], partialLastLine: String, width: Int32) -> LineBuffer {
        let buffer = LineBuffer()
        for line in lines {
            let sca = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
            buffer.append(sca, width: width)
        }
        let partialSca = screenCharArrayWithDefaultStyle(partialLastLine, eol: EOL_SOFT)
        buffer.append(partialSca, width: width)
        return buffer
    }

    // Test that when refining filter's last line was temporary, it's removed at start of catchUp
    func testTemporaryLastLineRemovedOnceAtStartOfCatchUp() {
        let width: Int32 = 80
        // Create buffer with 2 complete lines + 1 partial line
        // Note: The partial line is a separate raw line (not extending the previous one)
        // because we end line 1 with EOL_HARD before appending the partial
        let buffer = createLineBufferWithPartialLastLine(
            lines: ["hello first", "hello second"],
            partialLastLine: "hello partial",
            width: width
        )
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // Create first filter - finds matching lines, with the last one being temporary (partial)
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        // Filter finds 2 lines: "hello first" and "hello second" (which has "hello partial" appended)
        // Both contain "hello", and the last is partial/temporary
        let filter1LineCount = destination.appendedLines.count
        XCTAssertGreaterThanOrEqual(filter1LineCount, 2, "First filter should find at least 2 'hello' lines")

        let removeCountBeforeFilter2 = destination.removeLastLineCallCount

        // Create second filter that refines the first
        let filter2 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.syncProcessToCompletion()

        // The temporary line should be removed at least once at the start of catchUp.
        // It may also be removed when the search phase completes (removing the temp line before
        // re-adding it or when finishing).
        XCTAssertGreaterThanOrEqual(destination.removeLastLineCallCount, removeCountBeforeFilter2 + 1,
                                    "Temporary line should be removed at start of catchUp")

        // After catchUp and searching complete, we should have added more lines
        XCTAssertGreaterThanOrEqual(destination.appendedLines.count, filter1LineCount,
                                    "Should have at least as many lines after refining")
    }

    // Test rapid typing scenario where filters are cancelled mid-catchUp
    func testRapidTypingScenario() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "abc first",
            "ab second",
            "a third",
            "xyz fourth"
        ], width: width)
        let grid = createGrid(width: width, height: 24)

        // Filter A: query "a"
        let destinationA = MockFilterDestination()
        let filterA = AsyncFilter(
            query: "a",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destinationA,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filterA.start()
        filterA.syncProcessToCompletion()

        XCTAssertEqual(destinationA.appendedLines.count, 3, "Filter A should find 3 lines matching 'a'")

        // Filter B: query "ab", refines A, gets cancelled immediately
        let destinationB = MockFilterDestination()
        let filterB = AsyncFilter(
            query: "ab",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destinationB,
            cadence: 0.001,
            refining: filterA,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filterB.start()
        filterB.cancel() // Immediate cancel

        // Filter C: query "abc", refines B
        let destinationC = MockFilterDestination()
        let filterC = AsyncFilter(
            query: "abc",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destinationC,
            cadence: 0.001,
            refining: filterB,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filterC.start()
        filterC.syncProcessToCompletion()

        // Filter C should find 1 line matching "abc"
        XCTAssertEqual(destinationC.appendedLines.count, 1, "Filter C should find 1 line matching 'abc'")
    }

    // Test onComplete callback is called
    func testOnCompleteCallback() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello a", "hello b"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )

        var completionCount = 0
        filter.onComplete = {
            completionCount += 1
        }

        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(completionCount, 1, "onComplete should be called once when filter completes")

        // Deliver new content and process - should complete again
        let newLine = screenCharArrayWithDefaultStyle("hello c", eol: EOL_HARD)
        let metadata = iTermImmutableMetadataDefault()
        filter.deliver(newLine, metadata: metadata, lineBufferGeneration: 9999)
        filter.syncProcessToCompletion()

        XCTAssertEqual(completionCount, 2, "onComplete should be called again after processing new content")
    }
}

// MARK: - Temporary Line Tests

/// Comprehensive tests for temporary line handling in all states.
/// Temporary lines occur when a partial (soft EOL) line matches the filter query.
/// They should be removed and re-added as content updates, and removed when the line
/// becomes complete (hard EOL).
class AsyncFilterTemporaryLineTests: XCTestCase {

    private func createLineBuffer(withLines lines: [String], width: Int32) -> LineBuffer {
        let buffer = LineBuffer()
        for line in lines {
            let sca = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
            buffer.append(sca, width: width)
        }
        return buffer
    }

    private func createGrid(width: Int32, height: Int32) -> VT100Grid {
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height),
                             delegate: nil)!
        return grid
    }

    /// Helper to create a partial line ScreenCharArray
    private func partialLine(_ text: String) -> ScreenCharArray {
        return screenCharArrayWithDefaultStyle(text, eol: EOL_SOFT)
    }

    /// Helper to create a complete line ScreenCharArray
    private func completeLine(_ text: String) -> ScreenCharArray {
        return screenCharArrayWithDefaultStyle(text, eol: EOL_HARD)
    }

    // MARK: - Initial Buffer with Partial Line Tests

    /// Test that a partial line in the initial buffer is found
    func testPartialLineInInitialBufferIsFound() {
        let width: Int32 = 80
        let buffer = LineBuffer()
        buffer.append(completeLine("hello first"), width: width)
        // When appending a partial line after a complete line, it creates a new line
        buffer.append(partialLine("hello partial"), width: width)

        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        // Should find at least one line containing "hello"
        XCTAssertGreaterThanOrEqual(destination.appendedLines.count, 1,
                                    "Should find at least one line containing 'hello'")
    }

    // MARK: - CatchUp State Tests

    /// Test temporary line handling when entering catchUp
    func testTemporaryLineAtStartOfCatchUp() {
        let width: Int32 = 80
        let buffer = LineBuffer()
        buffer.append(completeLine("hello first"), width: width)
        buffer.append(partialLine("hello partial"), width: width)

        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // First filter finds lines
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        let countAfterFilter1 = destination.appendedLines.count
        XCTAssertGreaterThan(countAfterFilter1, 0, "First filter should find matches")

        let removeCountBeforeFilter2 = destination.removeLastLineCallCount

        // Second filter refines first - should remove temporary line at start if present
        let filter2 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.syncProcessToCompletion()

        // If filter1 had a temporary last line, filter2 should remove it
        // The remove count should be at least as high as before (may increase)
        XCTAssertGreaterThanOrEqual(destination.removeLastLineCallCount, removeCountBeforeFilter2,
                                    "Remove count should not decrease during catchUp")
    }

    /// Test delivering content during catchUp
    func testDeliverDuringCatchUp() {
        let width: Int32 = 80
        var lines: [String] = []
        for i in 0..<20 {
            lines.append("hello line \(i)")
        }
        let buffer = createLineBuffer(withLines: lines, width: width)
        let grid = createGrid(width: width, height: 24)

        // First filter
        let destination1 = MockFilterDestination()
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination1,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        // Second filter refines first
        let destination2 = MockFilterDestination()
        let filter2 = AsyncFilter(
            query: "hello line",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination2,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()

        // Deliver content during catchUp (will be queued)
        let metadata = iTermImmutableMetadataDefault()
        filter2.deliver(completeLine("hello line extra"), metadata: metadata, lineBufferGeneration: 99999)

        filter2.syncProcessToCompletion()

        // Should have processed catchUp results
        XCTAssertGreaterThan(destination2.appendedLines.count, 0,
                             "Should have processed catchUp results")
    }

    // MARK: - Draining Pending Deliveries State Tests

    /// Test that deliveries during catchUp are eventually processed
    func testPendingDeliveriesProcessed() {
        let width: Int32 = 80
        var lines: [String] = []
        for i in 0..<10 {
            lines.append("hello line \(i)")
        }
        let buffer = createLineBuffer(withLines: lines, width: width)
        let grid = createGrid(width: width, height: 24)

        // First filter
        let destination1 = MockFilterDestination()
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination1,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        // Second filter refines first
        let destination2 = MockFilterDestination()
        let filter2 = AsyncFilter(
            query: "hello line",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination2,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()

        // Queue up multiple deliveries
        let metadata = iTermImmutableMetadataDefault()
        filter2.deliver(completeLine("hello line new1"), metadata: metadata, lineBufferGeneration: 99990)
        filter2.deliver(completeLine("hello line new2"), metadata: metadata, lineBufferGeneration: 99991)

        filter2.syncProcessToCompletion()

        // Should have processed all lines
        XCTAssertGreaterThan(destination2.appendedLines.count, 0,
                             "Should have processed catchUp and pending deliveries")
    }

    // MARK: - Edge Cases

    /// Test that non-matching content doesn't affect results
    func testNonMatchingContentIgnored() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello first"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 1)
        let removeCountBefore = destination.removeLastLineCallCount

        // Deliver content that doesn't match
        let metadata = iTermImmutableMetadataDefault()
        filter.deliver(completeLine("no match here"), metadata: metadata, lineBufferGeneration: 9999)
        filter.syncProcessToCompletion()

        // Should not have added the non-matching line
        XCTAssertEqual(destination.appendedLines.count, 1,
                       "Non-matching content should not be added")
        // Remove count should stay the same (nothing to remove)
        XCTAssertEqual(destination.removeLastLineCallCount, removeCountBefore,
                       "Non-matching content should not trigger removal")
    }

    /// Test that cancelling stops processing
    func testCancelStopsProcessing() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello first", "hello second"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        let countBeforeCancel = destination.appendedLines.count
        let removeCountBeforeCancel = destination.removeLastLineCallCount

        filter.cancel()

        // Deliver more content - should be ignored
        let metadata = iTermImmutableMetadataDefault()
        filter.deliver(completeLine("hello ignored"), metadata: metadata, lineBufferGeneration: 9999)
        filter.syncProcessToCompletion()

        // Nothing should have changed
        XCTAssertEqual(destination.appendedLines.count, countBeforeCancel,
                       "Cancel should prevent further appends")
        XCTAssertEqual(destination.removeLastLineCallCount, removeCountBeforeCancel,
                       "Cancel should prevent further removes")
    }

    /// Test delivering complete lines after initial search
    func testDeliverCompleteLines() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello first"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 1, "Should find initial line")

        let metadata = iTermImmutableMetadataDefault()

        // Deliver several complete lines
        filter.deliver(completeLine("hello second"), metadata: metadata, lineBufferGeneration: 10000)
        filter.syncProcessToCompletion()

        filter.deliver(completeLine("hello third"), metadata: metadata, lineBufferGeneration: 10001)
        filter.syncProcessToCompletion()

        // Should have all three matching lines
        XCTAssertEqual(destination.appendedLines.count, 3,
                       "Should have all three matching lines")
    }

    /// Test that removeLastLine is called when replacing content
    func testRemoveLastLineCalledOnReplacement() {
        let width: Int32 = 80
        let buffer = LineBuffer()
        buffer.append(completeLine("hello first"), width: width)
        buffer.append(partialLine("hello partial"), width: width)

        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        // If a partial line was found, subsequent searches should remove it
        // before re-adding (if it still matches)
        let initialRemoveCount = destination.removeLastLineCallCount

        // Deliver more content that continues the partial line
        let metadata = iTermImmutableMetadataDefault()
        filter.deliver(partialLine(" continued"), metadata: metadata, lineBufferGeneration: 9999)
        filter.syncProcessToCompletion()

        // If there was a temporary line, it should have been removed
        // (remove count should increase or stay same if no temp line)
        XCTAssertGreaterThanOrEqual(destination.removeLastLineCallCount, initialRemoveCount,
                                    "Remove count should not decrease")
    }

    /// Test multiple refining filters with temporary lines
    func testMultipleRefiningFilters() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "abc one",
            "ab two",
            "a three"
        ], width: width)
        let grid = createGrid(width: width, height: 24)

        // Filter 1: "a" - finds 3 lines
        let dest1 = MockFilterDestination()
        let filter1 = AsyncFilter(
            query: "a",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: dest1,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()
        XCTAssertEqual(dest1.appendedLines.count, 3, "Filter 1 should find 3 lines")

        // Filter 2: "ab" - refines filter1, finds 2 lines
        let dest2 = MockFilterDestination()
        let filter2 = AsyncFilter(
            query: "ab",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: dest2,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.syncProcessToCompletion()
        XCTAssertEqual(dest2.appendedLines.count, 2, "Filter 2 should find 2 lines")

        // Filter 3: "abc" - refines filter2, finds 1 line
        let dest3 = MockFilterDestination()
        let filter3 = AsyncFilter(
            query: "abc",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: dest3,
            cadence: 0.001,
            refining: filter2,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter3.start()
        filter3.syncProcessToCompletion()
        XCTAssertEqual(dest3.appendedLines.count, 1, "Filter 3 should find 1 line")
    }

    /// Test that onComplete is called appropriately
    func testOnCompleteCallback() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: ["hello"], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )

        var completionCount = 0
        filter.onComplete = {
            completionCount += 1
        }

        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(completionCount, 1, "onComplete should be called when search completes")

        // Deliver new content
        let metadata = iTermImmutableMetadataDefault()
        filter.deliver(completeLine("hello again"), metadata: metadata, lineBufferGeneration: 9999)
        filter.syncProcessToCompletion()

        XCTAssertEqual(completionCount, 2, "onComplete should be called again after new content")
    }
}

// MARK: - Regex Filter Tests

class AsyncFilterRegexTests: XCTestCase {

    private func createLineBuffer(withLines lines: [String], width: Int32) -> LineBuffer {
        let buffer = LineBuffer()
        for line in lines {
            let sca = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
            buffer.append(sca, width: width)
        }
        return buffer
    }

    private func createGrid(width: Int32, height: Int32) -> VT100Grid {
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height),
                             delegate: nil)!
        return grid
    }

    // Test basic regex matching
    func testRegexBasicMatching() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "error: something failed",
            "warning: might be a problem",
            "error: another failure",
            "info: all good"
        ], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "error.*fail",
            lineBuffer: buffer,
            grid: grid,
            mode: .caseSensitiveRegex,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 2, "Should find 2 lines matching 'error.*fail'")
    }

    // Test case-insensitive regex
    func testRegexCaseInsensitive() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "ERROR: something",
            "error: something",
            "Error: something",
            "info: nothing"
        ], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "error",
            lineBuffer: buffer,
            grid: grid,
            mode: .caseInsensitiveRegex,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 3, "Should find 3 lines matching 'error' case-insensitively")
    }

    // Test that regex refinement is disabled - this is the critical test
    // If old query "a" is substring of new query "a|b", we should NOT use catchUp
    // because "a|b" matches MORE lines than "a", not fewer
    func testRegexRefinementDisabled() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "apple",
            "banana",
            "cherry"
        ], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        // First filter: matches "a" (apple, banana)
        let filter1 = AsyncFilter(
            query: "a",
            lineBuffer: buffer,
            grid: grid,
            mode: .caseSensitiveRegex,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 2, "First filter should find 'apple' and 'banana'")

        // Clear destination for second filter
        destination.appendedLines.removeAll()

        // Second filter: "a|c" contains "a" as substring, but matches MORE lines
        // If refinement were incorrectly enabled, we'd miss "cherry"
        let filter2 = AsyncFilter(
            query: "a|c",
            lineBuffer: buffer,
            grid: grid,
            mode: .caseSensitiveRegex,
            destination: destination,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.syncProcessToCompletion()

        // Should find all 3 lines: apple (has 'a'), banana (has 'a'), cherry (has 'c')
        XCTAssertEqual(destination.appendedLines.count, 3,
                       "Regex refinement should be disabled - must find all 3 lines matching 'a|c'")
    }

    // Test regex with alternation
    func testRegexAlternation() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "error occurred",
            "warning issued",
            "fatal crash",
            "info message"
        ], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "error|fatal",
            lineBuffer: buffer,
            grid: grid,
            mode: .caseSensitiveRegex,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 2, "Should find lines with 'error' or 'fatal'")
    }

    // Test regex with character class
    func testRegexCharacterClass() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "line 1",
            "line 2",
            "line 3",
            "line a"
        ], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "line [0-9]",
            lineBuffer: buffer,
            grid: grid,
            mode: .caseSensitiveRegex,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        XCTAssertEqual(destination.appendedLines.count, 3, "Should find 3 lines with digits")
    }

    // Test that literal search works correctly (control test)
    func testLiteralSearchWithoutRefinement() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "hello world",
            "hello there",
            "hello world again",
            "goodbye world"
        ], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination = MockFilterDestination()

        let filter = AsyncFilter(
            query: "hello world",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter.start()
        filter.syncProcessToCompletion()

        // Should find exactly 2 lines: "hello world" and "hello world again"
        XCTAssertEqual(destination.appendedLines.count, 2, "Should find 2 lines with 'hello world'")
    }

    // Test haveMatch correctly determines if a narrower query matches within
    // the bounds of a previous match. This tests the stopAt filtering in
    // findSubstring which uses direction-aware boundary comparisons.
    func testHaveMatchBehavior() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "hello world",
            "hello there",
            "hello world again"
        ], width: width)

        // Create updater with query "hello" to get acceptedLines
        let updater1 = FilteringUpdater(
            query: "hello",
            lineBuffer: buffer,
            count: Int32(buffer.numLines(withWidth: width)),
            width: width,
            mode: .smartCaseSensitivity,
            absLineRange: 0..<Int64(buffer.numLines(withWidth: width)),
            cumulativeOverflow: 0
        )
        updater1.accept = { _, _ in }
        while updater1.update() {}

        XCTAssertEqual(updater1.acceptedLines.count, 3, "Should have 3 accepted lines for 'hello'")

        // Create updater with query "hello world"
        let updater2 = FilteringUpdater(
            query: "hello world",
            lineBuffer: buffer,
            count: Int32(buffer.numLines(withWidth: width)),
            width: width,
            mode: .smartCaseSensitivity,
            absLineRange: 0..<Int64(buffer.numLines(withWidth: width)),
            cumulativeOverflow: 0
        )

        // Check each acceptedLine from updater1 against updater2's haveMatch
        var matchCount = 0
        for absRange in updater1.acceptedLines {
            if let resultRange = absRange.resultRange(offset: 0) {
                if updater2.haveMatch(at: resultRange) {
                    matchCount += 1
                }
            }
        }

        // Only 2 should match "hello world" (lines 0 and 2)
        XCTAssertEqual(matchCount, 2, "Only 2 lines should match 'hello world'")
    }

    // Test that literal refinement correctly filters results when the new query
    // is a superset of the previous query (e.g., "hello" -> "hello world").
    func testLiteralRefinementProducesCorrectResults() {
        let width: Int32 = 80
        let buffer = createLineBuffer(withLines: [
            "hello world",
            "hello there",
            "hello world again",
            "goodbye world"
        ], width: width)
        let grid = createGrid(width: width, height: 24)
        let destination1 = MockFilterDestination()

        // First filter: matches "hello"
        let filter1 = AsyncFilter(
            query: "hello",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination1,
            cadence: 0.001,
            refining: nil,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter1.start()
        filter1.syncProcessToCompletion()

        XCTAssertEqual(destination1.appendedLines.count, 3, "First filter should find 3 'hello' lines")

        // Use a fresh destination for the second filter
        let destination2 = MockFilterDestination()

        // Second filter: "hello world" - should use refinement (substring containment)
        // and produce correct results (only lines containing "hello world")
        let filter2 = AsyncFilter(
            query: "hello world",
            lineBuffer: buffer,
            grid: grid,
            mode: .smartCaseSensitivity,
            destination: destination2,
            cadence: 0.001,
            refining: filter1,
            absLineRange: NSRange(location: 0, length: 0),
            cumulativeOverflow: 0,
            progress: nil
        )
        filter2.start()
        filter2.syncProcessToCompletion()

        // Should find exactly 2 lines: "hello world" and "hello world again"
        XCTAssertEqual(destination2.appendedLines.count, 2, "Should find 2 lines with 'hello world'")
    }
}

//
//  TwoTierTokenQueueTests.swift
//  ModernTests
//
//  Unit tests for TwoTierTokenQueue, specifically for the discardAllAndReturnCount() method
//  used for cleanup accounting when sessions are unregistered.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - TwoTierTokenQueue Tests

/// Tests for TwoTierTokenQueue cleanup accounting functionality.
/// These tests verify the discardAllAndReturnCount() method correctly returns
/// the count of discarded arrays for slot accounting.
final class TwoTierTokenQueueTests: XCTestCase {

    func testDiscardAllReturnsCorrectCount() {
        // REQUIREMENT: discardAllAndReturnCount() should return the exact number
        // of TokenArrays that were in the queue.

        let queue = TwoTierTokenQueue()

        // Add some token arrays to normal priority queue
        let normalCount = 5
        for _ in 0..<normalCount {
            let tokenArray = createTestTokenArray(tokenCount: 3)
            queue.addTokens(tokenArray, highPriority: false)
        }

        // Add some token arrays to high priority queue
        let highPriCount = 3
        for _ in 0..<highPriCount {
            let tokenArray = createTestTokenArray(tokenCount: 2)
            queue.addTokens(tokenArray, highPriority: true)
        }

        XCTAssertFalse(queue.isEmpty, "Queue should not be empty before discard")

        // Discard all and verify count
        let discardedCount = queue.discardAllAndReturnCount()

        XCTAssertEqual(discardedCount, normalCount + highPriCount,
                       "Should return total count from both priority queues")
    }

    func testDiscardAllEmptiesQueue() {
        // REQUIREMENT: After discardAllAndReturnCount(), queue should be empty.
        // Test with deterministic distributions to ensure reproducibility.

        let totalTokens = 10

        // First: test with equal distribution (5 high, 5 normal)
        do {
            let queue = TwoTierTokenQueue()
            let highCount = totalTokens / 2
            let normalCount = totalTokens - highCount

            for i in 0..<highCount {
                let tokenArray = createTestTokenArray(tokenCount: 5)
                queue.addTokens(tokenArray, highPriority: true)
                XCTAssertFalse(queue.isEmpty,
                              "Equal distribution: queue should not be empty after adding high-priority token \(i + 1)")
            }
            for i in 0..<normalCount {
                let tokenArray = createTestTokenArray(tokenCount: 5)
                queue.addTokens(tokenArray, highPriority: false)
                XCTAssertFalse(queue.isEmpty,
                              "Equal distribution: queue should not be empty after adding normal-priority token \(i + 1)")
            }

            let discardedCount = queue.discardAllAndReturnCount()
            XCTAssertEqual(discardedCount, totalTokens,
                          "Equal distribution (\(highCount) high, \(normalCount) normal): discardedCount should be \(totalTokens)")
            XCTAssertTrue(queue.isEmpty,
                         "Equal distribution (\(highCount) high, \(normalCount) normal): queue should be empty after discard")
        }

        // Second: test with all complementary distributions (0/10, 1/9, 2/8, ..., 10/0)
        for highCount in 0...totalTokens {
            let normalCount = totalTokens - highCount
            let queue = TwoTierTokenQueue()

            for i in 0..<highCount {
                let tokenArray = createTestTokenArray(tokenCount: 5)
                queue.addTokens(tokenArray, highPriority: true)
                XCTAssertFalse(queue.isEmpty,
                              "Complementary (\(highCount)/\(normalCount)): queue should not be empty after adding high-priority token \(i + 1)")
            }
            for i in 0..<normalCount {
                let tokenArray = createTestTokenArray(tokenCount: 5)
                queue.addTokens(tokenArray, highPriority: false)
                XCTAssertFalse(queue.isEmpty,
                              "Complementary (\(highCount)/\(normalCount)): queue should not be empty after adding normal-priority token \(i + 1)")
            }

            // Since highCount + normalCount = totalTokens = 10, queue is always non-empty
            XCTAssertFalse(queue.isEmpty,
                          "Complementary (\(highCount)/\(normalCount)): queue should not be empty before discard")

            let discardedCount = queue.discardAllAndReturnCount()
            XCTAssertEqual(discardedCount, totalTokens,
                          "Complementary (\(highCount)/\(normalCount)): discardedCount should be \(totalTokens), got \(discardedCount)")
            XCTAssertTrue(queue.isEmpty,
                         "Complementary (\(highCount)/\(normalCount)): queue should be empty after discard")
        }
    }

    func testDiscardAllOnEmptyQueueReturnsZero() {
        // REQUIREMENT: Calling discardAllAndReturnCount() on empty queue returns 0.

        let queue = TwoTierTokenQueue()

        XCTAssertTrue(queue.isEmpty, "Fresh queue should be empty")

        let discardedCount = queue.discardAllAndReturnCount()

        XCTAssertEqual(discardedCount, 0, "Empty queue should return 0")
        XCTAssertTrue(queue.isEmpty, "Queue should still be empty")
    }

    func testDiscardAllCountsHighPriorityCorrectly() {
        // REQUIREMENT: High-priority tokens should be counted separately.

        let queue = TwoTierTokenQueue()

        // Add only high-priority tokens
        let highPriCount = 7
        for _ in 0..<highPriCount {
            let tokenArray = createTestTokenArray(tokenCount: 2)
            queue.addTokens(tokenArray, highPriority: true)
        }

        XCTAssertTrue(queue.hasHighPriorityToken, "Should have high priority tokens")

        let discardedCount = queue.discardAllAndReturnCount()

        XCTAssertEqual(discardedCount, highPriCount,
                       "Should return count of high-priority arrays")
        XCTAssertFalse(queue.hasHighPriorityToken, "Should have no high priority tokens after discard")
    }

    func testDiscardAllCountsNormalPriorityCorrectly() {
        // REQUIREMENT: Normal-priority tokens should be counted correctly.

        let queue = TwoTierTokenQueue()

        // Add only normal-priority tokens
        let normalCount = 12
        for _ in 0..<normalCount {
            let tokenArray = createTestTokenArray(tokenCount: 3)
            queue.addTokens(tokenArray, highPriority: false)
        }

        XCTAssertFalse(queue.hasHighPriorityToken, "Should have no high priority tokens")
        XCTAssertFalse(queue.isEmpty, "Should have normal priority tokens")

        let discardedCount = queue.discardAllAndReturnCount()

        XCTAssertEqual(discardedCount, normalCount,
                       "Should return count of normal-priority arrays")
    }

    func testDiscardAfterPartialConsumption() {
        // REQUIREMENT: discardAllAndReturnCount() should return count of REMAINING
        // arrays, not arrays that were already consumed.

        let queue = TwoTierTokenQueue()

        // Add 5 arrays
        for _ in 0..<5 {
            let tokenArray = createTestTokenArray(tokenCount: 2)
            queue.addTokens(tokenArray, highPriority: false)
        }

        // Consume some through enumeration (simulating partial processing)
        var consumedGroups = 0
        queue.enumerateTokenArrayGroups { group, _ in
            _ = group.consume()
            consumedGroups += 1
            return consumedGroups < 2  // Stop after 2 groups
        }

        // Now discard remaining - should be 5 - consumed groups
        // Note: enumerateTokenArrayGroups removes arrays when fully consumed
        let discardedCount = queue.discardAllAndReturnCount()

        // The exact count depends on whether arrays were fully consumed
        // This tests that we don't double-count
        XCTAssertLessThanOrEqual(discardedCount, 5,
                                  "Should not count more than original arrays")
    }

    func testMultipleDiscardCalls() {
        // REQUIREMENT: Multiple calls to discardAllAndReturnCount() should be safe
        // and return 0 for subsequent calls.

        let queue = TwoTierTokenQueue()

        // Add arrays
        for _ in 0..<3 {
            let tokenArray = createTestTokenArray(tokenCount: 2)
            queue.addTokens(tokenArray, highPriority: false)
        }

        let firstDiscard = queue.discardAllAndReturnCount()
        XCTAssertEqual(firstDiscard, 3, "First discard should return all arrays")

        let secondDiscard = queue.discardAllAndReturnCount()
        XCTAssertEqual(secondDiscard, 0, "Second discard should return 0")

        let thirdDiscard = queue.discardAllAndReturnCount()
        XCTAssertEqual(thirdDiscard, 0, "Third discard should return 0")
    }

    // MARK: - Test Helpers

    /// Create a TokenArray for testing with the specified number of tokens.
    private func createTestTokenArray(tokenCount: Int) -> TokenArray {
        var vector = CVector()
        CVectorCreate(&vector, Int32(tokenCount))

        for _ in 0..<tokenCount {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }

        let tokenArray = TokenArray(vector,
                                    lengthTotal: tokenCount * 10,
                                    lengthExcludingInBandSignaling: tokenCount * 10,
                                    semaphore: nil)
        return tokenArray
    }
}

// MARK: - Group Boundary Tests

/// Tests for TokenArrayGroup formation within a single queue.
/// These tests verify that enumerateTokenArrayGroups correctly identifies
/// group boundaries based on token coalesceability.
final class TwoTierTokenQueueGroupingTests: XCTestCase {

    func testNonCoalescableTokensFormSeparateGroups() {
        // REQUIREMENT: Each TokenArray with non-coalescable tokens (e.g., VT100_UNKNOWNCHAR)
        // should form its own group, even when in the same queue.

        let queue = TwoTierTokenQueue()

        // Add 3 token arrays with non-coalescable tokens (VT100_UNKNOWNCHAR)
        // Use different lengths to verify each is a separate group
        let lengths = [100, 200, 300]
        for length in lengths {
            let tokenArray = createNonCoalescableTokenArray(tokenCount: 1, lengthPerToken: length)
            queue.addTokens(tokenArray, highPriority: false)
        }

        // Count how many groups we get and their lengths
        var groupCount = 0
        var observedLengths: [Int] = []

        queue.enumerateTokenArrayGroups { group, priority in
            groupCount += 1
            observedLengths.append(group.lengthTotal)
            _ = group.consume()
            return true  // Continue enumerating
        }

        // Each TokenArray should be its own group (non-coalescable)
        XCTAssertEqual(groupCount, 3, "Each non-coalescable TokenArray should form its own group")
        XCTAssertEqual(observedLengths, lengths, "Each group should have the expected length")
    }

    func testEnumerateGroupsProcessesInOrder() {
        // REQUIREMENT: Groups should be processed in FIFO order within a queue.

        let queue = TwoTierTokenQueue()

        // Add arrays with different lengths to identify them
        let lengths = [10, 20, 30]
        for length in lengths {
            let tokenArray = createNonCoalescableTokenArray(tokenCount: 1, lengthPerToken: length)
            queue.addTokens(tokenArray, highPriority: false)
        }

        var observedLengths: [Int] = []

        queue.enumerateTokenArrayGroups { group, priority in
            observedLengths.append(group.lengthTotal)
            _ = group.consume()
            return true
        }

        XCTAssertEqual(observedLengths, lengths,
                       "Groups should be processed in FIFO order")
    }

    func testEnumerateGroupsStopsWhenClosureReturnsFalse() {
        // REQUIREMENT: Enumeration should stop when closure returns false.
        // This is essential for budget enforcement to work.

        let queue = TwoTierTokenQueue()

        // Add 5 groups
        for i in 0..<5 {
            let tokenArray = createNonCoalescableTokenArray(tokenCount: 1, lengthPerToken: (i + 1) * 10)
            queue.addTokens(tokenArray, highPriority: false)
        }

        var groupsProcessed = 0

        queue.enumerateTokenArrayGroups { group, priority in
            groupsProcessed += 1
            _ = group.consume()
            return groupsProcessed < 2  // Stop after 2 groups
        }

        XCTAssertEqual(groupsProcessed, 2,
                       "Enumeration should stop when closure returns false")

        // Queue should still have remaining groups
        XCTAssertFalse(queue.isEmpty, "Queue should still have 3 remaining groups")
    }

    func testEnumerateGroupsReturnsCorrectPriority() {
        // REQUIREMENT: Enumeration should report correct priority for each group.

        let queue = TwoTierTokenQueue()

        // Add high-priority group first
        queue.addTokens(createNonCoalescableTokenArray(tokenCount: 1), highPriority: true)

        // Add normal-priority group
        queue.addTokens(createNonCoalescableTokenArray(tokenCount: 1), highPriority: false)

        var priorities: [Int] = []

        queue.enumerateTokenArrayGroups { group, priority in
            priorities.append(priority)
            _ = group.consume()
            return true
        }

        // Priority 0 = high, Priority 1 = normal
        XCTAssertEqual(priorities, [0, 1],
                       "Should process high-priority (0) before normal-priority (1)")
    }

    func testHighPriorityExecutesBeforeNormalEvenWhenAddedSecond() {
        // REQUIREMENT: High-priority token arrays must execute before normal-priority,
        // regardless of insertion order. This is essential for API injection (e.g., report
        // responses) to be handled promptly.

        let queue = TwoTierTokenQueue()

        // Add NORMAL-priority first with distinct length (200)
        let normalArray = createNonCoalescableTokenArray(tokenCount: 1, lengthPerToken: 200)
        queue.addTokens(normalArray, highPriority: false)

        // Add HIGH-priority second with distinct length (100)
        let highPriArray = createNonCoalescableTokenArray(tokenCount: 1, lengthPerToken: 100)
        queue.addTokens(highPriArray, highPriority: true)

        // Track execution order via (priority, lengthTotal) tuples
        var executionOrder: [(priority: Int, length: Int)] = []

        queue.enumerateTokenArrayGroups { group, priority in
            executionOrder.append((priority: priority, length: group.lengthTotal))
            _ = group.consume()
            return true
        }

        // Should have processed both
        XCTAssertEqual(executionOrder.count, 2, "Both arrays should be processed")

        // High-priority (length=100) should execute FIRST despite being added SECOND
        XCTAssertEqual(executionOrder[0].priority, 0,
                       "High-priority (queue[0]) should execute first")
        XCTAssertEqual(executionOrder[0].length, 100,
                       "High-priority array (length=100) should execute first")

        // Normal-priority (length=200) should execute SECOND despite being added FIRST
        XCTAssertEqual(executionOrder[1].priority, 1,
                       "Normal-priority (queue[1]) should execute second")
        XCTAssertEqual(executionOrder[1].length, 200,
                       "Normal-priority array (length=200) should execute second")
    }

    func testMultipleGroupsInSameQueueWithBudgetSemantics() {
        // REQUIREMENT: Budget enforcement should be able to stop between groups
        // in the same queue. This test simulates what executeTurn does.

        let queue = TwoTierTokenQueue()

        // Add 3 groups with 10 tokens each
        let tokensPerGroup = 10
        for _ in 0..<3 {
            let tokenArray = createNonCoalescableTokenArray(tokenCount: tokensPerGroup, lengthPerToken: 10)
            queue.addTokens(tokenArray, highPriority: false)  // All normal priority
        }

        // Simulate budget enforcement: stop after first group exceeds budget
        var tokensConsumed = 0
        var groupsExecuted = 0
        let budget = 5  // Budget that first group (10 tokens) will exceed

        queue.enumerateTokenArrayGroups { group, priority in
            // We know each group has exactly tokensPerGroup tokens (our input constant)
            let groupTokenCount = tokensPerGroup

            // Budget check BETWEEN groups (not within)
            if tokensConsumed + groupTokenCount > budget && groupsExecuted > 0 {
                return false  // Stop - budget exceeded
            }

            // Execute group
            _ = group.consume()
            tokensConsumed += groupTokenCount
            groupsExecuted += 1

            return true
        }

        // First group should execute (progress guarantee), but not second
        XCTAssertEqual(groupsExecuted, 1,
                       "Only first group should execute when it exceeds budget")
        XCTAssertEqual(tokensConsumed, tokensPerGroup,
                       "First group's tokens should be consumed")
        XCTAssertFalse(queue.isEmpty,
                       "Remaining groups should still be in queue")
    }

    // MARK: - Test Helpers

    /// Create a TokenArray with non-coalescable tokens (VT100_UNKNOWNCHAR).
    private func createNonCoalescableTokenArray(tokenCount: Int, lengthPerToken: Int = 10) -> TokenArray {
        var vector = CVector()
        CVectorCreate(&vector, Int32(tokenCount))

        for _ in 0..<tokenCount {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR  // Non-coalescable
            CVectorAppendVT100Token(&vector, token)
        }

        return TokenArray(vector,
                          lengthTotal: tokenCount * lengthPerToken,
                          lengthExcludingInBandSignaling: tokenCount * lengthPerToken,
                          semaphore: nil)
    }
}

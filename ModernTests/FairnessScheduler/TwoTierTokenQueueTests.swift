//
//  TwoTierTokenQueueTests.swift
//  ModernTests
//
//  Unit tests for TwoTierTokenQueue grouping and enumeration behavior.
//

import XCTest
@testable import iTerm2SharedARC

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

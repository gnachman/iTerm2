//
//  TwoTierTokenQueueTests.swift
//  iTerm2
//
//  The reader thread adds tokens while the mutation queue checks for and
//  executes them, so the queue's first access can come from two threads at
//  once. It used to initialize its storage lazily, which is not thread safe:
//  each racing thread could build its own storage and tokens added to the
//  losing one were silently lost.
//

import XCTest
@testable import iTerm2SharedARC

final class TwoTierTokenQueueTests: XCTestCase {
    private func makeTokenArray(budget: TokenBudget? = nil) -> TokenArray {
        var vector = CVector()
        CVectorCreate(&vector, 1)
        let token = VT100Token()
        token.type = VT100CSI_SET_MODIFIERS
        CVectorAppendVT100Token(&vector, token)
        return TokenArray(vector, lengthTotal: 1, lengthExcludingInBandSignaling: 1, budget: budget)
    }

    // Restarting a session discards what the old program sent, but not injected tokens, and frees
    // the budget slots the discarded tokens held.
    func testRemovingNormalPriorityTokensKeepsHighPriorityTokens() {
        let queue = TwoTierTokenQueue()
        let budget = TokenBudget(capacity: 1)
        budget.acquire()
        queue.addTokens(makeTokenArray(budget: budget), highPriority: false)
        queue.addTokens(makeTokenArray(), highPriority: true)
        XCTAssertFalse(budget.hasCapacity)

        queue.removeAllNormalPriority()

        XCTAssertTrue(budget.hasCapacity)
        XCTAssertTrue(queue.hasHighPriorityToken)
        var priorities = [Int]()
        queue.enumerateTokenArrayGroups { group, priority in
            priorities.append(priority)
            group.arrays.forEach { $0.skipToEnd() }
            return true
        }
        XCTAssertEqual(priorities, [0])
    }

    func testTokensAddedDuringFirstAccessAreNotLost() {
        // Each iteration races the first read against the first append on a fresh
        // queue. A correct queue never loses the token, however the race goes.
        let reader = DispatchQueue(label: "TwoTierTokenQueueTests.reader")
        let adder = DispatchQueue(label: "TwoTierTokenQueueTests.adder")
        var lost = 0
        for _ in 0..<5000 {
            let queue = TwoTierTokenQueue()
            let tokenArray = makeTokenArray()
            let start = DispatchSemaphore(value: 0)
            let group = DispatchGroup()
            reader.async(group: group) {
                start.wait()
                _ = queue.isEmpty
            }
            adder.async(group: group) {
                start.wait()
                queue.addTokens(tokenArray, highPriority: false)
            }
            start.signal()
            start.signal()
            group.wait()
            if queue.isEmpty {
                lost += 1
            }
        }
        XCTAssertEqual(lost, 0, "Tokens added while the queue was first being read were lost")
    }
}

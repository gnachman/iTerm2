//
//  ChatBlobTruncationTests.swift
//  iTerm2 ModernTests
//
//  Assembly-time, whole-round truncation for blob-native replay. A blob is one
//  round, so dropping whole HEAD blobs can never orphan a tool_use/tool_result
//  pair (they always live inside a single blob). Two policies:
//
//    - anthropicHalve: prompt-cache pricing, so cut DEEP (down to 50% of the
//      context window) when we near the limit, buying a long stable-prefix runway
//      before the next cut.
//    - fitOnly: no cache pricing, so drop just enough head blobs to fit and keep
//      as much history as possible.
//
//  Either way, if dropping every blob still doesn't fit (the envelope + current
//  round alone exceed the budget), the caller falls back to in-message text
//  elision for that one request (needsElision).
//

import XCTest
@testable import iTerm2SharedARC

final class ChatBlobTruncationTests: XCTestCase {
    private typealias Policy = ChatBlobAssembler.TruncationPolicy

    private func plan(_ weights: [Int], fixedCost: Int, context: Int, reserve: Int,
                      _ policy: Policy) -> ChatBlobAssembler.TruncationPlan {
        ChatBlobAssembler.planTruncation(blobWeights: weights, fixedCost: fixedCost,
                                         contextWindow: context, outputReserve: reserve, policy: policy)
    }

    /// Under the fit budget: nothing is dropped, whatever the policy.
    func test_underBudget_noDrop() {
        for policy in [Policy.fitOnly, .anthropicHalve] {
            let p = plan([100, 100, 100], fixedCost: 200, context: 1000, reserve: 100, policy)
            XCTAssertEqual(p.dropCount, 0, "\(policy)")
            XCTAssertFalse(p.needsElision, "\(policy)")
        }
    }

    /// fitOnly drops the minimum number of head blobs to get under the fit budget
    /// (context - reserve), keeping as much history as possible.
    func test_fitOnly_dropsMinimumToFit() {
        // fit budget = 1000 - 100 = 900. total = 200 + 300*3 = 1100 > 900.
        // Dropping one 300 blob -> 800 <= 900. So drop exactly 1.
        let p = plan([300, 300, 300], fixedCost: 200, context: 1000, reserve: 100, .fitOnly)
        XCTAssertEqual(p.dropCount, 1)
        XCTAssertFalse(p.needsElision)
    }

    /// anthropicHalve cuts all the way to 50% of the context window, dropping more
    /// than fitOnly would, to earn a long caching runway.
    func test_anthropicHalve_cutsDeeperThanFit() {
        // fit budget = 900, target = 1000/2 = 500. total = 200 + 300*3 = 1100.
        // Drop 300 -> 800 (fits, but > 500). Drop 300 -> 500 (<= target). So drop 2.
        let p = plan([300, 300, 300], fixedCost: 200, context: 1000, reserve: 100, .anthropicHalve)
        XCTAssertEqual(p.dropCount, 2, "must cut to <= 50% of context, not merely to fit")
        XCTAssertFalse(p.needsElision)
    }

    /// anthropicHalve only triggers when we near the limit; a conversation already
    /// under the fit budget is left alone even though it exceeds the 50% target
    /// (otherwise we'd cut every turn and defeat the cache).
    func test_anthropicHalve_belowFit_doesNotCutToTarget() {
        // total = 100 + 200*2 = 500 <= fit budget 900. No trigger, even though it
        // is already at the 50% target boundary; do not truncate.
        let p = plan([200, 200], fixedCost: 100, context: 1000, reserve: 100, .anthropicHalve)
        XCTAssertEqual(p.dropCount, 0)
    }

    /// Dropping every blob still doesn't fit: the envelope + current round alone
    /// exceed the fit budget, so the caller must elide the tail.
    func test_allDroppedStillOverBudget_needsElision() {
        // fit budget = 900. fixedCost 950 already exceeds it.
        let p = plan([300, 300], fixedCost: 950, context: 1000, reserve: 100, .fitOnly)
        XCTAssertEqual(p.dropCount, 2, "drops all blobs trying to fit")
        XCTAssertTrue(p.needsElision, "even with no history the request doesn't fit -> elide")
    }

    /// anthropicHalve can't reach the 50% target because the envelope is itself
    /// over 50%, but the request still fits the hard budget: drop all blobs, no
    /// elision (elision is only for genuinely-doesn't-fit).
    func test_anthropicHalve_cannotReachTargetButFits_noElision() {
        // target = 500, fit budget = 900. fixedCost 700 (> target, <= fit).
        // Dropping both blobs -> 700: still > target but <= fit budget. No elision.
        let p = plan([300, 300], fixedCost: 700, context: 1000, reserve: 100, .anthropicHalve)
        XCTAssertEqual(p.dropCount, 2)
        XCTAssertFalse(p.needsElision, "700 <= fit budget 900, so it still fits")
    }

    /// No blobs at all: only the tail. If it fits, no-op; if not, elide.
    func test_noBlobs() {
        XCTAssertEqual(plan([], fixedCost: 500, context: 1000, reserve: 100, .fitOnly).dropCount, 0)
        XCTAssertFalse(plan([], fixedCost: 500, context: 1000, reserve: 100, .fitOnly).needsElision)
        XCTAssertTrue(plan([], fixedCost: 950, context: 1000, reserve: 100, .fitOnly).needsElision)
    }

    /// dropCount never exceeds the blob count.
    func test_dropCountBounded() {
        let p = plan([10, 10], fixedCost: 5000, context: 1000, reserve: 100, .anthropicHalve)
        XCTAssertEqual(p.dropCount, 2)
    }
}

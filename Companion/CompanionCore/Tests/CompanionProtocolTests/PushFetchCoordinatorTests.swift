//
//  PushFetchCoordinatorTests.swift
//  CompanionCore
//
//  The NSE decision core: fetch -> show content / fallback, and the watermark
//  contract (advance on any successful fetch, never on failure, never lowered).
//  Driven with an injected fetch closure and an in-memory watermark store.
//

import XCTest
@testable import CompanionProtocol

private final class MemoryBacking: WatermarkBacking {
    var store: [String: Int64] = [:]
    func watermarkValue(forKey key: String) -> Int64? { store[key] }
    func setWatermarkValue(_ value: Int64, forKey key: String) { store[key] = value }
    func removeWatermarks(matchingPrefix prefix: String) {
        for key in store.keys where key.hasPrefix(prefix) { store[key] = nil }
    }
}

private final class Captured {
    var sinceSeq: Int64?
    var limit: Int?
}

final class PushFetchCoordinatorTests: XCTestCase {
    private func makeStore(seed: [String: Int64] = [:]) -> WatermarkStore {
        let store = WatermarkStore(backing: MemoryBacking())
        for (token, value) in seed { store.advance(token: token, to: value) }
        return store
    }

    func testContentDecisionAndWatermarkAdvanceOnCommit() async {
        let store = makeStore()
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "Chat A", previews: [1, 2], maxSeq: 9, truncated: true, reset: false)
        }
        let outcome = await coord.run(collapseToken: "tok")
        guard case let .content(name, previews, truncated) = outcome.decision else {
            return XCTFail("expected content, got \(outcome.decision)")
        }
        XCTAssertEqual(name, "Chat A")
        XCTAssertEqual(previews, [1, 2])
        XCTAssertTrue(truncated)
        // run() must NOT mutate the watermark itself; only commit does.
        XCTAssertNil(store.watermark(forToken: "tok"), "run() must not advance the watermark")
        coord.commitWatermark(outcome)
        XCTAssertEqual(store.watermark(forToken: "tok"), 9)
    }

    func testDiscardedOutcomeNeverMovesWatermark() async {
        // The deadline-race bug: run() fetched and (previously) advanced the
        // watermark, but the caller threw the decision away and showed the
        // fallback -> that content was skipped forever. Now the advance is
        // deferred to commit, so an outcome that is NOT committed leaves the
        // watermark untouched and the next push re-fetches that content.
        let store = makeStore(seed: ["tok": 3])
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "Chat A", previews: [1, 2], maxSeq: 20, truncated: false, reset: false)
        }
        let outcome = await coord.run(collapseToken: "tok")
        guard case .content = outcome.decision else { return XCTFail("expected content") }
        // Caller discards this outcome (deadline won) and never commits it.
        XCTAssertEqual(store.watermark(forToken: "tok"), 3, "a discarded outcome must not move the watermark")
    }

    func testDeadlineOutcomeCommitsNoWatermark() {
        let store = makeStore(seed: ["tok": 3])
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "", previews: [], maxSeq: 99, truncated: false, reset: false)
        }
        let outcome = coord.deadlineOutcome(collapseToken: "tok")
        guard case .fallback = outcome.decision else { return XCTFail("expected fallback") }
        coord.commitWatermark(outcome)   // even committed, the deadline outcome carries no move
        XCTAssertEqual(store.watermark(forToken: "tok"), 3)
    }

    func testEmptyReplyIsFallbackButAdvancesOnCommit() async {
        let store = makeStore()
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "", previews: [], maxSeq: 4, truncated: false, reset: false)
        }
        let outcome = await coord.run(collapseToken: "tok")
        guard case .fallback = outcome.decision else { return XCTFail("expected fallback") }
        coord.commitWatermark(outcome)
        XCTAssertEqual(store.watermark(forToken: "tok"), 4, "nothing-new still advances to the tip")
    }

    func testFetchFailureIsFallbackAndLeavesWatermark() async {
        struct Boom: Error {}
        let store = makeStore(seed: ["tok": 7])
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in throw Boom() }
        let outcome = await coord.run(collapseToken: "tok")
        guard case .fallback = outcome.decision else { return XCTFail("expected fallback") }
        coord.commitWatermark(outcome)
        XCTAssertEqual(store.watermark(forToken: "tok"), 7, "a failed fetch must not move the watermark")
    }

    func testFirstRunFetchesOnlyNewest() async {
        let store = makeStore()
        let captured = Captured()
        let coord = PushFetchCoordinator<Int>(watermarks: store, normalLimit: 10, firstRunLimit: 1) { _, since, limit in
            captured.sinceSeq = since
            captured.limit = limit
            return .init(chatName: "A", previews: [1], maxSeq: 3, truncated: true, reset: false)
        }
        _ = await coord.run(collapseToken: "tok")
        XCTAssertEqual(captured.sinceSeq, 0)
        XCTAssertEqual(captured.limit, 1, "no watermark -> show only the newest")
    }

    func testSubsequentRunFetchesSinceWatermarkAtNormalLimit() async {
        let store = makeStore(seed: ["tok": 5])
        let captured = Captured()
        let coord = PushFetchCoordinator<Int>(watermarks: store, normalLimit: 10, firstRunLimit: 1) { _, since, limit in
            captured.sinceSeq = since
            captured.limit = limit
            return .init(chatName: "A", previews: [], maxSeq: 5, truncated: false, reset: false)
        }
        _ = await coord.run(collapseToken: "tok")
        XCTAssertEqual(captured.sinceSeq, 5)
        XCTAssertEqual(captured.limit, 10)
    }

    func testTokenMatchedNoChatDoesNotLowerWatermark() async {
        let store = makeStore(seed: ["tok": 8])
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "", previews: [], maxSeq: 0, truncated: false, reset: false)   // no chat resolved
        }
        let outcome = await coord.run(collapseToken: "tok")
        guard case .fallback = outcome.decision else { return XCTFail("expected fallback") }
        coord.commitWatermark(outcome)
        XCTAssertEqual(store.watermark(forToken: "tok"), 8, "max-merge never lowers")
    }

    func testHostResetLowersWatermarkToNewTipOnCommit() async {
        // The chat DB rewound: the host signals reset=true with a maxSeq BELOW
        // our stale-high watermark. We must LOWER the watermark to the new tip,
        // not max-merge (which would leave it stuck and never re-notify).
        let store = makeStore(seed: ["tok": 500])
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "Chat A", previews: [1], maxSeq: 5, truncated: false, reset: true)
        }
        let outcome = await coord.run(collapseToken: "tok")
        guard case .content = outcome.decision else { return XCTFail("expected content") }
        coord.commitWatermark(outcome)
        XCTAssertEqual(store.watermark(forToken: "tok"), 5, "reset lowers the watermark to the new tip")
    }
}

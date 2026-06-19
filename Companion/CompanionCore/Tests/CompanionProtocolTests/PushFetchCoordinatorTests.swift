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

    func testContentDecisionAndWatermarkAdvance() async {
        let store = makeStore()
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "Chat A", previews: [1, 2], maxSeq: 9, truncated: true)
        }
        let decision = await coord.run(collapseToken: "tok")
        guard case let .content(name, previews, truncated) = decision else {
            return XCTFail("expected content, got \(decision)")
        }
        XCTAssertEqual(name, "Chat A")
        XCTAssertEqual(previews, [1, 2])
        XCTAssertTrue(truncated)
        XCTAssertEqual(store.watermark(forToken: "tok"), 9)
    }

    func testEmptyReplyIsFallbackButStillAdvances() async {
        let store = makeStore()
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "", previews: [], maxSeq: 4, truncated: false)
        }
        let decision = await coord.run(collapseToken: "tok")
        guard case .fallback = decision else { return XCTFail("expected fallback") }
        XCTAssertEqual(store.watermark(forToken: "tok"), 4, "nothing-new still advances to the tip")
    }

    func testFetchFailureIsFallbackAndLeavesWatermark() async {
        struct Boom: Error {}
        let store = makeStore(seed: ["tok": 7])
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in throw Boom() }
        let decision = await coord.run(collapseToken: "tok")
        guard case .fallback = decision else { return XCTFail("expected fallback") }
        XCTAssertEqual(store.watermark(forToken: "tok"), 7, "a failed fetch must not move the watermark")
    }

    func testFirstRunFetchesOnlyNewest() async {
        let store = makeStore()
        let captured = Captured()
        let coord = PushFetchCoordinator<Int>(watermarks: store, normalLimit: 10, firstRunLimit: 1) { _, since, limit in
            captured.sinceSeq = since
            captured.limit = limit
            return .init(chatName: "A", previews: [1], maxSeq: 3, truncated: true)
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
            return .init(chatName: "A", previews: [], maxSeq: 5, truncated: false)
        }
        _ = await coord.run(collapseToken: "tok")
        XCTAssertEqual(captured.sinceSeq, 5)
        XCTAssertEqual(captured.limit, 10)
    }

    func testTokenMatchedNoChatDoesNotLowerWatermark() async {
        let store = makeStore(seed: ["tok": 8])
        let coord = PushFetchCoordinator<Int>(watermarks: store) { _, _, _ in
            .init(chatName: "", previews: [], maxSeq: 0, truncated: false)   // no chat resolved
        }
        let decision = await coord.run(collapseToken: "tok")
        guard case .fallback = decision else { return XCTFail("expected fallback") }
        XCTAssertEqual(store.watermark(forToken: "tok"), 8, "max-merge never lowers")
    }
}

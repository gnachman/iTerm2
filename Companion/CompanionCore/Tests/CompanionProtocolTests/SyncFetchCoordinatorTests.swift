//
//  SyncFetchCoordinatorTests.swift
//  CompanionCore
//
//  The contentless-wakeup decision core: unified fetch -> content / fallback, the
//  per-chat read-state gate, and the deferred global-floor + per-chat-watermark
//  writes. Driven with an injected fetch closure and an in-memory store.
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

final class SyncFetchCoordinatorTests: XCTestCase {
    private func store() -> WatermarkStore { WatermarkStore(backing: MemoryBacking()) }

    private func message(_ chatID: String, _ seq: Int64, body: String = "x") -> CompanionSyncItem {
        .message(CompanionSyncMessageItem(chatID: chatID, chatName: "Chat \(chatID)",
                                          uniqueID: UUID(), author: "agent", body: body, seq: seq))
    }
    private func alert(_ threadKey: String, _ seq: Int64) -> CompanionSyncItem {
        .alert(CompanionSyncAlertItem(alertID: UUID(), threadKey: threadKey,
                                      title: "T", body: "B", seq: seq))
    }
    private func reply(_ items: [CompanionSyncItem],
                       maxMessageSeq: Int64, maxAlertSeq: Int64,
                       messageReset: Bool = false, alertReset: Bool = false,
                       truncated: Bool = false) -> NSESyncSince.Reply {
        NSESyncSince.Reply(items: items, maxMessageSeq: maxMessageSeq, maxAlertSeq: maxAlertSeq,
                           messageReset: messageReset, alertReset: alertReset, truncated: truncated)
    }
    private func coordinator(_ s: WatermarkStore,
                             reply r: @escaping () -> NSESyncSince.Reply) -> SyncFetchCoordinator {
        SyncFetchCoordinator(watermarks: s, tokenForChat: { $0 }, fetch: { _, _, _ in r() })
    }

    /// The crux: reading chat A to a HIGH seq in-app (its per-chat watermark is
    /// 200) must NOT suppress an older UNREAD message in chat B (seq 100). A single
    /// global watermark would drop B; the per-chat gate keeps it.
    func testReadStateInOneChatDoesNotSuppressAnother() async {
        let s = store()
        s.advanceFloor(.message, to: 0)        // floor present -> not first-run
        s.advance(token: "A", to: 200)          // chat A read up to 200 in-app
        let coord = coordinator(s) { [self] in
            reply([message("B", 100), message("A", 150)], maxMessageSeq: 200, maxAlertSeq: 0)
        }
        let outcome = await coord.run()
        guard case let .content(items, _) = outcome.decision else {
            return XCTFail("expected content, got \(outcome.decision)")
        }
        XCTAssertTrue(alertKeys(items).isEmpty)
        XCTAssertEqual(chatIDs(items), ["B"], "A's already-read message must be suppressed; B must survive")
    }

    private func chatIDs(_ items: [SyncFetchCoordinator.RenderItem]) -> [String] {
        items.compactMap { if case let .message(chatID, _, _, _, _) = $0 { return chatID } else { return nil } }
    }
    private func alertKeys(_ items: [SyncFetchCoordinator.RenderItem]) -> [String] {
        items.compactMap { if case let .alert(_, threadKey, _, _) = $0 { return threadKey } else { return nil } }
    }
    private func tags(_ items: [SyncFetchCoordinator.RenderItem]) -> [String] {
        items.map {
            switch $0 {
            case let .message(chatID, _, _, _, _): return "msg:\(chatID)"
            case let .alert(_, threadKey, _, _): return "alert:\(threadKey)"
            case .placeholder: return "placeholder"
            }
        }
    }

    /// The coordinator must preserve reply.items order verbatim (the host emits it
    /// in global time order), interleaving messages and alerts, so the shell can
    /// anchor the oldest and sound the newest.
    func testPreservesInterleavedHostOrder() async {
        let s = store()
        s.advanceFloor(.message, to: 0)
        let coord = coordinator(s) { [self] in
            reply([alert("s1", 1), message("A", 10), alert("s2", 2), message("B", 11)],
                  maxMessageSeq: 11, maxAlertSeq: 2)
        }
        let outcome = await coord.run()
        guard case let .content(items, _) = outcome.decision else {
            return XCTFail("expected content")
        }
        XCTAssertEqual(tags(items), ["alert:s1", "msg:A", "alert:s2", "msg:B"])
    }

    func testUnsupportedItemRendersPlaceholderAndGoodItemsSurvive() async {
        // Item-level forward compatibility: an undecodable item becomes a
        // placeholder, and the good items in the same batch still render.
        let s = store()
        s.advanceFloor(.message, to: 0)
        let coord = coordinator(s) { [self] in
            reply([.unsupported, message("A", 10)], maxMessageSeq: 10, maxAlertSeq: 0)
        }
        let outcome = await coord.run()
        guard case let .content(items, _) = outcome.decision else {
            return XCTFail("expected content")
        }
        XCTAssertEqual(items.count, 2)
        guard case .placeholder = items.first else {
            return XCTFail("the unsupported item must render as a placeholder")
        }
        XCTAssertEqual(chatIDs(items), ["A"], "the decodable message must still render")
    }

    func testMultipleUnsupportedItemsCoalesceToOnePlaceholder() async {
        // A batch of only-unknown items is still content (not silent), but the
        // placeholders coalesce to ONE - they share a stable identity, so several in
        // a batch (and resends across syncs) collapse to a single standing prompt.
        let s = store()
        s.advanceFloor(.message, to: 0)
        let coord = coordinator(s) { [self] in
            reply([.unsupported, .unsupported, .unsupported], maxMessageSeq: 0, maxAlertSeq: 0)
        }
        let outcome = await coord.run()
        guard case let .content(items, _) = outcome.decision else {
            return XCTFail("expected content (a placeholder), not silent")
        }
        XCTAssertEqual(items, [.placeholder], "many unknown items -> one placeholder")
    }

    func testRunDoesNotMutateUntilCommit() async {
        let s = store()
        s.advanceFloor(.message, to: 5)
        let coord = coordinator(s) { [self] in
            reply([message("A", 9), alert("sess", 4)], maxMessageSeq: 9, maxAlertSeq: 4)
        }
        let outcome = await coord.run()
        XCTAssertEqual(s.floor(.message), 5, "run() must not move the floor")
        XCTAssertNil(s.watermark(forToken: "A"), "run() must not advance per-chat watermarks")
        coord.commit(outcome)
        XCTAssertEqual(s.floor(.message), 9)
        XCTAssertEqual(s.floor(.alert), 4)
        XCTAssertEqual(s.watermark(forToken: "A"), 9)
    }

    func testEmptyFetchedIsSilentNotFallback() async {
        // A SUCCESSFUL fetch with nothing to render is `.silent` (deliver silently),
        // distinct from `.fallback` (fetch failure). The floors still advance.
        let s = store()
        s.advanceFloor(.message, to: 1)
        let coord = coordinator(s) { [self] in reply([], maxMessageSeq: 5, maxAlertSeq: 0) }
        let outcome = await coord.run()
        XCTAssertEqual(outcome.decision, .silent)
        coord.commit(outcome)
        XCTAssertEqual(s.floor(.message), 5, "a silent (all-read) sync still advances the floor")
    }

    func testAllSuppressedIsSilent() async {
        // Items fetched but every one already-read (per-chat watermark) -> silent.
        let s = store()
        s.advanceFloor(.message, to: 0)
        s.advance(token: "A", to: 100)
        let coord = coordinator(s) { [self] in
            reply([message("A", 50), message("A", 90)], maxMessageSeq: 100, maxAlertSeq: 0)
        }
        let outcome = await coord.run()
        XCTAssertEqual(outcome.decision, .silent, "all-already-read must be silent, not a spurious fallback")
        coord.commit(outcome)
        XCTAssertEqual(s.floor(.message), 100)
    }

    func testFirstRunSendsNegativeMessageFloor() async {
        // No message floor -> first run -> send messageSeq = -1 (the host teaser
        // signal) and the firstRunLimit, not 0/normalLimit.
        let s = store()   // no floors
        var seenMessageSeq: Int64?
        var seenLimit: Int?
        let coord = SyncFetchCoordinator(watermarks: s, firstRunLimit: 1, tokenForChat: { $0 },
                                         fetch: { [self] msgSeq, _, limit in
            seenMessageSeq = msgSeq
            seenLimit = limit
            return reply([message("A", 9)], maxMessageSeq: 9, maxAlertSeq: 0)
        })
        _ = await coord.run()
        XCTAssertEqual(seenMessageSeq, -1, "first run must signal the host with a negative floor")
        XCTAssertEqual(seenLimit, 1, "first run uses firstRunLimit")
    }

    func testFailedFetchLeavesEverythingUntouched() async {
        let s = store()
        s.advanceFloor(.message, to: 7)
        s.advance(token: "A", to: 3)
        let coord = SyncFetchCoordinator(watermarks: s, tokenForChat: { $0 },
                                         fetch: { _, _, _ in throw NSError(domain: "x", code: 1) })
        let outcome = await coord.run()
        XCTAssertEqual(outcome.decision, .fallback)
        coord.commit(outcome)
        XCTAssertEqual(s.floor(.message), 7)
        XCTAssertEqual(s.watermark(forToken: "A"), 3)
    }

    func testMessageResetClearsChatWatermarksAndLowersFloor() async {
        let s = store()
        s.advanceFloor(.message, to: 1000)     // floor stuck high
        s.advance(token: "A", to: 900)          // stale-high per-chat watermark
        let coord = coordinator(s) { [self] in
            // Store rewound: seqs restart low; reset flagged.
            reply([message("A", 2)], maxMessageSeq: 2, maxAlertSeq: 0, messageReset: true)
        }
        let outcome = await coord.run()
        // The rewound message is surfaced (the stale-high gate is bypassed on reset).
        guard case let .content(items, _) = outcome.decision else {
            return XCTFail("expected content")
        }
        XCTAssertEqual(chatIDs(items), ["A"])
        coord.commit(outcome)
        XCTAssertEqual(s.floor(.message), 2, "reset must lower the floor")
        XCTAssertEqual(s.watermark(forToken: "A"), 2, "per-chat watermark restarts in the new seq space")
    }

    func testFirstRunUsesSmallLimit() async {
        let s = store()   // no message floor -> first run
        var seenLimit: Int?
        let coord = SyncFetchCoordinator(watermarks: s, firstRunLimit: 1, tokenForChat: { $0 },
                                         fetch: { [self] _, _, limit in
            seenLimit = limit
            return reply([message("A", 50)], maxMessageSeq: 50, maxAlertSeq: 0)
        })
        _ = await coord.run()
        XCTAssertEqual(seenLimit, 1, "first run (absent message floor) must use firstRunLimit")
    }
}

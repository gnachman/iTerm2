//
//  KittyDnDRemoteDragFetchTests.swift
//  iTerm2 ModernTests
//
//  Direct unit tests for KittyDnDRemoteDragFetch (the collector that assembles a
//  remote program's pushed files when the terminal drags them OUT). These drive
//  the fetch in isolation with small injected limits and a short timeout so the
//  resource caps and the drain-before-delete invariant can be exercised without
//  allocating gigabytes or waiting on the default 30 s idle timeout.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class KittyDnDRemoteDragFetchTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kittydnd-fetch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func failureCode(_ outcome: KittyDnDRemoteDragFetch.Outcome?) -> String? {
        if case .failure(let code) = outcome { return code }
        return nil
    }

    private func push(_ fetch: KittyDnDRemoteDragFetch, _ metadata: [String: String],
                      _ payload: Data = Data()) {
        fetch.receive(KittyDnDMessage(metadata: metadata, dataPayload: payload))
    }

    // Top-level fan-out breach: more entries than maxEntries is refused at start()
    // (before any t=k requests go out), synchronously.
    func testStartFanOutOverMaxEntriesIsEMFILE() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var limits = KittyDnDRemoteDragFetch.Limits()
        limits.maxEntries = 2
        var sent = 0
        var outcome: KittyDnDRemoteDragFetch.Outcome?
        let fetch = KittyDnDRemoteDragFetch(
            tempDir: dir, topLevelNames: ["a", "b", "c"], limits: limits,
            send: { _ in sent += 1 }, completion: { outcome = $0 })
        fetch.start()
        XCTAssertEqual(failureCode(outcome), "EMFILE")
        XCTAssertEqual(sent, 0, "no t=k requests should be sent past the cap")
    }

    // Directory-inflation breach: a directory listing that would push the
    // outstanding count over maxEntries is refused, synchronously (before the
    // mkdir write), so the drain-before-delete path is not involved.
    func testDirectoryInflationOverMaxEntriesIsEMFILE() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var limits = KittyDnDRemoteDragFetch.Limits()
        limits.maxEntries = 3
        var outcome: KittyDnDRemoteDragFetch.Outcome?
        let fetch = KittyDnDRemoteDragFetch(
            tempDir: dir, topLevelNames: ["dir"], limits: limits,
            send: { _ in }, completion: { outcome = $0 })
        fetch.start()  // pending == 1
        // A directory (X=7) declaring five children: 1 + 5 > 3.
        push(fetch, ["t": "k", "x": "1", "X": "7"],
             Data("a\u{0}b\u{0}c\u{0}d\u{0}e".utf8))
        XCTAssertEqual(failureCode(outcome), "EMFILE")
    }

    // Byte-budget breach: a push whose payload exceeds maxBytes is refused,
    // synchronously (before the file write).
    func testOverMaxBytesIsEMFILE() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var limits = KittyDnDRemoteDragFetch.Limits()
        limits.maxBytes = 8
        var outcome: KittyDnDRemoteDragFetch.Outcome?
        let fetch = KittyDnDRemoteDragFetch(
            tempDir: dir, topLevelNames: ["a.txt"], limits: limits,
            send: { _ in }, completion: { outcome = $0 })
        fetch.start()
        push(fetch, ["t": "k", "x": "1"], Data(count: 9))  // 9 > 8
        XCTAssertEqual(failureCode(outcome), "EMFILE")
    }

    // A per-push count over maxEntries (reached via ignored unknown-slot pushes, so
    // no write is in flight) is EMFILE.
    func testPerPushCountOverMaxEntriesIsEMFILE() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var limits = KittyDnDRemoteDragFetch.Limits()
        limits.maxEntries = 1
        var outcome: KittyDnDRemoteDragFetch.Outcome?
        let fetch = KittyDnDRemoteDragFetch(
            tempDir: dir, topLevelNames: ["a.txt"], limits: limits,
            send: { _ in }, completion: { outcome = $0 })
        fetch.start()
        push(fetch, ["t": "k", "x": "99"])  // unknown slot: counted, ignored, no write
        XCTAssertNil(outcome, "first push is within the cap")
        push(fetch, ["t": "k", "x": "98"])  // second push trips the count cap
        XCTAssertEqual(failureCode(outcome), "EMFILE")
    }

    // A genuinely stalled transfer is aborted after the idle timeout with an EIO.
    func testIdleTimeoutAbortsStalledTransfer() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let done = expectation(description: "idle abort")
        var outcome: KittyDnDRemoteDragFetch.Outcome?
        let fetch = KittyDnDRemoteDragFetch(
            tempDir: dir, topLevelNames: ["a.txt"], timeout: 0.05,
            send: { _ in }, completion: { outcome = $0; done.fulfill() })
        fetch.start()  // requests the entry, arms the idle timeout; nothing responds
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(failureCode(outcome)?.hasPrefix("EIO"), true)
    }

    // Drain-before-delete: when the fetch finishes (here via abort) while a write
    // is in flight, the outcome is not delivered until that write drains, so the
    // caller cannot remove the temp dir out from under a write that recreates it.
    func testCompletionIsDeferredUntilInFlightWriteDrains() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let done = expectation(description: "deferred completion")
        var completed = false
        let fetch = KittyDnDRemoteDragFetch(
            tempDir: dir, topLevelNames: ["a.txt"],
            send: { _ in }, completion: { _ in completed = true; done.fulfill() })
        fetch.start()
        // Push the file bytes: this increments activeWrites synchronously and
        // schedules the write, which cannot run until we await below.
        push(fetch, ["t": "k", "x": "1"], Data("hello".utf8))
        fetch.abort()  // finishes while the write is still in flight
        XCTAssertFalse(completed, "completion must be deferred until the write drains")
        await fulfillment(of: [done], timeout: 5)
        XCTAssertTrue(completed)
        // The write ran to completion before the outcome was delivered.
        let dest = dir.appendingPathComponent("1").appendingPathComponent("a.txt")
        XCTAssertEqual(try Data(contentsOf: dest), Data("hello".utf8))
    }
}

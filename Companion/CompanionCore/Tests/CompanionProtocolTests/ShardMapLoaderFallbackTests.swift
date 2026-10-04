//
//  ShardMapLoaderFallbackTests.swift
//  CompanionCore
//
//  Fallback sources for the shard map. Some networks cannot reach the primary
//  resolver (Cloudflare), so the loader also asks mirror URLs. Every source is
//  fetched at once; the primary's map is preferred if it arrives within the
//  delay, and otherwise (or once the primary fails) the first valid map from
//  any source wins. Monotonic versioning applies to the winner exactly as for
//  a single source.
//

import XCTest
import Foundation
@testable import CompanionProtocol

/// Thread-safe canned fetcher: the loader fetches sources concurrently.
private final class ConcurrentStubFetcher: ShardMapFetching, @unchecked Sendable {
    enum Response {
        case data(Data)
        case fail(Error)
        /// Never completes on its own; throws when the fetch task is cancelled.
        case hang
        /// Never completes, even when cancelled, until releaseStuckFetches().
        case ignoreCancellation
        /// Returns the data only after `url` has been requested, proving the
        /// two fetches were in flight at the same time.
        case dataAfterRequestOf(String, Data)
    }

    private let lock = UnfairLock()
    private var _responses: [String: Response] = [:]
    private var _requested: [String] = []
    private var stuck: [CheckedContinuation<Void, Never>] = []
    private var waiters: [(url: String, continuation: CheckedContinuation<Void, Never>)] = []

    var requested: [String] { lock.withLock { _requested } }

    func set(_ url: String, _ response: Response) {
        lock.withLock { _responses[url] = response }
    }

    func releaseStuckFetches() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { stuck = [] }
            return stuck
        }
        pending.forEach { $0.resume() }
    }

    func data(from url: URL) async throws -> Data {
        let (response, ready) = lock.withLock { () -> (Response?, [CheckedContinuation<Void, Never>]) in
            _requested.append(url.absoluteString)
            let ready = waiters.filter { $0.url == url.absoluteString }.map(\.continuation)
            waiters.removeAll { $0.url == url.absoluteString }
            return (_responses[url.absoluteString], ready)
        }
        ready.forEach { $0.resume() }
        switch response {
        case .data(let data):
            return data
        case .fail(let error):
            throw error
        case .hang:
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
            throw CancellationError()
        case .ignoreCancellation:
            await withCheckedContinuation { continuation in
                lock.withLock { stuck.append(continuation) }
            }
            throw URLError(.timedOut)
        case let .dataAfterRequestOf(other, data):
            await withCheckedContinuation { continuation in
                let alreadyRequested = lock.withLock { () -> Bool in
                    if _requested.contains(other) {
                        return true
                    }
                    waiters.append((other, continuation))
                    return false
                }
                if alreadyRequested {
                    continuation.resume()
                }
            }
            return data
        case nil:
            throw ShardMapLoaderError.httpStatus(404)
        }
    }
}

private struct DeadlineExceeded: Error {}

private final class ResultBox<T>: @unchecked Sendable {
    private let lock = UnfairLock()
    private var _result: Result<T, Error>?
    var result: Result<T, Error>? {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}

final class ShardMapLoaderFallbackTests: XCTestCase {
    private let primary = "https://resolver.example.com/shardmap.json"
    private let mirror1 = "https://mirror1.example.com/shardmap.json"
    private let mirror2 = "https://mirror2.example.com/shardmap.json"
    private let mirror3 = "https://mirror3.example.com/shardmap.json"

    /// A valid map whose every bucket goes to `host`, so the winner is visible.
    private func mapJSON(_ version: Int, host: String) -> Data {
        Data("""
        { "version": \(version),
          "ranges": [ { "low": 0, "high": 65535, "host": "\(host)" } ] }
        """.utf8)
    }

    /// Fails a hung test instead of blocking the suite forever. Generous, so it
    /// never fires on a slow machine; it only bounds a real deadlock.
    /// Uses an expectation rather than a task group, because a task group
    /// cannot return until every child finishes, which is the very hang this
    /// guards against.
    private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let finished = expectation(description: "refresh finished")
        let box = ResultBox<T>()
        Task {
            box.result = await Result { try await operation() }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 60)
        guard let result = box.result else {
            XCTFail("refresh did not finish; it waited on a source it should not have")
            throw DeadlineExceeded()
        }
        return try result.get()
    }

    // MARK: Racing

    func testMirrorWinsWhenPrimaryHangs() async throws {
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .hang)
        stub.set(mirror1, .data(mapJSON(3, host: "mirror-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1],
                                    fallbackDelay: 0, fetcher: stub)

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 3)
        let host = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(host, "mirror-host.iterm2.com")
    }

    func testMirrorWinsWhenPrimaryIgnoresCancellation() async throws {
        // The Mac's plugin-backed fetcher does not observe task cancellation, so
        // a stuck primary must not hold the race open after a mirror has won.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .ignoreCancellation)
        stub.set(mirror1, .data(mapJSON(3, host: "mirror-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1],
                                    fallbackDelay: 0, fetcher: stub)

        let map = try await bounded { try await loader.refresh() }
        stub.releaseStuckFetches()

        XCTAssertEqual(map?.version, 3)
    }

    func testPrimaryFailureUsesMirrorWithoutWaitingForDelay() async throws {
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .fail(URLError(.timedOut)))
        stub.set(mirror1, .data(mapJSON(3, host: "mirror-host.iterm2.com")))
        // An hour-long delay: only the primary's failure can release the mirror.
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1],
                                    fallbackDelay: 3600, fetcher: stub)

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 3)
    }

    // MARK: Mirror timing

    func testAfterDelayDoesNotFetchTheMirrorWhenThePrimaryAnswersInTime() async throws {
        // The Mac refreshes often; a healthy primary must not touch the mirror.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .data(mapJSON(3, host: "primary-host.iterm2.com")))
        stub.set(mirror1, .data(mapJSON(3, host: "mirror-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 3600,
                                    mirrorTiming: .afterDelay, fetcher: stub)

        _ = try await bounded { try await loader.refresh() }

        XCTAssertEqual(stub.requested, [primary])
    }

    func testAfterDelayStartsTheMirrorWhenThePrimaryFails() async throws {
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .fail(URLError(.timedOut)))
        stub.set(mirror1, .data(mapJSON(3, host: "mirror-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 3600,
                                    mirrorTiming: .afterDelay, fetcher: stub)

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 3)
        XCTAssertEqual(stub.requested, [primary, mirror1])
    }

    func testAfterDelayStartsTheMirrorWhenThePrimaryIsSlow() async throws {
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .hang)
        stub.set(mirror1, .data(mapJSON(3, host: "mirror-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 0,
                                    mirrorTiming: .afterDelay, fetcher: stub)

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 3)
    }

    func testAfterDelayStartsTheMirrorWhenThePrimaryIsStaleOnColdStart() async throws {
        // Floor v12, nothing loaded, and the primary serves a stale v11. The Mac
        // must ask the mirror right away rather than wait out the delay.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .data(mapJSON(11, host: "stale-host.iterm2.com")))
        stub.set(mirror1, .data(mapJSON(12, host: "mirror-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 3600,
                                    mirrorTiming: .afterDelay, fetcher: stub, initialHighestVersion: 12)

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 12)
        let host = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(host, "mirror-host.iterm2.com")
    }

    func testMirrorTimingDefaultsToAfterDelay() async throws {
        // Callers that don't choose (unpair, the notification extension) must not
        // add mirror traffic.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .data(mapJSON(3, host: "primary-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 3600,
                                    fetcher: stub)

        _ = try await bounded { try await loader.refresh() }

        XCTAssertEqual(stub.requested, [primary])
    }

    func testMirrorIsFetchedAlongsideThePrimary() async throws {
        // The primary cannot answer until the mirror has been requested, so this
        // only finishes if both are in flight before the (hour-long) delay.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .dataAfterRequestOf(mirror1, mapJSON(3, host: "primary-host.iterm2.com")))
        stub.set(mirror1, .hang)
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1],
                                    fallbackDelay: 3600, mirrorTiming: .withPrimary, fetcher: stub)

        _ = try await bounded { try await loader.refresh() }

        XCTAssertEqual(Set(stub.requested), [primary, mirror1])
    }

    func testPrimaryWithinDelayBeatsFasterMirror() async throws {
        // The mirror answers first, but the primary answers within the delay and
        // is preferred: the mirror can be up to ten minutes stale.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .dataAfterRequestOf(mirror1, mapJSON(3, host: "primary-host.iterm2.com")))
        stub.set(mirror1, .data(mapJSON(3, host: "mirror-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1],
                                    fallbackDelay: 3600, mirrorTiming: .withPrimary, fetcher: stub)

        _ = try await bounded { try await loader.refresh() }

        let host = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(host, "primary-host.iterm2.com")
    }

    func testUnusableMirrorsAreSkippedUntilOneServesAValidMap() async throws {
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .fail(URLError(.timedOut)))
        stub.set(mirror1, .data(Data("<html>not json</html>".utf8)))
        // Decodes but fails validation (does not cover the bucket space).
        stub.set(mirror2, .data(Data("""
        { "version": 9, "ranges": [ { "low": 0, "high": 100, "host": "bad.iterm2.com" } ] }
        """.utf8)))
        stub.set(mirror3, .data(mapJSON(3, host: "mirror3-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1, mirror2, mirror3],
                                    fallbackDelay: 3600, fetcher: stub)

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 3)
        let host = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(host, "mirror3-host.iterm2.com")
    }

    func testAllSourcesFailingReportsEveryAttempt() async throws {
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .fail(ShardMapLoaderError.httpStatus(503)))
        stub.set(mirror1, .fail(URLError(.timedOut)))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1],
                                    fallbackDelay: 3600, fetcher: stub)

        do {
            _ = try await bounded { try await loader.refresh() }
            XCTFail("expected a throw")
        } catch let error as ShardMapFetchError {
            XCTAssertEqual(error.attempts.map(\.url), [primary, mirror1])
            XCTAssertTrue(error.attempts.allSatisfy { $0.duration != nil })
            XCTAssertEqual(error.attempts.first?.error as? ShardMapLoaderError, .httpStatus(503))
            XCTAssertEqual((error.attempts.last?.error as? URLError)?.code, .timedOut)
        }
        let current = await loader.current
        XCTAssertNil(current)
    }

    func testOlderMapFromMirrorIsNotAdopted() async throws {
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .data(mapJSON(5, host: "current-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1],
                                    fallbackDelay: 0, fetcher: stub)
        _ = try await bounded { try await loader.refresh() }

        // The primary becomes unreachable (its fetch times out) and the mirror
        // lags a version behind: there is no up-to-date map to be had.
        stub.set(primary, .fail(URLError(.timedOut)))
        stub.set(mirror1, .data(mapJSON(4, host: "stale-host.iterm2.com")))
        do {
            _ = try await bounded { try await loader.refresh() }
            XCTFail("expected a throw")
        } catch let error as ShardMapFetchError {
            XCTAssertEqual(error.attempts.last?.error as? ShardMapLoaderError,
                           .outdatedMap(served: 4, latestSeen: 5))
        }

        let host = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(host, "current-host.iterm2.com")
    }

    func testUnreachablePrimaryAndStaleMirrorOnColdStartReportsAFetchFailure() async throws {
        // Persisted floor v10 and no map loaded. Previously the stale mirror map
        // was handed to refresh(), which ignored it, and the caller reported "no
        // host assigned" instead of the real problem.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .fail(URLError(.timedOut)))
        stub.set(mirror1, .data(mapJSON(9, host: "stale-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 0,
                                    fetcher: stub, initialHighestVersion: 10)

        do {
            _ = try await bounded { try await loader.refresh() }
            XCTFail("expected a throw")
        } catch let error as ShardMapFetchError {
            XCTAssertEqual(error.attempts.map(\.url), [primary, mirror1])
            XCTAssertEqual(error.attempts.last?.error as? ShardMapLoaderError,
                           .outdatedMap(served: 9, latestSeen: 10))
            XCTAssertTrue(error.isNetworkFailure)
        }
    }

    func testStaleMirrorDoesNotBeatASlowPrimaryOnColdStart() async throws {
        // Persisted floor v10, no map loaded yet. The mirror lags at v9 and
        // answers first; the primary is slower (it answers only once the mirror
        // has been requested) but serves v10. The delay is zero, so a mirror
        // that merely arrived first would win; the stale one must not.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .dataAfterRequestOf(mirror1, mapJSON(10, host: "primary-host.iterm2.com")))
        stub.set(mirror1, .data(mapJSON(9, host: "stale-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1],
                                    fallbackDelay: 0, mirrorTiming: .withPrimary, fetcher: stub, initialHighestVersion: 10)

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 10)
        let host = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(host, "primary-host.iterm2.com")
    }

    func testFailureSoFarReportsRecordedFailuresAndSourcesStillWaiting() async throws {
        // A caller that gives up early (an overall timeout) can still say what
        // happened to each source.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .fail(URLError(.cannotFindHost)))
        stub.set(mirror1, .hang)
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 3600,
                                    mirrorTiming: .withPrimary, fetcher: stub)
        let refresh = Task { try await loader.refresh() }
        // Wait until the primary's failure has been recorded.
        let recorded = expectation(description: "primary failure recorded")
        Task {
            while await loader.failureSoFar()?.attempts.first?.error as? URLError == nil {
                await Task.yield()
            }
            recorded.fulfill()
        }
        await fulfillment(of: [recorded], timeout: 60)
        refresh.cancel()

        let report = await loader.failureSoFar()

        XCTAssertEqual(report?.attempts.map(\.url), [primary, mirror1])
        XCTAssertEqual((report?.attempts.first?.error as? URLError)?.code, .cannotFindHost)
        // The mirror had only just started when the caller gave up.
        XCTAssertEqual(report?.attempts.last?.error as? ShardMapLoaderError, .cutShort)
        XCTAssertNotNil(report?.attempts.last?.duration)
    }

    func testAbandonedFetchStopsCountingTheWait() {
        // A caller's timeout cancels the fetch. However much later the report
        // is read, a source still waiting then waited only until the timeout.
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let progress = ShardMapFetchProgress(urls: [primary, mirror1])
        progress.started(0, at: start)
        progress.started(1, at: start.addingTimeInterval(29.6))
        progress.abandon(at: start.addingTimeInterval(30))

        let report = progress.report(at: start.addingTimeInterval(340))

        XCTAssertEqual((report?.attempts.first?.error as? URLError)?.code, .timedOut)
        XCTAssertEqual(report?.attempts.first?.duration ?? 0, 30, accuracy: 0.001)
        // The mirror got 0.4 seconds: cut short, not unresponsive.
        XCTAssertEqual(report?.attempts.last?.error as? ShardMapLoaderError, .cutShort)
        XCTAssertEqual(report?.attempts.last?.duration ?? 0, 0.4, accuracy: 0.001)
    }

    func testSlowSourceUnderAShortBudgetIsNotCalledUnresponsive() {
        // A caller with a short budget (the NSE's 10 seconds) gives up while
        // both sources are merely slow. Ten seconds of silence is less than a
        // request gets before timing out by itself, so it must not be reported
        // as a network dropping traffic, nor draw the advice to change networks.
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let progress = ShardMapFetchProgress(urls: [primary, mirror1])
        progress.started(0, at: start)
        progress.started(1, at: start.addingTimeInterval(2))
        progress.abandon(at: start.addingTimeInterval(10))

        let report = progress.report(at: start.addingTimeInterval(11))

        XCTAssertEqual(report?.attempts.map { $0.error as? ShardMapLoaderError }, [.cutShort, .cutShort])
        XCTAssertEqual(report?.isNetworkFailure, false)
        XCTAssertEqual(report?.summary.contains("VPN"), false)
        XCTAssertEqual(report?.details.contains("firewall"), false)
    }

    func testProgressReportsMarkMirrors() {
        let progress = ShardMapFetchProgress(urls: [primary, mirror1])
        progress.started(0)
        progress.started(1)
        progress.failed(0, error: URLError(.cancelled), duration: 1)
        progress.failed(1, error: URLError(.cannotFindHost), duration: 1)
        // The cancelled primary is left out; the mirror is still a mirror.
        XCTAssertEqual(progress.failure().attempts.map(\.isMirror), [true])
        XCTAssertEqual(progress.report()?.attempts.map(\.isMirror), [true])
    }

    func testCancelledFetchesAreReportedWhenTheyAreAllThatFailed() {
        let progress = ShardMapFetchProgress(urls: [primary, mirror1])
        progress.failed(0, error: URLError(.cancelled), duration: 1)
        progress.failed(1, error: CancellationError(), duration: 1)
        XCTAssertEqual(progress.failure().attempts.map(\.url), [primary, mirror1])
    }

    func testFailureSoFarInAScopeDescribesThatScopesFetch() async throws {
        // Two callers overlap on one loader. The first's primary failed DNS;
        // the second's fetch then replaces the loader's latest record. When the
        // first gives up, it must still hear about its own fetch.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .fail(URLError(.cannotFindHost)))
        stub.set(mirror1, .hang)
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 3600,
                                    mirrorTiming: .withPrimary, fetcher: stub)
        let scope = ShardMapFetchScope()
        let first = Task {
            try await ShardMapFetchScope.$current.withValue(scope) { try await loader.refresh() }
        }
        let recorded = expectation(description: "first fetch's primary failure recorded")
        Task {
            while await loader.failureSoFar()?.attempts.first?.error as? URLError == nil {
                await Task.yield()
            }
            recorded.fulfill()
        }
        await fulfillment(of: [recorded], timeout: 60)

        stub.set(primary, .hang)
        let second = Task { try await loader.refresh() }
        let started = expectation(description: "second fetch started")
        Task {
            while stub.requested.count < 4 {
                await Task.yield()
            }
            started.fulfill()
        }
        await fulfillment(of: [started], timeout: 60)
        first.cancel()

        let scoped = await ShardMapFetchScope.$current.withValue(scope) { await loader.failureSoFar() }
        XCTAssertEqual((scoped?.attempts.first?.error as? URLError)?.code, .cannotFindHost)
        // Outside the scope, the latest fetch is the second caller's, whose
        // primary has only just started.
        let latest = await loader.failureSoFar()
        XCTAssertEqual(latest?.attempts.first?.error as? ShardMapLoaderError, .cutShort)
        // A scope in which no fetch was made has nothing to report.
        let empty = await ShardMapFetchScope.$current.withValue(ShardMapFetchScope()) { await loader.failureSoFar() }
        XCTAssertNil(empty)
        second.cancel()
    }

    func testFinishedFetchIsNotAbandoned() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let progress = ShardMapFetchProgress(urls: [primary])
        progress.started(0, at: start)
        progress.finish(succeeded: true)
        progress.abandon(at: start.addingTimeInterval(10))
        XCTAssertNil(progress.report(at: start.addingTimeInterval(20)))
    }

    func testBackgroundRefreshDoesNotReplaceTheBlockingFetchsRecord() async throws {
        // A blocking refresh fails and leaves its record. A background refresh
        // that then hangs must not take its place: a later failureSoFar() would
        // describe a fetch nobody was waiting on.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .data(mapJSON(3, host: "primary-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [], fetcher: stub)
        _ = try await bounded { try await loader.refresh() }
        stub.set(primary, .fail(URLError(.cannotFindHost)))
        _ = try? await bounded { try await loader.refresh() }

        stub.set(primary, .hang)
        await loader.refreshInBackground()
        let requested = expectation(description: "background fetch started")
        Task {
            while stub.requested.count < 3 {
                await Task.yield()
            }
            requested.fulfill()
        }
        await fulfillment(of: [requested], timeout: 60)

        let report = await loader.failureSoFar()
        XCTAssertEqual((report?.attempts.first?.error as? URLError)?.code, .cannotFindHost)
    }

    func testForcedRefreshIsSatisfiedByAMirrorServingTheLoadedVersion() async throws {
        // v5 is loaded and the primary has become unreachable. The mirror still
        // serves v5: the loaded map is current, so the refresh succeeds with it.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .data(mapJSON(5, host: "current-host.iterm2.com")))
        stub.set(mirror1, .data(mapJSON(5, host: "current-host.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 0,
                                    fetcher: stub)
        _ = try await bounded { try await loader.refresh() }
        stub.set(primary, .fail(URLError(.timedOut)))

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 5)
        let report = await loader.failureSoFar()
        XCTAssertNil(report)
    }

    func testCancelledSourceIsLeftOutOfTheFailureReport() async throws {
        // The primary's fetch is cancelled out from under it (the Mac's plugin
        // reloading); the mirror fails for real. Only the mirror is reported, so
        // the advice to try another network survives.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .fail(URLError(.cancelled)))
        stub.set(mirror1, .fail(URLError(.cannotFindHost)))
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 0,
                                    fetcher: stub)
        do {
            _ = try await bounded { try await loader.refresh() }
            XCTFail("expected a throw")
        } catch let error as ShardMapFetchError {
            XCTAssertEqual(error.attempts.map(\.url), [mirror1])
            XCTAssertTrue(error.isNetworkFailure)
        }
        let report = await loader.failureSoFar()
        XCTAssertEqual(report?.attempts.map(\.url), [mirror1])
    }

    func testFailureSoFarIsNilAfterASuccessfulFetch() async throws {
        // The mirror was started and then abandoned when the primary won; it
        // must not be reported as unresponsive.
        let stub = ConcurrentStubFetcher()
        stub.set(primary, .dataAfterRequestOf(mirror1, mapJSON(3, host: "primary-host.iterm2.com")))
        stub.set(mirror1, .hang)
        let loader = ShardMapLoader(resolverURL: primary, fallbackURLs: [mirror1], fallbackDelay: 3600,
                                    mirrorTiming: .withPrimary, fetcher: stub)
        _ = try await bounded { try await loader.refresh() }

        let report = await loader.failureSoFar()
        XCTAssertNil(report)
    }

    // MARK: Logging

    func testCancelledFetchesAreNotLoggedAsFailures() {
        // A losing source is cancelled on every healthy race; URLSession reports
        // that as URLError(.cancelled), which must not read as a broken mirror.
        XCTAssertFalse(ShardMapLoader.isFailureWorthLogging(CancellationError()))
        XCTAssertFalse(ShardMapLoader.isFailureWorthLogging(URLError(.cancelled)))
        XCTAssertTrue(ShardMapLoader.isFailureWorthLogging(URLError(.timedOut)))
        XCTAssertTrue(ShardMapLoader.isFailureWorthLogging(ShardMapLoaderError.httpStatus(503)))
    }

    // MARK: Default mirrors

    func testDefaultResolverGetsTheGitHubPagesMirror() {
        XCTAssertEqual(ShardMapMirrors.fallbackURLs(forResolverURL: "https://resolver.iterm2.com/shardmap.json"),
                       ["https://gnachman.github.io/iterm2-companion-relay/shardmap.json"])
        XCTAssertEqual(ShardMapMirrors.fallbackURLs(forResolverURL: "https://RESOLVER.iterm2.com/shardmap.json"),
                       ["https://gnachman.github.io/iterm2-companion-relay/shardmap.json"])
    }

    func testOtherResolversGetNoMirror() {
        // A fork or self-hosted resolver must not silently fall back to ours.
        XCTAssertEqual(ShardMapMirrors.fallbackURLs(forResolverURL: "https://resolver.example.com/shardmap.json"), [])
        XCTAssertEqual(ShardMapMirrors.fallbackURLs(forResolverURL: "https://resolver.iterm2.com/other.json"), [])
        XCTAssertEqual(ShardMapMirrors.fallbackURLs(forResolverURL: "http://resolver.iterm2.com/shardmap.json"), [])
    }

    func testLoaderUsesDefaultMirrorsWhenNoneAreGiven() async throws {
        let stub = ConcurrentStubFetcher()
        let resolver = "https://resolver.iterm2.com/shardmap.json"
        let pages = "https://gnachman.github.io/iterm2-companion-relay/shardmap.json"
        stub.set(resolver, .fail(URLError(.timedOut)))
        stub.set(pages, .data(mapJSON(3, host: "relay2.iterm2.com")))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub)

        let map = try await bounded { try await loader.refresh() }

        XCTAssertEqual(map?.version, 3)
        XCTAssertEqual(Set(stub.requested), [resolver, pages])
    }
}

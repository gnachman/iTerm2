//
//  ShardMapFetchProgress.swift
//  CompanionCore
//
//  A running record of one shard-map fetch: when each source started and how
//  each has failed so far. It is the only record of a fetch's failures: the
//  error a failed fetch throws is built from it too. It outlives cancellation,
//  so a caller that gives up early (an overall resolve timeout) can still say
//  what happened to each source, e.g. that the primary failed DNS while only
//  the mirror was still waiting, instead of claiming that neither responded.
//

import Foundation

final class ShardMapFetchProgress: @unchecked Sendable {
    private let lock = UnfairLock()
    private let urls: [String]
    private var startTimes: [Int: Date] = [:]
    private var succeeded = Set<Int>()
    private var failures: [Int: ShardMapFetchError.Attempt] = [:]
    /// Nil while the fetch runs; then whether it produced a map.
    private var finishedSuccessfully: Bool?
    /// When the caller abandoned the fetch, if it did. Sources that were still
    /// waiting then are reported with the time they had waited by then.
    private var abandonedAt: Date?

    /// A source that waited less than this when the fetch was abandoned was not
    /// given a fair chance, so it is reported as cut short, not unresponsive.
    /// It is as long as a request is given before it times out by itself
    /// (URLSessionShardMapFetcher's default): a caller with a shorter budget
    /// (the NSE's 10 seconds) on a slow connection has not shown that the
    /// network drops the traffic.
    static let minimumConclusiveWait: TimeInterval = 15

    /// - urls: every source, primary first.
    init(urls: [String]) {
        self.urls = urls
    }

    func started(_ index: Int, at date: Date = Date()) {
        lock.withLock { startTimes[index] = date }
    }

    func succeeded(_ index: Int) {
        lock.withLock { _ = succeeded.insert(index) }
    }

    /// Record that a source failed, or served a map that was no use. Cancelled
    /// fetches are recorded too; the reports decide whether to mention them.
    func failed(_ index: Int, error: Error, duration: TimeInterval? = nil) {
        let attempt = ShardMapFetchError.Attempt(url: urls[index], error: error, duration: duration,
                                                 isMirror: index > 0)
        lock.withLock { failures[index] = attempt }
    }

    /// The error for a fetch in which no source produced a usable map: every
    /// failure, primary first. Cancelled fetches (the Mac's plugin reloading)
    /// are left out unless they are all there is: "cancelled" explains nothing
    /// next to a source that really failed.
    func failure() -> ShardMapFetchError {
        let all = lock.withLock { failures.keys.sorted().compactMap { failures[$0] } }
        let informative = all.filter { ShardMapLoader.isFailureWorthLogging($0.error) }
        return ShardMapFetchError(attempts: informative.isEmpty ? all : informative)
    }

    /// The fetch is over. Sources it abandoned are no longer reported as
    /// waiting, and after a success nothing is reported at all.
    func finish(succeeded: Bool) {
        lock.withLock { finishedSuccessfully = succeeded }
    }

    /// The caller gave up (it was cancelled, as by an overall timeout) with the
    /// fetch undecided. Sources still waiting stay in the report, but their
    /// wait stops growing.
    func abandon(at date: Date = Date()) {
        lock.withLock {
            if finishedSuccessfully == nil && abandonedAt == nil {
                abandonedAt = date
            }
        }
    }

    /// The failures so far plus, unless the fetch finished, no response from
    /// each source still waiting, after however long it has waited (up to when
    /// the fetch was abandoned). Nil after a success, or when nothing failed
    /// and nothing is waiting. Sources that answered, were cancelled, or never
    /// started are left out.
    func report(at now: Date = Date()) -> ShardMapFetchError? {
        let attempts = lock.withLock { () -> [ShardMapFetchError.Attempt] in
            if finishedSuccessfully == true {
                return []
            }
            let now = abandonedAt ?? now
            return urls.indices.compactMap { index in
                if let failure = failures[index] {
                    return ShardMapLoader.isFailureWorthLogging(failure.error) ? failure : nil
                }
                guard finishedSuccessfully == nil, let start = startTimes[index], !succeeded.contains(index) else {
                    return nil
                }
                let waited = now.timeIntervalSince(start)
                let error: Error = waited < Self.minimumConclusiveWait
                    ? ShardMapLoaderError.cutShort : URLError(.timedOut)
                return .init(url: urls[index], error: error, duration: waited, isMirror: index > 0)
            }
        }
        return attempts.isEmpty ? nil : ShardMapFetchError(attempts: attempts)
    }
}

/// Marks out one caller's resolve, so that when the caller's own timeout fires
/// it can ask what its fetch found even if another caller has since started a
/// fetch on the same loader. Bind `current` around both the resolve and the
/// call to failureSoFar().
public final class ShardMapFetchScope: @unchecked Sendable {
    @TaskLocal public static var current: ShardMapFetchScope?

    private let lock = UnfairLock()
    private var _progress: ShardMapFetchProgress?

    public init() {}

    /// The blocking fetch made within this scope, if one has started.
    var progress: ShardMapFetchProgress? {
        get { lock.withLock { _progress } }
        set { lock.withLock { _progress = newValue } }
    }
}

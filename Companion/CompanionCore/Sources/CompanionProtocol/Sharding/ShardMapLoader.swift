//
//  ShardMapLoader.swift
//  CompanionCore
//
//  Loads the shard map and applies monotonic versioning. The map URL is the
//  `resolver=` value from the pairing QR (PairingCode.resolverURL): it points
//  directly at the static shard-map JSON, served with a short TTL and replaced
//  atomically on publish, and is fetched verbatim (no path is appended, so the URL
//  a caller configures is exactly the URL that is GET'd). A single fetch gets the
//  latest map: the map carries its own `version`, so there is no separate
//  version-pointer file and no second round-trip. For the official resolver the
//  loader also races mirror copies of the map (ShardMapMirrors), for networks
//  that cannot reach the primary; the first valid map wins. Networking is behind an
//  injectable `ShardMapFetching`, so the loader is exercised entirely offline in
//  tests; persistence of the highest-seen version is the caller's concern (pass
//  `initialHighestVersion`, read `highestVersion`). See
//  docs/companion-relay-design.md (§6.3, §6.4, §6.8).
//

import Foundation

/// Abstraction over "GET this URL, give me the body" so the loader can be tested
/// without a network. The default conformance uses URLSession.
public protocol ShardMapFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public enum ShardMapLoaderError: Error, Equatable {
    /// The configured map URL could not be turned into a request URL.
    case invalidResolverURL(String)
    /// The HTTP response was not an HTTPURLResponse (e.g. a non-HTTP scheme).
    case badResponse
    /// A non-2xx HTTP status.
    case httpStatus(Int)
    /// The map file did not decode as a ShardMap.
    case malformedMap
    /// The Mac's plugin egress refused or failed the request itself (e.g. an
    /// invalid URL), described as text. Network errors do not use this: the
    /// plugin reports them as URLError (see CompanionPluginHTTPError).
    case requestFailed(String)
    /// A source served a map older than one this device has already seen (a
    /// lagging mirror or CDN edge), so it could not be used.
    case outdatedMap(served: Int, latestSeen: Int)
    /// The caller gave up before this source had been waiting long enough for
    /// its silence to mean anything.
    case cutShort
}

/// URLSession-backed fetcher: GET the URL, require a 2xx, return the body.
public struct URLSessionShardMapFetcher: ShardMapFetching {
    private let session: URLSession
    private let timeout: TimeInterval

    /// - session: pass a no-redirect session (CompanionURLSession.shared) so a
    ///   compromised CDN edge cannot 3xx-redirect the shard-map GET to a rogue
    ///   host. The default is URLSession.shared because this type lives below the
    ///   CompanionURLSession layer; every real call site injects the no-redirect
    ///   one.
    /// - timeout: bound the GET so a stalled fetch cannot blow a caller's budget
    ///   (e.g. the NSE, which resolves before its connect timeout applies).
    public init(session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.session = session
        self.timeout = timeout
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: timeout))
        guard let http = response as? HTTPURLResponse else {
            throw ShardMapLoaderError.badResponse
        }
        // A refused redirect surfaces here as a non-2xx (CompanionURLSession does
        // not follow 3xx), so it is thrown rather than followed to the rogue host.
        guard (200..<300).contains(http.statusCode) else {
            throw ShardMapLoaderError.httpStatus(http.statusCode)
        }
        return data
    }
}

public actor ShardMapLoader {
    private let resolverURL: String
    /// Mirrors of the map, tried when the primary is slow or failing (see
    /// ShardMapMirrors). Empty for a fork or self-hosted resolver.
    private let fallbackURLs: [String]
    /// How long the primary's map is preferred over a mirror's. All sources are
    /// fetched at once; after this delay (or once the primary fails) any valid
    /// map wins.
    private let fallbackDelay: TimeInterval
    private let mirrorTiming: ShardMapMirrorTiming
    private let fetcher: ShardMapFetching
    /// The latest blocking fetch's running record, for failureSoFar() outside
    /// a ShardMapFetchScope.
    private var progress: ShardMapFetchProgress?

    /// Durable floor across relaunches (§6.4). Seeds `highestVersion` at init and
    /// is written every time a newer map is adopted, so a fresh process cannot
    /// adopt a map older than one already trusted. Optional: tests and the delete
    /// path pass none and get within-session monotonicity only.
    private let floorStore: ShardMapVersionFloorStore?

    /// The highest map version adopted so far, or nil if none. Monotonicity
    /// (§6.6) rests on this: a version at or below it is ignored. Exposed so the
    /// caller can persist it across launches and seed a fresh loader with it.
    public private(set) var highestVersion: Int?

    /// The most recently adopted map, or nil before the first successful load.
    public private(set) var current: ShardMap?

    /// - fallbackURLs: mirrors to race against the primary; nil means the
    ///   defaults for `resolverURL` (ShardMapMirrors).
    /// - fallbackDelay: how long the primary's map is preferred over a mirror's.
    /// - mirrorTiming: when to start fetching the mirrors.
    public init(resolverURL: String,
                fallbackURLs: [String]? = nil,
                fallbackDelay: TimeInterval = 2,
                mirrorTiming: ShardMapMirrorTiming = .afterDelay,
                fetcher: ShardMapFetching = URLSessionShardMapFetcher(),
                initialHighestVersion: Int? = nil,
                floorStore: ShardMapVersionFloorStore? = nil) {
        self.resolverURL = resolverURL
        self.fallbackURLs = fallbackURLs ?? ShardMapMirrors.fallbackURLs(forResolverURL: resolverURL)
        self.fallbackDelay = fallbackDelay
        self.mirrorTiming = mirrorTiming
        self.fetcher = fetcher
        self.floorStore = floorStore
        // An explicit seed wins; otherwise read the persisted floor. Both are just
        // a starting floor for monotonicity, so the higher of the two is the safe
        // choice if a caller passes both.
        let persisted = floorStore?.floor(forResolverURL: resolverURL)
        switch (initialHighestVersion, persisted) {
        case let (seed?, stored?): self.highestVersion = max(seed, stored)
        case let (seed?, nil): self.highestVersion = seed
        case let (nil, stored?): self.highestVersion = stored
        case (nil, nil): self.highestVersion = nil
        }
    }

    /// Fetch and validate the latest map and, if its version is strictly newer
    /// than the highest already seen, adopt it. Returns the current map after
    /// the refresh (unchanged when the fetched map was not newer).
    /// Throws a ShardMapFetchError when no source produced a usable map (a
    /// fetch, decode, or validation failure, or on a cold start only maps below
    /// the persisted floor), leaving `current`/`highestVersion` untouched so a
    /// bad publish or a CDN blip never downgrades or corrupts the adopted map.
    @discardableResult
    public func refresh() async throws -> ShardMap? {
        try await refresh(recordingProgress: true)
    }

    private func refresh(recordingProgress: Bool) async throws -> ShardMap? {
        let map = try await fetchMap(recordingProgress: recordingProgress)
        // Monotonicity, but bootstrap-aware. Only the highest-seen VERSION is
        // persisted, not the map, so after a relaunch `current` is nil while
        // `highestVersion` may be a seeded floor.
        //  - With a map already loaded, adopt only a STRICTLY newer version; an
        //    equal or older one (e.g. a lagging CDN edge, or roll-forward meaning
        //    a lower version is never authoritative) is ignored.
        //  - With no map yet (fresh start / after restart), adopt a version EQUAL
        //    to the floor too, so a relaunch against an unchanged publisher picks
        //    a host instead of staying empty until the next version bump. A
        //    version strictly BELOW the floor never gets here: that is the
        //    stale-edge regression the persisted floor exists to prevent (§6.4),
        //    and the fetch fails with it as an outdated map (ShardMapRaceArbiter).
        guard Self.wouldAdopt(version: map.version, hasCurrentMap: current != nil,
                              highestVersion: highestVersion) else {
            CompanionLog.log("shardmap: fetched v\(map.version) not newer than current v\(highestVersion ?? 0); keeping current")
            return current
        }
        current = map
        highestVersion = map.version
        // Persist the new floor so a relaunch cannot adopt an older map from a
        // lagging edge (§6.4). Best-effort and monotonic in the store itself.
        floorStore?.setFloor(map.version, forResolverURL: resolverURL)
        CompanionLog.log("shardmap: adopted v\(map.version) (\(map.ranges.count) ranges)")
        return map
    }

    /// The monotonicity rule refresh() applies (see the comment there).
    static func wouldAdopt(version: Int, hasCurrentMap: Bool, highestVersion: Int?) -> Bool {
        guard let highestVersion else {
            return true
        }
        return hasCurrentMap ? version > highestVersion : version >= highestVersion
    }

    /// What the latest refresh() has found so far: each failure, and each
    /// source still waiting with how long it has waited. For a caller that
    /// gives up early (an overall timeout) and must still say what happened to
    /// each source. Nil after a successful fetch. Background refreshes are not
    /// included: nobody waits on them, and one must not replace the record of
    /// the fetch a caller is blocked on.
    ///
    /// Callers can overlap on one loader, and the latest refresh() may then be
    /// another caller's. Within a ShardMapFetchScope this describes the
    /// refresh() made in that scope instead.
    public func failureSoFar() -> ShardMapFetchError? {
        if let scope = ShardMapFetchScope.current {
            return scope.progress?.report()
        }
        return progress?.report()
    }

    /// Every URL a fetch tries, primary first.
    public nonisolated var sourceURLs: [String] {
        [resolverURL] + fallbackURLs
    }

    private var backgroundRefreshInFlight = false

    /// Kick off a refresh without blocking the caller, deduped so rapid callers
    /// (e.g. a reconnect storm) do not pile up concurrent fetches. Failures are
    /// swallowed: the caller already holds a usable adopted map, and the next call
    /// retries. Used by the resolver to keep the map fresh without ever blocking a
    /// connect on a control-plane fetch in steady state (§6.6, §8).
    public func refreshInBackground() {
        guard !backgroundRefreshInFlight else { return }
        backgroundRefreshInFlight = true
        Task {
            _ = try? await refresh(recordingProgress: false)
            backgroundRefreshInFlight = false
        }
    }

    /// Convenience: the host owning `bucket` per the currently adopted map, or
    /// nil if no map is loaded or the bucket is out of range.
    public func currentHost(forBucket bucket: Int) -> String? {
        current?.host(forBucket: bucket)
    }

    // MARK: - Fetching

    /// Fetch the primary, racing it against any mirrors. A lone primary runs
    /// the same race, so both cases fail and report the same way.
    /// - recordingProgress: whether this fetch is the one failureSoFar()
    ///   describes.
    private func fetchMap(recordingProgress: Bool) async throws -> ShardMap {
        let sources = [try mapURL()] + fallbackURLs.compactMap { URL(string: $0) }
        let progress = ShardMapFetchProgress(urls: sources.map(\.absoluteString))
        if recordingProgress {
            self.progress = progress
            ShardMapFetchScope.current?.progress = progress
        }
        let arbiter = ShardMapRaceArbiter(sourceCount: sources.count,
                                          highestVersion: highestVersion,
                                          hasCurrentMap: current != nil)
        return try await Self.race(sources: sources, arbiter: arbiter, progress: progress,
                                   fetcher: fetcher, delay: fallbackDelay, mirrorTiming: mirrorTiming)
    }

    /// Fetch the primary and the mirrors (started per `mirrorTiming`) and let
    /// `arbiter` pick the winner (see ShardMapRaceArbiter for the rules). If
    /// every source fails, throws a ShardMapFetchError listing each one.
    /// `progress` records each start and failure as it happens, so it survives
    /// the race being cancelled.
    ///
    /// The fetches are unstructured tasks feeding a stream rather than a task
    /// group, because a group cannot return until every child finishes and not
    /// every fetcher honors cancellation (the Mac's plugin does not). On exit
    /// the losers are cancelled without waiting for them.
    private static func race(sources: [URL],
                             arbiter: ShardMapRaceArbiter,
                             progress: ShardMapFetchProgress,
                             fetcher: ShardMapFetching,
                             delay: TimeInterval,
                             mirrorTiming: ShardMapMirrorTiming) async throws -> ShardMap {
        let (outcomes, continuation) = AsyncStream.makeStream(of: ShardMapRaceOutcome.self)
        var tasks: [Task<Void, Never>] = []
        defer {
            tasks.forEach { $0.cancel() }
            continuation.finish()
        }
        func start(_ index: Int) {
            let url = sources[index]
            // Recorded before the task exists, so a source the race launched is
            // never missing from the progress report, however late it runs.
            let start = Date()
            progress.started(index, at: start)
            tasks.append(Task {
                do {
                    let map = try await fetchMap(from: url, fetcher: fetcher)
                    progress.succeeded(index)
                    continuation.yield(.map(map, index: index))
                } catch {
                    let duration = Date().timeIntervalSince(start)
                    // Record it now, not when the race gets to it: the race may
                    // be cancelled first.
                    progress.failed(index, error: error, duration: duration)
                    continuation.yield(.failed(error, index: index, duration: duration))
                }
            })
        }
        var mirrorsStarted = false
        func startMirrors() {
            guard !mirrorsStarted else {
                return
            }
            mirrorsStarted = true
            sources.indices.dropFirst().forEach(start)
        }

        start(0)
        if mirrorTiming == .withPrimary {
            startMirrors()
        }
        tasks.append(Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            continuation.yield(.delayElapsed)
        })

        var arbiter = arbiter
        for await outcome in outcomes {
            // An outdated copy is a failure only the arbiter recognizes; the
            // fetches record every other kind themselves.
            if case let .map(map, index) = outcome, let rejection = arbiter.rejection(of: map, from: index) {
                progress.failed(index, error: rejection)
            }
            let decision = arbiter.handle(outcome)
            if !arbiter.primaryHasPriority {
                // The delay elapsed, or the primary failed or was out of date.
                startMirrors()
            }
            switch decision {
            case .wait:
                continue
            case let .win(map, index):
                progress.finish(succeeded: true)
                if index > 0 {
                    CompanionLog.log("shardmap: primary unavailable; using mirror \(sources[index].absoluteString)")
                }
                return map
            case .fail:
                progress.finish(succeeded: false)
                throw progress.failure()
            }
        }
        // The stream only ends early when the caller is cancelled. Stop the
        // clock on the sources still waiting, for failureSoFar().
        progress.abandon()
        try Task.checkCancellation()
        throw progress.failure()
    }

    /// GET, decode, and validate one source. A map that fails validation counts
    /// as a failed fetch, so when racing an invalid map cannot win.
    private static func fetchMap(from url: URL,
                                 fetcher: ShardMapFetching) async throws -> ShardMap {
        let data: Data
        do {
            data = try await fetcher.data(from: url)
        } catch {
            if isFailureWorthLogging(error) {
                CompanionLog.log("shardmap: GET \(url.absoluteString) failed: \(error)")
            }
            throw error
        }
        guard let map = try? JSONDecoder().decode(ShardMap.self, from: data) else {
            CompanionLog.log("shardmap: GET \(url.absoluteString) returned an undecodable body (\(data.count) bytes)")
            throw ShardMapLoaderError.malformedMap
        }
        do {
            try map.validate()
        } catch {
            CompanionLog.log("shardmap: v\(map.version) from \(url.absoluteString) failed validation: \(error); not adopting")
            throw error
        }
        return map
    }

    /// False for a cancelled fetch, which is how every losing race source ends.
    /// URLSession reports cancellation as URLError(.cancelled) rather than
    /// CancellationError, so both are checked.
    static func isFailureWorthLogging(_ error: Error) -> Bool {
        !(error is CancellationError) && (error as? URLError)?.code != .cancelled
    }

    /// The configured URL, fetched verbatim: it points directly at the shard-map
    /// JSON, so nothing is appended and the URL a caller configures is exactly the
    /// URL that is GET'd (which keeps it trivially pointable at any test fixture or
    /// self-hosted map).
    private func mapURL() throws -> URL {
        guard let url = URL(string: resolverURL) else {
            throw ShardMapLoaderError.invalidResolverURL(resolverURL)
        }
        return url
    }
}

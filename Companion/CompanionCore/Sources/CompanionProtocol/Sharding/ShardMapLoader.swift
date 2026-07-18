//
//  ShardMapLoader.swift
//  CompanionCore
//
//  Loads the shard map from a resolver base URL and applies monotonic
//  versioning. The resolver base URL is the `resolver=` value from the pairing
//  QR (PairingCode.resolverURL); the map is a single file under it,
//  `shardmap.json`, served with a short TTL and replaced atomically on publish.
//  A single fetch gets the latest map: the map carries its own `version`, so
//  there is no separate version-pointer file and no second round-trip. Networking
//  is behind an injectable `ShardMapFetching`, so the loader is exercised
//  entirely offline in tests; persistence of the highest-seen version is the
//  caller's concern (pass `initialHighestVersion`, read `highestVersion`). See
//  docs/companion-relay-design.md (§6.3, §6.4, §6.8).
//
//  NOT wired into the app yet: this is the standalone loader; a later step
//  computes a room's bucket and calls it to pick a host.
//

import Foundation

/// Abstraction over "GET this URL, give me the body" so the loader can be tested
/// without a network. The default conformance uses URLSession.
public protocol ShardMapFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public enum ShardMapLoaderError: Error, Equatable {
    /// The resolver base URL could not be turned into a request URL.
    case invalidResolverURL(String)
    /// The HTTP response was not an HTTPURLResponse (e.g. a non-HTTP scheme).
    case badResponse
    /// A non-2xx HTTP status.
    case httpStatus(Int)
    /// The map file did not decode as a ShardMap.
    case malformedMap
}

/// URLSession-backed fetcher: GET the URL, require a 2xx, return the body.
public struct URLSessionShardMapFetcher: ShardMapFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ShardMapLoaderError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ShardMapLoaderError.httpStatus(http.statusCode)
        }
        return data
    }
}

public actor ShardMapLoader {
    /// Filename of the map under the resolver base URL. Served with a short TTL
    /// and replaced atomically on publish, so a single fetch always yields the
    /// latest map (§6.3).
    public static let shardMapFilename = "shardmap.json"

    private let resolverURL: String
    private let fetcher: ShardMapFetching

    /// The highest map version adopted so far, or nil if none. Monotonicity
    /// (§6.6) rests on this: a version at or below it is ignored. Exposed so the
    /// caller can persist it across launches and seed a fresh loader with it.
    public private(set) var highestVersion: Int?

    /// The most recently adopted map, or nil before the first successful load.
    public private(set) var current: ShardMap?

    public init(resolverURL: String,
                fetcher: ShardMapFetching = URLSessionShardMapFetcher(),
                initialHighestVersion: Int? = nil) {
        self.resolverURL = resolverURL
        self.fetcher = fetcher
        self.highestVersion = initialHighestVersion
    }

    /// Fetch the latest map and, if its version is strictly newer than the
    /// highest already seen, validate and adopt it. Returns the current map after
    /// the refresh (unchanged, possibly nil, when the fetched map was not newer).
    /// Throws on a fetch, decode, or validation failure, leaving
    /// `current`/`highestVersion` untouched so a bad publish or a CDN blip never
    /// downgrades or corrupts the adopted map.
    @discardableResult
    public func refresh() async throws -> ShardMap? {
        let map = try await fetchMap()
        // Monotonicity, but bootstrap-aware. Only the highest-seen VERSION is
        // persisted, not the map, so after a relaunch `current` is nil while
        // `highestVersion` may be a seeded floor.
        //  - With a map already loaded, adopt only a STRICTLY newer version; an
        //    equal or older one (e.g. a lagging CDN edge, or roll-forward meaning
        //    a lower version is never authoritative) is ignored.
        //  - With no map yet (fresh start / after restart), adopt a version EQUAL
        //    to the floor too, so a relaunch against an unchanged publisher picks
        //    a host instead of staying empty until the next version bump. Still
        //    reject a version strictly BELOW the floor: that is the stale-edge
        //    regression the persisted floor exists to prevent (§6.4).
        if let highestVersion {
            if current == nil {
                if map.version < highestVersion { return current }
            } else if map.version <= highestVersion {
                return current
            }
        }
        try map.validate()
        current = map
        highestVersion = map.version
        return map
    }

    /// Convenience: the host owning `bucket` per the currently adopted map, or
    /// nil if no map is loaded or the bucket is out of range.
    public func currentHost(forBucket bucket: Int) -> String? {
        current?.host(forBucket: bucket)
    }

    // MARK: - Fetching

    private func fetchMap() async throws -> ShardMap {
        let data = try await fetcher.data(from: try mapURL())
        guard let map = try? JSONDecoder().decode(ShardMap.self, from: data) else {
            throw ShardMapLoaderError.malformedMap
        }
        return map
    }

    /// Build the URL of the map file under the resolver base. The base is treated
    /// as a directory: the filename is appended to its path (joined by a single
    /// slash), so a resolver hosted at a subpath (`https://cdn/x/y`) yields
    /// `.../x/y/shardmap.json` rather than replacing its last path component.
    /// Uses URLComponents so the host/port/encoding come straight from the parsed
    /// base rather than from string surgery.
    private func mapURL() throws -> URL {
        guard var components = URLComponents(string: resolverURL) else {
            throw ShardMapLoaderError.invalidResolverURL(resolverURL)
        }
        var path = components.percentEncodedPath
        if !path.hasSuffix("/") {
            path += "/"
        }
        components.percentEncodedPath = path + Self.shardMapFilename
        guard let url = components.url else {
            throw ShardMapLoaderError.invalidResolverURL(resolverURL)
        }
        return url
    }
}

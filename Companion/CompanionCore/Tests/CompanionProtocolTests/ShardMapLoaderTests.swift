//
//  ShardMapLoaderTests.swift
//  CompanionCore
//
//  The loader fetches the single latest shard-map file from a resolver base URL,
//  applies monotonic versioning, and validates before adopting. Networking is
//  stubbed so these run offline. See docs/companion-relay-design.md (§6.3, §6.4).
//

import XCTest
@testable import CompanionProtocol

/// A canned-response fetcher: maps an absolute URL string to a result, and
/// records every URL requested (so tests can assert what was fetched). Single-
/// threaded test use, hence @unchecked Sendable.
private final class StubFetcher: ShardMapFetching, @unchecked Sendable {
    var responses: [String: Result<Data, Error>] = [:]
    var requested: [String] = []

    func data(from url: URL) async throws -> Data {
        requested.append(url.absoluteString)
        guard let result = responses[url.absoluteString] else {
            throw ShardMapLoaderError.httpStatus(404)
        }
        return try result.get()
    }
}

/// In-memory floor store: records the highest version per resolver, monotonic.
/// Single-threaded test use, hence @unchecked Sendable.
private final class InMemoryFloorStore: ShardMapVersionFloorStore, @unchecked Sendable {
    private var floors: [String: Int] = [:]
    func floor(forResolverURL resolverURL: String) -> Int? { floors[resolverURL] }
    func setFloor(_ version: Int, forResolverURL resolverURL: String) {
        if let existing = floors[resolverURL], existing >= version { return }
        floors[resolverURL] = version
    }
}

final class ShardMapLoaderTests: XCTestCase {
    private let resolver = "https://resolver.example.com/"
    private var mapURL: String { resolver + "shardmap.json" }

    /// A valid two-range map at the given version.
    private func mapJSON(_ version: Int,
                         host0: String = "relay1.iterm2.com",
                         host1: String = "relay2.iterm2.com") -> Data {
        Data("""
        {
          "version": \(version),
          "ranges": [
            { "low": 0, "high": 32767, "host": "\(host0)" },
            { "low": 32768, "high": 65535, "host": "\(host1)" }
          ]
        }
        """.utf8)
    }

    // MARK: Happy path

    func testFreshLoadAdoptsMap() async throws {
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(37))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub)

        let map = try await loader.refresh()

        XCTAssertEqual(map?.version, 37)
        let current = await loader.current
        let highest = await loader.highestVersion
        let host0 = await loader.currentHost(forBucket: 0)
        let host1 = await loader.currentHost(forBucket: 65535)
        XCTAssertEqual(current?.version, 37)
        XCTAssertEqual(highest, 37)
        XCTAssertEqual(host0, "relay1.iterm2.com")
        XCTAssertEqual(host1, "relay2.iterm2.com")
        XCTAssertEqual(stub.requested, [mapURL])
    }

    func testRefreshAdoptsNewerVersionOnSecondPoll() async throws {
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(37, host0: "relay1.iterm2.com"))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub)
        _ = try await loader.refresh()

        // A reshard is published to the same URL; bucket 0 moved to relay3.
        stub.responses[mapURL] = .success(mapJSON(38, host0: "relay3.iterm2.com"))
        let map = try await loader.refresh()

        let highest = await loader.highestVersion
        let host0 = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(map?.version, 38)
        XCTAssertEqual(highest, 38)
        XCTAssertEqual(host0, "relay3.iterm2.com")
    }

    // MARK: Monotonicity

    func testOlderMapIgnoredAndNotAdopted() async throws {
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(37, host0: "relay1.iterm2.com"))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub)
        _ = try await loader.refresh()

        // A lagging edge now serves an older map. It is fetched but must not be
        // adopted: the newer map is kept.
        stub.responses[mapURL] = .success(mapJSON(36, host0: "stale.iterm2.com"))
        let map = try await loader.refresh()

        let highest = await loader.highestVersion
        let host0 = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(map?.version, 37)
        XCTAssertEqual(highest, 37)
        XCTAssertEqual(host0, "relay1.iterm2.com")   // still the newer map's host
    }

    func testEqualVersionNotReadopted() async throws {
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(37, host0: "relay1.iterm2.com"))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub)
        _ = try await loader.refresh()

        // Same version served again (e.g. a republish that kept the number).
        // Ignored; the current map is left in place.
        stub.responses[mapURL] = .success(mapJSON(37, host0: "different.iterm2.com"))
        _ = try await loader.refresh()

        let host0 = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(host0, "relay1.iterm2.com")
    }

    func testRestartSeededWithVersionAdoptsEqualVersion() async throws {
        // After a relaunch only the version was persisted, so `current` is nil and
        // `highestVersion` is the seeded floor. If the publisher is still serving
        // that same version, it MUST be adopted (bootstrap), or resolved mode can
        // never pick a host after a restart.
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(40))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub,
                                    initialHighestVersion: 40)
        let map = try await loader.refresh()

        XCTAssertEqual(map?.version, 40)
        let host0 = await loader.currentHost(forBucket: 0)
        XCTAssertEqual(host0, "relay1.iterm2.com")
    }

    func testRestartSeededWithVersionRejectsOlderFromStaleEdge() async throws {
        // On restart, a lagging edge serving a version BELOW the persisted floor
        // must NOT be adopted (the regression the floor exists to prevent). Nothing
        // is loaded until an edge catches up to the floor or beyond.
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(39))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub,
                                    initialHighestVersion: 40)
        let map = try await loader.refresh()

        XCTAssertNil(map)
        let current = await loader.current
        XCTAssertNil(current)
    }

    // MARK: Durable floor persistence (§6.4)

    func testAdoptingAMapPersistsTheFloorToTheStore() async throws {
        // Every adopted version is written through to the store so it survives a
        // relaunch (the within-session highestVersion alone does not).
        let store = InMemoryFloorStore()
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(41))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub, floorStore: store)
        _ = try await loader.refresh()
        XCTAssertEqual(store.floor(forResolverURL: resolver), 41)

        // A newer map advances the persisted floor too.
        stub.responses[mapURL] = .success(mapJSON(42))
        _ = try await loader.refresh()
        XCTAssertEqual(store.floor(forResolverURL: resolver), 42)
    }

    func testFreshLoaderSeedsFloorFromStoreAndRejectsStaleEdge() async throws {
        // Simulate a relaunch: the store already holds a floor of 41 from a prior
        // process, so a brand-new loader (current == nil) is seeded from it. A
        // lagging edge now serving v40 must NOT be adopted, the exact §6.4
        // regression the persisted floor exists to prevent; nothing loads until an
        // edge reaches the floor or beyond.
        let store = InMemoryFloorStore()
        store.setFloor(41, forResolverURL: resolver)
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(40))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub, floorStore: store)

        let seeded = await loader.highestVersion
        XCTAssertEqual(seeded, 41)   // seeded from the store, not the served map
        let map = try await loader.refresh()
        XCTAssertNil(map)
        let current = await loader.current
        XCTAssertNil(current)
    }

    func testFreshLoaderSeededFromStoreAdoptsEqualFloor() async throws {
        // Same relaunch, but the publisher still serves the floor version: it MUST
        // be adopted (bootstrap), or resolved mode could never pick a host after a
        // restart against an unchanged publisher.
        let store = InMemoryFloorStore()
        store.setFloor(41, forResolverURL: resolver)
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(41))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub, floorStore: store)

        let map = try await loader.refresh()
        XCTAssertEqual(map?.version, 41)
        XCTAssertEqual(store.floor(forResolverURL: resolver), 41)
    }

    func testExplicitSeedAndStoreFloorTakeTheHigher() async {
        // If a caller passes both an explicit seed and there is a persisted floor,
        // the higher wins (both are only a starting floor for monotonicity).
        let store = InMemoryFloorStore()
        store.setFloor(50, forResolverURL: resolver)
        let loaderHigherStore = ShardMapLoader(resolverURL: resolver, fetcher: StubFetcher(),
                                               initialHighestVersion: 30, floorStore: store)
        let a = await loaderHigherStore.highestVersion
        XCTAssertEqual(a, 50)

        store.setFloor(10, forResolverURL: resolver + "x")   // untouched: different key
        let loaderHigherSeed = ShardMapLoader(resolverURL: resolver, fetcher: StubFetcher(),
                                              initialHighestVersion: 99, floorStore: store)
        let b = await loaderHigherSeed.highestVersion
        XCTAssertEqual(b, 99)
    }

    // MARK: Failures leave state untouched

    func testMalformedMapThrows() async throws {
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(Data("{ broken".utf8))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub)
        await XCTAssertThrowsErrorAsync(try await loader.refresh()) {
            XCTAssertEqual($0 as? ShardMapLoaderError, .malformedMap)
        }
    }

    func testValidationFailurePropagatesAndKeepsCurrent() async throws {
        let stub = StubFetcher()
        stub.responses[mapURL] = .success(mapJSON(37))
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub)
        _ = try await loader.refresh()

        // A newer but malformed map (well-formed JSON, but leaves a gap) must not
        // be adopted, and the previously adopted map must survive.
        stub.responses[mapURL] = .success(Data("""
        { "version": 38,
          "ranges": [ { "low": 0, "high": 100, "host": "relay1.iterm2.com" } ] }
        """.utf8))
        await XCTAssertThrowsErrorAsync(try await loader.refresh()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .gapOrOverlap)
        }
        let highest = await loader.highestVersion
        let currentVersion = await loader.current?.version
        XCTAssertEqual(highest, 37)
        XCTAssertEqual(currentVersion, 37)
    }

    func testHttpErrorThrows() async throws {
        let stub = StubFetcher()   // no response registered -> stub throws httpStatus(404)
        let loader = ShardMapLoader(resolverURL: resolver, fetcher: stub)
        await XCTAssertThrowsErrorAsync(try await loader.refresh()) {
            XCTAssertEqual($0 as? ShardMapLoaderError, .httpStatus(404))
        }
    }

    // MARK: URL construction

    func testSubpathResolverAppendsRatherThanReplaces() async throws {
        // A resolver hosted at a subpath, with NO trailing slash: the filename
        // must append under it, not replace its last path component.
        let base = "https://cdn.example.com/iterm2/resolve"
        let stub = StubFetcher()
        let expected = "https://cdn.example.com/iterm2/resolve/shardmap.json"
        stub.responses[expected] = .success(mapJSON(9))
        let loader = ShardMapLoader(resolverURL: base, fetcher: stub)

        let map = try await loader.refresh()
        XCTAssertEqual(map?.version, 9)
        XCTAssertEqual(stub.requested, [expected])
    }

    func testBareOriginResolverBuildsRootFilename() async throws {
        // A resolver that is a bare origin (no path, no trailing slash) resolves
        // to /shardmap.json at the root.
        let base = "https://resolver.example.com"
        let stub = StubFetcher()
        let expected = "https://resolver.example.com/shardmap.json"
        stub.responses[expected] = .success(mapJSON(3))
        let loader = ShardMapLoader(resolverURL: base, fetcher: stub)

        let map = try await loader.refresh()
        XCTAssertEqual(map?.version, 3)
        XCTAssertEqual(stub.requested, [expected])
    }
}

// Small async throwing-assertion helper (XCTAssertThrowsError is sync-only).
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        handler(error)
    }
}

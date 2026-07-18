//
//  ShardHostResolverTests.swift
//  CompanionCore
//
//  Resolving a pairing's resolver URL + room to the owning relay origin, offline
//  via a stubbed shard-map fetcher. See docs/companion-relay-design.md (§6.2).
//

import XCTest
import CompanionProtocol
@testable import CompanionTransport

private final class StubShardFetcher: ShardMapFetching, @unchecked Sendable {
    var responses: [String: Result<Data, Error>] = [:]
    func data(from url: URL) async throws -> Data {
        guard let result = responses[url.absoluteString] else {
            throw ShardMapLoaderError.httpStatus(404)
        }
        return try result.get()
    }
}

final class ShardHostResolverTests: XCTestCase {
    private let resolverURL = "https://resolver.example.com/"
    private var mapURL: String { resolverURL + "shardmap.json" }

    private func code(resolverURL: String?) -> PairingCode {
        PairingCode(responderStaticPublicKey: Data(repeating: 7, count: 32),
                    pairingID: "abcd1234",
                    resolverURL: resolverURL)
    }

    /// A one-host map covering the whole ring, so any bucket resolves to `host`.
    private func wholeRingMap(_ version: Int, host: String) -> Data {
        Data("""
        { "version": \(version), "ranges": [ { "low": 0, "high": 65535, "host": "\(host)" } ] }
        """.utf8)
    }

    func test_resolvesBucketToOrigin() async throws {
        let fetcher = StubShardFetcher()
        fetcher.responses[mapURL] = .success(wholeRingMap(1, host: "relay1.iterm2.com"))
        let resolver = ShardHostResolver(resolverURL: resolverURL, fetcher: fetcher)
        let origin = try await resolver.relayOrigin(for: code(resolverURL: resolverURL))
        XCTAssertEqual(origin, "https://relay1.iterm2.com")
    }

    func test_throwsWhenCodeIsNotResolvedMode() async {
        let resolver = ShardHostResolver(resolverURL: resolverURL, fetcher: StubShardFetcher())
        await XCTAssertThrowsErrorAsync(try await resolver.relayOrigin(for: code(resolverURL: nil)))
    }

    func test_throwsWhenNoMapAdopted() async {
        // Floor above the served version -> refresh adopts nothing -> no host.
        let fetcher = StubShardFetcher()
        fetcher.responses[mapURL] = .success(wholeRingMap(5, host: "relay1.iterm2.com"))
        let resolver = ShardHostResolver(resolverURL: resolverURL, fetcher: fetcher,
                                         initialHighestVersion: 99)
        await XCTAssertThrowsErrorAsync(try await resolver.relayOrigin(for: code(resolverURL: resolverURL)))
    }

    func test_throwsWhenFetchFails() async {
        let resolver = ShardHostResolver(resolverURL: resolverURL, fetcher: StubShardFetcher())
        await XCTAssertThrowsErrorAsync(try await resolver.relayOrigin(for: code(resolverURL: resolverURL)))
    }
}

// Async throwing-assertion helper (XCTAssertThrowsError is sync-only).
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        // Expected.
    }
}

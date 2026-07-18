//
//  ShardHostResolver.swift
//  CompanionCore
//
//  Resolved (v2) mode: turn a pairing's resolver URL into the relay origin that
//  currently owns its room. The room's bucket (RelayRoom.bucket) is looked up in
//  the shard map fetched from the resolver (ShardMapLoader), yielding a host that
//  is fed to the ordinary relay transport as "https://host". Resolving is the
//  only new step; once it produces an origin, direct and resolved mode share all
//  the same admission/splice machinery. See docs/companion-relay-design.md
//  (§6.2, §6.4).
//

import Foundation
import CompanionProtocol

/// Resolves the relay origin that currently owns a pairing's room. Abstracted so
/// the resolving transports can be tested with a stub that returns a fixed origin
/// (or throws) without a network.
public protocol ShardHostResolving: Sendable {
    /// The relay origin (`https://host`) the shard map currently assigns to
    /// `code`'s room. Throws if the code is not resolved mode, the map cannot be
    /// loaded, or no host owns the bucket.
    func relayOrigin(for code: PairingCode) async throws -> String
}

/// Default resolver: one ShardMapLoader bound to a resolver URL, reused across
/// calls so the monotonic floor and cached map survive reconnects. Create one per
/// pairing (from the code's resolver URL) and share it across connect attempts.
public struct ShardHostResolver: ShardHostResolving {
    private let loader: ShardMapLoader

    /// - fetcher: the egress used to GET the shard map. Deliberately has NO
    ///   default: the Mac must pass a plugin-backed fetcher (its only sanctioned
    ///   outbound path), and a `URLSessionShardMapFetcher()` default would let a
    ///   Mac call site bypass the consent plugin without noticing. The phone
    ///   passes URLSession explicitly (it has no plugin).
    public init(resolverURL: String,
                fetcher: ShardMapFetching,
                initialHighestVersion: Int? = nil) {
        self.loader = ShardMapLoader(resolverURL: resolverURL,
                                     fetcher: fetcher,
                                     initialHighestVersion: initialHighestVersion)
    }

    public func relayOrigin(for code: PairingCode) async throws -> String {
        guard code.resolverURL != nil else {
            throw TransportError.connectionFailed("pairing code is not resolved mode (no resolver URL)")
        }
        let bucket = RelayRoom.bucket(responderStaticPublicKey: code.responderStaticPublicKey,
                                      pairingID: code.pairingID)
        CompanionLog.log("shardresolve: pid \(code.pairingID) -> bucket \(bucket); refreshing map")
        // Re-resolve on every call: a reconnect after a reshard must pick up the
        // new owner. The loader ignores anything not newer than what it holds, so
        // this is cheap when nothing changed.
        _ = try await loader.refresh()
        guard let host = await loader.currentHost(forBucket: bucket) else {
            CompanionLog.log("shardresolve: no host owns bucket \(bucket) (no map adopted)")
            throw TransportError.connectionFailed("shard map assigns no host to bucket \(bucket)")
        }
        CompanionLog.log("shardresolve: bucket \(bucket) -> https://\(host)")
        return "https://\(host)"
    }
}

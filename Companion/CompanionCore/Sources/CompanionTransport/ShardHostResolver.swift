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

    /// Resolve the relay origin to delete a room against at unpair: the owning
    /// shard host in resolved mode (looked up through `fetcher`), else the direct
    /// origin (`code.relayOrigin`, or `directOrigin` when the code carries none, as
    /// the mac's does), else nil. Best effort: on any miss the relay's idle TTL
    /// reclaims the room. Shared so the mac and phone unpair paths delete the same
    /// way. See docs/companion-relay-design.md.
    public static func resolveDeleteOrigin(code: PairingCode,
                                           fetcher: ShardMapFetching,
                                           directOrigin: String?) async -> String? {
        if code.resolverURL != nil {
            return try? await ShardHostResolver(resolverURL: code.resolverURL!, fetcher: fetcher)
                .relayOrigin(for: code)
        }
        return code.relayOrigin ?? directOrigin
    }

    public func relayOrigin(for code: PairingCode) async throws -> String {
        guard code.resolverURL != nil else {
            throw TransportError.connectionFailed("pairing code is not resolved mode (no resolver URL)")
        }
        let bucket = RelayRoom.bucket(responderStaticPublicKey: code.responderStaticPublicKey,
                                      pairingID: code.pairingID)
        // Steady state: a map is already adopted (this resolver is reused across a
        // session's reconnects). Return its host IMMEDIATELY and refresh in the
        // background, so a connect never blocks on, or fails from, a control-plane
        // fetch: a transient CDN blip must not fail a reconnect that a cached map
        // can serve (§8), and there is no steady-state dependence on the control
        // plane (§6.6). The next connect picks up any reshard; a reshard evicts the
        // room at the relay, forcing that reconnect.
        if let host = await loader.currentHost(forBucket: bucket) {
            await loader.refreshInBackground()
            CompanionLog.log("shardresolve: bucket \(bucket) -> https://\(host) (cached; refreshing in background)")
            return "https://\(host)"
        }
        // First resolve of the session: no map yet, so block on the initial fetch.
        // A failure here has no cached fallback, so it propagates (connect retries).
        CompanionLog.log("shardresolve: pid \(code.pairingID) -> bucket \(bucket); no map yet, fetching")
        _ = try await loader.refresh()
        guard let host = await loader.currentHost(forBucket: bucket) else {
            CompanionLog.log("shardresolve: no host owns bucket \(bucket) (no map adopted)")
            throw TransportError.connectionFailed("shard map assigns no host to bucket \(bucket)")
        }
        CompanionLog.log("shardresolve: bucket \(bucket) -> https://\(host)")
        return "https://\(host)"
    }
}

/// A per-session cache of one ShardHostResolver, keyed by (resolver URL, egress
/// token). Reused across a pairing's reconnects so the shard map's cache and
/// monotonic version floor survive within a session; rebuilt when either key
/// changes. The token lets a caller invalidate when its egress changes: the Mac
/// passes the plugin client's identity so a plugin reload rebuilds the resolver
/// against the new egress, while the phone (no plugin) passes a stable token
/// (nil). Both the Mac park path and the phone connect path use this, so the
/// floor-survives-reconnect invariant is encoded once (§6.4 "both endpoints run
/// the same resolution").
public struct ShardResolverCache {
    private var cached: (resolverURL: String, token: ObjectIdentifier?, resolver: ShardHostResolver)?

    public init() {}

    public mutating func resolver(resolverURL: String,
                                  token: ObjectIdentifier?,
                                  fetcher: ShardMapFetching) -> ShardHostResolver {
        if let cached, cached.resolverURL == resolverURL, cached.token == token {
            return cached.resolver
        }
        let resolver = ShardHostResolver(resolverURL: resolverURL, fetcher: fetcher)
        cached = (resolverURL, token, resolver)
        return resolver
    }
}

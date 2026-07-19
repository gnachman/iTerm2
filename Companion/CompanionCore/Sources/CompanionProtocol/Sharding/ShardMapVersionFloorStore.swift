//
//  ShardMapVersionFloorStore.swift
//  CompanionCore
//
//  Durable persistence of the highest shard-map version a client has ever adopted
//  (§6.4/§6.6, Appendix A invariant 3). The monotonic floor MUST survive an app
//  relaunch: without it, a freshly launched client that hits a lagging CDN edge
//  can adopt a map OLDER than one it already trusted, and resolve a pairing to a
//  host that no longer owns its bucket. The within-session floor (ShardMapLoader's
//  in-memory highestVersion) only guards reconnects; this closes the relaunch gap.
//
//  The store is keyed by resolver URL so pairings served by different resolvers
//  keep independent floors. It is injected into ShardMapLoader: the loader reads
//  the floor at init to seed highestVersion, and writes back every time it adopts
//  a newer map. Networking-free and behind a protocol, so the loader stays fully
//  testable offline (an in-memory stub) while the apps supply a UserDefaults-backed
//  one. See docs/companion-relay-design.md (§6.4).
//

import Foundation

public protocol ShardMapVersionFloorStore: Sendable {
    /// The highest map version ever adopted for `resolverURL`, or nil if none has
    /// been persisted. Read once at loader init to seed the monotonic floor.
    func floor(forResolverURL resolverURL: String) -> Int?

    /// Persist `version` as the floor for `resolverURL`. Called whenever the loader
    /// adopts a map. Implementations MUST keep it monotonic (never lower a stored
    /// floor), so a stale write or a race cannot roll the floor backward.
    func setFloor(_ version: Int, forResolverURL resolverURL: String)
}

/// A `UserDefaults`-backed floor store. Both apps use it: the phone with
/// `.standard`, the Mac with its `iTermUserDefaults` suite and a `NoSync` prefix
/// (the floor is local device state, not a synced setting). The key is the prefix
/// plus the resolver URL; UserDefaults keys may be arbitrary strings. `setFloor`
/// reads-then-writes under the assumption of a single writer per key (one loader
/// per resolver, shared via ShardResolverCache), taking the max defensively.
public final class UserDefaultsShardMapVersionFloorStore: ShardMapVersionFloorStore, @unchecked Sendable {
    // UserDefaults is thread-safe; the class is @unchecked Sendable on that basis.
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults, keyPrefix: String) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    private func key(_ resolverURL: String) -> String { keyPrefix + resolverURL }

    public func floor(forResolverURL resolverURL: String) -> Int? {
        // object(forKey:) distinguishes "never stored" (nil) from a stored 0.
        (defaults.object(forKey: key(resolverURL)) as? NSNumber)?.intValue
    }

    public func setFloor(_ version: Int, forResolverURL resolverURL: String) {
        let k = key(resolverURL)
        if let existing = (defaults.object(forKey: k) as? NSNumber)?.intValue, existing >= version {
            return
        }
        defaults.set(version, forKey: k)
    }
}

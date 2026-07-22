//
//  CompanionRelayMigration.swift
//  CompanionCore
//
//  The revision-11 relay migration (CompanionProtocolVersion): move devices off
//  the direct main relay onto the sharded resolver. A device that paired in direct
//  mode points at `https://relay.iterm2.com`; on upgrade it rewrites its pairing to
//  the default resolver so both endpoints resolve the owning shard host and
//  rendezvous there. These two constants are the before/after of that rewrite,
//  shared so the phone (which rewrites its stored pairing code) and the mac (which
//  rewrites its resolver advanced setting) agree byte-for-byte on the target.
//
//  The resolver URL here MUST match the mac's `CompanionResolverURL` advanced
//  setting default (iTermAdvancedSettingsModel), since a phone migrated to this URL
//  can only rendezvous with a mac that resolves through the same map.
//

import Foundation

public enum CompanionRelayMigration {
    /// The legacy direct main relay origin. A pairing (phone) or configured mode
    /// (mac) pointing here is what the revision-11 migration converts.
    public static let legacyDirectRelayOrigin = "https://relay.iterm2.com"

    /// The default resolver (shard-map JSON) URL a migrated pairing adopts. Kept in
    /// lockstep with the mac's `CompanionResolverURL` advanced-setting default.
    public static let defaultResolverURL = "https://resolver.iterm2.com/shardmap.json"

    /// Whether `code` is a legacy direct-relay pairing that should migrate: it uses
    /// the legacy relay origin and carries no resolver (so it is genuinely direct
    /// mode, not a resolved pairing that merely also lists a relay).
    public static func isLegacyDirectRelay(_ code: PairingCode) -> Bool {
        code.resolverURL == nil && code.relayOrigin == legacyDirectRelayOrigin
    }

    /// The resolved-mode pairing `code` migrates to: same identity (responder key +
    /// pairing id), the relay origin dropped, the default resolver adopted.
    public static func migrated(_ code: PairingCode) -> PairingCode {
        PairingCode(responderStaticPublicKey: code.responderStaticPublicKey,
                    pairingID: code.pairingID,
                    resolverURL: defaultResolverURL)
    }
}

//
//  ShardMapMirrors.swift
//  CompanionCore
//
//  Fallback copies of the official shard map, for clients whose network cannot
//  reach the primary resolver (it is served by Cloudflare, and some ISPs block
//  or misroute the shared Cloudflare addresses it uses). The relay is the only
//  transport, so an unreachable map would otherwise block pairing and every
//  cold reconnect. The GitHub Pages copy is published from the same file in the
//  iterm2-companion-relay repo (resolver/src/shardmap.json) by its Pages
//  workflow, so the two never diverge for long; monotonic versioning makes any
//  brief skew harmless. Its 10-minute cache bounds how stale it can be.
//

import Foundation

/// When the loader starts fetching the mirrors.
public enum ShardMapMirrorTiming: Sendable {
    /// Alongside the primary, so a failing primary falls back at once. For the
    /// phone, which refreshes rarely and only while the app is active.
    case withPrimary
    /// Only once the fallback delay elapses or the primary fails, so a healthy
    /// primary never touches the mirror. For the Mac, which refreshes often
    /// enough that racing would risk GitHub Pages rate limits.
    case afterDelay
}

public enum ShardMapMirrors {
    static let officialResolverHost = "resolver.iterm2.com"
    static let officialResolverPath = "/shardmap.json"
    static let gitHubPagesURL = "https://gnachman.github.io/iterm2-companion-relay/shardmap.json"

    /// Mirrors to try when `resolverURL` cannot be fetched. Only the official
    /// resolver has any: a fork or self-hosted resolver must never silently
    /// fall back to the official map.
    public static func fallbackURLs(forResolverURL resolverURL: String) -> [String] {
        guard let components = URLComponents(string: resolverURL),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == officialResolverHost,
              components.port == nil,
              components.path == officialResolverPath else {
            return []
        }
        return [gitHubPagesURL]
    }
}

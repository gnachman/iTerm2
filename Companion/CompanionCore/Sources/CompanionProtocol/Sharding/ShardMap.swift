//
//  ShardMap.swift
//  CompanionCore
//
//  The shard map: a static, versioned JSON file served from a CDN that maps
//  bucket ranges to relay hostnames. In resolved mode the pairing QR carries the
//  base URL this file is served under (`resolver=`, see PairingCode); a client
//  fetches the map, computes its room's bucket, and connects to the owning host.
//  This type is the parsed, validated model plus the bucket -> host lookup; the
//  fetching and monotonic-version logic live in ShardMapLoader. Pure value type,
//  no networking. See docs/companion-relay-design.md (§6.2, §6.3).
//
//  The `host` is a full relay hostname (the managed fleet names them
//  relay1.iterm2.com, relay2.iterm2.com, ...; a self-hosted resolver may use any
//  names), so the map is domain-agnostic and no host pattern is baked into the
//  client. The bucket count is NOT carried: it is fixed forever (expectedBuckets,
//  invariant 1), so a field for it could only ever hold one value; the ranges are
//  simply validated to tile [0, expectedBuckets - 1].
//
//  Example JSON:
//  {
//    "version": 37,
//    "ranges": [
//      { "low": 0,     "high": 32767, "host": "relay1.iterm2.com" },
//      { "low": 32768, "high": 65535, "host": "relay2.iterm2.com" }
//    ]
//  }
//

import Foundation

public struct ShardMap: Equatable, Sendable, Codable {
    /// One contiguous bucket range assigned to a host. A host may own several
    /// ranges (an arc that wraps the 0/65535 seam serializes as two ranges
    /// sharing a host, and a host may hold disjoint arcs for balancing), so the
    /// unit is a range, not a host. `low` and `high` are inclusive.
    public struct Entry: Equatable, Sendable, Codable {
        public let low: Int
        public let high: Int
        public let host: String

        public init(low: Int, high: Int, host: String) {
            self.low = low
            self.high = high
            self.host = host
        }
    }

    /// Monotonic version. Every actor ignores any map older than the newest it
    /// has already seen (§6.6), so this only ever moves forward.
    public let version: Int

    /// The bucket ranges. A valid map's ranges exactly partition
    /// `[0, expectedBuckets - 1]` with no gap or overlap (see `validate()`).
    public let ranges: [Entry]

    public init(version: Int, ranges: [Entry]) {
        self.version = version
        self.ranges = ranges
    }

    /// The immutable bucket count this build understands. Changing it rehashes
    /// every pairing, so it is fixed forever (Appendix A invariant 1). The map
    /// does not carry it (it could only ever be this value); the future
    /// roomName -> bucket derivation must use this same constant.
    public static let expectedBuckets = 65536

    public enum ValidationError: Error, Equatable {
        /// version < 0 (versions are monotonic and non-negative).
        case negativeVersion
        /// No ranges at all; a map must cover the whole bucket space.
        case emptyRanges
        /// A range with an empty host string.
        case emptyHost
        /// A range whose host is not a bare authority (has a scheme/path/
        /// userinfo/query/fragment/whitespace, is not lowercase, or has a
        /// trailing dot). The same string is the connect target, the cert SAN,
        /// and the proof origin, so a malformed entry silently breaks every proof
        /// for that host's buckets (§6.3/§6.10).
        case invalidHost(String)
        /// A range with low > high, or endpoints outside
        /// `[0, expectedBuckets - 1]`.
        case invalidRange(low: Int, high: Int)
        /// The ranges do not exactly tile `[0, expectedBuckets - 1]` (a gap
        /// between ranges, an overlap, or a duplicate boundary).
        case gapOrOverlap
    }

    /// A bare authority (§6.3/§6.10): no scheme/path/userinfo/query/fragment, no
    /// whitespace, lowercase, and no trailing dot. Accepts a DNS name, an IPv4
    /// literal, or a bracketed IPv6 authority with an optional `:port`.
    /// Deliberately permissive on the character set otherwise (the map is
    /// operator-authored); this only closes the "https://relay1" / uppercase /
    /// trailing-dot traps. Mirrors the Node `isBareAuthority` check byte-for-byte.
    static func isBareAuthority(_ host: String) -> Bool {
        if host.isEmpty || host.hasSuffix(".") { return false }
        for ch in host {
            if ch == "/" || ch == "@" || ch == "?" || ch == "#" { return false }
            if ch.isWhitespace || ch.isUppercase { return false }
        }
        return true
    }

    /// Throw unless this map is well formed: at least one range, every range
    /// in-bounds with a non-empty bare-authority host, and the ranges exactly
    /// partitioning `[0, expectedBuckets - 1]`. A wrap arc written as two ranges
    /// sharing a host still tiles the space, so it validates; host grouping is
    /// irrelevant to coverage.
    public func validate() throws {
        guard version >= 0 else { throw ValidationError.negativeVersion }
        guard !ranges.isEmpty else { throw ValidationError.emptyRanges }
        for range in ranges {
            guard !range.host.isEmpty else { throw ValidationError.emptyHost }
            guard Self.isBareAuthority(range.host) else { throw ValidationError.invalidHost(range.host) }
            guard range.low >= 0, range.high < Self.expectedBuckets, range.low <= range.high else {
                throw ValidationError.invalidRange(low: range.low, high: range.high)
            }
        }
        // Sort by low and walk: the first must start at 0, each next must start
        // exactly one past the previous (a larger low is a gap, a smaller-or-equal
        // one is an overlap or duplicate), and the last must end at
        // expectedBuckets - 1.
        let sorted = ranges.sorted { $0.low < $1.low }
        var expectedNext = 0
        for range in sorted {
            guard range.low == expectedNext else { throw ValidationError.gapOrOverlap }
            expectedNext = range.high + 1
        }
        guard expectedNext == Self.expectedBuckets else { throw ValidationError.gapOrOverlap }
    }

    /// The host owning `bucket`, or nil if the bucket is out of range or (in an
    /// unvalidated map) uncovered. A validated map covers every bucket in
    /// `[0, expectedBuckets - 1]`, so the nil case there is only an out-of-range
    /// bucket.
    public func host(forBucket bucket: Int) -> String? {
        guard bucket >= 0, bucket < Self.expectedBuckets else { return nil }
        for range in ranges where bucket >= range.low && bucket <= range.high {
            return range.host
        }
        return nil
    }
}

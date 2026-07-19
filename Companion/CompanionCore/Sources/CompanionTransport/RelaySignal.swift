//
//  RelaySignal.swift
//  CompanionCore
//
//  The client-side classification of a relay's rejection/close into the four
//  actions of the re-resolution wire-code contract (design §6.9). Pure: it maps a
//  WebSocket close (code + reason) or an HTTP status (+ optional owner hint) to
//  what the client should do next, so both the phone reconnect loop and the mac
//  park loop dispatch on one tested rule instead of re-deriving the taxonomy.
//
//  The whole point of §6.9: a re-resolve code (HTTP 421 / WS 4421) is the ONLY
//  thing that moves a client to a different host; every other code keeps it on the
//  one it has. Long-backoff cases (quota, displaced) are same-host but must not use
//  the ordinary short retry, and they are disambiguated by REASON, never by the
//  bare number (the relay overloads 1008 and 1000). See docs/companion-relay-design.md.
//

import Foundation

public enum RelaySignal: Equatable, Sendable {
    /// Leave this host: refetch the shard map and connect to whatever host it
    /// names. `ownerHint` is diagnostic only (§6.9) - the client never connects to
    /// it directly, only logs it; the map is the sole authority.
    case reResolve(ownerHint: String?)

    /// Transient: the host still owns the bucket but is busy/erroring/restarting.
    /// Retry the SAME host with the ordinary short jittered backoff.
    case retryHere

    /// Same host, but a deliberately LONG backoff (host-local exhaustion), so the
    /// client does not hammer it.
    case longBackoff(LongBackoffReason)

    /// A client or configuration error, not transient. Surface it; do not loop.
    case fatal

    public enum LongBackoffReason: Equatable, Sendable {
        case dailyQuota   // WS 1008 + "daily quota" (§5.3)
        case displaced    // WS 1000 + "displaced" (a duplicate instance took the slot)
    }

    /// Classify a WebSocket close. `code` is the numeric close code, or 0/any value
    /// when the stack cannot surface it (e.g. URLSessionWebSocketTask can't surface
    /// 4421); the `reason` sentinel is then the fallback, exactly as the existing
    /// quota close is matched on both its code and reason.
    public static func forWebSocketClose(code: Int, reason: String) -> RelaySignal {
        let lower = reason.lowercased()
        // Re-resolve: 4421, or the reshard sentinel ("reshard" alone or
        // "reshard <host>"). Guard the space/end so "resharding" does not match.
        if code == 4421 || lower == "reshard" || lower.hasPrefix("reshard ") {
            return .reResolve(ownerHint: ownerAfterReshardSentinel(reason))
        }
        // Long backoff, matched by code + reason (never the bare number).
        if code == 1008 && lower.contains("daily quota") {
            return .longBackoff(.dailyQuota)
        }
        if code == 1000 && lower.contains("displaced") {
            return .longBackoff(.displaced)
        }
        // Everything else on a socket is transient: retry the same host.
        return .retryHere
    }

    /// Classify an HTTP status from an admission or data-plane call. `ownerHint` is
    /// the `x-relay-owner` header value, if the host sent one (diagnostic only).
    public static func forHTTPStatus(_ status: Int, ownerHint: String? = nil) -> RelaySignal {
        switch status {
        case 421:
            return .reResolve(ownerHint: ownerHint)
        case 429:
            return .retryHere
        case 403, 413:
            return .fatal
        case 500...599:
            return .retryHere            // transient server error
        case 400...499:
            return .fatal                // other client errors: do not loop
        default:
            return .retryHere
        }
    }

    /// The owner named after the `reshard` sentinel in a 4421 reason, or nil for
    /// the bare sentinel. Only a hint; callers log it, they do not connect to it.
    static func ownerAfterReshardSentinel(_ reason: String) -> String? {
        let trimmed = reason.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("reshard") else { return nil }
        let rest = trimmed.dropFirst("reshard".count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}

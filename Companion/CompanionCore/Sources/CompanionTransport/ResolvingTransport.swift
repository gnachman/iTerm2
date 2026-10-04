//
//  ResolvingTransport.swift
//  CompanionCore
//
//  The resolved (v2) counterparts of the relay transports: they resolve the
//  owning relay origin from the shard map at connect/park time, then delegate to
//  the ordinary relay transport built against that origin. Resolving per attempt
//  is what makes a reconnect after a reshard land on the new owner (§6.4). See
//  ShardHostResolver.
//

import Foundation
import CompanionProtocol

/// Phone side, resolved mode: resolve the owning origin, then join it exactly as
/// direct mode does (same admission proof, same splice). The resolved origin is
/// bound into the admission transcript, so the proof matches the host actually
/// connected to.
struct ResolvingTransportConnector: TransportConnector {
    let transportName = "relay-resolved"
    let code: PairingCode
    let resolver: ShardHostResolving
    let webSocketFactory: RelayWebSocketFactory
    let roomSecret: (@Sendable () -> Data?)?
    let pairingTicket: String?
    let nonDisplacing: Bool

    func connect(to rendezvous: PairingRendezvous,
                 timeout: TimeInterval) async throws -> MessageTransport {
        // The resolve is a network fetch (cold in a fresh process like the NSE),
        // so it must share the caller's budget, or a stalled shard-map GET blows a
        // timeout the caller thinks it set (the NSE's 10s). Bound it, then give the
        // inner connect only the remaining budget so the total stays within
        // `timeout`.
        let start = Date()
        // The scope ties failureSoFar() to this connect's own map fetch: the
        // resolver is shared, and another caller's fetch may overlap this one.
        let relayOrigin = try await ShardMapFetchScope.$current.withValue(ShardMapFetchScope()) {
            try await resolveRelayOrigin(timeout: timeout)
        }
        let remaining = max(1, timeout - Date().timeIntervalSince(start))
        CompanionLog.log("resolved connect: joining \(relayOrigin) (\(Int(remaining))s left of \(Int(timeout))s)")
        let proof: @Sendable (RelayAdmission.Challenge, String) throws -> RelayAdmission.Proof =
            { challenge, roomName in
                try CompanionTransports.admissionProof(role: .phone, challenge: challenge,
                                                       roomName: roomName, origin: relayOrigin,
                                                       roomSecret: roomSecret?(),
                                                       pairingTicket: pairingTicket)
            }
        let connector = RelayTransportConnector(relayOrigin: relayOrigin,
                                                responderStaticKey: code.responderStaticPublicKey,
                                                joinProof: proof,
                                                nonDisplacing: nonDisplacing,
                                                webSocketFactory: webSocketFactory)
        return try await connector.connect(to: rendezvous, timeout: remaining)
    }

    /// The relay host for `code`, within `timeout`. A map that cannot be
    /// fetched is thrown as TransportError.shardMapUnavailable.
    private func resolveRelayOrigin(timeout: TimeInterval) async throws -> String {
        do {
            return try await withResolveTimeout(timeout) {
                try await resolver.relayOrigin(for: code)
            }
        } catch let error as ShardMapFetchError {
            // Every source failed: say what went wrong with each rather than
            // surface a raw URL error.
            CompanionLog.log("resolved connect: shard map unavailable: \(error.details)")
            throw TransportError.shardMapUnavailable(summary: error.summary, details: error.details)
        } catch is ResolveTimeoutError {
            // Keep whatever already went wrong (e.g. the primary failed DNS while
            // only the mirror was still waiting) rather than claiming that no
            // source responded.
            if let partial = await resolver.failureSoFar() {
                CompanionLog.log("resolved connect: shard map timed out: \(partial.details)")
                throw TransportError.shardMapUnavailable(summary: partial.summary, details: partial.details)
            }
            // Name the sources the resolver really uses; failing that, the one
            // every resolved-mode code has.
            let known = await resolver.mapSourceURLs()
            let urls = known.isEmpty ? [code.resolverURL].compactMap { $0 } : known
            let summary = ShardMapFetchError.noAnswerSummary(urls: urls, within: timeout)
            let details = ShardMapFetchError.noAnswerDetails(urls: urls, within: timeout)
            CompanionLog.log("resolved connect: shard map timed out: \(summary)")
            throw TransportError.shardMapUnavailable(summary: summary, details: details)
        }
    }
}

struct ResolveTimeoutError: Error {}

/// Run `operation`, throwing ResolveTimeoutError if it does not finish within
/// `seconds`. A hard bound when the operation honors cancellation (the shard-map
/// URLSession fetch does): the losing task is cancelled on scope exit.
func withResolveTimeout<T: Sendable>(_ seconds: TimeInterval,
                                     _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ResolveTimeoutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

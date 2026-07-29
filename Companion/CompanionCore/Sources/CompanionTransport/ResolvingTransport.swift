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
        let relayOrigin = try await withResolveTimeout(timeout) {
            try await resolver.relayOrigin(for: code)
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

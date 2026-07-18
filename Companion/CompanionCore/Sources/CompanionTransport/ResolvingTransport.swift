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
        let relayOrigin = try await resolver.relayOrigin(for: code)
        CompanionLog.log("resolved connect: joining \(relayOrigin)")
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
        return try await connector.connect(to: rendezvous, timeout: timeout)
    }
}

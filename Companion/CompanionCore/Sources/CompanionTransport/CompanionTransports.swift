//
//  CompanionTransports.swift
//  CompanionCore
//
//  The single place that decides which transports a pairing uses. Both apps
//  build their connector (phone) and listener (mac) stacks here, so the rule
//  lives in one tested spot instead of being duplicated in the app layers.
//
//  Currently the relay is the ONLY active transport: it reaches the mac
//  regardless of network topology (NAT, corporate wifi that blocks peer-to-peer
//  discovery, off-LAN), and reliability matters more than the latency the
//  local-network path would save. The Bonjour connector/listener are kept in
//  the package, switched off behind `useLocalNetworkTransport`, so bringing the
//  LAN fast path back later (raced alongside the relay) is a one-line change.
//

import Foundation
import CryptoKit
import CompanionProtocol

public enum CompanionTransports {
    /// Whether to also race the local-network (Bonjour) transport. Off for now;
    /// the relay is the sole transport so a pairing works the same on any
    /// network. Flip to true to restore Bonjour as a latency optimization.
    public static let useLocalNetworkTransport = false

    /// Build the admission proof for a role: a signature over the bound
    /// transcript when a roomSecret is available (established room), else an
    /// empty proof (open/pairing-mode room). The relay verifies the signature
    /// against the registered verifier; in open mode it ignores the proof.
    static func signedProof(role: RelayJoin.Role,
                            challenge: RelayAdmission.Challenge,
                            roomName: String,
                            origin: String,
                            roomSecret: Data?) throws -> RelayAdmission.Proof {
        guard let roomSecret else {
            return RelayAdmission.Proof(ticket: nil, signature: nil)
        }
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        let transcript = RelayJoin.transcript(role: role,
                                              nonce: challenge.nonce,
                                              roomName: roomName,
                                              origin: origin)
        let signature = try key.signature(for: transcript)
        return RelayAdmission.Proof(ticket: nil, signature: signature)
    }

    /// Phone side: the connector stack for a scanned (or stored) pairing code.
    /// Relay only (unless the LAN path is re-enabled); the relay connector is
    /// present only when the code carries a relay origin.
    ///
    /// - roomSecret: returns the persisted room secret once the pairing is
    ///   established (the phone registered its verifier), so reconnects sign
    ///   their join. Returns nil during/before first pairing (open-mode join).
    public static func connector(for code: PairingCode,
                                 session: URLSession = .shared,
                                 roomSecret: (@Sendable () -> Data?)? = nil) -> TransportConnector {
        var connectors: [TransportConnector] = []
        if useLocalNetworkTransport {
            connectors.append(BonjourTransportConnector())
        }
        if let relayOrigin = code.relayOrigin {
            let proof: (@Sendable (RelayAdmission.Challenge, String) throws -> RelayAdmission.Proof)? =
                roomSecret.map { secret in
                    { @Sendable challenge, roomName in
                        try signedProof(role: .phone, challenge: challenge, roomName: roomName,
                                        origin: relayOrigin, roomSecret: secret())
                    }
                }
            connectors.append(RelayTransportConnector(relayOrigin: relayOrigin,
                                                      responderStaticKey: code.responderStaticPublicKey,
                                                      joinProof: proof,
                                                      session: session))
        }
        return RaceTransportConnector(connectors)
    }

    /// Mac side: the listener stack for a pairing. Parks in the relay room when
    /// a relay origin is configured (and advertises on the local network only
    /// if the LAN path is re-enabled). With one listener it is returned bare;
    /// with several, CombinedTransportListener yields whichever a phone reaches
    /// first.
    ///
    /// - onParked: forwarded to the relay listener (fires once the mac holds
    ///   the room's mac slot); nil when no relay is configured.
    ///
    /// - roomSecret: returns the persisted room secret once the pairing is
    ///   established, so the mac signs its park; nil keeps an empty (open-mode)
    ///   proof.
    public static func listener(pairingID: String,
                                responderStaticPublicKey: Data,
                                relayOrigin: String?,
                                session: URLSession = .shared,
                                onParked: (@Sendable () -> Void)? = nil,
                                roomSecret: (@Sendable () -> Data?)? = nil) throws -> TransportListener {
        var listeners: [TransportListener] = []
        if useLocalNetworkTransport {
            listeners.append(try BonjourTransportListener(pairingID: pairingID,
                                                          version: PairingCode.supportedVersion))
        }
        if let relayOrigin {
            let roomName = RelayRoom.name(responderStaticPublicKey: responderStaticPublicKey,
                                          pairingID: pairingID)
            let proof: (@Sendable (RelayAdmission.Challenge, String) throws -> RelayAdmission.Proof)? =
                roomSecret.map { secret in
                    { @Sendable challenge, room in
                        try signedProof(role: .mac, challenge: challenge, roomName: room,
                                        origin: relayOrigin, roomSecret: secret())
                    }
                }
            listeners.append(RelayTransportListener(relayOrigin: relayOrigin,
                                                    roomName: roomName,
                                                    session: session,
                                                    onParked: onParked,
                                                    joinProof: proof))
        }
        if listeners.count == 1 {
            return listeners[0]
        }
        return CombinedTransportListener(listeners)
    }
}

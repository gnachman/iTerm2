//
//  CompanionTransports.swift
//  CompanionCore
//
//  The single place that decides which transports a pairing uses. Both apps
//  build their connector (phone) and listener (mac) stacks here, so the rule
//  lives in one tested spot instead of being duplicated in the app layers.
//
//  The relay is the only transport: it reaches the mac regardless of network
//  topology (NAT, corporate wifi that blocks peer-to-peer discovery, off-LAN),
//  and reliability matters more than the latency a local-network path would
//  save.
//

import Foundation
import CryptoKit
import CompanionProtocol

public enum CompanionTransports {
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

    /// The admission proof for a phone, choosing the credential by room state:
    /// an established room (roomSecret present) signs the transcript; a fresh
    /// pairing under attestation presents its single-use App Attest ticket; an
    /// open-mode pairing presents nothing. A signature always wins, since an
    /// established room never needs a ticket.
    static func admissionProof(role: RelayJoin.Role,
                               challenge: RelayAdmission.Challenge,
                               roomName: String,
                               origin: String,
                               roomSecret: Data?,
                               pairingTicket: String?) throws -> RelayAdmission.Proof {
        let signed = try signedProof(role: role, challenge: challenge, roomName: roomName,
                                     origin: origin, roomSecret: roomSecret)
        if signed.signature != nil {
            return signed
        }
        return RelayAdmission.Proof(ticket: pairingTicket, signature: nil)
    }

    /// Phone side: the connector for a scanned (or stored) pairing code. Relay
    /// only; returns a connector that fails fast when the code carries no relay
    /// origin (there is no other transport).
    ///
    /// - roomSecret: returns the persisted room secret once the pairing is
    ///   established (the phone registered its verifier), so reconnects sign
    ///   their join. Returns nil during/before first pairing (open-mode join).
    /// - pairingTicket: the single-use App Attest admission ticket the phone
    ///   earned (RelayAttestationClient) for a fresh pairing under attestation;
    ///   nil for open mode or for reconnects (which sign with roomSecret).
    public static func connector(for code: PairingCode,
                                 webSocketFactory: RelayWebSocketFactory = URLSessionRelayWebSocketFactory(),
                                 roomSecret: (@Sendable () -> Data?)? = nil,
                                 pairingTicket: String? = nil,
                                 nonDisplacing: Bool = false) -> TransportConnector {
        guard let relayOrigin = code.relayOrigin else {
            return UnavailableTransportConnector()
        }
        let proof: (@Sendable (RelayAdmission.Challenge, String) throws -> RelayAdmission.Proof) =
            { @Sendable challenge, roomName in
                try admissionProof(role: .phone, challenge: challenge, roomName: roomName,
                                   origin: relayOrigin, roomSecret: roomSecret?(),
                                   pairingTicket: pairingTicket)
            }
        // nonDisplacing is set only by the NSE, so a background fetch yields to a
        // foreground app holding the phone slot rather than displacing it.
        return RelayTransportConnector(relayOrigin: relayOrigin,
                                       responderStaticKey: code.responderStaticPublicKey,
                                       joinProof: proof,
                                       nonDisplacing: nonDisplacing,
                                       webSocketFactory: webSocketFactory)
    }

    /// Mac side: the listener for a pairing. Parks in the relay room when a
    /// relay origin is configured; otherwise returns a listener that fails fast
    /// (there is no other transport).
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
                                webSocketFactory: RelayWebSocketFactory = URLSessionRelayWebSocketFactory(),
                                onParked: (@Sendable () -> Void)? = nil,
                                roomSecret: (@Sendable () -> Data?)? = nil) throws -> TransportListener {
        guard let relayOrigin else {
            return UnavailableTransportListener()
        }
        let roomName = RelayRoom.name(responderStaticPublicKey: responderStaticPublicKey,
                                      pairingID: pairingID)
        let proof: (@Sendable (RelayAdmission.Challenge, String) throws -> RelayAdmission.Proof)? =
            roomSecret.map { secret in
                { @Sendable challenge, room in
                    try signedProof(role: .mac, challenge: challenge, roomName: room,
                                    origin: relayOrigin, roomSecret: secret())
                }
            }
        return RelayTransportListener(relayOrigin: relayOrigin,
                                      roomName: roomName,
                                      webSocketFactory: webSocketFactory,
                                      onParked: onParked,
                                      joinProof: proof)
    }
}

/// Returned when a pairing has no usable transport (the code carries no relay
/// origin). Connecting or accepting fails fast instead of silently doing
/// nothing, preserving the old behavior of an empty transport set.
private struct UnavailableTransportConnector: TransportConnector {
    let transportName = "none"
    func connect(to rendezvous: PairingRendezvous,
                 timeout: TimeInterval) async throws -> MessageTransport {
        throw TransportError.connectionFailed("No transport configured (no relay origin)")
    }
}

private final class UnavailableTransportListener: TransportListener {
    let transportName = "none"
    func accept() async throws -> MessageTransport {
        throw TransportError.connectionFailed("No transport configured (no relay origin)")
    }
    func stop() {}
}

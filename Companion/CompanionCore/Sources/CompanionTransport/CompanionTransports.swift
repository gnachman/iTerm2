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
import CompanionProtocol

public enum CompanionTransports {
    /// Whether to also race the local-network (Bonjour) transport. Off for now;
    /// the relay is the sole transport so a pairing works the same on any
    /// network. Flip to true to restore Bonjour as a latency optimization.
    public static let useLocalNetworkTransport = false

    /// Phone side: the connector stack for a scanned (or stored) pairing code.
    /// Relay only (unless the LAN path is re-enabled); the relay connector is
    /// present only when the code carries a relay origin.
    public static func connector(for code: PairingCode,
                                 session: URLSession = .shared) -> TransportConnector {
        var connectors: [TransportConnector] = []
        if useLocalNetworkTransport {
            connectors.append(BonjourTransportConnector())
        }
        if let relayOrigin = code.relayOrigin {
            connectors.append(RelayTransportConnector(relayOrigin: relayOrigin,
                                                      responderStaticKey: code.responderStaticPublicKey,
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
    public static func listener(pairingID: String,
                                responderStaticPublicKey: Data,
                                relayOrigin: String?,
                                session: URLSession = .shared,
                                onParked: (@Sendable () -> Void)? = nil) throws -> TransportListener {
        var listeners: [TransportListener] = []
        if useLocalNetworkTransport {
            listeners.append(try BonjourTransportListener(pairingID: pairingID,
                                                          version: PairingCode.supportedVersion))
        }
        if let relayOrigin {
            let roomName = RelayRoom.name(responderStaticPublicKey: responderStaticPublicKey,
                                          pairingID: pairingID)
            listeners.append(RelayTransportListener(relayOrigin: relayOrigin,
                                                    roomName: roomName,
                                                    session: session,
                                                    onParked: onParked))
        }
        if listeners.count == 1 {
            return listeners[0]
        }
        return CombinedTransportListener(listeners)
    }
}

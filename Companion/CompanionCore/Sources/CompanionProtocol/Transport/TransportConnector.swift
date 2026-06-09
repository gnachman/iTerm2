//
//  TransportConnector.swift
//  CompanionCore
//
//  Connection-establishment abstraction. MessageTransport already hides how
//  bytes move once a connection exists; these protocols hide how a connection
//  is *established* for a given pairing, so the companion is not tied to any
//  single rendezvous mechanism. Bonjour/local-network is one conformance; an
//  external relay server, an iCloud/CloudKit shared database, or anything else
//  can be added as another conformance without touching the app or the bridge.
//
//  The pairing id is the only rendezvous token shared out of band (it is in the
//  QR code). Each transport interprets it however it needs: Bonjour matches it
//  in a TXT record, a relay uses it as a room key, iCloud uses it as a record
//  name, and so on.
//

import Foundation

/// What both peers know about a pairing, independent of transport.
public struct PairingRendezvous: Sendable, Equatable {
    public let pairingID: String
    public let version: Int

    public init(pairingID: String, version: Int = PairingCode.supportedVersion) {
        self.pairingID = pairingID
        self.version = version
    }
}

/// The initiator side (phone). Produces a connected, started MessageTransport
/// for a pairing, or throws if this transport cannot reach the peer.
public protocol TransportConnector: Sendable {
    /// Stable identifier for logging and telemetry (e.g. "bonjour", "relay").
    var transportName: String { get }

    func connect(to rendezvous: PairingRendezvous,
                 timeout: TimeInterval) async throws -> MessageTransport
}

/// The responder side (mac). Yields inbound connected MessageTransports for a
/// pairing. A transport may accept more than one over its lifetime.
public protocol TransportListener: AnyObject {
    var transportName: String { get }

    /// Begin accepting (idempotent) and return the next inbound transport.
    func accept() async throws -> MessageTransport

    /// Stop accepting and release resources. Idempotent.
    func stop()
}

/// Tries several connectors concurrently and uses whichever connects first,
/// cancelling the rest. This is how the phone can attempt local network, a
/// relay, and iCloud at once and take the fastest path.
public struct RaceTransportConnector: TransportConnector {
    public let connectors: [TransportConnector]
    public let transportName = "race"

    public init(_ connectors: [TransportConnector]) {
        self.connectors = connectors
    }

    public func connect(to rendezvous: PairingRendezvous,
                        timeout: TimeInterval) async throws -> MessageTransport {
        try await withThrowingTaskGroup(of: MessageTransport.self) { group in
            for connector in connectors {
                group.addTask {
                    try await connector.connect(to: rendezvous, timeout: timeout)
                }
            }
            // Keep the first success; cancel the rest, then drain so any loser
            // that had already connected gets closed instead of leaking its
            // open connection.
            var winner: MessageTransport?
            var lastError: Error?
            while true {
                do {
                    guard let transport = try await group.next() else { break }
                    if winner == nil {
                        winner = transport
                        group.cancelAll()
                    } else {
                        await transport.close()
                    }
                } catch {
                    if winner == nil { lastError = error }
                }
            }
            if let winner { return winner }
            throw lastError ?? TransportError.connectionFailed("No transports configured")
        }
    }
}

/// Accepts inbound connections from several listeners at once, returning the
/// first to arrive on any transport. Lets the mac advertise on local network, a
/// relay, and iCloud simultaneously.
public final class CombinedTransportListener: TransportListener {
    public let listeners: [TransportListener]
    public let transportName = "combined"

    public init(_ listeners: [TransportListener]) {
        self.listeners = listeners
    }

    public func accept() async throws -> MessageTransport {
        try await withThrowingTaskGroup(of: MessageTransport.self) { group in
            for listener in listeners {
                group.addTask {
                    try await listener.accept()
                }
            }
            // Take the first inbound connection; cancel the rest, then drain so
            // a connection that landed on another listener at the same instant
            // is closed rather than leaked.
            var winner: MessageTransport?
            var lastError: Error?
            while true {
                do {
                    guard let transport = try await group.next() else { break }
                    if winner == nil {
                        winner = transport
                        group.cancelAll()
                    } else {
                        await transport.close()
                    }
                } catch {
                    if winner == nil { lastError = error }
                }
            }
            if let winner { return winner }
            throw lastError ?? TransportError.connectionFailed("No listeners configured")
        }
    }

    public func stop() {
        for listener in listeners {
            listener.stop()
        }
    }
}

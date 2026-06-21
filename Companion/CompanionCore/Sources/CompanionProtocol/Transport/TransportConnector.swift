//
//  TransportConnector.swift
//  CompanionCore
//
//  Connection-establishment abstraction. MessageTransport already hides how
//  bytes move once a connection exists; these protocols hide how a connection
//  is *established* for a given pairing, so the companion is not tied to any
//  single rendezvous mechanism. The relay is the only conformance today; an
//  iCloud/CloudKit shared database, a direct local connection, or anything
//  else can be added as another conformance without touching the app or the
//  bridge.
//
//  The pairing id is the only rendezvous token shared out of band (it is in the
//  QR code). Each transport interprets it however it needs: the relay uses it
//  as a room key, an iCloud transport would use it as a record name, and so on.
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
    /// Stable identifier for logging and telemetry (e.g. "relay").
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

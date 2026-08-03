//
//  MessageTransport.swift
//  CompanionCore
//
//  The transport abstraction. The companion protocol is deliberately not tied
//  to a single channel: a transport may be the relay, an iCloud / CloudKit
//  rendezvous, or a remote server. A transport moves opaque, ordered, reliable
//  frames between the two paired peers and knows nothing about Noise or the
//  application protocol layered above it.
//
//  Layering:
//    MessageTransport   - opaque frames between peers (this file)
//    NoiseChannel       - encrypts/decrypts frames after the XK handshake
//    CompanionSession   - request/response + subscription RPC (Codable)
//

import Foundation

public protocol MessageTransport: AnyObject, Sendable {
    /// Send one frame to the peer. Frames are delivered in order and reliably;
    /// the transport is responsible for any length-prefixing on the wire.
    func send(_ frame: Data) async throws

    /// Await the next inbound frame. Throws `TransportError.closed` once the
    /// connection ends and no more frames will arrive.
    func receive() async throws -> Data

    /// Close the connection. Idempotent. After this, `receive()` throws and
    /// `send()` throws.
    func close() async
}

public enum TransportError: Error, Equatable, LocalizedError {
    /// The connection is closed; no more frames will be sent or received.
    case closed
    /// A frame exceeded the negotiated maximum size.
    case frameTooLarge(size: Int, maximum: Int)
    /// The peer sent a malformed frame.
    case malformedFrame
    /// The transport-specific connection attempt failed.
    case connectionFailed(String)
    /// The relay closed the room because it hit its daily data quota (WebSocket
    /// close 1008 with reason "daily quota exceeded"). Distinct from `.closed`
    /// because it is NOT transient churn: reconnecting immediately just trips the
    /// same limit, so the caller must back off long and tell the user, rather
    /// than spinning the routine fast-retry path.
    case quotaExceeded
    /// The host does not own this pairing's bucket (HTTP 421 / WS 4421, §6.9): the
    /// client's shard map is stale, so it must re-resolve and connect to the host
    /// the map now names, NOT retry this one. `ownerHint` is the relay's
    /// diagnostic-only naming of the current owner (logged, never dialed; the map
    /// is the sole authority).
    case reResolve(ownerHint: String?)
    /// A duplicate same-role connection took the room's single slot, so the relay
    /// evicted this one (WebSocket close 1000 with reason "displaced"). Same host
    /// (NOT a re-resolve, §6.9): reconnecting immediately just evicts the other
    /// instance, which re-grabs the slot and evicts us, an eviction storm. The
    /// caller must back off LONG before reclaiming, so the two instances settle.
    case displaced

    public var errorDescription: String? {
        switch self {
        case .closed:
            return "The connection was closed"
        case .frameTooLarge(let size, let maximum):
            return "Received a frame of \(size) bytes, larger than the limit of \(maximum)"
        case .malformedFrame:
            return "Received a malformed frame"
        case .connectionFailed(let reason):
            return reason
        case .quotaExceeded:
            return "The relay's daily data limit was reached"
        case .reResolve:
            return "This relay no longer serves the pairing; re-resolving to the current host"
        case .displaced:
            return "Another connection took over this pairing's slot"
        }
    }
}

/// Minimal logging hook for the transport and crypto layers, which cannot see
/// the apps' loggers (DLog on the Mac, os.Logger on the phone). Each app
/// installs a handler at startup; without one, logging is a no-op.
public enum CompanionLog {
    /// nonisolated(unsafe) by design: set once at startup before any traffic.
    nonisolated(unsafe) public static var handler: (@Sendable (String) -> Void)?

    public static func log(_ message: @autoclosure () -> String,
                           file: StaticString = #fileID,
                           line: UInt = #line,
                           function: StaticString = #function) {
        guard let handler else { return }
        let basename = "\(file)".split(separator: "/").last.map(String.init) ?? "\(file)"
        handler("\(basename):\(line) (\(function)): \(message())")
    }
}

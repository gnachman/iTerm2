//
//  RelayWebSocket.swift
//  CompanionCore
//
//  The minimal WebSocket the relay transport needs, behind a protocol so the
//  socket can be supplied by something other than URLSession, in particular, on
//  the Mac, a consent plugin that owns the only outbound path to the relay. The
//  default factory wraps URLSessionWebSocketTask and behaves exactly as before;
//  injecting a different factory swaps the egress without touching the admission,
//  Noise, or RPC layers above. See docs/companion-relay-design.md.
//

import Foundation
import CompanionProtocol

/// A WebSocket frame: text (the admission handshake) or binary (Noise frames).
public enum RelayWebSocketMessage: Sendable {
    case text(String)
    case data(Data)
}

/// The subset of URLSessionWebSocketTask the relay transport uses. Class-bound
/// so the listener can compare instances with `===` (its in-flight park).
public protocol RelayWebSocket: AnyObject, Sendable {
    func resume()
    func send(_ message: RelayWebSocketMessage) async throws
    func receive() async throws -> RelayWebSocketMessage
    /// Sends a keepalive ping; returns false once the socket is gone.
    func sendPing() async -> Bool
    func cancel()
}

/// Opens a RelayWebSocket to a URL with the given headers. `timeout` bounds the
/// initial connect (nil = the implementation's default).
public protocol RelayWebSocketFactory: Sendable {
    func makeWebSocket(url: URL, headers: [String: String], timeout: TimeInterval?) -> RelayWebSocket
}

/// The default, URLSession-backed implementation, identical to the original
/// inline behavior.
final class URLSessionRelayWebSocket: RelayWebSocket {
    private let task: URLSessionWebSocketTask

    init(_ task: URLSessionWebSocketTask) {
        self.task = task
    }

    func resume() { task.resume() }

    func send(_ message: RelayWebSocketMessage) async throws {
        switch message {
        case .text(let s): try await task.send(.string(s))
        case .data(let d): try await task.send(.data(d))
        }
    }

    func receive() async throws -> RelayWebSocketMessage {
        switch try await task.receive() {
        case .string(let s): return .text(s)
        case .data(let d): return .data(d)
        @unknown default: throw TransportError.malformedFrame
        }
    }

    func sendPing() async -> Bool { await task.sendPingAsync() }

    func cancel() { task.cancel(with: .goingAway, reason: nil) }
}

public struct URLSessionRelayWebSocketFactory: RelayWebSocketFactory {
    private let session: URLSession

    public init(session: URLSession = CompanionURLSession.shared) {
        self.session = session
    }

    public func makeWebSocket(url: URL, headers: [String: String], timeout: TimeInterval?) -> RelayWebSocket {
        var request = timeout.map { URLRequest(url: url, timeoutInterval: $0) } ?? URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // Fixed User-Agent so the default (app/build + OS version) never reaches
        // the relay.
        request.setValue(CompanionUserAgent.value, forHTTPHeaderField: "User-Agent")
        return URLSessionRelayWebSocket(session.webSocketTask(with: request))
    }
}

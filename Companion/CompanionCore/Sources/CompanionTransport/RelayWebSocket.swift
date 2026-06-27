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
        do {
            switch message {
            case .text(let s): try await task.send(.string(s))
            case .data(let d): try await task.send(.data(d))
            }
        } catch {
            logFailure("send", error)
            throw error
        }
    }

    func receive() async throws -> RelayWebSocketMessage {
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            logFailure("receive", error)
            throw error
        }
        switch message {
        case .string(let s): return .text(s)
        case .data(let d): return .data(d)
        @unknown default: throw TransportError.malformedFrame
        }
    }

    /// Log why the socket failed, including the WebSocket close code and reason the
    /// relay sent (if any) and the underlying URLError, so a park or session drop is
    /// diagnosable instead of surfacing as an opaque "closed". closeCode is .invalid
    /// (0) for an abrupt transport drop with no close frame.
    private func logFailure(_ op: String, _ error: Error) {
        let code = task.closeCode.rawValue
        let reason = task.closeReason
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { $0.isEmpty ? "-" : $0 } ?? "-"
        let ns = error as NSError
        CompanionLog.log("Relay WS \(op) failed: closeCode=\(code) reason=\(reason) "
            + "error=\(ns.domain)#\(ns.code) \(ns.localizedDescription)")
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

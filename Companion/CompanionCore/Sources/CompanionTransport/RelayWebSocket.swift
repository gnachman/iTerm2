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
            throw mapQuotaClose(error)
        }
    }

    func receive() async throws -> RelayWebSocketMessage {
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            logFailure("receive", error)
            throw mapQuotaClose(error)
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

    /// The relay closes the room with WebSocket 1008 + "daily quota exceeded" when
    /// it hits the daily byte quota. Surface that as a distinct, non-transient
    /// error so the reconnect logic backs off instead of hammering an exhausted
    /// quota. A bare 1008 is NOT enough to match: the relay also uses 1008 for the
    /// transient "frame rate exceeded" per-second limiter and for "bad hello", so
    /// key off the reason text. Any other close falls through to the original error.
    private func mapQuotaClose(_ fallback: Error) -> Error {
        guard task.closeCode.rawValue == 1008 else { return fallback }
        let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return reason.range(of: "daily quota", options: .caseInsensitive) != nil
            ? TransportError.quotaExceeded
            : fallback
    }

    func sendPing() async -> Bool { await task.sendPingAsync() }

    func cancel() {
        // cancel() closes with goingAway (WS close code 1001). Logging it
        // distinguishes a deliberate client-side teardown from an OS/network close
        // we did NOT initiate -- the latter surfaces as a receive failure with no
        // cancel() logged here (e.g. iOS closing the socket on app suspend).
        CompanionLog.log("Relay WS cancel() (goingAway/1001)")
        task.cancel(with: .goingAway, reason: nil)
    }
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

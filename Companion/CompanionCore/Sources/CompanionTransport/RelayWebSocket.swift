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
    private let lifecycle = RelaySocketLifecycle()

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
            lifecycle.noteData()
        } catch {
            logFailure("send", error)
            throw mapCloseSignal(error)
        }
    }

    func receive() async throws -> RelayWebSocketMessage {
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            logFailure("receive", error)
            throw mapCloseSignal(error)
        }
        lifecycle.noteData()
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
            + "error=\(ns.domain)#\(ns.code) \(ns.localizedDescription) \(lifecycle.summary())")
    }

    /// Map a socket failure to a distinct transport error per the re-resolution
    /// wire codes (§6.9), via the shared RelaySignal classifier: a WS 4421 /
    /// "reshard" close, or a 421-rejected upgrade, becomes `.reResolve`; a 1008
    /// "daily quota" close becomes `.quotaExceeded`; every other close keeps the
    /// original error. URLSessionWebSocketTask cannot surface an arbitrary 4xxx
    /// close code (it collapses to `.invalid`), so the `reshard` reason sentinel is
    /// the fallback the classifier matches on, the same belt-and-suspenders the
    /// quota close already relied on.
    private func mapCloseSignal(_ fallback: Error) -> Error {
        // Reject-on-doubt on the WS UPGRADE returns an HTTP status before any socket
        // opens (no close code); it surfaces here on task.response.
        if let http = task.response as? HTTPURLResponse, http.statusCode >= 400,
           let mapped = RelaySignal.forHTTPStatus(
                http.statusCode,
                ownerHint: http.value(forHTTPHeaderField: "x-relay-owner")).transportError() {
            return mapped
        }
        let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return RelaySignal.forWebSocketClose(code: task.closeCode.rawValue, reason: reason)
            .transportError() ?? fallback
    }

    func sendPing() async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        let ok = await task.sendPingAsync()
        if ok {
            lifecycle.notePingOk()
            let rttMs = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            CompanionLog.log("Relay WS ping ok rtt=\(rttMs)ms \(lifecycle.summary())")
        }
        return ok
    }

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

//
//  CompanionPluginTransport.swift
//  iTerm2
//
//  Adapts the companion consent plugin's generic WebSocket to CompanionCore's
//  RelayWebSocket seam, so the relay transport's admission/Noise/RPC layers run
//  unchanged while every byte of relay egress flows through the plugin (the
//  app's only outbound path for the feature). Injecting this factory in place of
//  the default URLSession one is what routes the Mac through the plugin.
//

import Foundation
import CompanionProtocol
import CompanionTransport

/// Thrown when the relay closes our socket because another mac-role connection
/// took the room's single mac slot (a "displaced" close). Distinct from
/// TransportError.closed so the park loop can recognize an eviction (a duplicate
/// instance in the same room) and back off long rather than re-grab the slot.
struct RelayDisplacedError: Error {}

/// One plugin-backed relay socket. The connection is opened lazily on resume()
/// (mirroring an un-resumed URLSessionWebSocketTask); send/receive await it.
final class PluginRelayWebSocket: RelayWebSocket, @unchecked Sendable {
    private let client: CompanionPluginClient
    private let url: URL
    private let headers: [String: String]
    private let lock = UnfairLock()
    private var openTask: Task<String, Error>?

    init(client: CompanionPluginClient, url: URL, headers: [String: String]) {
        self.client = client
        self.url = url
        self.headers = headers
    }

    func resume() {
        lock.withLock {
            guard openTask == nil else { return }
            let client = self.client
            let url = self.url
            let headers = self.headers
            openTask = Task { try await client.wsOpen(url: url.absoluteString, headers: headers) }
        }
    }

    private func connectionID() async throws -> String {
        guard let task = lock.withLock({ openTask }) else { throw TransportError.closed }
        return try await task.value
    }

    func send(_ message: RelayWebSocketMessage) async throws {
        let id = try await connectionID()
        switch message {
        case .text(let s): client.wsSend(id, isBinary: false, data: s)
        case .data(let d): client.wsSend(id, isBinary: true, data: d.base64EncodedString())
        }
    }

    func receive() async throws -> RelayWebSocketMessage {
        let id = try await connectionID()
        let incoming: CompanionPluginClient.Incoming
        do {
            incoming = try await client.wsRecv(id)
        } catch {
            // The plugin RPC itself failed (JS bridge gone, promise rejected): not a
            // clean WebSocket close, so there's no close code to report.
            let ns = error as NSError
            CompanionLog.log("Relay WS (plugin) recv error: \(ns.domain)#\(ns.code) \(ns.localizedDescription)")
            throw error
        }
        switch incoming {
        case .text(let s): return .text(s)
        case .data(let d): return .data(d)
        case .closed(let code, let reason):
            // The relay (or an edge proxy) closed the socket. Surface the close code
            // and reason so a short-lived park can be diagnosed: a clean relay close
            // (1000/1001 with a reason) vs an abnormal drop with no close frame
            // (1006, set by the plugin on a transport error).
            CompanionLog.log("Relay WS (plugin) closed: closeCode=\(code) reason=\(reason.isEmpty ? "-" : reason)")
            // "displaced": the relay handed the room's single mac slot to a newer
            // mac-role connection. Distinguish it from routine churn so the park loop
            // can back off long instead of immediately re-grabbing the slot (an
            // eviction storm between two instances in the same room).
            if reason.localizedCaseInsensitiveContains("displaced") {
                throw RelayDisplacedError()
            }
            throw TransportError.closed
        }
    }

    func sendPing() async -> Bool {
        guard let id = try? await connectionID() else { return false }
        return await client.wsPing(id)
    }

    func cancel() {
        let client = self.client
        Task { [weak self] in
            guard let id = try? await self?.connectionID() else { return }
            client.wsClose(id)
        }
    }
}

/// Hands out plugin-backed sockets, all sharing one plugin client (one
/// JSContext). Drop-in replacement for URLSessionRelayWebSocketFactory.
public struct PluginRelayWebSocketFactory: RelayWebSocketFactory {
    private let client: CompanionPluginClient

    init(client: CompanionPluginClient) {
        self.client = client
    }

    public func makeWebSocket(url: URL, headers: [String: String], timeout: TimeInterval?) -> RelayWebSocket {
        PluginRelayWebSocket(client: client, url: url, headers: headers)
    }
}

/// Routes CompanionCore's RelayHTTPClient through the plugin, so the Mac's one
/// HTTP call (the authenticated delete-room at unpair) takes the same consent
/// egress as its WebSocket traffic. The plugin collapses a non-2xx response into
/// an "HTTP <status>" error string; this recovers the status code so the caller
/// can tell an already-deleted room (403) from a transport failure.
struct PluginRelayHTTPClient: RelayHTTPClient {
    let client: CompanionPluginClient
    let origin: String

    func post(path: String, roomName: String, json body: [String: String]?) async throws -> (status: Int, body: Data) {
        var headers = ["x-relay-room": roomName]
        var bodyString = ""
        if let body {
            headers["Content-Type"] = "application/json"
            bodyString = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        }
        let response = try await client.request(
            method: "POST", url: origin + path, headers: headers, body: bodyString)
        let data = Data(response.data.utf8)
        if response.error.isEmpty {
            return (200, data)
        }
        if response.error.hasPrefix("HTTP "), let code = Int(response.error.dropFirst(5)) {
            return (code, data)
        }
        // A transport-level failure (no HTTP status): surface it so the caller's
        // best-effort wrapper can log and move on.
        throw RelayAttestationError.http(-1, response.error)
    }
}

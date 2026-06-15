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
        switch try await client.wsRecv(id) {
        case .text(let s): return .text(s)
        case .data(let d): return .data(d)
        case .closed: throw TransportError.closed
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

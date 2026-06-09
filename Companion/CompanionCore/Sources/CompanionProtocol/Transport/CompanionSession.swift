//
//  CompanionSession.swift
//  CompanionCore
//
//  Client-side (phone) RPC over any MessageTransport. After the Noise handshake
//  the transport handed in here is the encrypted NoiseChannel, so this layer
//  never sees plaintext on the wire. It assigns request IDs, correlates host
//  replies to the client message that triggered them, and routes unsolicited
//  host events (subscription deliveries, typing status) to a handler.
//

import Foundation

public actor CompanionSession {
    private let transport: MessageTransport
    private var nextRequestID: UInt64 = 1
    private var waiters: [UInt64: CheckedContinuation<CompanionHostMessage, Error>] = [:]
    private var receiveLoop: Task<Void, Never>?
    private var eventHandler: (@Sendable (CompanionHostMessage) -> Void)?
    private var closed = false

    public init(transport: MessageTransport) {
        self.transport = transport
    }

    /// Start the receive loop. `onEvent` is called for every unsolicited host
    /// message (one with no requestID): deliveries and typing-status updates.
    public func start(onEvent: @escaping @Sendable (CompanionHostMessage) -> Void) {
        guard receiveLoop == nil else { return }
        eventHandler = onEvent
        receiveLoop = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    /// Send a client message and await its correlated host reply.
    public func request(_ message: CompanionClientMessage) async throws -> CompanionHostMessage {
        let requestID = nextRequestID
        nextRequestID += 1
        let envelope = ClientEnvelope(requestID: requestID, payload: message)
        let data = try WireCoding.encode(envelope)
        return try await withCheckedThrowingContinuation { continuation in
            waiters[requestID] = continuation
            Task {
                do {
                    try await transport.send(data)
                } catch {
                    if let waiter = waiters.removeValue(forKey: requestID) {
                        waiter.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Send a client message without waiting for a reply (e.g. unsubscribe,
    /// fire-and-forget publish of a streaming delta).
    public func send(_ message: CompanionClientMessage) async throws {
        let envelope = ClientEnvelope(requestID: nil, payload: message)
        try await transport.send(try WireCoding.encode(envelope))
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        receiveLoop?.cancel()
        await transport.close()
        let pending = waiters
        waiters.removeAll()
        for (_, waiter) in pending {
            waiter.resume(throwing: TransportError.closed)
        }
    }

    private func runReceiveLoop() async {
        while !closed {
            let frame: Data
            do {
                frame = try await transport.receive()
            } catch {
                failAllWaiters(with: error)
                return
            }
            do {
                let envelope = try WireCoding.decode(HostEnvelope.self, from: frame)
                deliver(envelope)
            } catch {
                // A frame we cannot decode is dropped rather than fatal: a
                // newer mac may send a payload shape this build cannot parse.
                continue
            }
        }
    }

    private func deliver(_ envelope: HostEnvelope) {
        if let requestID = envelope.requestID,
           let waiter = waiters.removeValue(forKey: requestID) {
            waiter.resume(returning: envelope.payload)
            return
        }
        eventHandler?(envelope.payload)
    }

    private func failAllWaiters(with error: Error) {
        let pending = waiters
        waiters.removeAll()
        for (_, waiter) in pending {
            waiter.resume(throwing: error)
        }
    }
}

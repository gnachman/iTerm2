//
//  CompanionSession.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in sibling files.
//
//  Client-side (phone) RPC over any MessageTransport. After the Noise handshake
//  the transport handed in here is the encrypted NoiseChannel, so this layer
//  never sees plaintext on the wire. It assigns request IDs, correlates host
//  replies to the client message that triggered them, and routes unsolicited
//  host events (subscription deliveries, typing status) to a handler.
//

import Foundation
import CompanionProtocol

actor CompanionSession {
    private let transport: MessageTransport
    private var nextRequestID: UInt64 = 1
    private var waiters: [UInt64: CheckedContinuation<CompanionHostMessage, Error>] = [:]
    private var receiveLoop: Task<Void, Never>?
    private var eventHandler: (@Sendable (CompanionHostMessage) -> Void)?
    private var mediaHandler: (@Sendable (CompanionMediaFrame) -> Void)?
    private var closedHandler: (@Sendable () -> Void)?
    private var closed = false

    init(transport: MessageTransport) {
        self.transport = transport
    }

    /// Start the receive loop. `onEvent` is called for every unsolicited host
    /// message (one with no requestID); `onClose` fires once if the connection
    /// dies remotely (a locally requested close() does not fire it).
    func start(onEvent: @escaping @Sendable (CompanionHostMessage) -> Void,
               onClose: @escaping @Sendable () -> Void,
               onMedia: (@Sendable (CompanionMediaFrame) -> Void)? = nil) {
        guard receiveLoop == nil else { return }
        eventHandler = onEvent
        mediaHandler = onMedia
        closedHandler = onClose
        receiveLoop = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    /// Send a client message and await its correlated host reply. Honors task
    /// cancellation (e.g. a caller-imposed deadline) by abandoning the waiter.
    func request(_ message: CompanionClientMessage) async throws -> CompanionHostMessage {
        let requestID = nextRequestID
        nextRequestID += 1
        let envelope = ClientEnvelope(requestID: requestID, payload: message)
        let data = try WireCoding.encode(envelope)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
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
        } onCancel: {
            Task { await self.cancelWaiter(requestID) }
        }
    }

    private func cancelWaiter(_ requestID: UInt64) {
        if let waiter = waiters.removeValue(forKey: requestID) {
            waiter.resume(throwing: CancellationError())
        }
    }

    /// Send a client message without waiting for a reply (e.g. unsubscribe,
    /// fire-and-forget publish of a streaming delta).
    func send(_ message: CompanionClientMessage) async throws {
        let envelope = ClientEnvelope(requestID: nil, payload: message)
        try await transport.send(try WireCoding.encode(envelope))
    }

    func close() async {
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
                if !closed {
                    CompanionLog.log("CompanionSession: connection lost (\(error))")
                    closedHandler?()
                }
                return
            }
            switch CompanionFrameChannel.classify(frame) {
            case .media(let payload):
                do {
                    mediaHandler?(try CompanionMediaFrame(decoding: payload))
                } catch {
                    CompanionLog.log("CompanionSession: DROPPING undecodable media frame (\(payload.count) bytes): \(error)")
                }
            case .control(let bytes):
                do {
                    let envelope = try WireCoding.decode(HostEnvelope.self, from: bytes)
                    deliver(envelope)
                } catch {
                    CompanionLog.log("CompanionSession: DROPPING undecodable frame (\(bytes.count) bytes): \(error)")
                }
            case .none:
                CompanionLog.log("CompanionSession: DROPPING empty frame")
            }
        }
    }

    private func deliver(_ envelope: HostEnvelope) {
        if let requestID = envelope.requestID,
           let waiter = waiters.removeValue(forKey: requestID) {
            waiter.resume(returning: envelope.payload)
            return
        }
        CompanionLog.log("CompanionSession: unsolicited event \(shortName(of: envelope.payload))")
        eventHandler?(envelope.payload)
    }

    private func shortName(of message: CompanionHostMessage) -> String {
        switch message {
        case .unsupported: "unsupported"
        case .hello: "hello"
        case .chatsAndSessions: "chatsAndSessions"
        case .chatCreated: "chatCreated"
        case .history: "history"
        case .delivery: "delivery"
        case .typingStatus: "typingStatus"
        case .mentionsResolved: "mentionsResolved"
        case .sessionScreenInfo: "sessionScreenInfo"
        case .sessionContent: "sessionContent"
        case .workgroupInfo: "workgroupInfo"
        case .sessionTree: "sessionTree"
        case .chatListChanged: "chatListChanged"
        case .requestNotificationPermission: "requestNotificationPermission"
        case .pong: "pong"
        case .relayRoomSecretStored: "relayRoomSecretStored"
        case .messagesSince: "messagesSince"
        case .syncSince: "syncSince"
        case .unpaired: "unpaired"
        case .error: "error"
        case .streamStarted: "streamStarted"
        case .streamConfig: "streamConfig"
        case .streamEnded: "streamEnded"
        }
    }

    private func failAllWaiters(with error: Error) {
        let pending = waiters
        waiters.removeAll()
        for (_, waiter) in pending {
            waiter.resume(throwing: error)
        }
    }
}

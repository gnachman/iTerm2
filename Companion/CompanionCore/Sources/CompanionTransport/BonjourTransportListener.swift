//
//  BonjourTransportListener.swift
//  CompanionCore
//
//  Local-network conformance of TransportListener (mac side): advertise the
//  companion service with the pairing id in its TXT record and hand back each
//  inbound connection as a started NWMessageTransport for the Noise handshake.
//  This is one transport among potentially many; see TransportListener.
//

import Foundation
import Network
import CompanionProtocol

public final class BonjourTransportListener: TransportListener, @unchecked Sendable {
    public let transportName = "bonjour"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.googlecode.iterm2.companion.listen")
    private let lock = UnfairLock()
    private var pending = [NWConnection]()
    // FIFO of parked accept() callers, keyed by id so a cancelled accept() can
    // remove exactly its own continuation. A single optional slot would orphan
    // earlier waiters when accept() is pipelined.
    private var waiters: [(id: Int, continuation: CheckedContinuation<NWConnection, Error>)] = []
    // ids whose accept() was cancelled before its continuation registered.
    private var cancelledBeforeRegister = Set<Int>()
    private var nextWaiterID = 0
    private var failure: Error?

    public init(pairingID: String, version: Int) throws {
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters)
        var txt = NWTXTRecord()
        txt[CompanionBonjour.pairingIDKey] = pairingID
        txt[CompanionBonjour.versionKey] = String(version)
        listener.service = NWListener.Service(
            type: CompanionBonjour.serviceType, txtRecord: txt)
        self.listener = listener
    }

    /// Start advertising and accept the next inbound connection, returned as a
    /// started transport. Repeated calls accept subsequent connections.
    public func accept() async throws -> MessageTransport {
        listener.newConnectionHandler = { [weak self] connection in
            self?.enqueue(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.fail(with: error)
            }
        }
        listener.start(queue: queue)

        let connection = try await nextConnection()
        let transport = NWMessageTransport(connection: connection)
        try await transport.start()
        return transport
    }

    public func stop() {
        listener.cancel()
        fail(with: TransportError.closed)
    }

    private func nextConnection() async throws -> NWConnection {
        let id = lock.withLock { () -> Int in
            let value = nextWaiterID
            nextWaiterID += 1
            return value
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enum Outcome {
                    case connection(NWConnection)
                    case failure(Error)
                    case parked
                }
                let outcome: Outcome = lock.withLock {
                    if cancelledBeforeRegister.remove(id) != nil {
                        return .failure(CancellationError())
                    }
                    if !pending.isEmpty {
                        return .connection(pending.removeFirst())
                    }
                    if let failure {
                        return .failure(failure)
                    }
                    waiters.append((id, continuation))
                    return .parked
                }
                switch outcome {
                case .connection(let connection): continuation.resume(returning: connection)
                case .failure(let error): continuation.resume(throwing: error)
                case .parked: break
                }
            }
        } onCancel: {
            cancelWaiter(id: id)
        }
    }

    private func enqueue(_ connection: NWConnection) {
        let waiter = lock.withLock { () -> CheckedContinuation<NWConnection, Error>? in
            if waiters.isEmpty {
                pending.append(connection)
                return nil
            }
            return waiters.removeFirst().continuation
        }
        waiter?.resume(returning: connection)
    }

    private func fail(with error: Error) {
        let parked = lock.withLock { () -> [CheckedContinuation<NWConnection, Error>] in
            if failure == nil {
                failure = error
            }
            let continuations = waiters.map(\.continuation)
            waiters.removeAll()
            return continuations
        }
        for waiter in parked {
            waiter.resume(throwing: error)
        }
    }

    private func cancelWaiter(id: Int) {
        let waiter = lock.withLock { () -> CheckedContinuation<NWConnection, Error>? in
            if let index = waiters.firstIndex(where: { $0.id == id }) {
                let continuation = waiters[index].continuation
                waiters.remove(at: index)
                return continuation
            }
            // onCancel fired before the continuation registered; record it so
            // nextConnection resumes with CancellationError when it runs.
            cancelledBeforeRegister.insert(id)
            return nil
        }
        waiter?.resume(throwing: CancellationError())
    }
}

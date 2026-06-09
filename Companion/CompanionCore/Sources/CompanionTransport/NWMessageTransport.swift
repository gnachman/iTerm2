//
//  NWMessageTransport.swift
//  CompanionCore
//
//  A MessageTransport backed by a Network.framework NWConnection. It rides a
//  raw TCP byte stream and applies the package's 4-byte length-prefix framing
//  so the higher layers (Noise, then RPC) see discrete frames. Network.framework
//  is available on both iOS and macOS, so this same transport serves the phone
//  (the connecting side) and the mac (the accepting side).
//

import Foundation
import Network
import CompanionProtocol

public final class NWMessageTransport: MessageTransport, @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let lock = UnfairLock()

    // Inbound frames decoded by the framer, plus any receive() callers waiting
    // for one. Guarded by `lock`.
    private var framer = LengthPrefixedFramer()
    private var inbox = [Data]()
    private var waiters = [CheckedContinuation<Data, Error>]()
    private var failure: Error?
    private var started = false

    public init(connection: NWConnection,
                queue: DispatchQueue = DispatchQueue(label: "com.googlecode.iterm2.companion.nw")) {
        self.connection = connection
        self.queue = queue
    }

    deinit {
        // Backstop against leaking the open NWConnection if a transport is
        // dropped without close() (e.g. a race loser). cancel() is idempotent.
        connection.cancel()
    }

    /// Bring the connection up and begin reading. Resolves once the connection
    /// is ready, or throws if it fails before becoming ready.
    public func start() async throws {
        let alreadyStarted = lock.withLock { () -> Bool in
            if started { return true }
            started = true
            return false
        }
        if alreadyStarted {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = ResumeOnce(continuation)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    resumed.succeed()
                    self?.receiveLoop()
                case .failed(let error):
                    resumed.fail(error)
                    self?.fail(with: error)
                case .cancelled:
                    let error = TransportError.closed
                    resumed.fail(error)
                    self?.fail(with: error)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func send(_ frame: Data) async throws {
        let wire = LengthPrefixedFramer.encode(frame)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: wire, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if !inbox.isEmpty {
                    continuation.resume(returning: inbox.removeFirst())
                } else if let failure {
                    continuation.resume(throwing: failure)
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    public func close() async {
        connection.cancel()
        fail(with: TransportError.closed)
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.ingest(data)
            }
            if let error {
                self.fail(with: error)
                return
            }
            if isComplete {
                self.fail(with: TransportError.closed)
                return
            }
            self.receiveLoop()
        }
    }

    private func ingest(_ data: Data) {
        let result = lock.withLock { () -> Result<Void, Error> in
            do {
                for frame in try framer.push(data) {
                    if waiters.isEmpty {
                        inbox.append(frame)
                    } else {
                        waiters.removeFirst().resume(returning: frame)
                    }
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        if case .failure(let error) = result {
            fail(with: error)
        }
    }

    private func fail(with error: Error) {
        let pending = lock.withLock { () -> [CheckedContinuation<Data, Error>] in
            if failure == nil {
                failure = error
            }
            let waiting = waiters
            waiters.removeAll()
            return waiting
        }
        for waiter in pending {
            waiter.resume(throwing: error)
        }
    }
}

/// Guards a continuation so it is resumed exactly once even though the NWConnection
/// state handler can fire .ready and later .failed/.cancelled.
private final class ResumeOnce: @unchecked Sendable {
    private let continuation: CheckedContinuation<Void, Error>
    private let lock = NSLock()
    private var done = false

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func succeed() {
        guard claim() else { return }
        continuation.resume()
    }

    func fail(_ error: Error) {
        guard claim() else { return }
        continuation.resume(throwing: error)
    }

    private func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

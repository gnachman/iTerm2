//
//  CompanionLoopbackTransport.swift
//  iTerm2 ModernTests
//
//  An in-memory MessageTransport pair: what one end sends, the other receives.
//  Frames queued before a close are still delivered; after that receive()
//  throws TransportError.closed. Closing either end closes both. fail(with:)
//  closes with a specific error, to stand in for a relay teardown such as the
//  daily quota.
//

import Foundation
import CompanionProtocol
import os

final class CompanionLoopbackTransport: MessageTransport {
    private struct State: Sendable {
        // Indexed by the end that RECEIVES from the queue.
        var queues: [[Data]] = [[], []]
        var waiters: [[CheckedContinuation<Data, Error>]] = [[], []]
        var closed = false
        var closeError = TransportError.closed
    }

    private enum ReceiveAction: Sendable {
        case deliver(Data)
        case fail(TransportError)
        case wait
    }

    private let state: OSAllocatedUnfairLock<State>
    private let receiveIndex: Int
    private var sendIndex: Int { 1 - receiveIndex }

    private init(state: OSAllocatedUnfairLock<State>, receiveIndex: Int) {
        self.state = state
        self.receiveIndex = receiveIndex
    }

    static func makePair() -> (CompanionLoopbackTransport, CompanionLoopbackTransport) {
        let state = OSAllocatedUnfairLock(initialState: State())
        return (CompanionLoopbackTransport(state: state, receiveIndex: 0),
                CompanionLoopbackTransport(state: state, receiveIndex: 1))
    }

    func send(_ frame: Data) async throws {
        let index = sendIndex
        let waiter = try state.withLock { state -> CheckedContinuation<Data, Error>? in
            if state.closed {
                throw state.closeError
            }
            if !state.waiters[index].isEmpty {
                return state.waiters[index].removeFirst()
            }
            state.queues[index].append(frame)
            return nil
        }
        waiter?.resume(returning: frame)
    }

    func receive() async throws -> Data {
        let index = receiveIndex
        return try await withCheckedThrowingContinuation { continuation in
            let action = state.withLock { state -> ReceiveAction in
                if !state.queues[index].isEmpty {
                    return .deliver(state.queues[index].removeFirst())
                }
                if state.closed {
                    return .fail(state.closeError)
                }
                state.waiters[index].append(continuation)
                return .wait
            }
            switch action {
            case .deliver(let frame):
                continuation.resume(returning: frame)
            case .fail(let error):
                continuation.resume(throwing: error)
            case .wait:
                break
            }
        }
    }

    func close() async {
        fail(with: .closed)
    }

    /// Close both ends so that receive() and send() throw `error`. The first
    /// close wins.
    func fail(with error: TransportError) {
        let waiters = state.withLock { state -> [CheckedContinuation<Data, Error>] in
            if !state.closed {
                state.closed = true
                state.closeError = error
            }
            let all = state.waiters.flatMap { $0 }
            state.waiters = [[], []]
            return all
        }
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }
}

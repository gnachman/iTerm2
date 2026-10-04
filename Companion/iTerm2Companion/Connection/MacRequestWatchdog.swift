//
//  MacRequestWatchdog.swift
//  iTerm2Companion
//
//  Request timeouts that know when the Mac cannot answer.
//
//  A modal alert on the Mac can stop its main thread from serving requests
//  until someone dismisses it. The connection stays up through that, and the
//  Mac says so (CompanionMacStatus). A request sent meanwhile is not lost: the
//  Mac answers it when the alert goes away. Timing it out after the usual few
//  seconds would tear down a healthy connection and loop reconnecting for as
//  long as the alert was up.
//
//  So while the Mac reports itself blocked, the deadline is held. It starts
//  over, at full length, each time the Mac unblocks, because the Mac then has a
//  backlog to work through. MacLivenessProbe covers the other half: with
//  deadlines held, something still has to notice a connection that really died.
//

import Foundation
import os
import CompanionProtocol

final class MacRequestWatchdog: Sendable {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    private struct State: Sendable {
        var blocked = false
        /// Bumped on every change of `blocked`, so a deadline can tell whether a
        /// block interrupted it even if the block has already ended.
        var generation = 0
        var nextWaiterID = 0
        var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let sleep: Sleep

    /// - sleep: waits this many seconds, throwing if the task is cancelled.
    ///   Injected for tests.
    init(sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.sleep = sleep
    }

    var isBlocked: Bool {
        return state.withLock { $0.blocked }
    }

    /// The Mac started or stopped reporting that it cannot serve requests.
    func setBlocked(_ blocked: Bool) {
        let toResume = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            guard state.blocked != blocked else {
                return []
            }
            state.blocked = blocked
            state.generation += 1
            guard !blocked else {
                return []
            }
            let waiters = Array(state.waiters.values)
            state.waiters = [:]
            return waiters
        }
        for continuation in toResume {
            continuation.resume()
        }
    }

    /// Run `body` with a deadline. Throws a timeout error naming `label` if the
    /// Mac had `timeout` seconds, uninterrupted and not blocked, to answer and
    /// did not. Time during which the Mac is blocked does not count, and each
    /// time it unblocks the full `timeout` starts over.
    func run<T: Sendable>(timeout: TimeInterval,
                          label: String,
                          _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                while true {
                    try await self.waitUntilUnblocked()
                    let generation = self.state.withLock { $0.generation }
                    try await self.sleep(timeout)
                    // The deadline counts only if the Mac was free to answer for
                    // all of it. If a block began during it, even one that has
                    // already ended, the Mac has a backlog: start over.
                    let expired = self.state.withLock { !$0.blocked && $0.generation == generation }
                    if expired {
                        throw TransportError.connectionFailed("\(label) timed out after \(Int(timeout)) seconds")
                    }
                }
            }
            guard let result = try await group.next() else {
                throw TransportError.closed
            }
            group.cancelAll()
            return result
        }
    }

    /// Returns at once if the Mac is not blocked; otherwise suspends until it
    /// unblocks. Throws if the task is cancelled first.
    private func waitUntilUnblocked() async throws {
        let id = state.withLock { state -> Int in
            state.nextWaiterID += 1
            return state.nextWaiterID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = state.withLock { state -> Bool in
                    if !state.blocked || Task.isCancelled {
                        return true
                    }
                    state.waiters[id] = continuation
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        } onCancel: {
            let continuation = state.withLock { $0.waiters.removeValue(forKey: id) }
            continuation?.resume()
        }
        try Task.checkCancellation()
    }
}

/// While active, pings the Mac at an interval and reports when a ping fails.
///
/// The Mac answers pings without its main thread, so a ping that goes
/// unanswered means the connection is really gone, even while every other
/// request is being held for a blocked Mac.
final class MacLivenessProbe: Sendable {
    private struct State: Sendable {
        var task: Task<Void, Never>?
        /// Identifies the running loop, so one that is ending cannot clear the
        /// record of its replacement.
        var generation = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let interval: TimeInterval
    private let sleep: MacRequestWatchdog.Sleep
    private let ping: @Sendable () async -> Bool
    private let onDead: @Sendable () async -> Void

    /// - ping: one ping with its own short, strict timeout. Returns false if it
    ///   failed.
    /// - onDead: called once, when a ping fails. The probe then goes inactive.
    init(interval: TimeInterval = 10,
         sleep: @escaping MacRequestWatchdog.Sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         ping: @escaping @Sendable () async -> Bool,
         onDead: @escaping @Sendable () async -> Void) {
        self.interval = interval
        self.sleep = sleep
        self.ping = ping
        self.onDead = onDead
    }

    /// Start or stop probing. Idempotent.
    func setActive(_ active: Bool) {
        let toCancel = state.withLock { state -> Task<Void, Never>? in
            if active {
                guard state.task == nil else {
                    return nil
                }
                state.generation += 1
                let generation = state.generation
                state.task = Task.detached { [weak self] in
                    await self?.run(generation: generation)
                }
                return nil
            }
            let task = state.task
            state.task = nil
            return task
        }
        toCancel?.cancel()
    }

    private func run(generation: Int) async {
        while !Task.isCancelled {
            do {
                try await sleep(interval)
            } catch {
                return
            }
            if Task.isCancelled {
                return
            }
            if await ping() {
                continue
            }
            let stillCurrent = state.withLock { state -> Bool in
                guard state.generation == generation, state.task != nil else {
                    return false
                }
                state.task = nil
                return true
            }
            if stillCurrent {
                await onDead()
            }
            return
        }
    }
}

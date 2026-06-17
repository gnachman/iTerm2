//
//  RelayKeepalive.swift
//  CompanionCore
//
//  A relay WebSocket carries no traffic while it sits idle: a mac parked in its
//  room waiting for a phone to scan, or an established session between messages.
//  Edge infrastructure reaps such idle sockets (observed ~30s), which silently
//  drops a parked mac so the phone then finds "mac offline". This sends a
//  periodic WebSocket ping to keep the connection from being reaped.
//
//  The ping closure returns false when the socket is gone; the loop then ends
//  and the normal receive()/accept() path surfaces the failure so the caller
//  can retry. The ping is injected so the loop is testable without a socket.
//

import Foundation
import CompanionProtocol

final class RelayKeepalive: @unchecked Sendable {
    private let intervalNanos: UInt64
    private let ping: @Sendable () async -> Bool
    private let lock = UnfairLock()
    private var task: Task<Void, Never>?
    private var stopped = false

    /// - intervalNanos: delay between pings. Comfortably under the observed
    ///   idle-reap window so a ping always lands first.
    /// - ping: sends one keepalive; returns false when the socket is gone, which
    ///   ends the loop (the transport's own error path takes over from there).
    init(intervalNanos: UInt64, ping: @escaping @Sendable () async -> Bool) {
        self.intervalNanos = intervalNanos
        self.ping = ping
    }

    func start() {
        let go = lock.withLock { () -> Bool in
            guard !stopped, task == nil else { return false }
            return true
        }
        guard go else { return }
        let t = Task { [intervalNanos, ping] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                if Task.isCancelled { break }
                if await ping() == false { break }
            }
        }
        lock.withLock {
            if stopped {
                // stop() raced in before we stored the task; honor it.
                t.cancel()
            } else {
                task = t
            }
        }
    }

    func stop() {
        let t = lock.withLock { () -> Task<Void, Never>? in
            stopped = true
            let t = task
            task = nil
            return t
        }
        t?.cancel()
    }
}

extension URLSessionWebSocketTask {
    /// Send one WebSocket ping; resolves true when the pong returns, false on any
    /// error (a closed or broken socket).
    func sendPingAsync() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.sendPing { error in cont.resume(returning: error == nil) }
        }
    }
}

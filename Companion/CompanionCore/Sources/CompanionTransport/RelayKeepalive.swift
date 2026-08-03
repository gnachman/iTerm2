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
    private var onDeath: (@Sendable () -> Void)?

    /// Invoked once if the ping fails (the socket died), as opposed to a deliberate
    /// stop(). Lets the owner tear down and recover even when the in-flight
    /// receive() does not unblock on cancel (observed under a hard network drop).
    /// Settable after creation so the transport can wire it to its own close once
    /// it has adopted the keepalive.
    func setOnDeath(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { onDeath = handler }
    }

    private func fireDeath() {
        let handler = lock.withLock { () -> (@Sendable () -> Void)? in
            stopped ? nil : onDeath
        }
        handler?()
    }

    /// - intervalNanos: delay between pings. Comfortably under the observed
    ///   idle-reap window so a ping always lands first.
    /// The smallest interval the loop will use. Task.sleep(0) returns instantly,
    /// so a 0 interval paired with an always-succeeding ping would busy-spin the
    /// CPU; clamp to a tiny but nonzero floor so the loop always yields.
    private static let minimumIntervalNanos: UInt64 = 1_000_000   // 1 ms

    /// - ping: sends one keepalive; returns false when the socket is gone, which
    ///   ends the loop (the transport's own error path takes over from there).
    init(intervalNanos: UInt64, ping: @escaping @Sendable () async -> Bool) {
        self.intervalNanos = max(intervalNanos, Self.minimumIntervalNanos)
        self.ping = ping
    }

    func start() {
        let go = lock.withLock { () -> Bool in
            guard !stopped, task == nil else { return false }
            return true
        }
        guard go else { return }
        let t = Task { [weak self, intervalNanos, ping] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                if Task.isCancelled { break }
                if await ping() == false {
                    // The socket is gone (not a deliberate stop): notify the owner
                    // so it can hard-close and recover.
                    self?.fireDeath()
                    break
                }
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
    ///
    /// URLSession may invoke the pong handler MORE THAN ONCE - notably when the
    /// task is cancelled while a ping is in flight (a pong/error callback plus a
    /// cancellation callback). Resuming a CheckedContinuation twice is fatal, so a
    /// one-shot guard ensures exactly one resume.
    func sendPingAsync() async -> Bool {
        let once = PingResumeOnce()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.sendPing { error in
                if once.claim() { cont.resume(returning: error == nil) }
            }
        }
    }
}

/// One-shot guard: the first claim() wins, later ones are no-ops, so a
/// multiply-invoked completion handler resumes its continuation only once.
private final class PingResumeOnce: @unchecked Sendable {
    private let lock = UnfairLock()
    private var fired = false
    func claim() -> Bool {
        lock.withLock {
            if fired { return false }
            fired = true
            return true
        }
    }
}

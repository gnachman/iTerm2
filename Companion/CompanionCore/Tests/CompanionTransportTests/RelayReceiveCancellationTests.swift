//
//  RelayReceiveCancellationTests.swift
//  CompanionCore
//
//  Regression for the "paired, socket healthy, but the handshake never completes"
//  wedge seen on a phone restart (2026-09-05). The phone reconnected, the relay
//  was reachable (keepalive pinged OK every 15s), but the Noise handshake reply
//  never arrived because the mac's bridge had died and re-parked. AppModel wraps
//  the reconnect handshake in withTimeout(reconnectHandshakeTimeout), whose timeout
//  leg CANCELS the task running NoiseHandshake.perform -> transport.receive(). For
//  that timeout to actually fire, receive() must observe task cancellation.
//
//  Before the fix it did not: receive() parked on a bare continuation whose only
//  wakeups were an explicit close() or a keepalive DEATH. With the ping healthy and
//  the task merely cancelled, nothing unblocked it, so the handshake (and the whole
//  reconnect loop) hung until the user force-quit the app.
//

import XCTest
import CompanionProtocol
@testable import CompanionTransport

/// A healthy relay socket: pings always succeed (the relay is reachable), and an
/// in-flight receive() blocks until an explicit cancel() - exactly like a real
/// URLSessionWebSocketTask, which ignores Swift task cancellation but throws when
/// the task is cancel()ed. Models the field wedge where the socket is fine but the
/// peer's frame never comes.
private final class HealthyBlockingWebSocket: RelayWebSocket, @unchecked Sendable {
    private let lock = UnfairLock()
    private var waiter: CheckedContinuation<RelayWebSocketMessage, Error>?
    private var cancelled = false

    func resume() {}
    func send(_ message: RelayWebSocketMessage) async throws {}

    func receive() async throws -> RelayWebSocketMessage {
        // Park until cancel() resolves us. The already-cancelled check closes the
        // race where cancel() lands before receive() is even called.
        try await withCheckedThrowingContinuation { cont in
            let resumeNow = lock.withLock { () -> Bool in
                if cancelled { return true }
                waiter = cont
                return false
            }
            if resumeNow { cont.resume(throwing: TransportError.closed) }
        }
    }

    func sendPing() async -> Bool { true }   // healthy: the relay is reachable

    func cancel() {
        let w = lock.withLock { () -> CheckedContinuation<RelayWebSocketMessage, Error>? in
            cancelled = true
            let w = waiter; waiter = nil; return w
        }
        w?.resume(throwing: TransportError.closed)
    }

    /// Test cleanup: unblock a still-parked receive so the buggy (hung) path does
    /// not leak a continuation. A no-op once cancel() has already fired.
    func releaseForTeardown() { cancel() }
}

final class RelayReceiveCancellationTests: XCTestCase {
    /// Await `work`, giving up after `nanos`. Returns the work's value if it
    /// finished in time, or nil if the deadline won (i.e. work hung). Keeps a
    /// regression failing loudly instead of hanging the whole suite.
    private func awaitWithin<T: Sendable>(_ nanos: UInt64,
                                          _ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { Optional(await work()) }
            group.addTask { try? await Task.sleep(nanoseconds: nanos); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func test_receive_honorsTaskCancellation_evenWhenSocketIgnoresItAndKeepaliveIsHealthy() async {
        let ws = HealthyBlockingWebSocket()
        // A live, healthy keepalive: pings succeed, so its death path never fires
        // and cannot be what rescues the stalled receive. The long interval keeps
        // it from pinging during the test at all; the point is only that it is NOT
        // dead. This mirrors the field: "Relay WS ping ok" the whole time.
        let keepalive = RelayKeepalive(intervalNanos: 30_000_000_000, ping: { await ws.sendPing() })
        let transport = RelayTransport(ws: ws, keepalive: keepalive)
        keepalive.start()

        // A task blocked in receive() (as NoiseHandshake.perform is), then cancelled
        // (as withTimeout's timeout leg cancels it). Returns true iff receive() threw.
        let receiver = Task { () -> Bool in
            do { _ = try await transport.receive(); return false }  // returned a frame: unexpected
            catch { return true }                                   // threw: cancellation observed
        }
        // Let receive() park on the socket read before cancelling.
        try? await Task.sleep(nanoseconds: 100_000_000)
        receiver.cancel()

        let outcome = await awaitWithin(2_000_000_000) { await receiver.value }

        // Release the parked socket read so nothing leaks (required while the bug
        // leaves receive() hung; harmless once the fix routes cancel through it).
        ws.releaseForTeardown()

        XCTAssertEqual(outcome, true,
            "receive() must throw when its awaiting task is cancelled; instead it ignored "
            + "cancellation and hung despite a healthy keepalive - the reconnect-handshake "
            + "timeout can never fire, which is the 'paired but never reconnects' wedge")
    }
}

//
//  RelayKeepaliveTeardownTests.swift
//  CompanionCore
//
//  Regression for the "paired but never reconnects" hang: the mac's accept()
//  parks on ws.receive() with no timeout, and the keepalive is the only thing
//  that can notice a half-open socket (sleep/wake, Wi-Fi change, edge reaping
//  without a close frame). The keepalive must therefore CANCEL the socket when a
//  ping fails, so the parked receive() throws and the error-driven retry path
//  engages. Before the fix the loop merely stopped pinging and accept() blocked
//  forever.
//

import XCTest
import CompanionProtocol
@testable import CompanionTransport

/// A RelayWebSocket that admits successfully, then parks on receive() until
/// cancel() is called - at which point the pending receive() throws, exactly as
/// a real URLSessionWebSocketTask does on cancel(). Its ping always fails, so it
/// models a socket that has gone half-open while parked.
private final class HalfOpenWebSocket: RelayWebSocket, @unchecked Sendable {
    private let lock = UnfairLock()
    private var scripted: [RelayWebSocketMessage]
    private var parkWaiter: CheckedContinuation<RelayWebSocketMessage, Error>?
    private var cancelled = false
    private(set) var wasCancelled = false

    init(admissionReplies: [RelayWebSocketMessage]) { self.scripted = admissionReplies }

    func resume() {}
    func send(_ message: RelayWebSocketMessage) async throws {}

    func receive() async throws -> RelayWebSocketMessage {
        if let next = lock.withLock({ scripted.isEmpty ? nil : scripted.removeFirst() }) {
            return next   // admission Challenge / Result
        }
        // The park: block until cancel() resolves us with an error. The
        // already-cancelled check closes the race where cancel() lands before
        // receive() is even called.
        return try await withCheckedThrowingContinuation { cont in
            let resumeNow = lock.withLock { () -> Bool in
                if cancelled { return true }
                parkWaiter = cont
                return false
            }
            if resumeNow { cont.resume(throwing: TransportError.closed) }
        }
    }

    func sendPing() async -> Bool { false }   // half-open: the ping always fails

    func cancel() {
        let waiter = lock.withLock { () -> CheckedContinuation<RelayWebSocketMessage, Error>? in
            wasCancelled = true
            cancelled = true
            let w = parkWaiter
            parkWaiter = nil
            return w
        }
        waiter?.resume(throwing: TransportError.closed)
    }
}

private struct SingleSocketFactory: RelayWebSocketFactory {
    let ws: HalfOpenWebSocket
    func makeWebSocket(url: URL, headers: [String: String], timeout: TimeInterval?) -> RelayWebSocket {
        ws
    }
}

final class RelayKeepaliveTeardownTests: XCTestCase {
    func test_failedKeepalivePingCancelsParkedAcceptSoItThrows() async {
        let ws = HalfOpenWebSocket(admissionReplies: [
            .text(#"{"nonce":"3q2+7w=="}"#),   // Challenge
            .text(#"{"ok":true}"#),            // Result (mac mints no token)
        ])
        let listener = RelayTransportListener(
            relayOrigin: "https://relay.example.com",
            roomName: "room",
            webSocketFactory: SingleSocketFactory(ws: ws),
            keepaliveIntervalNanos: 0)   // ping immediately, deterministically

        do {
            _ = try await listener.accept()
            XCTFail("a half-open parked accept must throw once the keepalive ping fails")
        } catch {
            // Expected: the failed ping cancelled the socket, so the parked
            // receive() threw instead of hanging forever.
        }
        XCTAssertTrue(ws.wasCancelled, "the keepalive must cancel the socket on ping failure")
    }
}

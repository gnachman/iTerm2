//
//  RelayTransportTests.swift
//  CompanionCore
//
//  Unit coverage for RelayTransport's close signal, which the mac listener
//  relies on to avoid parking a second socket (and displacing its own live
//  connection) while a connection is still up. These do not touch the network:
//  the socket task is never resumed.
//

import XCTest
import CompanionProtocol
@testable import CompanionTransport

/// A scripted, network-free RelayWebSocket: replays `receives` in order and
/// records what was sent. An empty receive queue blocks (an idle socket).
final class FakeRelayWebSocket: RelayWebSocket, @unchecked Sendable {
    private let lock = UnfairLock()
    private var scripted: [RelayWebSocketMessage]
    private(set) var sent: [RelayWebSocketMessage] = []
    private(set) var cancelled = false

    init(receives: [RelayWebSocketMessage] = []) { self.scripted = receives }

    func resume() {}
    func send(_ message: RelayWebSocketMessage) async throws {
        lock.withLock { sent.append(message) }
    }
    func receive() async throws -> RelayWebSocketMessage {
        if let next = lock.withLock({ scripted.isEmpty ? nil : scripted.removeFirst() }) {
            return next
        }
        try await Task.sleep(nanoseconds: .max) // idle: block until cancelled
        throw TransportError.closed
    }
    func sendPing() async -> Bool { !lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

final class RelayTransportTests: XCTestCase {
    private func makeTransport() -> RelayTransport {
        RelayTransport(ws: FakeRelayWebSocket())
    }

    // The admission handshake drives entirely through the RelayWebSocket seam:
    // a scripted socket replays Challenge then Result; admit() must send Hello +
    // Proof and parse the Result, with no network.
    func test_admit_runsHandshakeOverTheSocketSeam() async throws {
        let ws = FakeRelayWebSocket(receives: [
            .text(#"{"nonce":"3q2+7w=="}"#),                         // Challenge
            .text(#"{"ok":true,"registrationToken":"tok-123"}"#),    // Result
        ])
        let result = try await RelayAdmissionClient.admit(ws: ws, role: .mac) { _ in
            RelayAdmission.Proof(ticket: nil, signature: nil)
        }
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.registrationToken, "tok-123")
        XCTAssertEqual(ws.sent.count, 2, "sent Hello then Proof")
        XCTAssertFalse(ws.cancelled)
    }

    func test_admit_cancelsTheSocketWhenRefused() async {
        let ws = FakeRelayWebSocket(receives: [
            .text(#"{"nonce":"3q2+7w=="}"#),
            .text(#"{"ok":false,"error":"mac offline"}"#),
        ])
        do {
            _ = try await RelayAdmissionClient.admit(ws: ws, role: .phone) { _ in
                RelayAdmission.Proof(ticket: nil, signature: nil)
            }
            XCTFail("a refused admission must throw")
        } catch {
            XCTAssertTrue(ws.cancelled, "a refused socket is cancelled")
        }
    }

    func test_waitUntilClosed_resolvesAfterClose() async {
        let transport = makeTransport()
        let waiter = Task { await transport.waitUntilClosed() }
        await transport.close()
        // If close() did not signal, this await would hang the test.
        await waiter.value
    }

    func test_waitUntilClosed_returnsImmediately_whenAlreadyClosed() async {
        let transport = makeTransport()
        transport.cancelAndSignalClosed()
        // Already closed: must return without suspending indefinitely.
        await transport.waitUntilClosed()
    }

    func test_waitUntilClosed_blocksWhileOpen() async {
        let transport = makeTransport()
        let done = Flag()
        let waiter = Task {
            await transport.waitUntilClosed()
            await done.set()
        }
        // While open, the waiter must stay suspended.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let resolvedWhileOpen = await done.value
        XCTAssertFalse(resolvedWhileOpen, "waitUntilClosed resolved before the transport closed")
        // Closing releases it.
        await transport.close()
        await waiter.value
        let resolvedAfterClose = await done.value
        XCTAssertTrue(resolvedAfterClose)
    }
}

private actor Flag {
    private(set) var value = false
    func set() { value = true }
}

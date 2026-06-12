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
@testable import CompanionTransport

final class RelayTransportTests: XCTestCase {
    private func makeTransport() -> RelayTransport {
        let task = URLSession.shared.webSocketTask(with: URL(string: "wss://example.invalid/")!)
        return RelayTransport(task: task)
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

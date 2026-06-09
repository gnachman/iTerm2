//
//  CombinedTransportListenerTests.swift
//  CompanionCore
//

import XCTest
@testable import CompanionProtocol

private actor CloseFlag {
    private(set) var closed = false
    func mark() { closed = true }
}

private final class RecordingTransport: MessageTransport, @unchecked Sendable {
    let name: String
    let flag = CloseFlag()
    init(_ name: String) { self.name = name }
    func send(_ frame: Data) async throws {}
    func receive() async throws -> Data { throw TransportError.closed }
    func close() async { await flag.mark() }
}

private final class StubListener: TransportListener, @unchecked Sendable {
    enum Behavior {
        case returnsAfter(UInt64, RecordingTransport)
        case parksUntilCancelled
    }
    let transportName: String
    let behavior: Behavior

    init(transportName: String, behavior: Behavior) {
        self.transportName = transportName
        self.behavior = behavior
    }

    func accept() async throws -> MessageTransport {
        switch behavior {
        case .returnsAfter(let delay, let transport):
            try? await Task.sleep(nanoseconds: delay)
            return transport
        case .parksUntilCancelled:
            // Parks until the surrounding task is cancelled, then throws. This
            // mirrors BonjourTransportListener's wait; if the combinator did not
            // cancel-and-await losers correctly, this would hang the test.
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    parked.setContinuation(continuation)
                }
            } onCancel: {
                parked.cancel()
            }
            throw TransportError.closed
        }
    }

    func stop() {}

    private let parked = Parked()

    private final class Parked: @unchecked Sendable {
        private var continuation: CheckedContinuation<Void, Error>?
        private var cancelled = false
        private let lock = NSLock()

        func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
            let resumeNow: Bool = {
                lock.lock(); defer { lock.unlock() }
                if cancelled { return true }
                self.continuation = continuation
                return false
            }()
            if resumeNow { continuation.resume(throwing: CancellationError()) }
        }

        func cancel() {
            let continuation: CheckedContinuation<Void, Error>? = {
                lock.lock(); defer { lock.unlock() }
                cancelled = true
                let c = self.continuation
                self.continuation = nil
                return c
            }()
            continuation?.resume(throwing: CancellationError())
        }
    }
}

final class CombinedTransportListenerTests: XCTestCase {
    func testReturnsWinnerWithoutHangingOnAParkedListener() async throws {
        let winner = RecordingTransport("winner")
        let combined = CombinedTransportListener([
            StubListener(transportName: "parks", behavior: .parksUntilCancelled),
            StubListener(transportName: "ok", behavior: .returnsAfter(2_000_000, winner))
        ])
        let transport = try await combined.accept()
        XCTAssertEqual((transport as? RecordingTransport)?.name, "winner")
    }

    func testClosesLosingConnections() async throws {
        let fast = RecordingTransport("fast")
        let slow = RecordingTransport("slow")
        let combined = CombinedTransportListener([
            StubListener(transportName: "fast", behavior: .returnsAfter(1_000_000, fast)),
            StubListener(transportName: "slow", behavior: .returnsAfter(15_000_000, slow))
        ])
        let transport = try await combined.accept()
        XCTAssertEqual((transport as? RecordingTransport)?.name, "fast")
        // accept() drains the group before returning, so the loser is already
        // closed by the time we get here.
        let fastClosed = await fast.flag.closed
        let slowClosed = await slow.flag.closed
        XCTAssertFalse(fastClosed, "the winning connection must not be closed")
        XCTAssertTrue(slowClosed, "the losing connection must be closed")
    }
}

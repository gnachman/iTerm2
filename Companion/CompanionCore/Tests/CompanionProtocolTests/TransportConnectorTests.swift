//
//  TransportConnectorTests.swift
//  CompanionCore
//

import XCTest
@testable import CompanionProtocol

private final class DummyTransport: MessageTransport, @unchecked Sendable {
    let name: String
    init(_ name: String) { self.name = name }
    func send(_ frame: Data) async throws {}
    func receive() async throws -> Data { throw TransportError.closed }
    func close() async {}
}

private struct StubConnector: TransportConnector {
    let transportName: String
    let delayNanos: UInt64
    let succeeds: Bool

    func connect(to rendezvous: PairingRendezvous,
                 timeout: TimeInterval) async throws -> MessageTransport {
        try? await Task.sleep(nanoseconds: delayNanos)
        if succeeds {
            return DummyTransport(transportName)
        }
        throw TransportError.connectionFailed(transportName)
    }
}

final class TransportConnectorTests: XCTestCase {
    private let rendezvous = PairingRendezvous(pairingID: "pid-test")

    func testRacePicksTheConnectorThatSucceeds() async throws {
        // The fast connector fails; the slower one succeeds. The race must wait
        // out the failure and return the success rather than giving up.
        let race = RaceTransportConnector([
            StubConnector(transportName: "fast-fail", delayNanos: 1_000_000, succeeds: false),
            StubConnector(transportName: "slow-ok", delayNanos: 20_000_000, succeeds: true)
        ])
        let transport = try await race.connect(to: rendezvous, timeout: 5)
        XCTAssertEqual((transport as? DummyTransport)?.name, "slow-ok")
    }

    func testRacePrefersTheFastestSuccess() async throws {
        let race = RaceTransportConnector([
            StubConnector(transportName: "slow-ok", delayNanos: 40_000_000, succeeds: true),
            StubConnector(transportName: "fast-ok", delayNanos: 2_000_000, succeeds: true)
        ])
        let transport = try await race.connect(to: rendezvous, timeout: 5)
        XCTAssertEqual((transport as? DummyTransport)?.name, "fast-ok")
    }

    func testRaceThrowsWhenAllFail() async {
        let race = RaceTransportConnector([
            StubConnector(transportName: "a", delayNanos: 1_000_000, succeeds: false),
            StubConnector(transportName: "b", delayNanos: 1_000_000, succeeds: false)
        ])
        do {
            _ = try await race.connect(to: rendezvous, timeout: 5)
            XCTFail("expected the race to throw when every connector fails")
        } catch {
            // Expected.
        }
    }

    func testRaceThrowsWhenEmpty() async {
        let race = RaceTransportConnector([])
        do {
            _ = try await race.connect(to: rendezvous, timeout: 5)
            XCTFail("expected an empty race to throw")
        } catch {
            // Expected.
        }
    }
}

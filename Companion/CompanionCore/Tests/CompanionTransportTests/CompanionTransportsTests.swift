//
//  CompanionTransportsTests.swift
//  CompanionCore
//
//  The transport-selection rule: local network always; relay only when the
//  pairing code carries a relay origin. This is the seam both apps build their
//  stacks from, so it is worth pinning down without touching the network.
//

import XCTest
import CompanionProtocol
@testable import CompanionTransport

final class CompanionTransportsTests: XCTestCase {
    private func makeCode(relayOrigin: String?) -> PairingCode {
        PairingCode(responderStaticPublicKey: Data(repeating: 7, count: 32),
                    pairingID: "abcd1234",
                    relayOrigin: relayOrigin)
    }

    func test_connector_isRelayOnly_whenRelayOriginPresent() throws {
        // Relay is currently the sole transport; Bonjour is switched off.
        let connector = CompanionTransports.connector(
            for: makeCode(relayOrigin: "https://relay.example"))
        let race = try XCTUnwrap(connector as? RaceTransportConnector)
        XCTAssertEqual(race.connectors.map(\.transportName), ["relay"])
    }

    func test_connector_isEmpty_whenNoRelayOriginAndNoLAN() throws {
        // With the LAN path off and no relay origin there is no transport at
        // all: connect() fails fast rather than silently using Bonjour.
        let connector = CompanionTransports.connector(for: makeCode(relayOrigin: nil))
        let race = try XCTUnwrap(connector as? RaceTransportConnector)
        XCTAssertEqual(race.connectors.map(\.transportName), [])
        XCTAssertFalse(CompanionTransports.useLocalNetworkTransport,
                       "If the LAN path is re-enabled, update this expectation.")
    }
}

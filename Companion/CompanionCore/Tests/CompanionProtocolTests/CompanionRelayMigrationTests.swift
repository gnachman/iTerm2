//
//  CompanionRelayMigrationTests.swift
//  CompanionCore
//
//  The revision-10 direct-relay -> resolver rewrite: which pairings migrate, and
//  that the rewrite preserves identity while swapping the endpoint. See
//  CompanionRelayMigration and CompanionProtocolVersion (revision 10).
//

import XCTest
@testable import CompanionProtocol

final class CompanionRelayMigrationTests: XCTestCase {
    private let rs = Data(repeating: 9, count: 32)
    private let pid = "pid-abcd-1234"

    func testLegacyDirectRelayIsDetected() {
        let code = PairingCode(responderStaticPublicKey: rs, pairingID: pid,
                               relayOrigin: CompanionRelayMigration.legacyDirectRelayOrigin)
        XCTAssertTrue(CompanionRelayMigration.isLegacyDirectRelay(code))
    }

    func testCustomRelayIsNotMigrated() {
        // A self-hosted / custom relay origin is a deliberate choice; leave it be.
        let code = PairingCode(responderStaticPublicKey: rs, pairingID: pid,
                               relayOrigin: "https://relay.example.com")
        XCTAssertFalse(CompanionRelayMigration.isLegacyDirectRelay(code))
    }

    func testAlreadyResolvedIsNotMigrated() {
        // Resolved mode already; nothing to do even if it were the legacy host.
        let code = PairingCode(responderStaticPublicKey: rs, pairingID: pid,
                               resolverURL: "https://resolver.iterm2.com/shardmap.json")
        XCTAssertFalse(CompanionRelayMigration.isLegacyDirectRelay(code))
    }

    func testMigratedSwapsEndpointButKeepsIdentity() {
        let code = PairingCode(responderStaticPublicKey: rs, pairingID: pid,
                               relayOrigin: CompanionRelayMigration.legacyDirectRelayOrigin)
        let migrated = CompanionRelayMigration.migrated(code)

        // Identity preserved (so the derived room name / bucket are unchanged), the
        // relay origin dropped, the default resolver adopted.
        XCTAssertEqual(migrated.responderStaticPublicKey, rs)
        XCTAssertEqual(migrated.pairingID, pid)
        XCTAssertNil(migrated.relayOrigin)
        XCTAssertEqual(migrated.resolverURL, CompanionRelayMigration.defaultResolverURL)
        XCTAssertEqual(migrated.version, PairingCode.resolvedVersion)
        // The room name (rs + pid) does not change across the migration.
        XCTAssertEqual(RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid),
                       RelayRoom.name(responderStaticPublicKey: migrated.responderStaticPublicKey,
                                      pairingID: migrated.pairingID))
        // Migrating is idempotent: a migrated code no longer looks like a legacy one.
        XCTAssertFalse(CompanionRelayMigration.isLegacyDirectRelay(migrated))
    }
}

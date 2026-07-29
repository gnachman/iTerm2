//
//  CompanionProtocolVersionTests.swift
//  CompanionCore
//
//  The app-version compatibility verdict: who (if anyone) must upgrade, given
//  each side's (revision, minimumPeer). The two ends evaluate independently and
//  must agree on which app to upgrade.
//

import XCTest
@testable import CompanionProtocol

final class CompanionProtocolVersionTests: XCTestCase {
    private func eval(_ localRev: Int, _ localMin: Int, _ peerRev: Int, _ peerMin: Int)
        -> CompanionProtocolVersion.Compatibility {
        CompanionProtocolVersion.evaluate(localRevision: localRev, localMinimumPeer: localMin,
                                          peerRevision: peerRev, peerMinimumPeer: peerMin)
    }

    func testEqualRevisionsAreCompatible() {
        XCTAssertEqual(eval(5, 5, 5, 5), .compatible)
    }

    func testNewerPeerWithinOurFloorIsCompatible() {
        // Peer is ahead but still accepts us, and we accept it.
        XCTAssertEqual(eval(5, 3, 7, 4), .compatible)
    }

    func testPeerTooOldForUs() {
        // Peer revision (3) is below our minimumPeer (5): they must upgrade.
        XCTAssertEqual(eval(8, 5, 3, 1), .peerMustUpgrade)
    }

    func testWeAreTooOldForPeer() {
        // Our revision (3) is below the peer's minimumPeer (5): we must upgrade.
        XCTAssertEqual(eval(3, 1, 8, 5), .selfMustUpgrade)
    }

    func testBothOutOfRangeResolvesToSelfUpgradeOnEachSide() {
        // A's view: A.rev=3 < B.min=5 -> selfMustUpgrade.
        XCTAssertEqual(eval(3, 5, 4, 5), .selfMustUpgrade)
        // B's view of the same standoff: B.rev=4 < A.min=5 -> selfMustUpgrade.
        XCTAssertEqual(eval(4, 5, 3, 5), .selfMustUpgrade)
        // Each side tells its own user to upgrade the app in front of them - so
        // upgrading both resolves it, with no "upgrade the other one" deadlock.
    }

    func testVerdictsAreConsistentAcrossSides() {
        // A (rev 8, min 5) vs B (rev 3, min 1): A sees peerMustUpgrade (upgrade B),
        // B sees selfMustUpgrade (upgrade B). Both point at B.
        XCTAssertEqual(eval(8, 5, 3, 1), .peerMustUpgrade)
        XCTAssertEqual(eval(3, 1, 8, 5), .selfMustUpgrade)
    }
}

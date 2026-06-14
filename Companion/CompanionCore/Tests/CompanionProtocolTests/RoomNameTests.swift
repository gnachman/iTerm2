//
//  RoomNameTests.swift
//  CompanionCoreTests
//
//  The relay room is addressed by an unguessable pseudonym derived from the
//  responder static key and the pairing id (plus a domain-separation label),
//  so only a party that scanned the QR can compute it. See
//  docs/companion-relay-design.md.
//

import XCTest
import CryptoKit
@testable import CompanionProtocol

final class RoomNameTests: XCTestCase {
    private let rs = Data(repeating: 0xAB, count: 32)
    private let pid = "0123456789abcdef"

    func test_isDeterministic() {
        XCTAssertEqual(RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid),
                       RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid))
    }

    func test_matchesCanonicalSha256OfRsAndPid() {
        // roomName = SHA256(canonical("iterm2-room", [rs, pid])), lowercase hex.
        let preimage = CanonicalEncoding.encode(domain: "iterm2-room", [rs, Data(pid.utf8)])
        let expected = SHA256.hash(data: preimage)
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid), expected)
    }

    func test_isLowercaseHex64() {
        let name = RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid)
        XCTAssertEqual(name.count, 64)
        XCTAssertTrue(name.allSatisfy { $0.isHexDigit && (!$0.isLetter || $0.isLowercase) })
    }

    func test_changesWithPid() {
        XCTAssertNotEqual(RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid),
                          RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid + "0"))
    }

    func test_changesWithResponderKey() {
        var other = rs
        other[0] ^= 0x01
        XCTAssertNotEqual(RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid),
                          RelayRoom.name(responderStaticPublicKey: other, pairingID: pid))
    }

    func test_labelPreventsCollisionWithBareConcatenation() {
        // Without the label, SHA256(rs || pid) would be derivable; the label
        // domain-separates this hash from any other use of rs/pid.
        let bare = SHA256.hash(data: rs + Data(pid.utf8))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid), bare)
    }
}

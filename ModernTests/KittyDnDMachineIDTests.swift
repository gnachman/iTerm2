//
//  KittyDnDMachineIDTests.swift
//  iTerm2 ModernTests
//
//  Phase 0 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. HMAC-SHA256 machine-id hashing and the
//  cross-machine (X=1) comparison. Vectors below were produced with:
//    printf '%s' "<input>" | openssl dgst -sha256 -hmac "tty-dnd-protocol-machine-id"
//

import XCTest
@testable import iTerm2SharedARC

final class KittyDnDMachineIDTests: XCTestCase {
    func testHashedVectorForSimpleInput() {
        XCTAssertEqual(
            KittyDnDMachineID.hashed("test"),
            "1:509f95553cfd5f13379f088d183ed4d8a93f72287fdd56beb2a52160fea250ae")
    }

    func testHashedVectorForUUID() {
        XCTAssertEqual(
            KittyDnDMachineID.hashed("550e8400-e29b-41d4-a716-446655440000"),
            "1:ae99eb3010d89529f191e076592fd46b85bc075bb48a9f4494b3e4e29e6ac0ba")
    }

    func testHashedFormatIsLowercaseHexWithPrefix() {
        let hashed = KittyDnDMachineID.hashed("anything")
        XCTAssertTrue(hashed.hasPrefix("1:"))
        let hex = String(hashed.dropFirst(2))
        XCTAssertEqual(hex.count, 64)
        XCTAssertEqual(hex, hex.lowercased())
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit })
    }

    func testDifferentIDIsRemote() {
        let ours = KittyDnDMachineID.hashed("machine-a")
        let theirs = KittyDnDMachineID.hashed("machine-b")
        XCTAssertTrue(KittyDnDMachineID.isRemote(theirID: theirs, ourID: ours))
    }

    func testSameIDIsNotRemote() {
        let ours = KittyDnDMachineID.hashed("machine-a")
        XCTAssertFalse(KittyDnDMachineID.isRemote(theirID: ours, ourID: ours))
    }

    // If the peer sent no machine id we cannot conclude it is remote; treat as
    // local so the simple (path-based) transfer applies.
    func testMissingIDIsNotRemote() {
        let ours = KittyDnDMachineID.hashed("machine-a")
        XCTAssertFalse(KittyDnDMachineID.isRemote(theirID: nil, ourID: ours))
        XCTAssertFalse(KittyDnDMachineID.isRemote(theirID: "", ourID: ours))
    }
}

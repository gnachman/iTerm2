//
//  CompanionPushNonceCryptoTests.swift
//  CompanionCore
//
//  Sealing the push nonce under the room secret: it round-trips for the holder
//  of the room secret, and is unreadable to anyone who lacks it (the relay /
//  Apple) or holds the wrong one (a re-paired room).
//

import XCTest
@testable import CompanionProtocol

final class CompanionPushNonceCryptoTests: XCTestCase {
    private let roomSecret = Data(repeating: 7, count: 32)

    func testRoundTripsForTheRoomSecretHolder() throws {
        let sealed = try CompanionPushNonceCrypto.seal(nonce: "deadbeefcafe", roomSecret: roomSecret)
        XCTAssertNotEqual(sealed, "deadbeefcafe", "the wire value must be ciphertext, not the nonce")
        XCTAssertEqual(CompanionPushNonceCrypto.open(sealed, roomSecret: roomSecret), "deadbeefcafe")
    }

    func testWrongRoomSecretCannotOpen() throws {
        let sealed = try CompanionPushNonceCrypto.seal(nonce: "abc123", roomSecret: roomSecret)
        XCTAssertNil(CompanionPushNonceCrypto.open(sealed, roomSecret: Data(repeating: 9, count: 32)),
                     "authentication must fail under a different room secret")
    }

    func testGarbageDoesNotOpen() {
        XCTAssertNil(CompanionPushNonceCrypto.open("not base64 @@@", roomSecret: roomSecret))
        XCTAssertNil(CompanionPushNonceCrypto.open("YWJjZGVm", roomSecret: roomSecret),
                     "valid base64 but not a sealed box must not open")
    }

    func testEachSealIsDistinct() throws {
        // ChaChaPoly uses a fresh internal AEAD nonce per seal, so the same nonce
        // seals to different ciphertext each time (no static fingerprint on the
        // wire for the relay to correlate).
        let a = try CompanionPushNonceCrypto.seal(nonce: "same", roomSecret: roomSecret)
        let b = try CompanionPushNonceCrypto.seal(nonce: "same", roomSecret: roomSecret)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(CompanionPushNonceCrypto.open(a, roomSecret: roomSecret), "same")
        XCTAssertEqual(CompanionPushNonceCrypto.open(b, roomSecret: roomSecret), "same")
    }
}

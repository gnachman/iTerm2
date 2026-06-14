//
//  RelayJoinTests.swift
//  CompanionCore
//
//  The asymmetric join credential: both devices derive the same Ed25519
//  signing key from the couriered roomSecret, and prove possession at the
//  relay by signing a bound transcript. The relay stores only the public
//  verifier. See docs/companion-relay-design.md.
//

import XCTest
import CryptoKit
@testable import CompanionProtocol

final class RelayJoinTests: XCTestCase {
    private let roomSecret = Data(repeating: 0x5A, count: 32)
    private let nonce = Data(repeating: 0x11, count: 32)
    private let roomName = String(repeating: "a", count: 64)
    private let origin = "https://relay.example.com"

    // MARK: Key derivation

    func test_keyDerivationIsDeterministic() {
        let a = RelayJoin.signingKey(roomSecret: roomSecret)
        let b = RelayJoin.signingKey(roomSecret: roomSecret)
        XCTAssertEqual(a.publicKey.rawRepresentation, b.publicKey.rawRepresentation)
    }

    func test_keyDerivationMatchesHKDF() {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: roomSecret),
            info: Data("relay-auth-ed25519".utf8),
            outputByteCount: 32)
        let seed = derived.withUnsafeBytes { Data($0) }
        let expected = try! Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        XCTAssertEqual(RelayJoin.signingKey(roomSecret: roomSecret).publicKey.rawRepresentation,
                       expected.publicKey.rawRepresentation)
    }

    func test_differentRoomSecretGivesDifferentKey() {
        var other = roomSecret
        other[0] ^= 0x01
        XCTAssertNotEqual(RelayJoin.signingKey(roomSecret: roomSecret).publicKey.rawRepresentation,
                          RelayJoin.signingKey(roomSecret: other).publicKey.rawRepresentation)
    }

    func test_verifierIsThePublicKey() {
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        XCTAssertEqual(RelayJoin.verifier(roomSecret: roomSecret), key.publicKey.rawRepresentation)
        XCTAssertEqual(RelayJoin.verifier(roomSecret: roomSecret).count, 32)
    }

    // MARK: Transcript

    func test_transcriptLayout() {
        let t = RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin)
        let expected = CanonicalEncoding.encode(
            domain: "iterm2-relay-join",
            [Data([RelayJoin.Role.phone.rawValue]), nonce, Data(roomName.utf8), Data(origin.utf8)])
        XCTAssertEqual(t, expected)
    }

    func test_transcriptVariesWithRole() {
        XCTAssertNotEqual(
            RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin),
            RelayJoin.transcript(role: .mac, nonce: nonce, roomName: roomName, origin: origin))
    }

    func test_transcriptVariesWithNonce() {
        var n2 = nonce; n2[0] ^= 0x01
        XCTAssertNotEqual(
            RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin),
            RelayJoin.transcript(role: .phone, nonce: n2, roomName: roomName, origin: origin))
    }

    func test_transcriptVariesWithRoomAndOrigin() {
        XCTAssertNotEqual(
            RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin),
            RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin + "x"))
        XCTAssertNotEqual(
            RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin),
            RelayJoin.transcript(role: .phone, nonce: nonce, roomName: "b" + roomName.dropFirst(), origin: origin))
    }

    // MARK: Sign / verify round trip

    func test_signAndVerifyRoundTrip() {
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        let verifier = RelayJoin.verifier(roomSecret: roomSecret)
        let t = RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin)
        let sig = try! key.signature(for: t)
        XCTAssertTrue(RelayJoin.verify(signature: sig, transcript: t, verifier: verifier))
    }

    func test_wrongVerifierFailsVerification() {
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        var otherSecret = roomSecret; otherSecret[0] ^= 0xFF
        let t = RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin)
        let sig = try! key.signature(for: t)
        XCTAssertFalse(RelayJoin.verify(signature: sig,
                                        transcript: t,
                                        verifier: RelayJoin.verifier(roomSecret: otherSecret)))
    }

    func test_tamperedTranscriptFailsVerification() {
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        let verifier = RelayJoin.verifier(roomSecret: roomSecret)
        let t = RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin)
        let sig = try! key.signature(for: t)
        let tampered = RelayJoin.transcript(role: .mac, nonce: nonce, roomName: roomName, origin: origin)
        XCTAssertFalse(RelayJoin.verify(signature: sig, transcript: tampered, verifier: verifier))
    }
}

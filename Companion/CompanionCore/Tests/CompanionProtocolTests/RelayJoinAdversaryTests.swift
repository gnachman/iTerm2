//
//  RelayJoinAdversaryTests.swift
//  CompanionCore
//
//  Threat-model assertions for the relay-join credential: an attacker who does
//  NOT hold the roomSecret must be unable to forge a join, and a signature
//  captured for one room/relay must not be replayable against another (the
//  transcript binds room name and origin precisely so this fails). See the
//  "what Cloudflare can and cannot know" section of
//  docs/companion-relay-design.md.
//

import XCTest
import CryptoKit
@testable import CompanionProtocol

final class RelayJoinAdversaryTests: XCTestCase {
    private let roomSecret = Data(repeating: 0x5A, count: 32)
    private let nonce = Data(repeating: 0x11, count: 32)
    private let roomName = String(repeating: "a", count: 64)
    private let origin = "https://relay.example.com"

    /// Threat: a relay (or anyone) holding only the public verifier tries to
    /// mint a join. Without the signing key, any signature it fabricates must
    /// fail. (Models a relay storage dump: it holds verifiers, nothing else.)
    func test_attackerWithOnlyVerifierCannotForge() {
        let verifier = RelayJoin.verifier(roomSecret: roomSecret)
        let t = RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin)
        // Best the attacker can do is guess; try random and structured forgeries.
        for forgery in [Data(repeating: 0, count: 64),
                        Data(repeating: 0xFF, count: 64),
                        Data((0..<64).map { UInt8($0) }),
                        verifier + verifier] {
            XCTAssertFalse(RelayJoin.verify(signature: forgery, transcript: t, verifier: verifier))
        }
    }

    /// Threat: a malicious relay reuses a legitimate join signature for a
    /// DIFFERENT room (it knows other room names). The bound room name makes
    /// the signature invalid there.
    func test_signatureDoesNotReplayAcrossRooms() {
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        let verifier = RelayJoin.verifier(roomSecret: roomSecret)
        let roomA = String(repeating: "a", count: 64)
        let roomB = String(repeating: "b", count: 64)
        let sigForA = try! key.signature(
            for: RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomA, origin: origin))
        let transcriptForB = RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomB, origin: origin)
        XCTAssertFalse(RelayJoin.verify(signature: sigForA, transcript: transcriptForB, verifier: verifier))
    }

    /// Threat: a hostile relay at a different origin replays a signature minted
    /// for the official relay. The bound origin defeats it.
    func test_signatureDoesNotReplayAcrossOrigins() {
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        let verifier = RelayJoin.verifier(roomSecret: roomSecret)
        let sig = try! key.signature(
            for: RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: "https://official.example"))
        let evilTranscript = RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: "https://evil.example")
        XCTAssertFalse(RelayJoin.verify(signature: sig, transcript: evilTranscript, verifier: verifier))
    }

    /// Threat: a captured signature is replayed against a fresh DO challenge.
    /// A different nonce changes the transcript, so the old signature fails.
    func test_signatureDoesNotReplayAcrossNonces() {
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        let verifier = RelayJoin.verifier(roomSecret: roomSecret)
        let sig = try! key.signature(
            for: RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin))
        var freshNonce = nonce; freshNonce[31] ^= 0x01
        let freshTranscript = RelayJoin.transcript(role: .phone, nonce: freshNonce, roomName: roomName, origin: origin)
        XCTAssertFalse(RelayJoin.verify(signature: sig, transcript: freshTranscript, verifier: verifier))
    }

    /// Threat: the relay reuses a phone-role join in the mac slot (or vice
    /// versa). Role is bound, so a phone signature is invalid for a mac join.
    func test_signatureDoesNotReplayAcrossRoles() {
        let key = RelayJoin.signingKey(roomSecret: roomSecret)
        let verifier = RelayJoin.verifier(roomSecret: roomSecret)
        let phoneSig = try! key.signature(
            for: RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin))
        let macTranscript = RelayJoin.transcript(role: .mac, nonce: nonce, roomName: roomName, origin: origin)
        XCTAssertFalse(RelayJoin.verify(signature: phoneSig, transcript: macTranscript, verifier: verifier))
    }

    /// A malformed verifier (not a valid Ed25519 point / wrong length) must
    /// reject rather than crash.
    func test_malformedVerifierRejects() {
        let t = RelayJoin.transcript(role: .phone, nonce: nonce, roomName: roomName, origin: origin)
        XCTAssertFalse(RelayJoin.verify(signature: Data(repeating: 0, count: 64),
                                        transcript: t,
                                        verifier: Data(repeating: 0, count: 5)))
    }
}

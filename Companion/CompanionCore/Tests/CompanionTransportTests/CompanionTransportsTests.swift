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

    func test_connector_isRelay_whenRelayOriginPresent() {
        // Relay is the sole transport.
        let connector = CompanionTransports.connector(
            for: makeCode(relayOrigin: "https://relay.example"))
        XCTAssertEqual(connector.transportName, "relay")
    }

    func test_signedProof_isEmptyWithoutRoomSecret() throws {
        let challenge = RelayAdmission.Challenge(nonce: Data(repeating: 9, count: 32))
        let proof = try CompanionTransports.signedProof(
            role: .phone, challenge: challenge, roomName: "room", origin: "https://relay.example",
            roomSecret: nil)
        XCTAssertNil(proof.signature)
        XCTAssertNil(proof.ticket)
    }

    func test_signedProof_signsTranscriptVerifiableByTheRegisteredVerifier() throws {
        // The signature the client sends must verify against the verifier the
        // relay stores, over the same transcript the relay reconstructs.
        let roomSecret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let challenge = RelayAdmission.Challenge(nonce: nonce)
        let roomName = "abcd"
        let origin = "https://relay.example"

        let proof = try CompanionTransports.signedProof(
            role: .mac, challenge: challenge, roomName: roomName, origin: origin,
            roomSecret: roomSecret)
        let signature = try XCTUnwrap(proof.signature)

        let transcript = RelayJoin.transcript(role: .mac, nonce: nonce,
                                              roomName: roomName, origin: origin)
        XCTAssertTrue(RelayJoin.verify(signature: signature,
                                       transcript: transcript,
                                       verifier: RelayJoin.verifier(roomSecret: roomSecret)))
        // A different role's transcript must NOT verify (the role is bound in).
        let phoneTranscript = RelayJoin.transcript(role: .phone, nonce: nonce,
                                                   roomName: roomName, origin: origin)
        XCTAssertFalse(RelayJoin.verify(signature: signature,
                                        transcript: phoneTranscript,
                                        verifier: RelayJoin.verifier(roomSecret: roomSecret)))
    }

    // Adversarial: a proof signed with the wrong secret, or checked against a
    // tampered transcript, must fail verification, the same threats the relay's
    // established.test.js asserts, pinned here at the client signing layer.
    func test_signedProof_doesNotVerifyAgainstADifferentRoomSecret() throws {
        let secret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let otherSecret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let nonce = Data(repeating: 3, count: 32)
        let proof = try CompanionTransports.signedProof(
            role: .phone, challenge: RelayAdmission.Challenge(nonce: nonce),
            roomName: "room", origin: "https://relay.example", roomSecret: secret)
        let transcript = RelayJoin.transcript(role: .phone, nonce: nonce,
                                              roomName: "room", origin: "https://relay.example")
        XCTAssertFalse(RelayJoin.verify(signature: try XCTUnwrap(proof.signature),
                                        transcript: transcript,
                                        verifier: RelayJoin.verifier(roomSecret: otherSecret)))
    }

    func test_signedProof_doesNotVerifyWithTamperedTranscriptFields() throws {
        let secret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let nonce = Data(repeating: 5, count: 32)
        let proof = try CompanionTransports.signedProof(
            role: .phone, challenge: RelayAdmission.Challenge(nonce: nonce),
            roomName: "roomA", origin: "https://relay.example", roomSecret: secret)
        let signature = try XCTUnwrap(proof.signature)
        let verifier = RelayJoin.verifier(roomSecret: secret)

        // Each tampered field independently breaks verification.
        let wrongNonce = RelayJoin.transcript(role: .phone, nonce: Data(repeating: 6, count: 32),
                                              roomName: "roomA", origin: "https://relay.example")
        let wrongRoom = RelayJoin.transcript(role: .phone, nonce: nonce,
                                             roomName: "roomB", origin: "https://relay.example")
        let wrongOrigin = RelayJoin.transcript(role: .phone, nonce: nonce,
                                               roomName: "roomA", origin: "https://evil.example")
        for tampered in [wrongNonce, wrongRoom, wrongOrigin] {
            XCTAssertFalse(RelayJoin.verify(signature: signature, transcript: tampered, verifier: verifier))
        }
    }

    func test_connector_isUnavailable_whenNoRelayOrigin() async {
        // No relay origin means no transport at all: connect() fails fast.
        let connector = CompanionTransports.connector(for: makeCode(relayOrigin: nil))
        XCTAssertEqual(connector.transportName, "none")
        do {
            _ = try await connector.connect(to: PairingRendezvous(pairingID: "abcd1234"), timeout: 1)
            XCTFail("expected connect to fail when there is no transport")
        } catch {
            // Expected.
        }
    }
}

extension CompanionTransportsTests {
    private func challenge() -> RelayAdmission.Challenge {
        RelayAdmission.Challenge(nonce: Data(repeating: 9, count: 32))
    }

    func test_admissionProof_signsWhenRoomSecretPresent_ignoringTicket() throws {
        // An established room signs its join; a stale ticket must never override
        // a real signature.
        let secret = Data(repeating: 1, count: 32)
        let proof = try CompanionTransports.admissionProof(
            role: .phone, challenge: challenge(), roomName: "room",
            origin: "https://relay.example", roomSecret: secret, pairingTicket: "tkt")
        XCTAssertNotNil(proof.signature)
        XCTAssertNil(proof.ticket)
    }

    func test_admissionProof_presentsTicketForFreshPairing() throws {
        let proof = try CompanionTransports.admissionProof(
            role: .phone, challenge: challenge(), roomName: "room",
            origin: "https://relay.example", roomSecret: nil, pairingTicket: "tkt-9")
        XCTAssertNil(proof.signature)
        XCTAssertEqual(proof.ticket, "tkt-9")
    }

    func test_admissionProof_isEmptyForOpenModePairing() throws {
        let proof = try CompanionTransports.admissionProof(
            role: .phone, challenge: challenge(), roomName: "room",
            origin: "https://relay.example", roomSecret: nil, pairingTicket: nil)
        XCTAssertNil(proof.signature)
        XCTAssertNil(proof.ticket)
    }
}

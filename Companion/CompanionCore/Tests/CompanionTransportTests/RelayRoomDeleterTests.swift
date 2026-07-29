//
//  RelayRoomDeleterTests.swift
//  CompanionCore
//
//  The client side of the authenticated delete-room call made at unpair. The
//  deleter fetches a fresh challenge, signs the delete transcript with the
//  room's join key (derived from roomSecret), and POSTs /delete. The in-process
//  fake relay mirrors the DO's contract: it issues single-use challenges and
//  accepts a delete only if the signature verifies against the room's verifier
//  over the bound delete transcript. The adversarial cases assert the deleter
//  cannot delete with the wrong secret and treats an already-gone room as done.
//  See docs/companion-relay-design.md (Deletion, revocation, and expiry).
//

import XCTest
import CryptoKit
import CompanionProtocol
@testable import CompanionTransport

final class RelayRoomDeleterTests: XCTestCase {
    private let origin = "https://relay.example"
    private let roomName = String(repeating: "a", count: 64)
    private let roomSecret = Data(repeating: 0x5A, count: 32)

    /// An in-process relay implementing the /attest/challenge + /delete contract.
    /// It verifies the delete the way the real DO does: a single-use challenge it
    /// issued, signed over deleteTranscript by the registered room's key.
    private final class FakeRelay: RelayHTTPClient, @unchecked Sendable {
        let origin: String
        let roomVerifier: Data
        /// When false, the relay reports the room is not established (already
        /// deleted), exercising the deleter's "treat as done" path.
        var established: Bool
        private(set) var paths: [String] = []
        private var issued = Set<String>()
        private var seq = 0
        private(set) var deleted = false

        init(origin: String, roomVerifier: Data, established: Bool = true) {
            self.origin = origin
            self.roomVerifier = roomVerifier
            self.established = established
        }

        private func json(_ obj: [String: Any]) -> Data {
            try! JSONSerialization.data(withJSONObject: obj)
        }

        func post(path: String, roomName: String, json body: [String: String]?) async throws -> (status: Int, body: Data) {
            paths.append(path)
            switch path {
            case "/attest/challenge":
                seq += 1
                let nonce = Data((0..<32).map { _ in UInt8(seq & 0xff) })
                let challenge = nonce.base64EncodedString()
                issued.insert(challenge)
                return (200, json(["ok": true, "challenge": challenge]))
            case "/delete":
                guard established else {
                    return (403, json(["ok": false, "error": "not established"]))
                }
                guard let body,
                      let challenge = body["challenge"],
                      issued.remove(challenge) != nil, // single-use
                      let challengeBytes = Data(base64Encoded: challenge),
                      let sigB64 = body["signature"],
                      let sig = Data(base64Encoded: sigB64) else {
                    return (403, json(["ok": false, "error": "signature required"]))
                }
                let transcript = RelayJoin.deleteTranscript(
                    challenge: challengeBytes, roomName: roomName, origin: origin)
                guard RelayJoin.verify(signature: sig, transcript: transcript, verifier: roomVerifier) else {
                    return (403, json(["ok": false, "error": "bad signature"]))
                }
                deleted = true
                return (200, json(["ok": true]))
            default:
                return (404, json(["ok": false, "error": "not found"]))
            }
        }
    }

    func test_deletesRoomWithAValidSignedRequest() async throws {
        let relay = FakeRelay(origin: origin, roomVerifier: RelayJoin.verifier(roomSecret: roomSecret))
        let deleter = RelayRoomDeleter(origin: origin, http: relay)

        let ok = try await deleter.deleteRoom(roomName: roomName, roomSecret: roomSecret)

        XCTAssertTrue(ok)
        XCTAssertTrue(relay.deleted)
        XCTAssertEqual(relay.paths, ["/attest/challenge", "/delete"])
    }

    func test_treatsAnAlreadyGoneRoomAsSuccess() async throws {
        let relay = FakeRelay(origin: origin,
                              roomVerifier: RelayJoin.verifier(roomSecret: roomSecret),
                              established: false)
        let deleter = RelayRoomDeleter(origin: origin, http: relay)

        // A room already deleted (e.g. by the peer, or a prior attempt) is "done",
        // not an error: unpair must not block on it.
        let ok = try await deleter.deleteRoom(roomName: roomName, roomSecret: roomSecret)
        XCTAssertTrue(ok)
        XCTAssertFalse(relay.deleted)
    }

    func test_staleMapRejection_throwsReResolve() async {
        // A 421 on a room-scoped call means the host no longer owns the bucket, so
        // the deleter surfaces reResolve (§6.9) rather than a generic HTTP error;
        // the caller re-resolves the owner and retries there.
        let stub = FixedStatusRelay(status: 421)
        let deleter = RelayRoomDeleter(origin: origin, http: stub)
        do {
            _ = try await deleter.deleteRoom(roomName: roomName, roomSecret: roomSecret)
            XCTFail("expected reResolve")
        } catch let error as TransportError {
            XCTAssertEqual(error, .reResolve(ownerHint: nil))
        } catch {
            XCTFail("expected TransportError.reResolve, got \(error)")
        }
    }

    private struct FixedStatusRelay: RelayHTTPClient {
        let status: Int
        func post(path: String, roomName: String, json: [String: String]?) async throws -> (status: Int, body: Data) {
            (status, Data("{}".utf8))
        }
    }

    func test_wrongRoomSecretIsRejectedByTheRelay() async throws {
        // The relay registered the real pairing's verifier; a deleter holding a
        // different secret signs with the wrong key and must be refused.
        let relay = FakeRelay(origin: origin, roomVerifier: RelayJoin.verifier(roomSecret: roomSecret))
        var wrongSecret = roomSecret; wrongSecret[0] ^= 0xFF
        let deleter = RelayRoomDeleter(origin: origin, http: relay)

        do {
            _ = try await deleter.deleteRoom(roomName: roomName, roomSecret: wrongSecret)
            XCTFail("expected the relay to reject a delete signed with the wrong key")
        } catch {
            // expected
        }
        XCTAssertFalse(relay.deleted)
    }
}

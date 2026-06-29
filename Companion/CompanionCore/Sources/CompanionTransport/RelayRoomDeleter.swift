//
//  RelayRoomDeleter.swift
//  CompanionCore
//
//  The client side of the authenticated delete-room call. At unpair, either
//  device tells the relay to wipe the room (its pseudonym, public verifier, and
//  pinned attest key id) instead of leaving it to age out under the idle TTL.
//  The call proves possession of the room's join key by signing a delete
//  transcript over a fresh, single-use challenge, so it can be neither forged by
//  a room-name holder nor replayed. It is BEST-EFFORT: a failure (relay
//  unreachable, offline unpair) is tolerated because the relay's established-room
//  idle TTL bounds retention regardless. The HTTP surface is injected (the same
//  RelayHTTPClient the attestation client uses), so on the Mac it rides the
//  consent plugin's egress and on the phone it is a direct URLSession.
//  See docs/companion-relay-design.md (Deletion, revocation, and expiry).
//

import Foundation
import CryptoKit
import CompanionProtocol

public struct RelayRoomDeleter: Sendable {
    private let origin: String
    private let http: RelayHTTPClient

    public init(origin: String, http: RelayHTTPClient) {
        self.origin = origin
        self.http = http
    }

    public init(origin: String, session: URLSession = CompanionURLSession.shared) {
        self.init(origin: origin, http: URLSessionRelayHTTPClient(origin: origin, session: session))
    }

    /// Delete the room, authenticated by the join key derived from `roomSecret`.
    /// Returns true if the relay wiped the room OR it was already gone (an
    /// already-deleted room is "done", not an error, so unpair never blocks on
    /// it). Throws only on an unexpected relay rejection, which the caller treats
    /// as best-effort (the idle TTL is the backstop).
    @discardableResult
    public func deleteRoom(roomName: String, roomSecret: Data) async throws -> Bool {
        let challenge = try await fetchChallenge(roomName: roomName)
        guard let challengeBytes = Data(base64Encoded: challenge) else {
            throw RelayAttestationError.malformedResponse
        }
        let transcript = RelayJoin.deleteTranscript(
            challenge: challengeBytes, roomName: roomName, origin: origin)
        let signature = try RelayJoin.signingKey(roomSecret: roomSecret)
            .signature(for: transcript)
            .base64EncodedString()

        let (status, body) = try await http.post(
            path: "/delete", roomName: roomName,
            json: ["challenge": challenge, "signature": signature])
        switch status {
        case 200:
            return true
        case 403 where errorMessage(body) == "not established":
            // Already deleted (by the peer, or a prior attempt that landed): the
            // room is gone, which is exactly the goal.
            return true
        default:
            throw RelayAttestationError.http(status, errorMessage(body) ?? "")
        }
    }

    // MARK: -

    private func fetchChallenge(roomName: String) async throws -> String {
        let (status, body) = try await http.post(path: "/attest/challenge", roomName: roomName, json: nil)
        guard status == 200 else {
            throw RelayAttestationError.http(status, errorMessage(body) ?? "")
        }
        guard let challenge = decode(body)?.challenge else {
            throw RelayAttestationError.malformedResponse
        }
        return challenge
    }

    private struct RelayResponse: Decodable {
        var challenge: String?
        var error: String?
    }

    private func decode(_ data: Data) -> RelayResponse? {
        try? JSONDecoder().decode(RelayResponse.self, from: data)
    }

    private func errorMessage(_ data: Data) -> String? {
        decode(data)?.error
    }
}

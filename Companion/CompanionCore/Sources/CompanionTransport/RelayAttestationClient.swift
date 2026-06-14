//
//  RelayAttestationClient.swift
//  CompanionCore
//
//  The phone's App Attest client for the relay. Under attestation the relay
//  admits a pairing phone only if it presents a single-use TICKET it earned by
//  attesting a genuine-app key, and accepts the verifier registration only if
//  it is signed by an ASSERTION from that same key. This client produces both:
//
//    obtainTicket(roomName:)      POST /attest/challenge -> attestKey -> POST /attest
//    registerAssertion(roomName:) POST /attest/challenge -> generateAssertion
//
//  clientDataHash = SHA256(challengeBytes || origin) on both ends; the Worker
//  reconstructs it to verify the App Attest nonce. The attested key is pinned
//  per room (AttestKeyStore) so the assertion reuses the key the ticket
//  attested. Everything degrades safely: an unsupported device, or a relay in
//  open mode (which answers /attest with 400), yields nil so the caller sends
//  an empty proof / a token-only registration. See docs/companion-relay-design.md.
//

import Foundation
import CryptoKit
import CompanionProtocol

public enum RelayAttestationError: Error, Equatable {
    case malformedResponse
    case http(Int, String)
    case invalidOrigin
}

/// The tiny HTTP surface the attestation client needs: a POST to a relay path
/// with the room header and an optional JSON body, returning status + bytes.
/// Injected so the orchestration can run against an in-process fake.
public protocol RelayHTTPClient: Sendable {
    func post(path: String, roomName: String, json: [String: String]?) async throws -> (status: Int, body: Data)
}

/// The production transport: a plain URLSession POST to `origin + path`.
public struct URLSessionRelayHTTPClient: RelayHTTPClient {
    private let origin: String
    private let session: URLSession
    private let timeout: TimeInterval

    public init(origin: String, session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.origin = origin
        self.session = session
        self.timeout = timeout
    }

    public func post(path: String, roomName: String, json: [String: String]?) async throws -> (status: Int, body: Data) {
        guard let url = URL(string: origin + path) else { throw RelayAttestationError.invalidOrigin }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(roomName, forHTTPHeaderField: "x-relay-room")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, data)
    }
}

public struct RelayAttestationClient: Sendable {
    private let origin: String
    private let service: AppAttestService
    private let store: AttestKeyStore
    private let http: RelayHTTPClient

    public init(origin: String, service: AppAttestService, store: AttestKeyStore, http: RelayHTTPClient) {
        self.origin = origin
        self.service = service
        self.store = store
        self.http = http
    }

    public init(origin: String,
                service: AppAttestService,
                store: AttestKeyStore,
                session: URLSession = .shared) {
        self.init(origin: origin, service: service, store: store,
                  http: URLSessionRelayHTTPClient(origin: origin, session: session))
    }

    /// The clientDataHash both ends bind into the App Attest nonce:
    /// SHA256(canonical("iterm2-relay-attest", [challengeBytes, origin])).
    /// `challenge` is the relay's base64 nonce. Length-prefixed/domain-separated
    /// so the challenge/origin boundary is unambiguous; the worker reconstructs
    /// the identical bytes.
    public static func clientDataHash(challenge: String, origin: String) -> Data {
        let preimage = CanonicalEncoding.encode(domain: "iterm2-relay-attest",
                                                [Data(base64Encoded: challenge) ?? Data(),
                                                 Data(origin.utf8)])
        return Data(SHA256.hash(data: preimage))
    }

    /// Earn the single-use admission ticket for a fresh pairing. Returns nil
    /// (and pins no key) when the device cannot attest or the relay is in open
    /// mode, so the caller falls back to an empty proof.
    public func obtainTicket(roomName: String) async throws -> String? {
        guard service.isSupported else {
            CompanionLog.log("obtainTicket: device cannot attest (isSupported=false)")
            return nil
        }

        let challenge = try await fetchChallenge(roomName: roomName)
        let clientDataHash = Self.clientDataHash(challenge: challenge, origin: origin)
        CompanionLog.log("obtainTicket: generating App Attest key…")
        let keyId = try await service.generateKey()
        CompanionLog.log("obtainTicket: key \(keyId.prefix(12))…; calling attestKey (Apple round trip)…")
        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
        CompanionLog.log("obtainTicket: attestation produced (\(attestation.count) bytes); POST /attest…")

        let (status, body) = try await http.post(
            path: "/attest", roomName: roomName,
            json: ["challenge": challenge, "attestationObject": attestation.base64EncodedString()])
        CompanionLog.log("obtainTicket: /attest -> HTTP \(status)\(status == 200 ? "" : " (\(errorMessage(body) ?? ""))")")

        switch status {
        case 200:
            guard let ticket = decode(body, AttestResponse.self)?.ticket else {
                throw RelayAttestationError.malformedResponse
            }
            // Pin the attested key so the register assertion reuses it.
            store.setKeyId(keyId, forRoom: roomName)
            CompanionLog.log("obtainTicket: ticket minted; key pinned for room")
            return ticket
        case 400 where errorMessage(body) == "attestation disabled":
            // Open-mode relay: no ticket needed, and nothing to pin.
            CompanionLog.log("obtainTicket: relay in open mode; no ticket")
            return nil
        default:
            throw RelayAttestationError.http(status, errorMessage(body) ?? "")
        }
    }

    /// Produce the assertion that authorizes verifier registration, signed by
    /// the key the ticket attested. Returns nil when there is no pinned key
    /// (open mode / unsupported device), so the caller registers with the token
    /// alone.
    public func registerAssertion(roomName: String) async throws -> (challenge: String, assertion: String)? {
        guard service.isSupported else {
            CompanionLog.log("registerAssertion: device cannot attest; open-mode register")
            return nil
        }
        guard let keyId = store.keyId(forRoom: roomName) else {
            CompanionLog.log("registerAssertion: no pinned key for room; open-mode register")
            return nil
        }
        let challenge = try await fetchChallenge(roomName: roomName)
        let clientDataHash = Self.clientDataHash(challenge: challenge, origin: origin)
        CompanionLog.log("registerAssertion: signing with key \(keyId.prefix(12))…")
        let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
        CompanionLog.log("registerAssertion: assertion produced (\(assertion.count) bytes)")
        return (challenge, assertion.base64EncodedString())
    }

    // MARK: -

    private func fetchChallenge(roomName: String) async throws -> String {
        CompanionLog.log("attestation: POST /attest/challenge…")
        let (status, body) = try await http.post(path: "/attest/challenge", roomName: roomName, json: nil)
        guard status == 200 else {
            CompanionLog.log("attestation: /attest/challenge -> HTTP \(status) (\(errorMessage(body) ?? ""))")
            throw RelayAttestationError.http(status, errorMessage(body) ?? "")
        }
        guard let challenge = decode(body, AttestResponse.self)?.challenge else {
            throw RelayAttestationError.malformedResponse
        }
        return challenge
    }

    private struct AttestResponse: Decodable {
        var challenge: String?
        var ticket: String?
        var error: String?
    }

    private func decode<T: Decodable>(_ data: Data, _ type: T.Type) -> T? {
        try? JSONDecoder().decode(T.self, from: data)
    }

    private func errorMessage(_ data: Data) -> String? {
        decode(data, AttestResponse.self)?.error
    }
}

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

/// A resolver that returns a fixed origin, so a v2 connector can be built without
/// the phone-only URLSession fallback (which asserts on the macOS test host).
private struct StubShardResolver: ShardHostResolving {
    let origin: String
    func relayOrigin(for code: PairingCode, forceFresh: Bool) async throws -> String { origin }
}

/// A resolver that fails the way an unreachable shard map does.
private struct FailingShardResolver: ShardHostResolving {
    let error: Error
    func relayOrigin(for code: PairingCode, forceFresh: Bool) async throws -> String { throw error }
}

/// A resolver whose resolve never finishes but which has already recorded
/// what went wrong, as a real one would after the primary failed DNS while the
/// mirror was still waiting.
private struct HangingResolverWithRecordedFailure: ShardHostResolving {
    let recorded: ShardMapFetchError
    func relayOrigin(for code: PairingCode, forceFresh: Bool) async throws -> String {
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
        return "https://never.example"
    }
    func failureSoFar() async -> ShardMapFetchError? { recorded }
}

/// A resolver that never answers, like a shard-map GET a network silently drops.
private struct HangingShardResolver: ShardHostResolving {
    var sources: [String] = []
    func relayOrigin(for code: PairingCode, forceFresh: Bool) async throws -> String {
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
        return "https://never.example"
    }
    func mapSourceURLs() async -> [String] { sources }
}

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

    func test_connector_isResolved_whenResolverURLPresent() {
        // A v2 code (resolver, no relay origin) uses the resolving connector, which
        // picks the host from the shard map at connect time. Pass a resolver (as
        // both apps do) so this test does not exercise the phone-only URLSession
        // fallback, which asserts on the macOS test host.
        let code = PairingCode(responderStaticPublicKey: Data(repeating: 7, count: 32),
                               pairingID: "abcd1234",
                               resolverURL: "https://resolver.example.com/")
        let connector = CompanionTransports.connector(
            for: code, shardResolver: StubShardResolver(origin: "https://relay1.iterm2.com"))
        XCTAssertEqual(connector.transportName, "relay-resolved")
    }

    private func resolvedCode() -> PairingCode {
        PairingCode(responderStaticPublicKey: Data(repeating: 7, count: 32),
                    pairingID: "abcd1234",
                    resolverURL: "https://resolver.example.com/")
    }

    private func connectError(_ resolver: ShardHostResolving, timeout: TimeInterval = 30) async -> Error? {
        let connector = CompanionTransports.connector(for: resolvedCode(), shardResolver: resolver)
        do {
            _ = try await connector.connect(to: PairingRendezvous(pairingID: "abcd1234"), timeout: timeout)
            XCTFail("expected a throw")
            return nil
        } catch {
            return error
        }
    }

    func test_resolvedConnect_reportsTheFetchFailure_whenMapFetchFails() async {
        // The user sees this error, so a failed shard-map fetch must say what
        // went wrong with each source rather than surface a raw URL error.
        let fetchError = ShardMapFetchError(attempts: [
            .init(url: "https://resolver.example.com/", error: URLError(.timedOut))])
        let error = await connectError(FailingShardResolver(error: fetchError))
        guard case let .shardMapUnavailable(summary, details)? = error as? TransportError else {
            return XCTFail("unexpected \(String(describing: error))")
        }
        XCTAssertEqual(summary, fetchError.summary)
        XCTAssertEqual(details, fetchError.details)
    }

    func test_resolvedConnect_namesTheHosts_whenMapFetchHangs() async {
        let error = await connectError(HangingShardResolver(), timeout: 0.05)
        guard case let .shardMapUnavailable(summary, details)? = error as? TransportError else {
            return XCTFail("unexpected \(String(describing: error))")
        }
        XCTAssertTrue(summary.contains("resolver.example.com"), summary)
        XCTAssertTrue(details.contains("resolver.example.com"), details)
        XCTAssertFalse(summary.contains("https://"), summary)
    }

    func test_resolvedConnect_namesTheSourcesTheResolverUses_whenMapFetchHangs() async {
        // Not the default mirrors for the code's URL: a resolver built with its
        // own mirrors tried those, and one with none tried none.
        let resolver = HangingShardResolver(sources: ["https://resolver.example.com/",
                                                      "https://custom-mirror.example.org/map.json"])
        let error = await connectError(resolver, timeout: 0.05)
        guard case let .shardMapUnavailable(summary, details)? = error as? TransportError else {
            return XCTFail("unexpected \(String(describing: error))")
        }
        XCTAssertTrue(summary.contains("its mirror custom-mirror.example.org"), summary)
        XCTAssertTrue(details.contains("custom-mirror.example.org"), details)
        XCTAssertFalse(summary.contains("github"), summary)
    }

    func test_resolvedConnect_timeoutKeepsWhatAlreadyWentWrong() async {
        // The overall budget runs out while the mirror hangs, after the primary
        // has already failed DNS. What was recorded must be reported, not
        // replaced by "didn't respond". (Recording during a cancelled race is
        // tested in ShardMapLoaderFallbackTests.)
        let recorded = ShardMapFetchError(attempts: [
            .init(url: "https://resolver.iterm2.com/shardmap.json", error: URLError(.cannotFindHost), duration: 0.1),
            .init(url: "https://gnachman.github.io/iterm2-companion-relay/shardmap.json",
                  error: URLError(.timedOut), duration: 10),
        ])
        let error = await connectError(HangingResolverWithRecordedFailure(recorded: recorded), timeout: 0.05)
        guard case let .shardMapUnavailable(summary, details)? = error as? TransportError else {
            return XCTFail("unexpected \(String(describing: error))")
        }
        XCTAssertEqual(summary, recorded.summary)
        XCTAssertEqual(details, recorded.details)
    }

    func test_resolvedConnect_passesThroughOtherErrors() async {
        // Cancellation (URLSession reports it as URLError(.cancelled)) and
        // transport errors are not shard-map fetch failures.
        let cancelled = await connectError(FailingShardResolver(error: URLError(.cancelled)))
        XCTAssertEqual((cancelled as? URLError)?.code, .cancelled)
        let transport = await connectError(FailingShardResolver(error: TransportError.connectionFailed("x")))
        XCTAssertEqual(transport as? TransportError, .connectionFailed("x"))
    }

    func test_shardMapUnavailable_separatesSummaryFromDetails() {
        let error = TransportError.shardMapUnavailable(summary: "SUMMARY", details: "DETAILS")
        XCTAssertEqual(error.summary, "SUMMARY")
        XCTAssertEqual(error.details, "DETAILS")
        // localizedDescription lands in one-line status text: summary only.
        XCTAssertEqual(error.errorDescription, "SUMMARY")
        XCTAssertEqual(error.localizedDescription, "SUMMARY")
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

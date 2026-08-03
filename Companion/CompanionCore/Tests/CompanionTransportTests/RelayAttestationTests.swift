//
//  RelayAttestationTests.swift
//  CompanionCore
//
//  The phone-side App Attest client that earns the relay a genuine-app proof:
//  a single-use admission TICKET (challenge -> attest -> /attest) presented in
//  the WebSocket Proof, and a register ASSERTION (challenge -> assert) signed
//  by the SAME attested key, sent with the verifier on /register. The device
//  primitives (DCAppAttestService) and the HTTP transport are injected, so the
//  orchestration is exercised end to end against an in-process fake Worker that
//  mirrors the real DO's contract. The adversarial cases assert that supplying
//  invalid information (wrong key, replayed challenge, tampered attestation,
//  open-mode/unsupported device) fails closed. See docs/companion-relay-design.md.
//

import XCTest
import CryptoKit
import CompanionProtocol
@testable import CompanionTransport

// MARK: - Test doubles

/// A deterministic stand-in for DCAppAttestService. Its "attestation" and
/// "assertion" are plaintext envelopes that encode the key id and the exact
/// clientDataHash they were produced for, so the fake Worker can verify the
/// binding the real App Attest nonce would commit to.
private final class FakeAppAttest: AppAttestService, @unchecked Sendable {
    var supported: Bool
    private(set) var generatedKeys: [String] = []
    private var counter = 0
    /// When set, attestKey corrupts the clientDataHash it commits to (a device
    /// that attests over the wrong challenge), so the Worker must reject it.
    var corruptAttestationClientDataHash = false

    init(supported: Bool = true) { self.supported = supported }

    var isSupported: Bool { supported }

    func generateKey() async throws -> String {
        counter += 1
        let keyId = "key-\(counter)"
        generatedKeys.append(keyId)
        return keyId
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        let committed = corruptAttestationClientDataHash
            ? Data("tampered".utf8)
            : clientDataHash
        return Data("ATT:\(keyId):\(committed.base64EncodedString())".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        Data("ASRT:\(keyId):\(clientDataHash.base64EncodedString())".utf8)
    }
}

private final class InMemoryKeyStore: AttestKeyStore, @unchecked Sendable {
    private var keys: [String: String] = [:]
    func keyId(forRoom roomName: String) -> String? { keys[roomName] }
    func setKeyId(_ keyId: String?, forRoom roomName: String) { keys[roomName] = keyId }
    func removeAll() { keys.removeAll() }
}

/// Returns a fixed HTTP status for every call, to exercise status-based branches.
private struct FixedStatusHTTP: RelayHTTPClient {
    let status: Int
    func post(path: String, roomName: String, json: [String: String]?) async throws -> (status: Int, body: Data) {
        (status, Data("{}".utf8))
    }
}

/// An in-process relay that speaks the two endpoints the client calls
/// (/attest/challenge, /attest) AND exposes the WS-admission + /register checks
/// the app performs, so a test can drive the whole genuine-app path and assert
/// the Worker's contract: challenges are single-use, the attestation binds the
/// right clientDataHash, the ticket pins the attested key, and the register
/// assertion must be signed by that same key over a fresh challenge.
private final class FakeRelayWorker: RelayHTTPClient, @unchecked Sendable {
    let origin: String
    var attestRequired: Bool
    private(set) var requestPaths: [String] = []
    private var issued = Set<String>()
    private var tickets: [String: String] = [:]   // ticket -> keyId
    private var tokens: [String: String] = [:]     // regtoken -> keyId
    private var challengeSeq = 0
    private var ticketSeq = 0
    private var tokenSeq = 0
    private(set) var registered: (verifier: String, keyId: String)?

    init(origin: String, attestRequired: Bool = true) {
        self.origin = origin
        self.attestRequired = attestRequired
    }

    private func json(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    func post(path: String, roomName: String, json body: [String: String]?) async throws -> (status: Int, body: Data) {
        requestPaths.append(path)
        switch path {
        case "/attest/challenge":
            challengeSeq += 1
            let challenge = Data("challenge-\(challengeSeq)".utf8).base64EncodedString()
            issued.insert(challenge)
            return (200, json(["ok": true, "challenge": challenge]))

        case "/attest":
            guard attestRequired else {
                return (400, json(["ok": false, "error": "attestation disabled"]))
            }
            guard let challenge = body?["challenge"], let attestationB64 = body?["attestationObject"] else {
                return (400, json(["ok": false, "error": "missing fields"]))
            }
            guard issued.remove(challenge) != nil else {
                return (403, json(["ok": false, "error": "bad challenge"]))
            }
            guard let keyId = verifyAttestation(attestationB64, challenge: challenge) else {
                return (403, json(["ok": false, "error": "attestation rejected"]))
            }
            ticketSeq += 1
            let ticket = "ticket-\(ticketSeq)"
            tickets[ticket] = keyId
            return (200, json(["ok": true, "ticket": ticket]))

        default:
            return (404, json(["ok": false, "error": "not found"]))
        }
    }

    // The synthetic attestation is "ATT:<keyId>:<clientDataHashB64>"; verifying
    // it means recomputing clientDataHash the way the real Worker does and
    // checking the committed value matches (the App Attest nonce binding).
    private func verifyAttestation(_ attestationB64: String, challenge: String) -> String? {
        guard let data = Data(base64Encoded: attestationB64),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.components(separatedBy: ":")
        guard parts.count == 3, parts[0] == "ATT" else { return nil }
        let expected = RelayAttestationClient.clientDataHash(challenge: challenge, origin: origin)
        guard parts[2] == expected.base64EncodedString() else { return nil }
        return parts[1]
    }

    // MARK: WS admission + /register, the steps the app performs around the client.

    /// Mimics the DO admitting a phone that presents `ticket`: consumes it and
    /// mints a registration token that inherits the attested key id. nil if the
    /// ticket is unknown/spent.
    func admit(ticket: String) -> String? {
        guard let keyId = tickets.removeValue(forKey: ticket) else { return nil }
        tokenSeq += 1
        let token = "token-\(tokenSeq)"
        tokens[token] = keyId
        return token
    }

    /// Mimics POST /register under attestation: the token must be valid, and the
    /// assertion must be signed by the token's pinned key over a fresh,
    /// single-use challenge. Returns the HTTP status.
    func register(token: String, verifier: String, challenge: String?, assertion: String?) -> Int {
        guard let keyId = tokens[token] else { return 403 }
        if attestRequired {
            guard let challenge, let assertion else { return 403 }
            guard issued.remove(challenge) != nil else { return 403 }
            guard let data = Data(base64Encoded: assertion),
                  let text = String(data: data, encoding: .utf8) else { return 403 }
            let parts = text.components(separatedBy: ":")
            let expected = RelayAttestationClient.clientDataHash(challenge: challenge, origin: origin)
            guard parts.count == 3, parts[0] == "ASRT",
                  parts[1] == keyId, parts[2] == expected.base64EncodedString() else { return 403 }
        }
        registered = (verifier, keyId)
        return 200
    }
}

final class RelayAttestationTests: XCTestCase {
    private let origin = "https://relay.example"

    private func makeClient(worker: FakeRelayWorker,
                            attest: FakeAppAttest,
                            store: AttestKeyStore) -> RelayAttestationClient {
        RelayAttestationClient(origin: origin, service: attest, store: store, http: worker)
    }

    // MARK: clientDataHash agreement

    func test_clientDataHash_matchesWorkerReconstruction() {
        // SHA256(canonical("iterm2-relay-attest", [challengeBytes, origin])).
        // The Worker recomputes this exactly; any divergence breaks attestation,
        // so pin the formula.
        let challenge = Data("hello".utf8).base64EncodedString()
        let preimage = CanonicalEncoding.encode(domain: "iterm2-relay-attest",
                                                [Data("hello".utf8), Data(origin.utf8)])
        let expected = Data(SHA256.hash(data: preimage))
        XCTAssertEqual(RelayAttestationClient.clientDataHash(challenge: challenge, origin: origin), expected)
    }

    // MARK: Ticket

    func test_obtainTicket_happyPath_returnsTicketAndStoresKey() async throws {
        let worker = FakeRelayWorker(origin: origin)
        let attest = FakeAppAttest()
        let store = InMemoryKeyStore()
        let client = makeClient(worker: worker, attest: attest, store: store)

        let ticket = try await client.obtainTicket(roomName: "room")

        XCTAssertNotNil(ticket)
        XCTAssertEqual(attest.generatedKeys.count, 1, "one fresh App Attest key per pairing")
        XCTAssertEqual(store.keyId(forRoom: "room"), attest.generatedKeys.first,
                       "the attested key is persisted so the register assertion can reuse it")
    }

    func test_obtainTicket_unsupportedDevice_returnsNilWithoutTouchingTheKeychain() async throws {
        let worker = FakeRelayWorker(origin: origin)
        let attest = FakeAppAttest(supported: false)
        let store = InMemoryKeyStore()
        let client = makeClient(worker: worker, attest: attest, store: store)

        let ticket = try await client.obtainTicket(roomName: "room")

        XCTAssertNil(ticket)
        XCTAssertTrue(attest.generatedKeys.isEmpty)
        XCTAssertNil(store.keyId(forRoom: "room"))
        XCTAssertTrue(worker.requestPaths.isEmpty, "an unsupported device never calls the relay")
    }

    func test_obtainTicket_staleMapRejection_throwsReResolve() async {
        // A 421 on /attest/challenge means this host does not own the bucket, so the
        // client surfaces reResolve (§6.9) rather than a generic HTTP error; the
        // caller re-resolves the owner and retries the attestation there.
        let client = RelayAttestationClient(origin: origin,
                                            service: FakeAppAttest(supported: true),
                                            store: InMemoryKeyStore(),
                                            http: FixedStatusHTTP(status: 421))
        do {
            _ = try await client.obtainTicket(roomName: "room")
            XCTFail("expected reResolve")
        } catch let error as TransportError {
            XCTAssertEqual(error, .reResolve(ownerHint: nil))
        } catch {
            XCTFail("expected TransportError.reResolve, got \(error)")
        }
    }

    func test_obtainTicket_openMode_returnsNilAndDoesNotStoreKey() async throws {
        // Relay in open mode answers /attest with 400 attestation disabled; the
        // phone falls back to an empty proof rather than failing the pairing.
        let worker = FakeRelayWorker(origin: origin, attestRequired: false)
        let attest = FakeAppAttest()
        let store = InMemoryKeyStore()
        let client = makeClient(worker: worker, attest: attest, store: store)

        let ticket = try await client.obtainTicket(roomName: "room")

        XCTAssertNil(ticket)
        XCTAssertNil(store.keyId(forRoom: "room"),
                     "no key is pinned when the relay is not enforcing attestation")
    }

    func test_obtainTicket_rejectedAttestation_throws() async throws {
        // A device that attests over the wrong clientDataHash is refused (403).
        let worker = FakeRelayWorker(origin: origin)
        let attest = FakeAppAttest()
        attest.corruptAttestationClientDataHash = true
        let store = InMemoryKeyStore()
        let client = makeClient(worker: worker, attest: attest, store: store)

        do {
            _ = try await client.obtainTicket(roomName: "room")
            XCTFail("a rejected attestation must throw")
        } catch let error as RelayAttestationError {
            guard case .http(403, _) = error else { return XCTFail("expected http(403), got \(error)") }
        }
        XCTAssertNil(store.keyId(forRoom: "room"))
    }

    // MARK: Assertion

    func test_registerAssertion_withoutAttestedKey_returnsNil() async throws {
        let worker = FakeRelayWorker(origin: origin)
        let client = makeClient(worker: worker, attest: FakeAppAttest(), store: InMemoryKeyStore())

        let result = try await client.registerAssertion(roomName: "room")

        XCTAssertNil(result, "no attested key means open-mode register (no assertion)")
    }

    func test_registerAssertion_unsupportedDevice_returnsNil() async throws {
        let worker = FakeRelayWorker(origin: origin)
        let store = InMemoryKeyStore()
        store.setKeyId("stale", forRoom: "room")
        let client = makeClient(worker: worker, attest: FakeAppAttest(supported: false), store: store)

        let result = try await client.registerAssertion(roomName: "room")
        XCTAssertNil(result)
    }

    // MARK: Full genuine-app path (integration against the fake Worker)

    func test_fullFlow_ticketThenAdmitThenRegister_succeedsAndReusesOneKey() async throws {
        let worker = FakeRelayWorker(origin: origin)
        let attest = FakeAppAttest()
        let store = InMemoryKeyStore()
        let client = makeClient(worker: worker, attest: attest, store: store)

        // 1. Earn the admission ticket by attesting.
        let ticket = try await XCTUnwrapAsync(await client.obtainTicket(roomName: "room"))
        // 2. The relay admits the phone and mints a registration token.
        let token = try XCTUnwrap(worker.admit(ticket: ticket))
        // 3. Sign the verifier registration with an assertion from the same key.
        let assertion = try await XCTUnwrapAsync(await client.registerAssertion(roomName: "room"))
        let status = worker.register(token: token, verifier: "V",
                                     challenge: assertion.challenge, assertion: assertion.assertion)

        XCTAssertEqual(status, 200)
        XCTAssertEqual(worker.registered?.verifier, "V")
        XCTAssertEqual(worker.registered?.keyId, attest.generatedKeys.first)
        XCTAssertEqual(attest.generatedKeys.count, 1,
                       "attestation and assertion are produced by the SAME key")
    }

    func test_register_withAssertionFromWrongKey_isRejected() async throws {
        // If the assertion is signed by a key other than the one the ticket
        // pinned, the relay refuses the registration.
        let worker = FakeRelayWorker(origin: origin)
        let attest = FakeAppAttest()
        let store = InMemoryKeyStore()
        let client = makeClient(worker: worker, attest: attest, store: store)

        let ticket = try await XCTUnwrapAsync(await client.obtainTicket(roomName: "room"))
        let token = try XCTUnwrap(worker.admit(ticket: ticket))
        // Tamper: repoint the stored key so the assertion is signed by a
        // different (attacker) key than the ticket attested.
        store.setKeyId("attacker-key", forRoom: "room")
        let assertion = try await XCTUnwrapAsync(await client.registerAssertion(roomName: "room"))

        let status = worker.register(token: token, verifier: "V",
                                     challenge: assertion.challenge, assertion: assertion.assertion)
        XCTAssertEqual(status, 403)
    }

    func test_register_withReplayedChallenge_isRejected() async throws {
        // The assertion's challenge is single-use; presenting the same pair
        // twice fails the second time.
        let worker = FakeRelayWorker(origin: origin)
        let client = makeClient(worker: worker, attest: FakeAppAttest(), store: InMemoryKeyStore())

        let ticket = try await XCTUnwrapAsync(await client.obtainTicket(roomName: "room"))
        let token = try XCTUnwrap(worker.admit(ticket: ticket))
        let assertion = try await XCTUnwrapAsync(await client.registerAssertion(roomName: "room"))

        XCTAssertEqual(worker.register(token: token, verifier: "V",
                                       challenge: assertion.challenge, assertion: assertion.assertion), 200)
        XCTAssertEqual(worker.register(token: token, verifier: "V",
                                       challenge: assertion.challenge, assertion: assertion.assertion), 403,
                       "a consumed challenge cannot be replayed")
    }
}

// Async-friendly XCTUnwrap: XCTUnwrap is not usable on an already-awaited
// optional inside an autoclosure cleanly, so unwrap explicitly.
private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else {
        XCTFail("expected non-nil value", file: file, line: line)
        throw RelayAttestationError.malformedResponse
    }
    return value
}

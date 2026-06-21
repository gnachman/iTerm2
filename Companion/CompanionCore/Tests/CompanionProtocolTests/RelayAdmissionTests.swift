//
//  RelayAdmissionTests.swift
//  CompanionCore
//
//  The JSON admission handshake between a client (phone or Mac) and the relay
//  Durable Object, before the splice. Sequence: client Hello {v, role} -> DO
//  Challenge {nonce} (uniform, to avoid a mode oracle) -> client Proof
//  {ticket OR sig} -> DO Result {ok, registrationToken? | error}. These tests
//  pin the wire shape the JS Worker must match. See
//  docs/companion-relay-design.md.
//

import XCTest
@testable import CompanionProtocol

final class RelayAdmissionTests: XCTestCase {
    private let enc = JSONEncoder()
    private let dec = JSONDecoder()

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try enc.encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func test_helloRoundTrip() throws {
        let hello = RelayAdmission.Hello(v: 1, role: .phone)
        let obj = try json(hello)
        XCTAssertEqual(obj["v"] as? Int, 1)
        XCTAssertEqual(obj["role"] as? String, "phone")
        XCTAssertEqual(try dec.decode(RelayAdmission.Hello.self, from: enc.encode(hello)), hello)
    }

    func test_decodesHelloFromWorkerJSON() throws {
        let data = Data(#"{"v":1,"role":"mac"}"#.utf8)
        let hello = try dec.decode(RelayAdmission.Hello.self, from: data)
        XCTAssertEqual(hello.role, .mac)
    }

    func test_challengeNonceIsBase64() throws {
        let nonce = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let obj = try json(RelayAdmission.Challenge(nonce: nonce))
        XCTAssertEqual(obj["nonce"] as? String, nonce.base64EncodedString())
        let back = try dec.decode(RelayAdmission.Challenge.self,
                                  from: enc.encode(RelayAdmission.Challenge(nonce: nonce)))
        XCTAssertEqual(back.nonce, nonce)
    }

    func test_proofWithTicketOnly() throws {
        let proof = RelayAdmission.Proof(ticket: "tkt-123", signature: nil)
        let obj = try json(proof)
        XCTAssertEqual(obj["ticket"] as? String, "tkt-123")
        XCTAssertNil(obj["sig"])
    }

    func test_proofWithSignatureOnly() throws {
        let sig = Data(repeating: 0xAB, count: 64)
        let proof = RelayAdmission.Proof(ticket: nil, signature: sig)
        let obj = try json(proof)
        XCTAssertNil(obj["ticket"])
        XCTAssertEqual(obj["sig"] as? String, sig.base64EncodedString())
    }

    func test_resultAccepted() throws {
        let result = RelayAdmission.Result.accepted(registrationToken: "reg-9")
        let obj = try json(result)
        XCTAssertEqual(obj["ok"] as? Bool, true)
        XCTAssertEqual(obj["registrationToken"] as? String, "reg-9")
    }

    func test_resultRejected() throws {
        let result = RelayAdmission.Result.rejected(error: "bad ticket")
        let obj = try json(result)
        XCTAssertEqual(obj["ok"] as? Bool, false)
        XCTAssertEqual(obj["error"] as? String, "bad ticket")
    }

    func test_roleEncodesAsLowercaseString() throws {
        XCTAssertEqual(try json(RelayAdmission.Hello(v: 1, role: .mac))["role"] as? String, "mac")
        XCTAssertEqual(try json(RelayAdmission.Hello(v: 1, role: .phone))["role"] as? String, "phone")
    }
}

//
//  PairingCodeTests.swift
//  CompanionCore
//

import XCTest
@testable import CompanionProtocol

final class PairingCodeTests: XCTestCase {
    // 32 zero bytes, base64url-encoded (no padding).
    private let validKeyB64URL = Data(repeating: 0, count: 32).base64URLEncodedString()

    private func url(v: String = "1",
                     proto: String = PairingCode.supportedProtocol,
                     rs: String? = nil,
                     pid: String? = "f7c2a1b9") -> String {
        var items = "v=\(v)&proto=\(proto)"
        items += "&rs=\(rs ?? validKeyB64URL)"
        if let pid { items += "&pid=\(pid)" }
        return "iterm2://pair?\(items)"
    }

    func testParsesValidCode() throws {
        let code = try PairingCode.parse(url())
        XCTAssertEqual(code.responderStaticPublicKey.count, 32)
        XCTAssertEqual(code.pairingID, "f7c2a1b9")
    }

    func testRejectsWrongVersion() {
        XCTAssertThrowsError(try PairingCode.parse(url(v: "2"))) { error in
            XCTAssertEqual(error as? PairingCode.ParseError,
                           .unsupportedVersion(found: "2"))
        }
    }

    func testRejectsWrongProtocol() {
        XCTAssertThrowsError(try PairingCode.parse(url(proto: "Noise_NN"))) { error in
            XCTAssertEqual(error as? PairingCode.ParseError,
                           .unsupportedProtocol(found: "Noise_NN"))
        }
    }

    func testRejectsWrongKeySize() {
        let shortKey = Data(repeating: 1, count: 16).base64URLEncodedString()
        XCTAssertThrowsError(try PairingCode.parse(url(rs: shortKey))) { error in
            XCTAssertEqual(error as? PairingCode.ParseError, .invalidResponderKey)
        }
    }

    func testRejectsMissingPairingID() {
        XCTAssertThrowsError(try PairingCode.parse(url(pid: nil))) { error in
            XCTAssertEqual(error as? PairingCode.ParseError, .missingPairingID)
        }
    }

    func testRejectsNonPairURL() {
        XCTAssertThrowsError(try PairingCode.parse("https://example.com")) { error in
            XCTAssertEqual(error as? PairingCode.ParseError, .malformedURL)
        }
    }

    func testRoundTripsURL() throws {
        let original = try PairingCode.parse(url())
        let rebuilt = try PairingCode.parse(original.urlString())
        XCTAssertEqual(original, rebuilt)
    }

    // The pairing code is stored as a JSON blob in the keychain (so it survives
    // an app reinstall) and decoded by both the app and the NSE, so its Codable
    // round-trip must be stable.
    func testCodableRoundTrip() throws {
        let original = PairingCode(responderStaticPublicKey: Data(repeating: 0xAB, count: 32),
                                   pairingID: "pid-123",
                                   relayOrigin: "https://relay.example.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PairingCode.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTripWithNilRelayOrigin() throws {
        let original = PairingCode(responderStaticPublicKey: Data(repeating: 1, count: 32),
                                   pairingID: "pid", relayOrigin: nil)
        let decoded = try JSONDecoder().decode(PairingCode.self,
                                               from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.relayOrigin)
    }
}

//
//  PairingCodeRelayTests.swift
//  CompanionCore
//
//  The QR may carry a relay= origin so the pairing also works off-LAN (and on
//  client-isolated networks). The phone must canonicalize it to scheme+host
//  +port and refuse anything richer, so embedded path/userinfo tricks have no
//  foothold. See docs/companion-relay-design.md.
//

import XCTest
@testable import CompanionProtocol

final class PairingCodeRelayTests: XCTestCase {
    private let validKeyB64URL = Data(repeating: 0, count: 32).base64URLEncodedString()

    private func url(relay: String?) -> String {
        var items = "v=1&proto=\(PairingCode.supportedProtocol)&rs=\(validKeyB64URL)&pid=f7c2a1b9"
        if let relay {
            let escaped = relay.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? relay
            items += "&relay=\(escaped)"
        }
        return "iterm2://pair?\(items)"
    }

    func test_relayAbsent_isNil() throws {
        let code = try PairingCode.parse(url(relay: nil))
        XCTAssertNil(code.relayOrigin)
    }

    func test_validHttpsRelay_parsesToOrigin() throws {
        let code = try PairingCode.parse(url(relay: "https://relay.example.com"))
        XCTAssertEqual(code.relayOrigin, "https://relay.example.com")
    }

    func test_relayWithExplicitPort_keepsPort() throws {
        let code = try PairingCode.parse(url(relay: "https://relay.example.com:8443"))
        XCTAssertEqual(code.relayOrigin, "https://relay.example.com:8443")
    }

    func test_httpRelay_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(relay: "http://relay.example.com"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidRelay)
        }
    }

    func test_relayWithPath_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(relay: "https://relay.example.com/evil"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidRelay)
        }
    }

    func test_relayWithQuery_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(relay: "https://relay.example.com?x=1"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidRelay)
        }
    }

    func test_relayWithFragment_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(relay: "https://relay.example.com#frag"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidRelay)
        }
    }

    func test_relayWithUserinfo_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(relay: "https://user:pw@relay.example.com"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidRelay)
        }
    }

    func test_relayWithoutHost_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(relay: "https://"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidRelay)
        }
    }

    func test_relayRoundTripsThroughURLString() throws {
        let original = try PairingCode.parse(url(relay: "https://relay.example.com:8443"))
        let rebuilt = try PairingCode.parse(original.urlString())
        XCTAssertEqual(original, rebuilt)
        XCTAssertEqual(rebuilt.relayOrigin, "https://relay.example.com:8443")
    }

    func test_trailingSlashCanonicalizedAway() throws {
        // A bare host with a trailing slash is just the origin; the path is
        // empty, so it is accepted and canonicalized without the slash.
        let code = try PairingCode.parse(url(relay: "https://relay.example.com/"))
        XCTAssertEqual(code.relayOrigin, "https://relay.example.com")
    }
}

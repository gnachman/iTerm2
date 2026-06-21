//
//  RelayHostTests.swift
//  CompanionCore
//
//  The disclosure rule shared by both pairing entry points (tapped iterm2:// link
//  AND scanned QR): surface the relay host on the confirmation screen whenever it
//  differs from the official default, rendered in punycode so a Unicode lookalike
//  of the default host cannot read as legitimate. The default (or a missing host)
//  discloses nothing, so the indicator is signal, not noise.
//

import XCTest
@testable import CompanionProtocol

final class RelayHostTests: XCTestCase {
    private let defaultHost = "companion-relay.iterm2.com"

    func test_defaultRelayDisclosesNothing() {
        XCTAssertNil(RelayHost.hostToDisclose(
            relayOrigin: "https://\(defaultHost)", default: defaultHost))
    }

    func test_missingOrMalformedOriginDisclosesNothing() {
        XCTAssertNil(RelayHost.hostToDisclose(relayOrigin: nil, default: defaultHost))
        XCTAssertNil(RelayHost.hostToDisclose(relayOrigin: "", default: defaultHost))
        XCTAssertNil(RelayHost.hostToDisclose(relayOrigin: "not a url", default: defaultHost))
    }

    func test_nonDefaultAsciiHostIsDisclosedVerbatim() {
        XCTAssertEqual(
            RelayHost.hostToDisclose(relayOrigin: "https://relay.example.com", default: defaultHost),
            "relay.example.com")
    }

    func test_nonDefaultUnicodeHostIsDisclosedInPunycode() {
        // A confusable lookalike must show as its punycode, not the Unicode form.
        XCTAssertEqual(
            RelayHost.hostToDisclose(relayOrigin: "https://münchen.example", default: defaultHost),
            "xn--mnchen-3ya.example")
    }

    func test_disclosureIgnoresPortAndPath() {
        XCTAssertEqual(
            RelayHost.hostToDisclose(relayOrigin: "https://relay.example:8443/x", default: defaultHost),
            "relay.example")
    }
}

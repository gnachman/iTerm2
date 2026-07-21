//
//  PairingCodeResolverTests.swift
//  CompanionCore
//
//  Resolved mode (v=2): the QR carries a resolver= URL instead of a relay=
//  origin. The client fetches the shard map from the resolver (the base URL of a
//  static, versioned map on a CDN) and connects to the owning host. The resolver
//  may carry a path (it can be hosted at a subpath), but userinfo/query/fragment
//  and non-https schemes are refused. Direct (v1) and resolved (v2) modes are
//  mutually exclusive, selected by which parameter is present and tagged by the
//  version. See docs/companion-relay-design.md.
//

import XCTest
@testable import CompanionProtocol

final class PairingCodeResolverTests: XCTestCase {
    private let validKeyB64URL = Data(repeating: 0, count: 32).base64URLEncodedString()

    /// A resolved-mode (v=2) URL carrying the given resolver.
    private func url(resolver: String?) -> String {
        var items = "v=2&proto=\(PairingCode.supportedProtocol)&rs=\(validKeyB64URL)&pid=f7c2a1b9"
        if let resolver {
            let escaped = resolver.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? resolver
            items += "&resolver=\(escaped)"
        }
        return "iterm2://pair?\(items)"
    }

    func test_v2WithoutResolver_rejected() {
        // v2 is resolved mode by definition; a resolver is required.
        XCTAssertThrowsError(try PairingCode.parse(url(resolver: nil))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidResolver)
        }
    }

    func test_validHttpsResolver_parses() throws {
        let code = try PairingCode.parse(url(resolver: "https://resolver.example.com"))
        XCTAssertEqual(code.resolverURL, "https://resolver.example.com")
        XCTAssertNil(code.relayOrigin)
        XCTAssertEqual(code.version, 2)
    }

    func test_resolverWithExplicitPort_keepsPort() throws {
        let code = try PairingCode.parse(url(resolver: "https://resolver.example.com:8443"))
        XCTAssertEqual(code.resolverURL, "https://resolver.example.com:8443")
    }

    func test_resolverWithPath_keepsPath() throws {
        // Unlike relay=, the resolver value points directly at the shard-map JSON,
        // which may live at a subpath (e.g. behind a shared CDN). The path is
        // preserved verbatim, since the client GETs it as-is.
        let code = try PairingCode.parse(url(resolver: "https://cdn.example.com/iterm2/shardmap.json"))
        XCTAssertEqual(code.resolverURL, "https://cdn.example.com/iterm2/shardmap.json")
    }

    func test_trailingSlashPreserved() throws {
        // The value is used verbatim (the client appends nothing), so whatever path
        // it carries, trailing slash included, is preserved exactly as given.
        let code = try PairingCode.parse(url(resolver: "https://resolver.example.com/"))
        XCTAssertEqual(code.resolverURL, "https://resolver.example.com/")
    }

    func test_httpResolver_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(resolver: "http://resolver.example.com"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidResolver)
        }
    }

    func test_resolverWithQuery_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(resolver: "https://resolver.example.com?x=1"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidResolver)
        }
    }

    func test_resolverWithFragment_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(resolver: "https://resolver.example.com#frag"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidResolver)
        }
    }

    func test_resolverWithUserinfo_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(resolver: "https://user:pw@resolver.example.com"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidResolver)
        }
    }

    func test_resolverWithoutHost_rejected() {
        XCTAssertThrowsError(try PairingCode.parse(url(resolver: "https://"))) {
            XCTAssertEqual($0 as? PairingCode.ParseError, .invalidResolver)
        }
    }

    func test_resolverRoundTripsThroughURLString() throws {
        let original = try PairingCode.parse(url(resolver: "https://cdn.example.com/iterm2/resolve"))
        let rebuilt = try PairingCode.parse(original.urlString())
        XCTAssertEqual(original, rebuilt)
        XCTAssertEqual(rebuilt.resolverURL, "https://cdn.example.com/iterm2/resolve")
        XCTAssertNil(rebuilt.relayOrigin)
    }

    func test_urlStringEmitsV2AndResolver() throws {
        let code = PairingCode(responderStaticPublicKey: Data(repeating: 0, count: 32),
                               pairingID: "f7c2a1b9",
                               resolverURL: "https://resolver.example.com/")
        let s = code.urlString()
        XCTAssertTrue(s.contains("v=2"), s)
        XCTAssertTrue(s.contains("resolver="), s)
        XCTAssertFalse(s.contains("relay="), s)
    }

    func test_v2IgnoresStrayRelay() throws {
        // The mode is exclusive: in a v2 code a stray relay= is ignored, not
        // adopted, so the code can never be self-contradictory.
        let escapedRelay = "https://relay.example.com".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let escapedResolver = "https://resolver.example.com".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let s = "iterm2://pair?v=2&proto=\(PairingCode.supportedProtocol)&rs=\(validKeyB64URL)"
            + "&pid=f7c2a1b9&relay=\(escapedRelay)&resolver=\(escapedResolver)"
        let code = try PairingCode.parse(s)
        XCTAssertEqual(code.resolverURL, "https://resolver.example.com")
        XCTAssertNil(code.relayOrigin)
    }
}

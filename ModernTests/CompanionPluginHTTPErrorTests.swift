//
//  CompanionPluginHTTPErrorTests.swift
//  ModernTests
//
//  The companion plugin forwards the native HTTP error string verbatim, so the
//  native side encodes URLSession's error code alongside its message and the
//  callers rebuild a URLError. That lets the Mac explain a failed shard-map
//  fetch as specifically as the phone does (a DNS failure vs. a timeout).
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionPluginHTTPErrorTests: XCTestCase {
    func testURLErrorRoundTripsWithItsCodeAndMessage() {
        let original = URLError(.cannotFindHost,
                                userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."])

        let decoded = CompanionPluginHTTPError.decode(CompanionPluginHTTPError.encode(original))

        XCTAssertEqual(decoded.urlError?.code, .cannotFindHost)
        XCTAssertEqual(decoded.message, "A server with the specified hostname could not be found.")
        XCTAssertEqual(decoded.urlError?.localizedDescription, decoded.message)
    }

    func testTimeoutRoundTrips() {
        let original = URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        XCTAssertEqual(CompanionPluginHTTPError.decode(CompanionPluginHTTPError.encode(original)).urlError?.code,
                       .timedOut)
    }

    func testOtherErrorsAreJustTheirMessage() {
        let other = NSError(domain: "SomeDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "Something else."])

        let encoded = CompanionPluginHTTPError.encode(other)
        let decoded = CompanionPluginHTTPError.decode(encoded)

        XCTAssertEqual(encoded, "Something else.")
        XCTAssertNil(decoded.urlError)
        XCTAssertEqual(decoded.message, "Something else.")
    }

    func testPlainStringsDecodeToThemselves() {
        // HTTP statuses and messages from before this encoding existed.
        for plain in ["HTTP 503", "invalid url", "URLError is a type", "URLError x: y"] {
            let decoded = CompanionPluginHTTPError.decode(plain)
            XCTAssertNil(decoded.urlError, plain)
            XCTAssertEqual(decoded.message, plain)
        }
    }
}

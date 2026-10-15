//
//  AIPluginValidateLoggingTests.swift
//  iTerm2
//
//  With the AI plugin missing, Settings > AI probes validate() every few
//  seconds. Each probe must not add another line to the retrospective log;
//  the load failure is logged once when it is first seen. QA finding F-379.
//

import XCTest
@testable import iTerm2SharedARC

final class AIPluginValidateLoggingTests: XCTestCase {
    private func occurrences(of needle: String, in haystack: String) -> Int {
        return haystack.components(separatedBy: needle).count - 1
    }

    override func tearDown() {
        iTermAIClient.validationPluginResultForTesting = nil
        super.tearDown()
    }

    func testRepeatedFailedValidationDoesNotFloodRetrospectiveLog() throws {
        iTermAIClient.validationPluginResultForTesting = .failure(PluginError(reason: "Plugin not found"))
        let marker = "validate()"
        let before = occurrences(of: marker, in: iTermRetrospectiveLogString())
        for _ in 0..<3 {
            XCTAssertThrowsError(try iTermAIClient.instance.validate())
        }
        let after = occurrences(of: marker, in: iTermRetrospectiveLogString())
        XCTAssertEqual(after, before)
    }
}

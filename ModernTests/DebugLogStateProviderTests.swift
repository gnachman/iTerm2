//
//  DebugLogStateProviderTests.swift
//  iTerm2
//
//  Subsystems can add a description of their state to the header and footer of debug logs.
//

import XCTest
@testable import iTerm2SharedARC

final class DebugLogStateProviderTests: XCTestCase {
    func testRegisteredStateAppearsInTheDebugLogHeader() {
        let name = "DebugLogStateProviderTests-\(UUID().uuidString)"
        iTermRegisterDebugLogStateProvider(name) {
            return "everything is fine"
        }
        let header = iTermDebugLogHeaderString() ?? ""
        XCTAssertTrue(header.contains(name))
        XCTAssertTrue(header.contains("everything is fine"))
    }
}

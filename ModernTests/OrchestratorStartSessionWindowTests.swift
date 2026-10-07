//
//  OrchestratorStartSessionWindowTests.swift
//  iTerm2 ModernTests
//
//  The window choices start_session accepts, including a floating pane.
//

import XCTest
@testable import iTerm2SharedARC

final class OrchestratorStartSessionWindowTests: XCTestCase {
    private func decode(_ json: String) throws -> StartSessionArgs {
        return try JSONDecoder().decode(StartSessionArgs.self, from: Data(json.utf8))
    }

    func testEveryWindowChoiceDecodes() throws {
        for (raw, choice) in [("new", SpawnWindowChoice.new),
                              ("current", .current),
                              ("tab", .tab),
                              ("floating", .floating)] {
            let args = try decode(#"{"profile":null,"command":null,"cwd":null,"window":"\#(raw)"}"#)
            XCTAssertEqual(args.window, choice, raw)
        }
        XCTAssertNil(try decode(#"{"profile":null,"command":null,"cwd":null,"window":null}"#).window)
    }
}

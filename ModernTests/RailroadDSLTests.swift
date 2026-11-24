//
//  RailroadDSLTests.swift
//  iTerm2
//
//  Fixture parsing and byte-identical Rust railroad_dsl SVG coverage.
//

import Foundation
import XCTest
@testable import iTerm2SharedARC

final class RailroadDSLTests: XCTestCase {
    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tests/railroad")
    }

    private func fixtureURLs() throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: fixtureRoot.appendingPathComponent("dsl"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "dsl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(urls.isEmpty, "Railroad DSL fixture directory must not be empty")
        return urls
    }

    // Port of railroad_dsl's examples_must_parse, including regex-derived fixtures.
    func test_examples_must_parse() throws {
        for url in try fixtureURLs() {
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertNoThrow(try RailroadDSL.parse(source), url.lastPathComponent)
            XCTAssertTrue(RailroadDSL.isValid(source), url.lastPathComponent)
        }
    }

    func test_invalid_inputs_are_rejected() {
        for source in ["", "[", "\"unterminated", "<>", "{}", "'a' ,", "a"] {
            XCTAssertThrowsError(try RailroadDSL.parse(source), source) { error in
                XCTAssertTrue(error is RailroadDSL.ParseError, "\(source): \(error)")
            }
            XCTAssertFalse(RailroadDSL.isValid(source), source)
        }
    }

    func test_escaped_quote_is_preserved_in_terminal_label() throws {
        let nodes = try RailroadDSL.parse("\"a\\\"b\"")
        XCTAssertEqual(nodes.count, 1)
        let terminal = try XCTUnwrap(nodes.first as? RailroadTerminal)
        XCTAssertEqual(terminal.label, "a\"b")
    }

    func test_all_fixtures_match_rust_svg_byte_for_byte() throws {
        let css = try String(contentsOf: fixtureRoot.appendingPathComponent("light.css"), encoding: .utf8)
        for url in try fixtureURLs() {
            let name = url.deletingPathExtension().lastPathComponent
            let source = try String(contentsOf: url, encoding: .utf8)
            let expectedURL = fixtureRoot.appendingPathComponent("svg").appendingPathComponent(name + ".svg")
            let expected = try Data(contentsOf: expectedURL)
            let actual = try RailroadDSL.svg(source, css: css)
            // Compare UTF-8 bytes rather than Swift String's canonical-equivalence comparison.
            XCTAssertEqual(Data(actual.utf8), expected, name)
        }
    }
}

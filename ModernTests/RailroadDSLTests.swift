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
    private struct Fixture: Decodable {
        var name: String
        var regex: String?
        var dsl: String
        var svg: String
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Diagrams rendered by the Rust railroad_dsl library (railroad crate 0.3.12)
    /// with the light theme, before the Swift port replaced it. Each has the DSL
    /// it rendered and, for regex-derived ones, the regex ICURegexToRailroadConverter
    /// turned into that DSL.
    private func fixtures() throws -> [Fixture] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("tests/railroad/fixtures.json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
        XCTAssertFalse(fixtures.isEmpty, "Railroad fixtures must not be empty")
        return fixtures
    }

    // Port of railroad_dsl's examples_must_parse, including regex-derived fixtures.
    func test_examples_must_parse() throws {
        for fixture in try fixtures() {
            XCTAssertNoThrow(try RailroadDSL.parse(fixture.dsl), fixture.name)
            XCTAssertTrue(RailroadDSL.isValid(fixture.dsl), fixture.name)
        }
    }

    func test_invalid_inputs_are_rejected() {
        // Rust's pest grammar rejects leading whitespace but allows trailing whitespace.
        XCTAssertTrue(RailroadDSL.isValid("\"a\"\n"))
        for source in ["", "[", "\"unterminated", "<>", "{}", "'a' ,", "a", " \"a\"", "\n!", " "] {
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
        let css = try String(contentsOf: repoRoot.appendingPathComponent("sources/RegexVisualization/railroad-light.css"),
                             encoding: .utf8)
        for fixture in try fixtures() {
            let actual = try RailroadDSL.svg(fixture.dsl, css: css)
            // Compare UTF-8 bytes rather than Swift String's canonical-equivalence comparison.
            XCTAssertEqual(Data(actual.utf8), Data(fixture.svg.utf8), fixture.name)
        }
    }
}

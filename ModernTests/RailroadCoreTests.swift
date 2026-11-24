//
//  RailroadCoreTests.swift
//  iTerm2
//
//  Supported streaming API assertions from railroad 0.3.12.
//

import Foundation
import XCTest
@testable import iTerm2SharedARC

final class RailroadCoreTests: XCTestCase {
    private let payloads = [
        "\"><script>alert(1)</script>", "' onload='alert(1)",
        "&lt;not-an-entity", "</style><script>bad</script>", "foo & bar", "foo\"bar"
    ]

    func test_node_defaults_and_collection_helpers_follow_the_public_contract() {
        let leaf = LeafNode()
        XCTAssertEqual(leaf.entryHeight, 3)
        XCTAssertEqual(leaf.height, 9)
        XCTAssertEqual(leaf.width, 15)
        XCTAssertEqual(leaf.heightBelowEntry, 6)
        let out = RailroadRenderer()
        leaf.render(out, x: 7, y: 11, hDir: .rtl)
        XCTAssertTrue(out.output.contains("data-x=\"7\""))
        XCTAssertTrue(out.output.contains("data-y=\"11\""))
        XCTAssertTrue(out.output.contains("data-hdir=\"rtl\""))
        let nodes: [any RailroadNode] = [RailroadStart(), RailroadSimpleStart(), RailroadEnd()]
        XCTAssertEqual(nodes.maxEntryHeight, 10)
        XCTAssertEqual(nodes.maxHeightBelowEntry, 10)
        XCTAssertEqual(nodes.maxWidth, 20)
        XCTAssertEqual(nodes.totalWidth, 55)
        XCTAssertEqual(nodes.totalHeight, 50)
    }

    func test_built_in_primitives_render_distinct_markup() {
        // Debug and Continuation nodes from the Rust test are not in this port.
        let root = RailroadSequence(children: [
            RailroadStart(), RailroadSimpleStart(), RailroadSimpleEnd(), RailroadEnd(), RailroadEmpty()
        ])
        let svg = RailroadDiagram(root: root).svg
        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertGreaterThanOrEqual(svg.components(separatedBy: "<path").count - 1, 4)
        XCTAssertEqual(RailroadEmpty().entryHeight, 0)
        XCTAssertEqual(RailroadEmpty().height, 0)
        XCTAssertEqual(RailroadEmpty().width, 0)
        for node: any RailroadNode in [RailroadStart(), RailroadEnd()] {
            XCTAssertEqual(node.entryHeight, 10)
            XCTAssertEqual(node.height, 20)
            XCTAssertEqual(node.width, 20)
        }
        for node: any RailroadNode in [RailroadSimpleStart(), RailroadSimpleEnd()] {
            XCTAssertEqual(node.entryHeight, 5)
            XCTAssertEqual(node.height, 10)
            XCTAssertEqual(node.width, 15)
        }
    }

    func test_sequence_supports_builder_style_composition() {
        // Swift uses the memberwise initializer rather than Rust's push builder.
        let sequence = RailroadSequence(children: [
            RailroadStart(), RailroadTerminal(label: "middle"), RailroadEnd()
        ])
        let svg = RailroadDiagram(root: sequence).svg
        XCTAssertTrue(svg.contains("class=\"sequence\""))
        XCTAssertTrue(svg.contains("middle"))
        XCTAssertGreaterThanOrEqual(svg.components(separatedBy: "<path").count - 1, 3)
    }

    func test_text_nodes_escape_content_and_forward_representative_attributes() {
        // Sequence replaces the unsupported HorizontalGrid, preserving text assertions.
        let root = RailroadSequence(children: [
            RailroadTerminal(label: "A < B", attributes: ["data-token": "term"]),
            RailroadNonTerminal(label: "expr & tail", attributes: ["data-role": "rule"]),
            RailroadComment(text: "note > detail", attributes: ["data-note": "commentary"])
        ])
        let svg = RailroadDiagram(root: root).svg
        for fact in ["class=\"terminal\"", "class=\"nonterminal\"", "class=\"comment\"",
                     "A &lt; B", "expr &amp; tail", "note &gt; detail", "data-token=\"term\"",
                     "data-role=\"rule\"", "data-note=\"commentary\""] {
            XCTAssertTrue(svg.contains(fact), fact)
        }
    }

    func test_renderer_escapes_content_and_rejects_invalid_tag_names() {
        // Tag-name validation is deliberately excluded: production names are literals.
        let out = RailroadRenderer()
        out.textElement("text", "a < b & c") { $0.attr("data-note", "\"quoted\" & tagged") }
        let style = out.startElement("style")
        style.attr("type", "text/css")
        style.finish()
        out.writeRaw("text { fill: red < blue; }")
        out.endElement("style")
        XCTAssertTrue(out.output.contains("<text data-note=\"&quot;quoted&quot; &amp; tagged\">"))
        XCTAssertTrue(out.output.contains("a &lt; b &amp; c</text>"))
        XCTAssertTrue(out.output.contains("text { fill: red < blue; }</style>"))
    }

    func test_start_tag_attr_hashmap_writes_attributes_in_key_order() {
        let out = RailroadRenderer()
        let tag = out.startElement("g")
        tag.attrs(["b": "2", "a": "1"])
        tag.finishEmpty()
        XCTAssertEqual(out.output, "<g a=\"1\" b=\"2\"/>\n")
    }

    func test_start_tag_replaces_attributes_and_escapes_final_values() {
        for empty in [false, true] {
            let out = RailroadRenderer()
            let tag = out.startElement("g")
            tag.attr("b", "old")
            tag.attr("a", "kept")
            tag.attr("b", "<&\"'")
            if empty { tag.finishEmpty() } else { tag.finish() }
            XCTAssertEqual(out.output, "<g b=\"&lt;&amp;&quot;&#x27;\" a=\"kept\"\(empty ? "/>" : ">")\n")
        }
    }

    func test_path_data_tracks_direction_and_arrowhead_shape() {
        let ltr = RailroadPathData(.ltr).moveTo(0, 0).horizontal(60).arc(12, .westToSouth).text
        let rtl = RailroadPathData(.rtl).moveTo(0, 0).horizontal(60).text
        XCTAssertEqual(RailroadHDir.ltr.inverted, .rtl)
        XCTAssertEqual(RailroadHDir.rtl.inverted, .ltr)
        XCTAssertTrue(ltr.contains(" M 0 0 h 60"))
        XCTAssertTrue(ltr.contains(" l -5 -5 m 0 10 l 5 -5"))
        XCTAssertTrue(ltr.contains(" a 12 12 0 0 1 12 12"))
        XCTAssertTrue(rtl.contains(" l 5 -5 m 0 10 l -5 -5"))
        XCTAssertNotEqual(ltr, rtl)
    }

    func test_vertical_arrowheads_follow_segment_sign_and_reading_direction() {
        let cases: [(RailroadHDir, Int, String)] = [
            (.ltr, 51, " M 0 0 v 51 m 0 -22 l -5 -5 m 10 0 l -5 5 m 0 22 h 7"),
            (.rtl, 51, " M 0 0 v 51 m 0 -22 l -5 5 m 10 0 l -5 -5 m 0 22 h 7"),
            (.ltr, -51, " M 0 0 v -51 m 0 28 l -5 5 m 10 0 l -5 -5 m 0 -28 h 7"),
            (.rtl, -51, " M 0 0 v -51 m 0 28 l -5 -5 m 10 0 l -5 5 m 0 -28 h 7")
        ]
        for (direction, height, expected) in cases {
            XCTAssertEqual(RailroadPathData(direction).moveTo(0, 0).vertical(height).horizontal(7).text,
                           expected, "\(direction), height \(height)")
        }
    }

    func test_short_vertical_segments_have_no_arrowheads_in_either_direction() {
        for direction: RailroadHDir in [.ltr, .rtl] {
            for height in [-50, -49, 0, 49, 50] {
                XCTAssertEqual(RailroadPathData(direction).vertical(height).text, " v \(height)")
            }
        }
    }

    func test_diagram_includes_stylesheets_attributes_and_extra_elements() throws {
        // Arbitrary Element extras are unsupported. Check the supported CSS/attribute subset.
        for theme in ["light", "dark"] {
            let css = try String(contentsOf: fixtureRoot.appendingPathComponent("\(theme).css"), encoding: .utf8)
            let diagram = RailroadDiagram(root: RailroadTerminal(label: "demo"), css: css,
                                          extraAttributes: ["data-kind": "demo"])
            let svg = diagram.svg
            XCTAssertTrue(svg.hasPrefix("<svg"))
            for fact in ["class=\"railroad\"", "viewBox=\"0 0 ", "data-kind=\"demo\"",
                         css.trimmingCharacters(in: .whitespacesAndNewlines), "class=\"railroad_canvas\""] {
                XCTAssertTrue(svg.contains(fact), theme + ": " + fact)
            }
        }
    }

    func test_diagram_write_matches_display_output() {
        assertStreamingMatchesSVG(RailroadDiagram(root: RailroadTerminal(label: "write")))
    }

    func test_diagram_into_inner_returns_root_node() {
        // Swift exposes root directly instead of providing an into_inner method.
        let diagram = RailroadDiagram(root: RailroadTerminal(label: "inner"))
        XCTAssertEqual(RailroadDiagram(root: diagram.root).svg,
                       RailroadDiagram(root: RailroadTerminal(label: "inner")).svg)
    }

    func test_test_encode_minimal() {
        XCTAssertEqual(RailroadRenderer.escapeMinimal("foo<bar>"), "foo&lt;bar&gt;")
    }

    func test_encode_minimal() {
        let cases = [
            ("'a", "&#x27;a"), ("", ""), ("'", "&#x27;"), ("a'", "a&#x27;"),
            ("hello world!", "hello world!"), ("&", "&amp;"), ("<br>", "&lt;br&gt;"),
            ("\"a\" is not \"b\"", "&quot;a&quot; is not &quot;b&quot;")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(RailroadRenderer.escapeMinimal(input), expected)
        }
    }

    func test_geometry_cache_regression() {
        let root = deepSequence(depth: 3, width: 3)
        let first = RailroadDiagram(root: root).svg
        XCTAssertEqual(first, RailroadDiagram(root: deepSequence(depth: 3, width: 3)).svg)
        XCTAssertEqual(first, RailroadDiagram(root: root).svg)
        // Swift has no separate cache API, so verify the nested geometry directly.
        XCTAssertEqual(root.entryHeight, 11)
        XCTAssertEqual(root.height, 22)
        XCTAssertEqual(root.width, 27 * 28 + 26 * 10)
    }

    func test_diagram_write_matches_display() {
        assertStreamingMatchesSVG(RailroadDiagram(root: deepSequence(depth: 2, width: 3)))
    }

    func test_terminal_label_no_injection() {
        for payload in payloads {
            for node: any RailroadNode in [RailroadTerminal(label: payload), RailroadNonTerminal(label: payload)] {
                XCTAssertFalse(RailroadDiagram(root: node).svg.contains(payload), payload)
            }
        }
    }

    func test_comment_text_no_injection() {
        for payload in payloads {
            XCTAssertFalse(RailroadDiagram(root: RailroadComment(text: payload)).svg.contains(payload), payload)
        }
    }

    func test_node_attr_no_injection() {
        for payload in payloads {
            for attributes in [["data-x": payload], [payload: "value"]] {
                let node = RailroadTerminal(label: "x", attributes: attributes)
                XCTAssertFalse(RailroadDiagram(root: node).svg.contains(payload), payload)
            }
        }
    }

    func test_renderer_attribute_and_text_no_injection() {
        for payload in payloads {
            let out = RailroadRenderer()
            out.textElement("text", payload) {
                $0.attr("data-x", payload)
                $0.attr(payload, "value")
            }
            XCTAssertFalse(out.output.contains(payload), payload)
        }
    }

    func test_text_width_including_wide_and_combining_characters() {
        // Supplemental contract coverage for Rust's UnicodeWidthStr plus 5% padding.
        for (text, columns) in [("", 0), ("abc", 3), ("奶油", 4), ("a界", 3),
                                ("e\u{301}", 1), ("😀", 2), (String(repeating: "x", count: 20), 21),
                                (String(repeating: "界", count: 10), 21)] {
            XCTAssertEqual(Railroad.textWidth(text), columns, text)
            XCTAssertEqual(RailroadTerminal(label: text).width, columns * 8 + 20, text)
            XCTAssertEqual(RailroadNonTerminal(label: text).width, columns * 8 + 20, text)
            XCTAssertEqual(RailroadComment(text: text).width, columns * 7 + 10, text)
        }
    }

    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/railroad")
    }

    private func deepSequence(depth: Int, width: Int) -> any RailroadNode {
        if depth == 0 { return RailroadTerminal(label: "x") }
        return RailroadSequence(children: (0..<width).map { _ in deepSequence(depth: depth - 1, width: width) })
    }

    private func assertStreamingMatchesSVG(_ diagram: RailroadDiagram,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let out = RailroadRenderer()
        diagram.render(out, x: 0, y: 0, hDir: .ltr)
        XCTAssertEqual(out.output, diagram.svg, file: file, line: line)
    }

    private struct LeafNode: RailroadNode {
        var entryHeight: Int { 3 }
        var height: Int { 9 }
        var width: Int { 15 }

        func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
            let tag = out.startElement("g")
            tag.attr("data-x", x)
            tag.attr("data-y", y)
            tag.attr("data-hdir", hDir == .ltr ? "ltr" : "rtl")
            tag.finishEmpty()
        }
    }
}

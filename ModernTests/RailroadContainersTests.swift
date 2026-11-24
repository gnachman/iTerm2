//
//  RailroadContainersTests.swift
//  iTerm2
//
//  Stack and Choice assertions ported from railroad 0.3.12 tests/api_containers.rs.
//

import XCTest
@testable import iTerm2SharedARC

final class RailroadContainersTests: XCTestCase {
    func test_stack_and_choice_render_container_markup_and_children() {
        let stack = RailroadStack(children: [
            RailroadTerminal(label: "top"),
            RailroadTerminal(label: "bottom")
        ], attributes: ["data-layout": "stack"])
        let stackSVG = RailroadDiagram(root: stack).svg
        XCTAssertTrue(stackSVG.contains("class=\"stack\""))
        XCTAssertTrue(stackSVG.contains("data-layout=\"stack\""))
        XCTAssertTrue(stackSVG.contains("top"))
        XCTAssertTrue(stackSVG.contains("bottom"))

        let choice = RailroadChoice(children: [
            RailroadTerminal(label: "one"),
            RailroadTerminal(label: "two"),
            RailroadEmpty()
        ], attributes: ["data-layout": "choice"])
        let choiceSVG = RailroadDiagram(root: choice).svg
        XCTAssertTrue(choiceSVG.contains("class=\"choice\""))
        XCTAssertTrue(choiceSVG.contains("data-layout=\"choice\""))
        XCTAssertTrue(choiceSVG.contains("one"))
        XCTAssertTrue(choiceSVG.contains("two"))
        XCTAssertGreaterThanOrEqual(choiceSVG.components(separatedBy: "<path").count - 1, 3)
    }

    func test_stack_without_return_path_has_no_padding() {
        let terminal = RailroadTerminal(label: "one")
        for (stack, expected) in [
            (RailroadStack(children: []), 0),
            (RailroadStack(children: [terminal]), terminal.width)
        ] {
            // Swift exposes the computed geometry directly, rather than through
            // Rust's separate width() and compute_geometry().width accessors.
            XCTAssertEqual(stack.width, expected)
        }
    }

    func test_stack_inter_child_connector_stops_at_narrow_child_entry() {
        let sequence = RailroadSequence(children: [
            RailroadSimpleStart(),
            RailroadStack(children: [RailroadEmpty(), NarrowDebugNode()]),
            RailroadSimpleEnd()
        ])
        let svg = RailroadDiagram(root: sequence).svg
        XCTAssertTrue(svg.contains(
            "<path d=\" M 59 15 a 12 12 0 0 1 12 12 v 0 a 12 12 0 0 1 -12 12 h 0 a 12 12 0 0 0 -12 12 v 0 v 0 a 12 12 0 0 0 12 12\"/>"
        ))
        XCTAssertFalse(svg.contains(
            "<path d=\" M 59 15 a 12 12 0 0 1 12 12 v 0 a 12 12 0 0 1 -12 12 h 0 a 12 12 0 0 0 -12 12 v 0 v 0 a 12 12 0 0 0 12 12 h 12\"/>"
        ))
        XCTAssertTrue(svg.contains("<rect x=\"59\" y=\"58\" height=\"25\" width=\"4\""))
    }

    // Only the geometry and rectangle of Rust's Debug::new(5, 25, 4)
    // participate in the regression assertions above.
    private struct NarrowDebugNode: RailroadNode {
        var entryHeight: Int { 5 }
        var height: Int { 25 }
        var width: Int { 4 }

        func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
            out.rect(x: x, y: y, width: width, height: height)
        }
    }
}

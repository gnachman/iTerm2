import XCTest
@testable import iTerm2SharedARC

final class RailroadWrappersTests: XCTestCase {
    // Rust: optional_repeat_and_labeled_box_render_distinct_structures.
    func test_optional_repeat_and_labeled_box_render_distinct_structures() {
        let optionalSVG = RailroadDiagram(root: RailroadOptional(inner: RailroadTerminal(label: "maybe"))).svg
        XCTAssertTrue(optionalSVG.contains("class=\"optional\""))
        XCTAssertTrue(optionalSVG.contains("maybe"))

        let repeatSVG = RailroadDiagram(root: RailroadRepeat(inner: RailroadTerminal(label: "item"),
                                                             repeat: RailroadComment(text: ","))).svg
        XCTAssertTrue(repeatSVG.contains("class=\"repeat\""))
        XCTAssertTrue(repeatSVG.contains("item"))
        XCTAssertTrue(repeatSVG.contains(","))

        let labeledSVG = RailroadDiagram(root: RailroadLabeledBox(inner: RailroadTerminal(label: "body"),
                                                                 label: RailroadComment(text: "group"))).svg
        XCTAssertTrue(labeledSVG.contains("class=\"labeledbox\""))
        XCTAssertTrue(labeledSVG.contains("body"))
        XCTAssertTrue(labeledSVG.contains("group"))
        XCTAssertTrue(labeledSVG.contains("<rect"))
        // Rust's Optional<Empty>::default() assertion has no Swift Default counterpart.
    }

    // Rust: labeled_box_without_label_avoids_reserved_label_space.
    func test_labeled_box_without_label_avoids_reserved_label_space() {
        let unlabeled = RailroadLabeledBox(inner: RailroadTerminal(label: "body"), label: RailroadEmpty())
        let labeled = RailroadLabeledBox(inner: RailroadTerminal(label: "body"),
                                        label: RailroadComment(text: "group"))
        XCTAssertLessThan(unlabeled.height, labeled.height)
    }

    // Rust: vertical_and_horizontal_grids_render_their_children (VerticalGrid half).
    func test_vertical_and_horizontal_grids_render_their_children() {
        let vertical = RailroadVerticalGrid(children: [RailroadTerminal(label: "row one"),
                                                       RailroadTerminal(label: "row two")],
                                             attributes: ["data-layout": "vertical"])
        let svg = RailroadDiagram(root: vertical).svg
        XCTAssertTrue(svg.contains("class=\"verticalgrid\""))
        XCTAssertTrue(svg.contains("data-layout=\"vertical\""))
        XCTAssertTrue(svg.contains("row one"))
        XCTAssertTrue(svg.contains("row two"))
    }

    func test_empty_wrappers_and_grid_geometry() {
        let optional = RailroadOptional(inner: RailroadEmpty())
        XCTAssertEqual(optional.width, 48)
        XCTAssertEqual(optional.height, 29)
        XCTAssertEqual(optional.entryHeight, 29)
        let repeated = RailroadRepeat(inner: RailroadEmpty(), repeat: RailroadEmpty())
        XCTAssertEqual(repeated.width, 34)
        XCTAssertEqual(repeated.height, 34)
        XCTAssertEqual(repeated.entryHeight, 5)
        let labeled = RailroadLabeledBox(inner: RailroadEmpty(), label: RailroadEmpty())
        XCTAssertEqual(labeled.width, 0)
        XCTAssertEqual(labeled.height, 0)
        XCTAssertEqual(labeled.entryHeight, 0)
        let grid = RailroadVerticalGrid(children: [])
        XCTAssertEqual(grid.width, 0)
        XCTAssertEqual(grid.height, 0)
        XCTAssertEqual(grid.entryHeight, 0)
        XCTAssertEqual(render(grid), "<g class=\"verticalgrid\">\n</g>\n")
    }

    func test_optional_streaming_path_and_attribute_order() {
        let optional = RailroadOptional(inner: RailroadTerminal(label: "x"),
                                         attributes: ["z": "last", "a": "first", "class": "overridden"])
        XCTAssertEqual(optional.width, 76)
        XCTAssertEqual(optional.height, 40)
        XCTAssertEqual(optional.entryHeight, 29)
        XCTAssertEqual(render(optional, x: 3, y: 7), """
            <g a="first" class="optional" z="last">
            <path d=" M 3 36 h 24 m -24 0 a 12 12 0 0 0 12 -12 v 0 a 12 12 0 0 1 12 -12 h 28 a 12 12 0 0 1 12 12 v 0 a 12 12 0 0 0 12 12 h -24"/>
            <g class="terminal">
            <rect x="27" y="25" height="22" width="28" rx="10" ry="10"/>
            <text x="41" y="41">
            x</text>
            </g>
            </g>

            """)
    }

    func test_repeat_reverses_return_child_direction() {
        let returnChild = RailroadOptional(inner: RailroadTerminal(label: "long return label"))
        let repeated = RailroadRepeat(inner: RailroadTerminal(label: "x"), repeat: returnChild)
        XCTAssertEqual(repeated.width, returnChild.width + 34)
        XCTAssertEqual(repeated.entryHeight, 16)
        XCTAssertEqual(repeated.height, 82)
        let returnX = repeated.width - returnChild.width - 17
        let returnY = repeated.height - returnChild.height - 5
        XCTAssertTrue(render(repeated).contains(render(returnChild, x: returnX, y: returnY, hDir: .rtl)))
        XCTAssertTrue(render(repeated, hDir: .rtl).contains(render(returnChild, x: returnX, y: returnY)))
    }

    func test_labeled_box_and_vertical_grid_placement() {
        let unlabeled = RailroadLabeledBox(inner: RailroadTerminal(label: "body"), label: RailroadEmpty())
        XCTAssertEqual(unlabeled.width, 68)
        XCTAssertEqual(unlabeled.height, 38)
        XCTAssertEqual(unlabeled.entryHeight, 19)
        let labeled = RailroadLabeledBox(inner: RailroadTerminal(label: "body"),
                                        label: RailroadComment(text: "group"))
        XCTAssertEqual(labeled.width, 68)
        XCTAssertEqual(labeled.height, 66)
        XCTAssertEqual(labeled.entryHeight, 47)
        let grid = RailroadVerticalGrid(children: [unlabeled, labeled])
        XCTAssertEqual(grid.width, 68)
        XCTAssertEqual(grid.height, 116)
        XCTAssertEqual(grid.entryHeight, 0)
        let svg = render(grid, x: 3, y: 7)
        XCTAssertTrue(svg.contains(render(unlabeled, x: 3, y: 7)))
        XCTAssertTrue(svg.contains(render(labeled, x: 3, y: 57)))
    }

    private func render(_ node: any RailroadNode, x: Int = 0, y: Int = 0,
                        hDir: RailroadHDir = .ltr) -> String {
        let out = RailroadRenderer()
        node.render(out, x: x, y: y, hDir: hDir)
        return out.output
    }
}

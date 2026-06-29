//
//  iTermLayoutSpecValidatorTests.swift
//  ModernTests
//
//  TDD-driven tests for LayoutSpecValidator — the structural-rules pass
//  that runs after parsing and before live-state resolution. Catches
//  empty splitters, single-child splitters, V-in-V nesting, excessive
//  depth, and duplicate session GUIDs.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLayoutSpecValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func validate(_ spec: LayoutSpec) -> Result<Void, LayoutSpecError> {
        do {
            try LayoutSpecValidator.validate(spec)
            return .success(())
        } catch let error as LayoutSpecError {
            return .failure(error)
        } catch {
            return .failure(.wrongType(path: "?", expected: "LayoutSpecError"))
        }
    }

    private func session(_ guid: String) -> LayoutNode { .session(guid: guid) }

    private func vsplit(_ children: [LayoutNode]) -> LayoutNode {
        .splitter(vertical: true, children: children)
    }

    private func hsplit(_ children: [LayoutNode]) -> LayoutNode {
        .splitter(vertical: false, children: children)
    }

    private func tabSpec(_ id: String, _ root: LayoutNode) -> LayoutTabSpec {
        LayoutTabSpec(tabID: id, root: root)
    }

    private func makeSpec(tabs: [LayoutTabSpec] = [],
                          newTabs: [LayoutNewTabSpec] = [],
                          newWindows: [LayoutNewWindowSpec] = [],
                          closeSessions: [String] = []) -> LayoutSpec {
        LayoutSpec(tabs: tabs,
                   newTabs: newTabs,
                   newWindows: newWindows,
                   closeSessions: closeSessions,
                   closeTabs: [],
                   closeWindows: [])
    }

    // MARK: - Splitter cardinality

    func testSplitterWithZeroChildrenRejected() {
        let spec = makeSpec(tabs: [tabSpec("t1", vsplit([]))])
        guard case .failure(.splitterTooFewChildren(_, let count)) = validate(spec) else {
            XCTFail("expected splitterTooFewChildren"); return
        }
        XCTAssertEqual(count, 0)
    }

    func testSplitterWithOneChildRejected() {
        let spec = makeSpec(tabs: [tabSpec("t1", vsplit([session("a")]))])
        guard case .failure(.splitterTooFewChildren(_, let count)) = validate(spec) else {
            XCTFail("expected splitterTooFewChildren"); return
        }
        XCTAssertEqual(count, 1)
    }

    func testSplitterWithTwoChildrenAccepted() {
        let spec = makeSpec(tabs: [tabSpec("t1", vsplit([session("a"), session("b")]))])
        guard case .success = validate(spec) else {
            XCTFail("expected success"); return
        }
    }

    // MARK: - Same-orientation nesting

    func testVerticalNestedInVerticalRejected() {
        let inner = vsplit([session("a"), session("b")])
        let outer = vsplit([inner, session("c")])
        let spec = makeSpec(tabs: [tabSpec("t1", outer)])
        guard case .failure(.nestedSameOrientation) = validate(spec) else {
            XCTFail("expected nestedSameOrientation"); return
        }
    }

    func testHorizontalNestedInHorizontalRejected() {
        let inner = hsplit([session("a"), session("b")])
        let outer = hsplit([inner, session("c")])
        let spec = makeSpec(tabs: [tabSpec("t1", outer)])
        guard case .failure(.nestedSameOrientation) = validate(spec) else {
            XCTFail("expected nestedSameOrientation"); return
        }
    }

    func testAlternatingOrientationsAccepted() {
        let inner = hsplit([session("a"), session("b")])
        let outer = vsplit([inner, session("c")])
        let spec = makeSpec(tabs: [tabSpec("t1", outer)])
        guard case .success = validate(spec) else {
            XCTFail("expected success"); return
        }
    }

    // MARK: - Depth

    func testExcessiveDepthRejected() {
        // Build a tree of depth 33 by alternating splitters.
        var node: LayoutNode = session("leaf")
        for i in 0 ..< 33 {
            let isVertical = (i % 2 == 0)
            let children = [node, session("dummy_\(i)")]
            node = .splitter(vertical: isVertical, children: children)
        }
        let spec = makeSpec(tabs: [tabSpec("t1", node)])
        guard case .failure(.treeTooDeep) = validate(spec) else {
            XCTFail("expected treeTooDeep"); return
        }
    }

    // MARK: - Duplicate session GUIDs

    func testDuplicateSessionIDInSameTabRejected() {
        let spec = makeSpec(tabs: [tabSpec("t1", vsplit([session("a"), session("a")]))])
        guard case .failure(.duplicateSessionID(let guid)) = validate(spec) else {
            XCTFail("expected duplicateSessionID"); return
        }
        XCTAssertEqual(guid, "a")
    }

    func testDuplicateSessionIDAcrossTabsRejected() {
        let spec = makeSpec(tabs: [
            tabSpec("t1", session("a")),
            tabSpec("t2", session("a")),
        ])
        guard case .failure(.duplicateSessionID) = validate(spec) else {
            XCTFail("expected duplicateSessionID"); return
        }
    }

    func testDuplicateSessionIDBetweenTabAndNewTabRejected() {
        let spec = makeSpec(
            tabs: [tabSpec("t1", session("a"))],
            newTabs: [LayoutNewTabSpec(windowID: "w1", index: nil, root: session("a"))])
        guard case .failure(.duplicateSessionID) = validate(spec) else {
            XCTFail("expected duplicateSessionID"); return
        }
    }
}

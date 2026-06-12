//
//  iTermLayoutTreeRebuildTests.swift
//  ModernTests
//
//  Unit tests for iTermSplitTreeRebuilder.buildTree(layoutTree:frame:idMap:),
//  the GUID-keyed entry that powers the upcoming layout-application API.
//
//  These tests exercise the pure tree-build path (no PTYTab, no
//  view-hierarchy mutation) — that's covered separately at the
//  transaction-coordinator level.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLayoutTreeRebuildTests: XCTestCase {

    // MARK: - Helpers

    private func makeView(_ tag: Int) -> SessionView {
        // tag is informational only — instances are compared by identity (===).
        return SessionView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    }

    // MARK: - Splitter shape

    func testSimpleVerticalSplitterShape() throws {
        let a = makeView(1)
        let b = makeView(2)
        let tree: LayoutTreeNode = .splitter(
            vertical: true,
            children: [.session(guid: "a"), .session(guid: "b")])

        let view = try iTermSplitTreeRebuilder.buildTree(
            layoutTree: tree,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            idMap: ["a": a, "b": b])

        let split = view as! NSSplitView
        XCTAssertTrue(split.isVertical)
        XCTAssertEqual(split.subviews.count, 2)
        XCTAssertTrue(split.subviews[0] === a)
        XCTAssertTrue(split.subviews[1] === b)
    }

    func testHorizontalSplitter() throws {
        let a = makeView(1)
        let b = makeView(2)
        let tree: LayoutTreeNode = .splitter(
            vertical: false,
            children: [.session(guid: "a"), .session(guid: "b")])
        let view = try iTermSplitTreeRebuilder.buildTree(
            layoutTree: tree,
            frame: .zero,
            idMap: ["a": a, "b": b])
        XCTAssertFalse((view as! NSSplitView).isVertical)
    }

    func testNestedMixedOrientations() throws {
        let a = makeView(1)
        let b = makeView(2)
        let c = makeView(3)
        let inner: LayoutTreeNode = .splitter(
            vertical: false,
            children: [.session(guid: "b"), .session(guid: "c")])
        let outer: LayoutTreeNode = .splitter(
            vertical: true,
            children: [.session(guid: "a"), inner])

        let view = try iTermSplitTreeRebuilder.buildTree(
            layoutTree: outer,
            frame: .zero,
            idMap: ["a": a, "b": b, "c": c])

        let split = view as! NSSplitView
        XCTAssertTrue(split.isVertical)
        XCTAssertEqual(split.subviews.count, 2)
        XCTAssertTrue(split.subviews[0] === a)
        let innerSplit = split.subviews[1] as! NSSplitView
        XCTAssertFalse(innerSplit.isVertical)
        XCTAssertTrue(innerSplit.subviews[0] === b)
        XCTAssertTrue(innerSplit.subviews[1] === c)
    }

    // MARK: - Leaf resolution

    func testSessionLeafLooksUpInIdMap() throws {
        let v = makeView(42)
        let tree: LayoutTreeNode = .splitter(
            vertical: true,
            children: [.session(guid: "x"), .session(guid: "y")])

        let view = try iTermSplitTreeRebuilder.buildTree(
            layoutTree: tree,
            frame: .zero,
            idMap: ["x": v, "y": makeView(2)])
        let split = view as! NSSplitView
        XCTAssertTrue(split.subviews[0] === v)
    }

    func testNewSessionLeafUsesProvidedView() throws {
        let pre = makeView(7)
        let tree: LayoutTreeNode = .splitter(
            vertical: true,
            children: [.newSession(view: pre), .session(guid: "x")])
        let other = makeView(8)

        let view = try iTermSplitTreeRebuilder.buildTree(
            layoutTree: tree,
            frame: .zero,
            idMap: ["x": other])
        let split = view as! NSSplitView
        XCTAssertTrue(split.subviews[0] === pre)
        XCTAssertTrue(split.subviews[1] === other)
    }

    // MARK: - Validation errors

    func testMissingSessionGuidThrows() {
        let tree: LayoutTreeNode = .splitter(
            vertical: true,
            children: [.session(guid: "a"), .session(guid: "missing")])
        XCTAssertThrowsError(try iTermSplitTreeRebuilder.buildTree(
            layoutTree: tree,
            frame: .zero,
            idMap: ["a": makeView(1)]))
    }

    func testEmptySplitterThrows() {
        let tree: LayoutTreeNode = .splitter(vertical: true, children: [])
        XCTAssertThrowsError(try iTermSplitTreeRebuilder.buildTree(
            layoutTree: tree, frame: .zero, idMap: [:]))
    }

    func testSingleChildSplitterThrows() {
        let tree: LayoutTreeNode = .splitter(
            vertical: true,
            children: [.session(guid: "a")])
        XCTAssertThrowsError(try iTermSplitTreeRebuilder.buildTree(
            layoutTree: tree, frame: .zero, idMap: ["a": makeView(1)]))
    }

    // MARK: - Bare leaf

    func testBareLeafReturnsSessionView() throws {
        let v = makeView(99)
        let tree: LayoutTreeNode = .session(guid: "only")
        let view = try iTermSplitTreeRebuilder.buildTree(
            layoutTree: tree, frame: .zero, idMap: ["only": v])
        XCTAssertTrue(view === v)
    }
}

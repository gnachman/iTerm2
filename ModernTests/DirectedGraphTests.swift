//
//  DirectedGraphTests.swift
//  iTerm2
//
//  Ported from the legacy iTermDirectedGraphTest.m. Exercises cycle detection.
//

import XCTest
@testable import iTerm2SharedARC

final class DirectedGraphTests: XCTestCase {
    // iTermDirectedGraphCycleDetector takes an untyped graph, so the tests build
    // graphs of AnyObject and add NSString or NSNumber vertexes explicitly.
    private func makeGraph() -> iTermDirectedGraph<AnyObject> {
        return iTermDirectedGraph<AnyObject>()
    }

    private func addEdge(_ graph: iTermDirectedGraph<AnyObject>, from: String, to: String) {
        graph.addEdge(from: from as NSString, to: to as NSString)
    }

    private func addEdge(_ graph: iTermDirectedGraph<AnyObject>, from: Int, to: Int) {
        graph.addEdge(from: NSNumber(value: from), to: NSNumber(value: to))
    }

    private func containsCycle(_ graph: iTermDirectedGraph<AnyObject>) -> Bool {
        return iTermDirectedGraphCycleDetector(directedGraph: graph).containsCycle()
    }

    func testEmptyGraphHasNoCycle() {
        let graph = makeGraph()
        XCTAssertFalse(containsCycle(graph))
    }

    func testLinkedListHasNoCycle() {
        let graph = makeGraph()
        addEdge(graph, from: "a", to: "b")
        addEdge(graph, from: "b", to: "c")
        addEdge(graph, from: "c", to: "d")
        XCTAssertFalse(containsCycle(graph))
    }

    func testForestOfLinkedListsHasNoCycle() {
        let graph = makeGraph()
        addEdge(graph, from: "a", to: "b")
        addEdge(graph, from: "b", to: "c")
        addEdge(graph, from: "c", to: "d")

        addEdge(graph, from: "A", to: "B")
        addEdge(graph, from: "B", to: "C")
        addEdge(graph, from: "C", to: "D")
        XCTAssertFalse(containsCycle(graph))
    }

    func testRingHasCycle() {
        let graph = makeGraph()
        addEdge(graph, from: "a", to: "b")
        addEdge(graph, from: "b", to: "c")
        addEdge(graph, from: "c", to: "d")
        addEdge(graph, from: "d", to: "a")
        XCTAssertTrue(containsCycle(graph))
    }

    func testBigGraphWithCrossLinksHasCycle() {
        let graph = makeGraph()
        for i in 0..<1000 {
            addEdge(graph, from: i, to: i + 1)
        }
        for i in 2000..<3000 {
            addEdge(graph, from: i, to: i + 1)
        }
        // 0->1->...->500->501->...->600->601->...->700->701->...
        //          \                ^                |
        //           \                \_______________)______
        //            \                               |      \
        //             \                              V       \
        //              ->2500->2501->...->2600->...->2800->...->2900->...
        addEdge(graph, from: 500, to: 2500)
        addEdge(graph, from: 2900, to: 600)
        addEdge(graph, from: 700, to: 2800)

        XCTAssertTrue(containsCycle(graph))
    }

    func testEdgesAndVertexesAreRecorded() {
        let graph = makeGraph()
        addEdge(graph, from: "a", to: "b")
        addEdge(graph, from: "a", to: "c")

        let vertexes = Set(graph.vertexes.compactMap { $0 as? String })
        XCTAssertEqual(vertexes, Set(["a", "b", "c"]))

        let successorsOfA = Set((graph.edges["a"]?.allObjects ?? []).compactMap { $0 as? String })
        XCTAssertEqual(successorsOfA, Set(["b", "c"]))
        XCTAssertNil(graph.edges["b"])
    }
}

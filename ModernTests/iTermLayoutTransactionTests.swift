//
//  iTermLayoutTransactionTests.swift
//  ModernTests
//
//  TDD-driven tests for LayoutTransaction — the executor that takes a
//  resolved LayoutPlan and applies it via a `LayoutMutator` protocol.
//  The protocol is mocked here so we can verify the executor performs
//  the right sequence of operations (detach, create, attach, close)
//  without touching real PTYTab/PTYSession state.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLayoutTransactionTests: XCTestCase {

    // MARK: - RecordingMutator

    /// Records every call into a string log so tests can assert on the
    /// exact sequence of operations.
    final class RecordingMutator: LayoutMutator {
        private(set) var log: [String] = []
        var sessionGUIDsByTab: [String: [String]] = [:]
        var newSessionsToCreate: [String] = []   // GUIDs to assign to new sessions, in order

        func beginTransaction() { log.append("begin") }
        func endTransaction() { log.append("end") }

        func detachSession(_ guid: String, fromTab tabGUID: String) throws {
            log.append("detach \(guid) from \(tabGUID)")
            sessionGUIDsByTab[tabGUID]?.removeAll { $0 == guid }
        }

        func tabContaining(sessionGUID: String) -> String? {
            for (tab, list) in sessionGUIDsByTab where list.contains(sessionGUID) {
                return tab
            }
            return nil
        }

        func createNewSession(profileGUID: String, command: String?) throws -> String {
            let guid = newSessionsToCreate.isEmpty
                ? "new-\(log.count)"
                : newSessionsToCreate.removeFirst()
            log.append("create-session \(guid) profile=\(profileGUID) cmd=\(command ?? "<none>")")
            return guid
        }

        func attachTree(toTab tabGUID: String, layout: LayoutNode) throws {
            log.append("attach-tree to \(tabGUID): \(describe(layout))")
            sessionGUIDsByTab[tabGUID] = collectGUIDs(layout)
        }

        func createNewTab(windowGUID: String, index: Int?, layout: LayoutNode) throws -> String {
            let guid = "newtab-\(log.count)"
            log.append("new-tab \(guid) in \(windowGUID) idx=\(index ?? -1): \(describe(layout))")
            sessionGUIDsByTab[guid] = collectGUIDs(layout)
            return guid
        }

        func createNewWindow(profileGUID: String, frame: NSRect?, layout: LayoutNode) throws -> String {
            let guid = "newwin-\(log.count)"
            log.append("new-window \(guid) profile=\(profileGUID): \(describe(layout))")
            return guid
        }

        func terminateSession(_ guid: String) throws {
            log.append("terminate \(guid)")
        }

        func closeTab(_ tabGUID: String) throws {
            log.append("close-tab \(tabGUID)")
        }

        func closeWindow(_ windowGUID: String) throws {
            log.append("close-window \(windowGUID)")
        }

        // MARK: - Helpers

        private func describe(_ node: LayoutNode) -> String {
            switch node {
            case .splitter(let v, let children):
                let dir = v ? "V" : "H"
                return "\(dir)[\(children.map(describe).joined(separator: ","))]"
            case .session(let guid):
                return guid
            case .newSession(let info):
                return "NEW(\(info.profileGUID))"
            }
        }

        private func collectGUIDs(_ node: LayoutNode) -> [String] {
            switch node {
            case .splitter(_, let children):
                return children.flatMap(collectGUIDs)
            case .session(let guid):
                return [guid]
            case .newSession(let info):
                return ["new-from-\(info.profileGUID)"]
            }
        }
    }

    // MARK: - Helpers

    private func session(_ guid: String) -> LayoutNode { .session(guid: guid) }
    private func vsplit(_ children: [LayoutNode]) -> LayoutNode {
        .splitter(vertical: true, children: children)
    }

    // MARK: - Empty plan

    func testEmptyPlanBeginsAndEnds() throws {
        let mutator = RecordingMutator()
        let plan = LayoutPlan(tabUpdates: [],
                              newTabs: [],
                              newWindows: [],
                              closeSessions: [],
                              closeTabs: [],
                              closeWindows: [])
        try LayoutTransaction.execute(plan: plan, mutator: mutator)
        XCTAssertEqual(mutator.log, ["begin", "end"])
    }

    // MARK: - Single-tab reshape

    func testSingleTabReshapeEmitsAttach() throws {
        let mutator = RecordingMutator()
        let plan = LayoutPlan(
            tabUpdates: [.init(tabGUID: "t1", root: vsplit([session("a"), session("b")]))],
            newTabs: [], newWindows: [],
            closeSessions: [], closeTabs: [], closeWindows: [])
        try LayoutTransaction.execute(plan: plan, mutator: mutator)
        XCTAssertTrue(mutator.log.contains(where: { $0.hasPrefix("attach-tree to t1") }))
    }

    // MARK: - Cross-tab move

    /// A session moving from t1 to t2 must be detached from t1 *before*
    /// either tab is reattached, so it doesn't get terminated as an
    /// orphan in t1's reattach phase.
    func testCrossTabMoveDetachesBeforeAttach() throws {
        let mutator = RecordingMutator()
        mutator.sessionGUIDsByTab = ["t1": ["a", "b"], "t2": ["c"]]
        let plan = LayoutPlan(
            tabUpdates: [
                .init(tabGUID: "t1", root: session("a")),
                .init(tabGUID: "t2", root: vsplit([session("c"), session("b")])),
            ],
            newTabs: [], newWindows: [],
            closeSessions: [], closeTabs: [], closeWindows: [])
        try LayoutTransaction.execute(plan: plan, mutator: mutator)

        let detachIndex = mutator.log.firstIndex(of: "detach b from t1") ?? -1
        let attachT1Index = mutator.log.firstIndex(where: { $0.hasPrefix("attach-tree to t1") }) ?? -1
        let attachT2Index = mutator.log.firstIndex(where: { $0.hasPrefix("attach-tree to t2") }) ?? -1
        XCTAssertGreaterThanOrEqual(detachIndex, 0, "expected detach for moved session")
        XCTAssertLessThan(detachIndex, attachT1Index)
        XCTAssertLessThan(detachIndex, attachT2Index)
    }

    // MARK: - close_sessions

    func testCloseSessionsTerminate() throws {
        let mutator = RecordingMutator()
        let plan = LayoutPlan(
            tabUpdates: [],
            newTabs: [], newWindows: [],
            closeSessions: ["x", "y"],
            closeTabs: [], closeWindows: [])
        try LayoutTransaction.execute(plan: plan, mutator: mutator)
        XCTAssertTrue(mutator.log.contains("terminate x"))
        XCTAssertTrue(mutator.log.contains("terminate y"))
    }

    // MARK: - Order: closes happen after attachments

    /// close_sessions runs AFTER the attach phase so a session can
    /// legally appear in a new layout AND be terminated in the same
    /// call. (Previously close ran first to dodge a double-terminate
    /// from `replaceViewHierarchy`'s implicit auto-termination, but
    /// auto-termination has been removed: the rebuilder no longer
    /// terminates implicitly, so the close phase can come last.)
    func testCloseSessionsAfterAttachments() throws {
        let mutator = RecordingMutator()
        mutator.sessionGUIDsByTab = ["t1": ["a", "b"]]
        let plan = LayoutPlan(
            tabUpdates: [.init(tabGUID: "t1", root: session("a"))],
            newTabs: [], newWindows: [],
            closeSessions: ["b"],
            closeTabs: [], closeWindows: [])
        try LayoutTransaction.execute(plan: plan, mutator: mutator)
        let attachIdx = mutator.log.firstIndex(where: { $0.hasPrefix("attach-tree") })!
        let terminateIdx = mutator.log.firstIndex(of: "terminate b")!
        XCTAssertLessThan(attachIdx, terminateIdx)
    }

    /// closeTabs runs AFTER attachments so cross-tab moves out of a
    /// doomed tab have a chance to detach their sessions before the
    /// tab is closed.
    func testCloseTabsAfterAttachments() throws {
        let mutator = RecordingMutator()
        mutator.sessionGUIDsByTab = ["t1": ["a"], "t2": ["b"]]
        let plan = LayoutPlan(
            tabUpdates: [.init(tabGUID: "t1", root: vsplit([session("a"), session("b")]))],
            newTabs: [], newWindows: [],
            closeSessions: [],
            closeTabs: ["t2"],
            closeWindows: [])
        try LayoutTransaction.execute(plan: plan, mutator: mutator)
        let attachIdx = mutator.log.firstIndex(where: { $0.hasPrefix("attach-tree") })!
        let closeTabIdx = mutator.log.firstIndex(of: "close-tab t2")!
        XCTAssertLessThan(attachIdx, closeTabIdx)
    }

    // MARK: - New sessions

    /// If an attachTree call throws, the remaining operations
    /// (subsequent attaches, closes, terminations) must not execute.
    /// The whole transaction should be a single `throw` to the caller.
    func testAttachFailureAbortsRemainingOperations() {
        final class FailingMutator: LayoutMutator {
            var log: [String] = []
            enum Boom: Error { case bang }
            func beginTransaction() { log.append("begin") }
            func endTransaction() { log.append("end") }
            func detachSession(_ guid: String, fromTab tabGUID: String) throws {
                log.append("detach")
            }
            func createNewSession(profileGUID: String, command: String?) throws -> String { "" }
            func attachTree(toTab tabGUID: String, layout: LayoutNode) throws {
                log.append("attach \(tabGUID)")
                if tabGUID == "t1" { throw Boom.bang }
            }
            func createNewTab(windowGUID: String, index: Int?, layout: LayoutNode) throws -> String { "" }
            func createNewWindow(profileGUID: String, frame: NSRect?, layout: LayoutNode) throws -> String { "" }
            func terminateSession(_ guid: String) throws { log.append("terminate") }
            func closeTab(_ tabGUID: String) throws { log.append("close-tab") }
            func closeWindow(_ windowGUID: String) throws { log.append("close-window") }
            func tabContaining(sessionGUID: String) -> String? { nil }
        }
        let mutator = FailingMutator()
        let plan = LayoutPlan(
            tabUpdates: [
                .init(tabGUID: "t1", root: session("a")),
                .init(tabGUID: "t2", root: session("b")),
            ],
            newTabs: [], newWindows: [],
            closeSessions: ["c"],
            closeTabs: ["t9"],
            closeWindows: [])
        XCTAssertThrowsError(try LayoutTransaction.execute(plan: plan, mutator: mutator))
        XCTAssertTrue(mutator.log.contains("begin"))
        XCTAssertTrue(mutator.log.contains("attach t1"))
        XCTAssertTrue(mutator.log.contains("end"), "end should fire via defer even on throw")
        // Critical: no operations after the failing attach. terminate /
        // close-tab / close-window all run AFTER the attach phase, so
        // none should be in the log if attach t1 threw.
        XCTAssertFalse(mutator.log.contains("attach t2"))
        XCTAssertFalse(mutator.log.contains("terminate"))
        XCTAssertFalse(mutator.log.contains("close-tab"))
        XCTAssertFalse(mutator.log.contains("close-window"))
    }

    func testNewSessionLeafCreatesSession() throws {
        let mutator = RecordingMutator()
        mutator.newSessionsToCreate = ["fresh-1"]
        mutator.sessionGUIDsByTab = ["t1": ["a"]]

        let newLeaf: LayoutNode = .newSession(.init(profileGUID: "P1", command: nil))
        let plan = LayoutPlan(
            tabUpdates: [.init(tabGUID: "t1", root: vsplit([session("a"), newLeaf]))],
            newTabs: [], newWindows: [],
            closeSessions: [], closeTabs: [], closeWindows: [])
        try LayoutTransaction.execute(plan: plan, mutator: mutator)
        XCTAssertTrue(mutator.log.contains(where: { $0.hasPrefix("create-session fresh-1") }))
        // Attach should reference the freshly-created session GUID.
        XCTAssertTrue(mutator.log.contains(where: { $0.hasPrefix("attach-tree to t1") && $0.contains("fresh-1") }))
    }
}

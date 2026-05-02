//
//  iTermLayoutResolverTests.swift
//  ModernTests
//
//  TDD-driven tests for LayoutResolver — the live-state validation
//  pass that takes a structurally-valid LayoutSpec, checks that all
//  referenced GUIDs map to live state and that every involved tab's
//  sessions are fully accounted for, and produces a LayoutPlan.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLayoutResolverTests: XCTestCase {

    // MARK: - StubEnvironment

    /// In-memory environment for resolver tests. No real PTYTab /
    /// PTYSession state — sessions and tabs are identified by GUID
    /// strings, with simple maps tracking ownership and tmux flags.
    final class StubEnvironment: LayoutResolverEnvironment {
        var sessions: Set<String> = []
        var tabs: Set<String> = []
        var windows: Set<String> = []
        var sessionsByTab: [String: [String]] = [:]
        var tmuxTabs: Set<String> = []

        func sessionGUIDExists(_ guid: String) -> Bool { sessions.contains(guid) }
        func tabIDExists(_ tabID: String) -> Bool { tabs.contains(tabID) }
        func windowGUIDExists(_ guid: String) -> Bool { windows.contains(guid) }

        func tabID(containingSession sessionGUID: String) -> String? {
            for (tab, list) in sessionsByTab where list.contains(sessionGUID) {
                return tab
            }
            return nil
        }

        func sessionGUIDs(inTab tabID: String) -> [String] {
            sessionsByTab[tabID] ?? []
        }

        func isTmuxTab(_ tabID: String) -> Bool {
            tmuxTabs.contains(tabID)
        }
    }

    /// Convenience: build a stub environment with the given tab→sessions
    /// map.
    private func env(_ tabsToSessions: [String: [String]],
                     windows: [String] = ["w1"],
                     tmuxTabs: Set<String> = []) -> StubEnvironment {
        let env = StubEnvironment()
        env.windows = Set(windows)
        env.tmuxTabs = tmuxTabs
        for (tab, sessions) in tabsToSessions {
            env.tabs.insert(tab)
            env.sessionsByTab[tab] = sessions
            for s in sessions {
                env.sessions.insert(s)
            }
        }
        return env
    }

    private func session(_ guid: String) -> LayoutNode { .session(guid: guid) }
    private func vsplit(_ children: [LayoutNode]) -> LayoutNode {
        .splitter(vertical: true, children: children)
    }
    private func tabSpec(_ id: String, _ root: LayoutNode) -> LayoutTabSpec {
        LayoutTabSpec(tabID: id, root: root)
    }
    private func makeSpec(tabs: [LayoutTabSpec] = [],
                          newTabs: [LayoutNewTabSpec] = [],
                          newWindows: [LayoutNewWindowSpec] = [],
                          closeSessions: [String] = [],
                          closeTabs: [String] = [],
                          closeWindows: [String] = []) -> LayoutSpec {
        LayoutSpec(tabs: tabs,
                   newTabs: newTabs,
                   newWindows: newWindows,
                   closeSessions: closeSessions,
                   closeTabs: closeTabs,
                   closeWindows: closeWindows)
    }

    // MARK: - Empty / trivial

    func testEmptySpecResolvesToEmptyPlan() throws {
        let plan = try LayoutResolver.resolve(makeSpec(), environment: env([:]))
        XCTAssertTrue(plan.tabUpdates.isEmpty)
        XCTAssertTrue(plan.newTabs.isEmpty)
        XCTAssertTrue(plan.closeSessions.isEmpty)
    }

    // MARK: - Single-tab reshape

    func testSingleTabReshapeSucceeds() throws {
        let environment = env(["t1": ["a", "b"]])
        let spec = makeSpec(tabs: [
            tabSpec("t1", vsplit([session("b"), session("a")])),
        ])
        let plan = try LayoutResolver.resolve(spec, environment: environment)
        XCTAssertEqual(plan.tabUpdates.count, 1)
        XCTAssertEqual(plan.tabUpdates[0].tabGUID, "t1")
    }

    func testSingleTabMissingSessionFails() {
        let environment = env(["t1": ["a", "b"]])
        let spec = makeSpec(tabs: [
            tabSpec("t1", vsplit([session("a"), session("b"), session("c")])),
        ])
        XCTAssertThrowsError(try LayoutResolver.resolve(spec, environment: environment)) { err in
            guard case LayoutResolverError.unknownSession(let guid) = err else {
                XCTFail("expected unknownSession, got \(err)"); return
            }
            XCTAssertEqual(guid, "c")
        }
    }

    func testSingleTabUnknownTabIDFails() {
        let environment = env(["t1": ["a", "b"]])
        let spec = makeSpec(tabs: [
            tabSpec("t99", vsplit([session("a"), session("b")])),
        ])
        XCTAssertThrowsError(try LayoutResolver.resolve(spec, environment: environment)) { err in
            guard case LayoutResolverError.unknownTab = err else {
                XCTFail("expected unknownTab, got \(err)"); return
            }
        }
    }

    // MARK: - Orphan rule

    func testTabWithUnaccountedSessionRejected() {
        // t1 has sessions a, b. Spec only references a. b is orphaned.
        let environment = env(["t1": ["a", "b"]])
        let spec = makeSpec(tabs: [tabSpec("t1", session("a"))])
        XCTAssertThrowsError(try LayoutResolver.resolve(spec, environment: environment)) { err in
            guard case LayoutResolverError.orphanedSession = err else {
                XCTFail("expected orphanedSession, got \(err)"); return
            }
        }
    }

    func testCloseSessionsAccountsForOrphan() throws {
        let environment = env(["t1": ["a", "b"]])
        let spec = makeSpec(
            tabs: [tabSpec("t1", session("a"))],
            closeSessions: ["b"])
        let plan = try LayoutResolver.resolve(spec, environment: environment)
        XCTAssertEqual(plan.closeSessions, ["b"])
    }

    // MARK: - Cross-tab moves

    func testCrossTabMoveRequiresBothTabs() {
        // Move b from t2 to t1. t2 must appear in the spec (because t2's
        // remaining sessions need a new layout).
        let environment = env(["t1": ["a"], "t2": ["b", "c"]])
        let spec = makeSpec(tabs: [
            tabSpec("t1", vsplit([session("a"), session("b")])),
        ])
        XCTAssertThrowsError(try LayoutResolver.resolve(spec, environment: environment))
    }

    func testCrossTabMoveSucceedsWithBothTabsListed() throws {
        let environment = env(["t1": ["a"], "t2": ["b", "c"]])
        let spec = makeSpec(tabs: [
            tabSpec("t1", vsplit([session("a"), session("b")])),
            tabSpec("t2", session("c")),
        ])
        let plan = try LayoutResolver.resolve(spec, environment: environment)
        XCTAssertEqual(plan.tabUpdates.count, 2)
    }

    // MARK: - Tmux

    func testTmuxTabRejected() {
        let environment = env(["t1": ["a"]], tmuxTabs: ["t1"])
        let spec = makeSpec(tabs: [tabSpec("t1", session("a"))])
        XCTAssertThrowsError(try LayoutResolver.resolve(spec, environment: environment)) { err in
            guard case LayoutResolverError.tmuxTabNotSupported = err else {
                XCTFail("expected tmuxTabNotSupported, got \(err)"); return
            }
        }
    }

    // MARK: - Unsupported-feature rejections

    func testNewTabsRejected() {
        let environment = env(["t1": ["a"]])
        let spec = makeSpec(
            tabs: [tabSpec("t1", session("a"))],
            newTabs: [LayoutNewTabSpec(windowID: "w1", index: nil, root: session("a"))])
        XCTAssertThrowsError(try LayoutResolver.resolve(spec, environment: environment)) { err in
            guard case LayoutResolverError.newTabsNotSupported = err else {
                XCTFail("expected newTabsNotSupported, got \(err)"); return
            }
        }
    }

    func testNewWindowsRejected() {
        let environment = env(["t1": ["a"]])
        let spec = makeSpec(
            tabs: [tabSpec("t1", session("a"))],
            newWindows: [LayoutNewWindowSpec(profileGUID: "P1",
                                              frame: nil,
                                              root: session("a"))])
        XCTAssertThrowsError(try LayoutResolver.resolve(spec, environment: environment)) { err in
            guard case LayoutResolverError.newWindowsNotSupported = err else {
                XCTFail("expected newWindowsNotSupported, got \(err)"); return
            }
        }
    }

    func testNewSessionLeafRejected() {
        let environment = env(["t1": ["a"]])
        let newLeaf: LayoutNode = .newSession(.init(profileGUID: "P1", command: nil))
        let spec = makeSpec(tabs: [
            tabSpec("t1", vsplit([session("a"), newLeaf])),
        ])
        XCTAssertThrowsError(try LayoutResolver.resolve(spec, environment: environment)) { err in
            guard case LayoutResolverError.newSessionLeafNotSupported = err else {
                XCTFail("expected newSessionLeafNotSupported, got \(err)"); return
            }
        }
    }

    // MARK: - close_tabs accounts for all sessions in the named tab

    func testCloseTabAccountsForAllSessions() throws {
        let environment = env(["t1": ["a", "b"]])
        let spec = makeSpec(closeTabs: ["t1"])
        let plan = try LayoutResolver.resolve(spec, environment: environment)
        XCTAssertEqual(plan.closeTabs, ["t1"])
    }
}

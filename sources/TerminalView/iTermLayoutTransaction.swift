//
//  iTermLayoutTransaction.swift
//  iTerm2SharedARC
//
//  Executes a resolved `LayoutPlan` atomically. The plan-execution
//  algorithm is decoupled from PTYTab/PTYSession via a `LayoutMutator`
//  protocol so the sequencing logic can be unit-tested with a recording
//  mock. The production adapter wraps PTYTab/PseudoTerminal/iTermController.
//
//  Execution order (matters):
//
//  1. begin transaction (notification suppression / resize bracketing)
//  2. detach phase: every session that's moving to a different tab is
//     detached from its source tab so the source tab's reattach phase
//     doesn't terminate it as an orphan
//  3. create-new phase: every `.newSession` leaf is materialized
//  4. attach phase: every tab in `tabUpdates` adopts its new tree
//  5. new-tabs and new-windows are created
//  6. close phase: explicit close lists are applied
//  7. end transaction
//

import Foundation

/// All side-effecting operations the transaction needs. Production
/// implementation lives in `iTermLayoutMutator.swift`. Tests use a
/// recording mock to verify operation order.
protocol LayoutMutator {
    func beginTransaction()
    func endTransaction()

    /// Detach a session's view from its current tab without terminating
    /// the session. Used for cross-tab reparenting.
    func detachSession(_ guid: String, fromTab tabGUID: String) throws

    /// Create a brand-new session and return its GUID.
    func createNewSession(profileGUID: String, command: String?) throws -> String

    /// Replace the named tab's split-view tree with one matching
    /// `layout`. The resolver guarantees every leaf in `layout` is
    /// either an existing live session (already detached if it came
    /// from a different tab) or a `.newSession` referring to a session
    /// just created via `createNewSession`.
    func attachTree(toTab tabGUID: String, layout: LayoutNode) throws

    /// Create a new tab in the named window and populate it with
    /// `layout`. Returns the new tab's GUID.
    func createNewTab(windowGUID: String, index: Int?, layout: LayoutNode) throws -> String

    /// Create a new window with the given profile/frame, populated with
    /// `layout`. Returns the new window's GUID.
    func createNewWindow(profileGUID: String, frame: NSRect?, layout: LayoutNode) throws -> String

    /// Terminate the named session.
    func terminateSession(_ guid: String) throws

    /// Close the named tab.
    func closeTab(_ tabGUID: String) throws

    /// Close the named window.
    func closeWindow(_ windowGUID: String) throws

    /// Source-tab lookup for cross-tab move detection. Returns the GUID
    /// of the tab currently containing `sessionGUID`, or nil if the
    /// session is not parented in any tab.
    func tabContaining(sessionGUID: String) -> String?
}

enum LayoutTransaction {

    static func execute(plan: LayoutPlan, mutator: LayoutMutator) throws {
        mutator.beginTransaction()
        defer { mutator.endTransaction() }

        try detachCrossTabMovers(plan: plan, mutator: mutator)

        // Create new sessions and rewrite leaves to use the assigned
        // GUIDs, so the attach phase can simply reference sessions by
        // GUID throughout.
        let resolvedTabUpdates = try plan.tabUpdates.map { update in
            LayoutPlanTabUpdate(
                tabGUID: update.tabGUID,
                root: try materializeNewSessions(update.root, mutator: mutator))
        }
        let resolvedNewTabs = try plan.newTabs.map { spec in
            LayoutNewTabSpec(
                windowID: spec.windowID,
                index: spec.index,
                root: try materializeNewSessions(spec.root, mutator: mutator))
        }
        let resolvedNewWindows = try plan.newWindows.map { spec in
            LayoutNewWindowSpec(
                profileGUID: spec.profileGUID,
                frame: spec.frame,
                root: try materializeNewSessions(spec.root, mutator: mutator))
        }

        // Attach phase comes BEFORE close_sessions so a session can
        // legally appear in a new layout AND be terminated in the same
        // call ("apply this layout, then close these sessions"). The
        // close phase runs against the already-reshaped state.
        //
        // `replaceViewHierarchy` deliberately does NOT auto-terminate
        // sessions absent from the new layout — they'll be killed by
        // the explicit close phase below. (Auto-terminating here would
        // race with the explicit close: double-termination →
        // unknownSession on the second one.)
        for update in resolvedTabUpdates {
            try mutator.attachTree(toTab: update.tabGUID, layout: update.root)
        }
        for newTab in resolvedNewTabs {
            _ = try mutator.createNewTab(windowGUID: newTab.windowID,
                                         index: newTab.index,
                                         layout: newTab.root)
        }
        for newWindow in resolvedNewWindows {
            _ = try mutator.createNewWindow(profileGUID: newWindow.profileGUID,
                                            frame: newWindow.frame,
                                            layout: newWindow.root)
        }

        for guid in plan.closeSessions {
            try mutator.terminateSession(guid)
        }
        for tabGUID in plan.closeTabs {
            try mutator.closeTab(tabGUID)
        }
        for windowGUID in plan.closeWindows {
            try mutator.closeWindow(windowGUID)
        }
    }

    // MARK: - Helpers

    private static func detachCrossTabMovers(plan: LayoutPlan,
                                             mutator: any LayoutMutator) throws {
        // Build a map of session GUID → destination tab GUID for every
        // session that lands in a tab via the plan.
        var destinationByGUID: [String: String] = [:]
        for update in plan.tabUpdates {
            collectGUIDs(update.root, into: &destinationByGUID, destination: update.tabGUID)
        }
        for newTab in plan.newTabs {
            collectGUIDs(newTab.root, into: &destinationByGUID, destination: "<new-tab>")
        }
        for newWindow in plan.newWindows {
            collectGUIDs(newWindow.root, into: &destinationByGUID, destination: "<new-window>")
        }

        // Source tab for each moving session: ask the mutator (via its
        // session-to-tab knowledge). The mutator's RecordingMutator (in
        // tests) tracks `sessionGUIDsByTab`. The production
        // `iTermLayoutMutator` wraps `iTermController.tab(forSession:)`.
        for (sessionGUID, destinationTabGUID) in destinationByGUID {
            guard let sourceTab = sourceTabFor(sessionGUID: sessionGUID, mutator: mutator) else {
                continue
            }
            if sourceTab != destinationTabGUID {
                try mutator.detachSession(sessionGUID, fromTab: sourceTab)
            }
        }
    }

    /// Walks a layout tree and rewrites every `.newSession` leaf to a
    /// `.session` leaf carrying a freshly-created session's GUID.
    private static func materializeNewSessions(_ node: LayoutNode,
                                                mutator: any LayoutMutator) throws -> LayoutNode {
        switch node {
        case .splitter(let vertical, let children):
            let resolved = try children.map { try materializeNewSessions($0, mutator: mutator) }
            return .splitter(vertical: vertical, children: resolved)
        case .session:
            return node
        case .newSession(let info):
            let guid = try mutator.createNewSession(profileGUID: info.profileGUID,
                                                    command: info.command)
            return .session(guid: guid)
        }
    }

    private static func collectGUIDs(_ node: LayoutNode,
                                     into map: inout [String: String],
                                     destination: String) {
        switch node {
        case .splitter(_, let children):
            for child in children {
                collectGUIDs(child, into: &map, destination: destination)
            }
        case .session(let guid):
            map[guid] = destination
        case .newSession:
            break
        }
    }

    /// The tests' RecordingMutator and the production adapter both
    /// expose this lookup through the same protocol extension below.
    private static func sourceTabFor(sessionGUID: String, mutator: LayoutMutator) -> String? {
        return mutator.tabContaining(sessionGUID: sessionGUID)
    }
}


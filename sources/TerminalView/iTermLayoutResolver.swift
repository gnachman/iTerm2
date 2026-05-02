//
//  iTermLayoutResolver.swift
//  iTerm2SharedARC
//
//  Live-state validation pass for the layout-application API. Takes a
//  structurally-valid `LayoutSpec` and an environment that exposes the
//  current set of sessions, tabs, and windows, and produces a typed
//  `LayoutPlan`. The plan is consumed by the transaction coordinator.
//
//  Validation rules enforced here:
//  - Every referenced session_id maps to a live session.
//  - Every tab_id and window_id maps to a live tab/window.
//  - tmux integration tabs are not supported.
//  - The "involved set" rule: every live session in any involved tab
//    must be either referenced in the new layout, listed in
//    close_sessions, or its tab listed in close_tabs. No silent drops.
//
//  The environment is a protocol so the resolver can be unit-tested
//  with a stub. The production implementation lives in
//  iTermLayoutEnvironment.swift (added with the built-in function).
//

import Foundation

protocol LayoutResolverEnvironment {
    func sessionGUIDExists(_ guid: String) -> Bool
    /// True if a tab with the given numeric ID (matching `tab.uniqueId`,
    /// which is what the Python API exposes as `tab.tab_id`) exists.
    func tabIDExists(_ tabID: String) -> Bool
    func windowGUIDExists(_ guid: String) -> Bool

    /// The numeric tab ID currently containing the given session, or
    /// nil if the session is unknown or unparented.
    func tabID(containingSession sessionGUID: String) -> String?

    /// All sessions currently in the given tab (looked up by numeric
    /// tab ID).
    func sessionGUIDs(inTab tabID: String) -> [String]

    /// True if the tab is a tmux integration tab (rejected by the
    /// resolver — tmux owns server-side layout).
    func isTmuxTab(_ tabID: String) -> Bool
}

/// Errors thrown during live-state resolution.
enum LayoutResolverError: Error, Equatable {
    case unknownSession(guid: String)
    case unknownTab(guid: String)
    case unknownWindow(guid: String)
    case orphanedSession(tabGUID: String, sessionGUID: String)
    case tmuxTabNotSupported(tabGUID: String)
    case newTabsNotSupported
    case newWindowsNotSupported
    case newSessionLeafNotSupported
}

/// One tab whose layout is being replaced. Carries the resolved
/// `LayoutNode` (no further validation needed) and the GUID of the
/// target tab. The transaction coordinator will look up the live
/// PTYTab from the GUID at execution time.
struct LayoutPlanTabUpdate {
    let tabGUID: String
    let root: LayoutNode
}

/// Fully-resolved plan ready for atomic execution.
struct LayoutPlan {
    let tabUpdates: [LayoutPlanTabUpdate]
    let newTabs: [LayoutNewTabSpec]
    let newWindows: [LayoutNewWindowSpec]
    let closeSessions: [String]
    let closeTabs: [String]
    let closeWindows: [String]
}

enum LayoutResolver {

    /// Validates against live state and produces a `LayoutPlan`.
    /// `LayoutSpec.parse` runs `LayoutSpecValidator` automatically, so
    /// any `LayoutSpec` reaching this method has already been
    /// structurally validated.
    static func resolve(_ spec: LayoutSpec,
                        environment: LayoutResolverEnvironment) throws -> LayoutPlan {

        // Reject features the mutator cannot execute: inline session/
        // tab/window creation requires a headless session-creation
        // primitive that does not exist yet.
        if !spec.newTabs.isEmpty {
            throw LayoutResolverError.newTabsNotSupported
        }
        if !spec.newWindows.isEmpty {
            throw LayoutResolverError.newWindowsNotSupported
        }
        for tab in spec.tabs {
            try rejectNewSessionLeaves(tab.root)
        }

        // 1. Existence checks for every referenced ID.
        for tab in spec.tabs {
            if !environment.tabIDExists(tab.tabID) {
                throw LayoutResolverError.unknownTab(guid: tab.tabID)
            }
            try checkSessionExistence(tab.root, environment: environment)
        }
        for guid in spec.closeSessions where !environment.sessionGUIDExists(guid) {
            throw LayoutResolverError.unknownSession(guid: guid)
        }
        for tabID in spec.closeTabs where !environment.tabIDExists(tabID) {
            throw LayoutResolverError.unknownTab(guid: tabID)
        }
        for guid in spec.closeWindows where !environment.windowGUIDExists(guid) {
            throw LayoutResolverError.unknownWindow(guid: guid)
        }

        // 2. tmux rejection.
        for tab in spec.tabs where environment.isTmuxTab(tab.tabID) {
            throw LayoutResolverError.tmuxTabNotSupported(tabGUID: tab.tabID)
        }
        for tabID in spec.closeTabs where environment.isTmuxTab(tabID) {
            throw LayoutResolverError.tmuxTabNotSupported(tabGUID: tabID)
        }

        // 3. Compute the involved set and the accounted-for set.
        //    A tab is involved if:
        //    - It's named in spec.tabs or spec.closeTabs, or
        //    - It currently contains a session referenced anywhere in
        //      the new layout / close_sessions list.
        var referencedSessions: Set<String> = Set(spec.closeSessions)
        for tab in spec.tabs {
            collectReferencedSessions(tab.root, into: &referencedSessions)
        }

        var involvedTabs: Set<String> = Set(spec.tabs.map { $0.tabID })
            .union(spec.closeTabs)
        for sessionGUID in referencedSessions {
            if let containingTab = environment.tabID(containingSession: sessionGUID) {
                involvedTabs.insert(containingTab)
            }
        }

        // 4. Orphan check: every session in any involved tab must be
        //    accounted for (referenced or close_listed or its tab is in
        //    close_tabs).
        let closeTabSet = Set(spec.closeTabs)
        let accountedFor: Set<String> = referencedSessions
        for tabID in involvedTabs where !closeTabSet.contains(tabID) {
            for sessionGUID in environment.sessionGUIDs(inTab: tabID) {
                if !accountedFor.contains(sessionGUID) {
                    throw LayoutResolverError.orphanedSession(
                        tabGUID: tabID,
                        sessionGUID: sessionGUID)
                }
            }
        }

        // 5. Build the plan. (At this point everything has passed.)
        //    Every involved tab that's not in close_tabs needs a tab
        //    update; if the spec didn't list it explicitly, we've
        //    rejected above (since its sessions would be orphans).
        let tabUpdates = spec.tabs.map { LayoutPlanTabUpdate(tabGUID: $0.tabID, root: $0.root) }
        return LayoutPlan(tabUpdates: tabUpdates,
                          newTabs: spec.newTabs,
                          newWindows: spec.newWindows,
                          closeSessions: spec.closeSessions,
                          closeTabs: spec.closeTabs,
                          closeWindows: spec.closeWindows)
    }

    // MARK: - Helpers

    private static func rejectNewSessionLeaves(_ node: LayoutNode) throws {
        switch node {
        case .splitter(_, let children):
            for child in children {
                try rejectNewSessionLeaves(child)
            }
        case .session:
            break
        case .newSession:
            throw LayoutResolverError.newSessionLeafNotSupported
        }
    }

    private static func checkSessionExistence(_ node: LayoutNode,
                                              environment: LayoutResolverEnvironment) throws {
        switch node {
        case .splitter(_, let children):
            for child in children {
                try checkSessionExistence(child, environment: environment)
            }
        case .session(let guid):
            if !environment.sessionGUIDExists(guid) {
                throw LayoutResolverError.unknownSession(guid: guid)
            }
        case .newSession:
            break
        }
    }

    private static func collectReferencedSessions(_ node: LayoutNode,
                                                  into set: inout Set<String>) {
        switch node {
        case .splitter(_, let children):
            for child in children {
                collectReferencedSessions(child, into: &set)
            }
        case .session(let guid):
            set.insert(guid)
        case .newSession:
            break
        }
    }
}

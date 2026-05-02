//
//  iTermLayoutMutator.swift
//  iTerm2SharedARC
//
//  Production implementation of `LayoutMutator`. Wraps PTYTab,
//  PseudoTerminal, and iTermController to perform the actual mutations
//  the layout-application API needs.
//
//  Current scope: layouts may reference live sessions only. Layouts
//  with `.newSession` leaves are rejected by the resolver; the
//  mutator's create-new-* methods all throw
//  `LayoutMutatorError.newSessionNotSupported`. Adding inline session/
//  tab/window creation requires a headless session-creation primitive
//  that does not exist yet.
//

import Foundation

enum LayoutMutatorError: Error, LocalizedError {
    case newSessionNotSupported
    case unknownSession(guid: String)
    case unknownTab(guid: String)
    case unknownWindow(guid: String)
    case sessionWithoutOwningTab(guid: String)

    var errorDescription: String? {
        switch self {
        case .newSessionNotSupported:
            return "Creating new sessions via apply_layout is not supported; only existing sessions may appear as leaves."
        case .unknownSession(let guid):
            return "Unknown session: \(guid)"
        case .unknownTab(let guid):
            return "Unknown tab: \(guid)"
        case .unknownWindow(let guid):
            return "Unknown window: \(guid)"
        case .sessionWithoutOwningTab(let guid):
            return "Session \(guid) has no owning tab"
        }
    }
}

@objc(iTermLayoutMutator)
final class iTermLayoutMutator: NSObject, LayoutMutator {

    private let controller: iTermController
    private var detachedSessions: [String: PTYSession] = [:]   // guid → session
    private var emptyTabsToClose: Set<String> = []

    @objc init(controller: iTermController) {
        self.controller = controller
        super.init()
    }

    @objc convenience override init() {
        self.init(controller: iTermController.sharedInstance())
    }

    // MARK: - LayoutMutator

    func beginTransaction() {
        // Notification suppression / resize bracketing could go here.
        // We currently rely on each PTYTab.replaceViewHierarchy doing
        // its own bracketing.
        detachedSessions.removeAll()
        emptyTabsToClose.removeAll()
    }

    func endTransaction() {
        // Close any tabs that became empty during the transaction (e.g.
        // a tab that lost all its sessions via cross-tab moves).
        for tabID in emptyTabsToClose {
            guard let tab = controller.tab(withID: tabID),
                  let window = controller.window(for: tab) else { continue }
            if (tab.sessions() as? [PTYSession])?.isEmpty ?? true {
                window.close(tab)
            }
        }
        detachedSessions.removeAll()
        emptyTabsToClose.removeAll()
    }

    func detachSession(_ guid: String, fromTab tabID: String) throws {
        guard let session = controller.session(withGUID: guid) else {
            throw LayoutMutatorError.unknownSession(guid: guid)
        }
        guard let tab = controller.tab(withID: tabID) else {
            throw LayoutMutatorError.unknownTab(guid: tabID)
        }
        tab.remove(session)
        detachedSessions[guid] = session
        if (tab.sessions() as? [PTYSession])?.isEmpty ?? true {
            emptyTabsToClose.insert(tabID)
        }
    }

    func createNewSession(profileGUID: String, command: String?) throws -> String {
        throw LayoutMutatorError.newSessionNotSupported
    }

    func attachTree(toTab tabID: String, layout: LayoutNode) throws {
        guard let tab = controller.tab(withID: tabID) else {
            throw LayoutMutatorError.unknownTab(guid: tabID)
        }

        // Detach sessions present in the tab but absent from the new
        // layout. The resolver's orphan check guarantees they are
        // accounted for in close_sessions / close_tabs (cross-tab moves
        // were already detached by detachCrossTabMovers and so are not
        // in `tab.sessions()`).
        //
        // We hold a strong reference in `detachedSessions` so the close
        // phase can find them by GUID. Without this, the rebuilder
        // would orphan their views from the tree but leave them in
        // viewToSessionMap — `controller.session(withGUID:)` walks the
        // tree, so a subsequent `terminateSession(b)` would throw
        // `unknownSession` against a session that's still alive.
        let referencedGuids = collectReferencedGuids(layout)
        let preExisting = (tab.sessions() as? [PTYSession]) ?? []
        for session in preExisting {
            let guid = session.guid
            if !referencedGuids.contains(guid) {
                tab.remove(session)
                detachedSessions[guid] = session
            }
        }

        let idMap = try buildIdMap(for: layout)
        let keepAlive = Set(detachedSessions.keys)
        let treeNode = try toLayoutTreeNode(layout)
        let sessionsToAdopt = sessionsToAdoptInThisTab(layout: layout)
        try iTermSplitTreeRebuilder.replaceViewHierarchy(
            in: tab,
            layoutTree: treeNode,
            idMap: idMap,
            keepAlive: keepAlive,
            sessionsToAdopt: sessionsToAdopt)

        for guid in sessionsToAdopt.keys {
            if let session = detachedSessions.removeValue(forKey: guid) {
                NotificationCenter.default.post(
                    name: .iTermSessionDidChangeTab,
                    object: session)
                session.didMove()
            }
        }

        // Notify observers (notably iTermAPIHelper.layoutChanged:, which
        // re-broadcasts the new layout to subscribed Python clients)
        // that this tab's layout changed. The cross-tab-adoption loop
        // above already posts per-moved-session, but in-tab reshapes
        // (swap/restructure within one tab, no sessions moving in or
        // out) wouldn't otherwise fire any notification — leaving the
        // Python App's cached state stale and turning subsequent
        // apply_layout calls into no-ops because they read the OLD
        // session ordering.
        if sessionsToAdopt.isEmpty,
           let firstSession = (tab.sessions() as? [PTYSession])?.first {
            NotificationCenter.default.post(
                name: .iTermSessionDidChangeTab,
                object: firstSession)
        }
    }

    private func collectReferencedGuids(_ node: LayoutNode) -> Set<String> {
        var result: Set<String> = []
        var guids: [String] = []
        collectGUIDs(node, into: &guids)
        for g in guids { result.insert(g) }
        return result
    }

    private func toLayoutTreeNode(_ node: LayoutNode) throws -> LayoutTreeNode {
        switch node {
        case .splitter(let vertical, let children):
            let resolved = try children.map { try toLayoutTreeNode($0) }
            return .splitter(vertical: vertical, children: resolved)
        case .session(let guid):
            return .session(guid: guid)
        case .newSession:
            throw LayoutMutatorError.newSessionNotSupported
        }
    }

    func createNewTab(windowGUID: String, index: Int?, layout: LayoutNode) throws -> String {
        throw LayoutMutatorError.newSessionNotSupported
    }

    func createNewWindow(profileGUID: String, frame: NSRect?, layout: LayoutNode) throws -> String {
        throw LayoutMutatorError.newSessionNotSupported
    }

    func terminateSession(_ guid: String) throws {
        if let session = controller.session(withGUID: guid) {
            session.terminate()
        } else if let detached = detachedSessions.removeValue(forKey: guid) {
            detached.terminate()
        } else {
            throw LayoutMutatorError.unknownSession(guid: guid)
        }
    }

    func closeTab(_ tabID: String) throws {
        guard let tab = controller.tab(withID: tabID),
              let window = controller.window(for: tab) else {
            throw LayoutMutatorError.unknownTab(guid: tabID)
        }
        window.close(tab)
        emptyTabsToClose.remove(tabID)
    }

    func closeWindow(_ windowGUID: String) throws {
        guard let window = controller.terminal(withGuid: windowGUID) else {
            throw LayoutMutatorError.unknownWindow(guid: windowGUID)
        }
        // The user explicitly authorized this close by sending the
        // spec; don't pop a confirmation sheet via performClose:.
        window.window?.close()
    }

    func tabContaining(sessionGUID: String) -> String? {
        // Detached sessions are no longer in any tab — but the caller
        // is asking about the *original* tab to compute cross-tab moves.
        // We need to remember the original location of detached sessions.
        if detachedSessions[sessionGUID] != nil {
            // Already detached; the move-detection logic in
            // LayoutTransaction has already accounted for this session.
            return nil
        }
        guard let session = controller.session(withGUID: sessionGUID),
              let tab = controller.tab(for: session) else {
            return nil
        }
        return "\(tab.uniqueId)"
    }

    // MARK: - Helpers

    private func buildIdMap(for layout: LayoutNode) throws -> [String: SessionView] {
        var map: [String: SessionView] = [:]
        try walk(layout, accumulator: &map)
        return map
    }

    /// Collects sessions whose PTYSession is in `detachedSessions` and
    /// whose GUID appears in `layout`. These will be reparented into
    /// the destination tab and need adoption (viewToSessionMap update,
    /// delegate set) inside `replaceViewHierarchy`.
    private func sessionsToAdoptInThisTab(layout: LayoutNode) -> [String: PTYSession] {
        var result: [String: PTYSession] = [:]
        var guids: [String] = []
        collectGUIDs(layout, into: &guids)
        for guid in guids {
            if let session = detachedSessions[guid] {
                result[guid] = session
            }
        }
        return result
    }

    private func walk(_ node: LayoutNode, accumulator: inout [String: SessionView]) throws {
        switch node {
        case .splitter(_, let children):
            for child in children {
                try walk(child, accumulator: &accumulator)
            }
        case .session(let guid):
            // Look up the session: either still in a tab, or detached.
            if let detached = detachedSessions[guid] {
                accumulator[guid] = detached.view
            } else if let session = controller.session(withGUID: guid) {
                accumulator[guid] = session.view
            } else {
                throw LayoutMutatorError.unknownSession(guid: guid)
            }
        case .newSession:
            throw LayoutMutatorError.newSessionNotSupported
        }
    }

    private func collectGUIDs(_ node: LayoutNode, into set: inout [String]) {
        switch node {
        case .splitter(_, let children):
            for child in children {
                collectGUIDs(child, into: &set)
            }
        case .session(let guid):
            set.append(guid)
        case .newSession:
            break
        }
    }
}

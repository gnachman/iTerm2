//
//  iTermLayoutMutator.swift
//  iTerm2SharedARC
//
//  Production implementation of `LayoutMutator`. Wraps PTYTab,
//  PseudoTerminal, and iTermController to perform the actual mutations
//  the layout-application API needs.
//
//  Current scope: layouts may reference live sessions and create new
//  ones inline (`.newSession` leaves). `createNewSession` mints a
//  started, tab-less session and stashes it in `detachedSessions` so
//  the normal attach/adoption path splices it into the destination tab
//  (the same machinery used for cross-tab moves). Creating whole new
//  tabs/windows is still unsupported; those methods throw
//  `LayoutMutatorError.newTabOrWindowNotSupported`.
//

import Foundation

enum LayoutMutatorError: Error, LocalizedError {
    case newTabOrWindowNotSupported
    case unknownSession(guid: String)
    case unknownTab(guid: String)
    case unknownWindow(guid: String)
    case unknownProfile(guid: String)
    case noContextForNewSession
    case sessionWithoutOwningTab(guid: String)

    var errorDescription: String? {
        switch self {
        case .newTabOrWindowNotSupported:
            return "Creating new tabs or windows via apply_layout is not supported."
        case .unknownSession(let guid):
            return "Unknown session: \(guid)"
        case .unknownTab(let guid):
            return "Unknown tab: \(guid)"
        case .unknownWindow(let guid):
            return "Unknown window: \(guid)"
        case .unknownProfile(let guid):
            return "Unknown profile: \(guid)"
        case .noContextForNewSession:
            return "Cannot create a new session: there is no existing window to size it against."
        case .sessionWithoutOwningTab(let guid):
            return "Session \(guid) has no owning tab"
        }
    }
}

@objc(iTermLayoutMutator)
final class iTermLayoutMutator: NSObject, LayoutMutator {

    private let controller: iTermController
    private var detachedSessions: [String: PTYSession] = [:]   // guid → session
    private var detachedSessionSourceTab: [String: String] = [:]   // guid → tab it left
    private var createdSessionGUIDs: Set<String> = []   // sessions minted this transaction
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
        detachedSessionSourceTab.removeAll()
        createdSessionGUIDs.removeAll()
        emptyTabsToClose.removeAll()
    }

    func endTransaction() {
        // Terminate sessions we minted this transaction that were never
        // adopted into a tab. Adoption (in attachTree) removes a session
        // from detachedSessions, so a created GUID still present here means
        // its tab's attach never ran or failed — leaving a running shell
        // in no tab and no view hierarchy, about to lose its only strong
        // reference below. Kill it rather than leak a headless zombie.
        //
        // This is scoped to sessions WE created: detachedSessions also
        // holds real user sessions that were detached as cross-tab movers,
        // and those must never be terminated here (an aborted move should
        // leave the user's session intact, not destroy it).
        for guid in createdSessionGUIDs {
            if let session = detachedSessions[guid] {
                session.terminate()
            }
        }

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
        detachedSessionSourceTab.removeAll()
        createdSessionGUIDs.removeAll()
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
        detachedSessionSourceTab[guid] = tabID
        if (tab.sessions() as? [PTYSession])?.isEmpty ?? true {
            emptyTabsToClose.insert(tabID)
        }
    }

    func createNewSession(profileGUID: String,
                          command: String?,
                          destinationTabGUID: String?) throws -> String {
        guard let profile = ProfileModel.sharedInstance()?.bookmark(withGuid: profileGUID) else {
            throw LayoutMutatorError.unknownProfile(guid: profileGUID)
        }

        // Pick a reference session to make the new one behave like a split:
        // a neighbor in the destination tab supplies both a provisional
        // size and a working directory to inherit.
        //
        // The cross-tab detach phase runs BEFORE this (see
        // LayoutTransaction.execute), so a destination-tab session that's
        // moving away has already been removed from the tab. Prefer a
        // session that is staying in the destination tab; if the tab was
        // emptied by those moves, fall back to a former occupant of that
        // tab (still the right "previous directory" for the recycle case);
        // only then to an unrelated session. Size is provisional either way
        // (attachTree's arrangeSplitPanesEvenly recomputes it on attach), so
        // a wrong reference only affects cwd, which these fallbacks keep
        // tied to the destination tab.
        let destinationTab = destinationTabGUID.flatMap { controller.tab(withID: $0) }
        let formerOccupant: PTYSession? = destinationTabGUID.flatMap { destGUID in
            detachedSessions.first { detachedSessionSourceTab[$0.key] == destGUID }?.value
        }
        let window = destinationTab.flatMap { controller.window(for: $0) }
            ?? controller.currentTerminal
            ?? controller.terminals().first
        let reference =
            (destinationTab?.sessions() as? [PTYSession])?.first
            ?? formerOccupant
            ?? window?.allSessions().first
            ?? controller.terminals().first?.allSessions().first
        guard let reference, let window else {
            throw LayoutMutatorError.noContextForNewSession
        }

        // Mint a started, tab-less session. This mirrors the proven
        // workgroup-peer path (PTYSession.makeWorkgroupPeer): create via
        // the factory, give it a provisional size and a window to parent
        // its view to, then launch with windowController:nil so it is
        // born outside any tab.
        let factory = iTermSessionFactory()
        let newSession = factory.newSession(withProfile: profile, parent: reference)
        let provisionalSize = reference.view?.bounds.size ?? NSSize(width: 400, height: 300)
        newSession.setScreenSize(provisionalSize, parent: window)
        newSession.setSize(reference.screen.size)
        newSession.setPreferencesFromAddressBookEntry(profile)
        newSession.loadInitialColorTableAndResetCursorGuide()

        // Stash it where attachTree's walk/adoption looks (the same dict
        // used for cross-tab movers). The view already exists (created by
        // setScreenSize), so adoption can splice it straight in.
        let guid = newSession.guid
        detachedSessions[guid] = newSession
        // Remember we minted this one so endTransaction can terminate it if
        // the plan aborts before it's adopted into a tab.
        createdSessionGUIDs.insert(guid)

        // Resolve the working directory honoring the profile's mode (Home,
        // Custom, or Reuse-previous), using the reference session's
        // directory as the "previous" PWD so the recycle case lands next
        // to its neighbor, like an interactive split.
        //
        // We compute it ourselves and FORCE the result (forceUseOldCWD)
        // rather than letting the launcher do it: the request uses
        // canPrompt:false because an API context can't answer prompts, and
        // iTermSessionFactory.computeWorkingDirectory short-circuits to an
        // empty directory whenever it can't prompt, skipping the profile's
        // directory mode entirely. Forcing the value we computed restores
        // the profile-honoring behavior without any prompt.
        //
        // Evaluation may be async, but the session and its view already
        // exist, so the attach phase that runs right after we return does
        // not depend on the shell having launched yet.
        let oldPWD = reference.currentLocalWorkingDirectory ?? ""

        // Run the command the way the user would type it: wrapped in a
        // login shell so their interactive PATH, aliases, and dotfiles are
        // sourced. This matches makeWorkgroupPeer (the path this mirrors).
        // A nil/empty command leaves the profile's normal command/shell in
        // place.
        let wrappedCommand: String?
        if let command, !command.isEmpty {
            wrappedCommand = ITAddressBookMgr.commandByWrapping(inLoginShell: command)
        } else {
            wrappedCommand = nil
        }

        // Launch the shell in a fully-resolved directory, forced so the
        // canPrompt:false short-circuit in the factory doesn't drop it.
        func launch(inDirectory pwd: String) {
            let request = iTermSessionAttachOrLaunchRequest(
                session: newSession,
                canPrompt: false,
                objectType: .paneObject,
                hasServerConnection: false,
                serverConnection: iTermGeneralServerConnection(),
                urlString: nil,
                allowURLSubs: false,
                environment: nil,
                customShell: nil,
                oldCWD: pwd,
                forceUseOldCWD: true,
                command: wrappedCommand,
                isUTF8: nil,
                substitutions: nil,
                windowController: nil,
                ready: nil) { _, _ in }
            factory.attachOrLaunch(with: request)
        }

        if let initialDirectory = iTermInitialDirectory(fromProfile: profile,
                                                        objectType: .paneObject) {
            initialDirectory.evaluate(withOldPWD: oldPWD,
                                      scope: newSession.genericScope,
                                      substitutions: nil) { [initialDirectory] pwd in
                // Keep initialDirectory alive across the async evaluation
                // (evaluate does not retain itself; cf. iTermSessionFactory).
                _ = initialDirectory
                launch(inDirectory: pwd ?? oldPWD)
            }
        } else {
            // No profile directory object (unexpected): best-effort recycle
            // of the neighbor's directory.
            launch(inDirectory: oldPWD)
        }

        return guid
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
            // Unreachable: materializeNewSessions rewrites every
            // .newSession leaf to .session before attach runs.
            throw LayoutMutatorError.newTabOrWindowNotSupported
        }
    }

    func createNewTab(windowGUID: String, index: Int?, layout: LayoutNode) throws -> String {
        throw LayoutMutatorError.newTabOrWindowNotSupported
    }

    func createNewWindow(profileGUID: String, frame: NSRect?, layout: LayoutNode) throws -> String {
        throw LayoutMutatorError.newTabOrWindowNotSupported
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
            // Unreachable: materializeNewSessions rewrites every
            // .newSession leaf to .session before attach runs.
            throw LayoutMutatorError.newTabOrWindowNotSupported
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

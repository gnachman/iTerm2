//
//  iTermWorkgroupInstance.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import Foundation

// Runtime counterpart of an iTermWorkgroup config. One instance per
// active workgroup on a main session; owned by iTermWorkgroupController
// and referenced weakly from the main session.
//
// Sessions in the workgroup come in two flavors:
//   - Peer-group members: the main (root) plus its peer children.
//     These are wired up by iTermWorkgroupPeerPort, which knows how
//     to swap the visible toolbar between peers via PTYTab.
//   - Non-peer children: split panes and new tabs spawned at entry
//     time. They have their own toolbar (built fresh from config)
//     and don't participate in the peer-swap mechanism.
@objc(iTermWorkgroupInstance)
final class iTermWorkgroupInstance: NSObject {
    @objc let workgroupUniqueIdentifier: String

    // Stable identifier for this *entry* of the workgroup, distinct
    // from workgroupUniqueIdentifier (which is the config's UUID and
    // is the same across re-entries). Exposed to spawned sessions as
    // ITERM_WORKGROUP_ID so external tools can tell two runs of the
    // same workgroup config apart.
    @objc let instanceUniqueIdentifier: String

    @objc weak var mainSession: PTYSession?

    // Config snapshot at entry time.
    let workgroup: iTermWorkgroup

    // The peer port wired to the main session's SessionView.
    @objc let peerPort: iTermWorkgroupPeerPort

    // Seam for creating peers, splits, and tabs. Production uses
    // DefaultWorkgroupSessionSpawner (which calls into PTYSession,
    // PseudoTerminal, and iTermSessionFactory). Tests inject a fake
    // that returns synthetic PTYSessions without touching windows.
    let spawner: WorkgroupSessionSpawner

    // Per-session bundle of state for a non-peer (split/tab) child:
    // the live PTYSession and its toolbar item views.
    private struct NonPeerEntry {
        let session: PTYSession
        var items: [SessionToolbarGenericView]
    }

    // Non-peer entries keyed by workgroup-config UUID. We hold a
    // strong reference to the session so it can't dealloc between
    // spawn and teardown, and so we can find the session even after
    // PTYSession.replaceTerminatedShellWithNewInstance reassigns its
    // GUID on restart — keying by configID (stable) instead of GUID
    // (rotates) makes toolbar/lookup robust to those rotations.
    private var nonPeerEntriesByConfigID: [String: NonPeerEntry] = [:]

    // Insertion order so teardown terminates in spawn order.
    private var nonPeerOrderedConfigIDs: [String] = []

    // Non-peer sessions tracked for sessionWillTerminate matching but
    // not owned by us (e.g. peer children of a nested host — the
    // nested peer port already owns the lifecycle, but we want to
    // notice if any of them terminates so we can tear down the
    // workgroup). Stored as ObjectIdentifier so we can compare by
    // reference in the notification handler.
    private var trackedSessionIdentities: Set<ObjectIdentifier> = []

    // Nested peer ports for non-peer hosts that themselves host a peer
    // group (e.g. a split whose config declares peer children). Each
    // port needs to be invalidated at teardown, and toolbarItems(for:)
    // consults them when the main port doesn't own the session.
    private var nestedPeerPorts: [iTermWorkgroupPeerPort] = []

    // Workgroup-wide git poller, shared across every gitStatus and
    // changedFileSelector view in every peer group AND every non-peer
    // host. Built once at instance creation if any session in the
    // tree (peer or otherwise) declares an item that needs it; nil
    // otherwise. Owning it here (vs on the main peer port) means
    // workgroups whose only git-aware items live on splits or tabs
    // still get a poller, and updates fan out to all toolbars.
    @objc let gitPoller: iTermGitPoller?

    // Holds onto the leader's PWD/host observers that drive the
    // poller's currentDirectory and enabled state. Normally a
    // CCGitSessionToolbarItem (the gitStatus item) creates one of
    // these and the poller tracks the leader. But a workgroup can
    // have a changedFileSelector without any gitStatus item — in
    // that case nothing else would set up the observer chain, the
    // poller's currentDirectory stays nil, and the selector
    // dropdown is permanently empty. Always holding one here keeps
    // the poller productive whenever it exists.
    private var gitDirectoryTracker: iTermAutoGitString?

    // Workgroup-wide git base ref. Single source of truth — every
    // peer port mirrors this via applyGitBase, and every
    // resolvedCommand / resolvedPerFileCommand caller reads it
    // here so per-port copies can't drift. Updated by
    // gitBaseChanged whenever any gitBaseSelector commits.
    @objc fileprivate(set) var currentGitBase: String = CCGitBaseSelectorItem.defaultBase

    init(workgroup: iTermWorkgroup,
         instanceUniqueIdentifier: String,
         mainSession: PTYSession,
         peerPort: iTermWorkgroupPeerPort,
         gitPoller: iTermGitPoller?,
         spawner: WorkgroupSessionSpawner) {
        self.workgroupUniqueIdentifier = workgroup.uniqueIdentifier
        self.instanceUniqueIdentifier = instanceUniqueIdentifier
        self.workgroup = workgroup
        self.mainSession = mainSession
        self.peerPort = peerPort
        self.gitPoller = gitPoller
        self.spawner = spawner
        super.init()
        gitPoller?.delegate = self
        // When any of our tracked sessions terminates (leader, peer,
        // or non-peer child), exit the workgroup so the leader's
        // workgroupInstance is cleared and re-entering produces a
        // fresh setup. Without this, closing a child pane left the
        // workgroup half-alive — the controller's dict still pointed
        // at this instance, so enter() returned early as a no-op.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWillTerminate(_:)),
            name: NSNotification.Name.iTermSessionWillTerminate,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func sessionWillTerminate(_ notification: Notification) {
        guard let session = notification.object as? PTYSession else { return }
        let isMine: Bool = {
            if mainSession === session { return true }
            if peerPort.contains(session: session) { return true }
            for port in nestedPeerPorts where port.contains(session: session) {
                return true
            }
            // Reference-equality check — non-peer sessions can rotate
            // their GUID across restarts (replaceTerminatedShellWithNewInstance),
            // so a GUID-based contains here would miss a recently-restarted
            // session. The PTYSession object identity stays stable.
            if trackedSessionIdentities.contains(ObjectIdentifier(session)) {
                return true
            }
            return false
        }()
        guard isMine else { return }
        guard let leader = mainSession else {
            // Leader is gone too — just tear down directly. Nothing
            // for the controller's per-session dict to release.
            teardown()
            return
        }
        iTermWorkgroupController.instance.exit(on: leader)
    }

    // The toolbar items to show on a specific session's SessionView.
    //
    // For peer-group sessions: each peer has its own ordered list of
    // NSView instances built fresh from its config; the same view
    // objects are retained in the port's per-peer dict across
    // activations, so anything held on a peer's view (e.g. its
    // changed-file selector's last selection) persists across peer
    // swaps. Cross-peer consistency is coordinated externally: every
    // gitStatus / changedFileSelector view reads from a single shared
    // poller, and the active-peer segment on every modeSwitcher is
    // synced on activate.
    //
    // For non-peer sessions (splits/tabs): items were built once when
    // the session was spawned and live in nonPeerToolbarItems.
    @objc
    func toolbarItems(for session: PTYSession) -> [SessionToolbarGenericView] {
        // Peer ports first. A non-peer host that itself runs a peer
        // group (e.g. a split with peer children) is registered
        // BOTH as a non-peer entry (with an empty items list, for
        // teardown tracking) AND as the leader of a nested peer
        // port. Its real toolbar is the port's per-peer list, so
        // the port lookup must win — otherwise the empty items
        // list shadows it and the host's toolbar disappears.
        if let id = peerPort.identifier(for: session) {
            return peerPort.toolbarItems(forPeerID: id)
        }
        for port in nestedPeerPorts {
            if let id = port.identifier(for: session) {
                return port.toolbarItems(forPeerID: id)
            }
        }
        // Leaf non-peer (no peer children). Lookup by reference
        // equality — GUIDs rotate on restart.
        for entry in nonPeerEntriesByConfigID.values where entry.session === session {
            return entry.items
        }
        return []
    }

    // Register a peer port owned by a non-peer host (e.g. a split or
    // tab whose config itself declares peer children). The host
    // session is registered as a non-peer entry (its toolbar comes
    // from the port, so we store an empty items list). The port's
    // own non-leader peers are tracked by reference identity for the
    // sessionWillTerminate observer.
    func registerNestedPeerPort(_ port: iTermWorkgroupPeerPort,
                                hostSession: PTYSession,
                                hostConfig: iTermWorkgroupSessionConfig,
                                peerChildrenPromises: [iTermPromise<PTYSession>]) {
        nestedPeerPorts.append(port)
        // Same back-ref as the main port (set in enter) so a peer-
        // side gitBaseSelector inside the nested group can fan out
        // to non-peer entries.
        port.workgroupInstance = self
        nonPeerOrderedConfigIDs.append(hostConfig.uniqueIdentifier)
        nonPeerEntriesByConfigID[hostConfig.uniqueIdentifier] =
            NonPeerEntry(session: hostSession, items: [])
        trackedSessionIdentities.insert(ObjectIdentifier(hostSession))
        for promise in peerChildrenPromises {
            promise.then { [weak self] peerSession in
                guard let self else { return }
                self.trackedSessionIdentities.insert(ObjectIdentifier(peerSession))
            }
        }
    }

    // Register a freshly-spawned non-peer session (split or tab) with
    // its config-built toolbar items, and wire the workgroup back-
    // pointer so its desiredToolbarItems can find us.
    func registerNonPeer(session: PTYSession,
                        config: iTermWorkgroupSessionConfig) {
        let items = buildNonPeerToolbarItems(for: config)
        nonPeerOrderedConfigIDs.append(config.uniqueIdentifier)
        nonPeerEntriesByConfigID[config.uniqueIdentifier] =
            NonPeerEntry(session: session, items: items)
        trackedSessionIdentities.insert(ObjectIdentifier(session))
        session.workgroupInstance = self
        // Refresh the new session's toolbar view to pick up its items.
        session.delegate?.sessionDidChangeDesiredToolbarItems(session)
    }

    private func buildNonPeerToolbarItems(for config: iTermWorkgroupSessionConfig) -> [SessionToolbarGenericView] {
        let context = WorkgroupToolbarContext(
            peerPort: nil,
            gitPoller: gitPoller,
            scope: mainSession?.genericScope ?? iTermVariableScope(),
            peerGroupMembers: [],
            activePeerIdentifier: "",
            navigationDelegate: self,
            diffSelectorDelegate: self,
            gitBaseSelectorDelegate: self,
            displayName: config.displayName)
        // modeSwitcher only makes sense in a peer group; strip it
        // before injection so .name lands at index 0 on non-peers.
        let configured = config.toolbarItems.filter {
            if case .modeSwitcher = $0 { return false }
            return true
        }
        let augmented = WorkgroupToolbarBuilder.injectAutoItems(into: configured)
        var built: [SessionToolbarGenericView] = []
        for item in augmented {
            if let view = WorkgroupToolbarBuilder.build(
                item: item,
                context: context,
                ownerPeerID: config.uniqueIdentifier) {
                built.append(view)
            }
        }
        return built
    }

    // Activate a peer by ⌥⇧⌘digit shortcut, scoped to whichever peer
    // port owns `session`. Returns true if a peer was activated.
    // Hooked from iTermApplication.handleKeypressInTerminalWindow:
    // — only fires when the active session belongs to a workgroup
    // peer group.
    @objc
    @discardableResult
    func activatePeer(byShortcutDigit digit: Int,
                      fromSession session: PTYSession) -> Bool {
        let owningPort: iTermWorkgroupPeerPort?
        if peerPort.contains(session: session) {
            owningPort = peerPort
        } else {
            owningPort = nestedPeerPorts.first { $0.contains(session: session) }
        }
        guard let owningPort else { return false }
        return owningPort.activatePeer(byShortcutDigit: digit)
    }

    // Look up the live PTY session for a workgroup config UUID. Used
    // by toolbar callbacks (button taps, file picks) that come in
    // tagged with the config UUID; resolves it to whatever live
    // session that config currently corresponds to (peer in main
    // port, peer in a nested port, or non-peer host).
    fileprivate func liveSession(forConfigID configID: String) -> PTYSession? {
        if let s = peerPort.session(forIdentifier: configID) { return s }
        for port in nestedPeerPorts {
            if let s = port.session(forIdentifier: configID) { return s }
        }
        return nonPeerEntriesByConfigID[configID]?.session
    }

    fileprivate func config(forConfigID configID: String) -> iTermWorkgroupSessionConfig? {
        return workgroup.sessions.first(where: {
            $0.uniqueIdentifier == configID
        })
    }

    // Tear down peers, terminate non-peer children, and release
    // references. Leaves the main session in a clean state so a later
    // enter() can install a fresh port — PTYSession.set(peerPort:)
    // asserts the previous port is gone.
    @objc
    func teardown() {
        peerPort.invalidate()
        for port in nestedPeerPorts {
            port.invalidate()
        }
        nestedPeerPorts.removeAll()
        for configID in nonPeerOrderedConfigIDs {
            guard let entry = nonPeerEntriesByConfigID[configID] else { continue }
            entry.session.workgroupInstance = nil
            entry.session.peerPort = nil
            // Skip sessions that have already exited.
            // iTermSessionWillTerminate fires before `exited` is set,
            // so this guard does NOT skip the session that triggered
            // teardown — only ones that exited earlier.
            guard !entry.session.exited else { continue }
            // Defer the actual close to the next runloop. Reason:
            // when teardown is triggered by the leader's
            // iTermSessionWillTerminate notification, the leader is
            // still mid-terminate — its view hasn't been removed
            // from the tab yet. PseudoTerminal.closeSession only
            // closes the tab when sessions.count == 1, and at this
            // moment the count is 2 (the leader plus our child).
            // Dispatching to the next runloop tick lets the leader's
            // removeSession complete first, so when our close runs
            // the child is the only session left and the tab/window
            // closes naturally.
            let session = entry.session
            DispatchQueue.main.async {
                session.delegate?.close(session)
            }
        }
        nonPeerOrderedConfigIDs.removeAll()
        nonPeerEntriesByConfigID.removeAll()
        trackedSessionIdentities.removeAll()
        mainSession?.workgroupInstance = nil
        mainSession?.peerPort = nil
    }

    // MARK: - Entry

    // Build a workgroup instance on the given main session. Tests can
    // pass a fake spawner; production callers should use the default.
    static func enter(workgroup: iTermWorkgroup,
                      on mainSession: PTYSession,
                      spawner: WorkgroupSessionSpawner = DefaultWorkgroupSessionSpawner()) -> iTermWorkgroupInstance? {
        guard let root = workgroup.root else { return nil }

        // Per-entry UUID, generated upfront so peer spawns (which run
        // before the iTermWorkgroupInstance is constructed) can carry
        // it into the spawned sessions' environment as
        // ITERM_WORKGROUP_ID. Prefixed so it's visually distinct from
        // a PTYSession GUID (also a bare UUID) when it shows up in
        // env dumps, logs, or external tooling.
        let instanceUniqueIdentifier = "wg-" + UUID().uuidString

        // Peer-group members = the root + its peer children.
        let peerChildren = workgroup.sessions.filter { s in
            guard s.parentID == root.uniqueIdentifier else { return false }
            if case .peer = s.kind { return true }
            return false
        }
        let peerConfigs: [iTermWorkgroupSessionConfig] = [root] + peerChildren

        // Seed `gitBase` on the leader scope before any spawn so
        // codeReview swifty-string evaluation and downstream
        // consumers (status bar, triggers) see the default value.
        // The peer port re-affirms this on init for safety.
        mainSession.genericScope.setValue(
            CCGitBaseSelectorItem.defaultBase,
            forVariableNamed: "gitBase")

        // Build promises for each peer session. The leader (root) is
        // the already-existing main session; other peers are launched
        // anew via the spawner. Each peer's command is pre-substituted
        // for `\(gitBase)` so the non-swifty spawn path doesn't ship
        // a literal backslash-paren to the shell.
        var peers: [String: iTermPromise<PTYSession>] = [:]
        peers[root.uniqueIdentifier] = iTermPromise<PTYSession>(value: mainSession)
        for peer in peerChildren {
            peers[peer.uniqueIdentifier] =
                spawner.spawnPeer(parent: mainSession,
                                  config: peer.substitutingGitBase(CCGitBaseSelectorItem.defaultBase),
                                  workgroupInstanceID: instanceUniqueIdentifier)
        }

        // Workgroup-wide poller built up front (rather than inside the
        // peer port) so non-peer toolbars can share it. Built only if
        // any session in the WHOLE tree (peer or otherwise) needs git
        // status / changed-file lookup. The closure captures the
        // about-to-be-created instance via a weak local set after
        // construction, avoiding a strong cycle through the poller's
        // update handler.
        let needsPoller = workgroup.sessions.contains { s in
            s.toolbarItems.contains(where: { $0.needsGitPoller })
        }
        weak var instanceForPoller: iTermWorkgroupInstance?
        let poller: iTermGitPoller? = needsPoller
            ? iTermGitPoller(cadence: 2) {
                instanceForPoller?.gitPollerDidUpdate()
            }
            : nil
        poller?.includeDiffStats = true

        let port = iTermWorkgroupPeerPort(
            peers: peers,
            peerConfigs: peerConfigs,
            activeSessionIdentifier: root.uniqueIdentifier,
            leaderIdentifier: root.uniqueIdentifier,
            leaderScope: mainSession.genericScope,
            gitPoller: poller)

        mainSession.peerPort = port

        let instance = iTermWorkgroupInstance(workgroup: workgroup,
                                              instanceUniqueIdentifier: instanceUniqueIdentifier,
                                              mainSession: mainSession,
                                              peerPort: port,
                                              gitPoller: poller,
                                              spawner: spawner)
        instanceForPoller = instance
        // Back-pointer so a peer-side gitBaseSelector change can
        // fan out to non-peer entries' diff selectors via
        // propagateGitBaseToNonPeerSelectors.
        port.workgroupInstance = instance

        // Wire the poller to the leader's PWD so it polls a real
        // directory regardless of whether a gitStatus item exists.
        if let poller {
            let maker = iTermGitStringMaker(scope: mainSession.genericScope,
                                            gitPoller: poller)
            instance.gitDirectoryTracker =
                iTermAutoGitString(stringMaker: maker)
        }

        // Propagate workgroupInstance to every peer (not just the
        // main). desiredToolbarItems on a peer needs to reach the
        // instance to return that peer's own items; without this, a
        // peer ends up with an empty toolbar the moment it's
        // activated.
        for (_, promise) in peers {
            promise.then { peerSession in
                peerSession.workgroupInstance = instance
            }
        }

        // Recursively spawn split-pane and tab children. Each non-peer
        // session that lands is used as the parent for its own children
        // — arbitrary depth works because splitVertically/addSession
        // are synchronous and leave the new session fully installed in
        // the view hierarchy before spawnNonPeerChildren(of:) returns.
        // Peer-group children of a non-peer host are handled separately
        // inside spawnSplit/spawnTab via registerNonPeerOrPeerGroupHost.
        instance.spawnNonPeerChildren(of: mainSession,
                                      parentConfigID: root.uniqueIdentifier)

        return instance
    }

    // Walk the config and spawn every split/tab descendant of the node
    // identified by `parentConfigID`, using `session` as the live parent
    // for the first level. Each spawnSplit/spawnTab call recurses back
    // into this method, so a deeply-nested tree unwinds top-down.
    func spawnNonPeerChildren(of session: PTYSession,
                              parentConfigID: String) {
        let children = workgroup.sessions.filter {
            $0.parentID == parentConfigID
        }
        for child in children {
            switch child.kind {
            case .split:
                spawnSplit(config: child, parent: session)
            case .tab:
                spawnTab(config: child, parent: session)
            case .root, .peer:
                break
            }
        }
    }

    // Fan a poller update out to every git/changed-file view in the
    // workgroup — peer items in the main port, peer items in any
    // nested port, and non-peer-host items. Without iterating non-
    // peer items, a split with a changedFileSelector would have a
    // permanently empty dropdown even though the poller is firing.
    func gitPollerDidUpdate() {
        guard let poller = gitPoller else { return }
        let statuses = poller.state.fileStatuses ?? []
        var allViews: [SessionToolbarGenericView] = []
        allViews.append(contentsOf: peerPort.allToolbarItemViews)
        for port in nestedPeerPorts {
            allViews.append(contentsOf: port.allToolbarItemViews)
        }
        for entry in nonPeerEntriesByConfigID.values {
            allViews.append(contentsOf: entry.items)
        }
        for view in allViews {
            if let gitItem = view as? CCGitSessionToolbarItem {
                gitItem.pollerDidUpdate()
            } else if let selector = view as? CCDiffSelectorItem {
                selector.set(fileStatuses: statuses)
            }
        }
    }
}

extension iTermWorkgroupInstance: iTermGitPollerDelegate {
    func gitPollerShouldPoll(_ poller: iTermGitPoller,
                             after lastPoll: Date?) -> Bool {
        // Instance exists => workgroup is active => poll.
        return true
    }
}

// Navigation taps from non-peer toolbars (split/tab hosts) route
// here. Peer toolbars route through iTermWorkgroupPeerPort which
// has its own conformance. Both end up doing essentially the same
// thing for reload — re-run the configured command in the live
// session — but the lookup paths differ (peer port has its
// peerConfigs dict; the instance walks the full workgroup).
extension iTermWorkgroupInstance: WorkgroupNavigationToolbarItemDelegate {
    func workgroupNavigationDidTapBack(ownerPeerID: String?) {
        guard let configID = ownerPeerID else { return }
        diffSelector(forNonPeerConfigID: configID)?.selectPreviousFile()
    }

    func workgroupNavigationDidTapForward(ownerPeerID: String?) {
        guard let configID = ownerPeerID else { return }
        diffSelector(forNonPeerConfigID: configID)?.selectNextFile()
    }

    func workgroupNavigationDidTapReload(ownerPeerID: String?) {
        guard let configID = ownerPeerID else { return }
        // "Reload" means redo what's currently running — i.e.
        // re-execute the session's program. After a per-file pick
        // restart, that's the per-file command; before any pick,
        // it's whatever the session was launched with. We don't
        // pull cfg.command here because that would always reset to
        // the original entry command, which is not what users
        // expect from a reload button (cf. browser reload).
        guard let session = liveSession(forConfigID: configID),
              session.isRestartable() else {
            return
        }
        // Code-review hosts re-show the prompt overlay so the user
        // can edit their prompt before the program is rerun.
        if session.workgroupSessionMode == .codeReview,
           session.codeReviewRawCommand != nil {
            session.reloadCodeReviewPromptOverlay()
            return
        }
        session.restart()
    }

    // The CFS for a non-peer host (split/tab) by config ID. Peer
    // CFSes live in the peer port's itemsByPeerID; this method
    // intentionally only looks at the non-peer entries.
    private func diffSelector(forNonPeerConfigID id: String) -> CCDiffSelectorItem? {
        return nonPeerEntriesByConfigID[id]?
            .items
            .compactMap { $0 as? CCDiffSelectorItem }
            .first
    }

    // The navigation cluster for a non-peer host's toolbar, used to
    // mirror the diff selector's can-navigate state onto its
    // back/forward buttons. Same scoping rule as diffSelector(...).
    fileprivate func navigationItem(forNonPeerConfigID id: String) -> WorkgroupNavigationToolbarItem? {
        return nonPeerEntriesByConfigID[id]?
            .items
            .compactMap { $0 as? WorkgroupNavigationToolbarItem }
            .first
    }
}

// File picks from a changedFileSelector on a non-peer toolbar route
// here (the peer-toolbar version goes through iTermWorkgroupPeerPort).
extension iTermWorkgroupInstance: CCDiffSelectorItemDelegate {
    func diffDidSelect(filename: String, sender: CCDiffSelectorItem) {
        guard let configID = sender.ownerPeerID,
              let cfg = config(forConfigID: configID),
              !cfg.perFileCommand.isEmpty,
              let session = liveSession(forConfigID: configID) else {
            return
        }
        let command = cfg.resolvedPerFileCommand(filename: filename,
                                                 gitBase: currentGitBase)
        let wrapped = ITAddressBookMgr.commandByWrapping(inLoginShell: command)
        session.restart(withCommand: wrapped)
    }

    func diffDidSelectAllFiles(sender: CCDiffSelectorItem) {
        // See iTermWorkgroupPeerPort.diffDidSelectAllFiles for why
        // there's no isRestartable gate here.
        guard let configID = sender.ownerPeerID,
              let cfg = config(forConfigID: configID),
              !cfg.command.isEmpty,
              let session = liveSession(forConfigID: configID) else {
            return
        }
        let resolved = cfg.resolvedCommand(gitBase: currentGitBase)
        let wrapped = ITAddressBookMgr.commandByWrapping(inLoginShell: resolved)
        session.restart(withCommand: wrapped)
    }

    // Push the diff selector's can-navigate state and the "X/Y"
    // progress label onto the matching non-peer toolbar's navigation
    // cluster. Mirrors the peer-port implementation; see
    // iTermWorkgroupPeerPort.diffNavigationStateDidChange for the
    // rationale and the asynchronous-update story.
    func diffNavigationStateDidChange(sender: CCDiffSelectorItem) {
        guard let configID = sender.ownerPeerID,
              let nav = navigationItem(forNonPeerConfigID: configID) else {
            return
        }
        let position = sender.visibleFilePosition
        let progress = position > 0
            ? "\(position)/\(sender.navigableFileCount)"
            : nil
        nav.setNavigationState(
            canBack: sender.canSelectPreviousFile,
            canForward: sender.canSelectNextFile,
            progress: progress)
    }
}

// gitBaseSelector picks on a non-peer toolbar route here. The
// instance owns the workgroup-wide currentGitBase and every port
// reads through it; both the peer-port and non-peer delegate paths
// funnel into gitBaseChanged below.
extension iTermWorkgroupInstance: CCGitBaseSelectorItemDelegate {
    func gitBaseDidChange(base: String,
                          sender: CCGitBaseSelectorItem) {
        gitBaseChanged(base, fromSender: sender)
    }
}

extension iTermWorkgroupInstance {
    // Workgroup-wide handler for every gitBaseSelector commit.
    // Single source of truth for currentGitBase; broadcasts to
    // every port (so per-file restarts and swifty-string consumers
    // in nested groups stay aligned with the firing port), pushes
    // the new ref into the shared poller (so the changed-file
    // picker repopulates against the new base), then restarts
    // every diff session in the workgroup — the firing peer (if
    // any), plus every non-peer entry with a diff selector.
    //
    // The pre-centralization design had each port own its own
    // currentGitBase and only the firing port updated; nested
    // peer ports + non-peer diff sessions silently desynced. This
    // method exists to make that class of bug structurally
    // impossible.
    @objc
    func gitBaseChanged(_ base: String,
                        fromSender sender: CCGitBaseSelectorItem) {
        currentGitBase = base
        // Sync every port's local cache + leaderScope, and mirror
        // the new value into every gitBaseSelector — peer-side via
        // applyGitBase, non-peer-side here. Without this fan-out,
        // sibling selectors keep showing the old text after another
        // selector committed (state changes workgroup-wide; UI
        // doesn't).
        peerPort.applyGitBase(base)
        for nested in nestedPeerPorts {
            nested.applyGitBase(base)
        }
        for entry in nonPeerEntriesByConfigID.values {
            for view in entry.items {
                (view as? CCGitBaseSelectorItem)?.displayBase(base)
            }
        }
        // Tell the shared poller to compute fileStatuses against
        // the new base. Setting the property invalidates the cache
        // and bumps a fresh poll, fanning out to every
        // CCDiffSelectorItem via gitPollerDidUpdate. nil/HEAD
        // restores the legacy `git status` semantics.
        gitPoller?.gitBase =
            (base == CCGitBaseSelectorItem.defaultBase) ? nil : base
        // Restart every diff session in the workgroup — peer or
        // non-peer — against the new base. Iterating both fan-out
        // helpers covers the firing source as a side effect, so
        // there's no separate "firing source" branch to keep
        // straight: a single gitBase pick on any selector restarts
        // every diff peer / split / tab in the workgroup.
        peerPort.restartAllDiffSelectors()
        for nested in nestedPeerPorts {
            nested.restartAllDiffSelectors()
        }
        propagateGitBaseToNonPeerSelectors()
    }

    // Restart every non-peer entry's diff selector against the
    // current gitBase. Called from gitBaseChanged after every
    // port has been synced, so the cfg.resolvedCommand /
    // resolvedPerFileCommand calls inside diffDidSelect/
    // diffDidSelectAllFiles see the new value.
    @objc
    func propagateGitBaseToNonPeerSelectors() {
        for entry in nonPeerEntriesByConfigID.values {
            let selector = entry.items
                .compactMap { $0 as? CCDiffSelectorItem }
                .first
            guard let selector else { continue }
            if let file = selector.currentlySelectedFilename {
                diffDidSelect(filename: file, sender: selector)
            } else {
                diffDidSelectAllFiles(sender: selector)
            }
        }
    }

    // Try to dispatch a workgroup-toolbar shortcut for `event` while
    // `session` is focused. Returns true iff the shortcut matched a
    // toolbar item on `session`'s config and the corresponding action
    // was fired — the caller (the PTYTextView -> PTYSession key
    // chain) treats that as "handled" and short-circuits the rest of
    // its dispatch (main menu, profile bindings, terminal input).
    //
    // Global key bindings still win: if the keystroke has any global
    // mapping the call returns false so the regular flow handles it.
    // That preserves the user's expectation that a binding configured
    // globally (Keys preferences) is unconditional.
    @objc
    func handleToolbarShortcut(event: NSEvent,
                               focusedSession session: PTYSession) -> Bool {
        let keystroke = iTermKeystroke.withEvent(event)
        if iTermKeyMappings.haveGlobalKeyMapping(for: keystroke) {
            return false
        }
        // Peer-switch shortcuts are workgroup-wide rather than scoped
        // to the focused session's toolbar items: pressing the
        // configured shortcut from any session in the workgroup
        // activates the matching peer (in whichever peer port owns
        // it). Checked before the toolbar-item scan so a peer's
        // jump shortcut can't be accidentally shadowed by an
        // identically-bound navigation/reload key on the focused
        // session's toolbar.
        if activatePeer(matching: keystroke) {
            return true
        }
        guard let configID = configID(forSession: session),
              let config = config(forConfigID: configID) else {
            return false
        }
        let delegate = navigationDelegate(forSession: session)
        for item in config.toolbarItems {
            switch item {
            case .navigation(let shortcuts):
                if Self.shortcutMatches(shortcuts.back, keystroke: keystroke) {
                    delegate?.workgroupNavigationDidTapBack(ownerPeerID: configID)
                    return true
                }
                if Self.shortcutMatches(shortcuts.forward, keystroke: keystroke) {
                    delegate?.workgroupNavigationDidTapForward(ownerPeerID: configID)
                    return true
                }
                if Self.shortcutMatches(shortcuts.reload, keystroke: keystroke) {
                    delegate?.workgroupNavigationDidTapReload(ownerPeerID: configID)
                    return true
                }
            case .reload(let shortcut):
                if Self.shortcutMatches(shortcut, keystroke: keystroke) {
                    delegate?.workgroupNavigationDidTapReload(ownerPeerID: configID)
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    // Activate the peer whose configured `peerSwitchShortcut` matches
    // `keystroke`. Returns true iff a peer was found and activated.
    // Scans every session in the workgroup (not just `.peer` kinds —
    // a peer group's leader is the root or any non-peer host whose
    // children include peers, and that leader sits in the mode
    // switcher alongside the peer children). The live peer port
    // (main or nested) that owns the matching configID handles the
    // activation; ports return false for IDs they don't own.
    // Shortcuts are the user's responsibility to keep unique — on
    // a collision the first matching config in workgroup.sessions
    // order wins.
    private func activatePeer(matching keystroke: iTermKeystroke) -> Bool {
        for cfg in workgroup.sessions {
            guard Self.shortcutMatches(cfg.peerSwitchShortcut,
                                       keystroke: keystroke) else {
                continue
            }
            if peerPort.activate(identifier: cfg.uniqueIdentifier) {
                return true
            }
            for port in nestedPeerPorts {
                if port.activate(identifier: cfg.uniqueIdentifier) {
                    return true
                }
            }
        }
        return false
    }

    // Find the workgroup-config UUID that owns `session`. Mirrors the
    // peer/nested-peer/non-peer order used by toolbarItems(for:); the
    // main session falls back to the workgroup root.
    private func configID(forSession session: PTYSession) -> String? {
        if let id = peerPort.identifier(for: session) { return id }
        for port in nestedPeerPorts {
            if let id = port.identifier(for: session) { return id }
        }
        for (id, entry) in nonPeerEntriesByConfigID where entry.session === session {
            return id
        }
        if session === mainSession {
            return workgroup.root?.uniqueIdentifier
        }
        return nil
    }

    // Pick the WorkgroupNavigationToolbarItemDelegate that matches
    // `session`'s lifecycle owner: peer sessions go through their
    // peer port (so reload restarts the right peer; back/forward
    // reach the port's diff selector), non-peer sessions go through
    // the instance.
    private func navigationDelegate(forSession session: PTYSession)
        -> WorkgroupNavigationToolbarItemDelegate? {
        if peerPort.identifier(for: session) != nil {
            return peerPort
        }
        for port in nestedPeerPorts {
            if port.identifier(for: session) != nil {
                return port
            }
        }
        return self
    }

    private static func shortcutMatches(_ shortcut: WorkgroupToolbarShortcut?,
                                        keystroke: iTermKeystroke) -> Bool {
        guard let serialized = shortcut?.serialized,
              !serialized.isEmpty else {
            return false
        }
        // Use iTermKeystroke's own dictionary lookup so we get the
        // same matching semantics as profile / global key bindings,
        // including language-agnostic and legacy serialization
        // fallbacks. Empty dictionary is the placeholder value; we
        // only care whether the lookup hits.
        let dict: [String: [AnyHashable: Any]] = [serialized: [:]]
        return keystroke.value(inBindingDictionary: dict) != nil
    }
}

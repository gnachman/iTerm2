//
//  iTermWorkgroupPeerPort.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Generalized PTYSessionPeerPort for a workgroup's peer group.
//
// Each peer has its own ordered list of toolbar item VIEWS, built
// fresh from that peer's config. Item views are never shared across
// peers — two peers with the same kind get separate NSView
// instances. Shared state that matters across the group (git status,
// which peer is active) is coordinated out-of-band:
// - The git poller is a single workgroup-wide instance owned by
//   iTermWorkgroupInstance and passed in here. All peer ports
//   (main and nested) plus all non-peer toolbars share that one
//   poller, so updates fan out to every git/changed-file view in
//   the workgroup, and only one git process runs at a time.
// - On activate(identifier:), every peer's modeSwitcher is updated
//   to select the newly-active peer, so each peer's switcher
//   consistently reflects "who's active" rather than "who was
//   picked from this particular switcher".
@objc(iTermWorkgroupPeerPort)
final class iTermWorkgroupPeerPort: PTYSessionPeerPort {
    // Per-peer ordered list of item views, preserving each peer's
    // configured order and allowing duplicates within a single list
    // (two spacers, two separators — both get distinct NSViews).
    private var itemsByPeerID: [String: [SessionToolbarGenericView]] = [:]

    private let peerMembers: [(identifier: String,
                               label: String,
                               shortcut: WorkgroupToolbarShortcut?)]

    // Held so handleButtonTap / diffDidSelect can find the config for
    // the peer whose UI fired the event (for `command` and
    // `perFileCommand` lookup).
    private var peerConfigs: [iTermWorkgroupSessionConfig] = []

    // Variable scope used for swifty-string interpolation in commands
    // and exposed to status-bar / trigger consumers. Stored so the
    // gitBaseSelector can publish `gitBase` here on every change.
    private let leaderScope: iTermVariableScope

    // Cached copy of the workgroup-wide git base ref. The instance
    // owns the canonical value; each port keeps a local copy so
    // the per-file restart path stays decoupled from the instance
    // lifecycle (no `weak workgroupInstance` deref on every diff).
    // Synced via applyGitBase, which the instance calls whenever
    // any selector commits a new value.
    private var currentGitBase: String =
        CCGitBaseSelectorItem.defaultBase

    // Weak back-pointer to the workgroup instance that owns this
    // port. Set by iTermWorkgroupInstance.enter (main port) and
    // registerNestedPeerPort (nested ports). The peer port forwards
    // every gitBaseSelector commit to the instance via this ref so
    // the instance can broadcast the new value to every port (main
    // + nested) and fan out to non-peer entries — keeping all ports
    // in lockstep regardless of which one originated the change.
    @objc weak var workgroupInstance: iTermWorkgroupInstance?

    init(peers: [String: iTermPromise<PTYSession>],
         peerConfigs: [iTermWorkgroupSessionConfig],
         activeSessionIdentifier: String,
         leaderIdentifier: String,
         leaderScope: iTermVariableScope,
         gitPoller: iTermGitPoller?) {
        self.peerMembers = peerConfigs.map { cfg in
            (identifier: cfg.uniqueIdentifier,
             label: cfg.displayName.isEmpty ? "Peer" : cfg.displayName,
             shortcut: cfg.peerSwitchShortcut)
        }
        self.leaderScope = leaderScope

        super.init(peers: peers,
                   activeSessionIdentifier: activeSessionIdentifier,
                   leaderIdentifier: leaderIdentifier)

        // Seed the workgroup-wide `gitBase` variable so commands
        // that reference `\(gitBase)` resolve before the user has
        // touched the gitBaseSelector.
        leaderScope.setValue(currentGitBase,
                             forVariableNamed: "gitBase")

        // Build each peer's ordered list of views fresh. No cross-peer
        // sharing — a second `.spacer(4,4)` in the same list gets its
        // own NSView, and two peers with `.modeSwitcher` get separate
        // instances too. Each item is tagged with its owner peer ID so
        // delegate callbacks (button taps, file picks) know which
        // peer fired them. The context is rebuilt per peer because
        // `displayName` (used by the auto-injected .name item) varies
        // by peer.
        for cfg in peerConfigs {
            let context = WorkgroupToolbarContext(
                peerPort: self,
                gitPoller: gitPoller,
                scope: leaderScope,
                peerGroupMembers: peerMembers,
                activePeerIdentifier: activeSessionIdentifier,
                navigationDelegate: self,
                diffSelectorDelegate: self,
                gitBaseSelectorDelegate: self,
                displayName: cfg.displayName)
            var views: [SessionToolbarGenericView] = []
            let augmented = WorkgroupToolbarBuilder
                .injectAutoItems(into: cfg.toolbarItems)
            for item in augmented {
                if let view = WorkgroupToolbarBuilder.build(
                    item: item,
                    context: context,
                    ownerPeerID: cfg.uniqueIdentifier) {
                    views.append(view)
                }
            }
            itemsByPeerID[cfg.uniqueIdentifier] = views
        }
        self.peerConfigs = peerConfigs
    }

    override func activate(identifier: String) -> Bool {
        guard super.activate(identifier: identifier) else { return false }
        // Keep every peer's modeSwitcher visually in sync with the
        // newly-active peer — otherwise if you tap "Diff" on Main's
        // switcher and later come back to Main, Main's switcher would
        // still show "Diff" highlighted.
        for views in itemsByPeerID.values {
            for view in views {
                (view as? WorkgroupModeSwitcherItem)?
                    .setActiveIdentifier(identifier)
            }
        }
        // No explicit sessionDidChangeDesiredToolbarItems here:
        // super.activate's promise handler runs sessionActivate,
        // which calls updatePaneTitles → setToolbarItems on every
        // session in the tab. That picks up the per-peer items.
        return true
    }

    // The ordered list of toolbar items for a specific peer.
    @objc
    func toolbarItems(forPeerID id: String) -> [SessionToolbarGenericView] {
        return itemsByPeerID[id] ?? []
    }

    // Activate the peer mapped to a ⌥⇧⌘digit shortcut. Returns true
    // if a peer was activated, false when the digit doesn't map (no
    // matching peer, e.g. ⌥⇧⌘8 with 5 peers). 9 always picks the
    // last peer; 1..8 pick directly when in range.
    @discardableResult
    func activatePeer(byShortcutDigit digit: Int) -> Bool {
        let count = peerConfigs.count
        guard count > 0 else { return false }
        let targetIndex: Int
        switch digit {
        case 1...8:
            guard digit <= count else { return false }
            targetIndex = digit - 1
        case 9:
            targetIndex = count - 1
        default:
            return false
        }
        return activate(identifier: peerConfigs[targetIndex].uniqueIdentifier)
    }

    // Number of peers in the group — exposed so the Workgroups menu can
    // disable the next/previous-peer items when there's nothing to cycle.
    @objc var peerCount: Int { peerConfigs.count }

    // Display label for the peer registered under `id` — falls back to
    // "Peer" when the config's displayName is empty (matches how
    // peerLabel renders in WorkgroupVisualView and the mode switcher).
    @objc func label(forPeerID id: String) -> String? {
        return peerMembers.first { $0.identifier == id }?.label
    }

    // 1-based position of the peer registered under `id` in the peer
    // configs, or 0 when not found. Used to compute the peer's
    // ⌥⇧⌘<digit> activation shortcut for display.
    @objc func position(forPeerID id: String) -> Int {
        guard let i = peerConfigs.firstIndex(where: {
            $0.uniqueIdentifier == id
        }) else {
            return 0
        }
        return i + 1
    }

    @objc @discardableResult
    func activateNextPeer() -> Bool {
        return activatePeer(byOffset: 1)
    }

    @objc @discardableResult
    func activatePreviousPeer() -> Bool {
        return activatePeer(byOffset: -1)
    }

    private func activatePeer(byOffset offset: Int) -> Bool {
        let count = peerConfigs.count
        guard count > 1 else { return false }
        let currentID = activeSessionIdentifier
        let baseIndex = peerConfigs.firstIndex { $0.uniqueIdentifier == currentID } ?? 0
        // Modulo with sign correction so a negative offset wraps to the end.
        let targetIndex = ((baseIndex + offset) % count + count) % count
        return activate(identifier: peerConfigs[targetIndex].uniqueIdentifier)
    }

    // Flat list of every toolbar item view across all peers — used by
    // the workgroup instance to fan out poller updates without having
    // to know about per-peer organization.
    var allToolbarItemViews: [SessionToolbarGenericView] {
        return Array(itemsByPeerID.values.joined())
    }

    // Adopt a new git base ref pushed by the workgroup instance.
    // Updates the local cache + the per-port leaderScope variable
    // so swifty-string consumers in this port's session group see
    // the same value the instance just committed. Does NOT trigger
    // restarts — those are orchestrated by the instance after every
    // port has been synced. Call this rather than mutating
    // currentGitBase / leaderScope directly so future sync work
    // (e.g. driving toolbar items to display the new value) only
    // needs to be added in one place.
    @objc
    func applyGitBase(_ base: String) {
        currentGitBase = base
        leaderScope.setValue(base, forVariableNamed: "gitBase")
        // Mirror the new value into every gitBaseSelector in this
        // port's toolbar items so sibling selectors (e.g. another
        // peer in the same group, or the same selector duplicated
        // across peers) don't keep showing the old text after a
        // different selector committed.
        for views in itemsByPeerID.values {
            for view in views {
                (view as? CCGitBaseSelectorItem)?.displayBase(base)
            }
        }
    }

    // The peer's CFS, if it has one. Internal so back/forward can
    // route their click here for the per-file restart path.
    func diffSelector(forPeerID id: String?) -> CCDiffSelectorItem? {
        guard let id else { return nil }
        return itemsByPeerID[id]?
            .compactMap { $0 as? CCDiffSelectorItem }
            .first
    }

    // The peer's navigation cluster, if any — used to push the diff
    // selector's can-navigate state onto the back/forward buttons.
    private func navigationItem(forPeerID id: String?) -> WorkgroupNavigationToolbarItem? {
        guard let id else { return nil }
        return itemsByPeerID[id]?
            .compactMap { $0 as? WorkgroupNavigationToolbarItem }
            .first
    }

    // Restart every peer in this port whose toolbar has a diff
    // selector against the current base. Called by the workgroup
    // instance from gitBaseChanged so every running diff session
    // — firing or not, including a different peer port's diff peer
    // in nested workgroups — re-runs against the new ref. The
    // current-file vs All-Files decision is made per-selector so
    // each peer keeps its own visible filter.
    @objc
    func restartAllDiffSelectors() {
        for views in itemsByPeerID.values {
            for view in views {
                guard let selector = view as? CCDiffSelectorItem else {
                    continue
                }
                if let file = selector.currentlySelectedFilename {
                    diffDidSelect(filename: file, sender: selector)
                } else {
                    diffDidSelectAllFiles(sender: selector)
                }
            }
        }
    }
}

// MARK: - Navigation delegate

extension iTermWorkgroupPeerPort: WorkgroupNavigationToolbarItemDelegate {
    func workgroupNavigationDidTapBack(ownerPeerID: String?) {
        diffSelector(forPeerID: ownerPeerID)?.selectPreviousFile()
    }

    func workgroupNavigationDidTapForward(ownerPeerID: String?) {
        diffSelector(forPeerID: ownerPeerID)?.selectNextFile()
    }

    func workgroupNavigationDidTapReload(ownerPeerID: String?) {
        guard let ownerPeerID,
              let session = session(forIdentifier: ownerPeerID),
              session.isRestartable() else {
            return
        }
        // Code-review peers re-show the prompt overlay so the user can
        // edit their prompt before the program is rerun.
        if session.workgroupSessionMode == .codeReview,
           session.codeReviewRawCommand != nil {
            session.reloadCodeReviewPromptOverlay()
            return
        }
        // Reload re-runs whatever the session is currently set to run
        // (its _program), not the original cfg.command — same
        // rationale as the workgroup instance's reload path.
        session.restart()
    }
}

// MARK: - Toolbar item delegates

extension iTermWorkgroupPeerPort: WorkgroupModeSwitcherItemDelegate {
    func workgroupModeSwitcher(_ item: WorkgroupModeSwitcherItem,
                               didSelect identifier: String) {
        _ = activate(identifier: identifier)
    }
}

extension iTermWorkgroupPeerPort: CCDiffSelectorItemDelegate {
    func diffDidSelect(filename: String,
                       sender: CCDiffSelectorItem) {
        DLog("iTermWorkgroupPeerPort.diffDidSelect \(filename) owner=\(sender.ownerPeerID ?? "nil")")
        guard let ownerPeerID = sender.ownerPeerID,
              let cfg = peerConfigs.first(where: {
                  $0.uniqueIdentifier == ownerPeerID
              }),
              !cfg.perFileCommand.isEmpty,
              let session = session(forIdentifier: ownerPeerID) else {
            return
        }
        // Substitute \(file) and \(gitBase) before sending so the
        // shell never sees the template — that avoids any
        // backslash-paren shell parsing.
        let command = cfg.resolvedPerFileCommand(filename: filename,
                                                 gitBase: currentGitBase)
        guard !command.isEmpty else { return }
        let wrapped = ITAddressBookMgr.commandByWrapping(inLoginShell: command)
        session.restart(withCommand: wrapped)
    }

    // Mirror the diff selector's can-navigate predicates onto the
    // peer's back/forward buttons, plus the "X/Y" progress label
    // between them. Fires on file-list reloads (driven by the shared
    // git poller), popup picks, and after each button-driven advance
    // — so the cluster reflects state immediately for both
    // synchronous user actions and asynchronous repo changes.
    func diffNavigationStateDidChange(sender: CCDiffSelectorItem) {
        guard let nav = navigationItem(forPeerID: sender.ownerPeerID) else { return }
        let position = sender.visibleFilePosition
        let progress = position > 0
            ? "\(position)/\(sender.navigableFileCount)"
            : nil
        nav.setNavigationState(
            canBack: sender.canSelectPreviousFile,
            canForward: sender.canSelectNextFile,
            progress: progress)
    }

    // "All Files" is the menu's escape hatch back to the workgroup's
    // entry command — what diff would show with no filter. Restart
    // the peer with cfg.command, NOT cfg.perFileCommand.
    func diffDidSelectAllFiles(sender: CCDiffSelectorItem) {
        DLog("iTermWorkgroupPeerPort.diffDidSelectAllFiles owner=\(sender.ownerPeerID ?? "nil")")
        // No isRestartable gate — restart(withCommand:) early-returns
        // for non-restartable sessions internally (PTYSession.m:3399),
        // and matching the per-file path's lack of gate keeps both
        // CFS-driven restart shapes consistent.
        guard let ownerPeerID = sender.ownerPeerID,
              let cfg = peerConfigs.first(where: {
                  $0.uniqueIdentifier == ownerPeerID
              }),
              !cfg.command.isEmpty,
              let session = session(forIdentifier: ownerPeerID) else {
            return
        }
        let resolved = cfg.resolvedCommand(gitBase: currentGitBase)
        let wrapped = ITAddressBookMgr.commandByWrapping(inLoginShell: resolved)
        session.restart(withCommand: wrapped)
    }
}

extension iTermWorkgroupPeerPort: CCGitBaseSelectorItemDelegate {
    // Thin pass-through. The instance owns the workgroup-wide
    // gitBase value and is responsible for syncing it to every
    // port (main + nested), updating the poller, and restarting
    // both the firing peer and every non-peer diff session — see
    // iTermWorkgroupInstance.gitBaseChanged. Centralizing the
    // logic there is what keeps nested ports from desyncing when
    // a selector on a different port commits.
    func gitBaseDidChange(base: String,
                          sender: CCGitBaseSelectorItem) {
        DLog("iTermWorkgroupPeerPort.gitBaseDidChange \(base) owner=\(sender.ownerPeerID ?? "nil")")
        workgroupInstance?.gitBaseChanged(base, fromSender: sender)
    }
}

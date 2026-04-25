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

    private let peerMembers: [(identifier: String, label: String)]

    // Held so handleButtonTap / diffDidSelect can find the config for
    // the peer whose UI fired the event (for `command` and
    // `perFileCommand` lookup).
    private var peerConfigs: [iTermWorkgroupSessionConfig] = []

    init(peers: [String: iTermPromise<PTYSession>],
         peerConfigs: [iTermWorkgroupSessionConfig],
         activeSessionIdentifier: String,
         leaderIdentifier: String,
         leaderScope: iTermVariableScope,
         gitPoller: iTermGitPoller?) {
        self.peerMembers = peerConfigs.map { cfg in
            (identifier: cfg.uniqueIdentifier,
             label: cfg.displayName.isEmpty ? "Peer" : cfg.displayName)
        }

        super.init(peers: peers,
                   activeSessionIdentifier: activeSessionIdentifier,
                   leaderIdentifier: leaderIdentifier)

        let context = WorkgroupToolbarContext(
            peerPort: self,
            gitPoller: gitPoller,
            scope: leaderScope,
            peerGroupMembers: peerMembers,
            activePeerIdentifier: activeSessionIdentifier,
            buttonDelegate: self,
            diffSelectorDelegate: self)

        // Build each peer's ordered list of views fresh. No cross-peer
        // sharing — a second `.spacer(4,4)` in the same list gets its
        // own NSView, and two peers with `.modeSwitcher` get separate
        // instances too. Each item is tagged with its owner peer ID so
        // delegate callbacks (button taps, file picks) know which
        // peer fired them.
        for cfg in peerConfigs {
            var views: [SessionToolbarGenericView] = []
            for item in cfg.toolbarItems {
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

    // Flat list of every toolbar item view across all peers — used by
    // the workgroup instance to fan out poller updates without having
    // to know about per-peer organization.
    var allToolbarItemViews: [SessionToolbarGenericView] {
        return Array(itemsByPeerID.values.joined())
    }

    // MARK: - Private

    private func handleButtonTap(kind: iTermWorkgroupToolbarItemKind,
                                 ownerPeerID: String?) {
        switch kind {
        case .reload:
            guard let ownerPeerID,
                  let session = session(forIdentifier: ownerPeerID),
                  session.isRestartable() else {
                return
            }
            // Reload re-runs whatever the session is currently set to
            // run (its _program), not the original cfg.command — see
            // iTermWorkgroupInstance.toolbarButtonSelected for the
            // rationale.
            session.restart()
        case .back, .forward, .settings:
            // TODO: wire once we have peer-specific behavior.
            break
        case .gitStatus, .changedFileSelector, .modeSwitcher, .spacer:
            break
        }
    }
}

// MARK: - Button delegate

// The builder sets each back/forward/reload/settings button's
// identifier to the kind's rawValue, so we can decode it back here.
extension iTermWorkgroupPeerPort: CCModeButtonToolbarItemDelegate {
    func toolbarButtonSelected(identifier: String,
                               sender: CCModeButtonToolbarItem) {
        guard let kind = iTermWorkgroupToolbarItemKind(rawValue: identifier)
            else { return }
        handleButtonTap(kind: kind, ownerPeerID: sender.ownerPeerID)
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
        // Substitute \(file) with the picked path. We do the
        // substitution before sending so the shell never sees the
        // template — that avoids any backslash-paren shell parsing.
        let command = cfg.resolvedPerFileCommand(filename: filename)
        guard !command.isEmpty else { return }
        session.restart(withCommand: command)
    }
}

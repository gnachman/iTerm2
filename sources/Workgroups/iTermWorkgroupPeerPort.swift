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
// - The git poller is a single instance held by the port; every
//   peer's gitStatus / changedFileSelector view reads from it, so
//   all views show the same current git state regardless of which
//   peer you're looking at.
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

    // Held so every toolbar item consumer keeps the same shared poller.
    // nil if no peer's toolbar item needed one.
    @objc private(set) var gitPoller: iTermGitPoller?

    private let peerMembers: [(identifier: String, label: String)]

    init(peers: [String: iTermPromise<PTYSession>],
         peerConfigs: [iTermWorkgroupSession],
         activeSessionIdentifier: String,
         leaderIdentifier: String,
         leaderScope: iTermVariableScope) {
        self.peerMembers = peerConfigs.map { cfg in
            (identifier: cfg.uniqueIdentifier,
             label: cfg.displayName.isEmpty ? "Peer" : cfg.displayName)
        }

        super.init(peers: peers,
                   activeSessionIdentifier: activeSessionIdentifier,
                   leaderIdentifier: leaderIdentifier)

        // Build shared git poller only if any peer asked for it.
        let anyNeedsGit = peerConfigs.contains { cfg in
            cfg.toolbarItems.contains(where: { $0.needsGitPoller })
        }
        if anyNeedsGit {
            let poller = iTermGitPoller(cadence: 2) { [weak self] in
                self?.pollerDidUpdate()
            }
            poller.includeDiffStats = true
            poller.delegate = self
            self.gitPoller = poller
        }

        let context = WorkgroupToolbarContext(
            peerPort: self,
            gitPoller: self.gitPoller,
            scope: leaderScope,
            peerGroupMembers: peerMembers,
            activePeerIdentifier: activeSessionIdentifier,
            buttonDelegate: self)

        // Build each peer's ordered list of views fresh. No cross-peer
        // sharing — a second `.spacer(4,4)` in the same list gets its
        // own NSView, and two peers with `.modeSwitcher` get separate
        // instances too.
        for cfg in peerConfigs {
            var views: [SessionToolbarGenericView] = []
            for item in cfg.toolbarItems {
                if let view = WorkgroupToolbarBuilder.build(item: item, context: context) {
                    views.append(view)
                }
            }
            itemsByPeerID[cfg.uniqueIdentifier] = views
        }
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

    // MARK: - Private

    private func pollerDidUpdate() {
        guard let poller = gitPoller else { return }
        let files = poller.state.dirtyFiles ?? []
        for views in itemsByPeerID.values {
            for view in views {
                if let gitItem = view as? CCGitSessionToolbarItem {
                    gitItem.pollerDidUpdate()
                } else if let selector = view as? CCDiffSelectorItem {
                    selector.set(files: files)
                }
            }
        }
    }

    private func handleButtonTap(kind: iTermWorkgroupToolbarItemKind) {
        DLog("iTermWorkgroupPeerPort.handleButtonTap \(kind)")
        // Back/forward/reload/settings are TODO — wire them to peer-
        // specific behavior once that behavior exists.
    }
}

// MARK: - Button delegate

// The builder sets each back/forward/reload/settings button's
// identifier to the kind's rawValue, so we can decode it back here.
extension iTermWorkgroupPeerPort: CCModeButtonToolbarItemDelegate {
    func toolbarButtonSelected(identifier: String) {
        guard let kind = iTermWorkgroupToolbarItemKind(rawValue: identifier)
            else { return }
        handleButtonTap(kind: kind)
    }
}

// MARK: - iTermGitPollerDelegate

extension iTermWorkgroupPeerPort: iTermGitPollerDelegate {
    func gitPollerShouldPoll(_ poller: iTermGitPoller,
                             after lastPoll: Date?) -> Bool {
        // Port exists => workgroup toolbar exists => poll.
        return true
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
    func diffDidSelect(filename: String) {
        DLog("iTermWorkgroupPeerPort.diffDidSelect \(filename)")
        // TODO: run `git difftool <filename>` in the Diff peer session.
    }
}

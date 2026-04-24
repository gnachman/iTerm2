//
//  iTermWorkgroupPeerPort.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Generalized PTYSessionPeerPort for a workgroup's peer group.
//
// Toolbar items are built as the UNION of every peer's toolbar list
// (deduped, so e.g. a mode-switcher present on multiple peers becomes
// one shared instance). On activate(identifier:), each item's `enabled`
// flag is flipped according to whether the newly-active peer declared
// it. This mirrors the pattern the old ClaudeCodePeerPort used —
// reparenting one toolbar view across peer swaps while hiding/showing
// items — so state (segmented selection, git text, etc.) carries over.
@objc(iTermWorkgroupPeerPort)
final class iTermWorkgroupPeerPort: PTYSessionPeerPort {
    // One entry per item in the union, kept in display order.
    @objc private(set) var toolbarItems: [SessionToolbarGenericView] = []
    // Set of item values enabled per peer uniqueIdentifier.
    private var enabledByPeerID: [String: Set<iTermWorkgroupToolbarItem>] = [:]
    // Parallel array keyed by toolbarItems index → the enum value used
    // to look up in enabledByPeerID.
    private var itemValues: [iTermWorkgroupToolbarItem] = []
    // Held so every toolbar item consumer keeps the same shared poller.
    // nil if no peer's toolbar item needed one.
    @objc private(set) var gitPoller: iTermGitPoller?

    // Peer-group member metadata (identifier + label) captured at init
    // time. Used to populate the mode switcher and to validate
    // activate(identifier:) calls.
    private let peerMembers: [(identifier: String, label: String)]

    init(peers: [String: iTermPromise<PTYSession>],
         peerConfigs: [iTermWorkgroupSession],
         activeSessionIdentifier: String,
         leaderIdentifier: String,
         leaderScope: iTermVariableScope) {
        // Ordered list of members = configs in the order they appear.
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
            onButtonTapped: { [weak self] kind in
                self?.handleButtonTap(kind: kind)
            })

        let built = WorkgroupToolbarBuilder.buildUnion(
            fromSessions: peerConfigs,
            context: context)
        self.toolbarItems = built.map { $0.view }
        self.itemValues = built.map { $0.item }

        var masks: [String: Set<iTermWorkgroupToolbarItem>] = [:]
        for cfg in peerConfigs {
            masks[cfg.uniqueIdentifier] = Set(cfg.toolbarItems)
        }
        self.enabledByPeerID = masks

        applyEnabledMask(forPeerID: activeSessionIdentifier)
    }

    override func activate(identifier: String) -> Bool {
        guard super.activate(identifier: identifier) else { return false }
        applyEnabledMask(forPeerID: identifier)
        (toolbarItems.first {
            $0 is WorkgroupModeSwitcherItem
        } as? WorkgroupModeSwitcherItem)?.setActiveIdentifier(identifier)
        return true
    }

    // MARK: - Private

    private func applyEnabledMask(forPeerID identifier: String) {
        let mask = enabledByPeerID[identifier] ?? []
        for (view, value) in zip(toolbarItems, itemValues) {
            view.enabled = mask.contains(value)
        }
        // Nudge the live layout — flipping enabled alone doesn't
        // trigger relayout on the surrounding SessionToolbarView.
        requestToolbarLayout()
    }

    private func requestToolbarLayout() {
        for item in toolbarItems {
            if let delegate = item.delegate {
                delegate.itemDidChange(sender: item)
                return
            }
        }
    }

    private func pollerDidUpdate() {
        guard let poller = gitPoller else { return }
        let files = poller.state.dirtyFiles ?? []
        for view in toolbarItems {
            if let gitItem = view as? CCGitSessionToolbarItem {
                gitItem.pollerDidUpdate()
            } else if let selector = view as? CCDiffSelectorItem {
                selector.set(files: files)
            }
        }
    }

    private func handleButtonTap(kind: String) {
        DLog("iTermWorkgroupPeerPort.handleButtonTap \(kind)")
        // Back/forward/reload/settings are TODO — wire them to peer-
        // specific behavior once that behavior exists.
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

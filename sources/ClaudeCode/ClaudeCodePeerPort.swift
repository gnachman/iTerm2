//
//  ClaudeCodePeerPort.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import Foundation

// A PTYSessionPeerPort specialized for Claude Code. Owns the CC toolbar items
// and the shared git poller. Items live on the port so they stay alive and
// keep their state (segmented-control selection, git state, diff selection)
// across peer swaps. The port implements the delegate protocols those items
// need and forwards to the active peer session where appropriate.
@objc(iTermClaudeCodePeerPort)
class ClaudeCodePeerPort: PTYSessionPeerPort {
    // Toolbar item identifiers — shared with Obj-C callers that look items up.
    @objc static let leftSpacerIdentifier = "ccLeftSpacer"
    @objc static let rightSpacerIdentifier = "ccRightSpacer"
    @objc static let modeSwitcherIdentifier = "ccMode"
    @objc static let gitStatusIdentifier = "ccGitStatus"
    @objc static let diffSelectorIdentifier = "ccDiffSelector"
    @objc static let diffBackIdentifier = "ccDiffBack"
    @objc static let diffForwardIdentifier = "ccDiffForward"
    @objc static let diffSettingsIdentifier = "ccDiffSettings"
    @objc static let codeReviewReloadIdentifier = "ccCodeReviewReload"

    // Defaults for the command each peer kind launches. Exposed statically so
    // installClaudeCodePeers can use them when building the initial peers
    // (before the port instance itself exists).
    @objc static let defaultCommands: [String: String] = [
        PTYSessionClaudeCodePeerIdentifier.diff.rawValue: "git diff",
        PTYSessionClaudeCodePeerIdentifier.codeReview.rawValue:
            "claude -p 'Review the pending change in this git repository for correctness and completeness.'"
    ]

    private static let peerDisplayNames: [String: String] = [
        PTYSessionClaudeCodePeerIdentifier.diff.rawValue: "Diff",
        PTYSessionClaudeCodePeerIdentifier.codeReview.rawValue: "Code Review"
    ]

    @objc private(set) var toolbarItems: [SessionToolbarGenericView] = []
    @objc private(set) var gitPoller: iTermGitPoller!

    // Per-peer settings. For now, just the command; eventually this might
    // grow (pane kind, URL for browser-backed peers, env vars, …).
    private var peerCommands: [String: String]

    private var modeItem: CCModeSwitchSessionToolbarItem!
    private var gitItem: CCGitSessionToolbarItem!
    private var diffSelector: CCDiffSelectorItem!
    private var backButton: CCModeButtonToolbarItem!
    private var forwardButton: CCModeButtonToolbarItem!
    private var reloadButton: CCModeButtonToolbarItem!
    private var settingsButton: CCModeButtonToolbarItem!
    private var settingsPopover: NSPopover?

    @objc
    init(peers: [String: iTermPromise<PTYSession>],
         activeSessionIdentifier: String,
         leaderIdentifier: String,
         leaderScope: iTermVariableScope) {
        self.peerCommands = Self.defaultCommands
        super.init(peers: peers,
                   activeSessionIdentifier: activeSessionIdentifier,
                   leaderIdentifier: leaderIdentifier)

        // Now self is available — construct everything here.
        gitPoller = iTermGitPoller(cadence: 2) { [weak self] in
            self?.pollerDidUpdate()
        }
        gitPoller.includeDiffStats = true
        gitPoller.delegate = self

        let leftSpacer = SessionToolbarSpacer(identifier: Self.leftSpacerIdentifier,
                                              priority: 1,
                                              minWidth: 4,
                                              maxWidth: 4)
        let rightSpacer = SessionToolbarSpacer(identifier: Self.rightSpacerIdentifier,
                                               priority: 1,
                                               minWidth: 4,
                                               maxWidth: 4)
        modeItem = CCModeSwitchSessionToolbarItem(identifier: Self.modeSwitcherIdentifier,
                                                  priority: 1,
                                                  mode: Self.mode(forIdentifier: activeSessionIdentifier))
        modeItem.modeSwitchDelegate = self

        gitItem = CCGitSessionToolbarItem(identifier: Self.gitStatusIdentifier,
                                          priority: 2,
                                          scope: leaderScope,
                                          poller: gitPoller)

        diffSelector = CCDiffSelectorItem(identifier: Self.diffSelectorIdentifier,
                                          priority: 2,
                                          poller: gitPoller)
        diffSelector.diffSelectorDelegate = self

        let backImage = NSImage(systemSymbolName: SFSymbol.chevronLeft.rawValue,
                                accessibilityDescription: nil) ?? NSImage()
        let forwardImage = NSImage(systemSymbolName: SFSymbol.chevronRight.rawValue,
                                   accessibilityDescription: nil) ?? NSImage()
        let reloadImage = NSImage(systemSymbolName: SFSymbol.arrowClockwise.rawValue,
                                  accessibilityDescription: nil) ?? NSImage()
        let settingsImage = NSImage(systemSymbolName: SFSymbol.gearshape.rawValue,
                                    accessibilityDescription: "Diff settings") ?? NSImage()
        backButton = CCModeButtonToolbarItem(identifier: Self.diffBackIdentifier,
                                             priority: 3,
                                             image: backImage)
        backButton.buttonDelegate = self
        forwardButton = CCModeButtonToolbarItem(identifier: Self.diffForwardIdentifier,
                                                priority: 3,
                                                image: forwardImage)
        forwardButton.buttonDelegate = self
        reloadButton = CCModeButtonToolbarItem(identifier: Self.codeReviewReloadIdentifier,
                                               priority: 3,
                                               image: reloadImage)
        reloadButton.buttonDelegate = self
        settingsButton = CCModeButtonToolbarItem(identifier: Self.diffSettingsIdentifier,
                                                 priority: 3,
                                                 image: settingsImage)
        settingsButton.buttonDelegate = self

        toolbarItems = [leftSpacer, modeItem, gitItem, diffSelector,
                        backButton, forwardButton, reloadButton,
                        settingsButton, rightSpacer]

        customizeItems(for: Self.mode(forIdentifier: activeSessionIdentifier))
    }

    @objc(toolbarItemWithIdentifier:)
    func toolbarItem(withIdentifier identifier: String) -> SessionToolbarGenericView? {
        return toolbarItems.first(where: { $0.identifier == identifier })
    }

    @objc
    func customizeItems(for mode: iTermCCMode) {
        let desiredIDs: Set<String>
        switch mode {
        case .CLI:
            desiredIDs = [Self.leftSpacerIdentifier,
                          Self.modeSwitcherIdentifier,
                          Self.gitStatusIdentifier,
                          Self.rightSpacerIdentifier]
        case .diff:
            desiredIDs = [Self.leftSpacerIdentifier,
                          Self.modeSwitcherIdentifier,
                          Self.diffSelectorIdentifier,
                          Self.diffBackIdentifier,
                          Self.diffForwardIdentifier,
                          Self.diffSettingsIdentifier,
                          Self.rightSpacerIdentifier]
        case .codeReview:
            desiredIDs = [Self.leftSpacerIdentifier,
                          Self.modeSwitcherIdentifier,
                          Self.codeReviewReloadIdentifier,
                          Self.rightSpacerIdentifier]
        @unknown default:
            desiredIDs = []
        }
        for item in toolbarItems {
            item.enabled = desiredIDs.contains(item.identifier)
        }
        // Flipping `enabled` doesn't automatically tell the surrounding
        // SessionToolbarView to re-run its filter-and-layout pass, so the
        // toolbar would otherwise only redraw once updatePaneTitles fires
        // (post tab-swap, up to ~cadence later). Nudge it now via any item
        // whose delegate points at the live toolbar view.
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

    // Called by the poller on every update. Fans out to every consumer of the
    // shared poller (the poller supports only one update block).
    private func pollerDidUpdate() {
        let files = gitPoller.state.dirtyFiles ?? []
        DLog("ClaudeCodePeerPort.pollerDidUpdate — \(files.count) dirty files")
        gitItem.pollerDidUpdate()
        diffSelector.set(files: files)
    }

    private static func mode(forIdentifier identifier: String) -> iTermCCMode {
        switch PTYSessionClaudeCodePeerIdentifier(rawValue: identifier) {
        case .claudeCode: return .CLI
        case .diff: return .diff
        case .codeReview: return .codeReview
        case .none: return .CLI
        }
    }

    override func activate(identifier: String) -> Bool {
        // Update our own enabled-flags synchronously for the new mode, then
        // chain through to the base implementation so the tab does the swap.
        guard super.activate(identifier: identifier) else {
            return false
        }
        customizeItems(for: Self.mode(forIdentifier: identifier))
        return true
    }
}

// MARK: - iTermGitPollerDelegate

extension ClaudeCodePeerPort: iTermGitPollerDelegate {
    func gitPollerShouldPoll(_ poller: iTermGitPoller, after lastPoll: Date?) -> Bool {
        // Port exists => CC toolbar exists => poll.
        return true
    }
}

// MARK: - Toolbar item delegates

extension ClaudeCodePeerPort: CCModeSwitchSessionToolbarItemDelegate {
    func ccModeDidChange(mode: iTermCCMode) {
        let identifier: String
        switch mode {
        case .CLI:
            identifier = PTYSessionClaudeCodePeerIdentifier.claudeCode.rawValue
        case .diff:
            identifier = PTYSessionClaudeCodePeerIdentifier.diff.rawValue
        case .codeReview:
            identifier = PTYSessionClaudeCodePeerIdentifier.codeReview.rawValue
        @unknown default:
            return
        }
        _ = activate(identifier: identifier)
    }
}

extension ClaudeCodePeerPort: CCDiffSelectorItemDelegate {
    func diffDidSelect(filename: String) {
        DLog("ClaudeCodePeerPort.diffDidSelect \(filename)")
        // TODO: run `git difftool <filename>` in the diff peer session.
    }
}

extension ClaudeCodePeerPort: CCModeButtonToolbarItemDelegate {
    func toolbarButtonSelected(identifier: String) {
        DLog("ClaudeCodePeerPort.toolbarButtonSelected \(identifier)")
        switch identifier {
        case Self.diffSettingsIdentifier:
            showSettings(forPeer: PTYSessionClaudeCodePeerIdentifier.diff.rawValue,
                         anchor: settingsButton)
        default:
            // TODO: act on back/forward/reload buttons.
            break
        }
    }
}

// MARK: - Settings

extension ClaudeCodePeerPort {
    @objc
    func command(forPeer identifier: String) -> String {
        return peerCommands[identifier] ?? ""
    }

    @objc
    func setCommand(_ command: String, forPeer identifier: String) {
        peerCommands[identifier] = command
        // The running peer session isn't rebuilt here; the new command takes
        // effect the next time that peer session is (re)launched.
    }

    private func showSettings(forPeer peerIdentifier: String,
                              anchor: CCModeButtonToolbarItem) {
        if let existing = settingsPopover, existing.isShown {
            existing.close()
            settingsPopover = nil
            return
        }
        let displayName = Self.peerDisplayNames[peerIdentifier] ?? peerIdentifier
        let vc = PeerSessionSettingsViewController(
            peerDisplayName: displayName,
            command: command(forPeer: peerIdentifier))
        vc.onCommandChange = { [weak self] newCommand in
            self?.setCommand(newCommand, forPeer: peerIdentifier)
        }
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        let anchorView = anchor._view
        popover.show(relativeTo: anchorView.bounds,
                     of: anchorView,
                     preferredEdge: .minY)
        settingsPopover = popover
    }
}

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

    // Observes session tab-status changes so each peer's mode switcher
    // can spin its activity indicator while that peer is in the working
    // state. Registered for all sessions (object: nil) and gated to this
    // port's peers in the handler.
    private var tabStatusObserver: NSObjectProtocol?

    // Last observed idle/working/waiting state per peer identifier. Used to
    // detect the working -> idle edge that drives the code-review auto-send-
    // clippings toggle (see maybeAutoSendClippings).
    private var lastPeerState: [String: SessionState] = [:]

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
                displayName: cfg.displayName,
                autoSendClippingsDelegate: self,
                autoSendClippingsInitiallyOn:
                    peers[cfg.uniqueIdentifier]?.maybeValue?.autoSendClippingsWhenIdle ?? false)
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

        // Drive each switcher's activity indicator from session status:
        // spin while a peer is in the .working state. queue: .main keeps
        // the UI mutations on the main runloop. object: nil means this
        // fires for every session app-wide; handle() gates to our peers.
        tabStatusObserver = NotificationCenter.default.addObserver(
            forName: iTermSessionTabStatus.didChangeNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // queue: .main guarantees we're on the main thread; assume the
            // isolation so we can touch the @MainActor introspection +
            // toolbar UI without hopping (and re-ordering) work.
            MainActor.assumeIsolated {
                self?.handle(tabStatusNotification: notification)
            }
        }
        // Catch peers that are already working at build time (e.g.
        // re-entering a workgroup whose agents are mid-task). This init
        // already builds NSViews above, so it necessarily runs on main.
        MainActor.assumeIsolated {
            seedBusyStates()
        }
    }

    deinit {
        if let tabStatusObserver {
            NotificationCenter.default.removeObserver(tabStatusObserver)
        }
    }

    // MARK: - Activity indicator

    @MainActor
    private func handle(tabStatusNotification notification: Notification) {
        guard let status = notification.object as? iTermSessionTabStatus else {
            return
        }
        // object: nil registration fires for every session in the app;
        // ignore any that isn't one of this port's peers.
        guard let session = peerSession(withGUID: status.sessionID),
              let identifier = identifier(for: session) else {
            return
        }
        let state = WorkgroupIntrospection.state(forTabStatus: status)
        setBusy(state == .working, forPeerIdentifier: identifier)
        maybeAutoSendClippings(session: session,
                               identifier: identifier,
                               newState: state)
    }

    // Delay between pasting the clippings into the main session and sending
    // the submit Return. Pasting alone leaves the text in the coding agent's
    // input box; the trailing Return actually submits it. The beat lets the
    // paste (which may be bracketed and land asynchronously) settle before
    // the Return, so the submit doesn't race ahead of the pasted content.
    private static let autoSendSubmitDelay: TimeInterval = 0.2

    // When a code-review peer with the auto-send toggle on transitions from
    // working to idle, paste its clippings into the workgroup's main session
    // and submit them with a Return. Gated to the working -> idle edge (not
    // any -> idle) so a spurious first status, or a session that is idle at
    // launch, never fires; it also means one send per completed review run
    // rather than a resend on every idle notification. Clippings are the
    // peer-group's shared list (anchored on the main session), so this
    // delivers the review's findings as input to whatever is running in the
    // main session.
    // Pure decision behind the auto-send: the text to deliver to the main
    // session on a state change, or nil to do nothing. Split out from the
    // wiring below so the gating (edge, mode, toggle, non-empty) can be unit-
    // tested without a live port, sessions, or the paste path.
    static func clippingsToAutoSend(previousState: SessionState?,
                                    newState: SessionState,
                                    mode: iTermWorkgroupSessionMode,
                                    toggleOn: Bool,
                                    clippings: [PTYSessionClipping]) -> String? {
        guard previousState == .working, newState == .idle else { return nil }
        guard mode == .codeReview, toggleOn else { return nil }
        let text = clippings.joinedForSending()
        return text.isEmpty ? nil : text
    }

    @MainActor
    private func maybeAutoSendClippings(session: PTYSession,
                                        identifier: String,
                                        newState: SessionState) {
        let previous = lastPeerState[identifier]
        lastPeerState[identifier] = newState
        guard let text = Self.clippingsToAutoSend(
                previousState: previous,
                newState: newState,
                mode: session.workgroupSessionMode,
                toggleOn: session.autoSendClippingsWhenIdle,
                clippings: session.clippings) else {
            return
        }
        guard let mainSession = workgroupInstance?.mainSession,
              mainSession !== session else { return }
        RLog("iTermWorkgroupPeerPort: auto-sending \(session.clippings.count) clipping(s) from code-review peer \(session.guid) to main session \(mainSession.guid)")
        mainSession.paste(text, flags: [])
        // Send the submit Return after a beat so it lands after the paste,
        // not interleaved with it. \r is the Enter key at the TTY (\n would
        // leave the line unsubmitted).
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoSendSubmitDelay) {
            [weak mainSession] in
            mainSession?.writeTaskNoBroadcast("\r")
        }
    }

    // Reflect a peer's busy state on every switcher in the group: each
    // peer's toolbar carries its own switcher and all switchers mirror
    // the full peer set, mirroring how activate() fans setActiveIdentifier
    // across itemsByPeerID.
    @MainActor
    private func setBusy(_ busy: Bool, forPeerIdentifier identifier: String) {
        for views in itemsByPeerID.values {
            for view in views {
                (view as? WorkgroupModeSwitcherItem)?
                    .setBusy(busy, forIdentifier: identifier)
            }
        }
    }

    // Best-effort initial sync for peers already realized and working at
    // construction time. Unrealized peers get picked up by the tab-status
    // observer once their promise fulfills and a status arrives.
    @MainActor
    private func seedBusyStates() {
        for session in realizedPeerSessions {
            guard let identifier = identifier(for: session),
                  let status = session.tabStatus else {
                continue
            }
            // Record the current state so the first observed transition is a
            // real edge (a peer already working at re-entry, then finishing,
            // still fires the auto-send working -> idle path).
            let state = WorkgroupIntrospection.state(forTabStatus: status)
            lastPeerState[identifier] = state
            if state == .working {
                setBusy(true, forPeerIdentifier: identifier)
            }
        }
    }

    override func activate(identifier: String) -> Bool {
        guard super.activate(identifier: identifier) else { return false }
        // Keep every peer's modeSwitcher visually in sync with the
        // newly-active peer — otherwise if you tap "Diff" on Main's
        // switcher and later come back to Main, Main's switcher would
        // still show "Diff" highlighted.
        syncModeSwitchers(to: identifier)
        // No explicit sessionDidChangeDesiredToolbarItems here:
        // super.activate's promise handler runs sessionActivate,
        // which calls updatePaneTitles → setToolbarItems on every
        // session in the tab. That picks up the per-peer items.
        return true
    }

    // The switchers were synced at commit time (above), but the swap
    // never ran; put the highlight back on the member that is really
    // active.
    override func activationDidRollBack(to identifier: String) {
        syncModeSwitchers(to: identifier)
    }

    private func syncModeSwitchers(to identifier: String) {
        for views in itemsByPeerID.values {
            for view in views {
                (view as? WorkgroupModeSwitcherItem)?
                    .setActiveIdentifier(identifier)
            }
        }
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
        let identifier = peerConfigs[targetIndex].uniqueIdentifier
        guard isActivatable(identifier: identifier) else {
            // The digit names an in-range member of this group, so the
            // chord belongs to us even though the member's spawn
            // already failed and there is nothing to switch to.
            // Returning false would let ⌥⇧⌘<digit> fall through the
            // dispatch chain and reach the focused shell as input;
            // consume it as a no-op instead.
            RLog("iTermWorkgroupPeerPort.activatePeer(byShortcutDigit:): consuming chord for \(identifier), whose spawn failed")
            return true
        }
        return activate(identifier: identifier)
    }

    // Number of peers in the group — exposed so the Workgroups menu can
    // disable the next/previous-peer items when there's nothing to cycle.
    @objc var peerCount: Int { peerConfigs.count }

    // Realized peer sessions in peer-config order — the same order the peer
    // switcher control presents them. Other UIs (e.g. the chat @-mention
    // picker) use this so their peer ordering matches the switcher rather than
    // the unordered `realizedPeerSessions` dictionary traversal.
    var orderedRealizedPeerSessions: [PTYSession] {
        return peerConfigs.compactMap { session(forIdentifier: $0.uniqueIdentifier) }
    }

    // Display label for the peer registered under `id` — falls back to
    // "Peer" when the config's displayName is empty (matches how
    // peerLabel renders in WorkgroupVisualView and the mode switcher).
    @objc func label(forPeerID id: String) -> String? {
        return peerMembers.first { $0.identifier == id }?.label
    }

    // Display string for the peer's configured custom peer-switch
    // shortcut, or nil when it has none. Callers fall back to the
    // built-in ⌥⇧⌘<position> shortcut when this returns nil — matching
    // how WorkgroupModeSwitcherItem renders its segment labels.
    @objc func customShortcutLabel(forPeerID id: String) -> String? {
        guard let member = peerMembers.first(where: {
                  $0.identifier == id
              }),
              let keystroke = member.shortcut?.keystroke else {
            return nil
        }
        return iTermKeystrokeFormatter.string(for: keystroke)
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
        guard let target = viableConfigIdentifier(byOffset: offset) else {
            return false
        }
        return activate(identifier: target)
    }

    // The nearest member in the `offset` direction whose spawn hasn't
    // already failed, or nil when every other member is dead. Dead
    // members must be skipped, not targeted: activate() refuses a
    // rejected spawn without advancing activeSessionIdentifier, so
    // cycling that lands on one would recompute the same dead target
    // on every keypress and the user could never get past it in that
    // direction. Internal so tests can pin the skip without needing a
    // live activation anchor.
    func viableConfigIdentifier(byOffset offset: Int) -> String? {
        let count = peerConfigs.count
        guard count > 1 else { return nil }
        let currentID = activeSessionIdentifier
        let baseIndex = peerConfigs.firstIndex { $0.uniqueIdentifier == currentID } ?? 0
        for step in 1..<count {
            // Modulo with sign correction so a negative offset wraps
            // to the end.
            let targetIndex = ((baseIndex + offset * step) % count + count) % count
            let identifier = peerConfigs[targetIndex].uniqueIdentifier
            if isActivatable(identifier: identifier) {
                return identifier
            }
        }
        return nil
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
                guard let ownerPeerID = selector.ownerPeerID,
                      let session = session(forIdentifier: ownerPeerID) else {
                    continue
                }
                // For .diff peers in State B (program ran), don't
                // restart immediately. Install a deferred restart
                // closure instead, then let the bumped poll's
                // gitPollerDidUpdate decide: fire the closure if the
                // new base has changes, or show the queued-reload
                // overlay if it doesn't. Without this, switching to
                // a base with no diff (e.g. HEAD^ -> HEAD on a clean
                // tree) would silently exit and leave the previous
                // diff output on screen with no explanation.
                //
                // State A (.diff peer waiting for initial spawn) is
                // skipped: its existing pendingDiffLaunch already
                // re-resolves gitBase at fire time via the captured
                // unsubstituted config, so a gitBase change between
                // spawn and first poll propagates automatically.
                if session.workgroupSessionMode == .diff
                    && session.isRestartable() {
                    installDeferredDiffRestart(forPeerID: ownerPeerID,
                                               selector: selector)
                    continue
                }
                if session.workgroupSessionMode == .diff {
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

    // Build a closure that re-resolves the diff command against the
    // workgroup's CURRENT gitBase at fire time and calls
    // restart(withCommand:). Stashed on the session as
    // pendingDiffLaunch so the next gitPollerDidUpdate can either
    // fire it (changes appeared) or show the waiting overlay (still
    // empty). Captures the peer's config (held in this port) and the
    // selector's current file pick so the eventual restart uses the
    // right command shape (per-file vs All Files) even if the popup
    // state changes before the poll completes.
    private func installDeferredDiffRestart(forPeerID peerID: String,
                                            selector: CCDiffSelectorItem) {
        guard let cfg = peerConfigs.first(where: {
            $0.uniqueIdentifier == peerID
        }) else {
            return
        }
        guard let session = session(forIdentifier: peerID) else { return }
        let pickedFile = selector.currentlySelectedFilename
        session.pendingDiffLaunch = { [weak session, weak workgroupInstance] in
            guard let session else { return }
            let base = workgroupInstance?.currentGitBase
                ?? CCGitBaseSelectorItem.defaultBase
            let resolved: String
            if let pickedFile {
                resolved = cfg.resolvedPerFileCommand(filename: pickedFile,
                                                      gitBase: base)
            } else {
                resolved = cfg.resolvedCommand(gitBase: base)
            }
            guard !resolved.isEmpty else { return }
            let wrapped = ITAddressBookMgr.commandByWrapping(
                inLoginShell: resolved)
            session.restart(withCommand: wrapped)
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
              let session = session(forIdentifier: ownerPeerID) else {
            return
        }
        // Diff peers handle their own restartability: a waiting peer
        // (pendingDiffLaunch != nil, _program nil) reports
        // isRestartable() == false, but Reload there is still
        // meaningful (poll-check + fire if ready). See
        // PTYSession.reloadDiffWithDeferralIfNeeded for state matrix.
        if session.workgroupSessionMode == .diff {
            session.reloadDiffWithDeferralIfNeeded()
            return
        }
        guard session.isRestartable() else { return }
        // Code-review peers re-show the prompt overlay so the user can
        // edit their prompt before the program is rerun.
        if session.workgroupSessionMode == .codeReview,
           session.codeReviewRawCommand != nil {
            session.reloadCodeReviewPromptOverlay()
            return
        }
        // Reload re-runs whatever the session is currently set to run
        // (its _program), not the original cfg.command. Same rationale
        // as the workgroup instance's reload path.
        session.restart()
    }
}

// MARK: - Toolbar item delegates

extension iTermWorkgroupPeerPort: WorkgroupModeSwitcherItemDelegate {
    func workgroupModeSwitcher(_ item: WorkgroupModeSwitcherItem,
                               didSelect identifier: String) {
        if !activate(identifier: identifier) {
            // The control tracks .selectOne, so AppKit already
            // highlighted the clicked segment before this delegate
            // ran. A refused activation (spawn already failed, no
            // anchor to swap on) never commits and never rolls back,
            // so nothing else would un-highlight the dead segment;
            // resync every switcher to the member that is really
            // active.
            syncModeSwitchers(to: activeSessionIdentifier)
        }
    }
}

extension iTermWorkgroupPeerPort: CCDiffSelectorItemDelegate {
    func diffDidSelect(filename: String,
                       sender: CCDiffSelectorItem) {
        RLog("iTermWorkgroupPeerPort.diffDidSelect \(filename) owner=\(sender.ownerPeerID ?? "nil")")
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
        RLog("iTermWorkgroupPeerPort.diffDidSelectAllFiles owner=\(sender.ownerPeerID ?? "nil")")
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

// MARK: - Auto-send-clippings toggle delegate

extension iTermWorkgroupPeerPort: WorkgroupAutoSendClippingsToolbarItemDelegate {
    func workgroupAutoSendClippings(ownerPeerID: String?, isOn: Bool) {
        guard let ownerPeerID,
              let session = session(forIdentifier: ownerPeerID) else {
            return
        }
        RLog("iTermWorkgroupPeerPort.workgroupAutoSendClippings owner=\(ownerPeerID) isOn=\(isOn)")
        session.autoSendClippingsWhenIdle = isOn
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
        RLog("iTermWorkgroupPeerPort.gitBaseDidChange \(base) owner=\(sender.ownerPeerID ?? "nil")")
        workgroupInstance?.gitBaseChanged(base, fromSender: sender)
    }
}

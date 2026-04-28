//
//  WorkgroupSessionSpawner.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/25/26.
//

import AppKit

// Seam between iTermWorkgroupInstance's tree-walking logic and the
// AppKit/PTYSession machinery that actually spawns peers, splits, and
// tabs. Production code uses DefaultWorkgroupSessionSpawner; tests
// provide a fake that returns synthetic PTYSessions without touching
// windows or the session factory.
//
// All three methods are synchronous from the instance's point of view:
// spawnPeer returns a promise that may resolve later; spawnSplit and
// spawnTab block until the new session is installed in its parent
// view tree, matching iTermSessionLauncher's setupSession path.
protocol WorkgroupSessionSpawner: AnyObject {
    // `workgroupInstanceID` is the per-entry UUID of the
    // iTermWorkgroupInstance that owns this spawn. It's threaded
    // through the launch request's environment so the spawned shell
    // sees ITERM_WORKGROUP_ID. Pass-by-value (vs reading from a
    // back-pointer on the session) because the spawned session's
    // workgroupInstance back-pointer is set by the caller AFTER the
    // launch request fires — environment is built before then.
    func spawnPeer(parent: PTYSession,
                   config: iTermWorkgroupSessionConfig,
                   workgroupInstanceID: String) -> iTermPromise<PTYSession>

    // Returns the live session installed as a split of `parent`, or
    // nil if `parent`'s window context is missing.
    func spawnSplit(parent: PTYSession,
                    config: iTermWorkgroupSessionConfig,
                    settings: SplitSettings,
                    workgroupInstanceID: String) -> PTYSession?

    // Returns the live session installed in a new tab of `parent`'s
    // window, or nil if the window context is missing.
    func spawnTab(parent: PTYSession,
                  config: iTermWorkgroupSessionConfig,
                  workgroupInstanceID: String) -> PTYSession?
}

final class DefaultWorkgroupSessionSpawner: WorkgroupSessionSpawner {
    func spawnPeer(parent: PTYSession,
                   config: iTermWorkgroupSessionConfig,
                   workgroupInstanceID: String) -> iTermPromise<PTYSession> {
        return parent.makeWorkgroupPeer(config: config,
                                        workgroupInstanceID: workgroupInstanceID)
    }

    func spawnSplit(parent: PTYSession,
                    config: iTermWorkgroupSessionConfig,
                    settings: SplitSettings,
                    workgroupInstanceID: String) -> PTYSession? {
        guard let windowController =
                parent.delegate?.realParentWindow() as? PseudoTerminal
            else { return nil }
        guard let profile = Self.resolveProfile(config: config) else { return nil }
        let factory = windowController.sessionFactory!
        let newSession = factory.newSession(withProfile: profile, parent: parent)
        let args = Self.splitArguments(settings)
        windowController.splitVertically(
            args.isVertical,
            before: args.before,
            adding: newSession,
            targetSession: parent,
            performSetup: true)
        Self.applySplitLocation(settings: settings,
                                newSession: newSession,
                                targetSession: parent)
        Self.launch(session: newSession,
                    command: config.command,
                    urlString: config.urlString,
                    mode: config.mode,
                    objectType: .paneObject,
                    factory: factory,
                    windowController: windowController,
                    parent: parent,
                    workgroupInstanceID: workgroupInstanceID)
        return newSession
    }

    func spawnTab(parent: PTYSession,
                  config: iTermWorkgroupSessionConfig,
                  workgroupInstanceID: String) -> PTYSession? {
        guard let windowController =
                parent.delegate?.realParentWindow() as? PseudoTerminal
            else { return nil }
        guard let profile = Self.resolveProfile(config: config) else { return nil }
        let factory = windowController.sessionFactory!
        let newSession = factory.newSession(withProfile: profile, parent: parent)
        windowController.addSession(inNewTab: newSession)
        Self.launch(session: newSession,
                    command: config.command,
                    urlString: config.urlString,
                    mode: config.mode,
                    objectType: .tabObject,
                    factory: factory,
                    windowController: windowController,
                    parent: parent,
                    workgroupInstanceID: workgroupInstanceID)
        return newSession
    }

    // MARK: - Profile and split helpers

    // Honors the explicit profileGUID when it points at a real profile;
    // otherwise falls back to the user's default profile (NOT the
    // parent's profile — splits and tabs are independent units, and
    // inheriting from the parent would silently propagate parent-
    // specific settings into every workgroup-spawned child).
    private static func resolveProfile(config: iTermWorkgroupSessionConfig) -> [AnyHashable: Any]? {
        let model = ProfileModel.sharedInstance()
        let base: [AnyHashable: Any]?
        if let guid = config.profileGUID,
           let override = model?.bookmark(withGuid: guid) {
            base = override
        } else {
            base = model?.defaultBookmark()
        }
        guard var profile = base else { return nil }
        // Workgroup-spawned sessions must NOT auto-close when their
        // command exits — otherwise a `git diff` peer disappears the
        // moment diff finishes, and a "reload" or per-file pick that
        // restarts the session into a quickly-exiting command also
        // closes the session. Match makeWorkgroupPeer's behavior:
        // always prompt on Cmd-W, never auto-close on exit.
        profile[KEY_PROMPT_CLOSE as String] = PROMPT_ALWAYS
        profile[KEY_SESSION_END_ACTION as String] =
            iTermSessionEndAction.default.rawValue
        // Browser profile + configured URL: the launcher reads
        // KEY_INITIAL_URL to seed the deferred-URL load on the new
        // browser session (see iTermSessionLauncher.m:466). Terminal
        // profiles ignore the key.
        if !config.urlString.isEmpty,
           let customCommand = profile[KEY_CUSTOM_COMMAND as String] as? String,
           customCommand == kProfilePreferenceCommandTypeBrowserValue {
            profile[KEY_INITIAL_URL as String] = config.urlString
        }
        return profile
    }

    private static func splitArguments(_ settings: SplitSettings) -> (isVertical: Bool, before: Bool) {
        let isVertical: Bool
        switch settings.orientation {
        case .vertical: isVertical = true
        case .horizontal: isVertical = false
        }
        let before: Bool
        switch settings.side {
        case .leadingOrTop: before = true
        case .trailingOrBottom: before = false
        }
        return (isVertical, before)
    }

    // After a split lands, resize the divider so the new pane
    // occupies the configured fraction of the parent's area.
    //
    // Two layouts to handle:
    // - 2-subview splitView (fresh wrapper from an orientation-change
    //   split, OR root-of-tab just gained its second pane): parent +
    //   new are the only subviews and fill the splitView in the
    //   divider axis. Use splitView.bounds as the span — individual
    //   subview frames may still be in transition from the delegate's
    //   proportional resize, so frame-union is unreliable.
    // - 3+-subview splitView (same-orientation sibling insertion,
    //   per the no-same-orientation-nesting invariant): new is
    //   inserted as a sibling of parent alongside other unrelated
    //   panes. Compute the pair's span from their actual frames —
    //   splitView.bounds would cover the whole sibling row, giving a
    //   position far outside the parent+new pair.
    static func applySplitLocation(settings: SplitSettings,
                                   newSession: PTYSession,
                                   targetSession: PTYSession) {
        guard let splitView = newSession.view.superview as? NSSplitView else { return }
        let parentView: NSView = targetSession.view
        let newView: NSView = newSession.view
        guard let newIdx = splitView.subviews.firstIndex(of: newView),
              let parentIdx = splitView.subviews.firstIndex(of: parentView) else {
            return
        }
        let dividerIndex = min(newIdx, parentIdx)
        let isVertical = splitView.isVertical

        let pairOrigin: CGFloat
        let pairSpan: CGFloat
        if splitView.subviews.count == 2 {
            pairOrigin = 0
            pairSpan = isVertical
                ? splitView.bounds.width
                : splitView.bounds.height
        } else {
            let pAxisOrigin = isVertical
                ? parentView.frame.origin.x
                : parentView.frame.origin.y
            let pAxisSize = isVertical
                ? parentView.frame.width
                : parentView.frame.height
            let nAxisOrigin = isVertical
                ? newView.frame.origin.x
                : newView.frame.origin.y
            let nAxisSize = isVertical
                ? newView.frame.width
                : newView.frame.height
            pairOrigin = min(pAxisOrigin, nAxisOrigin)
            let pairEnd = max(pAxisOrigin + pAxisSize,
                              nAxisOrigin + nAxisSize)
            pairSpan = pairEnd - pairOrigin
        }
        // If layout hasn't produced a real span yet (zero bounds or
        // zero frames), leave the divider wherever splitVertically
        // put it — best-effort fallback to the system default.
        guard pairSpan > 0 else { return }

        let location = CGFloat(min(max(settings.location, 0.05), 0.95))
        let newPaneIsFirst = switch settings.side {
            case .leadingOrTop: true
            case .trailingOrBottom: false
        }
        let fraction = newPaneIsFirst ? location : 1.0 - location
        let position = (pairOrigin + fraction * pairSpan).rounded()

        // NSSplitView.setPosition:ofDividerAt: doesn't stick in this
        // codebase — PTYTab's splitView:resizeSubviewsWithOldSize:
        // delegate redistributes based on existing subview
        // proportions, so the divider gets snapped back to whatever
        // ratio was already there. Set the pair's frames directly
        // (the arrangeSplitPanesEvenlyInSplitView pattern) and then
        // let adjustSubviews finalize; the delegate's coefficient
        // collapses to ~1 against the sizes we just wrote, so the
        // ratio sticks.
        let beforeView = splitView.subviews[dividerIndex]
        let afterView = splitView.subviews[dividerIndex + 1]
        let dividerThickness = splitView.dividerThickness
        let beforeSize = max(0, position - pairOrigin)
        let afterSize = max(0,
                            (pairOrigin + pairSpan) - (position + dividerThickness))
        var beforeFrame = beforeView.frame
        var afterFrame = afterView.frame
        if isVertical {
            beforeFrame.origin.x = pairOrigin
            beforeFrame.size.width = beforeSize
            afterFrame.origin.x = position + dividerThickness
            afterFrame.size.width = afterSize
        } else {
            beforeFrame.origin.y = pairOrigin
            beforeFrame.size.height = beforeSize
            afterFrame.origin.y = position + dividerThickness
            afterFrame.size.height = afterSize
        }
        beforeView.frame = beforeFrame
        afterView.frame = afterFrame
        splitView.adjustSubviews()
    }

    // Fire the launch request for `session` using the parent's
    // working directory. The session must already be installed in
    // the window; the launcher's setupSession:withSize: wired up the
    // SessionView before this point.
    //
    // For .codeReview mode the launch is deferred: the prompt overlay
    // is added to the session view immediately, and attachOrLaunch
    // fires only when the user presses Start.
    private static func launch(session: PTYSession,
                               command: String,
                               urlString: String,
                               mode: iTermWorkgroupSessionMode,
                               objectType: iTermObjectType,
                               factory: iTermSessionFactory,
                               windowController: PseudoTerminal,
                               parent: PTYSession,
                               workgroupInstanceID: String) {
        parent.asyncInitialDirectoryForNewSessionBased { oldCWD in
            // Wrap workgroup-supplied commands so they go through
            // /usr/bin/login + ShellLauncher and pick up the user's
            // dotfiles / PATH. The launcher path here bypasses the
            // KEY_RUN_COMMAND_IN_LOGIN_SHELL wrapping that
            // bookmarkCommandSwiftyString: would normally apply.
            session.workgroupSessionMode = mode
            let url = urlString.isEmpty ? nil : urlString
            if mode == .codeReview {
                // Splits/tabs are already installed in the window by
                // splitVertically: / addSession:inNewTab: above, so
                // they're visible immediately — no bury() needed (peer
                // sessions, handled by PTYSession.makeWorkgroupPeer,
                // do bury here for the same reason a peer can't be
                // visible until activated). The overlay is added on
                // top of the freshly-installed pane.
                session.presentCodeReviewPromptOverlay(
                    rawCommand: command,
                    urlString: url,
                    objectType: objectType,
                    factory: factory,
                    windowController: windowController,
                    oldCWD: oldCWD,
                    workgroupInstanceID: workgroupInstanceID)
                return
            }
            let cmd = command.isEmpty
                ? nil
                : ITAddressBookMgr.commandByWrapping(inLoginShell: command)
            let request = iTermSessionAttachOrLaunchRequest(
                session: session,
                canPrompt: false,
                objectType: objectType,
                hasServerConnection: false,
                serverConnection: iTermGeneralServerConnection(),
                urlString: url,
                allowURLSubs: false,
                environment: ["ITERM_WORKGROUP_ID": workgroupInstanceID],
                customShell: nil,
                oldCWD: oldCWD,
                forceUseOldCWD: true,
                command: cmd,
                isUTF8: nil,
                substitutions: nil,
                windowController: windowController,
                ready: nil) { _, _ in }
            factory.attachOrLaunch(with: request)
        }
    }
}

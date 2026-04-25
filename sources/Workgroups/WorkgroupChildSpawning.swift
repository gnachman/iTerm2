//
//  WorkgroupChildSpawning.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import AppKit

extension iTermWorkgroupInstance {
    // Resolve the profile for a non-peer config. Honors the explicit
    // profileGUID when it points at a real profile; otherwise falls
    // back to the user's default profile (NOT the parent's profile —
    // splits and tabs are independent units, and inheriting from the
    // parent would silently propagate parent-specific settings into
    // every workgroup-spawned child).
    private static func resolveProfile(
        config: iTermWorkgroupSession
    ) -> [AnyHashable: Any]? {
        let model = ProfileModel.sharedInstance()
        let base: [AnyHashable: Any]?
        if let guid = config.profileGUID,
           let override = model?.bookmark(withGuid: guid) {
            base = override
        } else {
            base = model?.defaultBookmark()
        }
        guard var profile = base else { return nil }
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

    // Add a split-pane child of `parent` from the workgroup config.
    //
    // Order matters: install in the window via the PseudoTerminal
    // splitVertically:…:performSetup:YES path FIRST, then launch the
    // process — that's what iTermSessionLauncher.m:312 does. The
    // performSetup:YES side calls setupSession:withSize:, which
    // installs the SessionView's scrollview and terminal content.
    // Without it, the new pane shows up transparent.
    func spawnSplit(config: iTermWorkgroupSession, parent: PTYSession) {
        guard case .split(let settings) = config.kind else { return }
        guard let windowController = parent.delegate?.realParentWindow() as? PseudoTerminal else {
            return
        }
        guard let profile = Self.resolveProfile(config: config) else { return }
        let factory = windowController.sessionFactory!
        let newSession = factory.newSession(withProfile: profile,
                                            parent: parent)
        let args = Self.splitArguments(settings)
        windowController.splitVertically(
            args.isVertical,
            before: args.before,
            adding: newSession,
            targetSession: parent,
            performSetup: true)
        applySplitLocation(settings: settings,
                           newSession: newSession,
                           targetSession: parent)
        registerNonPeerOrPeerGroupHost(session: newSession,
                                       config: config,
                                       parent: parent)
        spawnNonPeerChildren(of: newSession,
                             parentConfigID: config.uniqueIdentifier)
        launch(session: newSession,
               command: config.command,
               urlString: config.urlString,
               objectType: .paneObject,
               factory: factory,
               windowController: windowController,
               parent: parent)
    }

    // Add a new-tab child from the workgroup config.
    func spawnTab(config: iTermWorkgroupSession, parent: PTYSession) {
        guard let windowController =
                parent.delegate?.realParentWindow() as? PseudoTerminal
            else { return }
        guard let profile = Self.resolveProfile(config: config) else { return }
        let factory = windowController.sessionFactory!
        let newSession = factory.newSession(withProfile: profile,
                                            parent: parent)
        windowController.addSession(inNewTab: newSession)
        registerNonPeerOrPeerGroupHost(session: newSession,
                                       config: config,
                                       parent: parent)
        spawnNonPeerChildren(of: newSession,
                             parentConfigID: config.uniqueIdentifier)
        launch(session: newSession,
               command: config.command,
               urlString: config.urlString,
               objectType: .tabObject,
               factory: factory,
               windowController: windowController,
               parent: parent)
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
    private func applySplitLocation(settings: SplitSettings,
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

    // If the spawned non-peer config has peer children of its own
    // (e.g. a split that hosts its own peer group), build a peer
    // port for it and register the peers. Otherwise treat the
    // session as a leaf non-peer.
    private func registerNonPeerOrPeerGroupHost(session: PTYSession,
                                                config: iTermWorkgroupSession,
                                                parent: PTYSession) {
        let peerChildren = workgroup.sessions.filter { s in
            guard s.parentID == config.uniqueIdentifier else { return false }
            if case .peer = s.kind { return true }
            return false
        }
        if peerChildren.isEmpty {
            registerNonPeer(session: session, config: config)
            return
        }
        // Nested peer group: this non-peer session hosts peers. Build
        // a separate peer port for it; its toolbar comes from the
        // port (not the non-peer items dict).
        let peerConfigs = [config] + peerChildren
        var peers: [String: iTermPromise<PTYSession>] = [:]
        peers[config.uniqueIdentifier] = iTermPromise<PTYSession>(value: session)
        for peer in peerChildren {
            peers[peer.uniqueIdentifier] = parent.makeWorkgroupPeer(config: peer)
        }
        let port = iTermWorkgroupPeerPort(
            peers: peers,
            peerConfigs: peerConfigs,
            activeSessionIdentifier: config.uniqueIdentifier,
            leaderIdentifier: config.uniqueIdentifier,
            leaderScope: session.genericScope)
        session.peerPort = port
        let childPromises = peerChildren.compactMap {
            peers[$0.uniqueIdentifier]
        }
        registerNestedPeerPort(port,
                               hostSession: session,
                               peerChildrenPromises: childPromises)
        for (_, promise) in peers {
            promise.then { [weak self] s in
                guard let self else { return }
                s.workgroupInstance = self
            }
        }
    }

    // Fire the launch request for `session` using the parent's
    // working directory. The session must already be installed in
    // the window; the launcher's setupSession:withSize: wired up the
    // SessionView before this point.
    private func launch(session: PTYSession,
                        command: String,
                        urlString: String,
                        objectType: iTermObjectType,
                        factory: iTermSessionFactory,
                        windowController: PseudoTerminal,
                        parent: PTYSession) {
        parent.asyncInitialDirectoryForNewSessionBased { oldCWD in
            let cmd = command.isEmpty ? nil : command
            let url = urlString.isEmpty ? nil : urlString
            let request = iTermSessionAttachOrLaunchRequest(
                session: session,
                canPrompt: false,
                objectType: objectType,
                hasServerConnection: false,
                serverConnection: iTermGeneralServerConnection(),
                urlString: url,
                allowURLSubs: false,
                environment: [:],
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

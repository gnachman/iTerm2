//
//  WorkgroupTmuxSpawning.swift
//  iTerm2SharedARC
//
//  Split and tab members of an instance whose leader is a tmux Integration pane. A local member
//  is a session iTerm2 creates and installs; in a tmux tab that session would be thrown away by
//  the next layout update, which rebuilds the tab from tmux's layout. So the member is created as
//  a tmux pane (or window) running its command on the server, and its session is adopted when
//  tmux reports the pane.
//

import Foundation

extension iTermWorkgroupInstance {
    /// - Parameter splitSettings: nil for a tab member.
    func spawnTmuxMember(config: iTermWorkgroupSessionConfig,
                         parent: PTYSession,
                         binding: TmuxWorkgroupBinding,
                         splitSettings: SplitSettings?) {
        let command = TmuxWorkgroupBinding.initialCommand(for: config, gitBase: currentGitBase)
        let parentPaneID = Int(parent.tmuxPane)
        let created: (Int?) -> Void = { [weak self, weak parent] paneID in
            guard let paneID else {
                return
            }
            guard let self, !self.didTeardown, let controller = parent?.tmuxController else {
                RLog("WorkgroupTmuxSpawning: instance gone before member \(config.uniqueIdentifier) was created; removing %\(paneID)")
                binding.killPane(paneID)
                return
            }
            controller.whenPaneRegistered(Int32(paneID)) { [weak self, weak parent] session in
                guard let session else {
                    return
                }
                guard let self, !self.didTeardown, let parent else {
                    RLog("WorkgroupTmuxSpawning: instance gone before member %\(paneID) arrived; removing it")
                    binding.killPane(paneID)
                    return
                }
                self.didCreateTmuxMember(session, config: config, parent: parent)
            }
        }
        if let splitSettings {
            binding.createSplit(configID: config.uniqueIdentifier,
                                settings: splitSettings,
                                command: command,
                                parentPaneID: parentPaneID,
                                completion: created)
        } else {
            binding.createWindow(configID: config.uniqueIdentifier,
                                 command: command,
                                 parentPaneID: parentPaneID,
                                 completion: created)
        }
    }

    private func didCreateTmuxMember(_ session: PTYSession,
                                     config: iTermWorkgroupSessionConfig,
                                     parent: PTYSession) {
        RLog("WorkgroupTmuxSpawning: member \(config.uniqueIdentifier) is %\(session.tmuxPane)")
        session.workgroupSessionMode = config.mode
        Self.applyTmuxMemberProfile(config: config, to: session)
        registerNonPeerOrPeerGroupHost(session: session, config: config, parent: parent)
        if let binding = tmuxBinding {
            session.syncTmuxWorkgroupWaiting(config: config, binding: binding)
        }
        spawnNonPeerChildren(of: session, parentConfigID: config.uniqueIdentifier)
    }

    /// A tmux pane can carry its own profile, as with Change Profile, but the panes of a tmux
    /// window share one font and spacing because tmux lays them out in character cells. So the
    /// member's profile is applied with the window's font settings.
    static func applyTmuxMemberProfile(config: iTermWorkgroupSessionConfig, to session: PTYSession) {
        guard let guid = config.profileGUID,
              let profile = ProfileModel.sharedInstance().bookmark(withGuid: guid),
              let controller = session.tmuxController,
              let window = session.delegate?.tmuxWindow() else {
            return
        }
        var merged = profile
        for (key, value) in controller.fontOverrides(forWindow: window) ?? [:] {
            merged[key] = value
        }
        if !session.setProfile(merged, preservingName: false) {
            RLog("WorkgroupTmuxSpawning: could not apply profile \(guid) to %\(session.tmuxPane)")
        }
    }
}

extension iTermWorkgroupInstance {
    /// Connects the instance to its state on the tmux server: peers' sessions are prepared as they
    /// arrive, and activating a peer is a guarded swap-pane.
    func wireTmux(_ binding: TmuxWorkgroupBinding) {
        tmuxBinding = binding
        binding.configurePeerSession = { [weak binding] session, config in
            session.workgroupSessionMode = config.mode
            Self.applyTmuxMemberProfile(config: config, to: session)
            if let binding {
                session.syncTmuxWorkgroupWaiting(config: config, binding: binding)
            }
        }
        binding.membersDidUpdate = { [weak self] in
            self?.adoptLateTmuxMembers()
            self?.adoptReplacedTmuxMembers()
            self?.followTmuxVisibleMember()
            self?.syncTmuxMembersWaiting()
        }
        binding.lockWaitDidChange = { [weak self] in
            self?.tmuxLockWaitDidChange()
        }
        // Nested groups' ports get theirs in registerTmuxPeerGroup.
        let port = peerPort
        port.tmuxActivation = { [weak self, weak port] identifier in
            guard let self, let port else { return false }
            return self.activateTmuxPeer(identifier, in: port)
        }
    }

    /// A split or tab that hosts peers, in a tmux tab: like the leader's group, its peers are tmux
    /// panes parked in hidden windows, and switching among them is a guarded swap. Peers in
    /// `adopted` (reattaching) take their sessions as they are; the rest get promises fulfilled when
    /// their panes exist, and with `createMissing` (entry) are created now, otherwise on demand.
    func registerTmuxPeerGroup(host session: PTYSession,
                               config: iTermWorkgroupSessionConfig,
                               binding: TmuxWorkgroupBinding,
                               adopted: [String: PTYSession],
                               activeIdentifier: String,
                               createMissing: Bool) {
        let peerChildren = self.peerChildren(of: config)
        var peers: [String: iTermPromise<PTYSession>] = [config.uniqueIdentifier: iTermPromise<PTYSession>(value: session)]
        var missing = [iTermWorkgroupSessionConfig]()
        for peer in peerChildren {
            if let existing = adopted[peer.uniqueIdentifier], existing.workgroupInstance == nil, existing.peerPort == nil {
                existing.workgroupSessionMode = peer.mode
                existing.forceDefaultEndAction = true
                if peer.mode == .codeReview {
                    existing.codeReviewRawCommand = peer.command
                }
                peers[peer.uniqueIdentifier] = iTermPromise<PTYSession>(value: existing)
            } else {
                peers[peer.uniqueIdentifier] = binding.peerPromise(for: peer.uniqueIdentifier)
                missing.append(peer)
            }
        }
        let port = iTermWorkgroupPeerPort(peers: peers,
                                          peerConfigs: [config] + peerChildren,
                                          activeSessionIdentifier: activeIdentifier,
                                          leaderIdentifier: config.uniqueIdentifier,
                                          leaderScope: session.genericScope,
                                          gitPoller: gitPoller)
        session.peerPort = port
        port.tmuxActivation = { [weak self, weak port] identifier in
            guard let self, let port else { return false }
            return self.activateTmuxPeer(identifier, in: port)
        }
        registerNestedPeerPort(port,
                               hostSession: session,
                               hostConfig: config,
                               peerChildrenPromises: peerChildren.compactMap { peers[$0.uniqueIdentifier] })
        attachBackPointers(toEach: Array(peers.values))
        // As for a local nested group: the host's toolbar was applied before the port existed.
        session.delegate?.sessionDidChangeDesiredToolbarItems(session)
        if createMissing && !missing.isEmpty {
            binding.createPeers(missing, gitBase: currentGitBase)
        }
    }

    /// After tmux reported the instance: a member whose position has a new pane (relaunched before
    /// tmux 3.8, by this client or another) takes that pane's session once it is registered here.
    /// On a Mac that adopted the instance, a split or tab member whose pane appeared after it
    /// adopted (another Mac creates them one by one after publishing the leader) joins once its
    /// session exists. On the Mac that entered it, the spawner registers each as it creates it.
    private func adoptLateTmuxMembers() {
        guard let binding = tmuxBinding, binding.isAdopted, let controller = binding.controller else {
            return
        }
        for config in workgroup.sessions {
            switch config.kind {
            case .split, .tab:
                break
            case .root, .peer:
                continue
            }
            let configID = config.uniqueIdentifier
            guard liveSession(forConfigID: configID) == nil,
                  let paneID = binding.paneID(forConfigID: configID),
                  !binding.lateMembersPending.contains(paneID) else {
                continue
            }
            binding.lateMembersPending.insert(paneID)
            controller.whenPaneRegistered(Int32(paneID)) { [weak self, weak binding] session in
                binding?.lateMembersPending.remove(paneID)
                guard let self, let binding, let session,
                      !self.didTeardown,
                      self.liveSession(forConfigID: configID) == nil,
                      session.workgroupInstance == nil else {
                    return
                }
                RLog("iTermWorkgroupInstance: member \(configID) arrived as %\(paneID) after adoption; joining it")
                Self.applyTmuxMemberProfile(config: config, to: session)
                session.workgroupSessionMode = config.mode
                if self.peerChildren(of: config).isEmpty {
                    self.registerNonPeer(session: session, config: config)
                } else {
                    self.registerTmuxPeerGroup(host: session,
                                               config: config,
                                               binding: binding,
                                               adopted: [:],
                                               activeIdentifier: configID,
                                               createMissing: false)
                }
            }
        }
    }

    private func adoptReplacedTmuxMembers() {
        guard let binding = tmuxBinding else {
            return
        }
        for config in workgroup.sessions {
            let configID = config.uniqueIdentifier
            // The current session may have ended already (its pane went first), which makes it
            // no longer a tmux client, so it is recognized by the pane it showed.
            // A member whose session ended while its pane lives on (a repair moved the pane into a
            // new window, whose tab made a new session for it) is adopted the same way.
            guard let paneID = binding.paneID(forConfigID: configID),
                  let current = liveSession(forConfigID: configID),
                  current !== mainSession,
                  let currentPaneID = current.tmuxPaneIfClient,
                  currentPaneID != paneID || current.exited,
                  let controller = binding.controller else {
                continue
            }
            RLog("iTermWorkgroupInstance: member \(configID) moved from %\(currentPaneID) to %\(paneID) (ended: \(current.exited)); adopting its new session")
            controller.whenPaneRegistered(Int32(paneID)) { [weak self, weak current] session in
                guard let self, let session, let current else {
                    return
                }
                self.replaceTmuxMember(config: config, old: current, new: session)
            }
        }
    }

    /// Each peer group shows whichever member tmux has in view, even one that came into view in a
    /// new window (a repair) rather than by a tab's relayout.
    private func followTmuxVisibleMember() {
        guard let visibleByHost = tmuxBinding?.visibleMemberByHost else {
            return
        }
        for port in allPeerPorts {
            guard let visible = visibleByHost[port.leaderIdentifier],
                  visible != port.activeSessionIdentifier,
                  let session = port.session(forIdentifier: visible) else {
                continue
            }
            port.tmuxMemberDidBecomeVisible(session)
        }
    }

    private func replaceTmuxMember(config: iTermWorkgroupSessionConfig, old: PTYSession, new: PTYSession) {
        let configID = config.uniqueIdentifier
        guard !didTeardown,
              new !== old,
              new.workgroupInstance == nil,
              liveSession(forConfigID: configID) === old else {
            return
        }
        new.workgroupSessionMode = config.mode
        Self.applyTmuxMemberProfile(config: config, to: new)
        if config.mode == .codeReview {
            new.codeReviewRawCommand = config.command
            new.codeReviewLastUsedPrompt = old.codeReviewLastUsedPrompt
        }
        // A nested group's host is both: its group's leader and a split or tab.
        let port = allPeerPorts.first { $0.ownsIdentifier(configID) }
        port?.replacePeer(identifier: configID, with: new)
        replaceNonPeer(configID: configID, with: new)
        new.workgroupInstance = self
        new.delegate?.sessionDidChangeDesiredToolbarItems(new)
        old.workgroupInstance = nil
        // A buried session's pane went with the window it was moved to, so nothing else will end
        // it. One in a tab ends when tmux's layout takes it out.
        if old.isTmuxBuried && !old.exited {
            old.terminate()
        }
    }

    /// After tmux reported the instance: each member's session shows whether it has started.
    func syncTmuxMembersWaiting() {
        guard let binding = tmuxBinding else {
            return
        }
        for config in workgroup.sessions where TmuxWorkgroupState.startsWaiting(config.mode) {
            liveSession(forConfigID: config.uniqueIdentifier)?.syncTmuxWorkgroupWaiting(config: config, binding: binding)
        }
    }

    /// Creating peers waits on another client's lock: after a few quiet seconds, a bar on the
    /// member in view says so, offering to take over or stop waiting. It goes when the wait ends.
    private func tmuxLockWaitDidChange() {
        guard let binding = tmuxBinding else {
            return
        }
        guard binding.isWaitingForLock else {
            let identifier = TmuxWorkgroupBinding.lockWaitAnnouncementIdentifier(instanceID: instanceUniqueIdentifier)
            for session in peerPort.realizedPeerSessions {
                session.dismissAnnouncement(withIdentifier: identifier)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TmuxWorkgroupBinding.lockWaitAnnouncementDelay) { [weak self] in
            self?.showTmuxLockWaitAnnouncement()
        }
    }

    private func showTmuxLockWaitAnnouncement() {
        guard !didTeardown, let binding = tmuxBinding, binding.isWaitingForLock else {
            return
        }
        let identifier = TmuxWorkgroupBinding.lockWaitAnnouncementIdentifier(instanceID: instanceUniqueIdentifier)
        guard !peerPort.realizedPeerSessions.contains(where: { $0.hasAnnouncement(withIdentifier: identifier) }),
              let session = peerPort.activeSession ?? mainSession else {
            return
        }
        RLog("iTermWorkgroupInstance: \(instanceUniqueIdentifier) is still waiting on another client's lock; telling the user")
        let title = String(localized: "TmuxWorkgroup.LockWait.Title",
                           defaultValue: "Another iTerm2 attached to this tmux session is setting up a workgroup. This one is waiting for it to finish.",
                           comment: "Announcement shown while creating a workgroup's sessions in tmux waits for another iTerm2 attached to the same tmux session")
        let actions = [String(localized: "TmuxWorkgroup.LockWait.TakeOver",
                              defaultValue: "Take Over",
                              comment: "Button that stops waiting for the other iTerm2 and proceeds anyway"),
                       String(localized: "TmuxWorkgroup.LockWait.Cancel",
                              defaultValue: "Stop Waiting",
                              comment: "Button that stops waiting; the workgroup's sessions are created later, when needed")]
        let choose: (Int32) -> Void = { [weak binding] choice in
            switch choice {
            case 0:
                RLog("iTermWorkgroupInstance: user chose to take over the workgroup lock")
                binding?.takeOverLock()
            case 1:
                RLog("iTermWorkgroupInstance: user chose to stop waiting for the workgroup lock")
                binding?.stopWaitingForLock()
            default:
                break
            }
        }
        guard let announcement = iTermAnnouncementViewController.announcement(withTitle: title,
                                                                                style: .kiTermAnnouncementViewStyleWarning,
                                                                                withActions: actions,
                                                                                completion: choose) else {
            return
        }
        session.queueAnnouncement(announcement, identifier: identifier)
    }

    /// Brings a peer into view: tmux swaps its pane with the visible member's, if neither moved
    /// meanwhile, and the tab follows tmux's layout (which adopts the peer's buried session and
    /// buries the other). A peer that does not exist yet (e.g. a client that was creating it
    /// vanished) is created first.
    private func activateTmuxPeer(_ identifier: String, in port: PTYSessionPeerPort) -> Bool {
        guard let binding = tmuxBinding, port.ownsIdentifier(identifier) else {
            return false
        }
        guard let visible = port.activeSession else {
            RLog("iTermWorkgroupInstance.activateTmuxPeer: no member of \(port.debugDescription) is in view")
            return false
        }
        guard let target = port.session(forIdentifier: identifier) else {
            guard let config = workgroup.session(withUniqueIdentifier: identifier) else {
                return false
            }
            RLog("iTermWorkgroupInstance.activateTmuxPeer: \(identifier) does not exist yet; creating it")
            binding.createPeers([config], gitBase: currentGitBase)
            port.promise(forIdentifier: identifier)?.then { [weak self, weak port] _ in
                guard let self, let port else { return }
                _ = self.activateTmuxPeer(identifier, in: port)
            }
            return true
        }
        if target === visible {
            return true
        }
        let window = visible.delegate?.tmuxWindow() ?? -1
        let controller = visible.tmuxController
        binding.switchPeer(visiblePaneID: Int(visible.tmuxPane), targetPaneID: Int(target.tmuxPane)) { outcome in
            RLog("iTermWorkgroupInstance.activateTmuxPeer: switching to \(identifier): \(outcome)")
            // tmux 3.2 reports no layout change for a swap between windows; read it now rather than
            // waiting for the pane-list subscription. Also resyncs after a guard that did not hold.
            if window >= 0 {
                controller?.refreshLayout(ofWindow: window)
            }
        }
        return true
    }
}

/// What a workgroup member on a tmux server shows about whether its program has started.
enum TmuxWorkgroupWaitingDisplay {
    case none
    /// The code review prompt, or the diff waiting for changes.
    case waiting
    /// This client is starting it.
    case starting
}

extension PTYSession {
    /// The tmux pane this session shows, if it is or was a tmux client. Unlike isTmuxClient, it is
    /// still known while the session terminates.
    var tmuxPaneIfClient: Int? {
        return (genericScope.value(forVariableName: iTermVariableKeySessionTmuxWindowPane) as? NSNumber)?.intValue
    }

    /// For a member of an instance on a tmux server, other than its leader (the user's own pane),
    /// the instance's binding, through which its program is started and relaunched.
    var workgroupTmuxBinding: TmuxWorkgroupBinding? {
        guard isTmuxClient,
              let instance = workgroupInstance,
              let binding = instance.tmuxBinding,
              instance.mainSession !== self else {
            return nil
        }
        return binding
    }

    /// tmux says this member's program ended, or runs again after a restart (possibly by another
    /// Mac). Like a local member's session, it says it ended and offers to restart it; the
    /// workgroup carries on. It is not marked exited, which would drop the output of a program
    /// another Mac restarts before this hears that it did.
    func tmuxWorkgroupMemberProgramDidChange(_ run: TmuxWorkgroupCommands.PaneRun) {
        let endedRun = run.dead ? run.run : nil
        guard endedRun != swiftState.tmuxMemberEndedRun else {
            return
        }
        swiftState.tmuxMemberEndedRun = endedRun
        RLog("PTYSession[\(guid)]: tmux member's program \(run.dead ? "ended" : "runs again") (run \(run.run))")
        if run.dead {
            if !iTermAdvancedSettingsModel.suppressRestartAnnouncement() {
                naggingController.sessionEnded(withExecFailure: false)
            }
        } else {
            dismissAnnouncement(withIdentifier: iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier)
        }
    }

    /// Restart from the Session Ended announcement of a tmux member whose program ended: relaunch
    /// it in its pane as Reload does. False if this is not one. Nothing happens unless the run
    /// that ended is still the pane's, as another Mac may have restarted it before this heard so;
    /// relaunching would kill that.
    @objc func restartEndedTmuxWorkgroupMember() -> Bool {
        guard let endedRun = swiftState.tmuxMemberEndedRun,
              let binding = workgroupTmuxBinding,
              workgroupInstance != nil else {
            return false
        }
        RLog("PTYSession[\(guid)]: restart ended tmux member")
        binding.paneRun(paneID: Int(tmuxPane)) { [weak self] run in
            guard let self else {
                return
            }
            guard let instance = self.workgroupInstance else {
                RLog("PTYSession[\(self.guid)]: not restarting: no longer in a workgroup")
                return
            }
            guard run == TmuxWorkgroupCommands.PaneRun(dead: true, run: endedRun) else {
                RLog("PTYSession[\(self.guid)]: not restarting: the pane's run is now \(String(describing: run))")
                return
            }
            _ = instance.reloadTmuxMember(self)
        }
        return true
    }

    /// Whether Reload, or picking a file in a diff, can replace what this workgroup member runs: a
    /// program that ran here, or a member on a tmux server, whose pane is respawned.
    @objc var canRelaunchWorkgroupMember: Bool {
        return isRestartable() || workgroupTmuxBinding != nil
    }

    /// Runs the shell command `command` in this tmux member's pane in place of what it runs.
    /// `onlyIfWaiting` makes this the first start, which another client may have made already.
    func relaunchTmuxWorkgroupMember(_ binding: TmuxWorkgroupBinding, command: String, onlyIfWaiting: Bool = false) {
        binding.relaunch(paneID: Int(tmuxPane),
                         onlyIfWaiting: onlyIfWaiting,
                         needsHome: false,
                         command: { _ in command },
                         completion: { [weak self] relaunched in
            guard let self else { return }
            RLog("PTYSession[\(self.guid)]: tmux member relaunched=\(relaunched)")
            if onlyIfWaiting {
                self.tmuxWorkgroupMemberDidStart(relaunched)
            }
            if relaunched {
                // The run that ended is over; whatever tmux reports next is a new one.
                if self.swiftState.tmuxMemberEndedRun != nil {
                    self.swiftState.tmuxMemberEndedRun = nil
                    self.dismissAnnouncement(withIdentifier: iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier)
                }
                self.tmuxController?.workgroupAttacher?.paneWasRelaunched()
            }
        })
    }

    /// Shows whether this code review or diff member on a tmux server has started, as tmux says:
    /// one that has not shows the prompt overlay or waits for changes, as a local one does; once
    /// any client starts it, this one stops waiting so it does not start it again. A report that
    /// it is waiting is stale while this client is starting it, as tmux may have sent it before.
    /// `binding` is the instance's, passed because a peer's session is prepared before it is
    /// connected to its instance.
    func syncTmuxWorkgroupWaiting(config: iTermWorkgroupSessionConfig, binding: TmuxWorkgroupBinding) {
        guard TmuxWorkgroupState.startsWaiting(config.mode),
              isTmuxClient,
              let waiting = binding.isWaiting(paneID: Int(tmuxPane)) else {
            return
        }
        let shown = swiftState.tmuxWorkgroupWaiting
        switch (waiting, shown) {
        case (true, .none):
            RLog("PTYSession[\(guid)]: tmux member \(config.uniqueIdentifier) is waiting")
            swiftState.tmuxWorkgroupWaiting = .waiting
            showTmuxWorkgroupWaiting(config: config)
        case (false, .waiting):
            RLog("PTYSession[\(guid)]: tmux member \(config.uniqueIdentifier) was started elsewhere")
            swiftState.tmuxWorkgroupWaiting = .none
            dismissTmuxWorkgroupWaiting(mode: config.mode)
        case (false, .starting):
            swiftState.tmuxWorkgroupWaiting = .none
        case (true, .waiting), (true, .starting), (false, .none):
            break
        }
    }

    private func showTmuxWorkgroupWaiting(config: iTermWorkgroupSessionConfig) {
        switch config.mode {
        case .codeReview:
            presentTmuxCodeReviewPromptOverlay(rawCommand: config.command)
        case .diff:
            pendingDiffLaunch = { [weak self] in
                guard let self, let binding = self.workgroupTmuxBinding else { return }
                self.tmuxWorkgroupMemberWillStart()
                let base = self.workgroupInstance?.currentGitBase ?? CCGitBaseSelectorItem.defaultBase
                self.relaunchTmuxWorkgroupMember(binding,
                                                 command: config.resolvedCommand(gitBase: base),
                                                 onlyIfWaiting: true)
            }
            presentDiffWaitingPromptOverlay()
            workgroupInstance?.fireDeferredDiffLaunchesIfReady()
        case .regular:
            break
        }
    }

    private func dismissTmuxWorkgroupWaiting(mode: iTermWorkgroupSessionMode) {
        switch mode {
        case .codeReview:
            view?.dismissCodeReviewPromptOverlay()
        case .diff:
            pendingDiffLaunch = nil
            view?.dismissDiffWaitingPromptOverlay()
        case .regular:
            break
        }
    }

    /// This client is starting the member: its overlay is gone already.
    func tmuxWorkgroupMemberWillStart() {
        if swiftState.tmuxWorkgroupWaiting == .waiting {
            swiftState.tmuxWorkgroupWaiting = .starting
        }
    }

    /// If this client did not start it after all (another client did, or tmux could not), whatever
    /// tmux says next is believed. If it is still waiting, it is shown so again now.
    func tmuxWorkgroupMemberDidStart(_ started: Bool) {
        guard !started, swiftState.tmuxWorkgroupWaiting == .starting else {
            return
        }
        swiftState.tmuxWorkgroupWaiting = .none
        workgroupInstance?.syncTmuxMembersWaiting()
    }

    /// A tab adopted this session's pane from a parked window: if it is a workgroup peer, its group
    /// now shows it.
    @objc func tmuxSessionWasAdoptedIntoTab() {
        peerPort?.tmuxMemberDidBecomeVisible(self)
        delegate?.sessionDidChangeDesiredToolbarItems(self)
    }

    /// A workgroup member in a tmux tab keeps its session when its pane leaves the tab, which it
    /// usually does to be parked in a hidden window for a peer switch: the session is buried, so its
    /// output keeps arriving and switching back to it is instant. That covers the members of an
    /// instance here and any session that has been buried, since only peers' panes are parked.
    @objc var keepsTmuxSessionWhenItLeavesItsTab: Bool {
        return workgroupInstance?.tmuxBinding != nil || hasBeenTmuxBuried
    }

    /// The filter to put back when this buried session's pane returns to a tab. It was showing
    /// one when a peer switch parked its pane.
    @objc var tmuxFilterToRestore: String? {
        get { swiftState.tmuxFilterToRestore }
        set { swiftState.tmuxFilterToRestore = newValue }
    }

    /// After this session was buried: if tmux no longer has its pane, the member really ended.
    @objc func tmuxSessionWasBuried() {
        guard let gateway = tmuxController?.gateway else {
            return
        }
        let paneID = Int(tmuxPane)
        gateway.send("display -p -t %\(paneID) '#{pane_id}'") { [weak self] reply in
            guard TmuxWorkgroupCommands.paneID(fromReply: reply) != paneID, let self else {
                return
            }
            RLog("WorkgroupTmuxSpawning: buried member %\(paneID) is gone from the server; terminating its session")
            self.terminate()
        }
    }
}

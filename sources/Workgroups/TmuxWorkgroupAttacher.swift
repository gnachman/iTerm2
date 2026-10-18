//
//  TmuxWorkgroupAttacher.swift
//  iTerm2SharedARC
//
//  Adopts the workgroup instances on a tmux server, for one tmux Integration connection. It reads
//  the state once the initial windows are open (adoption needs their sessions), and again whenever
//  a member pane's tag changes (another client entered or ended an instance, or created a member),
//  via a format subscription. What to do is decided by TmuxWorkgroupAdoption; this carries it out.
//
//  Behavior always comes from a local workgroup whose shape matches. When none matches, the
//  instance's panes stay ordinary panes and nothing on the server changes, so another Mac that does
//  have a matching workgroup can still adopt it; the user is told once per connection. Its parked
//  peers, which no tab here can show, are offered to the user (TmuxWorkgroupHiddenPaneOffer).
//

import Foundation

@objc(iTermTmuxWorkgroupAttacher)
final class TmuxWorkgroupAttacher: NSObject {
    private weak var controller: TmuxController?
    private var subscription: iTermTmuxSubscriptionHandle?
    private var paneListSubscription: iTermTmuxSubscriptionHandle?
    private var lockSubscription: iTermTmuxSubscriptionHandle?
    private var refreshing = false
    private var refreshAgain = false
    private var toldAboutUnmatched = false
    // Instances whose choice of workgroup the user declined on this connection; not asked again.
    private var declined = Set<String>()
    // Instances this client is removing from the server. A snapshot taken before the removal
    // lands still shows them, and they must not be adopted again. Dropped once a snapshot shows
    // their record gone.
    private var endedHere = Set<String>()
    /// This connection's client, as tmux reports it; names it as a lock holder. Nil until known.
    private(set) var identity: TmuxWorkgroupCommands.ClientIdentity?
    private var hiddenPaneOffer: TmuxWorkgroupHiddenPaneOffer?

    /// For TmuxController, which lists windows with this option to recognize parked ones.
    @objc static var parkedOptionName: String {
        return TmuxWorkgroupState.parkedOptionName
    }

    @objc static func isParkedWindowTag(_ value: String?) -> Bool {
        return value.flatMap { TmuxWorkgroupState.ParkedTag(encoded: $0) } != nil
    }

    @objc init(controller: TmuxController) {
        self.controller = controller
        super.init()
        hiddenPaneOffer = TmuxWorkgroupHiddenPaneOffer(controller: controller) { [weak self] in self?.identity }
        hiddenPaneOffer?.didRelease = { [weak self] in self?.refresh() }
    }

    /// Call once the initial windows are open.
    @objc func start() {
        guard let gateway = controller?.gateway, gateway.supportsSubscriptions() else {
            return
        }
        gateway.send(TmuxWorkgroupCommands.identityQuery) { [weak self] reply in
            self?.identity = reply.flatMap { TmuxWorkgroupCommands.ClientIdentity(reported: $0) }
            if self?.identity == nil {
                RLog("TmuxWorkgroupAttacher: tmux did not report this client's identity: \(reply ?? "(error)")")
            }
        }
        subscription = gateway.subscribe(toFormat: "#{\(TmuxWorkgroupState.paneOptionName)}",
                                         target: "%*") { [weak self] _, _ in
            self?.refresh()
        }
        // A peer switch is a swap-pane between a visible window and a parked one. tmux 3.2 reports
        // no layout change for that, so watch each window's panes and re-read the layout of one
        // whose tab no longer holds the panes tmux says it does. Their sizes are watched too: when a
        // workgroup's slot changes size, its parked peers are pinned to the new size.
        paneListSubscription = gateway.subscribe(toFormat: "#{P:#{pane_id} #{pane_width}x#{pane_height} }",
                                                 target: "@*") { [weak self] value, parts in
            self?.paneListDidChange(value ?? "", arguments: parts ?? [])
        }
        // A client waiting on the workgroup lock tries again when it changes; a holder that
        // detached without releasing it is noticed in clientDetached().
        lockSubscription = gateway.subscribe(toFormat: "#{\(TmuxWorkgroupCommands.lockOptionName)}",
                                             target: "") { [weak self] _, _ in
            self?.wakeLockWaiters()
        }
        refresh()
    }

    /// Another client detached. If it held the workgroup lock, the lock is now stale.
    @objc func clientDetached() {
        wakeLockWaiters()
    }

    private func wakeLockWaiters() {
        guard let gateway = controller?.gateway else {
            return
        }
        hiddenPaneOffer?.wake()
        for instance in iTermWorkgroupController.instance.allInstances {
            if let binding = instance.tmuxBinding, binding.uses(gateway: gateway) {
                binding.wakeLockWaiters()
            }
        }
    }

    private func paneListDidChange(_ value: String, arguments: [String]) {
        guard let controller,
              let windowID = arguments.lazy.compactMap({ $0.hasPrefix("@") ? Int32($0.dropFirst()) : nil }).first else {
            return
        }
        guard let tab = controller.window(windowID) else {
            if controller.isParkedWindow(windowID) {
                // Its panes changed (a member replaced in place) or were resized. tmux 3.2 may not
                // say so with a layout change; re-reading it gives new panes buried sessions.
                controller.refreshLayout(ofWindow: windowID)
                refreshIfWorkgroupsAreHere()
            }
            return
        }
        let reported = Set(value.split(separator: " ").compactMap { TmuxWorkgroupCommands.paneID(fromReply: String($0)) })
        let shown = Set(tab.sessions().map { Int($0.tmuxPane) })
        if reported != shown {
            RLog("TmuxWorkgroupAttacher: window @\(windowID) holds panes \(reported.sorted()) but its tab shows \(shown.sorted()); re-reading its layout")
            controller.refreshLayout(ofWindow: windowID)
        }
        refreshIfWorkgroupsAreHere()
    }

    /// Panes moved or changed size: parked peers may need pinning again, and members replaced in
    /// place need their new sessions (see TmuxWorkgroupBinding.update(from:)).
    private func refreshIfWorkgroupsAreHere() {
        if let gateway = controller?.gateway, !adoptedInstanceIDs(gateway: gateway).isEmpty {
            refresh()
        }
    }

    /// This client is removing the instance from the server.
    func instanceIsBeingRemoved(_ instanceID: String) {
        endedHere.insert(instanceID)
    }

    /// A window holding a parked peer appeared. Its tags were set in the same command list that
    /// created it, so they are there now; refresh at once rather than waiting for the subscription,
    /// which tmux checks only about once a second.
    @objc func parkedWindowAppeared() {
        refresh()
    }

    func refresh() {
        guard !refreshing else {
            refreshAgain = true
            return
        }
        guard let controller, let gateway = controller.gateway else {
            return
        }
        refreshing = true
        let sessionID = Int(controller.sessionId)
        let adoptedHere = adoptedInstanceIDs(gateway: gateway)
        gateway.sendList(TmuxWorkgroupAdoption.queries(sessionID: sessionID)) { [weak self] replies in
            guard let self else {
                return
            }
            self.refreshing = false
            if replies.count == 3, let options = replies[0], let paneReply = replies[1], let windowReply = replies[2] {
                let panes = TmuxWorkgroupAdoption.panes(listPanesReply: paneReply)
                let windows = TmuxWorkgroupAdoption.windows(listWindowsReply: windowReply)
                let derivation = TmuxWorkgroupState.derive(
                    panes: panes,
                    windows: windows,
                    instanceOptions: TmuxWorkgroupAdoption.instanceOptions(showReply: options))
                for id in derivation.undecodableInstanceIDs {
                    RLog("TmuxWorkgroupAttacher: instance \(id) has a record this version cannot read; leaving it alone")
                }
                let present = Set(derivation.instances.map(\.instanceID)).union(derivation.undecodableInstanceIDs)
                self.endedHere.formIntersection(present)
                self.perform(TmuxWorkgroupAdoption.plan(derivation: derivation,
                                                        localWorkgroups: iTermWorkgroupModel.instance.workgroups,
                                                        adoptedHere: adoptedHere.union(self.endedHere)))
                // Instances here learn of their peers' panes, wherever they were created.
                for derived in derivation.instances {
                    iTermWorkgroupController.instance.allInstances
                        .first { $0.instanceUniqueIdentifier == derived.instanceID }?
                        .tmuxBinding?.update(from: derived)
                }
                // What adoption left unreachable here. Instances ended here are on their way out.
                let adopted = self.adoptedInstanceIDs(gateway: gateway).union(self.endedHere)
                self.hiddenPaneOffer?.update(TmuxWorkgroupHiddenPanes.find(panes: panes,
                                                                          windows: windows,
                                                                          derivation: derivation,
                                                                          adoptedHere: adopted),
                                             adoptedHere: adopted)
            } else {
                RLog("TmuxWorkgroupAttacher: could not read workgroup state from tmux")
            }
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh()
            }
        }
    }

    private func adoptedInstanceIDs(gateway: TmuxGateway) -> Set<String> {
        return Set(iTermWorkgroupController.instance.allInstances
            .filter { $0.tmuxBinding?.uses(gateway: gateway) == true }
            .map(\.instanceUniqueIdentifier))
    }

    private func perform(_ steps: [TmuxWorkgroupAdoption.Step]) {
        var unmatched = [String]()
        for step in steps {
            switch step {
            case .adopt(let adoption):
                adopt(adoption)
            case let .choose(instance, candidates):
                choose(instance: instance, candidates: candidates)
            case .unmatched(let instanceID):
                unmatched.append(instanceID)
            case .removeFromServer(let instanceID):
                guard let controller, let gateway = controller.gateway else {
                    continue
                }
                RLog("TmuxWorkgroupAttacher: instance \(instanceID) has no leader; removing it")
                instanceIsBeingRemoved(instanceID)
                TmuxWorkgroupBinding.removeFromServer(gateway: gateway,
                                                      sessionID: Int(controller.sessionId),
                                                      instanceID: instanceID,
                                                      leaderPaneID: nil)
            case .forget(let instanceID):
                forget(instanceID: instanceID)
            case let .cleanUpOrphans(killPaneIDs, untagPaneIDs):
                guard let gateway = controller?.gateway else {
                    continue
                }
                RLog("TmuxWorkgroupAttacher: cleaning up after an interrupted removal: killing \(killPaneIDs), untagging \(untagPaneIDs)")
                for paneID in killPaneIDs {
                    gateway.send(TmuxWorkgroupCommands.killPane(paneID)) { _ in }
                }
                for paneID in untagPaneIDs {
                    gateway.send(TmuxWorkgroupCommands.untagPane(paneID: paneID)) { _ in }
                }
            }
        }
        if !unmatched.isEmpty {
            RLog("TmuxWorkgroupAttacher: no local workgroup matches instances \(unmatched)")
            tellAboutUnmatchedOnce()
        }
    }

    private func adopt(_ adoption: TmuxWorkgroupAdoption.Adoption) {
        let instanceID = adoption.instanceID
        guard let controller,
              let leader = controller.session(forWindowPane: Int32(adoption.leaderPaneID)) else {
            RLog("TmuxWorkgroupAttacher: leader %\(adoption.leaderPaneID) of instance \(instanceID) has no session here; not adopting")
            return
        }
        guard leader.workgroupInstance == nil else {
            RLog("TmuxWorkgroupAttacher: leader %\(adoption.leaderPaneID) is already in a workgroup; not adopting \(instanceID)")
            return
        }
        func sessions(_ paneIDs: [String: Int]) -> [String: PTYSession] {
            var result = [String: PTYSession]()
            for (configID, paneID) in paneIDs {
                if let session: PTYSession = controller.session(forWindowPane: Int32(paneID)),
                   session.workgroupInstance == nil {
                    result[configID] = session
                }
            }
            return result
        }
        let members = sessions(adoption.memberPaneIDsByConfigID)
        // Parked peers have buried sessions; one in view is in a tab.
        let peers = sessions(adoption.peerPaneIDsByConfigID)
        guard let binding = TmuxWorkgroupBinding(leader: leader, workgroup: adoption.workgroup,
                                                 instanceID: instanceID, gitBase: adoption.gitBase) else {
            RLog("TmuxWorkgroupAttacher: could not adopt \(instanceID)")
            return
        }
        binding.adoptLeader(paneID: adoption.leaderPaneID)
        guard let instance = iTermWorkgroupController.instance.adopt(workgroup: adoption.workgroup,
                                                                     leader: leader,
                                                                     instanceUniqueIdentifier: instanceID,
                                                                     activeIdentifier: adoption.activeConfigID,
                                                                     gitBase: adoption.gitBase,
                                                                     peerSessionsByConfigID: peers,
                                                                     nonPeerSessionsByConfigID: members,
                                                                     tmuxBinding: binding,
                                                                     nestedActiveIdentifiers: adoption.nestedActiveConfigIDs) else {
            RLog("TmuxWorkgroupAttacher: could not adopt \(instanceID)")
            return
        }
        instance.provenance = "Adopted from tmux session \(controller.sessionName ?? "") when iTerm2 attached to it."
        for (configID, session) in members.merging(peers, uniquingKeysWith: { first, _ in first }) {
            if let config = adoption.workgroup.session(withUniqueIdentifier: configID) {
                iTermWorkgroupInstance.applyTmuxMemberProfile(config: config, to: session)
                session.workgroupSessionMode = config.mode
            }
        }
        for session in [leader] + Array(peers.values) where session.delegate != nil {
            session.delegate?.sessionDidChangeDesiredToolbarItems(session)
        }
        RLog("TmuxWorkgroupAttacher: adopted \(instanceID) with workgroup \(adoption.workgroup.uniqueIdentifier), members \(members.keys.sorted()), peers \(peers.keys.sorted()), \(adoption.activeConfigID) in view")
    }

    private func choose(instance: TmuxWorkgroupState.Instance, candidates: [iTermWorkgroup]) {
        guard !declined.contains(instance.instanceID) else {
            return
        }
        // iTermWarning offers at most seven buttons, one of which declines.
        let offered = Array(candidates.prefix(6))
        let decline = String(localized: "TmuxWorkgroupAttacher.ChooseDecline",
                             defaultValue: "Leave as Ordinary Panes",
                             comment: "Button that declines to attach a workgroup to panes found in a tmux session")
        let body = String(format: String(localized: "TmuxWorkgroupAttacher.ChooseBody",
                                         defaultValue: "tmux session “%@” has a workgroup that more than one of your workgroups match. Which one should it use?",
                                         comment: "Asks which local workgroup to use for a workgroup found in a tmux session; %@ is the tmux session's name"),
                          controller?.sessionName ?? "")
        let selection = iTermWarning.show(
            withTitle: body,
            actions: offered.map(\.name) + [decline],
            accessory: nil,
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: String(localized: "TmuxWorkgroupAttacher.ChooseHeading",
                            defaultValue: "Choose a Workgroup",
                            comment: "Heading of the dialog asking which local workgroup to use for one found in a tmux session"),
            window: nil)
        let index = Int(selection.rawValue) - Int(iTermWarningSelection.kiTermWarningSelection0.rawValue)
        guard index >= 0, index < offered.count,
              let step = TmuxWorkgroupAdoption.adoptStep(instance: instance, workgroup: offered[index]),
              case .adopt(let adoption) = step else {
            declined.insert(instance.instanceID)
            return
        }
        adopt(adoption)
    }

    private func forget(instanceID: String) {
        guard let instance = iTermWorkgroupController.instance.allInstances.first(where: {
            $0.instanceUniqueIdentifier == instanceID
        }) else {
            return
        }
        RLog("TmuxWorkgroupAttacher: instance \(instanceID) was ended by another client; forgetting it here")
        instance.tmuxInstanceEndedElsewhere = true
        let leader = instance.mainSession
        iTermWorkgroupController.instance.exit(instance: instance)
        if let leader {
            leader.delegate?.sessionDidChangeDesiredToolbarItems(leader)
        }
    }

    private func tellAboutUnmatchedOnce() {
        guard !toldAboutUnmatched else {
            return
        }
        toldAboutUnmatched = true
        let description = String(format: String(localized: "TmuxWorkgroupAttacher.UnmatchedBody",
                                                defaultValue: "tmux session “%@” has a workgroup that none of your workgroups match, so its panes are shown as ordinary panes.",
                                                comment: "Notification body when a workgroup found in a tmux session matches no local workgroup; %@ is the tmux session's name"),
                                 controller?.sessionName ?? "")
        iTermNotificationController.sharedInstance().notify(
            String(localized: "TmuxWorkgroupAttacher.UnmatchedTitle",
                   defaultValue: "Workgroup Not Recognized",
                   comment: "Notification title when a workgroup found in a tmux session matches no local workgroup"),
            withDescription: description)
    }
}

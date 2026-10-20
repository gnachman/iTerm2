//
//  TmuxWorkgroupBinding.swift
//  iTerm2SharedARC
//
//  A workgroup instance whose leader is a tmux Integration pane keeps its state on the tmux
//  server (see TmuxWorkgroupState). This is the instance's link to that server: it publishes the
//  instance record and member tags, and creates members as tmux panes and windows running their
//  commands there. Members' sessions arrive later, when tmux reports the new panes.
//
//  Requires tmux 3.2 (the oldest server the commands are verified on). With an older server, or a
//  workgroup whose shape cannot be stored, there is no binding.
//

import Foundation

final class TmuxWorkgroupBinding {
    private let gatewayProvider: () -> TmuxGateway?
    let sessionID: Int
    let instanceID: String
    private let record: TmuxWorkgroupState.InstanceRecord
    private let configIDsByPosition: [String]
    private let workgroup: iTermWorkgroup
    private(set) var leaderPaneID: Int?
    private(set) weak var controller: TmuxController?
    // Seals of peers' promises, by config ID, until each peer's session arrives.
    private var peerSeals = [String: iTermPromiseSeal]()
    private var creators = [TmuxWorkgroupPeerCreator]()
    // At most one repair at a time; the next update starts another if anything is still wrong.
    private var repairer: TmuxWorkgroupRepairer?
    /// Prepares a peer's session (mode, profile) just before its promise is fulfilled.
    var configurePeerSession: ((PTYSession, iTermWorkgroupSessionConfig) -> Void)?
    /// After each update from tmux, e.g. when a member stopped waiting because a client started it.
    var membersDidUpdate: (() -> Void)?
    /// Members' panes by position as of the last update, and which of those are waiting
    /// (PaneTag.waiting).
    private var paneForPosition = [Int: Int]()
    private var waitingPaneIDs = Set<Int>()

    convenience init?(leader: PTYSession, workgroup: iTermWorkgroup, instanceID: String, gitBase: String) {
        guard leader.isTmuxClient,
              let controller = leader.tmuxController,
              let gateway = controller.gateway,
              gateway.supportsSubscriptions() else {
            return nil
        }
        self.init(gatewayProvider: { [weak controller] in controller?.gateway },
                  sessionID: Int(controller.sessionId),
                  workgroup: workgroup,
                  instanceID: instanceID,
                  gitBase: gitBase)
        self.controller = controller
    }

    init?(gatewayProvider: @escaping () -> TmuxGateway?,
          sessionID: Int,
          workgroup: iTermWorkgroup,
          instanceID: String,
          gitBase: String) {
        guard let skeleton = TmuxWorkgroupState.Skeleton(workgroup: workgroup),
              let ids = TmuxWorkgroupState.Skeleton.configIDsByPosition(in: workgroup) else {
            RLog("TmuxWorkgroupBinding: workgroup \(workgroup.uniqueIdentifier) has no storable shape")
            return nil
        }
        self.gatewayProvider = gatewayProvider
        self.sessionID = sessionID
        self.instanceID = instanceID
        record = TmuxWorkgroupState.InstanceRecord(workgroupID: workgroup.uniqueIdentifier,
                                                   gitBase: gitBase,
                                                   skeleton: skeleton)
        configIDsByPosition = ids
        self.workgroup = workgroup
    }

    deinit {
        // A seal must be settled before it is released. Peers that never arrived never will.
        for seal in peerSeals.values {
            seal.rejectWithDefaultError()
        }
    }

    private var gateway: TmuxGateway? {
        return gatewayProvider()
    }

    /// Whether this binding talks to `gateway`, i.e. belongs to that tmux connection.
    func uses(gateway other: TmuxGateway) -> Bool {
        return gateway === other
    }

    func position(ofConfigID configID: String) -> Int? {
        return configIDsByPosition.firstIndex(of: configID)
    }

    /// Writes the instance record and tags the leader in one command list, which tmux runs without
    /// interleaving another client's commands. Otherwise another client could read the state in
    /// between, see a record with no leader, and remove the instance as ended.
    func publish(leaderPaneID: Int) {
        RLog("TmuxWorkgroupBinding: publishing instance \(instanceID) with leader %\(leaderPaneID)")
        self.leaderPaneID = leaderPaneID
        let tag = TmuxWorkgroupState.PaneTag(instanceID: instanceID, position: 0)
        gateway?.sendList([TmuxWorkgroupCommands.setRecord(sessionID: sessionID, instanceID: instanceID, record: record),
                           TmuxWorkgroupCommands.tagPane(paneID: leaderPaneID, tag: tag)]) { _ in }
    }

    /// For an instance adopted from the server: its record and tags are already there.
    func adoptLeader(paneID: Int) {
        leaderPaneID = paneID
        isAdopted = true
    }

    /// Adopted from the server rather than entered here. Its split and tab members may arrive
    /// after it was adopted, as the Mac that entered it creates them one by one.
    private(set) var isAdopted = false
    /// Panes of members waiting for their sessions to join. By pane, so a member whose pane went
    /// before its session registered is still adopted when its replacement arrives.
    var lateMembersPending = Set<Int>()

    // MARK: - Peers

    /// A promise for a peer's session, fulfilled when its pane exists here: created by this client
    /// or another, at entry or on demand (see update(from:)).
    func peerPromise(for configID: String) -> iTermPromise<PTYSession> {
        return iTermPromise<PTYSession> { [weak self] seal in
            self?.peerSeals[configID] = seal
        }
    }

    /// The instance as tmux reports it: fulfill the promise of each peer whose pane now exists, once
    /// its session is registered.
    func update(from instance: TmuxWorkgroupState.Instance) {
        guard let controller else {
            return
        }
        paneForPosition = instance.paneForPosition
        visibleMemberByHost = [:]
        for group in instance.peerGroups {
            if let visible = group.visible, group.host < configIDsByPosition.count, visible < configIDsByPosition.count {
                visibleMemberByHost[configIDsByPosition[group.host]] = configIDsByPosition[visible]
            }
        }
        waitingPaneIDs = Set(instance.waitingPositions.compactMap { instance.paneForPosition[$0] })
        keepMemberPanesOnExit(instance.paneForPosition)
        repinParkedPeers(instance.parkedPeersToResize)
        repairIfNeeded(instance)
        for (position, paneID) in instance.paneForPosition where position < configIDsByPosition.count {
            let configID = configIDsByPosition[position]
            guard peerSeals[configID] != nil else {
                continue
            }
            controller.whenPaneRegistered(Int32(paneID)) { [weak self] session in
                guard let self, let session, let seal = self.peerSeals.removeValue(forKey: configID) else {
                    return
                }
                RLog("TmuxWorkgroupBinding: peer \(configID) of \(self.instanceID) is %\(paneID)")
                if let config = self.workgroup.session(withUniqueIdentifier: configID) {
                    self.configurePeerSession?(session, config)
                }
                seal.fulfill(session)
            }
        }
        membersDidUpdate?()
    }

    /// Repairs what TmuxWorkgroupState reports wrong with the instance, under the lock (see
    /// TmuxWorkgroupRepair). An instance without its leader is being removed, not repaired.
    private func repairIfNeeded(_ instance: TmuxWorkgroupState.Instance) {
        guard repairer == nil,
              !repairWaitDeclined,
              !instance.problems.isEmpty,
              !instance.problems.contains(.leaderMissing),
              let controller else {
            return
        }
        RLog("TmuxWorkgroupBinding: repairing \(instanceID): \(instance.problems)")
        withIdentity(controller: controller) { [weak self] identity in
            guard let self, self.repairer == nil else {
                return
            }
            let repairer = TmuxWorkgroupRepairer(gatewayProvider: self.gatewayProvider,
                                                 sessionID: self.sessionID,
                                                 instanceID: self.instanceID,
                                                 identity: identity)
            self.repairer = repairer
            repairer.onWaiting = { [weak self, instanceID] holder in
                RLog("TmuxWorkgroupBinding: repairing \(instanceID) waits on the lock held by \(holder)")
                self?.lockWaitDidChange?()
            }
            repairer.onWaitingEnded = { [weak self] in
                self?.lockWaitDidChange?()
            }
            repairer.run { [weak self, weak repairer] outcome in
                RLog("TmuxWorkgroupBinding: repairing \(self?.instanceID ?? "?") ended: \(outcome)")
                if self?.repairer === repairer {
                    self?.repairer = nil
                    self?.lockWaitDidChange?()
                }
            }
        }
    }

    /// Members' panes this client has made sure stay when their programs exit.
    private var panesKeptOnExit = Set<Int>()

    /// Every member but the leader keeps its pane when its program exits (see
    /// TmuxWorkgroupCommands.memberOptions); otherwise a parked one whose program exits would take
    /// its window, and with it the workgroup. Sent once per pane, as the option stays with it.
    private func keepMemberPanesOnExit(_ paneForPosition: [Int: Int]) {
        // A pane that left and later came back needs it again.
        panesKeptOnExit.formIntersection(paneForPosition.values)
        guard let gateway else {
            return
        }
        for (position, paneID) in paneForPosition where position > 0 && !panesKeptOnExit.contains(paneID) {
            panesKeptOnExit.insert(paneID)
            gateway.sendGuarded(TmuxWorkgroupCommands.keepPaneOnExit(paneID: paneID,
                                                                     instanceID: instanceID,
                                                                     position: position)) { outcome in
                RLog("TmuxWorkgroupBinding: keeping %\(paneID) when its program exits: \(outcome)")
            }
        }
    }

    /// Several clients may do this at once; they pin to the same size.
    private func repinParkedPeers(_ resizes: [TmuxWorkgroupState.Resize]) {
        guard let gateway else {
            return
        }
        for resize in resizes {
            gateway.sendGuarded(TmuxWorkgroupCommands.repinParkedPeer(sessionID: sessionID,
                                                                      instanceID: instanceID,
                                                                      paneID: resize.paneID,
                                                                      width: resize.size.width,
                                                                      height: resize.size.height)) { outcome in
                RLog("TmuxWorkgroupBinding: pinning parked %\(resize.paneID) to \(resize.size.width)x\(resize.size.height): \(outcome)")
            }
        }
    }

    /// For each peer group, by its host's config ID, the member tmux shows, as of the last update.
    private(set) var visibleMemberByHost = [String: String]()

    /// Whether a member's program has not started, as of the last update; nil for a pane not known
    /// to be a member yet.
    func isWaiting(paneID: Int) -> Bool? {
        guard paneForPosition.values.contains(paneID) else {
            return nil
        }
        return waitingPaneIDs.contains(paneID)
    }

    /// Whether the connection is up and staying up: not detached, nor closing its panes to switch
    /// sessions. Only then can tmux be asked about a member whose session ended.
    var isConnected: Bool {
        guard let controller, gateway != nil else {
            return false
        }
        return controller.isAttached && !controller.detaching
    }

    /// The pane at a member's position, as of the last update.
    func paneID(forConfigID configID: String) -> Int? {
        return position(ofConfigID: configID).flatMap { paneForPosition[$0] }
    }

    /// Whether the server has a member at `position` now: after a member's pane is gone, whether it
    /// was replaced (see TmuxWorkgroupCommands.RelaunchMethod) rather than ended. Without a
    /// connection to ask, the completion is not called.
    func positionIsOccupied(_ position: Int, completion: @escaping (Bool) -> Void) {
        let instanceID = self.instanceID
        gateway?.send("list-panes -s -t $\(sessionID) -F '#{pane_id} #{\(TmuxWorkgroupState.paneOptionName)}'") { reply in
            let occupied = (reply ?? "").split(separator: "\n").contains { line in
                let fields = line.split(separator: " ", maxSplits: 1)
                guard fields.count == 2, let tag = TmuxWorkgroupState.PaneTag(encoded: String(fields[1])) else {
                    return false
                }
                return tag.instanceID == instanceID && tag.position == position
            }
            completion(occupied)
        }
    }

    /// What a member runs when it is created: its command, or the waiting script for one that
    /// starts later.
    static func initialCommand(for config: iTermWorkgroupSessionConfig, gitBase: String) -> String {
        if TmuxWorkgroupState.startsWaiting(config.mode) {
            return TmuxWorkgroupCommands.waitingScript
        }
        return config.resolvedCommand(gitBase: gitBase)
    }

    /// Creates the peers among `configs` that are still missing, under the session's workgroup lock,
    /// each in a parked window of its own, in the leader's directory. Their promises are fulfilled
    /// when the refresh that their tags trigger finds them.
    func createPeers(_ configs: [iTermWorkgroupSessionConfig], gitBase: String) {
        guard let gateway, let controller, let leaderPaneID else {
            RLog("TmuxWorkgroupBinding: cannot create peers of \(instanceID): not connected")
            return
        }
        gateway.send("display -p -t %\(leaderPaneID) '#{pane_current_path}'") { [weak self] directory in
            guard let self else {
                return
            }
            var scripts = [Int: String]()
            for config in configs {
                guard let position = self.position(ofConfigID: config.uniqueIdentifier) else {
                    continue
                }
                let command = Self.initialCommand(for: config, gitBase: gitBase)
                scripts[position] = TmuxWorkgroupCommands.memberScript(command: command,
                                                                       directory: directory.flatMap { $0.isEmpty ? nil : $0 })
            }
            self.withIdentity(controller: controller) { [weak self] identity in
                self?.runCreator(identity: identity, scripts: scripts)
            }
        }
    }

    private func runCreator(identity: TmuxWorkgroupCommands.ClientIdentity, scripts: [Int: String]) {
        let creator = TmuxWorkgroupPeerCreator(gatewayProvider: gatewayProvider,
                                               sessionID: sessionID,
                                               instanceID: instanceID,
                                               identity: identity,
                                               scriptsByPosition: scripts)
        creator.onWaiting = { [weak self, instanceID] holder in
            RLog("TmuxWorkgroupBinding: creating peers of \(instanceID) waits on the lock held by \(holder)")
            self?.lockWaitDidChange?()
        }
        creator.onWaitingEnded = { [weak self] in
            self?.lockWaitDidChange?()
        }
        creators.append(creator)
        creator.run { [weak self, weak creator] outcome in
            RLog("TmuxWorkgroupBinding: creating peers of \(self?.instanceID ?? "?") ended: \(outcome)")
            self?.creators.removeAll { $0 === creator }
        }
    }

    // MARK: - Waiting on another client's lock

    /// After isWaitingForLock may have changed.
    var lockWaitDidChange: (() -> Void)?

    /// Whether creating or repairing this instance's peers waits on a lock held by another
    /// connected client, directly or behind another of this client's drivers that does.
    var isWaitingForLock: Bool {
        return creators.contains { $0.isWaiting } || repairer?.isWaiting == true
    }

    /// The user stopped waiting for a repair, so none is tried again until the lock changes or a
    /// client detaches.
    private var repairWaitDeclined = false

    /// The lock changed or a client detached: waiting creations try again. Returns whether a
    /// repair the user stopped waiting for may now be tried, on the next update.
    @discardableResult
    func wakeLockWaiters() -> Bool {
        let retryRepair = repairWaitDeclined
        repairWaitDeclined = false
        for creator in creators {
            creator.wake()
        }
        repairer?.wake()
        return retryRepair
    }

    /// The user chose to take the lock from a holder that is connected but seems stuck.
    func takeOverLock() {
        // Forcing one may end another's wait (one queued behind it), so find them all first.
        let waitingCreators = creators.filter { $0.isWaiting }
        let waitingRepairer = repairer.flatMap { $0.isWaiting ? $0 : nil }
        for creator in waitingCreators {
            creator.force()
        }
        waitingRepairer?.force()
    }

    /// The user chose to stop waiting. The peers are created on demand later, and the repair once
    /// the lock changes.
    func stopWaitingForLock() {
        // Cancelling one ends the wait of those queued behind it, which then start and would
        // wait again, so find them all first.
        let waitingCreators = creators.filter { $0.isWaiting }
        let waitingRepairer = repairer.flatMap { $0.isWaiting ? $0 : nil }
        for creator in waitingCreators {
            creator.cancel()
        }
        if let waitingRepairer {
            repairWaitDeclined = true
            waitingRepairer.cancel()
        }
    }

    /// The bar that says an instance waits, on whichever of its sessions is in view.
    static func lockWaitAnnouncementIdentifier(instanceID: String) -> String {
        return "TmuxWorkgroupLockWait-" + instanceID
    }

    /// How long to wait quietly first: the other client is usually done sooner.
    static let lockWaitAnnouncementDelay: TimeInterval = 3

    /// This connection's identity, which names it as a lock holder.
    private func withIdentity(controller: TmuxController,
                              _ block: @escaping (TmuxWorkgroupCommands.ClientIdentity) -> Void) {
        if let identity = controller.workgroupAttacher?.identity {
            block(identity)
            return
        }
        gateway?.send(TmuxWorkgroupCommands.identityQuery) { [instanceID] reply in
            guard let identity = reply.flatMap({ TmuxWorkgroupCommands.ClientIdentity(reported: $0) }) else {
                RLog("TmuxWorkgroupBinding: tmux did not report this client's identity; not creating peers of \(instanceID)")
                return
            }
            block(identity)
        }
    }

    /// Brings a parked peer into view in place of the visible member, if neither moved meanwhile.
    func switchPeer(visiblePaneID: Int,
                    targetPaneID: Int,
                    completion: @escaping (TmuxWorkgroupCommands.GuardOutcome) -> Void) {
        guard let gateway else {
            completion(.failed)
            return
        }
        gateway.sendGuarded(TmuxWorkgroupCommands.switchPeer(sessionID: sessionID,
                                                             instanceID: instanceID,
                                                             visiblePaneID: visiblePaneID,
                                                             targetPaneID: targetPaneID),
                            outcome: completion)
    }

    // MARK: - Splits and tabs

    /// Splits `parentPaneID` and runs `command` in the new pane, in the parent's directory, tagging
    /// it in the same command list. Calls `completion` with the new pane's ID, or nil if tmux could
    /// not make it.
    func createSplit(configID: String,
                     settings: SplitSettings,
                     command: String,
                     parentPaneID: Int,
                     completion: @escaping (Int?) -> Void) {
        create(configID: configID, command: command, parentPaneID: parentPaneID, completion: completion) { script, tag in
            TmuxWorkgroupCommands.splitWindow(targetPaneID: parentPaneID, settings: settings, script: script, tag: tag)
        }
    }

    /// Like createSplit, but in a new window.
    func createWindow(configID: String,
                      command: String,
                      parentPaneID: Int,
                      completion: @escaping (Int?) -> Void) {
        let sessionID = self.sessionID
        create(configID: configID, command: command, parentPaneID: parentPaneID, completion: completion) { script, tag in
            TmuxWorkgroupCommands.newWindow(sessionID: sessionID, script: script, tag: tag)
        }
    }

    // MARK: - Starting and relaunching members

    /// Replaces what a member runs with the shell command `command` makes, in the member's
    /// directory (or, if its program exited, the leader's). With `onlyIfWaiting`, this is the
    /// member's first start, which happens only if no other client started it first. With
    /// `needsHome`, `command` is given the server's home (e.g. to write a code review's input files
    /// there); otherwise nil. If `command` gives nil, nothing is relaunched. Calls `completion`
    /// with whether the member was relaunched.
    func relaunch(paneID: Int,
                  onlyIfWaiting: Bool,
                  needsHome: Bool,
                  command: @escaping (_ home: String?) -> String?,
                  completion: @escaping (Bool) -> Void) {
        guard let gateway else {
            completion(false)
            return
        }
        var queries = [TmuxWorkgroupCommands.memberQuery(paneID: paneID)]
        let leaderIndex = leaderPaneID.map { leaderPaneID -> Int in
            queries.append("display -p -t %\(leaderPaneID) '#{pane_current_path}'")
            return queries.count - 1
        }
        let homeIndex: Int? = needsHome ? queries.count : nil
        if needsHome {
            queries.append(TmuxWorkgroupCommands.homeQuery)
        }
        gateway.sendList(queries) { [weak self] replies in
            guard let self, let gateway = self.gateway else {
                completion(false)
                return
            }
            guard let member = TmuxWorkgroupCommands.parseMemberQuery(replies[0]),
                  member.tag.instanceID == self.instanceID,
                  member.tag.position > 0 else {
                RLog("TmuxWorkgroupBinding: %\(paneID) is not a member of \(self.instanceID); not relaunching it")
                completion(false)
                return
            }
            if onlyIfWaiting && !member.tag.waiting {
                RLog("TmuxWorkgroupBinding: %\(paneID) already started")
                completion(false)
                return
            }
            let leaderDirectory = leaderIndex.flatMap { replies[$0] }.flatMap {
                TmuxWorkgroupCommands.isAbsolutePath($0) ? $0 : nil
            }
            let home = homeIndex.flatMap { TmuxWorkgroupCommands.home(fromReply: replies[$0]) }
            if needsHome && home == nil {
                RLog("TmuxWorkgroupBinding: tmux did not report its home; not relaunching %\(paneID)")
                completion(false)
                return
            }
            guard let shellCommand = command(home) else {
                completion(false)
                return
            }
            let script = TmuxWorkgroupCommands.memberScript(command: shellCommand,
                                                            directory: member.directory ?? leaderDirectory)
            let method = TmuxWorkgroupCommands.RelaunchMethod(
                respawnIsSafe: gateway.versionAtLeastDecimalNumber(with: TmuxWorkgroupCommands.RelaunchMethod.safeRespawnVersion),
                sessionID: self.sessionID,
                instanceID: self.instanceID)
            // As at creation: every member but the leader keeps its pane when its program exits.
            let remainOnExit = member.tag.position > 0
            let relaunch = { (tag: TmuxWorkgroupState.PaneTag) in
                RLog("TmuxWorkgroupBinding: relaunching %\(paneID) by \(method)")
                gateway.sendList(TmuxWorkgroupCommands.relaunchMember(paneID: paneID, script: script, tag: tag,
                                                                      method: method,
                                                                      remainOnExit: remainOnExit)) { replies in
                    completion(!replies.isEmpty && !replies.contains { $0 == nil })
                }
            }
            guard onlyIfWaiting else {
                relaunch(member.tag)
                return
            }
            gateway.sendGuarded(TmuxWorkgroupCommands.startWaitingMember(paneID: paneID, tag: member.tag)) { outcome in
                RLog("TmuxWorkgroupBinding: starting %\(paneID): \(outcome)")
                guard outcome == .applied else {
                    completion(false)
                    return
                }
                // Started by the claim, so the relaunch need not clear the waiting flag.
                relaunch(member.tag.started)
            }
        }
    }

    /// Whether a pane's program has exited, and which run it is; nil if tmux does not say.
    func paneRun(paneID: Int, completion: @escaping (TmuxWorkgroupCommands.PaneRun?) -> Void) {
        guard let gateway else {
            completion(nil)
            return
        }
        gateway.send(TmuxWorkgroupCommands.paneRunQuery(paneID: paneID)) { reply in
            completion(TmuxWorkgroupCommands.PaneRun(reported: reply))
        }
    }

    /// For a member created after the instance went away.
    func killPane(_ paneID: Int) {
        gateway?.send(TmuxWorkgroupCommands.killPane(paneID)) { _ in }
    }

    /// Ends the instance on the server: untags the leader and unsets the record in one list, then
    /// kills every pane tagged as one of its members except the leader (see
    /// TmuxWorkgroupCommands.endInstance for why in that order). Works from the tags, so it also
    /// removes members this Mac never adopted. Several clients doing it at once is harmless: the
    /// later ones find nothing to remove.
    func removeFromServer() {
        guard let gateway else {
            RLog("TmuxWorkgroupBinding: cannot remove instance \(instanceID) from the server: no gateway")
            return
        }
        controller?.workgroupAttacher?.instanceIsBeingRemoved(instanceID)
        Self.removeFromServer(gateway: gateway, sessionID: sessionID, instanceID: instanceID, leaderPaneID: leaderPaneID)
    }

    /// See removeFromServer(). `leaderPaneID` is nil when the leader is gone.
    ///
    /// A leader that is parked (the member in view was closed, taking the leader's tab with it)
    /// is brought out into an ordinary window, which clients show as a tab: with no workgroup
    /// left to switch back to it, it would otherwise stay hidden.
    static func removeFromServer(gateway: TmuxGateway, sessionID: Int, instanceID: String, leaderPaneID: Int?) {
        RLog("TmuxWorkgroupBinding: removing instance \(instanceID) from the server")
        let queries = ["list-panes -s -t $\(sessionID) -F '#{pane_id} #{\(TmuxWorkgroupState.paneOptionName)}'",
                       Self.leaderWindowQuery(sessionID: sessionID)]
        gateway.sendList(queries) { [weak gateway] replies in
            guard let gateway else {
                return
            }
            gateway.sendList(TmuxWorkgroupCommands.endInstance(sessionID: sessionID,
                                                               instanceID: instanceID,
                                                               leaderPaneID: leaderPaneID)) { _ in }
            if let leaderPaneID,
               let bringOut = Self.bringOutParkedLeader(windowsReply: replies.count > 1 ? replies[1] : nil,
                                                        leaderPaneID: leaderPaneID,
                                                        sessionID: sessionID) {
                RLog("TmuxWorkgroupBinding: the leader %\(leaderPaneID) of \(instanceID) is parked; bringing it out")
                gateway.sendList(bringOut) { _ in }
            }
            for paneID in memberPaneIDs(listPanesReply: replies.first.flatMap { $0 } ?? "", instanceID: instanceID)
            where paneID != leaderPaneID {
                gateway.send(TmuxWorkgroupCommands.killPane(paneID)) { _ in }
            }
        }
    }

    /// Each pane's window, how many panes it holds, and whether it is parked.
    static func leaderWindowQuery(sessionID: Int) -> String {
        return "list-panes -s -t $\(sessionID) -F '#{pane_id} #{window_id} #{window_panes} #{\(TmuxWorkgroupState.parkedOptionName)}'"
    }

    /// The commands that bring the leader out of a parked window, from a leaderWindowQuery reply;
    /// nil when it is not parked, or not there.
    static func bringOutParkedLeader(windowsReply: String?, leaderPaneID: Int, sessionID: Int) -> [String]? {
        for line in (windowsReply ?? "").split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  TmuxWorkgroupCommands.paneID(fromReply: String(fields[0])) == leaderPaneID else {
                continue
            }
            guard fields.count == 4, TmuxWorkgroupAttacher.isParkedWindowTag(String(fields[3])),
                  fields[1].hasPrefix("@"), let windowID = Int(fields[1].dropFirst()),
                  let panes = Int(fields[2]) else {
                return nil
            }
            return TmuxWorkgroupCommands.bringOutPane(sessionID: sessionID,
                                                      paneID: leaderPaneID,
                                                      windowID: windowID,
                                                      sharesWindow: panes > 1)
        }
        return nil
    }

    /// A member's session ended on this Mac. If its pane is gone from the server the member really
    /// ended, so the instance ends there too. If the pane is still there, only this Mac's session
    /// went away (its window was hidden, or this client detached), and nothing on the server
    /// changes. Without a gateway nothing can be known, so nothing changes.
    ///
    /// The instance that asks has usually ended here already and released this binding by the time
    /// tmux answers, so the answer is acted on with what is captured now, not through the binding.
    func removeFromServerIfPaneIsGone(_ paneID: Int) {
        let sessionID = self.sessionID
        let instanceID = self.instanceID
        let leaderPaneID = self.leaderPaneID
        weak let controller = self.controller
        let gatewayProvider = self.gatewayProvider
        paneExists(paneID) { exists in
            guard exists == false else {
                // The session went but the pane stayed, e.g. it moved into a new window (a repair
                // that brought the leader out), whose tab has a new session for it. Adopt the
                // instance again once that session is registered.
                RLog("TmuxWorkgroupBinding: %\(paneID) is still on the server; instance stays there")
                controller?.whenPaneRegistered(Int32(paneID)) { [weak controller] _ in
                    controller?.workgroupAttacher?.refresh()
                }
                return
            }
            guard let gateway = gatewayProvider() else {
                RLog("TmuxWorkgroupBinding: cannot remove instance \(instanceID) from the server: no gateway")
                return
            }
            controller?.workgroupAttacher?.instanceIsBeingRemoved(instanceID)
            Self.removeFromServer(gateway: gateway, sessionID: sessionID, instanceID: instanceID,
                                  leaderPaneID: leaderPaneID == paneID ? nil : leaderPaneID)
        }
    }

    /// Whether tmux still has the pane. Without a connection to ask, the completion is not called.
    func paneExists(_ paneID: Int, completion: @escaping (Bool) -> Void) {
        gateway?.send("display -p -t %\(paneID) '#{pane_id}'") { reply in
            completion(TmuxWorkgroupCommands.paneID(fromReply: reply) == paneID)
        }
    }

    /// Pane IDs in a `list-panes -F '#{pane_id} #{@iterm2_wg}'` reply whose tag names this instance.
    static func memberPaneIDs(listPanesReply reply: String, instanceID: String) -> [Int] {
        return reply.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 1)
            guard fields.count == 2,
                  let paneID = TmuxWorkgroupCommands.paneID(fromReply: String(fields[0])),
                  TmuxWorkgroupState.PaneTag(encoded: String(fields[1]))?.instanceID == instanceID else {
                return nil
            }
            return paneID
        }
    }

    private func create(configID: String,
                        command: String,
                        parentPaneID: Int,
                        completion: @escaping (Int?) -> Void,
                        build: @escaping (String, TmuxWorkgroupState.PaneTag) -> [String]) {
        guard let gateway, let position = position(ofConfigID: configID) else {
            completion(nil)
            return
        }
        // The directory comes from tmux, so it reaches the server again only inside the encoded
        // script.
        gateway.send("display -p -t %\(parentPaneID) '#{pane_current_path}'") { [weak self] directory in
            guard let self, let gateway = self.gateway else {
                completion(nil)
                return
            }
            let script = TmuxWorkgroupCommands.memberScript(command: command,
                                                            directory: directory.flatMap { $0.isEmpty ? nil : $0 })
            let waiting = self.workgroup.session(withUniqueIdentifier: configID).map {
                TmuxWorkgroupState.startsWaiting($0.mode)
            } ?? false
            let tag = TmuxWorkgroupState.PaneTag(instanceID: self.instanceID, position: position, waiting: waiting)
            gateway.sendList(build(script, tag)) { replies in
                guard let paneID = TmuxWorkgroupCommands.paneID(fromReply: replies.first ?? nil) else {
                    RLog("TmuxWorkgroupBinding: tmux did not create member \(configID): \((replies.first ?? nil) ?? "(error)")")
                    completion(nil)
                    return
                }
                completion(paneID)
            }
        }
    }

}

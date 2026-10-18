//
//  TmuxWorkgroupHiddenPaneOffer.swift
//  iTerm2SharedARC
//
//  Offers the user the panes hidden from this Mac in parked windows (TmuxWorkgroupHiddenPanes):
//  open them in tabs or stop them. Nothing is left hidden, so dismissing the offer opens them. It
//  is an announcement in the instance's leader, which is in view, or else in any tab of this tmux
//  connection. When the instance is still on the server, the offer says that other Macs using its
//  workgroup will lose these panes. The choice is carried out while holding the session's
//  workgroup lock, since other clients may be switching peers.
//

import Foundation

final class TmuxWorkgroupHiddenPaneOffer {
    private typealias Group = TmuxWorkgroupHiddenPanes.Group

    private weak var controller: TmuxController?
    private let identity: () -> TmuxWorkgroupCommands.ClientIdentity?
    /// What is hidden now, by instance ID; a choice applies to these.
    private var latest = [String: Group]()
    private var adoptedHere = Set<String>()
    /// The session showing each instance's offer.
    private var hosts = [String: WeakBox<PTYSession>]()
    /// Choices being carried out, by instance ID. No new offer is made meanwhile.
    private var releasers = [String: TmuxWorkgroupRepairer]()
    /// Called when a choice has been carried out, so a fresh snapshot shows what is left.
    var didRelease: (() -> Void)?

    static func announcementIdentifier(instanceID: String) -> String {
        return "TmuxWorkgroupHiddenPanes." + instanceID
    }

    init(controller: TmuxController, identity: @escaping () -> TmuxWorkgroupCommands.ClientIdentity?) {
        self.controller = controller
        self.identity = identity
    }

    /// Called with each fresh snapshot.
    func update(_ groups: [TmuxWorkgroupHiddenPanes.Group], adoptedHere: Set<String>) {
        self.adoptedHere = adoptedHere
        let previous = latest
        latest = Dictionary(groups.map { ($0.instanceID, $0) }, uniquingKeysWith: { first, _ in first })
        for instanceID in previous.keys where latest[instanceID] == nil {
            // Nothing of it is hidden any more (another client acted, or the panes exited).
            withdraw(instanceID: instanceID)
        }
        for group in groups where releasers[group.instanceID] == nil {
            offer(group)
        }
    }

    /// The lock changed or a client detached.
    func wake() {
        for releaser in releasers.values {
            releaser.wake()
        }
    }

    private func withdraw(instanceID: String) {
        // Its completion finds nothing in `latest` and does nothing.
        hosts.removeValue(forKey: instanceID)?.value?.dismissAnnouncement(
            withIdentifier: Self.announcementIdentifier(instanceID: instanceID))
    }

    /// The leader if it is in a tab here, else the first tab session of this connection.
    private func host(for group: Group) -> PTYSession? {
        guard let controller else {
            return nil
        }
        if let leaderPaneID = group.leaderPaneID,
           let leader = controller.session(forWindowPane: Int32(leaderPaneID)),
           leader.delegate != nil {
            return leader
        }
        return controller.clientSessions()
            .filter { $0.delegate != nil }
            .min { $0.tmuxPane < $1.tmuxPane }
    }

    private func offer(_ group: Group) {
        let instanceID = group.instanceID
        let identifier = Self.announcementIdentifier(instanceID: instanceID)
        if let shown = hosts[instanceID]?.value, shown.hasAnnouncement(withIdentifier: identifier) {
            return
        }
        guard let host = host(for: group) else {
            DLog("No session to offer hidden panes \(group.paneIDs) of \(instanceID) in")
            return
        }
        RLog("TmuxWorkgroupHiddenPaneOffer: panes \(group.paneIDs) of instance \(instanceID) are hidden here")
        let count = group.paneIDs.count
        let title = group.inUseElsewhere ?
            String(localized: "TmuxWorkgroup.HiddenPanes.InUse",
                   defaultValue: "\(count) programs from a workgroup this Mac doesn’t use are in hidden tmux windows. Macs using that workgroup will lose them if you open or stop them here.",
                   comment: "Announcement shown when a tmux session has programs in hidden windows that belong to a workgroup none of this Mac’s workgroups match. Another Mac may be using them. The count is the number of programs.") :
            String(localized: "TmuxWorkgroup.HiddenPanes.Ended",
                   defaultValue: "\(count) programs from a workgroup that has ended are still running in hidden tmux windows.",
                   comment: "Announcement shown when a tmux session has programs left in hidden windows by a workgroup that no longer exists. The count is the number of programs.")
        let actions = [String(localized: "TmuxWorkgroup.HiddenPanes.Open",
                              defaultValue: "Open in Tabs",
                              comment: "Button that shows each program found in a hidden tmux window in a tab of its own"),
                       String(localized: "TmuxWorkgroup.HiddenPanes.Stop",
                              defaultValue: "Stop Them",
                              comment: "Button that stops the programs found in hidden tmux windows")]
        // Called again with -2 when it goes away after a choice.
        var decided = false
        let choose: (Int32) -> Void = { [weak self, weak host] choice in
            guard !decided else {
                return
            }
            decided = true
            guard let self else {
                return
            }
            if self.hosts[instanceID]?.value === host {
                self.hosts.removeValue(forKey: instanceID)
            }
            guard choice >= 0 || host?.delegate != nil else {
                // Its session closed, which is no choice. The next snapshot offers them again.
                return
            }
            // Dismissing it leaves nothing hidden either.
            self.release(instanceID: instanceID, choice: choice == 1 ? .stop : .open)
        }
        guard let announcement = iTermAnnouncementViewController.announcement(withTitle: title,
                                                                                style: .kiTermAnnouncementViewStyleWarning,
                                                                                withActions: actions,
                                                                                completion: choose) else {
            return
        }
        hosts[instanceID] = WeakBox(host)
        host.queueAnnouncement(announcement, identifier: identifier)
    }

    private func release(instanceID: String, choice: TmuxWorkgroupHiddenPaneRelease.Choice) {
        guard let group = latest[instanceID], releasers[instanceID] == nil else {
            return
        }
        guard let controller, controller.gateway != nil, let identity = identity() else {
            RLog("TmuxWorkgroupHiddenPaneOffer: cannot act on hidden panes of \(instanceID): not connected, or tmux did not say who this client is")
            return
        }
        RLog("TmuxWorkgroupHiddenPaneOffer: \(choice) panes \(group.paneIDs) of instance \(instanceID)")
        let repairer = TmuxWorkgroupRepairer(
            gatewayProvider: { [weak controller] in controller?.gateway },
            sessionID: Int(controller.sessionId),
            identity: identity,
            repair: TmuxWorkgroupHiddenPaneRelease(sessionID: Int(controller.sessionId),
                                                   instanceID: instanceID,
                                                   paneIDs: group.paneIDs,
                                                   choice: choice,
                                                   adoptedHere: adoptedHere))
        releasers[instanceID] = repairer
        repairer.onWaiting = { holder in
            RLog("TmuxWorkgroupHiddenPaneOffer: waiting on the lock held by \(holder)")
        }
        repairer.run { [weak self, weak repairer] outcome in
            RLog("TmuxWorkgroupHiddenPaneOffer: acting on hidden panes of \(instanceID) ended: \(outcome)")
            guard let self, self.releasers[instanceID] === repairer else {
                return
            }
            self.releasers.removeValue(forKey: instanceID)
            self.didRelease?()
        }
    }
}

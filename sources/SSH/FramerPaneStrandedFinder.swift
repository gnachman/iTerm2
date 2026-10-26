//
//  FramerPaneStrandedFinder.swift
//  iTerm2SharedARC
//
//  A workgroup peer's pane keeps running on its host when iTerm2 restarts. If its session is not
//  restored with it (its window was not saved, say), the pane is stranded: running, with no
//  session to show it. This finds those panes and offers the user to open them in tabs or to
//  stop them. Until the user decides, the conductor keeps what they write (see
//  Conductor+Panes.swift).
//
//  A pane is only stranded once every session that might claim it has had the chance: after
//  window restoration has settled, as for orphaned job servers, and after the pane's conductor
//  has resynchronized with its framer.
//

import Foundation

@MainActor
protocol StrandedFramerPanePresenter: AnyObject {
    /// Called with the panes on `conductor` that no session claims.
    func present(strandedPanes pids: [Int32], on conductor: Conductor)
}

@MainActor
@objc(iTermFramerPaneStrandedFinder)
final class FramerPaneStrandedFinder: NSObject {
    @objc(sharedInstance) static let shared = FramerPaneStrandedFinder(
        presenter: StrandedFramerPaneAnnouncer(),
        observesConductors: true,
        isOwned: { StrandedFramerPaneAnnouncer.owner(of: $0) != nil },
        claimedPIDs: { FramerPaneJobManager.claimedPIDs(on: $0) },
        reattachAll: { FramerPaneJobManager.reattachAllIfNeeded() })

    private(set) var restorationSettled = false
    /// Conductors that resynchronized before restoration settled.
    private let waiting = NSHashTable<Conductor>.weakObjects()
    private let presenter: StrandedFramerPanePresenter
    private let isOwned: (Conductor) -> Bool
    private let claimedPIDs: (Conductor) -> Set<Int32>
    private let reattachAll: () -> Void

    init(presenter: StrandedFramerPanePresenter,
         observesConductors: Bool,
         isOwned: @escaping (Conductor) -> Bool,
         claimedPIDs: @escaping (Conductor) -> Set<Int32>,
         reattachAll: @escaping () -> Void) {
        self.presenter = presenter
        self.isOwned = isOwned
        self.claimedPIDs = claimedPIDs
        self.reattachAll = reattachAll
        super.init()
        if observesConductors {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(conductorDidResynchronizeNotification(_:)),
                                                   name: Conductor.didResynchronizeNotification,
                                                   object: nil)
        }
    }

    /// Window restoration is done: every session that will be restored has been.
    @objc func restorationDidSettle() {
        guard !restorationSettled else {
            return
        }
        DLog("Restoration settled. Look for stranded panes on \(waiting.count) conductors")
        restorationSettled = true
        let conductors = waiting.allObjects
        waiting.removeAllObjects()
        for conductor in conductors {
            check(conductor)
        }
    }

    @objc private nonisolated func conductorDidResynchronizeNotification(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let conductor = notification.object as? Conductor else {
                return
            }
            conductorDidResynchronize(conductor)
        }
    }

    func conductorDidResynchronize(_ conductor: Conductor) {
        guard restorationSettled else {
            waiting.add(conductor)
            return
        }
        check(conductor)
    }

    private func check(_ conductor: Conductor) {
        guard conductor.framing, !conductor.awaitingResynchronization, isOwned(conductor) else {
            return
        }
        // Their requests go ahead of the query, so their answers come first.
        reattachAll()
        conductor.runningPanes { [weak self, weak conductor] running in
            guard let self, let conductor, let running else {
                return
            }
            let stranded = running
                .subtracting(conductor.panes.keys)
                .subtracting(self.claimedPIDs(conductor))
            guard !stranded.isEmpty else {
                return
            }
            RLog("Found \(stranded.count) stranded panes on \(conductor.guid)")
            self.presenter.present(strandedPanes: stranded.sorted(), on: conductor)
        }
    }
}

/// Offers stranded panes in an announcement in the session that owns their connection.
@MainActor
final class StrandedFramerPaneAnnouncer: StrandedFramerPanePresenter {
    /// Per owner rather than per conductor, which a recovery replaces.
    static func announcementIdentifier(for owner: PTYSession) -> String {
        return "StrandedFramerPanes." + owner.guid
    }

    /// The session whose connection `conductor` is.
    static func owner(of conductor: Conductor) -> PTYSession? {
        var result: PTYSession?
        iTermController.sharedInstance()?.enumerateSessionLookupLocations { session, _, stop in
            if session?.conductor === conductor {
                result = session
                stop?.pointee = true
            }
        }
        return result
    }

    func present(strandedPanes pids: [Int32], on conductor: Conductor) {
        guard let owner = Self.owner(of: conductor) else {
            return
        }
        let identifier = Self.announcementIdentifier(for: owner)
        guard !owner.hasAnnouncement(withIdentifier: identifier) else {
            return
        }
        let title = String(localized: "FramerPane.Stranded.Title",
                           defaultValue: "\(pids.count) programs started as workgroup peers are still running on this host but have no session.",
                           comment: "Announcement shown when programs that iTerm2 ran on a remote host for a workgroup are still running there after a restart, but their sessions were not restored. The count is the number of programs.")
        let actions = [String(localized: "FramerPane.Stranded.Open",
                              defaultValue: "Open in Tabs",
                              comment: "Button that opens each program left running on the remote host in a new tab"),
                       String(localized: "FramerPane.Stranded.Stop",
                              defaultValue: "Stop Them",
                              comment: "Button that stops the programs left running on the remote host")]
        // Called again with -2 when it goes away after a choice.
        var decided = false
        let choose: (Int32) -> Void = { [weak owner] choice in
            // The connection as of now, in case it was recovered meanwhile.
            guard !decided, let owner, let conductor = owner.conductor, conductor.framing else {
                return
            }
            decided = true
            switch choice {
            case 0:
                RLog("Open \(pids.count) stranded panes in tabs")
                for pid in pids {
                    owner.openStrandedFramerPane(pid)
                }
            case 1:
                RLog("User chose to stop \(pids.count) stranded panes")
                for pid in pids {
                    conductor.stopUnclaimedPane(pid)
                }
            default:
                // Closed without a choice: they keep running, unclaimed.
                RLog("Stranded panes offer closed without a choice")
            }
        }
        guard let announcement = iTermAnnouncementViewController.announcement(withTitle: title,
                                                                                style: .kiTermAnnouncementViewStyleWarning,
                                                                                withActions: actions,
                                                                                completion: choose) else {
            return
        }
        owner.queueAnnouncement(announcement, identifier: identifier)
    }
}

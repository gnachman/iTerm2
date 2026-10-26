//
//  PTYSession+FramerPane.swift
//  iTerm2SharedARC
//
//  A workgroup peer of a leader on a remote host runs its program as a pane of the leader's
//  framer (Conductor+Panes.swift) when it can, rather than over an ssh connection of its own:
//  no new login, no hops to replay, and it is on the right host as the right user however the
//  leader got there. If the pane cannot start, for example because the leader's framer is too
//  old to have `pane`, the peer connects over ssh as before.
//

import Foundation

extension PTYSession {
    /// Starts `command` as a pane of the leader's framer if it is the launch command made for
    /// this remote peer and the leader's connection is up. Returns false to have the caller
    /// start it as usual. Once this returns true, `completion` is called with true when the pane
    /// starts; if it cannot start, `fallback` runs instead and starts the program as usual.
    @objc(startWorkgroupProgramInFramerPaneIfPossible:completion:fallback:)
    func startWorkgroupProgramInFramerPaneIfPossible(_ command: String,
                                                     completion: ((Bool) -> Void)?,
                                                     fallback: @escaping () -> Void) -> Bool {
        return MainActor.assumeIsolated {
            guard let launch = swiftState.framerPaneLaunch,
                  launch.launchCommand == command,
                  let remote = workgroupRemoteHost,
                  let conductor = remote.conductorForNewPane,
                  let jobManager = makeFramerPaneJobManager() else {
                return false
            }
            let size = screen.size
            let directory = remote.currentDirectory ?? "~"
            RLog("PTYSession[\(guid)]: start workgroup peer as a pane of its leader's framer")
            conductor.startPane(rows: Int(size.height),
                                cols: Int(size.width),
                                directory: directory,
                                // Run as a peer's own connection runs it, with the user's
                                // interactive PATH. An empty command is a login shell.
                                command: launch.shellCommand.isEmpty
                                    ? "" : WorkgroupRemoteHost.peerRemoteCommand(launch.shellCommand),
                                environment: framerPaneEnvironment(),
                                client: jobManager) { [weak self] pid in
                guard let self else {
                    return
                }
                guard let pid else {
                    RLog("PTYSession[\(self.guid)]: the leader's framer could not start a pane. Connect over ssh instead.")
                    fallback()
                    return
                }
                jobManager.paneDidStart(pid: pid)
                self.shell.framerPaneJobManager = jobManager
                self.framerPaneDidStart(withCommand: command, remotePID: pid)
                completion?(true)
            }
            return true
        }
    }

    /// The connection the pane runs over: its leader's, or for an adopted pane, its owner's.
    @objc var framerPaneHostConductor: Conductor? {
        return MainActor.assumeIsolated {
            if let workgroupRemoteHost {
                return workgroupRemoteHost.leaderHostConductor
            }
            guard let ownerGUID = swiftState.framerPaneOwnerGUID,
                  let owner = iTermController.sharedInstance()?.anySession(withGUID: ownerGUID),
                  let conductor = owner.hostConductor,
                  conductor.framing else {
                return nil
            }
            return conductor
        }
    }

    /// Opens the stranded pane `pid` on this session's connection in a new tab, with what it
    /// wrote while it had no session. See FramerPaneStrandedFinder.
    @MainActor
    func openStrandedFramerPane(_ pid: Int32) {
        guard let windowController = (delegate?.realParentWindow() as? PseudoTerminal) ??
                iTermController.sharedInstance()?.currentTerminal,
              let factory = windowController.sessionFactory,
              let profile else {
            RLog("PTYSession[\(guid)]: no window to open stranded pane \(pid) in")
            return
        }
        let newSession = factory.newSession(withProfile: profile, parent: self)
        // Keep what it printed last when it ends rather than closing.
        newSession.forceDefaultEndAction = true
        windowController.addSession(inNewTab: newSession)
        newSession.adoptFramerPane(pid, ownerGUID: guid)
    }

    @MainActor
    private func adoptFramerPane(_ pid: Int32, ownerGUID: String) {
        guard let jobManager = makeFramerPaneJobManager() else {
            return
        }
        RLog("PTYSession[\(guid)]: adopt stranded pane \(pid) of \(ownerGUID)")
        swiftState.framerPaneOwnerGUID = ownerGUID
        shell.framerPaneJobManager = jobManager
        jobManager.restore(pid: pid)
    }

    @MainActor
    private func makeFramerPaneJobManager() -> FramerPaneJobManager? {
        let manager = FramerPaneJobManager(
            conductorProvider: { [weak self] in self?.framerPaneHostConductor },
            gridSizeProvider: { [weak self] in self?.screen.size })
        if let ledger = manager?.consumptionLedger {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.consumptionLedger = ledger
            })
        }
        manager?.didReattach = { [weak self] pid in
            guard let self else {
                return
            }
            RLog("PTYSession[\(self.guid)]: reattached to pane \(pid)")
            self.framerPaneDidStart(withCommand: self.swiftState.framerPaneLaunch?.launchCommand,
                                    remotePID: pid)
        }
        return manager
    }

    private enum FramerPaneKey {
        static let pid = "pid"
        static let command = "command"
        static let owner = "owner"
    }

    /// Saved with the session, so after a restart it reattaches to the pane, which keeps
    /// running on the leader's host, instead of starting its program again.
    @objc var framerPaneArrangement: [String: Any]? {
        guard let pid = shell.framerPaneJobManager?.remotePID else {
            return nil
        }
        let launch = swiftState.framerPaneLaunch
        let owner = swiftState.framerPaneOwnerGUID
        guard launch != nil || owner != nil else {
            return nil
        }
        var result: [String: Any] = [FramerPaneKey.pid: NSNumber(value: pid)]
        result[FramerPaneKey.command] = launch?.shellCommand
        result[FramerPaneKey.owner] = owner
        return result
    }

    /// Restoring a session saved with framerPaneArrangement: nothing is launched. The session
    /// keeps its restored contents and reattaches to the pane once its leader's connection is
    /// back (see FramerPaneJobManager). `launchCommand` is the session's program. Returns
    /// false if `arrangement` is not usable.
    @objc(restoreFramerPaneFromArrangement:launchCommand:)
    func restoreFramerPane(fromArrangement arrangement: [AnyHashable: Any],
                           launchCommand: String?) -> Bool {
        return MainActor.assumeIsolated {
            guard let pid = (arrangement[FramerPaneKey.pid] as? NSNumber)?.int32Value else {
                return false
            }
            let shellCommand = arrangement[FramerPaneKey.command] as? String
            let owner = arrangement[FramerPaneKey.owner] as? String
            // A workgroup peer relaunches with its command; an adopted pane finds its connection
            // through its owner.
            let launch = launchCommand.flatMap { launchCommand in
                shellCommand.map { (launchCommand, $0) }
            }
            guard launch != nil || owner != nil,
                  let jobManager = makeFramerPaneJobManager() else {
                return false
            }
            RLog("PTYSession[\(guid)]: restored session waits to reattach to pane \(pid)")
            // A relaunch runs the same command as a new pane.
            swiftState.framerPaneLaunch = launch
            swiftState.framerPaneOwnerGUID = owner
            shell.framerPaneJobManager = jobManager
            jobManager.restore(pid: pid)
            return true
        }
    }

    /// Workgroup restoration gives a restored peer its leader after the session exists.
    @MainActor
    func framerPaneLeaderDidChange() {
        shell.framerPaneJobManager?.reattachIfNeeded()
    }
}

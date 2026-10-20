//
//  Conductor+Panes.swift
//  iTerm2SharedARC
//
//  A pane is a program a workgroup peer runs through its leader's framer (framer.py `pane`)
//  instead of over an ssh connection of its own: it needs no new login and is on the right
//  host as the right user however the leader got there. Its output arrives in the leader's
//  stream on the pane channel and is passed to the client that started it.
//

import Foundation

/// The session side of a pane. Called on the main thread.
@objc protocol ConductorPaneClient: AnyObject {
    func conductorPaneDidOutput(_ data: Data)
    func conductorPaneDidExit(code: Int32)
    /// The connection to the pane's host is gone, so nothing more will be heard from it.
    func conductorPaneDidLoseConnection()
}

/// What reattaching to a pane found.
enum PaneReattachment: Equatable {
    /// The client gets the pane's output from now on (or its exit, if it ended meanwhile).
    case reattached
    /// The pane is gone with no exit to report.
    case gone
    /// The framer could not say, as when the connection ended or was reset first. Try again
    /// on the next conductor.
    case unknown
}

/// A pane's output and exit kept for its session until it reattaches.
struct UnclaimedPane {
    var output = Data()
    var exitCode: Int32?
}

extension Conductor {
    /// Posted once a conductor restored after a restart, or made by recovery, has
    /// resynchronized with its framer. Pane sessions reattach then.
    nonisolated static let didResynchronizeNotification = Notification.Name("iTermConductorDidResynchronize")

    @objc nonisolated static var didResynchronizeNotificationName: String {
        return didResynchronizeNotification.rawValue
    }

    /// Runs `command` with the remote login shell in `directory`, on a pty of its own sized
    /// rows x cols, with `environment` added to the framer's. An empty command runs an
    /// interactive login shell. `completion` gets its pid, or nil if it could not be started.
    func startPane(rows: Int,
                   cols: Int,
                   directory: String,
                   command: String,
                   environment: [String: String] = [:],
                   client: ConductorPaneClient,
                   completion: @escaping (Int32?) -> ()) {
        DLog("Start pane \(rows)x\(cols) in \(directory)")
        send(.framerPane(rows: rows, cols: cols, cwd: directory, command: command,
                         environment: environment),
             .handleEphemeralCompletion(StringArray(), .init({ [weak self] string, status in
                 guard let self else {
                     completion(nil)
                     return
                 }
                 guard status == 0, let pid = Int32(string) else {
                     self.DLog("Pane failed to start with status \(status): \(string)")
                     completion(nil)
                     return
                 }
                 self.DLog("Pane started with pid \(pid)")
                 self.panes[pid] = WeakBox(client)
                 self.flowPaneDidStart(pid)
                 completion(pid)
                 // Pane output leaves for its session as soon as it is parsed, so the first of
                 // it can arrive before this reply is handled, and was kept as unclaimed.
                 if let unclaimed = self.unclaimedPanes.removeValue(forKey: pid) {
                     if !unclaimed.output.isEmpty {
                         client.conductorPaneDidOutput(unclaimed.output)
                     }
                     if let code = unclaimed.exitCode {
                         self.panes.removeValue(forKey: pid)
                         client.conductorPaneDidExit(code: code)
                     }
                 }
             })))
    }

    func sendToPane(_ pid: Int32, data: Data) {
        send(.framerSend(data, pid: pid), .fireAndForget)
    }

    func resizePane(_ pid: Int32, rows: Int, cols: Int) {
        send(.framerPaneSize(pid: pid, rows: rows, cols: cols), .fireAndForget)
    }

    /// Sends SIGTERM. The client still hears about the exit when the framer reports it.
    func killPane(_ pid: Int32) {
        send(.framerKill(pid: Int(pid)), .fireAndForget)
    }

    @objc(handlePaneOutput:pid:depth:)
    func handlePaneOutput(_ data: Data, pid: Int32, depth: Int32) {
        if depth != self.depth {
            parent?.handlePaneOutput(data, pid: pid, depth: depth)
            return
        }
        guard let box = panes[pid] else {
            if stoppingPanes.contains(pid) {
                return
            }
            // Its session has not reattached yet. Keep the output for it.
            DLog("Keep \(data.count) bytes for unclaimed pane \(pid)")
            unclaimedPanes[pid, default: UnclaimedPane()].output.append(data)
            return
        }
        guard let client = box.value else {
            DLog("Pane \(pid) has no client any more. Kill it.")
            panes.removeValue(forKey: pid)
            // As when the user stops it: whatever it writes until it exits is dropped, not kept
            // for a session that will never come.
            stoppingPanes.insert(pid)
            killPane(pid)
            return
        }
        client.conductorPaneDidOutput(data)
    }

    /// Reconnects `client` to the pane `pid` after a restart or a recovery: it gets what the
    /// pane wrote meanwhile, then its output from now on, or its exit if it ended.
    func reattachPane(_ pid: Int32,
                      client: ConductorPaneClient,
                      completion: @escaping (PaneReattachment) -> ()) {
        DLog("Reattach pane \(pid)")
        runningPanes { [weak self] answer in
            guard let self, let running = answer else {
                // Nothing was learned; what was kept for the pane stays kept.
                completion(.unknown)
                return
            }
            let unclaimed = self.unclaimedPanes.removeValue(forKey: pid)
            if running.contains(pid) {
                self.panes[pid] = WeakBox(client)
            }
            if let output = unclaimed?.output, !output.isEmpty {
                client.conductorPaneDidOutput(output)
            }
            if let code = unclaimed?.exitCode {
                client.conductorPaneDidExit(code: code)
                completion(.reattached)
                return
            }
            guard running.contains(pid) else {
                self.DLog("Pane \(pid) is gone")
                completion(.gone)
                return
            }
            completion(.reattached)
        }
    }

    /// The pids of the framer's running panes, or nil if it could not say.
    func runningPanes(_ completion: @escaping (Set<Int32>?) -> ()) {
        send(.framerPanes, .handleEphemeralCompletion(StringArray(), .init({ [weak self] string, status in
            guard let self, status == 0 else {
                completion(nil)
                return
            }
            let running = Set(string.split(separator: " ").compactMap { Int32($0) })
            self.knownPanePIDs.formUnion(running)
            for pid in running.sorted() {
                self.flowPaneDidStart(pid)
            }
            completion(running)
        })))
    }

    /// Kills a pane no session claims, at the user's request. Its output is no longer kept.
    func stopUnclaimedPane(_ pid: Int32) {
        DLog("Stop unclaimed pane \(pid)")
        unclaimedPanes.removeValue(forKey: pid)
        stoppingPanes.insert(pid)
        killPane(pid)
    }

    /// Recovery replaces `other` with this conductor while the framer, and its panes, keep
    /// running: take over what it kept for panes no session has claimed.
    @objc(adoptUnclaimedPanesFrom:)
    func adoptUnclaimedPanes(from other: Conductor?) {
        guard let other else {
            return
        }
        for (pid, pane) in other.unclaimedPanes {
            var merged = pane
            if let mine = unclaimedPanes[pid] {
                merged.output.append(mine.output)
                merged.exitCode = mine.exitCode ?? pane.exitCode
            }
            unclaimedPanes[pid] = merged
        }
        other.unclaimedPanes.removeAll()
    }

    /// The connection is ending: tell every pane's client, since no exit will be reported.
    @objc func abandonPanes() {
        let clients = panes.values.compactMap(\.value)
        panes.removeAll()
        unclaimedPanes.removeAll()
        knownPanePIDs.removeAll()
        stoppingPanes.removeAll()
        for client in clients {
            client.conductorPaneDidLoseConnection()
        }
    }

    /// Returns whether pid was a pane. Called with a termination reported at this depth.
    func handlePaneTermination(_ pid: Int32, code: Int32) -> Bool {
        flowPaneDidEnd(pid)
        guard let box = panes.removeValue(forKey: pid) else {
            if stoppingPanes.remove(pid) != nil {
                DLog("Stopped pane \(pid) exited with \(code)")
                knownPanePIDs.remove(pid)
                return true
            }
            guard unclaimedPanes[pid] != nil || knownPanePIDs.contains(pid) else {
                return false
            }
            // A pane whose session has not reattached yet: it learns of the exit when it does.
            DLog("Unclaimed pane \(pid) exited with \(code)")
            unclaimedPanes[pid, default: UnclaimedPane()].exitCode = code
            knownPanePIDs.remove(pid)
            return true
        }
        DLog("Pane \(pid) exited with \(code)")
        box.value?.conductorPaneDidExit(code: code)
        return true
    }
}

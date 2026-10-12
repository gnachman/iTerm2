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
}

extension Conductor {
    /// Runs `command` with the remote login shell in `directory`, on a pty of its own sized
    /// rows x cols. `completion` gets its pid, or nil if it could not be started.
    func startPane(rows: Int,
                   cols: Int,
                   directory: String,
                   command: String,
                   client: ConductorPaneClient,
                   completion: @escaping (Int32?) -> ()) {
        DLog("Start pane \(rows)x\(cols) in \(directory)")
        send(.framerPane(rows: rows, cols: cols, cwd: directory, command: command),
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
                 completion(pid)
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
            DLog("Drop output for unknown pane \(pid)")
            return
        }
        guard let client = box.value else {
            DLog("Pane \(pid) has no client any more. Kill it.")
            panes.removeValue(forKey: pid)
            killPane(pid)
            return
        }
        client.conductorPaneDidOutput(data)
    }

    /// Returns whether pid was a pane. Called with a termination reported at this depth.
    func handlePaneTermination(_ pid: Int32, code: Int32) -> Bool {
        guard let box = panes.removeValue(forKey: pid) else {
            return false
        }
        DLog("Pane \(pid) exited with \(code)")
        box.value?.conductorPaneDidExit(code: code)
        return true
    }
}

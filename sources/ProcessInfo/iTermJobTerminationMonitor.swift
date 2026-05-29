//
//  iTermJobTerminationMonitor.swift
//  iTerm2
//
//  Watches arbitrary processes by PID and shows a modal alert when they
//  terminate. Used by the jobs view (toolbelt and status bar popover) to
//  implement the "Notify on Termination" context menu item.
//

import AppKit

@objc(iTermJobTerminationMonitor)
class iTermJobTerminationMonitor: NSObject {
    @objc(sharedInstance) static let shared = iTermJobTerminationMonitor()

    // Posted (on the main thread) whenever the set of monitored PIDs changes, so views
    // showing the jobs list can refresh their "notify on termination" indicator.
    @objc static let stateDidChangeNotificationName = "iTermJobTerminationMonitorStateDidChange"

    // All state below is accessed only on the main thread.
    private var sources = [pid_t: DispatchSourceProcess]()
    private var names = [pid_t: String]()

    // Terminations waiting to be shown, plus whether a modal alert is currently up.
    // Buffering lets near-simultaneous exits coalesce into one alert and prevents a
    // second runModal from nesting inside the first.
    private var pendingTerminations = [(name: String, pid: pid_t)]()
    private var isPresentingAlert = false

    private override init() {
        super.init()
    }

    // Returns whether we are currently watching pid for termination.
    @objc(isMonitoringProcessID:)
    func isMonitoring(processID pid: pid_t) -> Bool {
        return sources[pid] != nil
    }

    // Begins watching pid. When it terminates, a modal alert naming the job and
    // pid is shown. Does nothing if pid is already being monitored.
    @objc(beginMonitoringProcessID:name:)
    func beginMonitoring(processID pid: pid_t, name: String?) {
        guard pid > 0, sources[pid] == nil else {
            return
        }
        let source = DispatchSource.makeProcessSource(identifier: pid,
                                                      eventMask: .exit,
                                                      queue: .main)
        sources[pid] = source
        names[pid] = name ?? "unknown name"
        source.setEventHandler { [weak self] in
            self?.processDidTerminate(pid)
        }
        source.resume()
        DLog("Began monitoring pid \(pid) (\(name ?? "")) for termination")
        postStateDidChange()
    }

    // Stops watching pid without showing an alert.
    @objc(stopMonitoringProcessID:)
    func stopMonitoring(processID pid: pid_t) {
        guard let source = sources[pid] else {
            return
        }
        source.cancel()
        sources.removeValue(forKey: pid)
        names.removeValue(forKey: pid)
        postStateDidChange()
    }

    private func postStateDidChange() {
        NotificationCenter.default.post(name: NSNotification.Name(Self.stateDidChangeNotificationName),
                                        object: self)
    }

    private func processDidTerminate(_ pid: pid_t) {
        let name = names[pid] ?? ""
        stopMonitoring(processID: pid)
        pendingTerminations.append((name: name, pid: pid))
        // Defer to the next runloop iteration so we never run a modal session from inside
        // the dispatch source event handler, and so several exits that happen at once
        // collapse into a single alert.
        DispatchQueue.main.async { [weak self] in
            self?.presentPendingTerminationsIfNeeded()
        }
    }

    private func presentPendingTerminationsIfNeeded() {
        guard !isPresentingAlert, !pendingTerminations.isEmpty else {
            return
        }
        isPresentingAlert = true
        let batch = pendingTerminations
        pendingTerminations.removeAll()
        showAlert(for: batch)
        isPresentingAlert = false
        // Anything that terminated while the alert was up gets a follow-up alert.
        if !pendingTerminations.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.presentPendingTerminationsIfNeeded()
            }
        }
    }

    private func showAlert(for terminations: [(name: String, pid: pid_t)]) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        if terminations.count == 1 {
            let termination = terminations[0]
            alert.messageText = "Job Terminated"
            alert.informativeText = sentence(for: termination)
        } else {
            alert.messageText = "Jobs Terminated"
            alert.informativeText = terminations.map { "• " + sentence(for: $0) }.joined(separator: "\n")
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func sentence(for termination: (name: String, pid: pid_t)) -> String {
        let displayName = termination.name.isEmpty ? "(unknown)" : termination.name
        return "The job \(displayName) with process ID \(termination.pid) has terminated."
    }
}

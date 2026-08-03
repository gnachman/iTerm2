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
    // pid is shown. Does nothing (returning true) if pid is already being
    // monitored. Returns false, after showing an explanatory alert, if pid cannot
    // be watched, e.g. it has already exited or belongs to another user.
    @discardableResult
    @objc(beginMonitoringProcessID:name:)
    func beginMonitoring(processID pid: pid_t, name: String?) -> Bool {
        guard pid > 0 else {
            return false
        }
        if sources[pid] != nil {
            return true
        }
        // kill(pid, 0) sends no signal but tells us whether the process still
        // exists. ESRCH means it is already gone, so the kqueue source we are about
        // to create would never fire; report that instead of failing silently.
        // EPERM means the process exists but belongs to another user (e.g. a root
        // job). EVFILT_PROC's NOTE_EXIT does not require signal permission, so those
        // notify fine and we proceed normally.
        if kill(pid, 0) != 0 && errno == ESRCH {
            showCannotMonitorAlert(pid: pid, name: name)
            return false
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
        RLog("Began monitoring pid \(pid) (\(name ?? "")) for termination")
        postStateDidChange()
        return true
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

    private func showCannotMonitorAlert(pid: pid_t, name: String?) {
        let displayName = (name?.isEmpty == false) ? name! : "(unknown)"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cannot Notify on Termination"
        alert.informativeText = "iTerm2 cannot watch the job \(displayName) with process ID \(pid) because it has already terminated."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

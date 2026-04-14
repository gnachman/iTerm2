//
//  GlobalJobMonitor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/6/26.
//

import Foundation

@objc(iTermGlobalJobMonitor)
class GlobalJobMonitor: NSObject {
    @objc static let didChangeNotification = NSNotification.Name("iTermGlobalJobMonitorDidChange")

    // Notification userInfo keys.
    @objc static let jobNameKey = "jobName"
    @objc static let sessionGUIDsKey = "sessionGUIDs"

    @objc static let instance = GlobalJobMonitor()

    // Maps job name (lowercased) → set of session GUIDs whose ancestor chain contains that job.
    private var guidsByJob = [String: Set<String>]()

    // Maps session GUID → ordered ancestor chain (deepest first) of lowercased job names.
    private var ancestorsByGUID = [String: [String]]()

    // Variable references kept alive for observation, keyed by session GUID.
    private var references = [String: iTermVariableReference<AnyObject>]()

    // Use foregroundJobAncestors because it contains argv[0] values for the foreground process
    // and all its ancestors up to the login shell. This ensures we detect jobs like "claude"
    // even when a child process (e.g. caffeinate) is the deepest foreground job.
    private let monitoredVariable = iTermVariableKeySessionForegroundJobAncestors

    private override init() {
        DLog("GlobalJobMonitor initializing")
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionCreated(_:)),
            name: .PTYSessionCreated,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRevived(_:)),
            name: .PTYSessionRevived,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWillTerminate(_:)),
            name: .iTermSessionWillTerminate,
            object: nil)

        // Pick up sessions that already exist.
        let existing = iTermController.sharedInstance().allSessions() ?? []
        DLog("GlobalJobMonitor picking up \(existing.count) existing sessions")
        for session in existing {
            startObserving(session)
        }
    }

    /// Returns the set of session GUIDs whose ancestor chain contains the given job name (case-insensitive).
    @objc func sessionGUIDs(runningJob jobName: String) -> Set<String> {
        let result = guidsByJob[jobName.lowercased()] ?? []
        DLog("GlobalJobMonitor sessionGUIDs(runningJob: \(jobName)) -> \(result.count) sessions: \(result)")
        return result
    }

    // MARK: - Notifications

    @objc private func sessionCreated(_ notification: Notification) {
        guard let session = notification.object as? PTYSession else { return }
        DLog("GlobalJobMonitor sessionCreated: \(session.guid ?? "(no guid)")")
        startObserving(session)
    }

    @objc private func sessionRevived(_ notification: Notification) {
        guard let session = notification.object as? PTYSession else { return }
        DLog("GlobalJobMonitor sessionRevived: \(session.guid ?? "(no guid)")")
        startObserving(session)
    }

    @objc private func sessionWillTerminate(_ notification: Notification) {
        guard let session = notification.object as? PTYSession,
              let guid = session.guid else { return }
        DLog("GlobalJobMonitor sessionWillTerminate: \(guid)")
        stopObserving(guid)
    }

    // MARK: - Observation

    private func startObserving(_ session: PTYSession) {
        guard let guid = session.guid else {
            DLog("GlobalJobMonitor startObserving: session has no guid, skipping")
            return
        }
        guard references[guid] == nil else {
            DLog("GlobalJobMonitor startObserving: already observing \(guid)")
            return
        }

        DLog("GlobalJobMonitor startObserving \(guid)")
        let ref = iTermVariableReference<AnyObject>(path: monitoredVariable,
                                                    vendor: session.genericScope)
        ref.onChangeBlock = { [weak self, weak session] in
            guard let self, let session, let guid = session.guid else { return }
            let value = session.genericScope.value(forVariableName: self.monitoredVariable) as? String
            DLog("GlobalJobMonitor variable changed for \(guid): \(value ?? "(nil)")")
            self.ancestorsChanged(for: guid, newValue: value)
        }
        references[guid] = ref

        // Seed with current value.
        let currentValue = session.genericScope.value(forVariableName: monitoredVariable) as? String
        DLog("GlobalJobMonitor seeding \(guid) with: \(currentValue ?? "(nil)")")
        ancestorsChanged(for: guid, newValue: currentValue)
    }

    private func stopObserving(_ guid: String) {
        if let ref = references.removeValue(forKey: guid) {
            ref.invalidate()
        }
        guard let oldAncestors = ancestorsByGUID.removeValue(forKey: guid) else {
            DLog("GlobalJobMonitor stopObserving \(guid): no ancestors tracked")
            return
        }
        DLog("GlobalJobMonitor stopObserving \(guid): removing ancestors \(oldAncestors)")
        let oldJobs = Set(oldAncestors)
        for job in oldJobs {
            removeGUID(guid, fromJob: job)
        }
        for job in oldJobs {
            postNotification(jobName: job)
        }
    }

    /// Parse the newline-separated ancestor chain variable into an ordered array.
    private func parseAncestors(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: "\n").map { String($0) }
    }

    private func ancestorsChanged(for guid: String, newValue: String?) {
        let newAncestors = parseAncestors(newValue)
        let oldAncestors = ancestorsByGUID[guid] ?? []

        guard newAncestors != oldAncestors else {
            DLog("GlobalJobMonitor ancestorsChanged for \(guid): unchanged (\(oldAncestors))")
            return
        }

        let oldJobs = Set(oldAncestors)
        let newJobs = Set(newAncestors)
        let removed = oldJobs.subtracting(newJobs)
        let added = newJobs.subtracting(oldJobs)

        DLog("GlobalJobMonitor ancestorsChanged for \(guid): \(oldAncestors) -> \(newAncestors) (added=\(added), removed=\(removed))")

        for job in removed {
            removeGUID(guid, fromJob: job)
        }

        if newAncestors.isEmpty {
            ancestorsByGUID.removeValue(forKey: guid)
        } else {
            ancestorsByGUID[guid] = newAncestors
            for job in added {
                guidsByJob[job, default: []].insert(guid)
            }
        }

        // Post notifications for all affected job names.
        for job in removed.union(added) {
            postNotification(jobName: job)
        }
    }

    private func removeGUID(_ guid: String, fromJob jobKey: String) {
        guidsByJob[jobKey]?.remove(guid)
        if guidsByJob[jobKey]?.isEmpty == true {
            guidsByJob.removeValue(forKey: jobKey)
            DLog("GlobalJobMonitor: no more sessions running \(jobKey)")
        }
    }

    private func postNotification(jobName: String) {
        let guids = guidsByJob[jobName] ?? []
        DLog("GlobalJobMonitor posting notification for \(jobName): \(guids.count) session(s)")
        NotificationCenter.default.post(
            name: GlobalJobMonitor.didChangeNotification,
            object: self,
            userInfo: [
                GlobalJobMonitor.jobNameKey: jobName,
                GlobalJobMonitor.sessionGUIDsKey: guids
            ])
    }
}

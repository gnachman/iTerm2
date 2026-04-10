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

    // Maps job name (lowercased) → set of session GUIDs running that job.
    private var guidsByJob = [String: Set<String>]()

    // Maps session GUID → lowercased job name.
    private var jobByGUID = [String: String]()

    // Variable references kept alive for observation, keyed by session GUID.
    private var references = [String: iTermVariableReference<AnyObject>]()

    // Use processTitle because it gives argv[0] while jobName gives the name of the on-disk
    // binary, which could be different (e.g., if the command is a symlink to a differently named
    // binary, which is the case for claude as I write it).
    private let monitoredVariable = iTermVariableKeySessionProcessTitle

    private override init() {
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
        for session in iTermController.sharedInstance().allSessions() {
            startObserving(session)
        }
    }

    /// Returns the set of session GUIDs currently running the given job name (case-insensitive).
    @objc func sessionGUIDs(runningJob jobName: String) -> Set<String> {
        return guidsByJob[jobName.lowercased()] ?? []
    }

    // MARK: - Notifications

    @objc private func sessionCreated(_ notification: Notification) {
        guard let session = notification.object as? PTYSession else { return }
        startObserving(session)
    }

    @objc private func sessionRevived(_ notification: Notification) {
        guard let session = notification.object as? PTYSession else { return }
        startObserving(session)
    }

    @objc private func sessionWillTerminate(_ notification: Notification) {
        guard let session = notification.object as? PTYSession,
              let guid = session.guid else { return }
        stopObserving(guid)
    }

    // MARK: - Observation

    private func startObserving(_ session: PTYSession) {
        guard let guid = session.guid else { return }
        guard references[guid] == nil else { return }

        let ref = iTermVariableReference<AnyObject>(path: monitoredVariable,
                                                    vendor: session.genericScope)
        ref.onChangeBlock = { [weak self, weak session] in
            guard let self, let session, let guid = session.guid else { return }
            self.jobChanged(for: guid,
                            newJob: session.genericScope.value(forVariableName: monitoredVariable) as? String)
        }
        references[guid] = ref

        // Seed with current value.
        let currentJob = session.genericScope.value(forVariableName: monitoredVariable) as? String
        jobChanged(for: guid, newJob: currentJob)
    }

    private func stopObserving(_ guid: String) {
        if let ref = references.removeValue(forKey: guid) {
            ref.invalidate()
        }
        if let oldKey = jobByGUID.removeValue(forKey: guid) {
            removeGUID(guid, fromJob: oldKey)
            postNotification(jobName: oldKey)
        }
    }

    private func jobChanged(for guid: String, newJob: String?) {
        let newKey = newJob.flatMap({ $0.isEmpty ? nil : $0.lowercased() })
        let oldKey = jobByGUID[guid]

        guard newKey != oldKey else { return }

        if let oldKey {
            removeGUID(guid, fromJob: oldKey)
        }

        if let newKey {
            jobByGUID[guid] = newKey
            guidsByJob[newKey, default: []].insert(guid)
            postNotification(jobName: newKey)
        } else {
            jobByGUID.removeValue(forKey: guid)
        }

        if let oldKey, oldKey != newKey {
            postNotification(jobName: oldKey)
        }
    }

    private func removeGUID(_ guid: String, fromJob jobKey: String) {
        guidsByJob[jobKey]?.remove(guid)
        if guidsByJob[jobKey]?.isEmpty == true {
            guidsByJob.removeValue(forKey: jobKey)
        }
    }

    private func postNotification(jobName: String) {
        let guids = guidsByJob[jobName] ?? []
        NotificationCenter.default.post(
            name: GlobalJobMonitor.didChangeNotification,
            object: self,
            userInfo: [
                GlobalJobMonitor.jobNameKey: jobName,
                GlobalJobMonitor.sessionGUIDsKey: guids
            ])
    }
}

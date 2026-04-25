//
//  iTermWorkgroupController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Public API for entering and exiting workgroups on sessions. Owns no
// trigger logic — callers (trigger sources like ClaudeCodeModeController,
// menu actions, API calls) invoke these methods directly.
@objc(iTermWorkgroupController)
final class iTermWorkgroupController: NSObject {
    @objc static let instance = iTermWorkgroupController()

    // Sessions currently running a workgroup, keyed by session GUID.
    // Holds strong references to the instances; sessions keep a weak
    // reference back.
    private var instancesBySessionGUID: [String: iTermWorkgroupInstance] = [:]

    private override init() {
        super.init()
    }

    // Enter the workgroup identified by `workgroupUniqueIdentifier` on
    // `session`. Idempotent: entering the same workgroup twice is a
    // no-op; entering a different one while one is already running
    // exits the old one first.
    @objc
    @discardableResult
    func enter(workgroupUniqueIdentifier identifier: String,
               on session: PTYSession) -> Bool {
        guard let sessionGUID = session.guid else { return false }

        // Already running the same one? Nothing to do.
        if let existing = instancesBySessionGUID[sessionGUID],
           existing.workgroupUniqueIdentifier == identifier {
            return true
        }
        // Running a different one — exit first.
        if instancesBySessionGUID[sessionGUID] != nil {
            exit(on: session)
        }

        guard let workgroup = resolveWorkgroup(uniqueIdentifier: identifier) else {
            DLog("iTermWorkgroupController: no workgroup with id \(identifier)")
            return false
        }
        guard let instance = iTermWorkgroupInstance.enter(workgroup: workgroup,
                                                          on: session) else {
            DLog("iTermWorkgroupController: failed to build instance for \(identifier)")
            return false
        }
        instancesBySessionGUID[sessionGUID] = instance
        session.delegate?.sessionDidChangeDesiredToolbarItems(session)
        return true
    }

    @objc
    func exit(on session: PTYSession) {
        guard let sessionGUID = session.guid,
              let instance = instancesBySessionGUID.removeValue(
                forKey: sessionGUID) else { return }
        instance.teardown()
        session.delegate?.sessionDidChangeDesiredToolbarItems(session)
    }

    @objc
    func workgroupInstance(on session: PTYSession) -> iTermWorkgroupInstance? {
        guard let sessionGUID = session.guid else { return nil }
        return instancesBySessionGUID[sessionGUID]
    }

    // MARK: - Private

    // Looks up the workgroup config by identifier. Checks built-ins
    // first (so e.g. the Claude Code workgroup is always available
    // regardless of user settings), then the user's configured
    // workgroups in the model.
    private func resolveWorkgroup(uniqueIdentifier: String) -> iTermWorkgroup? {
        if let builtin =
                BuiltinWorkgroups.all.first(where: {
                    $0.uniqueIdentifier == uniqueIdentifier
                }) {
            return builtin
        }
        return iTermWorkgroupModel.instance.workgroup(uniqueIdentifier: uniqueIdentifier)
    }
}

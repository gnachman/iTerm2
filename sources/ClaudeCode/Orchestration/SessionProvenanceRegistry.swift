//
//  SessionProvenanceRegistry.swift
//  iTerm2SharedARC
//

import Foundation

// Remembers how a session came to exist when the answer is not simply
// "the user made it". Today the only writer is the orchestrator's
// start_session path, which records "Created by agent in chat X" so
// that other chats seeing the session in a <workgroups> snapshot can
// tell that a different agent conjured it. Without this, a second
// window spun up by another chat is indistinguishable from something
// the user set up deliberately, and agents stop to ask about it.
//
// In-memory only: provenance describes a live session's origin, and a
// restart both empties this registry and tears down the sessions it
// described. Entries are dropped when their session terminates so the
// map cannot grow past the set of live spawned sessions.
@MainActor
final class SessionProvenanceRegistry {
    static let instance = SessionProvenanceRegistry()

    private var provenanceByGUID: [String: String] = [:]
    private var sessionWillTerminateObserver: NSObjectProtocol?

    private init() {
        sessionWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.iTermSessionWillTerminate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let session = notification.object as? PTYSession else { return }
                self?.provenanceByGUID.removeValue(forKey: session.guid)
            }
        }
    }

    func set(_ provenance: String, forSessionGUID guid: String) {
        provenanceByGUID[guid] = provenance
    }

    func provenance(forSessionGUID guid: String) -> String? {
        return provenanceByGUID[guid]
    }
}

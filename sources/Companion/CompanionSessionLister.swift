//
//  CompanionSessionLister.swift
//  iTerm2
//
//  Enumerates terminal sessions for the companion's Create screen, projecting
//  each PTYSession down to the wire-level CompanionSessionSummary (guid +
//  display text). Must run on the main thread, like all iTermController access.
//

import Foundation
import CompanionProtocol

@MainActor
enum CompanionSessionLister {
    static func sessions() -> [CompanionSessionSummary] {
        guard let controller = iTermController.sharedInstance() else {
            return []
        }
        return controller.allSessions().map { session in
            CompanionSessionSummary(guid: session.guid,
                                    name: session.name,
                                    subtitle: session.subtitle ?? "")
        }
    }
}

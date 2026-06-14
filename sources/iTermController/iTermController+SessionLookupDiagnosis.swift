//
//  iTermController+SessionLookupDiagnosis.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/10/26.
//

import Foundation

extension iTermController {
    // Explains why a session GUID can't be resolved by
    // anySession(withGUID:) by dumping every session that lookup
    // searches, labeled with where it was found. Built on the same
    // enumerateSessionLookupLocations walk the lookup itself uses, so
    // the dump cannot drift from the real search path.
    @objc(diagnosisForUnresolvableSessionGUID:)
    func diagnosis(unresolvableGUID guid: String) -> String {
        // Build a session -> window map once. Looking each session's
        // window up via terminal(with:) inside the per-session loop
        // would be O(sessions^2) (that method linearly scans every
        // window's sessions), all on the main thread.
        var windowGUIDsBySession = [ObjectIdentifier: String]()
        for terminal in terminals() {
            guard let windowGUID = terminal.terminalGuid else { continue }
            for session in terminal.allSessions() {
                windowGUIDsBySession[ObjectIdentifier(session)] = windowGUID
            }
        }
        var lines = ["Diagnosis for unresolvable session \(guid):"]
        enumerateSessionLookupLocations { session, location, _ in
            // The header is unaudited for nullability, so the block
            // parameter imports as optional; the enumerator never
            // yields nil.
            guard let session else { return }
            let windowGUID = windowGUIDsBySession[ObjectIdentifier(session)]
            lines.append("  \(location.diagnosisLabel): \(Self.sessionInfo(session, windowGUID: windowGUID))")
        }
        return lines.joined(separator: "\n")
    }

    private static func sessionInfo(_ session: PTYSession, windowGUID: String?) -> String {
        var info = "\(session.guid) exited=\(session.exited)"
        if let windowGUID {
            info += " window=\(windowGUID)"
        }
        if let port = session.peerPort {
            info += " port=\(port.debugDescription)"
        } else {
            info += " port=nil"
        }
        return info
    }
}

private extension iTermSessionLookupLocation {
    var diagnosisLabel: String {
        switch self {
        case .tab: return "in tab"
        case .buried: return "buried"
        case .tabPeerPort: return "in-tab port peer"
        case .buriedPeerPort: return "buried port peer"
        case .workgroupRegistryPort: return "registry port peer"
        @unknown default: return "unknown location"
        }
    }
}

//
//  iTermWorkgroup.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import Foundation

// Top-level workgroup definition. How a workgroup is *entered* (triggers on
// profiles, menu item, API call, …) is not part of this type — those entry
// points reference the workgroup by uniqueIdentifier.
//
// Invariant: sessions contains exactly one element whose kind == .root and
// parentID == nil. All other sessions have a parentID matching some other
// session's uniqueIdentifier.
struct iTermWorkgroup: Codable, Equatable {
    let uniqueIdentifier: String
    var name: String
    var sessions: [iTermWorkgroupSession]

    var root: iTermWorkgroupSession? {
        return sessions.first(where: { $0.parentID == nil })
    }

    // Convenience: build an empty workgroup with just a root session.
    static func newEmpty(name: String) -> iTermWorkgroup {
        let root = iTermWorkgroupSession(
            uniqueIdentifier: UUID().uuidString,
            parentID: nil,
            kind: .root,
            profileGUID: nil,
            command: "",
            urlString: "",
            toolbarItems: [],
            displayName: "Main")
        return iTermWorkgroup(uniqueIdentifier: UUID().uuidString,
                              name: name,
                              sessions: [root])
    }

    func children(of parentID: String) -> [iTermWorkgroupSession] {
        return sessions.filter { $0.parentID == parentID }
    }

    func session(withUniqueIdentifier id: String) -> iTermWorkgroupSession? {
        return sessions.first(where: { $0.uniqueIdentifier == id })
    }
}

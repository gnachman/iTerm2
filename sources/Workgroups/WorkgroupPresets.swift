//
//  WorkgroupPresets.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import Foundation

// Built-in workgroup templates offered from the "Add Preset" menu in the
// workgroups editor. A preset is just a recipe that constructs a fresh
// iTermWorkgroup value; the resulting workgroup is then owned and edited
// the same way as a user-built one.
struct WorkgroupPreset {
    let identifier: String
    let displayName: String
    let build: () -> iTermWorkgroup
}

enum WorkgroupPresets {
    static let all: [WorkgroupPreset] = [
        WorkgroupPreset(
            identifier: "codingAgentPlusDiff",
            displayName: "Coding Agent + Diff",
            build: buildCodingAgentPlusDiff)
    ]

    private static func buildCodingAgentPlusDiff() -> iTermWorkgroup {
        let rootID = UUID().uuidString
        let diffID = UUID().uuidString
        // Template uses \(workgroup.selectedFile), which the runtime
        // substitutes when a file is picked from the changed-file
        // selector. Double backslash keeps the `\(` literal in the
        // stored Swift string.
        let diffCommand = "git diff \\(workgroup.selectedFile) HEAD"

        let root = iTermWorkgroupSessionConfig(
            uniqueIdentifier: rootID,
            parentID: nil,
            kind: .root,
            profileGUID: nil,
            command: "",
            urlString: "",
            toolbarItems: [.modeSwitcher, .gitStatus],
            displayName: "")

        let diff = iTermWorkgroupSessionConfig(
            uniqueIdentifier: diffID,
            parentID: rootID,
            kind: .peer,
            profileGUID: nil,
            command: diffCommand,
            urlString: "",
            toolbarItems: [.modeSwitcher,
                           .changedFileSelector,
                           .navigation],
            displayName: "Diff")

        return iTermWorkgroup(
            uniqueIdentifier: UUID().uuidString,
            name: "Coding Agent + Diff",
            sessions: [root, diff])
    }
}

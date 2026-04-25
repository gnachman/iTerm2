//
//  BuiltinWorkgroups.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Workgroups that iTerm ships with — resolvable by
// iTermWorkgroupController without the user having configured them in
// Settings. Stable unique identifiers so trigger sources (menu items,
// API callers, or the Claude Code job monitor) can reference them.
enum BuiltinWorkgroups {
    // Unique identifiers for the built-in workgroups. These must stay
    // stable: triggers and saved state encode them as plain strings.
    enum ID {
        static let claudeCode = "builtin.claudeCode"
        // Stable sub-session IDs inside the built-in Claude Code
        // workgroup, so runtime peer activation can reference them
        // without having to look up sessions by kind.
        static let claudeCodeMain = "builtin.claudeCode.main"
        static let claudeCodeDiff = "builtin.claudeCode.diff"
        static let claudeCodeReview = "builtin.claudeCode.review"
    }

    static let all: [iTermWorkgroup] = [claudeCode]

    // Mirrors the behavior of the old hardcoded Claude Code mode:
    // Main session with mode switcher + git status, Diff peer running
    // `git diff` with mode switcher + changed-file selector + nav
    // buttons, Code Review peer running `claude -p '...'` with mode
    // switcher + reload.
    static let claudeCode: iTermWorkgroup = {
        let main = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ID.claudeCodeMain,
            parentID: nil,
            kind: .root,
            profileGUID: nil,
            command: "",
            urlString: "",
            toolbarItems: [
                .spacer(minWidth: 4, maxWidth: 4),
                .modeSwitcher,
                .gitStatus,
                .spacer(minWidth: 4, maxWidth: 4),
            ],
            displayName: "Claude Code")

        let diff = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ID.claudeCodeDiff,
            parentID: ID.claudeCodeMain,
            kind: .peer,
            profileGUID: nil,
            command: "git difftool -y -x vimdiff HEAD",
            urlString: "",
            toolbarItems: [
                .spacer(minWidth: 4, maxWidth: 4),
                .modeSwitcher,
                .changedFileSelector,
                .reload,
                .spacer(minWidth: 4, maxWidth: 4),
            ],
            displayName: "Diff",
            perFileCommand: "git difftool -y -x vimdiff HEAD -- \\(file)")

        let review = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ID.claudeCodeReview,
            parentID: ID.claudeCodeMain,
            kind: .peer,
            profileGUID: nil,
            command: "claude -p 'Review the pending change in this git repository for correctness and completeness.'",
            urlString: "",
            toolbarItems: [
                .spacer(minWidth: 4, maxWidth: 4),
                .modeSwitcher,
                .reload,
                .spacer(minWidth: 4, maxWidth: 4),
            ],
            displayName: "Code Review")

        return iTermWorkgroup(uniqueIdentifier: ID.claudeCode,
                              name: "Claude Code",
                              sessions: [main, diff, review])
    }()
}

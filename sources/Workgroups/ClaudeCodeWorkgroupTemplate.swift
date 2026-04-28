//
//  ClaudeCodeWorkgroupTemplate.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Factory for the Claude Code workgroup the onboarding installer installs
// into the user's iTermWorkgroupModel. After install it's just regular
// user data — editable in Settings, removable on uninstall — but the
// identifier strings stay stable so an Enter Workgroup trigger pointing
// at this ID keeps resolving across upgrades.
enum ClaudeCodeWorkgroupTemplate {
    // The strings start with "builtin." for backward compatibility:
    // pre-cleanup, this workgroup was a hardcoded built-in keyed off
    // these literals. Users who already had triggers or saved state
    // pointing at "builtin.claudeCode" must keep working.
    enum ID {
        static let workgroup = "builtin.claudeCode"
        static let main = "builtin.claudeCode.main"
        static let diff = "builtin.claudeCode.diff"
        static let review = "builtin.claudeCode.review"
    }

    // Mirrors the behavior of the old hardcoded Claude Code mode:
    // Main session with mode switcher + git status, Diff peer running
    // `git diff` with mode switcher + changed-file selector + nav
    // buttons, Code Review peer running `claude -p '...'` with mode
    // switcher + reload.
    static let config: iTermWorkgroup = {
        let main = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ID.main,
            parentID: nil,
            kind: .root,
            profileGUID: nil,
            command: "",
            urlString: "",
            toolbarItems: [
                .modeSwitcher,
                .gitStatus,
            ],
            displayName: "Claude Code")

        let diff = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ID.diff,
            parentID: ID.main,
            kind: .peer,
            profileGUID: nil,
            command: "git difftool -y -x vimdiff HEAD",
            urlString: "",
            toolbarItems: [
                .modeSwitcher,
                .changedFileSelector,
                .navigation,
            ],
            displayName: "Diff",
            perFileCommand: "git difftool -y -x vimdiff HEAD -- \\(file)")

        let systemPromptFile = Bundle.main.path(forResource: "code-review-system-prompt", ofType: "txt")! as NSString
        let escapedSystemPromptFile = systemPromptFile.withEscapedShellCharacters(includingNewlines: true)
        let settings = #"'{"autoMode":{"allow":["$defaults","Running `it2 session add-clipping` is allowed: it pipes content to the local iTerm2 session per the user’s request."]}}'"#

        let review = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ID.review,
            parentID: ID.main,
            kind: .peer,
            profileGUID: nil,
            command: "claude \\(codeReviewPrompt) --append-system-prompt-file \(escapedSystemPromptFile) --settings \(settings)",
            urlString: "",
            toolbarItems: [
                .modeSwitcher,
                .reload,
            ],
            displayName: "Code Review",
            mode: .codeReview)

        return iTermWorkgroup(uniqueIdentifier: ID.workgroup,
                              name: "Claude Code",
                              sessions: [main, diff, review])
    }()
}

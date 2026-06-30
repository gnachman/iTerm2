//
//  iTermWorkgroupModel.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import Foundation

// Single source of truth for the user's configured workgroups. Loads from
// iTermUserDefaults on first access; writes synchronously on every
// mutation (payload is small, and we want round-trip semantics to be
// obvious in tests / when the user quits the app mid-edit).
//
// Observers listen for didChangeNotification rather than KVO so we don't
// have to model mutations as a single @Published property — the settings
// UI is happy to re-read the array on every change.
@objc(iTermWorkgroupModel)
final class iTermWorkgroupModel: NSObject {
    @objc static let instance = iTermWorkgroupModel()
    @objc static let didChangeNotification =
        Notification.Name("iTermWorkgroupModelDidChange")

    private(set) var workgroups: [iTermWorkgroup]

    private override init() {
        self.workgroups = Self.load()
        super.init()
        backfillToolbarShortcutsIfNeeded()
        backfillClaudeCodeDiffModeIfNeeded()
        backfillCodeReviewSystemPromptCommandIfNeeded()
    }

    // MARK: - Top-level mutations

    func add(_ workgroup: iTermWorkgroup) {
        workgroups.append(workgroup)
        didChange()
    }

    func remove(uniqueIdentifier: String) {
        guard let idx = workgroups.firstIndex(where: {
            $0.uniqueIdentifier == uniqueIdentifier
        }) else { return }
        workgroups.remove(at: idx)
        didChange()
    }

    func replace(uniqueIdentifier: String, with workgroup: iTermWorkgroup) {
        guard let idx = workgroups.firstIndex(where: {
            $0.uniqueIdentifier == uniqueIdentifier
        }) else { return }
        workgroups[idx] = workgroup
        didChange()
    }

    // Replace the whole list (used for undo).
    func setAll(_ newList: [iTermWorkgroup]) {
        workgroups = newList
        didChange()
    }

    func workgroup(uniqueIdentifier: String) -> iTermWorkgroup? {
        return workgroups.first(where: { $0.uniqueIdentifier == uniqueIdentifier })
    }

    // MARK: - Persistence

    private static func load() -> [iTermWorkgroup] {
        guard let data = iTermUserDefaults.workgroupsData else {
            return []
        }
        do {
            return try JSONDecoder().decode([iTermWorkgroup].self, from: data)
        } catch {
            RLog("Failed to decode workgroups: \(error)")
            return []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(workgroups)
            iTermUserDefaults.workgroupsData = data
        } catch {
            RLog("Failed to encode workgroups: \(error)")
        }
    }

    private func didChange() {
        persist()
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self)
    }

    // One-time migration: flip the Claude Code workgroup's Diff peer
    // from .regular to .diff. The peer's command starts difftool, which
    // does nothing useful against a clean tree; before .diff mode
    // existed the peer ran immediately on workgroup entry, popping
    // open vimdiff on no files. Users who installed the integration
    // before .diff existed already have mode=.regular persisted; this
    // migration brings them in line with the template default without
    // forcing a full reinstall.
    //
    // Latched in NoSync user defaults so a user who has *intentionally*
    // switched the peer back to .regular doesn't get it flipped a
    // second time on the next launch. Same precedent and rationale as
    // backfillToolbarShortcutsIfNeeded below.
    private func backfillClaudeCodeDiffModeIfNeeded() {
        guard !iTermUserDefaults.claudeCodeDiffModeBackfilled else { return }
        defer { iTermUserDefaults.claudeCodeDiffModeBackfilled = true }

        var changed = false
        for wgIdx in workgroups.indices
        where workgroups[wgIdx].uniqueIdentifier
                == ClaudeCodeWorkgroupTemplate.ID.workgroup {
            for sIdx in workgroups[wgIdx].sessions.indices
            where workgroups[wgIdx].sessions[sIdx].uniqueIdentifier
                    == ClaudeCodeWorkgroupTemplate.ID.diff
                && workgroups[wgIdx].sessions[sIdx].mode == .regular {
                workgroups[wgIdx].sessions[sIdx].mode = .diff
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    // One-time migration: rewrite any persisted Code Review command so
    // its system prompt comes from the user-editable temp file (the
    // `codeReviewSystemPromptFile` variable) instead of a fixed path to
    // the bundled code-review-system-prompt.txt. Installs predating the
    // editable system prompt carry the old `--append-system-prompt-file`
    // argument in one of two forms: the templated
    // `'\(iterm2.appBundlePath)/Contents/Resources/code-review-system-prompt.txt'`,
    // or an already-resolved absolute path to the same file (older
    // builds persisted the resolved path, unquoted). Both end in
    // code-review-system-prompt.txt, so a regex over that argument
    // handles either without disturbing the rest of the command (e.g. a
    // custom --settings value). Sessions whose argument no longer points
    // at the bundled file are left alone.
    //
    // Not scoped to the Claude Code workgroup ID: a user who built the
    // "Coding Agent + Diff + Code Review" preset by hand has the same
    // argument under a different workgroup ID and should migrate too.
    //
    // Latched in NoSync user defaults for the same reason as
    // backfillClaudeCodeDiffModeIfNeeded above.
    private func backfillCodeReviewSystemPromptCommandIfNeeded() {
        guard !iTermUserDefaults.claudeCodeReviewSystemPromptCommandBackfilled else { return }
        defer { iTermUserDefaults.claudeCodeReviewSystemPromptCommandBackfilled = true }

        // Matches `--append-system-prompt-file` plus its single
        // argument when that argument (quoted or not) ends in
        // code-review-system-prompt.txt. `[^']*` can't cross a quote, so
        // it stops at the closing quote in the quoted form and spans the
        // unquoted absolute path otherwise; the literal filename anchor
        // keeps it from overrunning into a later quoted argument.
        let pattern =
            "--append-system-prompt-file\\s+'?[^']*code-review-system-prompt\\.txt'?"
        let newFragment =
            "--append-system-prompt-file '\\(codeReviewSystemPromptFile)'"

        var changed = false
        for wgIdx in workgroups.indices {
            for sIdx in workgroups[wgIdx].sessions.indices {
                let command = workgroups[wgIdx].sessions[sIdx].command
                guard let range = command.range(of: pattern,
                                                options: .regularExpression) else {
                    continue
                }
                // Plain (non-template) replacement so the backslash in
                // `\(codeReviewSystemPromptFile)` survives verbatim.
                workgroups[wgIdx].sessions[sIdx].command =
                    command.replacingCharacters(in: range, with: newFragment)
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    // One-time migration: stamp the default keyboard shortcuts onto
    // .navigation and .reload toolbar items that pre-date this
    // feature. Runs once per user (latched in NoSync user defaults)
    // so a subsequent intentional clear by the user doesn't get
    // re-seeded on the next launch. Only items whose shortcuts are
    // entirely empty are touched: if any of the three navigation
    // sub-shortcuts is set, that item is left as-is on the
    // assumption it has already been updated.
    private func backfillToolbarShortcutsIfNeeded() {
        guard !iTermUserDefaults.workgroupShortcutsBackfilled else { return }
        defer { iTermUserDefaults.workgroupShortcutsBackfilled = true }

        var changed = false
        for wgIdx in workgroups.indices {
            for sIdx in workgroups[wgIdx].sessions.indices {
                let original = workgroups[wgIdx].sessions[sIdx].toolbarItems
                var items = original
                for itemIdx in items.indices {
                    switch items[itemIdx] {
                    case .navigation(let s)
                        where s.back == nil && s.forward == nil
                            && s.reload == nil:
                        items[itemIdx] = .navigation(.defaults)
                    case .reload(nil):
                        items[itemIdx] = .reload(.reloadDefault)
                    default:
                        break
                    }
                }
                if items != original {
                    workgroups[wgIdx].sessions[sIdx].toolbarItems = items
                    changed = true
                }
            }
        }
        if changed {
            persist()
        }
    }
}

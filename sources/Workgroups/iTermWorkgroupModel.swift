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
            DLog("Failed to decode workgroups: \(error)")
            return []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(workgroups)
            iTermUserDefaults.workgroupsData = data
        } catch {
            DLog("Failed to encode workgroups: \(error)")
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

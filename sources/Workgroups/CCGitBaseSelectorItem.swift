//
//  CCGitBaseSelectorItem.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/1/26.
//

import AppKit

@objc(iTermCCGitBaseSelectorItemDelegate)
protocol CCGitBaseSelectorItemDelegate: AnyObject {
    func gitBaseDidChange(base: String, sender: CCGitBaseSelectorItem)
}

// Combo-box toolbar item for picking the git base ref that the
// changedFileSelector's diff command runs against. Defaults to HEAD;
// the dropdown is seeded from a recents list so previously-typed bases
// (branches, tags, SHAs) reappear across launches. See
// WorkgroupRecentsComboBoxItem for the commit semantics.
@objc(iTermCCGitBaseSelectorItem)
class CCGitBaseSelectorItem: WorkgroupRecentsComboBoxItem {
    @objc weak var gitBaseSelectorDelegate: CCGitBaseSelectorItemDelegate?
    // Set by the workgroup builder so the delegate can demux which
    // peer's selector fired.
    @objc var ownerPeerID: String?

    @objc static let defaultBase = "HEAD"

    // Recents are intentionally global rather than per-workgroup —
    // bases like main / develop / origin/HEAD recur across every
    // workgroup the user opens, and forcing them to retype per
    // workgroup would be friction without benefit.
    private static let configuration = WorkgroupRecentsComboBoxItem.Configuration(
        defaultValue: defaultBase,
        recentsKey: "NoSyncWorkgroupGitBaseRecents")

    @objc var currentBase: String {
        return currentValue
    }

    @objc
    init(identifier: String, priority: Int) {
        super.init(identifier: identifier,
                   priority: priority,
                   configuration: Self.configuration)
    }

    // Adopt a new base value pushed by the workgroup instance — used
    // when another selector commits and we need to mirror its choice
    // without firing our own delegate.
    @objc
    func displayBase(_ base: String) {
        display(base)
    }

    override func valueDidCommit(_ value: String) {
        gitBaseSelectorDelegate?.gitBaseDidChange(base: value, sender: self)
    }
}

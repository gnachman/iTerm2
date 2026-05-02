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
// the dropdown is seeded from a recents list persisted in
// iTermUserDefaults so previously-typed bases (branches, tags, SHAs)
// reappear across launches. Only fires its delegate on a real commit
// (Return or dropdown pick), not on every keystroke — otherwise a
// user typing "feature/foo" would kick off a restart per character.
@objc(iTermCCGitBaseSelectorItem)
class CCGitBaseSelectorItem: SessionToolbarControl {
    @objc weak var gitBaseSelectorDelegate: CCGitBaseSelectorItemDelegate?
    // Set by the workgroup builder so the delegate can demux which
    // peer's selector fired.
    @objc var ownerPeerID: String?

    private let comboBox: NSComboBox

    @objc static let defaultBase = "HEAD"
    private static let recentsKey = "WorkgroupGitBaseRecents"
    private static let maxRecents = 16

    @objc var currentBase: String {
        let trimmed = comboBox.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultBase : trimmed
    }

    @objc
    init(identifier: String, priority: Int) {
        comboBox = NSComboBox()
        comboBox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.isEditable = true
        super.init(identifier: identifier,
                   priority: priority,
                   control: comboBox)
        reloadDropdownItems()
        comboBox.stringValue = Self.defaultBase
        comboBox.target = self
        comboBox.action = #selector(commit(_:))
        comboBox.delegate = self
    }

    private func reloadDropdownItems() {
        let recents = Self.loadRecents()
        comboBox.removeAllItems()
        comboBox.addItem(withObjectValue: Self.defaultBase)
        for entry in recents where entry != Self.defaultBase {
            comboBox.addItem(withObjectValue: entry)
        }
    }

    @objc
    private func commit(_ sender: Any?) {
        let base = currentBase
        // Reflect the canonicalized value (trim/HEAD-fallback) back
        // into the field so what the user sees matches what we'll
        // substitute downstream.
        if comboBox.stringValue != base {
            comboBox.stringValue = base
        }
        Self.recordRecent(base)
        reloadDropdownItems()
        // Reselect so the dropdown's highlight matches the field.
        if let idx = comboBox.objectValues.firstIndex(where: {
            ($0 as? String) == base
        }) {
            comboBox.selectItem(at: idx)
        }
        gitBaseSelectorDelegate?.gitBaseDidChange(base: base, sender: self)
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        // Min width keeps the combo box wide enough to show "HEAD"
        // plus the dropdown chevron without truncation.
        let natural = max(comboBox.fittingSize.width, 100)
        return 80...natural
    }

    private static func loadRecents() -> [String] {
        let defaults = iTermUserDefaults.userDefaults()
        return (defaults.object(forKey: recentsKey) as? [String]) ?? []
    }

    private static func recordRecent(_ value: String) {
        guard !value.isEmpty else { return }
        var recents = loadRecents()
        recents.removeAll { $0 == value }
        recents.insert(value, at: 0)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        iTermUserDefaults.userDefaults().set(recents,
                                             forKey: recentsKey)
    }
}

extension CCGitBaseSelectorItem: NSComboBoxDelegate {
    // Picking from the dropdown commits immediately.
    func comboBoxSelectionDidChange(_ notification: Notification) {
        // The selectedItem index hasn't been reflected into
        // stringValue yet at this notification, so read it directly.
        guard let value = comboBox.objectValueOfSelectedItem as? String else {
            return
        }
        comboBox.stringValue = value
        commit(comboBox)
    }

    // Return / Tab / focus loss on the editable field commits.
    func controlTextDidEndEditing(_ obj: Notification) {
        commit(comboBox)
    }
}

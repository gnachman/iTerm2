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
    // Recents are intentionally global rather than per-workgroup —
    // bases like main / develop / origin/HEAD recur across every
    // workgroup the user opens, and forcing them to retype per
    // workgroup would be friction without benefit.
    private static let recentsKey = "NoSyncWorkgroupGitBaseRecents"
    private static let maxRecents = 16
    // Sanity cap on a single recents entry. Git ref names are
    // short by convention (a SHA is 40 chars); anything longer is
    // almost certainly an accidental paste, and unbounded entries
    // would let one paste bloat the user's defaults plist.
    private static let maxRecentLength = 200

    // Last value committed. Initialized to defaultBase ("HEAD") in
    // init so a fresh user pressing Return on the seeded value
    // doesn't fire a no-op delegate callback, and updated on every
    // committed value thereafter. This is the load-bearing guard
    // against duplicate fires when both `controlTextDidEndEditing`
    // and `comboBoxSelectionDidChange` arrive for the same user
    // action — neither path bypasses the equality check.
    private var lastCommittedBase = ""

    @objc var currentBase: String {
        let trimmed = comboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
        lastCommittedBase = Self.defaultBase
        comboBox.target = self
        comboBox.action = #selector(commit(_:))
        comboBox.delegate = self
    }

    // Adopt a new base value pushed by the workgroup instance —
    // used when another selector commits and we need to mirror its
    // choice without firing our own delegate. Skips the assignment
    // when the user is mid-edit on this field (currentEditor != nil)
    // so a sibling commit doesn't yank input out from under them.
    // Updates lastCommittedBase too so a subsequent Return on the
    // displayed value is correctly recognized as a no-op.
    @objc
    func displayBase(_ base: String) {
        let normalized = base.isEmpty ? Self.defaultBase : base
        if comboBox.currentEditor() != nil {
            // User is actively typing here. Their next commit will
            // overwrite the workgroup's base anyway; pre-empting
            // their cursor would be hostile.
            return
        }
        if comboBox.stringValue != normalized {
            comboBox.stringValue = normalized
        }
        lastCommittedBase = normalized
    }

    // Rebuild the dropdown contents from the persisted recents
    // list. Called from init and from `comboBoxWillPopUp` so a
    // newly-recorded recent appears the next time the user opens
    // the dropdown — never from inside `commit`, because
    // `removeAllItems` cascades into NSTableView selection
    // notifications that re-enter the combo-box delegate and
    // crashed the app on the first commit.
    private func reloadDropdownItems() {
        let savedString = comboBox.stringValue
        let recents = Self.loadRecents()
        comboBox.removeAllItems()
        comboBox.addItem(withObjectValue: Self.defaultBase)
        for entry in recents where entry != Self.defaultBase {
            comboBox.addItem(withObjectValue: entry)
        }
        // removeAllItems clears stringValue on the field; restore.
        comboBox.stringValue = savedString
        // Tell the toolbar to recompute layout — desiredWidthRange
        // is derived from the dropdown contents, so a newly-added
        // recent (e.g. "origin/master") may need more horizontal
        // room than the previous max.
        delegate?.itemDidChange(sender: self)
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
        // Skip the delegate fire when the value didn't actually
        // change. Otherwise picking the already-shown HEAD entry
        // (or pressing Return without edits) would trigger a
        // pointless diff restart, AND a single user action that
        // posts both end-editing and selection-changed
        // notifications would fire twice.
        guard base != lastCommittedBase else { return }
        lastCommittedBase = base
        Self.recordRecent(base)
        gitBaseSelectorDelegate?.gitBaseDidChange(base: base, sender: self)
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        // Width the field needs to render every dropdown entry
        // without truncating. NSComboBox.fittingSize only accounts
        // for the current text, not the items it can show, so the
        // default (just enough for "HEAD") leaves long branch /
        // tag names ellipsized when the user picks them. We measure
        // each persisted entry against the field's font and pick
        // the max, then add a fixed allowance for combo-box chrome
        // (chevron, focus ring, internal padding) so the largest
        // string still doesn't bump up against the dropdown arrow.
        let font = comboBox.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var maxStringWidth: CGFloat = 0
        for value in comboBox.objectValues {
            guard let s = value as? String else { continue }
            let w = (s as NSString).size(withAttributes: attributes).width
            if w > maxStringWidth { maxStringWidth = w }
        }
        // Also fold in the live editor contents so the field grows
        // as the user types past the longest dropdown entry, instead
        // of clipping their text until they commit.
        let live = (comboBox.stringValue as NSString).size(withAttributes: attributes).width
        if live > maxStringWidth { maxStringWidth = live }
        // Empirical chrome budget: the combo-box editor inset on
        // each side plus the chevron button, with extra headroom so
        // the caret has room to breathe past the last glyph while
        // typing instead of butting up against the dropdown arrow.
        let chrome: CGFloat = 48
        // Cap the upper bound so a pathologically long ref (e.g.
        // a 64-char SHA the user pasted in once) doesn't push
        // every other toolbar item out of the available space.
        let cap: CGFloat = 400
        let natural = min(cap, maxStringWidth + chrome)
        // Floor at the "HEAD"-only width so the field stays
        // legible even before the user has used the selector.
        let floor: CGFloat = 80
        return floor...max(floor, natural)
    }

    private static func loadRecents() -> [String] {
        let defaults = iTermUserDefaults.userDefaults()
        return (defaults.object(forKey: recentsKey) as? [String]) ?? []
    }

    private static func recordRecent(_ value: String) {
        guard !value.isEmpty else { return }
        // HEAD is always synthesized at the top of the dropdown by
        // reloadDropdownItems and is the implicit fallback whenever
        // the field is blank — persisting it here would just leave
        // a never-rendered "HEAD" entry in the user's defaults.
        guard value != defaultBase else { return }
        // Drop pathological pastes — git refs are short, and an
        // entry larger than this is almost certainly a mistake the
        // user doesn't want carried across launches.
        guard value.count <= maxRecentLength else { return }
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
    // Refresh the dropdown contents just before it's shown so a
    // recent recorded by the most recent commit appears in the
    // list. Doing this lazily (rather than after every commit)
    // sidesteps the reentrancy hazard that crashed the app: a
    // mid-commit removeAllItems cascades into selection-change
    // notifications that re-enter this delegate.
    func comboBoxWillPopUp(_ notification: Notification) {
        reloadDropdownItems()
    }

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

    // Ask the toolbar to relayout on every keystroke so the field
    // can grow when the typed value exceeds the widest dropdown
    // entry. Without this, desiredWidthRange would only be re-read
    // on commit and the user's text would be clipped mid-type.
    func controlTextDidChange(_ obj: Notification) {
        delegate?.itemDidChange(sender: self)
    }
}

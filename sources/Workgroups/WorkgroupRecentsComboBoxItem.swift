//
//  WorkgroupRecentsComboBoxItem.swift
//  iTerm2SharedARC
//

import AppKit

// Editable combo-box toolbar item whose dropdown offers a fixed default,
// some optional presets, and a recents list persisted in iTermUserDefaults
// so previously-typed values reappear across launches. Subclasses override
// valueDidCommit to act on a change. Only commits on Return, focus loss, or
// a dropdown pick, never on every keystroke, so typing a long value doesn't
// fire once per character. An optional accessory view (e.g. a button) sits
// after the field in the same toolbar item.
class WorkgroupRecentsComboBoxItem: SessionToolbarGenericView {
    struct Configuration {
        // Shown first in the dropdown and used whenever the field is blank.
        let defaultValue: String
        // Shown after the default and before the recents.
        var presets: [String] = []
        // NoSync user defaults key holding the recents list.
        let recentsKey: String
        var maxRecents = 16
        // Sanity cap on a single recents entry. Anything longer is almost
        // certainly an accidental paste, and unbounded entries would let one
        // paste bloat the user's defaults plist.
        var maxRecentLength = 200
        // Minimum field width, so it stays legible before any recents exist.
        var minimumWidth: CGFloat = 80
    }

    private let comboBox: NSComboBox
    private let accessory: NSView?
    private let configuration: Configuration
    private static let accessorySpacing: CGFloat = 4

    // Last value committed. Initialized to the default in init so a fresh
    // user pressing Return on the seeded value doesn't fire a no-op commit,
    // and updated on every committed value thereafter. This is the
    // load-bearing guard against duplicate fires when both
    // `controlTextDidEndEditing` and `comboBoxSelectionDidChange` arrive for
    // the same user action; neither path bypasses the equality check.
    private var lastCommittedValue: String

    // The value as of the last commit or pushed display. Unlike
    // currentValue, it excludes text the user is still typing.
    var committedValue: String {
        return lastCommittedValue
    }

    var currentValue: String {
        let trimmed = comboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? configuration.defaultValue : trimmed
    }

    init(identifier: String,
         priority: Int,
         configuration: Configuration,
         toolTip: String? = nil,
         accessory: NSView? = nil) {
        self.configuration = configuration
        self.accessory = accessory
        comboBox = NSComboBox()
        comboBox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.isEditable = true
        comboBox.toolTip = toolTip
        lastCommittedValue = configuration.defaultValue
        // Plain container, no auto layout, positioned in layoutSubviews.
        let container = NSView(frame: .zero)
        container.addSubview(comboBox)
        if let accessory {
            container.addSubview(accessory)
        }
        super.init(identifier: identifier,
                   priority: priority,
                   view: container)
        reloadDropdownItems()
        comboBox.stringValue = configuration.defaultValue
        comboBox.target = self
        comboBox.action = #selector(commit(_:))
        comboBox.delegate = self
    }

    // Called once per real change. Subclasses override to notify their
    // delegate.
    func valueDidCommit(_ value: String) {
    }

    // Called whenever committedValue may have changed: on commit and on a
    // pushed display. Subclasses override to refresh UI that depends on it,
    // such as the accessory.
    func committedValueDidChange() {
    }

    // Called as the user types, before anything commits. For UI that must
    // react to the live text (currentValue) rather than committedValue.
    func pendingTextDidChange() {
    }

    // Commit whatever is in the field, as if the user pressed Return. For
    // controls (like an accessory button) that refuse first responder, so
    // clicking them doesn't end editing on their own. Ending editing
    // commits through controlTextDidEndEditing; the explicit commit covers
    // the case where the field wasn't being edited or the window declined to
    // change first responder, and is a no-op if the value already committed.
    func commitPendingEdit() {
        if comboBox.currentEditor() != nil {
            comboBox.window?.makeFirstResponder(nil)
        }
        commit(comboBox)
    }

    // Adopt a value pushed from elsewhere (e.g. a sibling item committed)
    // without calling valueDidCommit. Skips the assignment when the user is
    // mid-edit on this field (currentEditor != nil) so a sibling commit
    // doesn't yank input out from under them: their next commit will
    // overwrite the shared value anyway. Updates lastCommittedValue too so a
    // subsequent Return on the displayed value is recognized as a no-op.
    func display(_ value: String) {
        let normalized = value.isEmpty ? configuration.defaultValue : value
        if comboBox.currentEditor() != nil {
            return
        }
        if comboBox.stringValue != normalized {
            comboBox.stringValue = normalized
        }
        lastCommittedValue = normalized
        committedValueDidChange()
    }

    // Rebuild the dropdown contents from the presets and persisted recents.
    // Called from init and from `comboBoxWillPopUp` so a newly-recorded
    // recent appears the next time the user opens the dropdown. Never call
    // it from inside `commit`: `removeAllItems` cascades into NSTableView
    // selection notifications that re-enter the combo-box delegate and
    // crashed the app on the first commit.
    private func reloadDropdownItems() {
        let savedString = comboBox.stringValue
        let fixed = [configuration.defaultValue] + configuration.presets
        comboBox.removeAllItems()
        for entry in fixed {
            comboBox.addItem(withObjectValue: entry)
        }
        for entry in loadRecents() where !fixed.contains(entry) {
            comboBox.addItem(withObjectValue: entry)
        }
        // removeAllItems clears stringValue on the field; restore.
        comboBox.stringValue = savedString
        // desiredWidthRange is derived from the dropdown contents, so a
        // newly-added recent may need more horizontal room than before.
        delegate?.itemDidChange(sender: self)
    }

    @objc
    private func commit(_ sender: Any?) {
        let value = currentValue
        // Reflect the canonicalized value (trimmed, default fallback) back
        // into the field so what the user sees matches what's used.
        if comboBox.stringValue != value {
            comboBox.stringValue = value
        }
        // Skip when the value didn't actually change. Otherwise picking the
        // already-shown entry (or pressing Return without edits) would fire
        // a pointless commit, and a single user action that posts both
        // end-editing and selection-changed notifications would fire twice.
        guard value != lastCommittedValue else { return }
        lastCommittedValue = value
        recordRecent(value)
        valueDidCommit(value)
        committedValueDidChange()
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        let field = fieldWidthRange
        let extra = accessoryWidth
        return (field.lowerBound + extra)...(field.upperBound + extra)
    }

    private var accessoryWidth: CGFloat {
        guard let accessory else { return 0 }
        return accessory.fittingSize.width + Self.accessorySpacing
    }

    override func layoutSubviews() {
        // Skip super: its sizing assumes _view has a useful fittingSize, but
        // a plain container reports zero.
        let bounds = view.bounds
        _view.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        let fieldHeight = comboBox.fittingSize.height
        let fieldWidth = max(0, bounds.width - accessoryWidth)
        comboBox.frame = NSRect(x: 0,
                                y: (bounds.height - fieldHeight) / 2.0,
                                width: fieldWidth,
                                height: fieldHeight)
        if let accessory {
            let size = accessory.fittingSize
            accessory.frame = NSRect(x: fieldWidth + Self.accessorySpacing,
                                     y: (bounds.height - size.height) / 2.0,
                                     width: size.width,
                                     height: size.height)
        }
    }

    private var fieldWidthRange: ClosedRange<CGFloat> {
        // Width the field needs to render every dropdown entry without
        // truncating. NSComboBox.fittingSize only accounts for the current
        // text, not the items it can show, so measure each entry against the
        // field's font and take the max.
        let font = comboBox.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var maxStringWidth: CGFloat = 0
        for value in comboBox.objectValues {
            guard let s = value as? String else { continue }
            let w = (s as NSString).size(withAttributes: attributes).width
            if w > maxStringWidth { maxStringWidth = w }
        }
        // Also fold in the live editor contents so the field grows as the
        // user types past the longest dropdown entry, instead of clipping
        // their text until they commit.
        let live = (comboBox.stringValue as NSString).size(withAttributes: attributes).width
        if live > maxStringWidth { maxStringWidth = live }
        // Empirical chrome budget: the combo-box editor inset on each side
        // plus the chevron button, with extra headroom so the caret has room
        // past the last glyph while typing.
        let chrome: CGFloat = 48
        // Cap the upper bound so a pathologically long value doesn't push
        // every other toolbar item out of the available space.
        let cap: CGFloat = 400
        let natural = min(cap, maxStringWidth + chrome)
        let floor = configuration.minimumWidth
        return floor...max(floor, natural)
    }

    private func loadRecents() -> [String] {
        let defaults = iTermUserDefaults.userDefaults()
        return (defaults.object(forKey: configuration.recentsKey) as? [String]) ?? []
    }

    private func recordRecent(_ value: String) {
        guard !value.isEmpty else { return }
        // The default and presets are always synthesized at the top of the
        // dropdown, so persisting them would just leave never-rendered
        // entries in the user's defaults.
        guard value != configuration.defaultValue,
              !configuration.presets.contains(value) else {
            return
        }
        guard value.count <= configuration.maxRecentLength else { return }
        var recents = loadRecents()
        recents.removeAll { $0 == value }
        recents.insert(value, at: 0)
        if recents.count > configuration.maxRecents {
            recents = Array(recents.prefix(configuration.maxRecents))
        }
        iTermUserDefaults.userDefaults().set(recents,
                                             forKey: configuration.recentsKey)
    }
}

extension WorkgroupRecentsComboBoxItem: NSComboBoxDelegate {
    // Refresh the dropdown contents just before it's shown so a recent
    // recorded by the most recent commit appears in the list. Doing this
    // lazily (rather than after every commit) sidesteps the reentrancy hazard
    // described at reloadDropdownItems.
    func comboBoxWillPopUp(_ notification: Notification) {
        reloadDropdownItems()
    }

    // Picking from the dropdown commits immediately.
    func comboBoxSelectionDidChange(_ notification: Notification) {
        // The selectedItem index hasn't been reflected into stringValue yet
        // at this notification, so read it directly.
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

    // Ask the toolbar to relayout on every keystroke so the field can grow
    // when the typed value exceeds the widest dropdown entry. Without this,
    // desiredWidthRange would only be re-read on commit and the user's text
    // would be clipped mid-type.
    func controlTextDidChange(_ obj: Notification) {
        delegate?.itemDidChange(sender: self)
        pendingTextDidChange()
    }
}

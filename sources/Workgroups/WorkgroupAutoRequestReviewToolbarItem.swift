//
//  WorkgroupAutoRequestReviewToolbarItem.swift
//  iTerm2SharedARC
//

import AppKit

// The user toggled the "auto-request review when idle" control. `ownerPeerID`
// identifies the main-session config whose toolbar the toggle belongs to so
// the delegate can find the right session; `isOn` is the new state.
protocol WorkgroupAutoRequestReviewToolbarItemDelegate: AnyObject {
    func workgroupAutoRequestReview(ownerPeerID: String?, isOn: Bool)
}

// On/off toggle for the main (root) session. When on, the workgroup requests
// a code review from its sole code-review session each time the main session
// goes idle. Same borderless look as WorkgroupAutoSendClippingsToolbarItem
// (state shown by tint, not a bezel), but with an enabled flag: the workgroup
// must have exactly one code-review session for the toggle to do anything, so
// it renders disabled (and non-interactive) otherwise.
final class WorkgroupAutoRequestReviewToolbarItem: SessionToolbarControl {
    weak var autoRequestDelegate: WorkgroupAutoRequestReviewToolbarItemDelegate?
    // Tagged with the owning (main) config UUID so the delegate can find the
    // session whose toggle fired.
    var ownerPeerID: String?

    private let button: NSButton
    private let isEnabledForReview: Bool

    init(identifier: String,
         priority: Int,
         isOn: Bool,
         enabled: Bool) {
        isEnabledForReview = enabled
        button = NSButton(title: "", target: nil, action: nil)
        button.setButtonType(.pushOnPushOff)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.refusesFirstResponder = true
        // A disabled toggle can't meaningfully be on, so force off when there
        // isn't exactly one code-review session to target.
        button.state = (isOn && enabled) ? .on : .off
        button.isEnabled = enabled
        Self.configure(button: button, isOn: button.state == .on, enabled: enabled)
        super.init(identifier: identifier, priority: priority, control: button)
        button.target = self
        button.action = #selector(didToggle(_:))
    }

    // Reflect a state set programmatically without firing the delegate.
    func setOn(_ isOn: Bool) {
        guard isEnabledForReview else { return }
        button.state = isOn ? .on : .off
        Self.configure(button: button, isOn: isOn, enabled: isEnabledForReview)
    }

    private static func configure(button: NSButton, isOn: Bool, enabled: Bool) {
        // Outline seal when off, filled seal when on, so state reads from the
        // glyph as well as the tint (matching the paperplane auto-send toggle).
        let symbol: SFSymbol = (isOn && enabled) ? .checkmarkSealFill : .checkmarkSeal
        button.image = NSImage(systemSymbolName: symbol.rawValue,
                               accessibilityDescription: "Auto-request review when idle")
        if !enabled {
            button.contentTintColor = .tertiaryLabelColor
            button.toolTip = "Auto-request a review when idle (needs exactly one code review session)"
            return
        }
        button.contentTintColor = isOn ? .controlAccentColor : .secondaryLabelColor
        button.toolTip = isOn
            ? "Auto-request a review from the code review session when idle: on"
            : "Auto-request a review from the code review session when idle: off"
    }

    @objc private func didToggle(_ sender: Any?) {
        let isOn = button.state == .on
        Self.configure(button: button, isOn: isOn, enabled: isEnabledForReview)
        autoRequestDelegate?.workgroupAutoRequestReview(ownerPeerID: ownerPeerID,
                                                        isOn: isOn)
    }
}

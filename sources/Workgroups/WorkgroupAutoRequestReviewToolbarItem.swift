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

    // Current visual on-state. Read-only; the source of truth is the
    // owning session's autoRequestReviewWhenIdle flag, mirrored here by
    // setOn. Exposed for tests and introspection.
    var isOn: Bool { button.state == .on }

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
    // Lets the port re-derive the button from its owning session's live
    // flag (see iTermWorkgroupPeerPort.syncAutoBehaviorToggles).
    func setOn(_ isOn: Bool) {
        guard isEnabledForReview else { return }
        guard button.state != (isOn ? .on : .off) else { return }
        button.state = isOn ? .on : .off
        Self.configure(button: button, isOn: isOn, enabled: isEnabledForReview)
    }

    private static func configure(button: NSButton, isOn: Bool, enabled: Bool) {
        // Outline seal when off, filled seal when on, so state reads from the
        // glyph as well as the tint (matching the paperplane auto-send toggle).
        let symbol: SFSymbol = (isOn && enabled) ? .checkmarkSealFill : .checkmarkSeal
        button.image = NSImage(systemSymbolName: symbol.rawValue,
                               accessibilityDescription: String(localized: "WorkgroupAutoRequestReview.AccessibilityDescription", defaultValue: "Auto-request review when idle", comment: "Accessibility description for the auto-request-review toggle"))
        if !enabled {
            button.contentTintColor = .tertiaryLabelColor
            button.toolTip = String(localized: "WorkgroupAutoRequestReview.ToolTipDisabled", defaultValue: "Auto-request a review when idle (needs exactly one code review session)", comment: "Tooltip when the auto-request-review toggle is disabled")
            return
        }
        button.contentTintColor = isOn ? .controlAccentColor : .secondaryLabelColor
        button.toolTip = isOn
            ? String(localized: "WorkgroupAutoRequestReview.ToolTipOn", defaultValue: "Auto-request a review from the code review session when idle: on", comment: "Tooltip when the auto-request-review toggle is on")
            : String(localized: "WorkgroupAutoRequestReview.ToolTipOff", defaultValue: "Auto-request a review from the code review session when idle: off", comment: "Tooltip when the auto-request-review toggle is off")
    }

    @objc private func didToggle(_ sender: Any?) {
        let isOn = button.state == .on
        Self.configure(button: button, isOn: isOn, enabled: isEnabledForReview)
        autoRequestDelegate?.workgroupAutoRequestReview(ownerPeerID: ownerPeerID,
                                                        isOn: isOn)
    }
}

//
//  WorkgroupAutoSendClippingsToolbarItem.swift
//  iTerm2SharedARC
//

import AppKit

// The user toggled the "auto-send clippings when idle" control. `ownerPeerID`
// identifies the code-review peer whose toolbar the toggle belongs to so the
// delegate can find the right session; `isOn` is the new state.
protocol WorkgroupAutoSendClippingsToolbarItemDelegate: AnyObject {
    func workgroupAutoSendClippings(ownerPeerID: String?, isOn: Bool)
}

// A single on/off toggle button for .codeReview peers. When on, the workgroup
// runtime sends the review session's clippings to the workgroup's main session
// whenever the review session goes idle. Modeled on WorkgroupReloadToolbarItem
// (a borderless NSButton), so it reads as a sibling of the other toolbar
// buttons. On/off is conveyed entirely by the symbol (outline vs filled) and
// an explicit tint (dim vs accent) rather than a bezel background: a bordered
// push-on/push-off bezel tracks both button state AND window-active status, so
// its fill flips between blue and white in a way that reads as noise, not
// state.
final class WorkgroupAutoSendClippingsToolbarItem: SessionToolbarControl {
    weak var autoSendDelegate: WorkgroupAutoSendClippingsToolbarItemDelegate?
    // Tagged with the owning peer config UUID so the delegate can demultiplex
    // which session's toggle fired.
    var ownerPeerID: String?

    private let button: NSButton

    init(identifier: String,
         priority: Int,
         isOn: Bool) {
        button = NSButton(title: "", target: nil, action: nil)
        button.setButtonType(.pushOnPushOff)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.refusesFirstResponder = true
        button.state = isOn ? .on : .off
        Self.configure(button: button, isOn: isOn)
        super.init(identifier: identifier, priority: priority, control: button)
        button.target = self
        button.action = #selector(didToggle(_:))
    }

    private static func configure(button: NSButton, isOn: Bool) {
        let symbol: SFSymbol = isOn ? .paperplaneFill : .paperplane
        button.image = NSImage(systemSymbolName: symbol.rawValue,
                               accessibilityDescription: "Auto-send clippings when idle")
        // Explicit tints so the look is stable across window-active changes:
        // accent when on, a dim secondary label color when off.
        button.contentTintColor = isOn ? .controlAccentColor : .secondaryLabelColor
        button.toolTip = isOn
            ? "Auto-send clippings to the main session when idle: on"
            : "Auto-send clippings to the main session when idle: off"
    }

    @objc private func didToggle(_ sender: Any?) {
        let isOn = button.state == .on
        Self.configure(button: button, isOn: isOn)
        autoSendDelegate?.workgroupAutoSendClippings(ownerPeerID: ownerPeerID,
                                                     isOn: isOn)
    }
}

//
//  CompanionKeyboardInputView.swift
//  iTerm2 Companion
//
//  The live session canvas's root view, made a first responder so tapping the
//  terminal raises the system keyboard and routes typing into the session. It
//  conforms to UIKeyInput (the minimal text-entry protocol: insert a string, delete
//  backward) and hosts the SwiftUI accessory bar (SessionKeyboardAccessory) as its
//  inputAccessoryView. Every keypress - typed characters here, and accessory-button
//  keys in the SwiftUI bar - funnels through the shared SessionKeyboardController.
//

import SwiftUI
import UIKit

final class CompanionKeyboardInputView: UIView, UIKeyInput {
    weak var controller: SessionKeyboardController?

    /// The hosted accessory bar. Retained here (a UIHostingController is not added as
    /// a child VC, which is fine for an input accessory) and returned as the
    /// inputAccessoryView while this view is first responder.
    private var accessoryView: KeyboardAccessoryInputView?

    /// Build and install the accessory bar for the given controller. Called once by
    /// the canvas coordinator after wiring the controller's send/dismiss closures.
    func installAccessory(controller: SessionKeyboardController) {
        self.controller = controller
        let accessory = KeyboardAccessoryInputView(controller: controller)
        accessoryView = accessory
        // Resize the accessory (and tell UIKit to re-query it) when the tray expands.
        controller.onExpandedChanged = { [weak self, weak accessory] expanded in
            accessory?.setExpanded(expanded)
            self?.reloadInputViews()
        }
    }

    override var canBecomeFirstResponder: Bool { true }
    override var inputAccessoryView: UIView? { accessoryView }

    // MARK: UITextInputTraits

    // A terminal wants the raw keys, so disable every "helpful" transform: no
    // autocorrect, no autocapitalizing the first letter of a command, and no smart
    // quote/dash substitution that would turn -- into an en dash or " into a curly
    // quote. asciiCapable also drops the predictive suggestion bar.
    var keyboardType: UIKeyboardType { .asciiCapable }
    var autocorrectionType: UITextAutocorrectionType { .no }
    var autocapitalizationType: UITextAutocapitalizationType { .none }
    var spellCheckingType: UITextSpellCheckingType { .no }
    var smartQuotesType: UITextSmartQuotesType { .no }
    var smartDashesType: UITextSmartDashesType { .no }
    var smartInsertDeleteType: UITextSmartInsertDeleteType { .no }

    // MARK: UIKeyInput

    // Always report text so deleteBackward is delivered even when nothing has been
    // typed yet (the session, not this view, owns the real buffer).
    var hasText: Bool { true }

    func insertText(_ text: String) {
        controller?.sendText(text)
    }

    func deleteBackward() {
        controller?.sendBackspace()
    }
}

/// A UIInputView that hosts the SwiftUI accessory and sizes itself via
/// intrinsicContentSize (which UIKit reads for input accessory views), switching
/// between the compact and expanded heights. It opts into key-click feedback so the
/// accessory buttons' UIDevice.playInputClick() plays (only when the user has
/// keyboard clicks enabled).
final class KeyboardAccessoryInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }

    private let host: UIHostingController<SessionKeyboardAccessory>
    private var expanded = false

    init(controller: SessionKeyboardController) {
        host = UIHostingController(rootView: SessionKeyboardAccessory(controller: controller))
        super.init(frame: CGRect(x: 0, y: 0, width: 0,
                                 height: SessionKeyboardAccessoryMetrics.compactHeight),
                   inputViewStyle: .keyboard)
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addSubview(host.view)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        expanded = value
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: expanded ? SessionKeyboardAccessoryMetrics.expandedHeight
                                : SessionKeyboardAccessoryMetrics.compactHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = bounds
    }
}

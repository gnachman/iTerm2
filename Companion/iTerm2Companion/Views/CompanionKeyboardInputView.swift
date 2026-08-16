//
//  CompanionKeyboardInputView.swift
//  iTerm2 Companion
//
//  The session's text-entry first responder: a hidden, zero-size UITextView that a
//  tap on the terminal makes first responder, raising the system keyboard. It is a
//  UITextView - not a bare UIKeyInput - on purpose: the system keyboard's dictation
//  (mic) key only engages against a full UITextInput responder, so a UIKeyInput
//  leaves that key inert. In normal use this view is a transparent pass-through - its
//  own document is kept empty and every keystroke is forwarded straight to the
//  session (the mac owns the real buffer) - and it hosts the SwiftUI accessory bar
//  (SessionKeyboardAccessory) as its inputAccessoryView. Every keypress (typed
//  characters here, and accessory-button keys in the SwiftUI bar) funnels through the
//  shared SessionKeyboardController.
//
//  The same view doubles as the local Composer in its expanded state: opened by the
//  accessory's compose button or automatically when dictation starts, it becomes a
//  visible, editable text area above the keyboard (a real UITextView document, so the
//  system dictation key works natively). Typing and dictation accumulate locally; Send
//  types the whole draft to the session at once (no trailing newline) and Close keeps
//  the draft for next time. Being one view - not a separate field - is what lets the
//  system mic seamlessly open the composer without resigning first responder mid-
//  dictation. The canvas coordinator owns where the expanded view sits (above the
//  keyboard); this view owns the two modes and their styling.
//

import SwiftUI
import UIKit

final class CompanionKeyboardInputView: UITextView, UITextViewDelegate {
    /// Pass-through routes every keystroke to the session and keeps this view's own
    /// document empty; composer accumulates a local draft that Send delivers at once.
    enum Mode { case passthrough, composer }

    weak var controller: SessionKeyboardController?

    private(set) var mode: Mode = .passthrough

    /// Called whenever the mode flips, so the canvas coordinator can (re)position the
    /// visible composer above the keyboard or shrink it away.
    var onModeChanged: (() -> Void)?
    /// Delivers the composer's draft when the user taps Send. No trailing newline - the
    /// mac types it verbatim, so the user adds a Return themselves if they want one.
    var onSendComposerText: ((String) -> Void)?

    /// The terminal key bar (esc/^C/arrows), shown while passing through; and the
    /// composer bar (Send/Close), shown while composing. Swapped as the inputAccessory.
    private var terminalAccessory: KeyboardAccessoryInputView?
    private var composerAccessory: ComposerAccessoryInputView?

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = true
        applyPassthroughStyling()
        // A terminal wants the raw keys, so disable every "helpful" transform: no
        // autocorrect, no autocapitalizing the first letter of a command, and no smart
        // quote/dash substitution that would turn -- into an en dash or " into a curly
        // quote. asciiCapable also drops the predictive suggestion bar. (The composer
        // inherits these too, which suits typing shell commands.)
        keyboardType = .asciiCapable
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        delegate = self
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    /// Build both accessory bars for the given controller and install the terminal one.
    /// Called once by the canvas coordinator after wiring the controller's closures.
    func installAccessory(controller: SessionKeyboardController) {
        self.controller = controller
        let terminal = KeyboardAccessoryInputView(controller: controller)
        terminalAccessory = terminal
        // UITextView exposes inputAccessoryView as a settable property (unlike the
        // read-only UIResponder one), so just assign it.
        inputAccessoryView = terminal
        // Resize the accessory (and tell UIKit to re-query it) when the tray expands.
        controller.onExpandedChanged = { [weak self, weak terminal] expanded in
            terminal?.setExpanded(expanded)
            self?.reloadInputViews()
        }
        // The composer bar is built up front and swapped in when the composer opens.
        composerAccessory = ComposerAccessoryInputView(
            onSend: { [weak self] in self?.sendComposerTapped() },
            onClose: { [weak self] in self?.exitComposer(clearDraft: false) })
    }

    override var canBecomeFirstResponder: Bool { true }

    // MARK: Mode

    /// Enter the composer: reveal an editable local draft above the keyboard and swap
    /// the terminal keys for the composer bar. No-op if already composing.
    func enterComposer() {
        guard mode == .passthrough else { return }
        mode = .composer
        applyComposerStyling()
        inputAccessoryView = composerAccessory
        reloadInputViews()
        onModeChanged?()
    }

    /// Collapse back to the transparent pass-through. `clearDraft` empties the draft
    /// (after a send); otherwise the text is kept in the hidden view for next time.
    func exitComposer(clearDraft: Bool) {
        guard mode == .composer else { return }
        if clearDraft { text = "" }
        mode = .passthrough
        applyPassthroughStyling()
        inputAccessoryView = terminalAccessory
        reloadInputViews()
        onModeChanged?()
    }

    private func sendComposerTapped() {
        // Strip any stray dictation placeholder (U+FFFC object replacement char) so it
        // can never reach the shell.
        let draft = (text ?? "").replacingOccurrences(of: "\u{FFFC}", with: "")
        guard !draft.isEmpty else { exitComposer(clearDraft: false); return }
        onSendComposerText?(draft)
        exitComposer(clearDraft: true)
    }

    /// Invisible and caretless (the coordinator keeps it a small strip behind the opaque
    /// canvas), but scroll-enabled: a scroll-disabled, zero-size text view pushes the
    /// system dictation key onto its degenerate insertText path. Keeping it a real,
    /// scrollable document lets dictation deposit text we can detect.
    private func applyPassthroughStyling() {
        isScrollEnabled = true
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear               // no visible caret
        layer.cornerRadius = 0
        layer.masksToBounds = false
    }

    /// A visible, scrollable, rounded editor with a real caret.
    private func applyComposerStyling() {
        isScrollEnabled = true
        backgroundColor = .secondarySystemBackground
        textColor = .label
        tintColor = UIColor(Color.accentColor)   // visible caret in the app tint
        font = .preferredFont(forTextStyle: .body)
        textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        layer.cornerRadius = 12
        layer.masksToBounds = true
    }

    // MARK: Text entry

    // Always report text so deleteBackward is delivered even when the (empty) document
    // has nothing to delete - in pass-through the session, not this view, owns the
    // real buffer.
    override var hasText: Bool {
        mode == .composer ? super.hasText : true
    }

    override func insertText(_ text: String) {
        switch mode {
        case .passthrough:
            // A multi-character insert is the system mic's opening dictation chunk: typed
            // input is always a single grapheme (asciiCapable, no autocorrect) and paste
            // goes through the edit menu, not insertText. Seed the document with it -
            // textViewDidChange then opens the composer, and the rest of the dictation
            // streams in as native document updates. Single characters are live typing:
            // forward to the session and leave our document untouched.
            if text.count >= 2 {
                super.insertText(text)
            } else {
                controller?.sendText(text)
            }
        case .composer:
            super.insertText(text)   // accumulate locally for review
        }
    }

    override func deleteBackward() {
        switch mode {
        case .passthrough:
            controller?.sendBackspace()
        case .composer:
            super.deleteBackward()
        }
    }

    // MARK: UITextViewDelegate

    // In pass-through our own typing never touches this document (single characters are
    // forwarded, not inserted), so ANY change here is the system mic dictating - the
    // opening chunk we seed via insertText, OR a fresh dictation writing straight into
    // the document. The latter is what happens after the composer was closed with a kept
    // draft: the next dictation bypasses insertText entirely, so this is the only signal
    // that reopens the composer. Deferred a runloop tick so we do not swap input views
    // from inside the text-change callback (the in-flight dictation keeps updating the
    // now-composer document). exitComposer clears its draft while still in composer mode,
    // so that clear does not bounce us straight back open.
    func textViewDidChange(_ textView: UITextView) {
        guard mode == .passthrough, textStorage.length > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mode == .passthrough else { return }
            self.enterComposer()
        }
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

/// The composer's input-accessory bar (Send / Close), docked directly above the
/// keyboard while the composer is open. Fixed height; hosts the SwiftUI bar the same
/// way KeyboardAccessoryInputView does.
final class ComposerAccessoryInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }

    private let host: UIHostingController<SessionComposerAccessory>

    init(onSend: @escaping () -> Void, onClose: @escaping () -> Void) {
        host = UIHostingController(rootView: SessionComposerAccessory(onSend: onSend, onClose: onClose))
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: SessionComposerAccessory.height),
                   inputViewStyle: .keyboard)
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addSubview(host.view)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: SessionComposerAccessory.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = bounds
    }
}

/// The composer's button bar: Close on the left (keeps the draft), Send on the right
/// (types the draft to the session with no trailing newline). The Whisper mic button
/// lands here in a later step.
struct SessionComposerAccessory: View {
    static let height: CGFloat = 52

    let onSend: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close composer")

            Spacer()
            Text("Compose")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Send to session")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
    }
}

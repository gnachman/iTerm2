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

    /// Hint shown in the (otherwise empty) composer so it doesn't read as a blank slab.
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Type here…"
        label.textColor = .placeholderText
        label.font = .preferredFont(forTextStyle: .body)
        label.isHidden = true
        return label
    }()

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = true
        addSubview(placeholderLabel)
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

    /// Build both accessory bars and install the terminal one. Called once by the canvas
    /// coordinator, which owns the composer's Send/Close/Mic behavior (it drives the
    /// shared dictation controller), so those arrive as closures.
    func installAccessory(controller: SessionKeyboardController,
                          model: AppModel,
                          dictationToken: UUID,
                          onComposerSend: @escaping () -> Void,
                          onComposerClose: @escaping () -> Void,
                          onComposerMic: @escaping () -> Void) {
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
            model: model, dictationToken: dictationToken,
            onSend: onComposerSend, onClose: onComposerClose, onMic: onComposerMic)
    }

    /// Type the draft to the session (no trailing newline), returning whether anything
    /// was sent. Does NOT collapse the composer - the coordinator animates that out and
    /// clears the draft afterward. Called after any in-flight Whisper dictation is
    /// finalized so its tail is included.
    @discardableResult
    func sendComposerDraft() -> Bool {
        // Strip any stray dictation placeholder (U+FFFC object replacement char) so it
        // can never reach the shell.
        let draft = (text ?? "").replacingOccurrences(of: "\u{FFFC}", with: "")
        guard !draft.isEmpty else { return false }
        onSendComposerText?(draft)
        return true
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
        updatePlaceholderVisibility()
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
        updatePlaceholderVisibility()
        onModeChanged?()
    }

    /// The composer placeholder shows only while composing with an empty draft.
    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = mode != .composer || !(text ?? "").isEmpty
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let x = textContainerInset.left + textContainer.lineFragmentPadding
        let width = max(0, bounds.width - x - textContainerInset.right)
        let height = placeholderLabel.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)).height
        placeholderLabel.frame = CGRect(x: x, y: textContainerInset.top, width: width, height: height)
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
        layer.borderWidth = 0
        layer.masksToBounds = false
    }

    /// A rounded editing surface with a real caret. Its background is clear: the
    /// coordinator's Liquid Glass backing view sits directly behind it and supplies the
    /// translucent blur and glass outline (matching system floating panels), so this view
    /// just holds the (clipped) text on top.
    private func applyComposerStyling() {
        isScrollEnabled = true
        backgroundColor = .clear
        textColor = .label
        tintColor = UIColor(Color.accentColor)   // visible caret in the app tint
        font = .preferredFont(forTextStyle: .body)
        textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        layer.cornerRadius = Self.composerCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }

    static let composerCornerRadius: CGFloat = 14

    // MARK: On-device (Whisper) dictation live span

    // Whisper re-transcribes the whole recording each pass, so each partial replaces the
    // last instead of appending. We own a range in the document and rewrite it on every
    // update, leaving anything the user typed before it untouched. Mirrors the chat
    // composer's MentionComposerController. Only used for the Whisper mic button; the
    // system dictation key writes into the document natively and needs none of this.

    /// The span currently owned by live Whisper dictation, or nil when not dictating.
    private var liveRange: NSRange?
    /// Prefix the transcript with a space when it starts right after non-whitespace, so
    /// it reads as a new word rather than being glued on.
    private var liveNeedsLeadingSpace = false

    private var composerTextAttributes: [NSAttributedString.Key: Any] {
        [.font: font ?? UIFont.preferredFont(forTextStyle: .body),
         .foregroundColor: UIColor.label]
    }

    /// Mark the cursor position as the start of a live dictation segment.
    func beginLiveTranscript() {
        let location = selectedRange.location
        liveRange = NSRange(location: location, length: 0)
        let contents = attributedText.string as NSString
        if location > 0, location <= contents.length {
            let preceding = contents.substring(with: NSRange(location: location - 1, length: 1))
            liveNeedsLeadingSpace = !preceding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            liveNeedsLeadingSpace = false
        }
    }

    /// Replace the live segment with the latest partial transcript, leaving text typed
    /// before it untouched.
    func updateLiveTranscript(_ text: String) {
        guard let range = liveRange else { return }
        let prefix = (liveNeedsLeadingSpace && !text.isEmpty) ? " " : ""
        let replacement = NSAttributedString(string: prefix + text, attributes: composerTextAttributes)
        let updated = NSMutableAttributedString(attributedString: attributedText)
        guard range.location + range.length <= updated.length else { liveRange = nil; return }
        updated.replaceCharacters(in: range, with: replacement)
        attributedText = updated
        let newRange = NSRange(location: range.location, length: replacement.length)
        liveRange = newRange
        selectedRange = NSRange(location: newRange.location + newRange.length, length: 0)
        typingAttributes = composerTextAttributes
        scrollRangeToVisible(selectedRange)
        updatePlaceholderVisibility()
    }

    /// Apply the definitive final transcript and finish. Passing "" just drops the live
    /// span (e.g. dictation was abandoned).
    func commitLiveTranscript(_ text: String) {
        updateLiveTranscript(text)
        liveRange = nil
        liveNeedsLeadingSpace = false
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
        updatePlaceholderVisibility()
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
                   inputViewStyle: .default)
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        // Transparent: the bar floats as a glass shape (drawn in SwiftUI) over the video,
        // with the keyboard directly below. No opaque panel background.
        backgroundColor = .clear
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

/// The composer's input-accessory bar (Close / mic / Send), docked directly above the
/// keyboard while the composer is open. Fixed height; hosts the SwiftUI bar the same
/// way KeyboardAccessoryInputView does.
final class ComposerAccessoryInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }

    private let host: UIHostingController<SessionComposerAccessory>

    init(model: AppModel,
         dictationToken: UUID,
         onSend: @escaping () -> Void,
         onClose: @escaping () -> Void,
         onMic: @escaping () -> Void) {
        host = UIHostingController(rootView: SessionComposerAccessory(
            model: model, dictationToken: dictationToken,
            onSend: onSend, onClose: onClose, onMic: onMic))
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: SessionComposerAccessory.height),
                   inputViewStyle: .default)
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
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

/// Drives the composer glass's vertical position. The glass must move via SwiftUI's own
/// `.offset` (animated with `withAnimation`), because `.glassEffect` stops rendering the
/// moment its hosting layer has a UIKit transform - so the coordinator can't slide it the
/// way it slides the (UIKit) text view.
@MainActor final class ComposerGlassModel: ObservableObject {
    @Published var offsetY: CGFloat = 0
    @Published var opacity: Double = 1
}

/// The composer pane's Liquid Glass backing, rendered in SwiftUI so it uses the exact
/// same `.glassEffect` as the accessory bars (which read as properly translucent, unlike
/// the UIKit UIGlassEffect, which can't sample the video layer). The text view sits on top
/// with a clear background; this supplies the blur and the glass edge.
struct ComposerGlassBackground: View {
    @ObservedObject var model: ComposerGlassModel
    var body: some View {
        Color.clear
            .glassEffect(.regular,
                         in: RoundedRectangle(cornerRadius: CompanionKeyboardInputView.composerCornerRadius,
                                              style: .continuous))
            .opacity(model.opacity)
            .offset(y: model.offsetY)
    }
}

/// The composer's button bar: Close (keeps the draft), the on-device (Whisper) mic, and
/// Send (types the draft to the session, no trailing newline). The coordinator owns the
/// dictation lifecycle; this bar renders the mic state from the shared controller and
/// reports taps.
struct SessionComposerAccessory: View {
    static let height: CGFloat = 52

    let model: AppModel
    let dictationToken: UUID
    let onSend: () -> Void
    let onClose: () -> Void
    let onMic: () -> Void

    /// This composer owns the dictation cycle (vs. a chat's bar, which shares the same
    /// recorder), so only then does the mic read as listening.
    private var listening: Bool {
        model.dictation.owns(dictationToken) && model.dictation.voice.state == .listening
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Close composer")

            micButton

            Spacer(minLength: 8)

            // Send is the one prominent action: a filled accent circle (like Messages),
            // which reads clearly on the glass in both light and dark mode.
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: Circle())
            }
            .accessibilityLabel("Send to session")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder private var micButton: some View {
        Button(action: onMic) {
            Group {
                switch model.whisperManager.status {
                case .downloading, .preparing:
                    ProgressView()
                default:
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(listening ? Color.red : Color.primary)
                        .scaleEffect(listening ? 1 + CGFloat(model.dictation.voice.audioLevel) * 0.3 : 1)
                        .animation(.easeOut(duration: 0.1), value: model.dictation.voice.audioLevel)
                }
            }
            .frame(width: 30, height: 30)
        }
        .accessibilityLabel(listening ? "Stop dictation" : "Dictate")
    }
}

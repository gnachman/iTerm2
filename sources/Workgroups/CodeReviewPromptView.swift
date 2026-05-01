//
//  CodeReviewPromptView.swift
//  iTerm2SharedARC
//
//  In-session overlay shown before a Code Review-mode workgroup peer
//  starts its program. The user types a free-form prompt; clicking
//  Start invokes `onStart` with the entered text.
//

import AppKit

@objc(iTermCodeReviewPromptView)
class CodeReviewPromptView: NSView {
    @objc var onStart: ((String) -> Void)?

    // Closure that returns the desired frame in superview coordinates.
    // Invoked whenever the superview posts NSViewFrameDidChangeNotification
    // so the overlay tracks the scrollview-area as the session resizes
    // (SessionView's manual layout doesn't honor subview autoresizing).
    var frameProvider: (() -> NSRect)? {
        didSet { updateFrameFromProvider() }
    }

    @objc var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            let end = (newValue as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            reloadBaselineAndUpdateSaveButton()
        }
    }

    // Baseline value used to decide whether the prompt has been "edited"
    // (and thus whether Save Prompt is enabled). Set to the current
    // saved-defaults value at init time and after each save.
    private var savedBaseline: String = ""

    private let scrollView: NSScrollView
    private let textView: ShiftReturnSubmittingTextView
    private let startButton: NSButton
    private let savePromptButton: NSButton
    private let titleLabel: NSTextField

    private let outerInset: CGFloat = 16
    private let innerSpacing: CGFloat = 8
    private let buttonSpacing: CGFloat = 12
    private let buttonHeight: CGFloat = 28
    private let titleHeight: CGFloat = 18

    // Block-based KVO token. Manual addObserver/removeObserver against a
    // weak SessionView is unsafe at tear-down: ARC zeros weak refs before
    // -[NSView dealloc] propagates removeFromSuperview to subviews, so
    // viewWillMove(toSuperview: nil) would see a nil ref and skip removal,
    // tripping the "deallocated while observers still registered" trap.
    private var panelReservationObservation: NSKeyValueObservation?

    @objc override init(frame frameRect: NSRect) {
        scrollView = NSScrollView(frame: .zero)
        textView = ShiftReturnSubmittingTextView(frame: .zero)
        startButton = NSButton(frame: .zero)
        savePromptButton = NSButton(frame: .zero)
        titleLabel = NSTextField(labelWithString:
            NSLocalizedString("Code review prompt:",
                              comment: "Label above the code review prompt text field"))

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        autoresizesSubviews = false

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(titleLabel)

        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .userFixedPitchFont(ofSize: NSFont.systemFontSize)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.onSubmit = { [weak self] in
            guard let self else { return }
            self.startClicked(self)
        }
        textView.delegate = self

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        startButton.title = NSLocalizedString("Start",
            comment: "Button to start the code review program")
        startButton.bezelStyle = .rounded
        // Shift-Return submits via the text view's keyDown override
        // (set above); plain Return inserts a newline. The button
        // itself has no keyEquivalent because the text view consumes
        // Return as text input before performKeyEquivalent: runs.
        startButton.target = self
        startButton.action = #selector(startClicked(_:))
        startButton.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(startButton)

        savePromptButton.title = NSLocalizedString("Save Prompt",
            comment: "Button that saves the current code review prompt as the new default")
        savePromptButton.bezelStyle = .rounded
        savePromptButton.target = self
        savePromptButton.action = #selector(savePromptClicked(_:))
        savePromptButton.isEnabled = false
        savePromptButton.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(savePromptButton)

        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let startWidth = max(80, startButton.fittingSize.width)
        let saveWidth = max(100, savePromptButton.fittingSize.width)

        // Title at top.
        let titleY = bounds.maxY - outerInset - titleHeight
        titleLabel.frame = NSRect(x: outerInset,
                                  y: titleY,
                                  width: bounds.width - 2 * outerInset,
                                  height: titleHeight)

        // Bottom row: Save Prompt on the left of Start, both
        // right-aligned.
        let buttonY = outerInset
        let startX = bounds.maxX - outerInset - startWidth
        startButton.frame = NSRect(x: startX,
                                   y: buttonY,
                                   width: startWidth,
                                   height: buttonHeight)
        let saveX = startX - buttonSpacing - saveWidth
        savePromptButton.frame = NSRect(x: saveX,
                                         y: buttonY,
                                         width: saveWidth,
                                         height: buttonHeight)

        // Scroll view fills the middle.
        let scrollTop = titleY - innerSpacing
        let scrollBottom = buttonY + buttonHeight + innerSpacing
        let scrollHeight = max(40, scrollTop - scrollBottom)
        scrollView.frame = NSRect(x: outerInset,
                                  y: scrollBottom,
                                  width: bounds.width - 2 * outerInset,
                                  height: scrollHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(textView)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // CGColor is a snapshot of the resolved color; re-snapshot
        // under the new appearance so the overlay's background stays
        // in sync with the user's light/dark mode toggle.
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if let oldSuperview = superview {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.frameDidChangeNotification,
                object: oldSuperview)
        }
        panelReservationObservation = nil
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let newSuperview = superview {
            newSuperview.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(superviewFrameDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: newSuperview)
            // The right-gutter panel reservation can change without the
            // SessionView frame changing — e.g., when the session finishes
            // setup and instantiates panels after the overlay is already up,
            // or when a panel is toggled by a non-resize path. Observe it
            // directly so the overlay re-insets in those cases.
            if let sessionView = newSuperview as? SessionView {
                panelReservationObservation = sessionView.observe(
                    \.actualPanelReservation,
                    options: [.new]
                ) { [weak self] _, _ in
                    self?.updateFrameFromProvider()
                }
            }
            updateFrameFromProvider()
        }
    }

    @objc private func superviewFrameDidChange(_ notification: Notification) {
        updateFrameFromProvider()
    }

    private func updateFrameFromProvider() {
        guard let provider = frameProvider, superview != nil else { return }
        let target = provider()
        if frame != target {
            frame = target
        }
    }

    // Re-evaluate the frame against the current frameProvider. Called from
    // SessionView.updateLayout so the overlay re-syncs after the toolbar
    // or title strip is added/removed/resized — those don't change the
    // SessionView's own frame, so the frameDidChangeNotification observer
    // doesn't fire for them.
    @objc func sessionViewLayoutDidChange() {
        updateFrameFromProvider()
    }

    @objc private func startClicked(_ sender: Any) {
        let text = textView.string
        onStart?(text)
    }

    @objc private func savePromptClicked(_ sender: Any) {
        let current = textView.string
        iTermPreferences.setString(current, forKey: kPreferenceKeyAIPromptCodeReview)
        savedBaseline = current
        savePromptButton.isEnabled = false
    }

    // Pull the current saved value from prefs into `savedBaseline`
    // and refresh the Save Prompt button's enabled state. Called
    // when the prompt text is replaced wholesale (e.g. when the
    // overlay is presented and prepopulated) so future text changes
    // can be compared against the right baseline.
    fileprivate func reloadBaselineAndUpdateSaveButton() {
        savedBaseline = iTermPreferences.string(forKey: kPreferenceKeyAIPromptCodeReview) ?? ""
        syncSavePromptEnabled()
    }

    // Cheap version: just compare current text to the cached baseline
    // without round-tripping prefs. Used on every keystroke.
    private func syncSavePromptEnabled() {
        savePromptButton.isEnabled = (textView.string != savedBaseline)
    }
}

extension CodeReviewPromptView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        syncSavePromptEnabled()
    }
}

// NSTextView subclass that fires `onSubmit` on Shift+Return. Plain Return
// continues to insert a newline so multiline editing still works. Using
// keyDown: rather than a button keyEquivalent because NSTextView consumes
// Return-family keys as text input before window-level performKeyEquivalent:
// runs against subviews.
private class ShiftReturnSubmittingTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "\r",
           event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}

//
//  CodeReviewPromptView.swift
//  iTerm2SharedARC
//
//  In-session overlay shown before a Code Review-mode workgroup peer
//  starts its program. The user types a free-form prompt; clicking
//  Start invokes `onStart` with the entered text. A pulldown menu
//  exposes the user’s saved prompts (managed via the dedicated
//  CodeReviewPromptManagerWindowController).
//

import AppKit

@objc(iTermCodeReviewPromptView)
class CodeReviewPromptView: iTermLayerBackedSolidColorView {
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
        }
    }

    // The NSView that should receive focus when this overlay is on
    // screen. Exposed so PTYSession.mainResponder can route focus here
    // on peer activation; otherwise PTYTab.setActiveSession’s
    // makeFirstResponder call clobbers the assignment we make in
    // viewDidMoveToWindow.
    @objc var promptResponder: NSView { textView }

    private let scrollView: NSScrollView
    private let textView: ShiftReturnSubmittingTextView
    private let startButton: NSButton
    private let promptMenuButton: NSPopUpButton
    private let titleLabel: NSTextField

    private let outerInset: CGFloat = 16
    private let innerSpacing: CGFloat = 8
    private let buttonSpacing: CGFloat = 12
    private let buttonHeight: CGFloat = 28
    private let titleHeight: CGFloat = 18
    private let menuButtonWidth: CGFloat = 160

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
        promptMenuButton = NSPopUpButton(frame: .zero, pullsDown: true)
        titleLabel = NSTextField(labelWithString: "Code review prompt:")

        super.init(frame: frameRect)

        color = NSColor.windowBackgroundColor
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

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        startButton.title = "Start"
        startButton.bezelStyle = .rounded
        // Shift-Return submits via the text view's keyDown override
        // (set above); plain Return inserts a newline. The button
        // itself has no keyEquivalent because the text view consumes
        // Return as text input before performKeyEquivalent: runs.
        startButton.target = self
        startButton.action = #selector(startClicked(_:))
        startButton.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(startButton)

        promptMenuButton.bezelStyle = .rounded
        promptMenuButton.autoenablesItems = false
        promptMenuButton.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(promptMenuButton)
        rebuildPromptMenu()
        // Lazily refresh per-item enabled state right before the menu
        // opens, instead of recomputing on every keystroke.
        promptMenuButton.menu?.delegate = self

        // Only structural changes (add/remove/rename/reorder) affect
        // what the pulldown shows. Body edits in the manager fire a
        // separate notification that we deliberately ignore.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange(_:)),
            name: CodeReviewPromptStore.structureDidChangeNotification,
            object: nil)

        autoresizingMask = [.width, .height]
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    required init(frame frameRect: NSRect, color: NSColor) {
        it_fatalError("init(frame:color:) is not supported; use init(frame:)")
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let startWidth = max(80, startButton.fittingSize.width)
        let menuWidth = max(menuButtonWidth, promptMenuButton.fittingSize.width)

        // Title at top.
        let titleY = bounds.maxY - outerInset - titleHeight
        titleLabel.frame = NSRect(x: outerInset,
                                  y: titleY,
                                  width: bounds.width - 2 * outerInset,
                                  height: titleHeight)

        // Bottom row: prompts pulldown on the left of Start, both
        // right-aligned.
        let buttonY = outerInset
        let startX = bounds.maxX - outerInset - startWidth
        startButton.frame = NSRect(x: startX,
                                   y: buttonY,
                                   width: startWidth,
                                   height: buttonHeight)
        let menuX = startX - buttonSpacing - menuWidth
        promptMenuButton.frame = NSRect(x: menuX,
                                         y: buttonY,
                                         width: menuWidth,
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

    @objc private func storeDidChange(_ note: Notification) {
        rebuildPromptMenu()
    }

    // MARK: - Pulldown menu

    // Pull-down NSPopUpButtons display item-0's title as the menu’s
    // visible label and never select it on click. Use a fixed “Prompts”
    // header item so the button reads consistently regardless of which
    // saved prompt is currently loaded.
    private func rebuildPromptMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Prompts", action: nil, keyEquivalent: "")

        let store = CodeReviewPromptStore.shared
        if !store.prompts.isEmpty {
            for (index, prompt) in store.prompts.enumerated() {
                let item = NSMenuItem(title: prompt.name,
                                       action: #selector(loadSavedPromptMenuItem(_:)),
                                       keyEquivalent: "")
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let saveItem = NSMenuItem(title: "Save Current as New…",
                                   action: #selector(saveAsNewMenuItem(_:)),
                                   keyEquivalent: "")
        saveItem.target = self
        saveItem.identifier = Self.saveItemIdentifier
        menu.addItem(saveItem)

        let manageItem = NSMenuItem(title: "Manage Prompts…",
                                     action: #selector(manageMenuItem(_:)),
                                     keyEquivalent: "")
        manageItem.target = self
        menu.addItem(manageItem)

        menu.delegate = self
        promptMenuButton.menu = menu
    }

    private static let saveItemIdentifier =
        NSUserInterfaceItemIdentifier("iTermCodeReviewPromptSaveAsNewItem")

    @objc private func loadSavedPromptMenuItem(_ sender: NSMenuItem) {
        let store = CodeReviewPromptStore.shared
        let index = sender.tag
        guard index >= 0, index < store.prompts.count else { return }
        let prompt = store.prompts[index]
        text = prompt.text
        store.lastSelectedUUID = prompt.uuid
    }

    @objc private func saveAsNewMenuItem(_ sender: Any) {
        guard let host = window else { return }
        let alert = NSAlert()
        alert.messageText = "Name this prompt"
        alert.informativeText =
            "Saved prompts can be re-loaded from the Prompts pulldown."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.placeholderString = "Prompt name"
        alert.accessoryView = field

        alert.beginSheetModal(for: host) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let store = CodeReviewPromptStore.shared
            let index = store.add(name: name, text: self.textView.string)
            if index >= 0, index < store.prompts.count {
                store.lastSelectedUUID = store.prompts[index].uuid
            }
        }
        // Focus the input as the sheet finishes presenting.
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
    }

    @objc private func manageMenuItem(_ sender: Any) {
        CodeReviewPromptManagerWindowController.shared.showWindow(parent: window)
    }
}

extension CodeReviewPromptView: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === promptMenuButton.menu else { return }
        let trimmed = textView.string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let canSave = !trimmed.isEmpty
        for item in menu.items where item.identifier == Self.saveItemIdentifier {
            item.isEnabled = canSave
        }
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

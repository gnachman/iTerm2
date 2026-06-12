//
//  RoundedTextField.swift
//  iTerm2
//
//  Created by George Nachman on 2/19/25.
//

//
//  ChatInputTextFieldContainer.swift
//  Modified to use NSTextView with dynamic intrinsic content size
//

import Cocoa

fileprivate let extraHeight = CGFloat(12)
fileprivate let horizontalInset = CGFloat(6)

class ChatInputTextFieldContainer: NSView {
    private let scrollView: NSScrollView = {
        let sv = NSScrollView(frame: .zero)
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        return sv
    }()

    // Translucent backdrop. NSVisualEffectView replaces the older
    // NSGlassEffectView entirely so this container doesn't drag the chat
    // tree into NSGlassEffectView's auto-layout coupling.
    private let backdrop: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.wantsLayer = true
        v.blendingMode = .withinWindow
        v.state = .active
        v.material = .menu
        v.layer?.cornerRadius = 10
        v.layer?.masksToBounds = true
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
        return v
    }()

    private let scrim: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.masksToBounds = true
        return v
    }()

    var maxHeight: CGFloat = 200.0

    let textView: ChatInputTextView = {
        let tv = ChatInputTextView(frame: .zero)
        // Rich text is required so @-mention tokens (ChatSessionMentionAttachment)
        // survive in the storage. Typed text is kept plain via typingAttributes
        // below, and paste is forced to plain text (see ChatInputTextView.paste).
        tv.isRichText = true
        tv.importsGraphics = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        // Keep typed text plain regardless of any attributes carried by an
        // adjacent @-mention token.
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                               .foregroundColor: NSColor.labelColor]
        tv.allowsUndo = true
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        return tv
    }()

    private let layoutJoiner = IdempotentOperationJoiner.asyncJoiner(.main)

    func setNeedsLayoutNow() {
        layoutJoiner.setNeedsUpdate { [weak self] in
            self?.performLayoutNow()
        }
    }
    var placeholder: String? {
        get {
            textView.it_placeholderString
        }
        set {
            textView.it_placeholderString = newValue
        }
    }

    private var _enabled = true
    var isEnabled: Bool {
        get {
            _enabled
        }
        set {
            _enabled = newValue
            textView.isEditable = _enabled
            textView.isSelectable = _enabled
            textView.alphaValue = _enabled ? 1.0 : 0.8
        }
    }

    // The full attributed contents, including any @-mention tokens. Used to
    // save/restore per-chat drafts so a pending message (tokens and all)
    // survives switching chats. The setter resets typing attributes so text
    // typed after a restore stays plain.
    var attributedStringValue: NSAttributedString {
        get {
            // NSTextView.attributedString() hands back the live textStorage by
            // reference, so callers that stash it (e.g. per-chat drafts) would
            // see it mutate as the field changes. Return an immutable snapshot.
            NSAttributedString(attributedString: textView.attributedString())
        }
        set {
            textView.textStorage?.setAttributedString(newValue)
            textView.typingAttributes = [.font: textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                         .foregroundColor: NSColor.labelColor]
            setNeedsLayoutNow()
        }
    }

    // Getter returns the sendable form: each @-mention token is serialized back
    // to "@<guid>" (see NSAttributedString.chatMentionSerialized) while all other
    // runs contribute their literal text. The setter installs plain text only;
    // restored drafts therefore appear as literal text without live tokens.
    var stringValue: String {
        get {
            textView.attributedString().chatMentionSerialized()
        }
        set {
            textView.string = newValue
            textView.typingAttributes = [.font: textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                         .foregroundColor: NSColor.labelColor]
            setNeedsLayoutNow()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        customizeAppearance()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textDidChange(_:)),
                                               name: NSText.didChangeNotification,
                                               object: textView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        customizeAppearance()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textDidChange(_:)),
                                               name: NSText.didChangeNotification,
                                               object: textView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if oldSize != newSize {
            setNeedsLayoutNow()
        }
    }

    // AppKit's pass calls layout() before draw — route through the same
    // method the joiner uses so children are sized in time for the first
    // paint. The async path coalesces re-layouts triggered by text or
    // size changes outside an active layout pass.
    override func layout() {
        super.layout()
        performLayoutNow()
    }

    private func performLayoutNow() {
        guard bounds.width > 0 else { return }

        let backdropFrame = bounds
        if backdrop.frame != backdropFrame {
            backdrop.frame = backdropFrame
        }
        let scrimFrame = bounds
        if scrim.frame != scrimFrame {
            scrim.frame = scrimFrame
        }

        // ScrollView is inset horizontally and vertically; same insets as
        // the original auto-layout setup.
        let scrollFrame = NSRect(x: horizontalInset,
                                 y: extraHeight / 2,
                                 width: max(0, bounds.width - horizontalInset * 2),
                                 height: max(0, bounds.height - extraHeight))
        if scrollView.frame != scrollFrame {
            scrollView.frame = scrollFrame
        }

        // Lay out the text view inside the scroll view's content view.
        // Width fills clip view; height = max(font line height, used rect
        // height) so a blank single line still reserves a full line of
        // room for the cursor. Without the floor, single-line empty
        // content sizes the text view shorter than its drawn cursor and
        // the bottom of the line gets clipped by the scroll view.
        let clipBounds = scrollView.contentView.bounds
        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: clipBounds.width,
                                                 height: CGFloat.greatestFiniteMagnitude)
        }
        var textFrame = textView.frame
        textFrame.origin = .zero
        textFrame.size.width = clipBounds.width
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer).height
            let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
            textFrame.size.height = max(lineHeight, ceil(used))
        }
        if textView.frame != textFrame {
            textView.frame = textFrame
        }
    }

    private func customizeAppearance() {
        frame = NSRect(x: 0, y: 0, width: 100, height: 100)

        addSubview(backdrop)
        addSubview(scrim)

        scrollView.documentView = textView
        // No contentInsets here — performLayoutNow insets the scrollView's
        // frame inside this container (horizontalInset on the sides,
        // extraHeight/2 top and bottom). Using both would double the
        // padding and leave only a sliver of visible text.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init()
        addSubview(scrollView)

        updateScrimColor()
    }

    private func updateScrimColor() {
        scrim.layer?.backgroundColor = effectiveAppearance.it_isDark ?
            NSColor(white: 0, alpha: 0.3).cgColor :
            NSColor(white: 1, alpha: 0.3).cgColor
    }

    @objc private func textDidChange(_ notification: Notification) {
        setNeedsLayoutNow()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateScrimColor()
    }

    // Stable height measurement for a hypothetical content width that does
    // NOT touch our live text container or layout manager. Floored at one
    // line of the configured font so empty / single-line content reserves
    // enough vertical room for the cursor — without this, NSLayoutManager's
    // usedRect under-reports for a single empty line and the scroll view
    // ends up shorter than the text view it contains.
    func preferredHeight(forContentWidth contentWidth: CGFloat) -> CGFloat {
        guard let textStorage = textView.textStorage else {
            return extraHeight
        }
        let measurementWidth = max(0, contentWidth - horizontalInset * 2)
        let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let storage = NSTextStorage(attributedString: textStorage)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: measurementWidth,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
        let textHeight = max(lineHeight, ceil(used.height))
        return min(textHeight + extraHeight, maxHeight)
    }
}

class ChatInputTextView: ShiftEnterTextView {
    var sendAction: Selector?
    weak var sendTarget: AnyObject?

    // Invoked when file URLs are dropped onto the text view. Return true if
    // the drop was fully handled (the text view should insert nothing);
    // return false to fall back to NSTextView's default behavior of inserting
    // the dropped file paths as plain text.
    var onDropFileURLs: (([URL]) -> Bool)?

    // A plain-text NSTextView accepts file drops by inserting their paths as
    // text. Intercept here so the owner can offer to attach backend-supported
    // files instead. We only divert when onDropFileURLs claims the drop;
    // otherwise (or for non-file drags like selected text) the default path is
    // preserved exactly.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let handler = onDropFileURLs,
           let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty,
           handler(urls) {
            return true
        }
        return super.performDragOperation(sender)
    }

    // Bind the undo stack to this text view's lifetime. NSUndoManager holds
    // undo targets unowned(unsafe), so registering text-edit undo on a shared
    // (window) undo manager leaves dangling pointers when the chat — and this
    // text view with it — is deallocated.
    private lazy var privateUndoManager = UndoManager()
    override var undoManager: UndoManager? { privateUndoManager }

    // Don't override keyDown to intercept "\r". AppKit calls insertNewline(_:)
    // (via the delegate's doCommandBy:) only after the input-method client has
    // had a chance to consume the event, so submitting from there lets IMEs
    // commit composing text on Enter without iTerm2 stealing the keystroke.
    // Issue 12867.
    override func insertNewline(_ sender: Any?) {
        if iTermApplication.shared().it_modifierFlags.contains(.shift) {
            super.insertNewline(sender)
            return
        }
        // Plain Enter only reaches here when the delegate declined to submit
        // (e.g. send button disabled). Old behavior was a no-op in that case,
        // so don't insert a newline.
    }

    override func paste(_ sender: Any?) {
        self.pasteAsPlainText(nil)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performFindPanelAction(_:)) &&
            menuItem.tag == NSFindPanelAction.setFindString.rawValue {
            return selectedRanges.count > 0 || selectedRange.length > 0
        }
        return super.validateMenuItem(menuItem)
    }

    override func performFindPanelAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            return
        }
        if menuItem.tag == NSFindPanelAction.setFindString.rawValue {
            let string = (self.string as NSString).substring(with: selectedRange())
            guard !string.isEmpty else {
                return
            }
            iTermSetFindStringNotification(string: string).post()
        }
        super.performFindPanelAction(sender)
    }
}

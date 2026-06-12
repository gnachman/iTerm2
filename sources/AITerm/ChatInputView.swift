//
//  ChatInputView.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

protocol ChatInputViewDelegate: AnyObject {
    func sendButtonClicked(text: String)
    func stopButtonClicked()
    func textDidChange()
}

// ChatInputView (manual layout)
//   NSVisualEffectView (full bounds, pre-macOS 26)
//   horizontal row: [+] [text field] [send]
//   below it (when files attached): horizontal file list
//   hintLabel floats inside the text field's right edge.
@objc
class ChatInputView: NSView, NSTextFieldDelegate {
    private class SendButton: NSButton { }
    private class AddAttachmentButton: NSButton { }

    // Translucent backdrop. Sized to fill self in performLayoutNow so chat
    // bubbles that scroll under the input area (allowed by the scroll
    // view's bottom contentInset) blur behind the controls instead of
    // being solid behind them — improves legibility of the row's text
    // field and buttons against the message stream.
    private let vev: NSVisualEffectView
    private let inputTextFieldContainer = ChatInputTextFieldContainer()
    private var sendButton: SendButton!
    private var addAttachmentButton: AddAttachmentButton!
    private let attachmentsView = HorizontalFileListView()
    private let sendImage: NSImage
    private let stopImage: NSImage
    private var hintLabel: NSTextField!

    // Horizontal row of [+ button, text field, send button]. The text
    // field flexes to fill the available width.
    private var inputRow: ChatManualStackView!
    // Outer column of [input row, attachments strip].
    private var outerColumn: ChatManualStackView!

    weak var delegate: ChatInputViewDelegate?

    // Returns whether the current chat is in orchestration mode. The @-mention
    // session picker only activates when this returns true. Read lazily on every
    // keystroke so runtime orchestration toggles are reflected immediately.
    var orchestrationEnabledProvider: (() -> Bool)?
    private let mentionPicker = ChatMentionPickerController()

    var stoppable = false {
        didSet {
            updateSendButtonEnabled()
        }
    }

    var attachedFiles: [HorizontalFileListView.File] {
        attachmentsView.files
    }

    private static let leftPadding: CGFloat = 16
    private static let rightPadding: CGFloat = 16
    private static let buttonGap: CGFloat = 6
    // Total vertical padding above+below the text field inside the row.
    // Mirrors the constraint cascade in the prior auto-layout build:
    // verticalStack.top = inputTextField.top - 12 with stack.top = self.top
    // forced the row height to be at least textHeight + 24.
    private static let inputRowVerticalPadding: CGFloat = 24

    private var buttonHeight: CGFloat {
        if #available(macOS 26, *) { return 28 }
        return 18
    }

    // iOS-style deferred layout: setNeedsLayoutNow marks dirty, the joiner
    // coalesces marks into a single performLayoutNow on the next runloop
    // tick. No layout work runs synchronously inside an AppKit layout
    // pass — that's how we avoid re-entering the constraint engine via
    // ChatInputTextFieldContainer's auto-layout subtree.
    private let layoutJoiner = IdempotentOperationJoiner.asyncJoiner(.main)

    func setNeedsLayoutNow() {
        layoutJoiner.setNeedsUpdate { [weak self] in
            self?.performLayoutNow()
        }
    }

    init() {
        // Match the symbol size of the + button (pointSize 16, weight
        // .medium). Without this, paperplane.fill renders ~10pt taller
        // than plus, throwing off the row visually.
        let sendConfig: NSImage.SymbolConfiguration?
        if #available(macOS 11.0, *) {
            sendConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        } else {
            sendConfig = nil
        }
        let rawSendImage = NSImage(systemSymbolName: SFSymbol.paperplaneFill.rawValue, accessibilityDescription: "Send")!
        let rawStopImage = NSImage(systemSymbolName: SFSymbol.stopCircleFill.rawValue, accessibilityDescription: "Stop")!
        if #available(macOS 11.0, *), let sendConfig {
            sendImage = rawSendImage.withSymbolConfiguration(sendConfig) ?? rawSendImage
            stopImage = rawStopImage.withSymbolConfiguration(sendConfig) ?? rawStopImage
        } else {
            sendImage = rawSendImage
            stopImage = rawStopImage
        }
        vev = NSVisualEffectView()
        super.init(frame: .zero)

        inputTextFieldContainer.placeholder = "Type a message…"
        inputTextFieldContainer.isEnabled = false
        inputTextFieldContainer.textView.delegate = self
        inputTextFieldContainer.textView.onDropFileURLs = { [weak self] urls in
            self?.handleTextViewFileDrop(urls) ?? false
        }

        sendButton = SendButton(image: sendImage, target: self, action: #selector(sendButtonClicked))
        // .scaleNone keeps the symbol at the configured pointSize. With
        // .scaleProportionallyUpOrDown the symbol would upscale to fill
        // the 28pt-square button, undoing the explicit sizing above.
        sendButton.imageScaling = .scaleNone
        sendButton.imagePosition = .imageOnly
        sendButton.bezelStyle = .regularSquare
        sendButton.isBordered = false
        sendButton.setButtonType(.momentaryPushIn)

        var addImage = NSImage.it_image(forSymbolName: SFSymbol.plus.rawValue,
                                        accessibilityDescription: "Attach files",
                                        fallbackImageName: "plus",
                                        for: ChatInputView.self)!
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            addImage = addImage.withSymbolConfiguration(config)!
        }
        addAttachmentButton = AddAttachmentButton(image: addImage,
                                                  target: self,
                                                  action: #selector(attachmentButtonClicked))
        addAttachmentButton.imageScaling = .scaleNone
        addAttachmentButton.imagePosition = .imageOnly
        addAttachmentButton.bezelStyle = .regularSquare
        addAttachmentButton.isBordered = false
        addAttachmentButton.setButtonType(.momentaryPushIn)
        addAttachmentButton.toolTip = "Attach files"

        attachmentsView.onItemsWillBeDeleted = { _ in true }
        attachmentsView.onDidDeleteItems = { [weak self] in
            self?.updateAttachmentsView()
            self?.updateSendButtonEnabled()
        }

        hintLabel = NSTextField(labelWithString: "↩ to submit")
        hintLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .right

        // Disable autoresizing on every manually-laid-out subview so AppKit's
        // implicit autoresizingMask logic doesn't fight our layout() pass on
        // window resize.
        addAttachmentButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        attachmentsView.translatesAutoresizingMaskIntoConstraints = false
        inputTextFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        vev.wantsLayer = true
        vev.translatesAutoresizingMaskIntoConstraints = false
        vev.blendingMode = .withinWindow
        // .windowBackground blends with the host window's chrome — subtle
        // in both light and dark mode (matches the window's own
        // background) — its job is to obscure bubbles scrolling
        // underneath, not to stand out.
        vev.material = .windowBackground
        vev.state = .active
        addSubview(vev, positioned: .below, relativeTo: nil)

        // Build the input row [+ button, text field, send button] using
        // the manual stack helper. The text field is the flex child — it
        // absorbs all leftover horizontal space so a too-clever intrinsic
        // size on the buttons can't squeeze it down to 10pt.
        inputRow = ChatManualStackView(orientation: .horizontal,
                                       spacing: Self.buttonGap,
                                       alignment: .center)
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputRow.addArrangedSubview(addAttachmentButton)
        inputRow.addArrangedSubview(inputTextFieldContainer)
        inputRow.addArrangedSubview(sendButton)
        inputRow.setFlex(inputTextFieldContainer, true)

        outerColumn = ChatManualStackView(orientation: .vertical,
                                          spacing: 0,
                                          alignment: .fill)
        outerColumn.translatesAutoresizingMaskIntoConstraints = false
        outerColumn.addArrangedSubview(inputRow)
        outerColumn.addArrangedSubview(attachmentsView)

        addSubview(outerColumn)
        addSubview(hintLabel)

        updateAttachmentsView()
        updateSendButtonEnabled()
        setupDragAndDrop()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // intentionally no `intrinsicContentSize` override — that property is
    // an auto-layout protocol and returning a non-noIntrinsicMetric value
    // pulls the whole view tree into the constraint engine. Callers ask
    // for our preferred height through the explicit method below instead.

    // Predict the input view's required height given the container width.
    // Stable for a given (text, attachments, container width) tuple.
    func preferredHeight(forContainerWidth containerWidth: CGFloat) -> CGFloat {
        let textW = predictedTextWidth(forContainerWidth: containerWidth)
        let textH = inputTextFieldContainer.preferredHeight(forContentWidth: textW)
        let rowHeight = max(buttonHeight, textH + Self.inputRowVerticalPadding)
        let attH = attachmentsView.isHidden ? 0 : HorizontalFileListView.preferredHeight
        return rowHeight + attH
    }

    private func predictedTextWidth(forContainerWidth containerWidth: CGFloat) -> CGFloat {
        let stackWidth = max(0, containerWidth - Self.leftPadding - Self.rightPadding)
        let attachW = buttonHeight
        let sendIntrinsic = sendButton.intrinsicContentSize
        let sendBtnW = max(buttonHeight, sendIntrinsic.width > 0 ? sendIntrinsic.width : buttonHeight)
        return max(0, stackWidth - attachW - sendBtnW - Self.buttonGap * 2)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if oldSize != newSize {
            setNeedsLayoutNow()
        }
    }

    // AppKit's layout pass calls layout() before draw — route through the
    // same method the joiner uses, so children are sized in time for the
    // first paint. The joiner's separately-scheduled async will fire later
    // and run performLayoutNow again, which is a no-op when frames are
    // already correct (every assignment is gated on `frame != newFrame`).
    override func layout() {
        super.layout()
        performLayoutNow()
    }

    private func performLayoutNow() {
        guard bounds.width > 0 else { return }

        let outerWidth = max(0, bounds.width - Self.leftPadding - Self.rightPadding)
        let textW = predictedTextWidth(forContainerWidth: bounds.width)
        let textH = inputTextFieldContainer.preferredHeight(forContentWidth: textW)
        let rowHeight = max(buttonHeight, textH + Self.inputRowVerticalPadding)
        let attH: CGFloat = attachmentsView.isHidden ? 0 : HorizontalFileListView.preferredHeight

        // Per-child size overrides for the input row. Flex absorbs the
        // remaining width for the text field, so we just declare its
        // width as 0 (a floor) and the row's flex pass fills it in.
        let buttonH = buttonHeight
        inputRow.sizeOverride = { [weak self] view, _ in
            guard let self else { return nil }
            if view === self.addAttachmentButton || view === self.sendButton {
                return NSSize(width: buttonH, height: buttonH)
            }
            if view === self.inputTextFieldContainer {
                return NSSize(width: 0, height: textH)
            }
            return nil
        }

        outerColumn.sizeOverride = { [weak self] view, _ in
            guard let self else { return nil }
            if view === self.inputRow {
                return NSSize(width: outerWidth, height: rowHeight)
            }
            if view === self.attachmentsView {
                return NSSize(width: outerWidth, height: attH)
            }
            return nil
        }

        let outerHeight = rowHeight + attH
        let outerFrame = NSRect(x: Self.leftPadding,
                                y: 0,
                                width: outerWidth,
                                height: outerHeight)
        if outerColumn.frame != outerFrame {
            outerColumn.frame = outerFrame
        }
        // Force the manual stack to lay out its children synchronously
        // so the hint label can be positioned relative to the (now
        // settled) text field frame in the same pass.
        outerColumn.layout()
        inputRow.layout()

        let textFrameInOuter = inputTextFieldContainer.convert(inputTextFieldContainer.bounds, to: self)

        // Visual effect view: bottom = self bottom, top = top of the text
        // field (no extra space above). Mirrors the Messages app, where
        // the input bar's blur lines up with the entry field's top edge
        // and content scrolls past beneath without an extra blank strip
        // above it.
        let vevFrame = NSRect(x: 0,
                              y: 0,
                              width: bounds.width,
                              height: textFrameInOuter.maxY)
        if vev.frame != vevFrame {
            vev.frame = vevFrame
        }

        // Use sizeToFit so the label gets its rendered size (NSTextField's
        // intrinsicContentSize occasionally rounds the width down by a
        // sub-pixel and the trailing glyph clips). Pad by 1pt for safety.
        hintLabel.sizeToFit()
        let hintFitting = hintLabel.frame.size
        let hintW = ceil(hintFitting.width) + 1
        let hintH = hintFitting.height > 0 ? hintFitting.height : 14
        let hintX = textFrameInOuter.maxX - 12 - hintW
        let hintY = textFrameInOuter.midY - hintH / 2
        let hintFrame = NSRect(x: hintX, y: hintY, width: hintW, height: hintH)
        if hintLabel.frame != hintFrame {
            hintLabel.frame = hintFrame
        }
    }

    private func setupDragAndDrop() {
        registerForDraggedTypes([.fileURL])
    }

    func clear() {
        mentionPicker.hide()
        stringValue = ""
        attachmentsView.files.removeAll()
        updateAttachmentsView()
        updateSendButtonEnabled()
    }

    @objc
    func sendButtonClicked(_ sender: Any) {
        if stoppable {
            delegate?.stopButtonClicked()
        } else {
            delegate?.sendButtonClicked(text: inputTextFieldContainer.stringValue)
        }
    }

    @objc private func attachmentButtonClicked() {
        attachFile()
    }

    @objc private func attachFile() {
        guard let window else {
            return
        }
        let panel = iTermOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        let provider = AITermController.provider
        panel.isSelectable = { remoteFile in
            return provider?.fileTypeIsSupported(extension: remoteFile.name.pathExtension.lowercased()) == true
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else {
                return
            }
            var rejected: [URL] = []
            for item in panel.items {
                guard AITermController.provider?.fileTypeIsSupported(extension: item.filename.pathExtension.lowercased()) == true else {
                    rejected.append(URL(fileURLWithPath: item.filename))
                    continue
                }
                let placeholder = attachmentsView.addPlaceholder(filename: item.filename,
                                                                 isDirectory: item.isDirectory,
                                                                 host: item.host,
                                                                 progress: item.progress) {
                    item.urlPromise.renege()
                }
                item.urlPromise.then { [weak self] url in
                    guard let self else { return }
                    placeholder.graduate(url as URL)
                    updateAttachmentsView()
                    updateSendButtonEnabled()
                }
            }
            if !rejected.isEmpty {
                presentRejectedAttachments(rejected)
            }
            updateAttachmentsView()
            updateSendButtonEnabled()
        }
    }

    func attach(filename: String,
                content: Data,
                mimeType: String) {
        attachmentsView.files.append(.inMemory(filename: filename,
                                               content: content,
                                               mimeType: mimeType))
        updateAttachmentsView()
        updateSendButtonEnabled()
    }

    private func updateSendButtonEnabled() {
        let hasPlaceholder = attachmentsView.files.anySatisfies { $0.isPlaceholder }
        // Mirror sendButtonClicked's whitespace-trim rule: a field
        // containing only spaces / newlines isn't a sendable message,
        // so the button shouldn't be active either. Without this the
        // user can click Send on a whitespace-only field and the click
        // is silently no-oped by the trim in ChatViewController.
        let trimmed = inputTextFieldContainer.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        sendButton.isEnabled = stoppable || (!trimmed.isEmpty && !hasPlaceholder)
        if stoppable {
            sendButton.image = stopImage
            hintLabel.isHidden = true
        } else {
            sendButton.image = sendImage
            hintLabel.isHidden = shouldHideHintLabel()
        }
    }

    private func shouldHideHintLabel() -> Bool {
        let textView = inputTextFieldContainer.textView
        let text = textView.string

        if text.isEmpty {
            return false
        }

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return !text.isEmpty
        }

        let usedRect = layoutManager.usedRect(for: textContainer)
        let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))

        if usedRect.height > lineHeight * 1.5 {
            return true
        }

        let textWidth = usedRect.width
        let hintWidth = hintLabel.intrinsicContentSize.width
        let availableWidth = textView.bounds.width

        let hintStartX = availableWidth - hintWidth - 12
        if textWidth > hintStartX - 20 {
            return true
        }

        return false
    }

    private func updateAttachmentsView() {
        let shouldHide = attachmentsView.files.isEmpty
        if attachmentsView.isHidden != shouldHide {
            attachmentsView.isHidden = shouldHide
            heightDidChange()
        }
    }

    // Notify ourselves and the chat view controller that our preferred
    // height changed. The chat view controller's nextResponder chain
    // walks back to itself; we hop two responder steps (NSView -> next
    // responder, which is the controller) to reach it. Intentionally
    // does NOT call invalidateIntrinsicContentSize — that would engage
    // the constraint engine.
    private func heightDidChange() {
        setNeedsLayoutNow()
        chatViewController?.setNeedsLayoutNow()
    }

    private var chatViewController: ChatViewController? {
        var responder: NSResponder? = self
        while let next = responder?.nextResponder {
            if let vc = next as? ChatViewController {
                return vc
            }
            responder = next
        }
        return nil
    }

    // Called when files are dropped directly onto the text view. A plain-text
    // NSTextView would otherwise insert the file paths as text. For files the
    // current backend can accept as attachments, offer to attach them instead
    // (the choice is rememberable). Returns true if we handled the drop, or
    // false to let the text view insert the paths as before.
    private func handleTextViewFileDrop(_ urls: [URL]) -> Bool {
        let provider = AITermController.provider
        let supported = urls.filter {
            provider?.fileTypeIsSupported(extension: $0.pathExtension.lowercased()) == true
        }
        // Nothing the backend accepts: keep the legacy behavior and let the
        // text view insert every path as text.
        guard !supported.isEmpty else {
            return false
        }
        // Consume the drop now (suppressing the text view's default path
        // insertion) and decide asynchronously: iTermWarning.show with a
        // window spins a nested sheet-modal loop, which would block the drag
        // session if run here inside performDragOperation. Deferring to the
        // next runloop mirrors presentRejectedAttachments' async sheet. When
        // the choice has been remembered the warning returns immediately with
        // no UI, so this just adds an imperceptible one-tick delay.
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            let selection = iTermWarning.show(
                withTitle: dropPromptTitle(for: supported),
                actions: ["Attach", "Insert Path"],
                accessory: nil,
                identifier: "NoSyncAIChatAttachDroppedFile",
                silenceable: .kiTermWarningTypePermanentlySilenceable,
                heading: supported.count == 1 ? "Attach File?" : "Attach Files?",
                window: window)
            if selection == .kiTermWarningSelection0 {
                addFiles(from: supported)
                // Preserve any unsupported files in the same drop by inserting
                // their paths as text, since we consumed the whole drop.
                insertFilePathsAsText(urls.filter { !supported.contains($0) })
            } else {
                // Insert Path: insert every dropped path as text, matching the
                // legacy behavior.
                insertFilePathsAsText(urls)
            }
        }
        return true
    }

    private func dropPromptTitle(for urls: [URL]) -> String {
        if urls.count == 1 {
            return "Add “\(urls[0].lastPathComponent)” to your message as an attachment, or insert its path as text?"
        }
        return "Add the \(urls.count) dropped files to your message as attachments, or insert their paths as text?"
    }

    private func insertFilePathsAsText(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        let textView = inputTextFieldContainer.textView
        let joined = urls.map { $0.path }.joined(separator: " ")
        let range = textView.selectedRange()
        if textView.shouldChangeText(in: range, replacementString: joined) {
            textView.insertText(joined, replacementRange: range)
            textView.didChangeText()
        }
    }

    private func addFiles(from urls: [URL]) {
        let provider = AITermController.provider
        var accepted: [URL] = []
        var rejected: [URL] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if provider?.fileTypeIsSupported(extension: ext) == true {
                accepted.append(url)
            } else {
                rejected.append(url)
            }
        }
        if !rejected.isEmpty {
            presentRejectedAttachments(rejected)
        }
        var attachments = attachmentsView.files
        for url in accepted {
            let path = url.path
            if !attachments.contains(.regular(path)) {
                attachments.append(.regular(path))
            }
        }
        attachmentsView.files = attachments
        updateAttachmentsView()
        updateSendButtonEnabled()
    }

    private func presentRejectedAttachments(_ urls: [URL]) {
        guard let window else { return }
        let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
        let providerName = AITermController.provider?.displayName ?? "the current AI provider"
        let alert = NSAlert()
        alert.messageText = urls.count == 1
            ? "Attachment not supported"
            : "Attachments not supported"
        alert.informativeText = "\(providerName) doesn’t accept this file type as a chat attachment: \(names)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    var isEnabled: Bool {
        get {
            inputTextFieldContainer.isEnabled
        }
        set {
            inputTextFieldContainer.isEnabled = newValue
        }
    }

    var stringValue: String {
        get {
            inputTextFieldContainer.stringValue
        }
        set {
            mentionPicker.hide()
            inputTextFieldContainer.stringValue = newValue
            updateSendButtonEnabled()
            heightDidChange()
        }
    }

    // The attributed input (including @-mention tokens), for saving/restoring a
    // per-chat draft across chat switches.
    var attributedStringValue: NSAttributedString {
        get {
            inputTextFieldContainer.attributedStringValue
        }
        set {
            mentionPicker.hide()
            inputTextFieldContainer.attributedStringValue = newValue
            updateSendButtonEnabled()
            heightDidChange()
        }
    }

    func setAttachedFiles(_ files: [HorizontalFileListView.File]) {
        attachmentsView.files = files
        updateAttachmentsView()
        updateSendButtonEnabled()
    }

    func makeTextViewFirstResponder() {
        window?.makeFirstResponder(inputTextFieldContainer.textView)
    }

    // Surface the @-mention feature where it's available: orchestration chats
    // get a placeholder that advertises it. Call when the chat loads and
    // whenever orchestration is toggled.
    func refreshPlaceholder() {
        let orchestration = orchestrationEnabledProvider?() ?? false
        inputTextFieldContainer.placeholder = orchestration
            ? "Type a message, or @ to mention a session…"
            : "Type a message…"
    }

    private func revealSelectedRange() {
        inputTextFieldContainer.textView.scrollRangeToVisible(inputTextFieldContainer.textView.selectedRange())
    }
}

// MARK: - Drag and Drop Support
extension ChatInputView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard

        guard let urls = pb.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL]
        else {
            return []
        }

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if AITermController.provider?.fileTypeIsSupported(extension: ext) == true {
                return .copy
            }
        }

        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }

        let fileURLs = urls.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }

        guard !fileURLs.isEmpty else {
            return false
        }

        addFiles(from: fileURLs)
        return true
    }
}

extension ChatInputView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // While the @-mention picker is open it owns the arrow/Return/Tab/Escape
        // keys: they drive the list rather than the text view or the send action.
        if mentionPicker.isVisible {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                mentionPicker.moveSelectionDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                mentionPicker.moveSelectionUp()
                return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                mentionPicker.commitSelection()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                mentionPicker.hide()
                return true
            default:
                break
            }
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            && !iTermApplication.shared().it_modifierFlags.contains(.shift)
            && sendButton.isEnabled {
            let wasStoppable = stoppable
            sendButtonClicked(self)
            if wasStoppable && !stoppable {
                sendButtonClicked(self)
            }
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        updateSendButtonEnabled()
        heightDidChange()
        updateMentionPicker()
        delegate?.textDidChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        DispatchQueue.main.async {
            self.revealSelectedRange()
        }
        // Moving the caret (e.g. a click) out of an @-mention context dismisses
        // the picker; moving into one shows it.
        updateMentionPicker()
    }
}

// MARK: - @-mention session picker
extension ChatInputView {
    // A run beginning with "@" immediately before the caret, if any. `atIndex`
    // is the location of the "@"; `query` is the text typed after it (no
    // whitespace, since a space ends the mention being composed).
    private func mentionQueryContext() -> (atIndex: Int, query: String)? {
        let tv = inputTextFieldContainer.textView
        let selection = tv.selectedRange()
        guard selection.length == 0 else {
            return nil
        }
        let caret = selection.location
        let ns = tv.string as NSString
        guard caret <= ns.length else {
            return nil
        }
        let atChar = UInt16(UnicodeScalar("@").value)
        var i = caret
        while i > 0 {
            let c = ns.character(at: i - 1)
            if c == atChar {
                let atIndex = i - 1
                // The "@" must start a word: at the very start, or right after
                // whitespace or another token.
                if atIndex == 0 || isMentionBoundary(ns.character(at: atIndex - 1)) {
                    let query = ns.substring(with: NSRange(location: i, length: caret - i))
                    return (atIndex, query)
                }
                return nil
            }
            // A whitespace/newline or attachment glyph before reaching "@" means
            // the caret isn't inside a mention being composed.
            if isMentionBoundary(c) {
                return nil
            }
            i -= 1
        }
        return nil
    }

    private func isMentionBoundary(_ unichar: unichar) -> Bool {
        if unichar == 0xFFFC {
            // Object replacement character: an existing attachment/token.
            return true
        }
        guard let scalar = UnicodeScalar(unichar) else {
            return false
        }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private func updateMentionPicker() {
        guard orchestrationEnabledProvider?() == true,
              window != nil,
              let context = mentionQueryContext() else {
            mentionPicker.hide()
            return
        }
        if mentionPicker.isVisible {
            mentionPicker.update(query: context.query)
        } else {
            mentionPicker.show(anchorView: inputTextFieldContainer,
                               query: context.query) { [weak self] guid, displayName in
                self?.insertMention(guid: guid, displayName: displayName)
            }
        }
    }

    private func insertMention(guid: String, displayName: String) {
        let tv = inputTextFieldContainer.textView
        guard let context = mentionQueryContext() else {
            return
        }
        let caret = tv.selectedRange().location
        let replaceRange = NSRange(location: context.atIndex, length: caret - context.atIndex)
        let font = tv.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let color = resolvedMentionColor()
        let mention = NSMutableAttributedString(
            attributedString: ChatSessionMentionAttachment.attributedString(
                guid: guid,
                displayName: displayName,
                font: font,
                color: color))
        // A trailing space so the next keystroke isn't swallowed into the token.
        mention.append(NSAttributedString(string: " ",
                                          attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        guard tv.shouldChangeText(in: replaceRange, replacementString: mention.string) else {
            return
        }
        tv.textStorage?.replaceCharacters(in: replaceRange, with: mention)
        tv.didChangeText()
        let newCaret = replaceRange.location + mention.length
        tv.setSelectedRange(NSRange(location: newCaret, length: 0))
        tv.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        updateSendButtonEnabled()
        heightDidChange()
    }

    // The token images bake in the link color resolved for one appearance, so
    // they don't follow a light/dark switch on their own. Re-render every
    // mention token when the effective appearance changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rerenderMentionTokens()
    }

    private func rerenderMentionTokens() {
        let textView = inputTextFieldContainer.textView
        guard let storage = textView.textStorage, storage.length > 0 else {
            return
        }
        let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let color = resolvedMentionColor()
        let fullRange = NSRange(location: 0, length: storage.length)
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let mention = value as? ChatSessionMentionAttachment else {
                return
            }
            mention.renderImage(font: font, color: color)
            ranges.append(range)
        }
        guard !ranges.isEmpty else {
            return
        }
        // Updating an attachment's image doesn't invalidate the layout
        // manager's cached glyph, so force a redraw of each token's range.
        for range in ranges {
            textView.layoutManager?.invalidateDisplay(forCharacterRange: range)
        }
    }

    // The session-link color baked into the token image, resolved for the text
    // view's current appearance so the frozen image matches light/dark.
    private func resolvedMentionColor() -> NSColor {
        var color = NSColor.linkColor
        inputTextFieldContainer.textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.linkColor.usingColorSpace(.sRGB) ?? NSColor.linkColor
        }
        return color
    }
}

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

// ChatInputView
//   NSVisualEffectView
//   ChatViewControllerInputStackView
//     AddAttachmentButton
//     ChatInputTextFieldContainer
//     SendButton
@objc
class ChatInputView: NSView, NSTextFieldDelegate {
    private class ChatInputVerticalStackView: NSStackView {}
    private class ChatInputHorizontalStackView: NSStackView {}
    private class SendButton: NSButton { }
    private class AddAttachmentButton: NSButton { }

    private let vev: NSVisualEffectView?
    private let inputTextFieldContainer = ChatInputTextFieldContainer()
    private var sendButton: SendButton!
    private var addAttachmentButton: AddAttachmentButton!
    private let attachmentsView = HorizontalFileListView()
    private var verticalStack: ChatInputVerticalStackView!
    private let sendImage: NSImage
    private let stopImage: NSImage
    private var hintLabel: NSTextField!

    weak var delegate: ChatInputViewDelegate?
    var stoppable = false {
        didSet {
            updateSendButtonEnabled()
        }
    }

    var attachedFiles: [HorizontalFileListView.File] {
        attachmentsView.files
    }

    init() {
        sendImage = NSImage(systemSymbolName: SFSymbol.paperplaneFill.rawValue, accessibilityDescription: "Send")!
        stopImage = NSImage(systemSymbolName: SFSymbol.stopCircleFill.rawValue, accessibilityDescription: "Stop")!
        if #available(macOS 26, *) {
            vev = nil
        } else {
            vev = NSVisualEffectView()
        }
        super.init(frame: .zero)

        // Input Components
        inputTextFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        inputTextFieldContainer.placeholder = "Type a message…"
        inputTextFieldContainer.isEnabled = false
        inputTextFieldContainer.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        inputTextFieldContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inputTextFieldContainer.textView.delegate = self

        sendButton = SendButton(image: sendImage, target: self, action: #selector(sendButtonClicked))
        if #available(macOS 26, *) {
            // New Tahoe (macOS 26) liquid glass look
            sendButton.imagePosition = .imageOnly
            sendButton.imageScaling = .scaleProportionallyDown
            sendButton.contentTintColor = .it_dynamicColor(forLightMode: NSColor(white: 1, alpha: 0.3),
                                                           darkMode: NSColor(white: 0, alpha: 0.3))
            sendButton.controlSize = .large
            sendButton.bezelStyle = .glass
            sendButton.borderShape = .circle
            sendButton.isBordered = true
            sendButton.showsBorderOnlyWhileMouseInside = true
        } else {
            sendButton.imageScaling = .scaleProportionallyUpOrDown
            sendButton.imagePosition = .imageOnly
            sendButton.bezelStyle = .regularSquare
            sendButton.isBordered = false
        }
        sendButton.setButtonType(.momentaryPushIn)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        var addImage = NSImage.it_image(forSymbolName: SFSymbol.plus.rawValue, accessibilityDescription: "Attach files", fallbackImageName: "plus", for: ChatInputView.self)!
        if #available(macOS 11.0, *) {
            // Create a larger version of the image
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium) // Adjust size as needed
            addImage = addImage.withSymbolConfiguration(config)!
        }
        addAttachmentButton = AddAttachmentButton(image: addImage, target: self, action: #selector(attachmentButtonClicked))
        if #available(macOS 26, *) {
            // New Tahoe (macOS 26) liquid glass look
            addAttachmentButton.imagePosition = .imageOnly
            addAttachmentButton.imageScaling = .scaleProportionallyDown
            addAttachmentButton.contentTintColor = .it_dynamicColor(forLightMode: NSColor(white: 1, alpha: 0.3),
                                                                    darkMode: NSColor(white: 0, alpha: 0.3))
            addAttachmentButton.controlSize = .large
            addAttachmentButton.bezelStyle = .glass
            addAttachmentButton.borderShape = .circle
            addAttachmentButton.isBordered = true
            addAttachmentButton.showsBorderOnlyWhileMouseInside = true
        } else {
            addAttachmentButton.imageScaling = .scaleNone
            addAttachmentButton.imagePosition = .imageOnly
            addAttachmentButton.bezelStyle = .regularSquare
            addAttachmentButton.isBordered = false
        }
        addAttachmentButton.setButtonType(.momentaryPushIn)
        addAttachmentButton.toolTip = "Attach files"
        addAttachmentButton.translatesAutoresizingMaskIntoConstraints = false
        addAttachmentButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        addAttachmentButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        attachmentsView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsView.onItemsWillBeDeleted = { _ in
            return true
        }
        attachmentsView.onDidDeleteItems = { [weak self] in
            self?.updateAttachmentsView()
            self?.updateSendButtonEnabled()
        }
        
        hintLabel = NSTextField(labelWithString: "↩ to submit")
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .right
        hintLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let horizontalStack = ChatInputHorizontalStackView(views: [addAttachmentButton, inputTextFieldContainer, sendButton])
        horizontalStack.orientation = .horizontal
        horizontalStack.spacing = 6
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        horizontalStack.setContentHuggingPriority(.defaultHigh, for: .vertical)

        verticalStack = ChatInputVerticalStackView(views: [horizontalStack, attachmentsView])
        verticalStack.orientation = .vertical
        verticalStack.spacing = 0
        verticalStack.translatesAutoresizingMaskIntoConstraints = false

        if let vev {
            vev.translatesAutoresizingMaskIntoConstraints = false
            vev.wantsLayer = true
            vev.blendingMode = .withinWindow
            vev.material = .underWindowBackground
            vev.state = .active

            addSubview(vev)
        }

        addSubview(verticalStack)
        addSubview(hintLabel)

        let inputStackVerticalInset = CGFloat(12)

        let buttonHeight: CGFloat
        if #available(macOS 26, *) {
            buttonHeight = 28
        } else {
            buttonHeight = 18
        }
        NSLayoutConstraint.activate([
            addAttachmentButton.widthAnchor.constraint(equalToConstant: buttonHeight),
            addAttachmentButton.heightAnchor.constraint(equalToConstant: buttonHeight),

            verticalStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            verticalStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            verticalStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            verticalStack.topAnchor.constraint(equalTo: inputTextFieldContainer.topAnchor,
                                            constant: -inputStackVerticalInset),
            verticalStack.topAnchor.constraint(equalTo: topAnchor),

            horizontalStack.leadingAnchor.constraint(equalTo: verticalStack.leadingAnchor),
            horizontalStack.trailingAnchor.constraint(equalTo: verticalStack.trailingAnchor),

            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: buttonHeight),
            sendButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            sendButton.trailingAnchor.constraint(equalTo: horizontalStack.trailingAnchor),

            hintLabel.trailingAnchor.constraint(equalTo: inputTextFieldContainer.trailingAnchor, constant: -12),
            hintLabel.centerYAnchor.constraint(equalTo: inputTextFieldContainer.centerYAnchor),
        ])
        if let vev {
            NSLayoutConstraint.activate([
                vev.leftAnchor.constraint(equalTo: leftAnchor),
                vev.rightAnchor.constraint(equalTo: rightAnchor),
                vev.bottomAnchor.constraint(equalTo: bottomAnchor),
                vev.heightAnchor.constraint(equalTo: heightAnchor),
            ])
        }
        updateAttachmentsView()
        updateSendButtonEnabled()
        setupDragAndDrop()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setupDragAndDrop() {
        registerForDraggedTypes([.fileURL])
    }

    func clear() {
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
            for item in panel.items {
                guard AITermController.provider?.fileTypeIsSupported(extension: item.filename.pathExtension.lowercased()) == true else {
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
        sendButton.isEnabled = stoppable || (!inputTextFieldContainer.stringValue.isEmpty && !hasPlaceholder)
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

        // Always show hint if empty
        if text.isEmpty {
            return false
        }

        // Hide if multiple lines (text contains newline or has wrapped)
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return !text.isEmpty
        }

        // Check if text spans multiple lines
        let usedRect = layoutManager.usedRect(for: textContainer)
        let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))

        // If content height is greater than one line, hide hint
        if usedRect.height > lineHeight * 1.5 {
            return true
        }

        // Calculate the width of the text to see if it would overlap with hint label
        let textWidth = usedRect.width
        let hintWidth = hintLabel.intrinsicContentSize.width
        let availableWidth = textView.bounds.width

        // Hide if text would be under the hint (leaving some padding)
        let hintStartX = availableWidth - hintWidth - 12 // 12 is the trailing constraint constant
        if textWidth > hintStartX - 20 { // 20px padding buffer
            return true
        }

        return false
    }

    private func updateAttachmentsView() {
        verticalStack.setVisibilityPriority(attachmentsView.files.isEmpty ? .notVisible : .mustHold,
                                            for: attachmentsView)
    }

    private func addFiles(from urls: [URL]) {
        var attachments = attachmentsView.files
        for url in urls {
            let path = url.path
            if !attachments.contains(.regular(path)) {
                attachments.append(.regular(path))
            }
        }
        attachmentsView.files = attachments
        updateAttachmentsView()
        updateSendButtonEnabled()
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
            inputTextFieldContainer.stringValue = newValue
            updateSendButtonEnabled()
        }
    }

    func makeTextViewFirstResponder() {
        window?.makeFirstResponder(inputTextFieldContainer.textView)
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

        // Filter to only include files (not directories)
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
        if commandSelector == #selector(NSResponder.insertNewline(_:)) && sendButton.isEnabled {
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
        delegate?.textDidChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        DispatchQueue.main.async {
            self.revealSelectedRange()
        }
    }
}

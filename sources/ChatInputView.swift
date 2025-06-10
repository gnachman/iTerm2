//
//  ChatInputView.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

protocol ChatInputViewDelegate: AnyObject {
    func sendButtonClicked(text: String)
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

    private let vev = NSVisualEffectView()
    private let inputTextFieldContainer = ChatInputTextFieldContainer()
    private var sendButton: SendButton!
    private var addAttachmentButton: AddAttachmentButton!
    private let attachmentsView = HorizontalFileListView()
    private var verticalStack: ChatInputVerticalStackView!

    weak var delegate: ChatInputViewDelegate?

    var attachedFiles: [HorizontalFileListView.File] {
        attachmentsView.files
    }

    init() {
        super.init(frame: .zero)

        // Input Components
        inputTextFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        inputTextFieldContainer.placeholder = "Type a message…"
        inputTextFieldContainer.isEnabled = false
        inputTextFieldContainer.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        inputTextFieldContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inputTextFieldContainer.textView.delegate = self

        if #available(macOS 11.0, *) {
            if let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send") {
                sendButton = SendButton(image: image, target: self, action: #selector(sendButtonClicked))
                sendButton.imageScaling = .scaleProportionallyUpOrDown
                sendButton.imagePosition = .imageOnly
                sendButton.bezelStyle = .regularSquare
                sendButton.isBordered = false
                sendButton.setButtonType(.momentaryPushIn)
            } else {
                sendButton = SendButton(title: "Send", target: self, action: #selector(sendButtonClicked))
            }
        } else {
            sendButton = SendButton(title: "Send", target: self, action: #selector(sendButtonClicked))
        }
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        var addImage = NSImage.it_image(forSymbolName: "plus", accessibilityDescription: "Attach files", fallbackImageName: "plus", for: ChatInputView.self)!
        if #available(macOS 11.0, *) {
            // Create a larger version of the image
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium) // Adjust size as needed
            addImage = addImage.withSymbolConfiguration(config)!
        }
        addAttachmentButton = AddAttachmentButton(image: addImage, target: self, action: #selector(attachmentButtonClicked))
        addAttachmentButton.imageScaling = .scaleNone
        addAttachmentButton.imagePosition = .imageOnly
        addAttachmentButton.bezelStyle = .regularSquare
        addAttachmentButton.isBordered = false
        addAttachmentButton.setButtonType(.momentaryPushIn)
        addAttachmentButton.toolTip = "Attach files"
        addAttachmentButton.translatesAutoresizingMaskIntoConstraints = false
        addAttachmentButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        addAttachmentButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        addAttachmentButton.imageScaling = .scaleNone

        attachmentsView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsView.onItemsWillBeDeleted = { _ in
            return true
        }
        attachmentsView.onDidDeleteItems = { [weak self] in
            self?.updateAttachmentsView()
            self?.updateSendButtonEnabled()
        }
        let horizontalStack = if iTermAdvancedSettingsModel.openAIResponsesAPI() {
            ChatInputHorizontalStackView(views: [addAttachmentButton, inputTextFieldContainer, sendButton])
        } else {
            ChatInputHorizontalStackView(views: [inputTextFieldContainer, sendButton])
        }
        horizontalStack.orientation = .horizontal
        horizontalStack.spacing = 6
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        horizontalStack.setContentHuggingPriority(.defaultHigh, for: .vertical)

        verticalStack = ChatInputVerticalStackView(views: [horizontalStack, attachmentsView])
        verticalStack.orientation = .vertical
        verticalStack.spacing = 0
        verticalStack.translatesAutoresizingMaskIntoConstraints = false

        vev.translatesAutoresizingMaskIntoConstraints = false
        vev.wantsLayer = true
        vev.blendingMode = .withinWindow
        vev.material = .underWindowBackground
        vev.state = .active

        addSubview(vev)
        addSubview(verticalStack)

        let inputStackVerticalInset = CGFloat(12)

        NSLayoutConstraint.activate([
            addAttachmentButton.widthAnchor.constraint(equalToConstant: 18),
            addAttachmentButton.heightAnchor.constraint(equalToConstant: 18),

            verticalStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            verticalStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            verticalStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            verticalStack.topAnchor.constraint(equalTo: inputTextFieldContainer.topAnchor,
                                            constant: -inputStackVerticalInset),
            verticalStack.topAnchor.constraint(equalTo: topAnchor),

            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            sendButton.trailingAnchor.constraint(equalTo: horizontalStack.trailingAnchor),

            vev.leftAnchor.constraint(equalTo: leftAnchor),
            vev.rightAnchor.constraint(equalTo: rightAnchor),
            vev.bottomAnchor.constraint(equalTo: bottomAnchor),
            vev.heightAnchor.constraint(equalTo: heightAnchor),
        ])

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
        delegate?.sendButtonClicked(text: inputTextFieldContainer.stringValue)
    }

    @objc private func attachmentButtonClicked() {
        // Create the menu
        let menu = NSMenu()

        // Create menu items
        let attachFileItem = NSMenuItem(title: "Attach File",
                                        action: #selector(attachFile),
                                        keyEquivalent: "")
        let shareFolderItem = NSMenuItem(title: "Add Files or Folders to Project",
                                         action: #selector(shareFolder),
                                         keyEquivalent: "")

        // Add items to the menu
        menu.addItem(attachFileItem)
        menu.addItem(shareFolderItem)

        // Show the menu
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: addAttachmentButton)
    }

    @objc private func shareFolder() {

    }

    @objc private func attachFile() {
        guard let window else {
            return
        }
        let panel = iTermOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else {
                return
            }
            for item in panel.items {
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

    private func updateSendButtonEnabled() {
        let hasPlaceholder = attachmentsView.files.anySatisfies { $0.isPlaceholder }
        sendButton.isEnabled = !inputTextFieldContainer.stringValue.isEmpty && !hasPlaceholder
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
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        return .copy
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
            sendButtonClicked(self)
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

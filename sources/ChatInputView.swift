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

        if #available(macOS 11.0, *) {
            if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Attach files") {
                addAttachmentButton = AddAttachmentButton(image: image, target: self, action: #selector(attachmentButtonClicked))
                addAttachmentButton.imageScaling = .scaleProportionallyUpOrDown
                addAttachmentButton.imagePosition = .imageOnly
                addAttachmentButton.bezelStyle = .regularSquare
                addAttachmentButton.isBordered = false
                addAttachmentButton.setButtonType(.momentaryPushIn)
                addAttachmentButton.toolTip = "Attach files"
            } else {
                addAttachmentButton = AddAttachmentButton(title: "+", target: self, action: #selector(attachmentButtonClicked))
            }
        } else {
            addAttachmentButton = AddAttachmentButton(title: "+", target: self, action: #selector(attachmentButtonClicked))
        }
        addAttachmentButton.translatesAutoresizingMaskIntoConstraints = false
        addAttachmentButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        addAttachmentButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        attachmentsView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsView.onItemsWillBeDeleted = { _ in
            return true
        }
        attachmentsView.onDidDeleteItems = { [weak self] in
            self?.updateAttachmentsView()
        }
        let horizontalStack = ChatInputHorizontalStackView(views: [addAttachmentButton, inputTextFieldContainer, sendButton])
        horizontalStack.orientation = .horizontal
        horizontalStack.spacing = 8
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
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    @objc
    func sendButtonClicked(_ sender: Any) {
        delegate?.sendButtonClicked(text: inputTextFieldContainer.stringValue)
    }

    @objc private func attachmentButtonClicked() {
        guard let window else {
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else {
                return
            }
            var attachments = attachmentsView.files
            for url in openPanel.urls {
                let path = url.path
                if !attachments.contains(path) {
                    attachments.append(path)
                }
            }
            attachmentsView.files = attachments
            updateAttachmentsView()
        }
    }

    private func updateAttachmentsView() {
        verticalStack.setVisibilityPriority(attachmentsView.files.isEmpty ? .notVisible : .mustHold,
                                            for: attachmentsView)
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

extension ChatInputView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            sendButtonClicked(self)
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        delegate?.textDidChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        DispatchQueue.main.async {
            self.revealSelectedRange()
        }
    }
}

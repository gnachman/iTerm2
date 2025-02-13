//
//  ChatViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

import AppKit
import SwiftyMarkdown

@objc(iTermChatViewControllerDelegate)
protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ controller: ChatViewController, revealSessionWithGuid guid: String) -> Bool
}

@objc
class ChatViewController: NSViewController {
    private(set) var messages: [Message] = []
    @objc weak var delegate: ChatViewControllerDelegate?
    private(set) var chatID = UUID().uuidString

    private var tableView: NSTableView!
    private var titleLabel = NSTextField()
    private var sessionButton: NSButton!
    private var inputTextField: NSTextField!
    private var sendButton: NSButton!
    private var showTypingIndicator = false {
        didSet {
            if showTypingIndicator == oldValue {
                return
            }
            if showTypingIndicator {
                tableView.insertRows(at: IndexSet(integer: messages.count))
            } else {
                tableView.removeRows(at: IndexSet(integer: messages.count))
            }
            scrollToBottom(animated: true)
        }
    }
    private var eligibleForAutoPaste = true
    private var brokerSubscription: ChatBroker.Subscription?

    deinit {
        brokerSubscription?.unsubscribe()
    }

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))

        // Title Label
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.alignment = .natural
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false

        // Session button
        if #available(macOS 11.0, *) {
            if let image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Send") {
                sessionButton = NSButton(image: image, target: self, action: #selector(sessionButtonClicked))
                sessionButton.imageScaling = .scaleProportionallyDown
                sessionButton.imagePosition = .imageOnly
                sessionButton.bezelStyle = .regularSquare
                sessionButton.isBordered = false
                sessionButton.setButtonType(.momentaryPushIn)
            } else {
                sessionButton = NSButton(title: "Reveal Session", target: self, action: #selector(sessionButtonClicked))
            }
        } else {
            sessionButton = NSButton(title: "Reveal Session", target: self, action: #selector(sessionButtonClicked))
        }
        sessionButton.translatesAutoresizingMaskIntoConstraints = false
        sessionButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sessionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Configure Table View
        tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MessageColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 40
        tableView.backgroundColor = .clear

        // Scroll View for Table
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Input Components
        inputTextField = NSTextField()
        inputTextField.placeholderString = "Type a message…"
        inputTextField.translatesAutoresizingMaskIntoConstraints = false
        inputTextField.delegate = self

        if #available(macOS 11.0, *) {
            if let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send") {
                sendButton = NSButton(image: image, target: self, action: #selector(sendButtonClicked))
                sendButton.imageScaling = .scaleProportionallyDown
                sendButton.imagePosition = .imageOnly
                sendButton.bezelStyle = .regularSquare
                sendButton.isBordered = false
                sendButton.setButtonType(.momentaryPushIn)
            } else {
                sendButton = NSButton(title: "Send", target: self, action: #selector(sendButtonClicked))
            }
        } else {
            sendButton = NSButton(title: "Send", target: self, action: #selector(sendButtonClicked))
        }
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Input Stack
        let inputStack = NSStackView(views: [inputTextField, sendButton])
        inputStack.orientation = .horizontal
        inputStack.spacing = 8
        inputStack.translatesAutoresizingMaskIntoConstraints = false

        // Header stack
        let headerStack = NSStackView(views: [titleLabel, sessionButton])
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // Main Layout including Title
        let mainStack = NSStackView(views: [headerStack, scrollView, inputStack])
        mainStack.orientation = .vertical
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            inputStack.heightAnchor.constraint(equalToConstant: 25),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
        view.alphaValue = 0
        self.view = view
    }
}

extension ChatViewController {
    func load(chatID: String) {
        guard let window = view.window else {
            return
        }
        guard let chat = ChatListModel.instance.chat(id: chatID) else {
            it_fatalError("Loading a nonexistent chat")
        }
        titleLabel.stringValue = chat.title
        self.chatID = chat.id
        self.messages = chat.messages
        tableView.reloadData()
        brokerSubscription?.unsubscribe()
        brokerSubscription = ChatClient.instance.subscribe(chatID: chat.id, registrationProvider: window) { [weak self] update in
            guard let self else {
                return
            }
            switch update {
            case let .delivery(message, _):
                self.messages.append(message)
                self.tableView.insertRows(at: IndexSet(integer: self.messages.count - 1))
            case let .typingStatus(typing, participant):
                switch participant {
                case .user:
                    break
                case .agent:
                    self.showTypingIndicator = typing
                }
                self.scrollToBottom(animated: true)
            }
        }
        view.alphaValue = 1.0
        sessionButton.isHidden = chat.sessionGuid == nil
        showTypingIndicator = TypingStatusModel.instance.isTyping(participant: .agent,
                                                                  chatID: chatID)
        scrollToBottom(animated: false)
        view.window?.makeFirstResponder(inputTextField)
    }

    func offerSelectedText(_ text: String) {
        if eligibleForAutoPaste {
            inputTextField.stringValue = text
        }
    }

    @objc private func sessionButtonClicked() {
        guard let chat = ChatListModel.instance.chat(id: self.chatID),
              let guid = chat.sessionGuid,
              let delegate else {
            return
        }
        if !delegate.chatViewController(self, revealSessionWithGuid: guid) {
            sessionButton.it_showWarning(withMarkdown: "The session that is the subject of this chat is now defunct.")
        }
    }

    @objc private func sendButtonClicked() {
        let text = inputTextField.stringValue
        guard !text.isEmpty else {
            return
        }
        let message = Message(participant: .user,
                              content: .plainText(text),
                              date: Date(),
                              uniqueID: UUID())
        ChatBroker.instance.publish(message: message, toChatID: chatID)

        inputTextField.stringValue = ""
        eligibleForAutoPaste = true
    }

    private func scrollToBottom(animated: Bool) {
        let row = messages.count - 1 + (showTypingIndicator ? 1 : 0)
        guard row >= 0 else { return }

        if !animated {
            tableView.scrollRowToVisible(row)
        } else if let scrollView = tableView.enclosingScrollView {
            let clipView = scrollView.contentView
            let rowRect = tableView.rect(ofRow: row)
            let insetTop = scrollView.contentInsets.top
            let visibleHeight = clipView.bounds.height

            // Ensure we don't scroll too far
            let maxY = tableView.bounds.height - visibleHeight
            let targetY = min(max(rowRect.origin.y - insetTop, 0), maxY)

            clipView.animator().setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: targetY))
        }
    }
}

extension ChatViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        messages.count + (showTypingIndicator ? 1 : 0)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row == messages.count {
            it_assert(showTypingIndicator)
            return TypingIndicatorCellView()
        }
        let message = messages[row]
        let cell = MessageCellView()
        cell.configure(with: message, tableViewWidth: tableView.bounds.width)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if row == messages.count {
            it_assert(showTypingIndicator)
            return 20
        }
        let message = messages[row]
        return MessageCellView.height(for: message,
                                      tableViewWidth: tableView.bounds.width)
    }
}

extension ChatViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            sendButtonClicked()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        eligibleForAutoPaste = inputTextField.stringValue.isEmpty
    }
}

extension Message {
    var linkColor: NSColor {
        return NSColor.white
    }

    var attributedStringValue: NSAttributedString {
        switch content {
        case .plainText(let string):
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
            return NSAttributedString(
                string: string,
                attributes: attributes
            )
        case .markdown(let string):
            return AttributedStringForGPTMarkdown(string, linkColor: linkColor) { }
        case .explanationRequest(request: let request):
            let string =
            if let url = request.url {
                "Explain the output of \(request.subjectMatter) based on [attached terminal content](\(url))."
            } else {
                "Explain the output of \(request.subjectMatter) based on some no-longer-available content."
            }
            return AttributedStringForGPTMarkdown(string, linkColor: linkColor) { }
        case .explanationResponse(let collection):
            it_fatalError("You should never render an explanation response")
        }
    }
}

// MARK: - Custom Cell View

class AutoSizingTextView: ClickableTextView {
    override var intrinsicContentSize: NSSize {
        guard let textContainer = self.textContainer, let layoutManager = self.layoutManager else {
            return super.intrinsicContentSize
        }

        layoutManager.ensureLayout(for: textContainer)

        let rect = layoutManager.usedRect(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                  in: textContainer)
        let size = NSSize(width: ceil(rect.maxX), height: ceil(bounding.maxY))
        return size
    }
}

@objc
fileprivate class TypingIndicatorCellView: NSView {
    private let activityIndicator = NSProgressIndicator()

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Bubble View Setup
        activityIndicator.isIndeterminate = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.style = .spinning
        activityIndicator.controlSize = .regular
        addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            activityIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            activityIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        activityIndicator.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        activityIndicator.startAnimation(nil)
    }
}

@objc
fileprivate class MessageCellView: NSView {
    private let bubbleView = NSView()
    private let textLabel = AutoSizingTextView()
    private var backgroundColorPair: (NSColor, NSColor)?

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Bubble View Setup
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        addSubview(bubbleView)

        // Text Label Setup
        textLabel.isEditable = false
        textLabel.isSelectable = true
        textLabel.drawsBackground = false
        textLabel.isVerticallyResizable = false
        textLabel.isHorizontallyResizable = false
        textLabel.textContainer?.lineFragmentPadding = 0
        textLabel.textContainerInset = .zero
        textLabel.textContainer?.widthTracksTextView = true
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bubbleView.addSubview(textLabel)
    }

    private func updateBackgroundColor() {
        guard let backgroundColorPair else {
            return
        }
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? backgroundColorPair.1 : backgroundColorPair.0).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        updateBackgroundColor()
    }

    private static let topInset = 4.0
    private static let bottomInset = 4.0

    func configure(with message: Message, tableViewWidth: CGFloat) {
        textLabel.linkTextAttributes = [
            .foregroundColor: message.linkColor,
            .underlineColor: message.linkColor ]
        textLabel.textStorage?.setAttributedString(message.attributedStringValue)

        // Configure Bubble
        backgroundColorPair = message.participant == .user ?
            (NSColor.init(fromHexString: "p3#448bf7")!, NSColor.init(fromHexString: "p3#4a93f5")!)  :
            (NSColor.init(fromHexString: "p3#e9e9eb")!, NSColor.init(fromHexString: "p3#3b3b3d")!)
        updateBackgroundColor()

        // Layout Constraints
        let maxBubbleWidth = tableViewWidth * 0.7
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        NSLayoutConstraint.deactivate(constraints)

        let topInset = Self.topInset
        let bottomInset = Self.bottomInset

        if message.participant == .user {
            NSLayoutConstraint.activate([
                bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
                bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset),
                bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth),

                textLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
                textLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
                textLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: topInset),
                textLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -bottomInset)
            ])
        } else {
            NSLayoutConstraint.activate([
                bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
                bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset),
                bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth),

                textLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
                textLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
                textLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: topInset),
                textLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -bottomInset)
            ])
        }
        textLabel.textContainer?.widthTracksTextView = false
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth - 16,
                                               height: .greatestFiniteMagnitude)
    }

    static func height(for message: Message, tableViewWidth: CGFloat) -> CGFloat {
        let hpadding = 16.0
        let vpadding = (topInset + bottomInset) * 2
        let maxBubbleWidth = tableViewWidth * 0.7 - hpadding

        let attributedStringValue = message.attributedStringValue
        return measuredTextHeight(for: attributedStringValue,
                                  maxWidth: maxBubbleWidth,
                                  vpadding: vpadding)
    }

    private static func measuredTextHeight(for attributedString: NSAttributedString,
                                           maxWidth: CGFloat,
                                           vpadding: CGFloat) -> CGFloat {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))

        textContainer.lineFragmentPadding = 0  // Ensure consistent width measurement
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        layoutManager.ensureLayout(for: textContainer)

        let rect = layoutManager.usedRect(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                  in: textContainer)
        let size = NSSize(width: ceil(rect.maxX), height: ceil(bounding.maxY))

        DLog("Measured height for \(attributedString.string) is \(size.height) with \(vpadding) vertical padding")
        return size.height + vpadding
    }
}

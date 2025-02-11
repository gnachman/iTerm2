//
//  ChatViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

import AppKit
import SwiftyMarkdown

enum Participant: String, Codable {
    case user
    case agent
}

struct Message: Codable {
    let participant: Participant
    enum Content: Codable {
        case plainText(String)
        case markdown(String)
    }
    let content: Content
    let date: Date

    var stringValue: String {
        switch content {
        case .plainText(let value), .markdown(let value):
            value
        }
    }
}

@objc(iTermChatViewControllerDelegate)
protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ controller: ChatViewController, didSendMessage text: String)
}

@objc
class ChatViewController: NSViewController {
    private(set) var messages: [Message] = []
    @objc weak var delegate: ChatViewControllerDelegate?
    private var conversation: AIConversation?

    private var tableView: NSTableView!
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

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))

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
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            if let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send") {
                sendButton = NSButton(image: image, target: self, action: #selector(sendButtonClicked))
                sendButton.imageScaling = .scaleProportionallyDown
                sendButton.imagePosition = .imageOnly
                sendButton.bezelStyle = .regularSquare
                sendButton.isBordered = false
                sendButton.setButtonType(.momentaryChange)
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

        // Main Layout
        let mainStack = NSStackView(views: [scrollView, inputStack])
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
        self.view = view
    }

    @objc(appendAgentMessage:)
    public func appendAgentMessage(text: String) {
        let message = Message(participant: .agent, content: .markdown(text), date: Date())
        append(message: message)
    }

    private func append(message: Message) {
        messages.append(message)
        tableView.insertRows(at: IndexSet(integer: messages.count - 1))
        scrollToBottom(animated: true)
    }

    @objc(appendUserMessage:)
    public func appendUserMessage(text: String) {
        let message = Message(participant: .user, content: .plainText(text), date: Date())
        append(message: message)
    }

    @objc
    public func commit() {
        if let window = view.window {
            let messages = messages.map { message in
                let role = switch message.participant {
                case .user: "user"
                case .agent: "assistant"
                }
                return AITermController.Message(role: role, content: message.stringValue)
            }
            conversation = AIConversation(window: window, messages: messages)
        }
    }

    @objc private func sendButtonClicked() {
        let text = inputTextField.stringValue
        guard !text.isEmpty else {
            return
        }
        let message = Message(participant: .user, content: .plainText(text), date: Date())
        messages.append(message)
        inputTextField.stringValue = ""
        tableView.reloadData()
        scrollToBottom(animated: true)
        delegate?.chatViewController(self, didSendMessage: text)
        conversation?.add(text: text, role: "user")
        showTypingIndicator = true
        conversation?.complete { [weak self] result in
            self?.showTypingIndicator = false
            result.handle { updated in
                self?.conversation = updated
                if let text = updated.messages.last?.content {
                    self?.appendAgentMessage(text: text)
                }
            } failure: { error in
                self?.appendAgentMessage(text: "I ran into a problem: \(error.localizedDescription)")
            }

        }
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
}

// MARK: - Serialization

extension ChatViewController {
    private enum CodingKeys: String {
        case messages
    }

    @objc var dictionaryValue: NSDictionary {
        return [CodingKeys.messages.rawValue: try! JSONEncoder().encode(messages)]
    }

    @objc
    func loadChat(from dictionary: NSDictionary) {
        guard let data = dictionary[CodingKeys.messages.rawValue] as? Data else {
            return
        }
        guard let messages = try? JSONDecoder().decode([Message].self, from: data) else {
            return
        }
        self.messages = messages
        tableView.reloadData()
        scrollToBottom(animated: false)
    }
}

extension Message {
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
            return AttributedStringForGPTMarkdown(string) { }
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

//        layoutManager.glyphRange(for: textContainer) // Force layout
//        let rect = layoutManager.usedRect(for: textContainer)
//
//        return rect.height + vpadding

        layoutManager.ensureLayout(for: textContainer)

        let rect = layoutManager.usedRect(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                  in: textContainer)
        let size = NSSize(width: ceil(rect.maxX), height: ceil(bounding.maxY))

        print("Measured height for \(attributedString.string) is \(size.height) with \(vpadding) vertical padding")
        return size.height + vpadding
    }
}

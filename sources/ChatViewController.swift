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
    func chatViewControllerDeleteSession(_ controller: ChatViewController)
}

@objc
class ChatViewController: NSViewController {
    @objc weak var delegate: ChatViewControllerDelegate?
    private(set) var chatID: String? = UUID().uuidString

    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var titleLabel = NSTextField()
    private var sessionButton: NSButton!
    private var inputTextField: NSTextField!
    private var sendButton: NSButton!
    private var showTypingIndicator: Bool {
        get {
            model?.showTypingIndicator ?? false
        }
        set {
            model?.showTypingIndicator = newValue
            scrollToBottom(animated: true)
        }
    }
    private var eligibleForAutoPaste = true
    private var brokerSubscription: ChatBroker.Subscription?
    private var pickSessionPromise: iTermPromise<PTYSession>?
    private var model: ChatViewControllerModel?
    private let listModel: ChatListModel
    private let client: ChatClient
    private let broker: ChatBroker
    private var estimatedCount = 0

    init(listModel: ChatListModel, client: ChatClient, broker: ChatBroker) {
        self.listModel = listModel
        self.client = client
        self.broker = broker
        model = ChatViewControllerModel(listModel: listModel)
        super.init(nibName: nil, bundle: nil)
        model?.delegate = self
    }
    
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
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
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        // Session button
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil) {
            sessionButton = NSButton(image: image, target: nil, action: nil)
            sessionButton.controlSize = .large
            sessionButton.isBordered = false
        } else {
            sessionButton = NSButton(title: "Chat Info", target: nil, action: nil)
        }


        sessionButton.bezelStyle = .badge
        sessionButton.isBordered = false
        sessionButton.target = self
        sessionButton.action = #selector(showSessionButtonMenu(_:))
        sessionButton.sizeToFit()
        sessionButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

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
        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Input Components
        inputTextField = NSTextField()
        inputTextField.placeholderString = "Type a message…"
        inputTextField.translatesAutoresizingMaskIntoConstraints = false
        inputTextField.delegate = self
        inputTextField.isEnabled = false

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
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerStack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // Main Layout including Title
        let mainStack = NSStackView(views: [headerStack, scrollView, inputStack])
        mainStack.orientation = .vertical
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),

            sessionButton.trailingAnchor.constraint(equalTo: headerStack.trailingAnchor),
            sessionButton.widthAnchor.constraint(equalToConstant: 18),
            sessionButton.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            sessionButton.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor),

            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            inputStack.heightAnchor.constraint(equalToConstant: 25),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
        view.alphaValue = 0
        self.view = view
    }
}

extension ChatViewController {
    func load(chatID: String?) {
        guard let window = view.window else {
            return
        }
        let chat: Chat? = if let chatID {
            listModel.chat(id: chatID)
        } else {
            nil
        }
        if let chat {
            model = ChatViewControllerModel(chat: chat, listModel: listModel)
        } else {
            model = nil
        }
        inputTextField.isEnabled = chatID != nil
        model?.delegate = self
        titleLabel.stringValue = chat?.title ?? ""
        self.chatID = chat?.id
        tableView.reloadData()
        brokerSubscription?.unsubscribe()
        if let chat {
            brokerSubscription = client.subscribe(chatID: chat.id, registrationProvider: window) { [weak self] update in
                guard let self, let model else {
                    return
                }
                switch update {
                case let .delivery(message, _):
                    if !message.visibleInClient {
                        let originalCount = model.items.count
                        model.appendMessage(message)
                        if originalCount > 0 {
                            // Might need to disable buttons in the last message.
                            tableView.reloadData(forRowIndexes: IndexSet(integer: model.items.count - 2),
                                                 columnIndexes: IndexSet(integer: 0))
                        }
                    }
                    if case .renameChat(let newName) = message.content {
                        titleLabel.stringValue = newName
                    }
                case let .typingStatus(typing, participant):
                    switch participant {
                    case .user:
                        break
                    case .agent:
                        self.showTypingIndicator = typing
                    }
                }
                self.scrollToBottom(animated: true)
            }
        }
        view.alphaValue = 1.0
        if let chatID {
            showTypingIndicator = TypingStatusModel.instance.isTyping(participant: .agent,
                                                                      chatID: chatID)
        } else {
            showTypingIndicator = false
        }
        scrollToBottom(animated: false)
        view.window?.makeFirstResponder(inputTextField)
    }

    func offerSelectedText(_ text: String) {
        if eligibleForAutoPaste {
            inputTextField.stringValue = text
        }
    }

    func reveal(messageID: UUID) {
        if let i = model?.index(ofMessageID: messageID) {
            scrollRowToCenter(i)
        }
    }

    private func scrollRowToCenter(_ row: Int) {
        let clipView = scrollView.contentView

        guard row >= 0, row < tableView.numberOfRows else {
            return
        }

        let rowRect = tableView.rect(ofRow: row)

        // Convert row rect to clipView's coordinate space
        let rowRectInClipView = tableView.convert(rowRect, to: clipView)

        // Calculate the new origin to center the row
        let newY = rowRectInClipView.midY - (clipView.bounds.height / 2)

        // Ensure we stay within the scrollable area
        let maxY = tableView.bounds.height - clipView.bounds.height
        let constrainedY = max(0, min(newY, maxY))

        // Animate the scroll
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: constrainedY))
        })
    }

    @objc private func showSessionButtonMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Delete Chat", action: #selector(deleteChat(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        if let guid = model?.sessionGuid,
           iTermController.sharedInstance().session(withGUID: guid) != nil {

            menu.addItem(withTitle: "Reveal Linked Session", action: #selector(revealLinkedSession(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Unlink Session", action: #selector(unlinkSession(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())

            let rce = RemoteCommandExecutor.instance
            menu.addItem(withTitle: "Agent can view and modify linked session", action: #selector(setAlwaysAllow(_:)), state: rce.permission(inSessionGuid: guid) == .always ? .on : .off)
            menu.addItem(withTitle: "Keep linked session private from agent", action: #selector(setNeverAllow(_:)), state: rce.permission(inSessionGuid: guid) == .never ? .on : .off)
            menu.addItem(withTitle: "Ask before allowing agent to access linked session", action: #selector(setAsk(_:)), state: rce.permission(inSessionGuid: guid) == .ask ? .on : .off)

            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Help", action: #selector(showLinkedSessionHelp(_:)), keyEquivalent: "")

            // Position the menu just below the button
            let location = NSPoint(x: 0, y: sender.bounds.height)
            menu.popUp(positioning: nil, at: location, in: sender)
        } else {
            menu.addItem(withTitle: "Link Session", action: #selector(objcLinkSession(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Help", action: #selector(showLinkedSessionHelp(_:)), keyEquivalent: "")

            // Position the menu just below the button
            let location = NSPoint(x: 0, y: sender.bounds.height)
            menu.popUp(positioning: nil, at: location, in: sender)
        }
    }

    @objc private func setAlwaysAllow(_ sender: Any) {
        if let guid = model?.sessionGuid {
            RemoteCommandExecutor.instance.setPermission(allowed: true, remember: true, guid: guid)
        }
    }

    @objc private func setNeverAllow(_ sender: Any) {
        if let guid = model?.sessionGuid {
            RemoteCommandExecutor.instance.setPermission(allowed: false, remember: true, guid: guid)
        }
    }

    @objc private func setAsk(_ sender: Any) {
        if let guid = model?.sessionGuid {
            RemoteCommandExecutor.instance.erasePermissions(guid: guid)
        }
    }

    @objc private func objcLinkSession(_ sender: Any) {
        linkSession { _ in }
    }

    private func linkSession(_ completion: @escaping (PTYSession?) -> ()) {
        if let pickSessionPromise {
            SessionSelector.cancel(pickSessionPromise)
        }
        guard let chatID = self.chatID else {
            completion(nil)
            return
        }
        pickSessionPromise = SessionSelector.select()
        let waitingMessage = Message(chatID: chatID,
                                     author: .agent,
                                     content: .clientLocal(ClientLocal(action: .pickingSession)),
                                     sentDate: Date(),
                                     uniqueID: UUID())
        if let pickSessionPromise {
            pickSessionPromise.then {  [weak self] session in
                if let self, let model = self.model {
                    model.sessionGuid = session.guid
                    completion(session)
                    self.pickSessionPromise = nil
                    reloadCell(forMessageID: waitingMessage.uniqueID)
                }
            }

            pickSessionPromise.catchError { [weak self] error in
                self?.pickSessionPromise = nil
                completion(nil)
                self?.reloadCell(forMessageID: waitingMessage.uniqueID)
            }
        }
        broker.publish(message: waitingMessage,
                       toChatID: chatID)
    }

    @objc private func showLinkedSessionHelp(_ sender: Any) {
        sessionButton.it_showWarning(withMarkdown: "When a terminal session is linked to this chat, the AI may view terminal contents and run commands in that session. You will be prompted to grant permission before it is able to view, type to, or modify a terminal session.")
    }

    @objc private func deleteChat(_ sender: Any) {
        delegate?.chatViewControllerDeleteSession(self)
    }
    @objc private func revealLinkedSession(_ sender: Any) {
        if let guid = model?.sessionGuid {
            _ = delegate?.chatViewController(self, revealSessionWithGuid: guid)
        }
    }

    @objc private func unlinkSession(_ sender: Any) {
        if let chatID {
            listModel.setGuid(for: chatID, to: nil)
        }
    }

    @objc private func sendButtonClicked() {
        let text = inputTextField.stringValue
        guard !text.isEmpty, let chatID else {
            return
        }
        let message = Message(chatID: chatID,
                              author: .user,
                              content: .plainText(text),
                              sentDate: Date(),
                              uniqueID: UUID())
        broker.publish(message: message, toChatID: chatID)

        inputTextField.stringValue = ""
        eligibleForAutoPaste = true
    }

    private func scrollToBottom(animated: Bool) {
        guard let model else {
            return
        }
        let row = model.items.count - 1
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
        guard let model else {
            estimatedCount = 0
            return 0
        }
        DLog("report \(model.items.count) items in table view")
        estimatedCount = model.items.count
        return model.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let model else {
            return nil
        }
        let view = view(forItem: model.items[row], isLastMessage: model.indexIsLastMessage(row))
        DLog("Return view of class \(type(of: view)) for row \(row))")
        return view
    }

    private func view(forItem item: ChatViewControllerModel.Item, isLastMessage: Bool) -> NSView {
        switch item {
        case .agentTyping:
            return TypingIndicatorCellView()
        case .date(let date):
            let view = DateCellView()
            view.set(dateComponents: date)
            return view
        case .message(let message):
            let cell = MessageCellView()
            configure(cell: cell, for: message, isLast: isLastMessage)
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    private func reloadCell(forMessageID messageID: UUID) {
        if let model, let i = model.index(ofMessageID: messageID) {
            tableView.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integer: 0))
        }
    }

    private func edit(_ messageID: UUID) {
        guard let model,
              let i = model.index(ofMessageID: messageID),
              case .message(let message) = model.items[i],
               case .plainText(let text) = message.content else {
            return
        }
        model.deleteFrom(index: i)
        inputTextField.stringValue = text
    }

    private func configure(cell: MessageCellView, for message: Message, isLast: Bool) {
        cell.configure(with: rendition(for: message, isLast: isLast),
                       tableViewWidth: tableView.bounds.width)
        cell.editButtonClicked = { [weak self] messageID in
            self?.edit(messageID)
        }
        let originalMessageID = message.uniqueID
        let chatID = self.chatID
        switch message.content {
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession:
                cell.buttonClicked = { [weak self] identifier, messageID in
                    guard let self else {
                        return
                    }
                    guard messageID == originalMessageID else {
                        return
                    }
                    if let pickSessionPromise {
                        SessionSelector.cancel(pickSessionPromise)
                        self.pickSessionPromise = nil
                    }
                }
            case .executingCommand:
                cell.buttonClicked = { [weak self] identifier, messageID in
                    if let model = self?.model, let guid = model.sessionGuid,
                       let session = iTermController.sharedInstance().session(withGUID: guid) {
                        session.cancelRemoteCommand()
                    }
                }
            }
        case .selectSessionRequest(let originalMessage):
            cell.buttonClicked = { [weak self] identifier, messageID in
                guard let self else {
                    return
                }
                guard messageID == originalMessageID else {
                    return
                }
                switch PickSessionButtonIdentifier(rawValue: identifier) {
                case .cancel, .none:
                    return
                case .pickSession:
                    break
                }
                linkSession { session in
                    if let chatID {
                        if session != nil {
                            self.client.publish(message: originalMessage, toChatID: chatID)
                        } else {
                            self.client.respondSuccessfullyToRemoteCommandRequest(
                                inChat: chatID,
                                requestUUID: originalMessage.uniqueID,
                                message: "The user declined to allow this function call to execute.",
                                functionCallName: originalMessage.functionCallName ?? "Unknown function call name")
                        }
                    }
                }
            }
        case .remoteCommandRequest(let remoteCommand):
            cell.buttonClicked = { identifier, messageID in
                guard messageID == originalMessageID else {
                    return
                }
                guard let chatID,
                      let guid = self.listModel.chat(id: chatID)?.sessionGuid,
                      let session = iTermController.sharedInstance().session(withGUID: guid) else {
                    return
                }
                var allowed = false
                switch RemoteCommandButtonIdentifier(rawValue: identifier) {
                case .allowOnce:
                    RemoteCommandExecutor.instance.setPermission(allowed: true, remember: false, guid: guid)
                    allowed = true
                case .allowAlways:
                    RemoteCommandExecutor.instance.setPermission(allowed: true, remember: true, guid: guid)
                    allowed = true
                case .denyOnce:
                    RemoteCommandExecutor.instance.setPermission(allowed: false, remember: false, guid: guid)
                case .denyAlways:
                    RemoteCommandExecutor.instance.setPermission(allowed: false, remember: true, guid: guid)
                case .none:
                    return
                }
                if allowed {
                    self.client.performRemoteCommand(remoteCommand,
                                                     in: session,
                                                     chatID: chatID,
                                                     messageUniqueID: messageID)
                } else {
                    self.client.respondSuccessfullyToRemoteCommandRequest(
                        inChat: chatID,
                        requestUUID: messageID,
                        message: "The user declined to allow function calling. Try to find another way to assist.",
                        functionCallName: remoteCommand.llmMessage.function_call?.name ?? "Unknown function call name")
                }
            }
        default:
            cell.buttonClicked = nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let model else {
            return 0
        }
        let item = model.items[row]
        let prototypeCell = view(forItem: item, isLastMessage: model.indexIsLastMessage(row))
        prototypeCell.frame = NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 0)
        prototypeCell.layoutSubtreeIfNeeded()

        let height = prototypeCell.fittingSize.height
        return height
    }

    private func rendition(for message: Message, isLast: Bool) -> MessageRendition {
        var enableButtons = isLast
        var editable = false
        switch message.content {
        case .plainText:
            editable = message.author == .user
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession:
                if pickSessionPromise == nil {
                    enableButtons = false
                }
            case .executingCommand:
                if let model,
                   let guid = model.sessionGuid,
                   let session = iTermController.sharedInstance().session(withGUID: guid) {
                    if !session.isExecutingRemoteCommand {
                        enableButtons = false
                    }
                }
            }
        default:
            break
        }
        let timestamp = {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: message.sentDate)
        }()
        return MessageRendition(attributedString: message.attributedStringValue,
                                buttons: message.buttons,
                                messageUniqueID: message.uniqueID,
                                isUser: message.author == .user,
                                enableButtons: enableButtons,
                                timestamp: timestamp,
                                isEditable: editable)
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

fileprivate enum RemoteCommandButtonIdentifier: String {
    case allowOnce
    case allowAlways
    case denyOnce
    case denyAlways
}

fileprivate enum PickSessionButtonIdentifier: String {
    case pickSession
    case cancel
}

extension Message {
    var linkColor: NSColor {
        return NSColor.white
    }

    var buttons: [MessageRendition.Button] {
        switch content {
        case .plainText, .markdown, .explanationRequest, .explanationResponse, .remoteCommandResponse, .renameChat:
            []
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession, .executingCommand:
                [.init(title: "Cancel", color: .red, identifier: "")]
            }
        case .selectSessionRequest:
            [.init(title: "Pick Session", color: .white, identifier: PickSessionButtonIdentifier.pickSession.rawValue),
             .init(title: "Cancel", color: .red, identifier: PickSessionButtonIdentifier.cancel.rawValue)]
        case .remoteCommandRequest:
            [.init(title: "Allow Once", color: .white, identifier: RemoteCommandButtonIdentifier.allowOnce.rawValue),
             .init(title: "Always Allow", color: .white, identifier: RemoteCommandButtonIdentifier.allowAlways.rawValue),
             .init(title: "Deny this Time", color: .red, identifier: RemoteCommandButtonIdentifier.denyOnce.rawValue),
             .init(title: "Always Deny", color: .red, identifier: RemoteCommandButtonIdentifier.denyAlways.rawValue)]
        }
    }

    var attributedStringValue: NSAttributedString {
        switch content {
        case .renameChat:
            it_fatalError()
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
            #warning("TODO: Show the copied toast")
            return AttributedStringForGPTMarkdown(string, linkColor: linkColor) { }
        case .explanationRequest(request: let request):
            let string =
            if let url = request.url {
                "Explain the output of \(request.subjectMatter) based on [attached terminal content](\(url))."
            } else {
                "Explain the output of \(request.subjectMatter) based on some no-longer-available content."
            }
            return AttributedStringForGPTMarkdown(string, linkColor: linkColor) { }
        case .explanationResponse:
            it_fatalError("You should never render an explanation response")
        case .remoteCommandRequest(let request):
            return AttributedStringForGPTMarkdown(request.permissionDescription,
                                                  linkColor: linkColor) {}
        case .remoteCommandResponse(let response, _, _):
            switch response {
            case .success(let object):
                it_fatalError("\(object)")
            case .failure(let error):
                return AttributedStringForGPTMarkdown(error.localizedDescription,
                                                      linkColor: linkColor) {}
            }
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession:
                return AttributedStringForGPTMarkdown("Waiting for a session to be selected…") { }
            case .executingCommand(let command):
                return AttributedStringForGPTMarkdown(command.markdownDescription) { }

            }
        case .selectSessionRequest:
            return AttributedStringForGPTMarkdown("The AI agent needs to run commands in a live terminal session, but none is attached to this chat.", didCopy: {})
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
            heightAnchor.constraint(equalToConstant: 20.0)
        ])
        activityIndicator.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        activityIndicator.startAnimation(nil)
    }
}

extension ChatViewController: ChatViewControllerModelDelegate {
    func chatViewControllerModel(didInsertItemAtIndex i: Int) {
        DLog("Insert tableview row at \(i)")
        estimatedCount += 1
        it_assert(i <= estimatedCount)
        tableView.insertRows(at: IndexSet(integer: i))
    }
    
    func chatViewControllerModel(didRemoveItemsInRange range: Range<Int>) {
        DLog("Remove tableview row at \(range)")
        it_assert(range.upperBound <= estimatedCount)
        estimatedCount -= range.count
        tableView.removeRows(at: IndexSet(ranges: [range]))
    }
}

extension NSMenu {
    func addItem(withTitle title: String, action: Selector, state: NSControl.StateValue) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = state
        addItem(item)
    }
}

protocol ChatViewControllerModelDelegate: AnyObject {
    func chatViewControllerModel(didInsertItemAtIndex: Int)
    func chatViewControllerModel(didRemoveItemsInRange range: Range<Int>)
}

class NotifyingArray<Element> {
    private var storage = [Element]()

    var didInsert: ((Int) -> ())?
    var didRemove: ((Range<Int>) -> ())?

    func append(_ element: Element) {
        storage.append(element)
        DLog("Insert \(element)")
        didInsert?(storage.count - 1)
    }

    func removeLast(_ n: Int = 1) {
        DLog("Remove \(String(describing: storage.last))")
        let count = storage.count
        storage.removeLast(n)
        didRemove?((count - n)..<count)
    }

    var last: Element? {
        storage.last
    }

    func firstIndex(where test: (Element) -> Bool) -> Int? {
        return storage.firstIndex(where: test)
    }

    subscript(_ index: Int) -> Element {
        storage[index]
    }

    var count: Int {
        storage.count
    }
}

class ChatViewControllerModel {
    weak var delegate: ChatViewControllerModelDelegate?
    private let listModel: ChatListModel

    enum Item {
        case message(Message)
        case date(DateComponents)
        case agentTyping
    }

    private(set) var items = NotifyingArray<Item>()
    private let chatID: String

    var showTypingIndicator = false {
        didSet {
            if showTypingIndicator == oldValue {
                return
            }
            if showTypingIndicator {
                items.append(.agentTyping)
            } else if case .agentTyping = items.last {
                items.removeLast()
            }
        }
    }

    var sessionGuid: String? {
        get {
            listModel.chat(id: chatID)?.sessionGuid
        }
        set {
            listModel.setGuid(for: chatID, to: newValue)
        }
    }

    init(listModel: ChatListModel) {
        self.listModel = listModel
        chatID = ""
        initializeItemsDelegate()
    }

    private let alwaysAppendDate = false

    init(chat: Chat, listModel: ChatListModel) {
        self.listModel = listModel
        chatID = chat.id
        var lastDate: DateComponents?
        if let messages = listModel.messages(forChat: chatID, createIfNeeded: false) {
            for message in messages {
                if message.visibleInClient {
                    continue
                }
                let date = message.dateErasingTime
                if alwaysAppendDate || lastDate != date {
                    items.append(.date(date))
                }
                items.append(.message(message))
                lastDate = Calendar.current.dateComponents([.year, .month, .day], from: message.sentDate)
            }
        }
        initializeItemsDelegate()
    }

    private func initializeItemsDelegate() {
        items.didInsert = { [weak self] i in
            self?.delegate?.chatViewControllerModel(didInsertItemAtIndex: i)
        }
        items.didRemove = { [weak self] range in
            self?.delegate?.chatViewControllerModel(didRemoveItemsInRange: range)
        }
    }

    func appendMessage(_ message: Message) {
        let saved = showTypingIndicator
        showTypingIndicator = false
        defer {
            showTypingIndicator = saved
        }
        if let last = items.last,
           case .message(let lastMessage) = last,
           (alwaysAppendDate || message.dateErasingTime != lastMessage.dateErasingTime) {
            items.append(.date(message.dateErasingTime))
        }
        items.append(.message(message))
    }

    func indexIsLastMessage(_ i: Int) -> Bool {
        if case .message = items[i] {
            for j in (i + 1)..<items.count {
                if case .message = items[j] {
                    return false
                }
            }
            return true
        } else {
            return false
        }
    }

    func index(ofMessageID messageID: UUID) -> Int? {
        return items.firstIndex {
            switch $0 {
            case .message(let candidate):
                return candidate.uniqueID == messageID
            default:
                return false
            }
        }
    }

    func deleteFrom(index i: Int) {
        items.removeLast(items.count - i)
    }
}

extension Message {
    var dateErasingTime: DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: sentDate)
    }
}

//
//  ChatViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

import AppKit
import SwiftyMarkdown
import UniformTypeIdentifiers

@objc(iTermChatViewControllerDelegate)
protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ controller: ChatViewController, revealSessionWithGuid guid: String) -> Bool
    func chatViewControllerDeleteSession(_ controller: ChatViewController)
}

@objc class WebSearchButton: NSButton { }

@objc
class ChatViewController: NSViewController {
    @objc weak var delegate: ChatViewControllerDelegate?
    private(set) var chatID: String? = UUID().uuidString

    private let inputView = ChatInputView()
    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var titleLabel = NSTextField()
    private var sessionButton: NSButton!
    private var webSearchButton: WebSearchButton?
    private var sendButton: NSButton!
    private var showTypingIndicator: Bool {
        get {
            model?.showTypingIndicator ?? false
        }
        set {
            model?.showTypingIndicator = newValue
            if showTypingIndicator {
                scrollToBottom(animated: true)
            }
        }
    }
    private var eligibleForAutoPaste = true
    private var brokerSubscription: ChatBroker.Subscription?
    private var pickSessionPromise: iTermPromise<PTYSession>?
    private var model: ChatViewControllerModel?
    private let listModel: ChatListModel
    private let client: ChatClient
    private var estimatedCount = 0
    private var _commandDidExitObserver: (any NSObjectProtocol)?
    private(set) var streaming = false {
        didSet {
            if let _commandDidExitObserver {
                NotificationCenter.default.removeObserver(_commandDidExitObserver)
                self._commandDidExitObserver = nil
            }
            if streaming, let model, model.sessionGuid != nil {
                _commandDidExitObserver = NotificationCenter.default.addObserver(
                    forName: Notification.Name.PTYCommandDidExit,
                    object: nil,
                    queue: nil) { [weak self] notif in
                        if let self,
                           self.streaming,
                           let userInfo = notif.userInfo,
                           let guid = self.model?.sessionGuid,
                           notif.object as? String == guid {
                            self.streamLastCommand(userInfo)
                    }
                }
            }
        }
    }
    var sessionGuid: String? { model?.sessionGuid }
    private let userDefaultsObserver = iTermUserDefaultsObserver()

    init(listModel: ChatListModel, client: ChatClient) {
        self.listModel = listModel
        self.client = client
        super.init(nibName: nil, bundle: nil)

        userDefaultsObserver.observeKey(kPreferenceKeyAIFeatureHostedWebSearch) { [weak self] in
            self?.webSearchButton?.isEnabled = (AITermController.provider?.supportsHostedWebSearch == true)
        }
    }
    
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        brokerSubscription?.unsubscribe()
    }

    private var lastTableViewWidth: CGFloat?
    override func viewWillLayout() {
        super.viewWillLayout()
        let tableViewWidth = tableView.bounds.width
        if tableViewWidth != lastTableViewWidth {
            lastTableViewWidth = tableViewWidth
            // I tried updating constraints but of course it does crazy stuff. Some day when I have
            // more ability to suffer abuse from auto layout I should revisit this. On the other
            // hand, I have to recalculate height for every row so it might not make much of a
            // difference anyway.
            tableView.reloadData()
            tableView.invalidateIntrinsicContentSize()
        }
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
            sessionButton.imageScaling = .scaleProportionallyUpOrDown
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

        if #available(macOS 11.0, *) {
            let webSearchButton = WebSearchButton(image: NSImage.it_image(forSymbolName: "globe",
                                                                          accessibilityDescription: "Web search image",
                                                                          fallbackImageName: "globe",
                                                                          for: Self.self),
                                                  target: nil,
                                                  action: nil)
            webSearchButton.imageScaling = .scaleProportionallyUpOrDown
            webSearchButton.controlSize = .large
            webSearchButton.contentTintColor = webSearchEnabled ? .controlAccentColor : nil
            webSearchButton.isBordered = false
            webSearchButton.bezelStyle = .badge
            webSearchButton.isBordered = false
            webSearchButton.target = self
            webSearchButton.action = #selector(toggleWebSearch(_:))
            webSearchButton.sizeToFit()
            webSearchButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            webSearchButton.translatesAutoresizingMaskIntoConstraints = false
            webSearchButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            webSearchButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            webSearchButton.toolTip = "Allow AI to perform web search?"
            self.webSearchButton = webSearchButton
        }
        webSearchButton?.isEnabled = (AITermController.provider?.supportsHostedWebSearch == true)

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
        tableView.focusRingType = .none
        tableView.translatesAutoresizingMaskIntoConstraints = false

        class ChatViewControllerDocumentView: NSView {
            override func setFrameSize(_ newSize: NSSize) {
                DLog("About to change document view frame size from \(frame.size) to \(newSize). Will adjust clip view's bounds accordingly")
                enclosingScrollView?.performWithoutScrolling {
                    super.setFrameSize(newSize)
                }
            }
        }
        let documentView = ChatViewControllerDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(tableView)

        class ChatViewControllerSpacerView: NSView {}
        let spacer = ChatViewControllerSpacerView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(spacer)

        // Scroll View for Table
        scrollView = NSScrollView()
        scrollView.contentView = NSClipView()
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        inputView.delegate = self
        inputView.translatesAutoresizingMaskIntoConstraints = false

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        headerSpacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        // Header stack
        class ChatViewControllerHeaderStackView: NSStackView {}
        let headerStack = ChatViewControllerHeaderStackView(views: [titleLabel, headerSpacer, webSearchButton, sessionButton].compactMap { $0 })
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerStack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        class ChatViewControllerInnerContainer: NSView {}
        let innerContainer = ChatViewControllerInnerContainer()
        innerContainer.addSubview(scrollView)
        innerContainer.addSubview(inputView)
        innerContainer.translatesAutoresizingMaskIntoConstraints = false

        // Main Layout including Title
        class ChatViewControllerMainStackView: NSStackView {}
        let mainStack = ChatViewControllerMainStackView(views: [headerStack, innerContainer])
        mainStack.orientation = .vertical
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        let mainStackInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        class ChatViewControllerDividerView: GradientView {}
        let divider = ChatViewControllerDividerView(
            gradient: .init(
                stops: [
                    .init(
                        color: .it_dynamicColor(
                            forLightMode: .init(fromHexString: "#f2f2f2")!,
                            darkMode: .init(fromHexString: "#161616")!), location: 0.25),
                    .init(
                        color: .it_dynamicColor(
                            forLightMode: .init(fromHexString: "#e3e3e3")!,
                            darkMode: .init(fromHexString: "#0b0b0b")!), location: 0.75)]))
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor, constant: 8),
            headerStack.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -8),

            divider.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: scrollView.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            sessionButton.widthAnchor.constraint(equalToConstant: 18),
            sessionButton.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            sessionButton.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor),

            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: mainStackInsets.left),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -mainStackInsets.right),
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: mainStackInsets.top),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -mainStackInsets.bottom),

            innerContainer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            innerContainer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            innerContainer.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            innerContainer.topAnchor.constraint(equalTo: scrollView.topAnchor),

            innerContainer.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            innerContainer.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: documentView.topAnchor),
            tableView.leftAnchor.constraint(equalTo: documentView.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: documentView.rightAnchor),

            tableView.bottomAnchor.constraint(equalTo: spacer.topAnchor),

            spacer.leftAnchor.constraint(equalTo: documentView.leftAnchor),
            spacer.rightAnchor.constraint(equalTo: documentView.rightAnchor),
            spacer.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            inputView.leftAnchor.constraint(equalTo: documentView.leftAnchor),
            inputView.rightAnchor.constraint(equalTo: documentView.rightAnchor),
            inputView.bottomAnchor.constraint(equalTo: innerContainer.bottomAnchor),
            inputView.heightAnchor.constraint(equalTo: spacer.heightAnchor),
        ])
        if let webSearchButton {
            NSLayoutConstraint.activate([
                webSearchButton.widthAnchor.constraint(equalToConstant: 18),
                webSearchButton.topAnchor.constraint(equalTo: titleLabel.topAnchor),
                webSearchButton.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            ])
        }
        view.alphaValue = 0
        self.view = view
    }
}

extension Message {
    var shouldCauseScrollToBottom: Bool {
        switch content {
        case .append, .commit:
            false
        case .explanationResponse(_, let update, markdown: _):
            update == nil
        default:
            true
        }
    }
}

extension ChatViewController {
    func load(chatID: String?) {
        if streaming {
            stopStreaming()
        }
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
        inputView.isEnabled = chatID != nil
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
                var shouldScroll = true
                switch update {
                case let .delivery(message, _):
                    shouldScroll = message.shouldCauseScrollToBottom
                    if !message.hiddenFromClient {
                        model.appendMessage(message)
                    } else if case .commit = message.content {
                        model.commit()
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
                        shouldScroll = typing
                    }
                }
                if shouldScroll {
                    DLog("Schedule scroll to bottom")
                    DispatchQueue.main.async { [weak self] in
                        DLog("Scroll to bottom")
                        self?.scrollToBottom(animated: true)
                    }
                }
            }
        }
        view.alphaValue = 1.0
        if let chatID {
            showTypingIndicator = TypingStatusModel.instance.isTyping(participant: .agent,
                                                                      chatID: chatID)
        } else {
            showTypingIndicator = false
        }
        if let chatID, let model, model.lastStreamingState == .active {
            ChatClient.instance?.publishClientLocalMessage(
                chatID: chatID,
                action: .streamingChanged(.stoppedAutomatically))
            model.lastStreamingState = .stoppedAutomatically
        }
        scrollToBottom(animated: false)
        inputView.makeTextViewFirstResponder()
    }

    func attach(filename: String,
                content: Data,
                mimeType: String) {
        inputView.attach(filename: filename, content: content, mimeType: mimeType)
        inputView.makeTextViewFirstResponder()
    }

    func offerSelectedText(_ text: String) {
        if eligibleForAutoPaste {
            inputView.stringValue = text
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
        guard let chatID else {
            return
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Delete Chat", action: #selector(deleteChat(_:)), target: self)
        menu.addItem(NSMenuItem.separator())
        if let guid = model?.sessionGuid,
           iTermController.sharedInstance().session(withGUID: guid) != nil {

            menu.addItem(withTitle: "Reveal Linked Session", action: #selector(revealLinkedSession(_:)), target: self)
            menu.addItem(withTitle: "Unlink Session", action: #selector(unlinkSession(_:)), target: self)
            menu.addItem(NSMenuItem.separator())

            let rce = RemoteCommandExecutor.instance
            for category in RemoteCommand.Content.PermissionCategory.allCases {
                menu.addItem(withTitle: "AI can \(category.rawValue)",
                             action: #selector(toggleAlwaysAllow(_:)),
                             target: self,
                             state: rce.controlState(chatID: chatID,
                                                     guid: guid,
                                                     category: category),
                             object: category)

            }
            menu.addItem(NSMenuItem.separator())

            if haveLinkedSession {
                menu.addItem(withTitle: "Send Commands & Output to AI Automatically",
                             action: #selector(toggleStream(_:)),
                             target: self,
                             state: streaming ? .on : .off,
                             object: nil)
                menu.addItem(NSMenuItem.separator())
            }

            menu.addItem(withTitle: "Help", action: #selector(showLinkedSessionHelp(_:)), target: self)

            // Position the menu just below the button
            let location = NSPoint(x: 0, y: sender.bounds.height)
            menu.popUp(positioning: nil, at: location, in: sender)
        } else {
            menu.addItem(withTitle: "Link Session", action: #selector(objcLinkSession(_:)), target: self)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Help", action: #selector(showLinkedSessionHelp(_:)), target: self)

            // Position the menu just below the button
            let location = NSPoint(x: 0, y: sender.bounds.height)
            menu.popUp(positioning: nil, at: location, in: sender)
        }
    }

    private static let webSearchUserDefaultsKey = "AI Web Search Enabled"
    private var webSearchEnabled: Bool {
        get {
            guard let model = LLMMetadata.model() else {
                return false
            }
            if !model.features.contains(.hostedWebSearch) {
                return false
            }
            if #available(macOS 11, *) {
                return UserDefaults.standard.bool(forKey: Self.webSearchUserDefaultsKey)
            }
            return false
        }
        set {
            return UserDefaults.standard.set(newValue, forKey: Self.webSearchUserDefaultsKey)
        }
    }

    @objc private func toggleWebSearch(_ sender: Any) {
        webSearchEnabled = !webSearchEnabled
        webSearchButton?.contentTintColor = webSearchEnabled ? .controlAccentColor : nil
    }

    @objc private func toggleAlwaysAllow(_ sender: Any) {
        if let chatID, let guid = model?.sessionGuid,
            let menuItem = sender as? NSMenuItem,
            let category = menuItem.representedObject as? RemoteCommand.Content.PermissionCategory {
            let existing = RemoteCommandExecutor.instance.permission(chatID: chatID,
                                                                     inSessionGuid: guid,
                                                                     category: category)
            let newPermission: RemoteCommandExecutor.Permission = switch existing {
            case .always: .never
            case .never: .ask
            case .ask: .always
            }
            listModel.setPermission(chat: chatID,
                                    permission: newPermission,
                                    guid: guid,
                                    category: category)
            let rce = RemoteCommandExecutor.instance
            ChatClient.instance?.publishUserMessage(
                chatID: chatID,
                content: .setPermissions(rce.allowedCategories(chatID: chatID, for: guid)))
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
        pickSessionPromise = SessionSelector.select(reason: "Link this session to AI chat?")
        let waitingMessage = Message(chatID: chatID,
                                     author: .agent,
                                     content: .clientLocal(ClientLocal(action: .pickingSession)),
                                     sentDate: Date(),
                                     uniqueID: UUID())
        if let pickSessionPromise {
            pickSessionPromise.then {  [weak self] session in
                if let self, let model = self.model {
                    model.sessionGuid = session.guid
                    ChatClient.instance?.publishNotice(
                        chatID: chatID,
                        notice: "This chat has been linked to terminal session `\(session.name?.escapedForMarkdownCode ?? "(Unnamed session)")`")
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
        ChatClient.instance?.publish(message: waitingMessage,
                                     toChatID: chatID,
                                     partial: false)
    }

    private var haveLinkedSession: Bool {
        guard let model,
              let guid = model.sessionGuid,
              iTermController.sharedInstance().session(withGUID: guid) != nil else {
            return false
        }
        return true
    }

    func stopStreaming() {
        if let chatID, streaming {
            ChatClient.instance?.publishMessageFromAgent(
                chatID: chatID,
                content: .clientLocal(.init(action: .streamingChanged(.stopped))))
        }
        streaming = false
        tableView.reloadData()
    }

    @objc private func toggleStream(_ sender: Any) {
        guard haveLinkedSession, let chatID else {
            return
        }
        if streaming {
            stopStreaming()
            return
        }
        let selection = iTermWarning.show(withTitle: "All terminal content will be sent to AI, which may go to a third party. Ensure this is safe to do before proceeding.",
                                          actions: ["OK", "Cancel"],
                                          accessory: nil,
                                          identifier: nil,
                                          silenceable: .kiTermWarningTypePersistent,
                                          heading: "Privacy Warning",
                                          window: nil)
        if selection == .kiTermWarningSelection0 {
            streaming = true
            tableView.reloadData()
            ChatClient.instance?.publishMessageFromAgent(
                chatID: chatID,
                content: .clientLocal(.init(action: .streamingChanged(.active))))
        }
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
            ChatClient.instance?.publishNotice(
                chatID: chatID,
                notice: "This chat is no longer linked to a terminal session.")
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard let model else {
            return
        }
        let row = model.items.count - 1
        guard row >= 0 else { return }
        if !animated {
            tableView.scrollRowToVisible(row)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                scrollView.contentView.animator().setBoundsOrigin(.zero)
            }
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
            switch message.message.content {
            case .terminalCommand:
                let cell = TerminalCommandMessageCellView()
                configure(cell: cell, for: message.message, isLast: isLastMessage)
                return cell
            case .clientLocal:
                let cell = SystemMessageCellView()
                configure(cell: cell, for: message.message, isLast: isLastMessage)
                return cell
            case .multipart:
                let cell = MultipartMessageCellView()
                configure(cell: cell, for: message.message, isLast: isLastMessage)
                return cell

            case .append, .appendAttachment:
                it_fatalError("Append-type messages should not be in model")

            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .selectSessionRequest,
                    .renameChat, .commit, .setPermissions, .vectorStoreCreated:
                let cell = RegularMessageCellView()
                configure(cell: cell, for: message.message, isLast: isLastMessage)
                return cell
            }
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    private func reloadCell(forMessageID messageID: UUID) {
        if let model, let i = model.index(ofMessageID: messageID) {
            tableView.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integer: 0))
            tableView.invalidateIntrinsicContentSize()
        }
    }

    private func edit(_ messageID: UUID) {
        guard let model,
              let i = model.index(ofMessageID: messageID),
              case .message(let message) = model.items[i],
              case .plainText(let text) = message.message.content else {
            return
        }
        model.deleteFrom(index: i)
        inputView.stringValue = text
    }

    private func configure(cell: MultipartMessageCellView,
                           for message: Message,
                           isLast: Bool) {
        cell.configure(with: rendition(for: message, isLast: isLast),
                       maxBubbleWidth: max(16, tableView.bounds.width * 0.7))
    }

    private func configure(cell: TerminalCommandMessageCellView,
                           for message: Message,
                           isLast: Bool) {
        cell.configure(with: rendition(for: message, isLast: isLast),
                       tableViewWidth: tableView.bounds.width)
    }

    private func configure(cell: RegularMessageCellView,
                           for message: Message,
                           isLast: Bool) {
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
            case .notice:
                break
            case .streamingChanged(let state):
                if state == .active {
                    cell.buttonClicked = { [weak self] identifier, messageID in
                        guard let self else {
                            return
                        }
                        guard messageID == originalMessageID else {
                            return
                        }
                        stopStreaming()
                    }
                }
            }
        case .vectorStoreCreated:
            it_fatalError()
        case .selectSessionRequest(let originalMessage):
            cell.buttonClicked = { [weak self] identifier, messageID in
                guard let self else {
                    return
                }
                guard messageID == originalMessageID else {
                    return
                }
                switch PickSessionButtonIdentifier(rawValue: identifier) {
                case .cancel:
                    if let pickSessionPromise {
                        SessionSelector.cancel(pickSessionPromise)
                        self.pickSessionPromise = nil
                    }
                    if let chatID {
                        self.client.respondSuccessfullyToRemoteCommandRequest(
                            inChat: chatID,
                            requestUUID: originalMessage.uniqueID,
                            message: "The user declined to allow this function call to execute.",
                            functionCallName: originalMessage.functionCallName ?? "Unknown function call name",
                            functionCallID: originalMessage.functionCallID,
                            userNotice: nil)
                    }
                    return
                case  .none:
                    return
                case .pickSession:
                    break
                }
                linkSession { session in
                    if let chatID {
                        if session != nil {
                            self.client.publish(message: originalMessage,
                                                toChatID: chatID,
                                                partial: false)
                        } else {
                            self.client.respondSuccessfullyToRemoteCommandRequest(
                                inChat: chatID,
                                requestUUID: originalMessage.uniqueID,
                                message: "The user declined to allow this function call to execute.",
                                functionCallName: originalMessage.functionCallName ?? "Unknown function call name",
                                functionCallID: originalMessage.functionCallID,
                                userNotice: nil)
                        }
                    }
                }
            }
        case .remoteCommandRequest(let remoteCommand):
            let functionCallName = remoteCommand.llmMessage.function_call?.name ?? "Unknown function call name"
            let functionCallID = remoteCommand.llmMessage.functionCallID
            cell.buttonClicked = { [client, listModel] identifier, messageID in
                guard messageID == originalMessageID else {
                    return
                }
                guard let chatID else {
                    return
                }
                guard let guid = self.listModel.chat(id: chatID)?.sessionGuid,
                      let session = iTermController.sharedInstance().session(withGUID: guid) else {
                    ChatClient.instance?.publishNotice(chatID: chatID, notice: "This chat is not linked to any terminal session.")
                    client.respondSuccessfullyToRemoteCommandRequest(
                        inChat: chatID,
                        requestUUID: messageID,
                        message: "The user did not link a terminal session to chat, so the function could not be run.",
                        functionCallName: functionCallName,
                        functionCallID: functionCallID,
                        userNotice: "AI attempted to perform an action, but no session is linked to this chat so it failed.")
                    return
                }
                let allowed: Bool
                switch RemoteCommandButtonIdentifier(rawValue: identifier) {
                case .allowOnce:
                    allowed = true
                case .allowAlways:
                    listModel.setPermission(chat: chatID,
                                            permission: .always,
                                            guid: guid,
                                            category: remoteCommand.content.permissionCategory)
                    allowed = true
                case .denyOnce:
                    allowed = false
                case .denyAlways:
                    listModel.setPermission(chat: chatID,
                                            permission: .never,
                                            guid: guid,
                                            category: remoteCommand.content.permissionCategory)
                    allowed = false
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
                        functionCallName: functionCallName,
                        functionCallID: functionCallID,
                        userNotice: nil)
                }
            }
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandResponse, .renameChat, .append, .commit, .setPermissions,
                .appendAttachment, .multipart:
            cell.buttonClicked = nil

        case .terminalCommand:
            it_fatalError()
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let model else {
            DLog("no model, can't calculate height")
            return 0
        }
        let item = model.items[row]
        let prototypeCell = view(forItem: item, isLastMessage: model.indexIsLastMessage(row))
        prototypeCell.frame = NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 0)
        prototypeCell.layoutSubtreeIfNeeded()

        let height = prototypeCell.fittingSize.height
        DLog("tableView(_, heightOfRow: \(row)) returns \(height)")
        return height
    }

    private func rendition(for message: Message, isLast: Bool) -> MessageRendition {
        var enableButtons = isLast
        var editable = false
        switch message.content {
        case .plainText:
            editable = message.author == .user
        case .vectorStoreCreated:
            it_fatalError()
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
            case .notice:
                break
            case .streamingChanged:
                enableButtons = streaming
            }
        default:
            break
        }
        let timestamp = {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: message.sentDate)
        }()
        let flavor: MessageRendition.Flavor = switch message.content {
        case .terminalCommand(let cmd):
                .command(.init(command: cmd.command,
                               url: cmd.url))
        case .multipart(let subparts, _):
                .multipart(subparts.map { subpart in
                    switch subpart {
                    case .attachment(let attachment):
                        switch attachment.type {
                        case .code(let content):
                            MessageRendition.SubpartContainer(
                                kind: .codeAttachment,
                                attributedString: AttributedStringForCode(
                                    content,
                                    textColor: message.textColor))
                        case .statusUpdate(let statusUpdate):
                            MessageRendition.SubpartContainer(
                                kind: .statusUpdate,
                                attributedString: AttributedStringForStatusUpdate(
                                    statusUpdate,
                                    textColor: message.textColor))
                        case .file(let file):
                            MessageRendition.SubpartContainer(
                                kind: .fileAttachment(id: attachment.id, name: file.name, file: file),
                                icon: NSImage.iconImage(filename: file.name,
                                                        size: .init(width: 16, height: 16)),
                                attributedString: AttributedStringForFilename(file.name,
                                                                              textColor: message.textColor))
                        case .fileID(id: let id, name: let name):
                            MessageRendition.SubpartContainer(
                                kind: .fileAttachment(id: id, name: name, file: nil),
                                icon: NSImage.iconImage(filename: name,
                                                        size: .init(width: 16, height: 16)),
                                attributedString: AttributedStringForFilename(name,
                                                                              textColor: message.textColor))
                        }
                    case .plainText(let text):
                        MessageRendition.SubpartContainer(
                            kind: .regular,
                            attributedString: Message.Content.plainText(text).attributedStringValue(
                                linkColor: message.linkColor, textColor: message.textColor))
                    case .markdown(let text):
                        MessageRendition.SubpartContainer(
                            kind: .regular,
                            attributedString: Message.Content.markdown(text).attributedStringValue(
                                linkColor: message.linkColor, textColor: message.textColor))
                    }
                })
        default:
                .regular(.init(attributedString: message.attributedStringValue,
                               buttons: message.buttons,
                               enableButtons: enableButtons))
        }
        return MessageRendition(isUser: message.author == .user,
                                messageUniqueID: message.uniqueID,
                                flavor: flavor,
                                timestamp: timestamp,
                                isEditable: editable,
                                linkColor: message.linkColor)
    }
}

extension LLM.Message.Attachment {
    func localPathCreatingIfNeeded() -> String {
        if let path = existingLocalPath() {
            return path
        }
        let path = proposedLocalPath()
        switch type {
        case .code(let text):
            do {
                try text.write(toFile: path, atomically: false, encoding: .utf8)
            } catch {
                DLog("Failed to write to \(path): \(error)")
            }
        case .statusUpdate:
            it_fatalError()
        case .file(let file):
            do {
                try file.content.write(to: URL(fileURLWithPath: path))
            } catch {
                DLog("Failed to write to \(path): \(error)")
            }
        case .fileID:
            // TODO: Download the file
            it_fatalError()
        }
        return path
    }

    private var basePathForAttachments: String {
        NSTemporaryDirectory() + "iTerm2ChatAttachments/"
    }

    private func possibleLocalPaths() -> [String] {
        switch type {
        case .code:
            [basePathForAttachments.appendingPathComponent(id).appendingPathComponent("code.txt")]
        case .file(let file):
            [file.localPath,
             basePathForAttachments.appendingPathComponent(id).appendingPathComponent(file.name.lastPathComponent)].compactMap { $0 }
        case .statusUpdate:
            it_fatalError()
        case .fileID:
            // TODO: Download the file
            []
        }
    }

    private func existingLocalPath() -> String? {
        let candidates = possibleLocalPaths()
        return candidates.first { candidate in
            FileManager.default.fileExists(atPath: candidate)
        }
    }

    private func proposedLocalPath() -> String {
        let path = possibleLocalPaths()[0]
        do {
            try FileManager.default.createDirectory(atPath: path.deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
        } catch {
            DLog("Failed to create \(path): \(error)")
        }
        return path
    }
}

extension ChatViewController: ChatInputViewDelegate {
    func textDidChange() {
        eligibleForAutoPaste = inputView.stringValue.isEmpty
    }

    func mimeType(_ filename: String) -> String {
        let ext = filename.pathExtension
        if let mime = openAIExtensionToMime[ext] {
            return mime
        }
        if #available(macOS 11, *) {
            let url = URL(fileURLWithPath: filename)
            if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
               let mimeType = UTType(uti)?.preferredMIMEType {
                return mimeType
            }
            // This is OK for file search but not if inlining.
            return "application/octet-stream"
        } else {
            let ext = (filename as NSString).pathExtension as CFString
            guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext, nil)?.takeRetainedValue(),
                  let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() as String? else {
                return "text/plain"
            }
            return mime
        }
    }

    func sendButtonClicked(text: String) {
        guard !text.isEmpty, let chatID else {
            return
        }
        let attachments = inputView.attachedFiles.flatMap { item -> [Message.Subpart] in
            switch item {
            case let .inMemory(filename: filename, content: data, mimeType: mimeType):
                return [
                    Message.Subpart.attachment(.init(
                        inline: false,
                        id: UUID().uuidString,
                        type: .file(.init(name: filename.lastPathComponent,
                                          content: data,
                                          mimeType: mimeType))))]

            case .regular(let filename):
                let resolved = FileManager.default.realPath(of: filename)
                var isDirectory = ObjCBool(false)
                if FileManager.default.fileExists(atPath: filename, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        guard let sequence = FileManager.default.recursiveRegularFileIterator(
                            at: URL(fileURLWithPath: filename)) else {
                            return []
                        }
                        return sequence.compactMap { childURL -> Message.Subpart? in
                            guard let data = try? Data(contentsOf: childURL) else {
                                return nil
                            }
                            return Message.Subpart.attachment(.init(
                                inline: false,
                                id: UUID().uuidString,
                                type: .file(.init(name: String(childURL.path.removing(prefix: resolved).removing(prefix: "/")),
                                                  content: data,
                                                  mimeType: mimeType(childURL.path)))))
                            }
                    } else {
                        if let data = try? Data(contentsOf: URL(fileURLWithPath: filename)) {
                            return [
                                Message.Subpart.attachment(.init(
                                    inline: false,
                                    id: UUID().uuidString,
                                    type: .file(.init(name: filename.lastPathComponent,
                                                      content: data,
                                                      mimeType: mimeType(filename)))))]
                        } else {
                            return []
                        }
                    }
                } else {
                    return []
                }
            case .placeholder:
                return []
            }
        }
        let vectorStoreIDs = [listModel.chat(id: chatID)?.vectorStore].compactMap { $0 }
        let configuration = Message.Configuration(hostedWebSearchEnabled: webSearchEnabled,
                                                  vectorStoreIDs: vectorStoreIDs)
        let message = if attachments.isEmpty {
            Message(chatID: chatID,
                    author: .user,
                    content: .plainText(text),
                    sentDate: Date(),
                    uniqueID: UUID(),
                    configuration: configuration)
        } else {
            Message(chatID: chatID,
                    author: .user,
                    content: .multipart([.plainText(text)] + attachments,
                                        vectorStoreID: listModel.chat(id: chatID)?.vectorStore),
                    sentDate: Date(),
                    uniqueID: UUID(),
                    configuration: configuration)
        }

        ChatClient.instance?.publish(
            message: message,
            toChatID: chatID,
            partial: false)

        inputView.clear()
        eligibleForAutoPaste = true
    }
}

extension ChatViewController {
    func streamLastCommand(_ userInfo: [AnyHashable: Any]) {
        it_assert(streaming)
        guard haveLinkedSession else {
            return
        }
        guard let command = userInfo[PTYCommandDidExitUserInfoKeyCommand] as? String else {
            return
        }
        guard let chatID else {
            return
        }

        let exitCode = (userInfo[PTYCommandDidExitUserInfoKeyExitCode] as? Int32) ?? 0
        let directory = userInfo[PTYCommandDidExitUserInfoKeyDirectory] as? String
        let remoteHost = userInfo[PTYCommandDidExitUserInfoKeyRemoteHost] as? VT100RemoteHostReading
        let startLine = userInfo[PTYCommandDidExitUserInfoKeyStartLine] as! Int32
        let lineCount = userInfo[PTYCommandDidExitUserInfoKeyLineCount] as! Int32
        let snapshot = userInfo[PTYCommandDidExitUserInfoKeySnapshot] as! TerminalContentSnapshot
        let extractor = iTermTextExtractor(dataSource: snapshot)
        let url = userInfo[PTYCommandDidExitUserInfoKeyURL] as! URL
        let content = extractor.content(
            in: VT100GridWindowedRange(
                coordRange: VT100GridCoordRange(
                    start: VT100GridCoord(x: 0, y: startLine),
                    end: VT100GridCoord(x: 0, y: startLine + lineCount)),
                columnWindow: VT100GridRange(location: 0, length: 0)),
            attributeProvider: nil,
            nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
            pad: false,
            includeLastNewline: false,
            trimTrailingWhitespace: true,
            cappedAtSize: -1,
            truncateTail: false,
            continuationChars: nil,
            coords: nil) as! String
        let cmd = TerminalCommand(username: remoteHost?.username,
                                  hostname: remoteHost?.hostname,
                                  directory: directory,
                                  command: command,
                                  output: content,
                                  exitCode: exitCode,
                                  url: url)
        ChatClient.instance?.publishMessageFromUser(chatID: chatID,
                                                    content: .terminalCommand(cmd))
    }
}

extension ChatViewController: ChatViewControllerModelDelegate {
    private func assertMessageTypeAllowed(_ message: Message?) {
        ChatViewControllerModel.assertMessageTypeAllowed(message)
    }
    func chatViewControllerModel(didInsertItemAtIndex i: Int) {
        if let model {
            assertMessageTypeAllowed(model.items[i].existingMessage?.message)
        }
        DLog("Insert tableview row at \(i)")
        estimatedCount += 1
        it_assert(i <= estimatedCount)
        tableView.insertRows(at: IndexSet(integer: i))

        // Disable buttons in message that just becamse second-to-last
        if let model,
           model.items.count > 1,
           model.items[model.items.count - 2].hasButtons {
            let rows = IndexSet(integer: model.items.count - 2)
            tableView.beginUpdates()
            tableView.reloadData(forRowIndexes: rows,
                                 columnIndexes: IndexSet(integer: 0))
            tableView.noteHeightOfRows(withIndexesChanged: rows)
            tableView.invalidateIntrinsicContentSize()
            tableView.endUpdates()
        }
    }


    func chatViewControllerModel(didRemoveItemsInRange range: Range<Int>) {
        DLog("Remove tableview row at \(range)")
        it_assert(range.upperBound <= estimatedCount)
        estimatedCount -= range.count
        tableView.removeRows(at: IndexSet(ranges: [range]))
    }

    func chatViewControllerModel(didModifyItemsAtIndexes indexSet: IndexSet) {
        if let model {
            for i in indexSet {
                assertMessageTypeAllowed(model.items[i].existingMessage?.message)
            }
        }
        guard let scrollView = tableView.enclosingScrollView,
              scrollView.documentView != nil else {
            return
        }

        tableView.beginUpdates()
        tableView.noteHeightOfRows(withIndexesChanged: indexSet)
        tableView.reloadData(forRowIndexes: indexSet, columnIndexes: IndexSet(integer: 0))
        tableView.invalidateIntrinsicContentSize()
        tableView.endUpdates()
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

extension Message.Content {
    func attributedStringValue(linkColor: NSColor,
                               textColor: NSColor) -> NSAttributedString {
        switch self {
        case .multipart:
            it_fatalError()  // TODO: This will be hit. We need a different cell type for multipart messages.
        case .renameChat, .append, .commit, .setPermissions, .terminalCommand, .appendAttachment,
                .vectorStoreCreated:
            it_fatalError()
        case .plainText(let string):
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
            return NSAttributedString(
                string: string,
                attributes: attributes
            )
        case .markdown(let string), .explanationResponse(_, _, let string):
            return AttributedStringForGPTMarkdown(string,
                                                  linkColor: linkColor,
                                                  textColor: textColor) { }
        case .explanationRequest(request: let request):
            let string =
            if let url = request.url {
                "Explain the output of \(request.subjectMatter) based on [attached terminal content](\(url))."
            } else {
                "Explain the output of \(request.subjectMatter) based on some no-longer-available content."
            }
            let epilogue = if request.truncated {
                "\n*Note: The command output was truncated because it exceeded the maximum number of lines supported by AI Chat*"
            } else {
                ""
            }
            return AttributedStringForGPTMarkdown(string + epilogue,
                                                  linkColor: linkColor,
                                                  textColor: textColor) { }
        case .remoteCommandRequest(let request):
            let specific = request.permissionDescription + "."
            let general = "Would you like to grant AI **\(request.content.permissionCategory.rawValue)** permission?"
            let info = "*If you grant or deny permission, it affects only this chat conversation while linked to this particular terminal session. You can change permissions in the chat Info menu.*"
            return AttributedStringForGPTMarkdown(specific + " " + general + "\n\n" + info,
                                                  linkColor: linkColor,
                                                  textColor: textColor) {}
        case .remoteCommandResponse(let response, _, _, _):
            switch response {
            case .success(let object):
                it_fatalError("\(object)")
            case .failure(let error):
                return AttributedStringForGPTMarkdown(error.localizedDescription,
                                                      linkColor: linkColor,
                                                      textColor: textColor) {}
            }
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession:
                return AttributedStringForSystemMessageMarkdown("Waiting for a session to be selected…") { }
            case .executingCommand(let command):
                return AttributedStringForSystemMessageMarkdown(command.markdownDescription) { }
            case .notice(let message):
                return AttributedStringForSystemMessagePlain(message, textColor: textColor)
            case .streamingChanged(let state):
                return switch state {
                case .stopped:
                    AttributedStringForSystemMessageMarkdown("Terminal commands will no longer be sent to AI automatically.") {}
                case .active:
                    AttributedStringForSystemMessageMarkdown("All terminal commands in the linked session will be sent to AI automatically.") {}
                case .stoppedAutomatically:
                    AttributedStringForSystemMessageMarkdown("Terminal commands will no longer be sent to AI automatically. Automatic sending always terminates when iTerm2 restarts or the current chat changes.") {}
                }
            }

        case .selectSessionRequest:
            return AttributedStringForGPTMarkdown(
                "The AI agent needs to run commands in a live terminal session, but none is attached to this chat.",
                linkColor: linkColor,
                textColor: textColor,
                didCopy: {})
        }
    }
}

extension Message {
    var linkColor: NSColor {
        return author == .user ? .white : .linkColor
    }
    var textColor: NSColor {
        return author == .user ? .white : .textColor
    }

    var buttons: [MessageRendition.Regular.Button] {
        switch content {
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandResponse, .renameChat, .append, .commit, .setPermissions,
                .terminalCommand, .appendAttachment, .multipart, .vectorStoreCreated:
            []
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession, .executingCommand:
                [.init(title: "Cancel", destructive: true, identifier: "")]
            case .notice: []
            case .streamingChanged(let state):
                switch state {
                case .active:
                    [.init(title: "Stop", destructive: true, identifier: "")]
                case .stopped, .stoppedAutomatically:
                    []
                }
            }
        case .selectSessionRequest:
            [.init(title: "Select a Session", destructive: false, identifier: PickSessionButtonIdentifier.pickSession.rawValue),
             .init(title: "Cancel", destructive: true, identifier: PickSessionButtonIdentifier.cancel.rawValue)]
        case .remoteCommandRequest:
            [.init(title: "Allow Once", destructive: false, identifier: RemoteCommandButtonIdentifier.allowOnce.rawValue),
             .init(title: "Always Allow", destructive: false, identifier: RemoteCommandButtonIdentifier.allowAlways.rawValue),
             .init(title: "Deny this Time", destructive: true, identifier: RemoteCommandButtonIdentifier.denyOnce.rawValue),
             .init(title: "Always Deny", destructive: true, identifier: RemoteCommandButtonIdentifier.denyAlways.rawValue)]
        }
    }

    var attributedStringValue: NSAttributedString {
        return content.attributedStringValue(linkColor: linkColor,
                                             textColor: textColor)
    }
}

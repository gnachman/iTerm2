//
//  ChatWindowController.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

import AppKit

@objc public class ChatErrorObjc: NSObject {
    @objc static let domain = "com.iterm2.chat"
    @objc(iTermChatErrorType) public enum ErrorType: Int {
        case chatNotFound

        var localizedDescription: String {
            switch self {
            case .chatNotFound:
                "The messages for this chat could not be loaded."
            }
        }

        var error: ChatError {
            ChatError(self)
        }
    }
}

public typealias ChatErrorType = ChatErrorObjc.ErrorType

public struct ChatError: LocalizedError, CustomStringConvertible, CustomNSError {
    public internal(set) var type: ChatErrorType

    public init(_ type: ChatErrorType) {
        self.type = type
    }

    public var errorDescription: String? {
        type.localizedDescription
    }

    public var description: String {
        type.localizedDescription
    }

    var localizedDescription: String {
        type.localizedDescription
    }

    public static var errorDomain: String { ChatErrorObjc.domain }
    public var errorCode: Int { type.rawValue }
}

protocol DictionaryCodable: Codable {
    init?(dictionaryValue: NSDictionary)
    var dictionaryValue: NSDictionary { get }
}

extension DictionaryCodable {
    init?(dictionaryValue dictionary: NSDictionary) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = decoded
    }

    var dictionaryValue: NSDictionary {
        guard let data = try? JSONEncoder().encode(self),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = jsonObject as? NSDictionary else {
            return [:]
        }
        return dictionary
    }
}

extension NSToolbarItem.Identifier {
    static let toggleChatList = NSToolbarItem.Identifier("ToggleChatList")
    static let modelSelector = NSToolbarItem.Identifier("ModelSelector")
    static let thinkingToggle = NSToolbarItem.Identifier("ThinkingToggle")
    static let webSearchToggle = NSToolbarItem.Identifier("WebSearchToggle")
    static let sessionButton = NSToolbarItem.Identifier("SessionButton")
}

@objc(iTermChatWindowController)
final class ChatWindowController: NSWindowController, DictionaryCodable {
    private static var _instance: ChatWindowController?
    @objc(instanceShowingErrors:) static func instance(showErrors: Bool) -> ChatWindowController? {
        if _instance == nil,
           let model = ChatListModel.instance,
           let client = ChatClient.instance {
            _instance = ChatWindowController(model: model,
                                             client: client)
        } else if showErrors && _instance == nil {
            iTermWarning.show(withTitle: "AI Chat could not open because of a problem loading the database. Verify there is only one instance of iTerm2 running.",
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Error",
                              window: nil)
        }
        return _instance
    }
    @objc static var instanceIfExists: ChatWindowController? {
        _instance
    }
    private let chatViewController: ChatViewController
    private let chatListViewController = ChatListViewController()
    private var splitViewController: ChatSplitViewController!
    private let model: ChatListModel
    private let client: ChatClient

    private enum CodingKeys: String, CodingKey {
        case chatID
    }

    init(model: ChatListModel, client: ChatClient) {
        chatViewController = ChatViewController(listModel: model,
                                                client: client)
        self.model = model
        self.client = client
        super.init(window: nil)
        chatListViewController.dataSource = model
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let chatID = try container.decode(String.self, forKey: .chatID)
        guard let model = ChatListModel.instance,
              let client = ChatClient.instance else {
            throw AIError("There was a problem initializing the database")
        }
        self.init(model: model, client: client)

        select(chatID: chatID)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chatViewController.chatID, forKey: .chatID)
    }


    // MARK: - Public Interface

    @objc
    func showChatWindow() {
        if !iTermAITermGatekeeper.check() {
            return
        }
        let window = self.window ?? initialize()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        chatViewController.makeMessageInputFieldFirstResponder()
    }

    @objc(isStreamingToGuid:)
    func isStreaming(to guid: String) -> Bool {
        return chatViewController.streaming && chatViewController.terminalSessionGuid == guid
    }

    @objc(stopStreamingSession:)
    func stopStreaming(guid: String) {
        if chatViewController.terminalSessionGuid == guid && chatViewController.streaming {
            chatViewController.stopStreaming()
        }
    }

    private var ageOfMostRecentChat: TimeInterval? {
        guard let chat = chatListViewController.mostRecentChat else {
            return nil
        }
        return -chat.lastModifiedDate.timeIntervalSinceNow
    }


    private var mostRecentChatIsEmpty: Bool {
        guard let chatID = chatListViewController.selectedChatID ?? chatListViewController.mostRecentChat?.id else {
            return false
        }
        guard let messages = model.messages(forChat: chatID, createIfNeeded: false) else {
            return false
        }
        let hasNontrivialMessage = messages.contains { message in
            switch message.content {
            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .selectSessionRequest,
                    .clientLocal, .renameChat, .append, .appendAttachment, .commit,
                    .vectorStoreCreated, .terminalCommand, .multipart:
                true
            case .userCommand, .setPermissions:
                false
            }
        }
        return !hasNontrivialMessage
    }

    @objc
    func createNewChatIfNeeded(currentSession: PTYSession?) {
        if model.count == 0 {
            createNewChat(offerGuid: currentSession?.guid)
        } else if let currentSession {
            if chatListViewController.selectMostRecent(forGuid: currentSession.guid) {
                return
            } else {
                createNewChat(offerGuid: currentSession.guid)
            }
        } else if mostRecentChatIsEmpty {
            _ = chatListViewController.selectMostRecent(forGuid: nil)
        } else if let ageOfMostRecentChat, ageOfMostRecentChat < 60 * 5 {
            _ = chatListViewController.selectMostRecent(forGuid: nil)
        } else {
            createNewChat(offerGuid: nil)
        }
    }

    private func initialize() -> NSWindow {
        chatListViewController.dataSource = model
        splitViewController = ChatSplitViewController(chatListViewController: chatListViewController,
                                                      chatViewController: chatViewController)

        // Configure the window with full size content view for transparent toolbar
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Keep a window title for accessibility but hide it visually
        if let chatID = chatViewController.chatID,
           let model = model.chat(id: chatID) {
            window.title = model.title
        } else {
            window.title = "AI Chat"
        }

        // Hide the native title
        if #available(macOS 26, *) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }

        window.minSize = .init(width: 500, height: 500)
        window.isMovableByWindowBackground = true

        self.window = window

        window.contentViewController = splitViewController
        window.center()
        window.setFrameAutosaveName("ChatWindow")

        if #available(macOS 26, *) {
            // On macOS 26, no toolbar - we'll use floating controls
            window.titlebarSeparatorStyle = .none
        } else if #available(macOS 11.0, *) {
            // Use unified compact style for cleaner appearance
            window.toolbarStyle = .unifiedCompact
            // Remove the separator line for seamless blending
            window.titlebarSeparatorStyle = .none

            // Only create toolbar for pre-macOS 26
            let toolbar = NSToolbar(identifier: "MainToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbar?.isVisible = true
        } else {
            // macOS 10.x
            let toolbar = NSToolbar(identifier: "MainToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbar?.isVisible = true
        }

        window.minSize = NSSize(width: 400, height: 300)

        chatListViewController.delegate = self
        chatViewController.delegate = self
        window.delegate = self

        // Add floating controls on macOS 26
        if #available(macOS 26, *) {
            chatViewController.setupFloatingControls()
        }

        return window
    }

    func updateTitle(_ title: String) {
        // Update both the window title (for accessibility) and our custom label
        window?.title = title
        chatViewController.chatToolbar.titleLabel.stringValue = title
    }

    private func createNewChat(offerGuid guid: String?) {
        do {
            let chatID = try client.create(chatWithTitle: "New Chat",
                                           terminalSessionGuid: nil,
                                           browserSessionGuid: nil,
                                           initialMessages: [],
                                           permissions: "")
            chatViewController.load(chatID: chatID)
            chatListViewController.select(chatID: chatID)
            if let guid, let session = iTermController.sharedInstance().session(withGUID: guid) {
                let terminal = !session.isBrowserSession()
                let name = session.name
                chatViewController.offerLink(to: guid, terminal: terminal, name: name)
            }
        } catch {
            DLog("\(error)")
        }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeCurrentSession(_:)) {
            return true
        }
        return false
    }

    @objc(closeCurrentSession:)
    func closeCurrentSession(_ sender: Any) {
        chatViewController.stopStreaming()
        window?.performClose(sender)
    }

    @objc(selectChatWithID:)
    func select(chatID: String) {
        guard model.chat(id: chatID) != nil else {
            return
        }
        chatListViewController.select(chatID: chatID)
        chatViewController.load(chatID: chatID)
    }
}

extension ChatWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        chatViewController.stopStreaming()
    }
}

// MARK: - NSToolbarDelegate

extension ChatWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if #available(macOS 26, *) {
            return []
        } else {
            return [.modelSelector, .thinkingToggle, .webSearchToggle, .sessionButton, .toggleChatList]
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if #available(macOS 26, *) {
            return []
        } else {
            return [.modelSelector, .thinkingToggle, .webSearchToggle, .sessionButton, .toggleChatList]
        }
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        switch itemIdentifier {
        case .toggleChatList:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Toggle Chat List"
            item.paletteLabel = "Toggle Chat List"
            item.toolTip = "Show or hide the chat list"
            item.image = NSImage(systemSymbolName: SFSymbol.sidebarLeft.rawValue,
                                 accessibilityDescription: "Toggle Chat List")
            item.target = self
            item.action = #selector(toggleChatList)
            // Standard toolbar buttons get automatic glass backing on macOS 26
            if #available(macOS 26, *) {
                item.isBordered = true  // Let the system handle the glass effect
            } else if #available(macOS 11.0, *) {
                item.isBordered = true
            }
            return item

        case .modelSelector:
            // Only create if we have multiple models
            if let modelSelector = chatViewController.chatToolbar.modelSelectorButton {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "Model"
                item.paletteLabel = "AI Model"
                item.toolTip = "Select AI model"
                item.view = modelSelector
                return item
            }
            return nil

        case .thinkingToggle:
            if let button = chatViewController.chatToolbar.thinkingButton {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "Thinking"
                item.paletteLabel = "Toggle Thinking"
                item.toolTip = "Enable or disable thinking/reasoning mode"
                item.view = button
                return item
            }
            return nil

        case .webSearchToggle:
            if let button = chatViewController.chatToolbar.webSearchButton {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "Web Search"
                item.paletteLabel = "Toggle Web Search"
                item.toolTip = "Enable or disable web search"
                item.view = button
                return item
            }
            return nil

        case .sessionButton:
            if let button = chatViewController.chatToolbar.sessionButton {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "Session"
                item.paletteLabel = "Link Session"
                item.toolTip = "Link or unlink terminal/browser session"
                item.view = button
                return item
            }
            return nil

        default:
            return nil
        }
    }

    private var currentChat: Chat? {
        guard let chatID = chatViewController.chatID else {
            return nil
        }
        return model.chat(id: chatID)
    }

    @objc(setSelectionText:forSession:)
    func setSelectedText(_ text: String, forSession guid: String) {
        if currentChat?.terminalSessionGuid == guid {
            chatViewController.offerSelectedText(text)
        }
    }

    @objc(revealOrCreateChatAboutSessionGuid:name:isTerminal:)
    func revealOrCreateChat(aboutGuid guid: String, name: String, terminal: Bool) {
        if let chat = model.lastChat(guid: guid) {
            chatListViewController.select(chatID: chat.id)
        } else {
            do {
                let chatID = try client.create(chatWithTitle: "Chat about \(name)",
                                               terminalSessionGuid: terminal ? guid : nil,
                                               browserSessionGuid: terminal ? nil : guid,
                                               initialMessages: [],
                                               permissions: "")
                chatViewController.load(chatID: chatID)
                chatListViewController.select(chatID: chatID)
            } catch {
                DLog("\(error)")
            }
        }
    }

    func createChat(name: String,
                    inject: String?,
                    linkToBrowserSessionGuid guid: String) {
        do {
            let chatID = try client.create(chatWithTitle: name,
                                           terminalSessionGuid: nil,
                                           browserSessionGuid: guid,
                                           initialMessages: [],
                                           permissions: "")
            chatViewController.load(chatID: chatID)
            chatListViewController.select(chatID: chatID)
            if let inject {
                chatViewController.attach(filename: name + ".txt",
                                          content: inject.lossyData,
                                          mimeType: "text/plain")
            }
        } catch {
            DLog("\(error)")
        }
    }

    // MARK: - Actions

    @objc func toggleChatList() {
        splitViewController.toggleChatList()
    }

    func updateToolbarItems() {
        guard let toolbar = window?.toolbar else {
            return
        }

        // Update visibility of toolbar items based on current state
        var visibleIdentifiers: [NSToolbarItem.Identifier] = [.toggleChatList, .flexibleSpace]

        // Add model selector if multiple models available
        let availableModels = AITermController.allProvidersForCurrentVendor.map({ $0.model })
        if availableModels.count > 1 {
            visibleIdentifiers.append(.modelSelector)
        }

        // Add thinking button if supported
        if let provider = chatViewController.provider,
           provider.model.features.contains(.configurableThinking) {
            visibleIdentifiers.append(.thinkingToggle)
        }

        // Add web search if available
        if chatViewController.chatToolbar.webSearchButton != nil {
            visibleIdentifiers.append(.webSearchToggle)
        }

        // Always show session button
        visibleIdentifiers.append(.sessionButton)

        // Validate visible items to update the toolbar
        toolbar.validateVisibleItems()
    }
}

extension ChatWindowController: ChatListViewControllerDelegate {
    func chatListViewControllerDidTapNewChat(_ viewController: ChatListViewController) {
        createNewChat(offerGuid: nil)
    }

    func chatListViewController(_ chatListViewController: ChatListViewController,
                                didSelectChat chatID: String?) {
        chatViewController.load(chatID: chatID)
        // Update window title using our custom method
        updateTitle(chatViewController.chatTitle)
        // Update toolbar items in case model or features changed
        updateToolbarItems()
    }
}

extension ChatWindowController: ChatSearchResultsViewControllerDelegate {
    func chatSearchResultsDidSelect(_ result: ChatSearchResult) {
        select(chatID: result.chatID)
        chatViewController.reveal(messageID: result.message.uniqueID)
    }
}

extension ChatWindowController: ChatViewControllerDelegate {
    func chatViewController(_ controller: ChatViewController, revealSessionWithGuid guid: String) -> Bool {
        if let session = iTermController.sharedInstance().session(withGUID: guid) {
            session.reveal()
            return true
        }
        return false
    }

    func chatViewControllerDeleteSession(_ controller: ChatViewController) {
        guard let chatID = controller.chatID else {
            return
        }
        let warning = iTermWarning()
        warning.title = "Are you sure you want to delete this chat? This action cannot be undone."
        warning.heading = "Delete Chat?"

        let action = iTermWarningAction(label: "Delete") { [weak self] _ in
            guard let self else {
                return
            }
            do {
                try client.delete(chatID: chatID)
                chatViewController.load(chatID: nil)
            } catch {
                DLog("\(error)")
            }
        }
        action.destructive = true
        warning.warningActions = [ iTermWarningAction(label: "Cancel"), action ]
        warning.warningType = .kiTermWarningTypePersistent
        warning.runModal()
    }

    func chatViewControllerDidUpdateToolbar(_ controller: ChatViewController) {
        updateToolbarItems()
    }

    func chatViewController(_ controller: ChatViewController,
                            forkAtMessageID: UUID,
                            ofChat originalChatID: String) {
        guard let listModel = ChatListModel.instance else {
            DLog("No chat list model")
            return
        }
        guard let chat = ChatListModel.instance?.chat(id: originalChatID) else {
            DLog("No chat with id \(originalChatID)")
            return
        }
        guard let index = listModel.index(ofMessageID: forkAtMessageID, inChat: chat.id) else {
            DLog("No such message \(forkAtMessageID) in \(originalChatID)")
            return
        }
        do {
            let allMessages = listModel.messages(forChat: originalChatID, createIfNeeded: false)
            let sourceMessages: [Message] =
                if let allMessages {
                    Array(allMessages[0..<index])
                } else {
                    []
                }
            var initialMessages = [Message]()
            var uuidMap = [UUID: UUID]()
            var messageMap = [UUID: Message]()
            for sourceMessage in sourceMessages {
                if case .renameChat = sourceMessage.content {
                    continue
                }
                let clone = sourceMessage.clone(&uuidMap, messages: messageMap)
                initialMessages.append(clone)
                messageMap[clone.uniqueID] = clone
            }
            let originalTitle = chat.title

            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            let now = Date()
            let nowString = formatter.string(from: now)

            var title = originalTitle
            let forkedAt = "(Forked at "
            let desiredSuffix = forkedAt + nowString + ")"
            if let range = title.range(of: forkedAt) {
                title = originalTitle[..<range.lowerBound] + desiredSuffix
            } else {
                title += " " + desiredSuffix
            }
            let chatID = try client.create(chatWithTitle: title,
                                           terminalSessionGuid: chat.terminalSessionGuid,
                                           browserSessionGuid: chat.browserSessionGuid,
                                           initialMessages: initialMessages,
                                           permissions: chat.permissions)
            chatViewController.load(chatID: chatID)
            chatListViewController.select(chatID: chatID)

            if let allMessages {
                let userMessage = allMessages[index]
                chatViewController.stage(userMessage)
            }
        } catch {
            DLog("\(error)")
        }
    }
}


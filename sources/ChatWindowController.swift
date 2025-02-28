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
    }

    @objc(isStreamingToGuid:)
    func isStreaming(to guid: String) -> Bool {
        return chatViewController.streaming && chatViewController.sessionGuid == guid
    }

    @objc(stopStreamingSession:)
    func stopStreaming(guid: String) {
        if chatViewController.sessionGuid == guid && chatViewController.streaming {
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
        guard let chatID = chatListViewController.selectedChatID else {
            return false
        }
        guard let messages = model.messages(forChat: chatID, createIfNeeded: false) else {
            return false
        }

        return messages.isEmpty
    }

    @objc
    func createNewChatIfNeeded() {
        if model.count == 0 {
            createNewChat()
        } else if mostRecentChatIsEmpty {
            chatListViewController.selectMostRecent()
        } else if let ageOfMostRecentChat, ageOfMostRecentChat < 60 * 5 {
            chatListViewController.selectMostRecent()
        } else {
            createNewChat()
        }
    }

    private func initialize() -> NSWindow {
        chatListViewController.dataSource = model
        splitViewController = ChatSplitViewController(chatListViewController: chatListViewController,
                                                      chatViewController: chatViewController)

        // Configure the window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        if let chatID = chatViewController.chatID,
           let model = model.chat(id: chatID) {
            window.title = model.title
        } else {
            window.title = "AI Chat"
        }

        window.minSize = .init(width: 500, height: 500)
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true

        self.window = window

        window.contentViewController = splitViewController
        window.center()
        window.setFrameAutosaveName("ChatWindow")

        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unifiedCompact
            // Hiding the title gives the toolbar more room to show.
            // A transparent title bar lets the toolbar appear as an overlay.
            window.titlebarAppearsTransparent = true
        }

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbar?.isVisible = true
        window.minSize = NSSize(width: 400, height: 300)

        chatListViewController.delegate = self
        chatViewController.delegate = self
        window.delegate = self

        return window
    }

    private func createNewChat() {
        let chatID = client.create(chatWithTitle: "New Chat", sessionGuid: nil)
        chatViewController.load(chatID: chatID)
        chatListViewController.select(chatID: chatID)
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
        return [.toggleChatList]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleChatList]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == .toggleChatList else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Toggle Chat List"
        item.paletteLabel = "Toggle Chat List"
        item.toolTip = "Show or hide the chat list"
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: "sidebar.left",
                                 accessibilityDescription: "Toggle Chat List")
        } else {
            item.image = NSImage(named: NSImage.touchBarSidebarTemplateName)
        }
        item.target = self
        item.action = #selector(toggleChatList)
        return item
    }

    private var currentChat: Chat? {
        guard let chatID = chatViewController.chatID else {
            return nil
        }
        return model.chat(id: chatID)
    }

    @objc(setSelectionText:forSession:)
    func setSelectedText(_ text: String, forSession guid: String) {
        if currentChat?.sessionGuid == guid {
            chatViewController.offerSelectedText(text)
        }
    }

    @objc(revealOrCreateChatAboutSessionGuid:name:)
    func revealOrCreateChat(aboutGuid guid: String, name: String) {
        if let chat = model.lastChat(guid: guid) {
            chatListViewController.select(chatID: chat.id)
        } else {
            let chatID = client.create(chatWithTitle: "Chat about \(name)",
                                       sessionGuid: guid)
            chatViewController.load(chatID: chatID)
            chatListViewController.select(chatID: chatID)
        }
    }

    // MARK: - Actions

    @objc func toggleChatList() {
        splitViewController.toggleChatList()
    }
}

extension ChatWindowController: ChatListViewControllerDelegate {
    func chatListViewControllerDidTapNewChat(_ viewController: ChatListViewController) {
        createNewChat()
    }

    func chatListViewController(_ chatListViewController: ChatListViewController,
                                didSelectChat chatID: String?) {
        chatViewController.load(chatID: chatID)
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
            client.delete(chatID: chatID)
            chatViewController.load(chatID: nil)
        }
        action.destructive = true
        warning.warningActions = [ iTermWarningAction(label: "Cancel"), action ]
        warning.warningType = .kiTermWarningTypePersistent
        warning.runModal()
    }
}


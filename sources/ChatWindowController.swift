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
    @objc static let instance = {
        let controller = ChatWindowController()
        controller.chatListViewController.dataSource = ChatListModel.instance
        return controller
    }()
    private let chatViewController = ChatViewController()
    private let chatListViewController = ChatListViewController()
    private var splitViewController: ChatSplitViewController!

    private enum CodingKeys: String, CodingKey {
        case chatID
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let chatID = try container.decode(String.self, forKey: .chatID)

        self.init(window: nil)

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
        let window = self.window ?? initialize()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func initialize() -> NSWindow {
        chatListViewController.dataSource = ChatListModel.instance
        splitViewController = ChatSplitViewController(chatListViewController: chatListViewController,
                                                      chatViewController: chatViewController)

        // Configure the window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ChatListModel.instance.chat(id: chatViewController.chatID)?.title ?? "AI Chat"

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

        return window
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeCurrentSession(_:)) {
            return true
        }
        return false
    }

    @objc(closeCurrentSession:)
    func closeCurrentSession(_ sender: Any) {
        window?.performClose(sender)
    }

    @objc(selectChatWithID:)
    func select(chatID: String) {
        guard ChatListModel.instance.chat(id: chatID) != nil else {
            return
        }
        chatListViewController.select(chatID: chatID)
        chatViewController.load(chatID: chatID)
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
        return ChatListModel.instance.chat(id: chatViewController.chatID)
    }

    @objc(setSelectionText:forSession:)
    func setSelectedText(_ text: String, forSession guid: String) {
        if currentChat?.sessionGuid == guid {
            chatViewController.offerSelectedText(text)
        }
    }

    @objc(revealOrCreateChatAboutSessionGuid:name:)
    func revealOrCreateChat(aboutGuid guid: String, name: String) {
        if let chat = ChatListModel.instance.lastChat(guid: guid) {
            chatListViewController.select(chatID: chat.id)
        } else {
            let chatID = ChatClient.instance.create(chatWithTitle: "Chat about \(name)",
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
        let chatID = ChatBroker.instance.create(chatWithTitle: "New Chat", sessionGuid: nil)
        chatViewController.load(chatID: chatID)
        chatListViewController.select(chatID: chatID)
    }

    func chatListViewController(_ chatListViewController: ChatListViewController,
                                didSelectChat chatID: String) {
        chatViewController.load(chatID: chatID)
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
}


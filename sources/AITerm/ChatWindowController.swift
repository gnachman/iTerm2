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
                String(localized: "ChatWindowController.ChatNotFound", defaultValue: "The messages for this chat could not be loaded.", comment: "Error description when a chat's messages cannot be loaded")
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
    static let providerSelector = NSToolbarItem.Identifier("ProviderSelector")
    static let modelSelector = NSToolbarItem.Identifier("ModelSelector")
    static let reasoningEffortSelector = NSToolbarItem.Identifier("ReasoningEffortSelector")
    static let serviceTierSelector = NSToolbarItem.Identifier("ServiceTierSelector")
    static let thinkingToggle = NSToolbarItem.Identifier("ThinkingToggle")
    static let webSearchToggle = NSToolbarItem.Identifier("WebSearchToggle")
    static let sessionButton = NSToolbarItem.Identifier("SessionButton")
}

@objc(iTermChatWindowController)
final class ChatWindowController: NSWindowController, DictionaryCodable {
    // Builds a forked chat title by stripping any pre-existing fork suffix and
    // appending a fresh one for the current locale, so re-forking replaces the
    // suffix instead of stacking a second one.
    //
    // DESIGN NOTE: The robust fix is to persist the base title and fork
    // timestamp as separate Chat fields and compose the display suffix at render
    // time, so no reverse-engineering of the display string is needed. That is
    // deliberately NOT done here: Chat is the on-disk persistence model (and is
    // also compiled into the iOS companion app), so adding fields is a schema
    // migration that is out of scope for this change. Instead we harden the
    // string-based approach against the two failure modes of the previous
    // implementation:
    //   1. It stripped from the FIRST unanchored occurrence of the prefix, which
    //      truncated a user title that merely contained "(Forked at " somewhere
    //      in the middle. We now only strip a suffix anchored to the END of the
    //      title, and only when the text between the prefix and the trailing ")"
    //      looks like a timestamp (non-empty and contains a digit).
    //   2. A reworded translation could not be recognized. We still try the
    //      current locale first and then the other shipped localizations so a
    //      chat forked in one language and re-forked in another replaces its
    //      suffix. This cannot recognize a locale whose wording changed AFTER an
    //      old suffix was written; only stored provenance (the deferred model
    //      change above) would fix that.
    static func forkedChatTitle(from originalTitle: String, timestamp: String) -> String {
        let currentPrefix = String(localized: "ChatWindowController.ForkedAtPrefix", defaultValue: "(Forked at ", comment: "Prefix appended to a forked chat title, followed by a timestamp")
        let desiredSuffix = currentPrefix + timestamp + ")"

        var candidatePrefixes = [currentPrefix]
        for localization in Bundle.main.localizations {
            guard let lprojPath = Bundle.main.path(forResource: localization, ofType: "lproj"),
                  let bundle = Bundle(path: lprojPath) else {
                continue
            }
            let prefix = bundle.localizedString(forKey: "ChatWindowController.ForkedAtPrefix", value: "", table: "Localizable")
            if !prefix.isEmpty && !candidatePrefixes.contains(prefix) {
                candidatePrefixes.append(prefix)
            }
        }

        for prefix in candidatePrefixes {
            if let base = baseTitle(strippingForkSuffixFrom: originalTitle, prefix: prefix) {
                return compose(baseTitle: base, suffix: desiredSuffix)
            }
        }
        return compose(baseTitle: originalTitle, suffix: desiredSuffix)
    }

    // Returns the base title with a trailing fork suffix removed, or nil if the
    // title does not END in a recognizable "<prefix><timestamp>)" suffix. The
    // match is anchored to the end of the string and the timestamp portion must
    // be non-empty and contain a digit, so ordinary titles that merely contain
    // the prefix are left intact.
    private static func baseTitle(strippingForkSuffixFrom title: String, prefix: String) -> String? {
        guard !prefix.isEmpty, title.hasSuffix(")") else {
            return nil
        }
        // Use the LAST occurrence so everything after it is treated as the suffix.
        guard let prefixRange = title.range(of: prefix, options: .backwards) else {
            return nil
        }
        let timestamp = title[prefixRange.upperBound..<title.index(before: title.endIndex)]
        guard !timestamp.isEmpty, timestamp.contains(where: { $0.isNumber }) else {
            return nil
        }
        return String(title[..<prefixRange.lowerBound])
    }

    // Joins a base title and a fork suffix with exactly one separating space,
    // tolerating a base that already ends in a space (the strip path keeps the
    // space that preceded the removed suffix).
    private static func compose(baseTitle: String, suffix: String) -> String {
        let trimmed = baseTitle.hasSuffix(" ") ? String(baseTitle.dropLast()) : baseTitle
        if trimmed.isEmpty {
            return suffix
        }
        return trimmed + " " + suffix
    }

    private static var _instance: ChatWindowController?
    @objc(instanceShowingErrors:) static func instance(showErrors: Bool) -> ChatWindowController? {
        if _instance == nil,
           let model = ChatListModel.instance,
           let client = ChatClient.instance {
            _instance = ChatWindowController(model: model,
                                             client: client)
        } else if showErrors && _instance == nil {
            iTermWarning.show(withTitle: String(localized: "ChatWindowController.OpenFailedMessage", defaultValue: "AI Chat could not open because of a problem loading the database. Verify there is only one instance of iTerm2 running.", comment: "Error message when the AI chat window cannot open due to a database problem"),
                              actions: [iTermLocalizedOK()],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: String(localized: "General.Error", defaultValue: "Error", comment: "Generic error heading"),
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

        // The window's own delete flow clears the conversation view itself,
        // but a chat can also be deleted out from under us (the companion
        // phone today; anything else tomorrow). Without this the view keeps
        // showing, and interacting with, a chat that no longer exists.
        NotificationCenter.default.addObserver(
            forName: ChatListModel.chatWasDeleted,
            object: nil,
            queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let deletedID = notification.userInfo?[ChatListModel.chatIDUserInfoKey] as? String,
                          self.chatViewController.chatID == deletedID else {
                        return
                    }
                    RLog("Displayed chat \(deletedID) was deleted externally; clearing the view")
                    self.chatViewController.load(chatID: nil)
                }
            }
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

    // True when `binding` (a chat's stored terminal reference, a stableID for
    // new bindings or a legacy guid otherwise) is one of `keys` (a session's
    // {guid, stableID} pair). Matches a binding stored in either form.
    private func terminalBinding(_ binding: String?, matchesReferenceKeys keys: Set<String>) -> Bool {
        guard let binding else {
            return false
        }
        return keys.contains(binding)
    }

    // Resolving convenience for the non-hot callers that only hold a guid.
    private func terminalBinding(_ binding: String?, matchesSessionGuid guid: String) -> Bool {
        return terminalBinding(binding, matchesReferenceKeys: iTermSessionReferenceKeys(forGuid: guid))
    }

    // Called from the draw path (textViewSessionIsStreamingToAIChat), so the
    // caller passes the session's stableID to avoid a session-tree walk here.
    @objc(isStreamingToGuid:stableID:)
    func isStreaming(toGuid guid: String, stableID: String) -> Bool {
        return chatViewController.streaming &&
            terminalBinding(chatViewController.terminalSessionGuid,
                            matchesReferenceKeys: [guid, stableID])
    }

    @objc(stopStreamingSession:)
    func stopStreaming(guid: String) {
        if terminalBinding(chatViewController.terminalSessionGuid, matchesSessionGuid: guid) &&
            chatViewController.streaming {
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
                    .vectorStoreCreated, .terminalCommand, .multipart, .unsupported:
                true
            case .userCommand, .setPermissions, .watcherEvent:
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
            window.title = String(localized: "ChatWindowController.WindowTitle", defaultValue: "AI Chat", comment: "Default window title for the AI chat window")
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
        } else {
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

    private func createNewChat(offerGuid guid: String?, enableOrchestration: Bool = false) {
        do {
            let chatID = try client.create(chatWithTitle: String(localized: "ChatWindowController.NewChatTitle", defaultValue: "New Chat", comment: "Default title for a newly created chat"),
                                           terminalSessionGuid: nil,
                                           browserSessionGuid: nil,
                                           initialMessages: [],
                                           permissions: "")
            chatViewController.load(chatID: chatID)
            chatListViewController.select(chatID: chatID)
            if enableOrchestration {
                // The "try orchestration" entry point: don't just offer it,
                // turn it on so the user lands in an orchestration chat.
                chatViewController.enableOrchestration()
                return
            }
            if let guid, let session = iTermController.sharedInstance().anySession(forReference: guid) {
                let terminal = !session.isBrowserSession()
                let name = session.name
                chatViewController.offerLink(to: guid, terminal: terminal, name: name)
            } else {
                // No session to link to, so offer the alternative:
                // switch the chat into orchestration mode.
                chatViewController.offerOrchestration()
            }
        } catch {
            DLog("\(error)")
        }
    }

    // Open a brand-new chat with orchestration already enabled. The caller is
    // expected to have shown the window first (showChatWindow), which is gated
    // by iTermAITermGatekeeper; if AI is disabled the window never appeared, so
    // bail rather than silently creating a chat behind the warning.
    @objc
    func createNewOrchestrationChat() {
        guard window?.isVisible == true else {
            return
        }
        createNewChat(offerGuid: nil, enableOrchestration: true)
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeCurrentSession(_:)) {
            return true
        }
        if let action = menuItem.action, chatViewController.isFindAction(action) {
            return chatViewController.validateFindAction(action, tag: menuItem.tag)
        }
        return false
    }

    // Find actions reach the window controller when no view in the
    // conversation subtree is first responder (e.g. nothing focused). Forward
    // to the conversation so Cmd-F works regardless of focus.
    @objc func performFindPanelAction(_ sender: Any?) {
        chatViewController.performFindPanelAction(sender)
    }

    @objc func findNext(_ sender: Any?) {
        chatViewController.findNext(sender)
    }

    @objc func findPrevious(_ sender: Any?) {
        chatViewController.findPrevious(sender)
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
            return [.providerSelector, .modelSelector, .reasoningEffortSelector, .serviceTierSelector,
                    .thinkingToggle, .webSearchToggle, .sessionButton, .toggleChatList]
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if #available(macOS 26, *) {
            return []
        } else {
            return [.providerSelector, .modelSelector, .reasoningEffortSelector, .serviceTierSelector,
                    .thinkingToggle, .webSearchToggle, .sessionButton, .toggleChatList]
        }
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        switch itemIdentifier {
        case .toggleChatList:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = String(localized: "ChatWindowController.ToggleChatList", defaultValue: "Toggle Chat List", comment: "Toolbar item to show or hide the chat list")
            item.paletteLabel = String(localized: "ChatWindowController.ToggleChatList", defaultValue: "Toggle Chat List", comment: "Toolbar item to show or hide the chat list")
            item.toolTip = String(localized: "ChatWindowController.ToggleChatListTooltip", defaultValue: "Show or hide the chat list", comment: "Tooltip for the toggle chat list toolbar item")
            item.image = NSImage(systemSymbolName: SFSymbol.sidebarLeft.rawValue,
                                 accessibilityDescription: String(localized: "ChatWindowController.ToggleChatList", defaultValue: "Toggle Chat List", comment: "Toolbar item to show or hide the chat list"))
            item.target = self
            item.action = #selector(toggleChatList)
            // Standard toolbar buttons get automatic glass backing on macOS 26
            if #available(macOS 26, *) {
                item.isBordered = true  // Let the system handle the glass effect
            } else {
                item.isBordered = true
            }
            return item

        case .providerSelector:
            if let providerSelector = chatViewController.chatToolbar.providerSelectorButton,
               !providerSelector.isHidden {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = String(localized: "ChatWindowController.ProviderLabel", defaultValue: "Provider", comment: "Toolbar label for the AI provider selector")
                item.paletteLabel = String(localized: "ChatWindowController.ProviderPaletteLabel", defaultValue: "AI Provider", comment: "Toolbar customization palette label for the AI provider selector")
                item.toolTip = String(localized: "ChatWindowController.ProviderTooltip", defaultValue: "Select AI provider for new chats", comment: "Tooltip for the AI provider selector toolbar item")
                item.view = providerSelector
                return item
            }
            return nil

        case .modelSelector:
            // Only create if we have multiple models
            if let modelSelector = chatViewController.chatToolbar.modelSelectorButton {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = String(localized: "ChatWindowController.ModelLabel", defaultValue: "Model", comment: "Toolbar label for the AI model selector")
                item.paletteLabel = String(localized: "ChatWindowController.ModelPaletteLabel", defaultValue: "AI Model", comment: "Toolbar customization palette label for the AI model selector")
                item.toolTip = String(localized: "ChatWindowController.ModelTooltip", defaultValue: "Select AI model", comment: "Tooltip for the AI model selector toolbar item")
                item.view = modelSelector
                return item
            }
            return nil

        case .thinkingToggle:
            if let button = chatViewController.chatToolbar.thinkingButton {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = String(localized: "ChatWindowController.ThinkingLabel", defaultValue: "Thinking", comment: "Toolbar label for the thinking toggle")
                item.paletteLabel = String(localized: "ChatWindowController.ThinkingPaletteLabel", defaultValue: "Toggle Thinking", comment: "Toolbar customization palette label for the thinking toggle")
                item.toolTip = String(localized: "ChatWindowController.ThinkingTooltip", defaultValue: "Enable or disable thinking/reasoning mode", comment: "Tooltip for the thinking toggle toolbar item")
                item.view = button
                return item
            }
            return nil

        case .reasoningEffortSelector:
            if let selector = chatViewController.chatToolbar.reasoningEffortButton,
               !selector.isHidden {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = String(localized: "ChatWindowController.EffortLabel", defaultValue: "Effort", comment: "Toolbar label for the reasoning effort selector")
                item.paletteLabel = String(localized: "ChatWindowController.EffortPaletteLabel", defaultValue: "Reasoning Effort", comment: "Toolbar customization palette label for the reasoning effort selector")
                item.toolTip = String(localized: "ChatWindowController.EffortTooltip", defaultValue: "Select reasoning effort", comment: "Tooltip for the reasoning effort selector toolbar item")
                item.view = selector
                return item
            }
            return nil

        case .serviceTierSelector:
            if let selector = chatViewController.chatToolbar.serviceTierButton,
               !selector.isHidden {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = String(localized: "ChatWindowController.SpeedLabel", defaultValue: "Speed", comment: "Toolbar label for the AI service tier selector")
                item.paletteLabel = String(localized: "ChatWindowController.SpeedPaletteLabel", defaultValue: "AI Speed", comment: "Toolbar customization palette label for the AI service tier selector")
                item.toolTip = String(localized: "ChatWindowController.SpeedTooltip", defaultValue: "Select AI service tier", comment: "Tooltip for the AI service tier selector toolbar item")
                item.view = selector
                return item
            }
            return nil

        case .webSearchToggle:
            if let button = chatViewController.chatToolbar.webSearchButton {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = String(localized: "ChatWindowController.WebSearchLabel", defaultValue: "Web Search", comment: "Toolbar label for the web search toggle")
                item.paletteLabel = String(localized: "ChatWindowController.WebSearchPaletteLabel", defaultValue: "Toggle Web Search", comment: "Toolbar customization palette label for the web search toggle")
                item.toolTip = String(localized: "ChatWindowController.WebSearchTooltip", defaultValue: "Enable or disable web search", comment: "Tooltip for the web search toggle toolbar item")
                item.view = button
                return item
            }
            return nil

        case .sessionButton:
            if let button = chatViewController.chatToolbar.sessionButton {
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = String(localized: "ChatWindowController.SessionLabel", defaultValue: "Session", comment: "Toolbar label for the link session button")
                item.paletteLabel = String(localized: "ChatWindowController.SessionPaletteLabel", defaultValue: "Link Session", comment: "Toolbar customization palette label for the link session button")
                item.toolTip = String(localized: "ChatWindowController.SessionTooltip", defaultValue: "Link or unlink terminal/browser session", comment: "Tooltip for the link session toolbar item")
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
        if terminalBinding(currentChat?.terminalSessionGuid, matchesSessionGuid: guid) {
            chatViewController.offerSelectedText(text)
        }
    }

    @objc(revealOrCreateChatAboutSessionGuid:name:isTerminal:)
    func revealOrCreateChat(aboutGuid guid: String, name: String, terminal: Bool) {
        if let chat = model.lastChat(guid: guid) {
            chatListViewController.select(chatID: chat.id)
        } else {
            do {
                let chatID = try client.create(chatWithTitle: String(localized: "ChatWindowController.ChatAboutTitle", defaultValue: "Chat about \(name)", comment: "Default title for a chat created about a named session"),
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

        if chatViewController.availableProviderOptions.count > 1 {
            visibleIdentifiers.append(.providerSelector)
        }

        // Add model selector if multiple models available
        if chatViewController.availableModels.count > 1 {
            visibleIdentifiers.append(.modelSelector)
        }

        if let provider = chatViewController.provider,
           !provider.model.reasoningEfforts.isEmpty {
            visibleIdentifiers.append(.reasoningEffortSelector)
        }

        if let provider = chatViewController.provider,
           !provider.model.serviceTiers.isEmpty {
            visibleIdentifiers.append(.serviceTierSelector)
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

    func chatListViewController(_ chatListViewController: ChatListViewController,
                                renameChat chatID: String) {
        renameChat(chatID: chatID)
    }

    func chatListViewController(_ chatListViewController: ChatListViewController,
                                deleteChats chatIDs: [String]) {
        let currentChatID = chatViewController.chatID
        deleteChats(chatIDs: chatIDs) { [weak self] in
            guard let self else {
                return
            }
            if let currentChatID,
               chatIDs.contains(currentChatID) {
                if model.count > 0 {
                    let nextChatID = model.chat(at: 0).id
                    chatViewController.load(chatID: nextChatID)
                    chatListViewController.select(chatID: nextChatID)
                } else {
                    chatViewController.load(chatID: nil)
                }
            }
            updateTitle(chatViewController.chatTitle)
            updateToolbarItems()
        }
    }

    private func renameChat(chatID: String) {
        guard let chat = model.chat(id: chatID) else {
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "ChatWindowController.RenameChatTitle", defaultValue: "Rename Chat", comment: "Title of the rename chat dialog")
        alert.informativeText = String(localized: "ChatWindowController.RenameChatPrompt", defaultValue: "Choose a new name for this chat.", comment: "Prompt in the rename chat dialog")
        alert.addButton(withTitle: String(localized: "ChatWindowController.RenameButton", defaultValue: "Rename", comment: "Rename button in the rename chat dialog"))
        alert.addButton(withTitle: iTermLocalizedCancel())

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = chat.title
        field.selectText(nil)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        let newTitle = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty,
              newTitle != chat.title else {
            return
        }
        do {
            try client.publishMessageFromAgent(chatID: chatID,
                                               content: .renameChat(newTitle))
            if chatViewController.chatID == chatID {
                updateTitle(newTitle)
            }
        } catch {
            DLog("Failed to rename chat \(chatID): \(error)")
            iTermWarning.show(withTitle: String(localized: "ChatWindowController.RenameFailedMessage", defaultValue: "The chat could not be renamed.", comment: "Error message when renaming a chat fails"),
                              actions: [iTermLocalizedOK()],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: String(localized: "ChatWindowController.RenameFailedHeading", defaultValue: "Rename Failed", comment: "Heading for the rename-failed error dialog"),
                              window: window)
        }
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
        if let session = iTermController.sharedInstance().anySession(forReference: guid) {
            session.reveal()
            return true
        }
        return false
    }

    func chatViewControllerDeleteSession(_ controller: ChatViewController) {
        guard let chatID = controller.chatID else {
            return
        }
        deleteChats(chatIDs: [chatID]) { [weak self] in
            self?.chatViewController.load(chatID: nil)
        }
    }

    fileprivate func deleteChats(chatIDs: [String], completion: (() -> Void)?) {
        let uniqueChatIDs = Array(Set(chatIDs))
        guard !uniqueChatIDs.isEmpty else {
            return
        }
        let warning = iTermWarning()
        let count = uniqueChatIDs.count
        warning.title = String(localized: "ChatWindowController.DeleteChatConfirm", defaultValue: "Are you sure you want to delete \(count) chats? This action cannot be undone.", comment: "Confirmation before deleting chats; %lld is the number of chats")
        warning.heading = String(localized: "ChatWindowController.DeleteChatHeading", defaultValue: "Delete \(count) Chats?", comment: "Heading of the delete-chats confirmation; %lld is the number of chats")

        let action = iTermWarningAction(label: String(localized: "General.Delete", defaultValue: "Delete", comment: "Delete button")) { [weak self] _ in
            guard let self else {
                return
            }
            for chatID in uniqueChatIDs {
                do {
                    try client.delete(chatID: chatID)
                } catch {
                    DLog("\(error)")
                }
            }
            completion?()
        }
        action.destructive = true
        warning.warningActions = [ iTermWarningAction(label: iTermLocalizedCancel()), action ]
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
            RLog("No chat list model")
            return
        }
        guard let chat = ChatListModel.instance?.chat(id: originalChatID) else {
            RLog("No chat with id \(originalChatID)")
            return
        }
        guard let index = listModel.index(ofMessageID: forkAtMessageID, inChat: chat.id) else {
            RLog("No such message \(forkAtMessageID) in \(originalChatID)")
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

            let title = Self.forkedChatTitle(from: originalTitle, timestamp: nowString)
            let chatID = try client.create(chatWithTitle: title,
                                           terminalSessionGuid: chat.terminalSessionGuid,
                                           browserSessionGuid: chat.browserSessionGuid,
                                           initialMessages: initialMessages,
                                           permissions: chat.permissions)
            // The fork inherits the source chat's icon: icon generation
            // only runs when the AI mints a title, and a forked chat is
            // never renamed (its title is set at creation and
            // .renameChat messages are stripped from the clones above),
            // so without this it would show the default icon forever
            // next to its near-identical sibling. setIcon is the single
            // funnel for icon writes; both this and create's insert post
            // their notifications in the same runloop turn, so no
            // default-icon flash is visible. Non-fatal: a failed icon
            // write must not abort loading the freshly forked chat.
            do {
                try listModel.setIcon(chat.icon, forChatID: chatID)
            } catch {
                RLog("Failed to copy icon to forked chat \(chatID): \(error)")
            }

            // Inherit the source chat's blobs for the retained prefix so the fork
            // keeps the prompt cache instead of re-migrating on its first turn. Only
            // when the retained prefix is FULLY linked: the retained messages'
            // firstBlobRefs must equal the source's blob prefix, in order. Any
            // migration-era unlinked round makes it copy nothing and fall back to
            // re-migration (safe) rather than risk a history that does not match the
            // copied blobs. Blobs are copied with fresh blobIDs and the clones'
            // firstBlobRefs are remapped to them (clone() cleared the stale source ref).
            let sourceBlobs = listModel.chatDatabase.blobs(inChat: originalChatID)
            let retainedRefs = sourceMessages.compactMap { $0.firstBlobRef }
            if let retainedBlobs = ChatBlobAssembler.forkBlobPrefix(sourceBlobs: sourceBlobs,
                                                                    retainedBlobRefs: retainedRefs) {
                var blobIDMap = [String: String]()
                for blob in retainedBlobs {
                    let newBlobID = UUID()
                    let copy = ChatBlob(blobID: newBlobID, chatID: chatID,
                                        blobProtocol: blob.blobProtocol, role: blob.role,
                                        payload: blob.payload, responseID: blob.responseID,
                                        tokenCount: blob.tokenCount)
                    if listModel.chatDatabase.appendBlob(copy) != nil {
                        blobIDMap[blob.blobID.uuidString] = newBlobID.uuidString
                    }
                }
                if let blobProtocol = chat.blobProtocol {
                    try? listModel.setBlobProtocol(blobProtocol, forChatID: chatID)
                }
                for sourceMessage in sourceMessages {
                    if let oldRef = sourceMessage.firstBlobRef,
                       let newRef = blobIDMap[oldRef],
                       let newMessageID = uuidMap[sourceMessage.uniqueID] {
                        listModel.setFirstBlobRef(newRef, forMessageID: newMessageID, inChat: chatID)
                    }
                }
            }

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

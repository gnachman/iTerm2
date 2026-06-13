//
//  ChatListModel.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

// In-memory cache of chat rows and their messages. Drives the chat
// list UI; chats live in a single array regardless of mode and are
// distinguished at dispatch time by Chat.orchestrationEnabled.
class ChatListModel: ChatListDataSource {
    static let metadataDidChange = Notification.Name("ChatListModelMetadataDidChange")
    // Posted when a chat row is removed from storage. userInfo["chatID"]
    // carries the deleted chat's ID. Observed by ChatService to drop
    // any in-flight ChatAgent (and its OrchestratorDispatcher, with
    // its NotificationCenter observers) so deleting a chat doesn't
    // leak the agent for the lifetime of the process.
    static let chatWasDeleted = Notification.Name("ChatListModelChatWasDeleted")
    static let chatIDUserInfoKey = "chatID"
    private static var _instance: ChatListModel?
    static var instance: ChatListModel? {
        if _instance == nil,
           let db = ChatDatabase.instance {
            _instance = ChatListModel(database: db)
        }
        return _instance
    }

    private var chatStorage: DatabaseBackedArray<Chat>
    private var messageStorage = [String: DatabaseBackedArray<Message>]()
    private let database: ChatDatabase

    var count: Int { chatStorage.count }

    init?(database: ChatDatabase) {
        guard let chats = database.chats else {
            return nil
        }
        self.database = database
        self.chatStorage = chats
    }

    // MARK: - Chat-level operations

    func chat(id: String) -> Chat? {
        let result = chatStorage.first { $0.id == id }
        if let result,
           !result.permissions.isEmpty,
           !result.orchestrationEnabled {
            // Session-bound side effect: load the chat's encoded
            // permissions into RemoteCommandExecutor so subsequent
            // tool calls see the right policy. We deliberately do NOT
            // reload when the chat is in orchestration mode: the
            // session-bound RemoteCommand gate doesn't apply there
            // (orchestration uses its own claim model), so loading
            // would just thrash the executor singleton with policy
            // that has no effect. Preserving the stored permissions
            // string also means a future orchestration-disable
            // restores the user's prior session-bound policy without
            // having to round-trip through a schema migration.
            RemoteCommandExecutor.instance.load(encodedPermissions: result.permissions)
        }
        return result
    }

    func index(of chatID: String) -> Int? {
        return chatStorage.firstIndex {
            $0.id == chatID
        }
    }

    func chat(at index: Int) -> Chat {
        return chatStorage[index]
    }

    func add(chat: Chat) throws {
        try chatStorage.prepend(chat)
        postMetadataChange()
    }

    func delete(chatID: String) throws {
        guard let i = index(of: chatID) else {
            return
        }
        // Drop the persisted Message rows BEFORE removing the in-memory
        // handle. Otherwise the SQLite rows referencing the deleted
        // chatID leak forever (no foreign-key constraint enforces
        // cascade), and disk usage grows monotonically across the user's
        // entire deletion history.
        if let messages = messages(forChat: chatID, createIfNeeded: false) {
            do {
                try messages.removeAll(where: { _ in true })
            } catch {
                DLog("Failed to delete messages for chat \(chatID): \(error)")
            }
        }
        try chatStorage.remove(at: i)
        messageStorage.removeValue(forKey: chatID)
        NotificationCenter.default.post(
            name: Self.chatWasDeleted,
            object: nil,
            userInfo: [Self.chatIDUserInfoKey: chatID])
        postMetadataChange()
    }

    private func bump(chatID: String) throws {
        guard let i = index(of: chatID) else { return }
        var temp = chatStorage[i]
        try chatStorage.remove(at: i)
        temp.lastModifiedDate = Date()
        try chatStorage.prepend(temp)
        postMetadataChange()
    }

    private func rename(chatID: String, newName: String) throws {
        guard let i = index(of: chatID) else { return }
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNewName.isEmpty {
            // Defense in depth: ChatAgent sanitizes model-supplied titles
            // before publishing, but nothing stops a future producer from
            // publishing a blank .renameChat. Never blank the title.
            DLog("Ignoring rename of \(chatID) to a blank title")
            return
        }
        if chatStorage[i].title == trimmedNewName {
            // A no-op rename must not rewrite the row or reload the list.
            return
        }
        try chatStorage.modify(at: i) { chat in
            chat.title = trimmedNewName
            // The icon is drawn from the title, so a title change
            // invalidates it. Behavior-neutral for the one current
            // producer (ChatAgent renames a chat once, while its icon is
            // still nil, and regenerates afterward), but it makes any
            // future rename path correct by default: worst case is the
            // default icon until something regenerates, never a stale
            // icon for the previous title.
            chat.icon = nil
        }
        postMetadataChange()
    }

    // Persists an AI-generated icon (delivered by ChatAgent after it
    // mints a title) or copies one to a new chat (the fork path, since a
    // forked chat is never renamed and would otherwise keep the default
    // icon forever). Nil clears the icon back to the default; the no-op
    // guard matters because the common failure path delivers nil right
    // after rename() already cleared the icon, which must not cost a row
    // rewrite and a list reload. The notification carries the chatID so
    // the list can reload just this row: an icon can't change row height
    // or order.
    func setIcon(_ data: Data?, forChatID chatID: String) throws {
        guard let i = index(of: chatID) else { return }
        if chatStorage[i].icon == data {
            return
        }
        try chatStorage.modify(at: i) { chat in
            chat.icon = data
        }
        postMetadataChange(chatID: chatID)
    }

    // When the change is scoped to one chat AND cannot affect row height
    // or order (currently only icon changes), pass its ID so observers
    // can reload a single row instead of every cell.
    private func postMetadataChange(chatID: String? = nil) {
        let userInfo: [AnyHashable: Any]? = chatID.map { [Self.chatIDUserInfoKey: $0] }
        NotificationCenter.default.post(name: Self.metadataDidChange,
                                        object: nil,
                                        userInfo: userInfo)
    }

    // MARK: - Message-level operations

    func messages(forChat chatID: String,
                  createIfNeeded: Bool) -> DatabaseBackedArray<Message>? {
        if let array = messageStorage[chatID] {
            return array
        }
        if let array = database.messages(inChat: chatID) {
            messageStorage[chatID] = array
            return array
        }
        if createIfNeeded {
            let array = database.messages(inChat: chatID)
            messageStorage[chatID] = array
            return array
        }
        return nil
    }

    func index(ofMessageID messageID: UUID, inChat chatID: String) -> Int? {
        return messages(forChat: chatID,
                        createIfNeeded: false)?.firstIndex { $0.uniqueID == messageID }
    }

    func snippet(forChatID chatID: String) -> String? {
        if let array = messageStorage[chatID] {
            return array.last { $0.snippetText != nil }?.snippetText
        }
        for message in database.messageReverseIterator(inChat: chatID) {
            if let snippet = message.snippetText {
                return snippet
            }
        }
        return nil
    }

    func delete(chatID: String, messageIDs: [UUID]) {
        guard let messages = messages(forChat: chatID, createIfNeeded: false) else {
            return
        }
        do {
            try messages.removeAll(where: { messageIDs.contains($0.uniqueID) })
        } catch {
            DLog("Failed to delete messages from chat \(chatID): \(error)")
        }
    }

    // MARK: - Append

    func append(message: Message, toChatID chatID: String) throws {
        if try handlePreAppendMutation(message: message, chatID: chatID) {
            return
        }

        try messages(forChat: chatID, createIfNeeded: true)?.append(message)

        switch message.content {
        case .renameChat(let string):
            try rename(chatID: chatID, newName: string)
        case .vectorStoreCreated:
            // System-generated, no user input. Don't bump the chat to
            // the top of the recents list just because a vector store
            // finished indexing.
            break
        default:
            try bump(chatID: chatID)
        }

        // Session-bound side effect: track the vector store ID that a
        // .vectorStoreCreated message announces. No-op for
        // orchestration chats (the message type doesn't appear).
        if case let .vectorStoreCreated(id) = message.content {
            try setVectorStore(chatID: chatID, vectorStoreID: id)
        }
    }

    private func handlePreAppendMutation(message: Message, chatID: String) throws -> Bool {
        switch message.content {
        case let .append(string: chunk, uuid: uuid):
            if let i = index(ofMessageID: uuid, inChat: chatID),
               let messages = messages(forChat: chatID, createIfNeeded: false) {
                var existing = messages[i]
                existing.removeReasoningStatusSubparts()
                existing.append(chunk, useMarkdownIfAmbiguous: true)
                try messages.set(at: i, existing)
            } else {
                DLog("Drop append \u{201C}\(chunk)\u{201D} of nonexistent message \(uuid)")
            }
            return true

        case let .appendAttachment(attachment: attachment, uuid: uuid):
            if let i = index(ofMessageID: uuid, inChat: chatID),
               let messages = messages(forChat: chatID, createIfNeeded: false) {
                var existing = messages[i]
                let storeID = (message.author == .user)
                    ? chat(id: chatID)?.vectorStore
                    : nil
                existing.append(attachment, vectorStoreID: storeID)
                try messages.set(at: i, existing)
            } else {
                DLog("Drop append attachment \(attachment) of nonexistent message \(uuid)")
            }
            return true

        case let .explanationResponse(_, update, _):
            guard let update else { return false }
            if let messageID = update.messageID,
               let i = index(ofMessageID: messageID, inChat: chatID),
               let messages = messages(forChat: chatID, createIfNeeded: false) {
                var existing = messages[i]
                existing.content = message.content
                try messages.set(at: i, existing)
            } else {
                DLog("Drop explanation response update \(update)")
            }
            return true

        case .commit(let streamID):
            // Final harvest: removeReasoningStatusSubparts normally fires on each text
            // chunk via the .append case above, which moves reasoning subparts
            // off the body and into agentReasoning. A stream that delivers
            // only reasoning attachments and then ends (no text chunks ever
            // arrived) would skip that path entirely, leaving reasoning stuck
            // in the body as statusUpdate subparts and agentReasoning nil —
            // which then breaks the next-turn round-trip for DeepSeek thinking
            // mode. Run the harvest once more here so commit is always the
            // settling point.
            if let i = index(ofMessageID: streamID, inChat: chatID),
               let messages = messages(forChat: chatID, createIfNeeded: false) {
                var existing = messages[i]
                existing.removeReasoningStatusSubparts()
                try messages.set(at: i, existing)
            }
            return true

        case .plainText, .markdown, .explanationRequest, .remoteCommandRequest,
                .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat,
                .setPermissions, .terminalCommand, .multipart, .vectorStoreCreated,
                .userCommand, .watcherEvent:
            return false
        }
    }

    // MARK: - Search

    func chatSearchResultsIterator(query: String) -> AnySequence<ChatSearchResult> {
        return database.searchResultSequence(forQuery: query)
    }

    // MARK: - ChatListDataSource

    func numberOfChats(in chatListViewController: ChatListViewController) -> Int {
        return count
    }

    func chatListViewController(_ chatListViewController: ChatListViewController, chatAt index: Int) -> Chat {
        return chat(at: index)
    }

    func chatListViewController(_ viewController: ChatListViewController,
                                indexOfChatID chatID: String) -> Int? {
        return index(of: chatID)
    }

    // MARK: - Session-binding helpers (session-bound chats)

    func firstIndex(forGuid guid: String) -> Int? {
        return chatStorage.firstIndex { chat in
            chat.terminalSessionGuid == guid || chat.browserSessionGuid == guid
        }
    }

    func setTerminalGuid(for chatID: String, to guid: String?) throws {
        if let i = index(of: chatID) {
            if guid != nil {
                it_assert(chatStorage[i].orchestrationEnabled == false,
                          "Refusing to link a terminal session to an orchestration-mode chat \(chatID). Orchestration and session binding are mutually exclusive; toggle orchestration off first via setOrchestrationEnabled(false, forChatID:).")
            }
            try chatStorage.modify(at: i) { chat in
                chat.terminalSessionGuid = guid
            }
        }
    }

    func setBrowserGuid(for chatID: String, to guid: String?) throws {
        if let i = index(of: chatID) {
            if guid != nil {
                it_assert(chatStorage[i].orchestrationEnabled == false,
                          "Refusing to link a browser session to an orchestration-mode chat \(chatID). Orchestration and session binding are mutually exclusive; toggle orchestration off first via setOrchestrationEnabled(false, forChatID:).")
            }
            try chatStorage.modify(at: i) { chat in
                chat.browserSessionGuid = guid
            }
        }
    }

    func lastChat(guid: String) -> Chat? {
        return chatStorage.last { chat in
            chat.terminalSessionGuid == guid || chat.browserSessionGuid == guid
        }
    }

    // chatStorage is kept ordered most-recent-first (new chats prepend; a
    // bump/rename re-prepends), so the first match is the chat with the
    // most recent activity for the given session guid.
    func mostRecentChat(forGuid guid: String) -> Chat? {
        return chatStorage.first { chat in
            chat.terminalSessionGuid == guid || chat.browserSessionGuid == guid
        }
    }

    func setPermission(chat chatID: String,
                       permission: RemoteCommandExecutor.Permission,
                       guid: String,
                       category: RemoteCommand.Content.PermissionCategory) throws {
        let rce = RemoteCommandExecutor.instance
        rce.setPermission(chatID: chatID,
                          permission: permission,
                          guid: guid,
                          category: category)
        guard let i = index(of: chatID) else {
            return
        }
        var chat = chatStorage[i]
        chat.permissions = rce.encodedPermissions(chatID: chatID)
        try chatStorage.set(at: i, chat)
    }

    private func setVectorStore(chatID: String, vectorStoreID: String) throws {
        if let i = index(of: chatID) {
            var temp = chatStorage[i]
            temp.vectorStore = vectorStoreID
            try chatStorage.set(at: i, temp)
            postMetadataChange()
        }
    }

    // MARK: - Orchestrator-mode accessors

    // Flip the chat between session-bound and orchestrator modes.
    // The two modes are mutually exclusive: enabling clears any
    // session/browser binding, the per-session remote-command
    // permissions, and the vector store; disabling clears claimed
    // workgroups and registered watchers. The on-disk row is updated
    // atomically and metadataDidChange fires so observers (chat
    // lists, pickers) refresh.
    //
    // Callers that need the in-flight ChatAgent dropped on mode
    // change must do so explicitly (e.g. ChatViewController) since
    // ChatService doesn't observe metadataDidChange directly.
    func setOrchestrationEnabled(_ enabled: Bool, forChatID chatID: String) throws {
        guard let i = index(of: chatID) else { return }
        try chatStorage.modify(at: i) { chat in
            chat.orchestrationEnabled = enabled
            if enabled {
                chat.terminalSessionGuid = nil
                chat.browserSessionGuid = nil
                chat.vectorStore = nil
                // Preserve chat.permissions across the toggle. It's
                // dormant in orchestration mode (chat(id:) skips the
                // RemoteCommandExecutor reload when orchestrationEnabled
                // is true), but keeping it means a later disable
                // restores the user's prior session-bound policy
                // without losing it.
            } else {
                chat.claimedScopes = []
                chat.watchers = []
            }
        }
        postMetadataChange()
    }

    func claimedScopes(forChatID chatID: String) -> Set<String> {
        return Set(chat(id: chatID)?.claimedScopes ?? [])
    }

    func setClaimedScopes(_ ids: Set<String>,
                                forChatID chatID: String) throws {
        guard let i = index(of: chatID) else { return }
        try chatStorage.modify(at: i) { chat in
            chat.claimedScopes = Array(ids)
        }
    }

    func watchers(forChatID chatID: String) -> [WorkgroupWatcher] {
        return chat(id: chatID)?.watchers ?? []
    }

    func setWatchers(_ watchers: [WorkgroupWatcher],
                     forChatID chatID: String) throws {
        guard let i = index(of: chatID) else { return }
        try chatStorage.modify(at: i) { chat in
            chat.watchers = watchers
        }
    }
}

struct PersonChat: Hashable {
    var participant: Participant
    var chatID: String
}

class TypingStatusModel {
    static let instance = TypingStatusModel()

    private var typing = Set<PersonChat>()

    func set(isTyping: Bool, participant: Participant, chatID: String) {
        let pc = PersonChat(participant: participant, chatID: chatID)
        if isTyping {
            typing.insert(pc)
        } else {
            typing.remove(pc)
        }
    }

    func isTyping(participant: Participant, chatID: String) -> Bool {
        let pc = PersonChat(participant: participant, chatID: chatID)
        return typing.contains(pc)
    }
}

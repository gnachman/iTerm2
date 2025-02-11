//
//  ChatViewControllerModel.swift
//  iTerm2
//
//  Created by George Nachman on 2/24/25.
//

protocol ChatViewControllerModelDelegate: AnyObject {
    func chatViewControllerModel(didInsertItemAtIndex: Int)
    func chatViewControllerModel(didRemoveItemsInRange range: Range<Int>)
    func chatViewControllerModel(didModifyItemsAtIndexes indexSet: IndexSet)
}

class ChatViewControllerModel {
    weak var delegate: ChatViewControllerModelDelegate?
    private let listModel: ChatListModel
    // Avoid streaming so quickly that we bog down recalculating textview geometry and parsing markdown.
    private let rateLimit = iTermRateLimitedUpdate(name: "reloadCell", minimumInterval: 1)
    private var pendingItemIdentities = Set<ChatViewControllerModel.Item.Identity>()
    var lastStreamingState = ClientLocal.Action.StreamingState.stopped

    enum Item: CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .message(let message): "<Message: \(message.message.content.shortDescription), pending: \(message.pending?.content.shortDescription ?? "(nil)")>"
            case .date(let date): "<Date: \(date)>"
            case .agentTyping: "<AgentTyping>"
            }
        }

        class UpdatableMessage {
            private(set) var message: Message
            var pending: Message?

            init(_ message: Message) {
                self.message = message
            }
            func commit() {
                if let pending {
                    message = pending
                }
            }
        }
        case message(UpdatableMessage)
        case date(DateComponents)
        case agentTyping

        enum Identity: Hashable {
            case message(UUID)
            case date(DateComponents)
            case agentTyping
        }

        var identity: Identity {
            switch self {
            case .message(let message): .message(message.message.uniqueID)
            case .date(let date): .date(date)
            case .agentTyping: .agentTyping
            }
        }

        var hasButtons: Bool {
            guard case .message(let message) = self else {
                return false
            }
            return !message.message.buttons.isEmpty
        }

        var existingMessage: UpdatableMessage? {
            switch self {
            case .message(let existing): existing
            default: nil
            }
        }
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

    private let alwaysAppendDate = false

    init(chat: Chat, listModel: ChatListModel) {
        self.listModel = listModel
        chatID = chat.id
        var lastDate: DateComponents?
        if let messages = listModel.messages(forChat: chatID, createIfNeeded: false) {
            for message in messages {
                if message.hiddenFromClient {
                    continue
                }
                let date = message.dateErasingTime
                if alwaysAppendDate || lastDate != date {
                    items.append(.date(date))
                }
                items.append(.message(Item.UpdatableMessage(message)))
                lastDate = Calendar.current.dateComponents([.year, .month, .day], from: message.sentDate)
                if case .clientLocal(let cl) = message.content,
                   case .streamingChanged(let state) = cl.action {
                    lastStreamingState = state
                }
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
        items.didModify = { [weak self] i in
            self?.delegate?.chatViewControllerModel(didModifyItemsAtIndexes: IndexSet(integer: i))
        }
    }

    private func scheduleCommit(_ item: Item) {
        if pendingItemIdentities.contains(item.identity) {
            return
        }
        pendingItemIdentities.insert(item.identity)
        rateLimit.performRateLimitedBlock { [weak self] in
            guard let self else {
                return
            }
            let indexes = pendingItemIdentities.compactMap {
                self.index(of: $0)
            }
            pendingItemIdentities.removeAll()
            guard !indexes.isEmpty else {
                return
            }
            for i in indexes {
                if case .message(let message) = self.items[i] {
                    message.commit()
                }
            }
            delegate?.chatViewControllerModel(didModifyItemsAtIndexes: IndexSet(indexes))
        }
    }

    private func didAppend(toMessageID messageID: UUID) {
        if let i = index(ofMessageID: messageID),
           let existing = items[i].existingMessage,
           let canonicalMessages = listModel.messages(forChat: chatID, createIfNeeded: false),
           let updated = canonicalMessages.firstIndex(where: { $0.uniqueID == messageID }) {
            // Streaming update. Place modified message in second position so rate limited
            // updates can be applied atomically.
            existing.pending = canonicalMessages[updated]
            scheduleCommit(items[i])
        }
    }

    func appendMessage(_ message: Message) {
        switch message.content {
        case .append(string: _, uuid: let uuid):
            didAppend(toMessageID: uuid)
            return
        case .explanationResponse(_, let update, markdown: _):
            if let messageID = update?.messageID {
                didAppend(toMessageID: messageID)
                return
            }
        default:
            break
        }
        let saved = showTypingIndicator
        showTypingIndicator = false
        defer {
            showTypingIndicator = saved
        }
        if let last = items.last,
           case .message(let lastMessage) = last,
           (alwaysAppendDate || message.dateErasingTime != lastMessage.message.dateErasingTime) {
            items.append(.date(message.dateErasingTime))
        }
        items.append(.message(Item.UpdatableMessage(message)))
    }

    func commit() {
        rateLimit.force()
    }

    func index(of identity: Item.Identity) -> Int? {
        return items.firstIndex {
            $0.identity == identity
        }
    }

    // Returns true for all messages message[j] for j>i, test(message[j]) is false. Returns true if there are no messages after i.
    private func indexIsLastMessage(_ i: Int, passingTest test: (Message) -> Bool) -> Bool {
        if case .message = items[i] {
            for j in (i + 1)..<items.count {
                if case .message(let message) = items[j], test(message.message) {
                    return false
                }
            }
            return true
        } else {
            return false
        }
    }

    func indexIsLastMessage(_ i: Int) -> Bool {
        return indexIsLastMessage(i, passingTest: { _ in true })
    }

    func index(ofMessageID messageID: UUID) -> Int? {
        return items.firstIndex {
            switch $0 {
            case .message(let candidate):
                return candidate.message.uniqueID == messageID
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

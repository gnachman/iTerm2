//
//  CompanionHostBridge.swift
//  iTerm2
//
//  The server end of the companion protocol. Given an established (Noise-
//  encrypted) transport, it decodes client requests and drives iTerm2's chat
//  system: listing chats and sessions, creating and deleting chats, publishing
//  user messages, and streaming chat updates back to the phone. It is the
//  mac-side mirror of the phone's CompanionSession.
//
//  The wire carries the real model types (Chat, Message); the only filtering
//  is hiddenFromClient, mirroring what the Mac's own chat UI renders.
//
//  Everything here runs on the main actor because ChatClient, ChatBroker, and
//  iTermController all require it. All outbound traffic is enqueued
//  synchronously (in main-actor order) onto a single outbox stream drained by
//  one task, so frames reach the transport in exactly the order they were
//  produced: replies never interleave with each other, and streamed .append
//  deltas cannot arrive scrambled.
//

import Foundation
import CompanionProtocol
import CompanionNoise

@MainActor
final class CompanionHostBridge {
    private let transport: MessageTransport
    private var receiveTask: Task<Void, Never>?
    private var subscriptions: [String: ChatBroker.Subscription] = [:]
    private var outbox: AsyncStream<HostEnvelope>.Continuation?
    private var outboxTask: Task<Void, Never>?

    /// Called once the transport closes remotely, so the owner can drop this
    /// bridge. A user-initiated stop() does not fire it.
    var onClose: (@MainActor () -> Void)?

    init(transport: MessageTransport) {
        self.transport = transport
    }

    func start() {
        ChatBroker.instance?.ensureServiceRunning()

        var continuation: AsyncStream<HostEnvelope>.Continuation!
        let stream = AsyncStream<HostEnvelope> { continuation = $0 }
        outbox = continuation
        outboxTask = Task { [transport] in
            for await envelope in stream {
                guard let data = try? WireCoding.encode(envelope) else { continue }
                do {
                    try await transport.send(data)
                } catch {
                    break
                }
            }
        }

        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    func stop() {
        // A user-initiated stop is not a remote disconnect; don't report one.
        onClose = nil
        receiveTask?.cancel()
        receiveTask = nil
        teardownStreams()
        let transport = self.transport
        Task { await transport.close() }
    }

    private func teardownStreams() {
        for subscription in subscriptions.values {
            subscription.unsubscribe()
        }
        subscriptions.removeAll()
        outbox?.finish()
        outbox = nil
        outboxTask?.cancel()
        outboxTask = nil
    }

    // MARK: Receive loop

    private func runReceiveLoop() async {
        while true {
            let frame: Data
            do {
                frame = try await transport.receive()
            } catch {
                break
            }
            guard let envelope = try? WireCoding.decode(ClientEnvelope.self, from: frame) else {
                // A frame we cannot decode (newer phone) is dropped, not fatal.
                continue
            }
            handle(envelope)
        }
        teardownStreams()
        onClose?()
    }

    private func handle(_ envelope: ClientEnvelope) {
        let requestID = envelope.requestID
        switch envelope.payload {
        case .listChatsAndSessions:
            send(.chatsAndSessions(chats: chatEntries(),
                                   sessions: CompanionSessionLister.sessions()),
                 requestID: requestID)
        case .createChat(let title, let mode):
            handleCreate(title: title, mode: mode, requestID: requestID)
        case .deleteChat(let chatID):
            do {
                guard let client = ChatClient.instance else {
                    throw CompanionMacError.chatSystemUnavailable
                }
                try client.delete(chatID: chatID)
            } catch {
                // The phone removed the row optimistically; tell it the Mac
                // disagrees so it can resync instead of silently diverging.
                send(.error(CompanionError(code: .internalError, message: "\(error)")),
                     requestID: requestID)
            }
        case .subscribe(let chatID):
            handleSubscribe(chatID: chatID, requestID: requestID)
        case .unsubscribe(let chatID):
            subscriptions[chatID]?.unsubscribe()
            subscriptions[chatID] = nil
        case .publish(let message, let chatID, _):
            handlePublish(message: message, toChatID: chatID)
        case .ping:
            send(.pong, requestID: requestID)
        }
    }

    // MARK: Handlers

    private func handleCreate(title: String,
                              mode: CompanionNewChatMode,
                              requestID: UInt64?) {
        guard let client = ChatClient.instance else {
            send(.error(CompanionError(code: .notPaired, message: "Chat system unavailable")),
                 requestID: requestID)
            return
        }
        let terminalSessionGuid: String?
        switch mode {
        case .orchestrator:
            terminalSessionGuid = nil
        case .session(let guid):
            terminalSessionGuid = guid
        }
        do {
            let chatID = try client.create(chatWithTitle: title,
                                           terminalSessionGuid: terminalSessionGuid,
                                           browserSessionGuid: nil,
                                           initialMessages: [],
                                           permissions: "")
            if let entry = entry(forChatID: chatID) {
                send(.chatCreated(entry: entry), requestID: requestID)
            } else {
                send(.error(CompanionError(code: .internalError, message: "Chat was not created")),
                     requestID: requestID)
            }
        } catch {
            send(.error(CompanionError(code: .internalError, message: "\(error)")),
                 requestID: requestID)
        }
    }

    private func handleSubscribe(chatID: String, requestID: UInt64?) {
        // Install the subscription BEFORE snapshotting history, with no
        // suspension point in between: both happen synchronously on the main
        // actor, so no message published by other main-actor code can fall
        // into a gap between "not in the history snapshot" and "not yet
        // subscribed". A delivery that lands after the subscription but
        // before the snapshot appears in both; the phone dedupes by uniqueID.
        subscriptions[chatID]?.unsubscribe()
        if let client = ChatClient.instance {
            subscriptions[chatID] = client.subscribe(chatID: chatID,
                                                     registrationProvider: nil) { [weak self] update in
                self?.handleBrokerUpdate(update, chatID: chatID)
            }
        }
        send(.history(chatID: chatID, messages: history(chatID: chatID)),
             requestID: requestID)
    }

    private func handlePublish(message: Message, toChatID chatID: String) {
        // The phone only sends user-authored content; ignore anything else.
        guard message.author == .user else {
            return
        }
        try? ChatClient.instance?.publishUserMessage(chatID: chatID, content: message.content)
    }

    private func handleBrokerUpdate(_ update: ChatBroker.Update, chatID: String) {
        switch update {
        case .delivery(let message, let deliveredChatID):
            // Mirror the Mac UI: bookkeeping messages are not rendered there
            // and are not forwarded here. Streaming .append deltas are visible
            // (not hidden) and flow through.
            guard !message.hiddenFromClient else { return }
            send(.delivery(message: message,
                           chatID: deliveredChatID,
                           partial: Self.isPartial(message.content)),
                 requestID: nil)
        case .typingStatus(let isTyping, let participant):
            send(.typingStatus(isTyping: isTyping, participant: participant, chatID: chatID),
                 requestID: nil)
        }
    }

    private static func isPartial(_ content: Message.Content) -> Bool {
        switch content {
        case .append, .appendAttachment:
            return true
        default:
            return false
        }
    }

    // MARK: Model projection

    private func chatEntries() -> [CompanionChatListEntry] {
        guard let model = ChatListModel.instance else { return [] }
        var result = [CompanionChatListEntry]()
        for index in 0..<model.count {
            let chat = model.chat(at: index)
            result.append(CompanionChatListEntry(chat: chat,
                                                 snippet: model.snippet(forChatID: chat.id)))
        }
        return result
    }

    private func entry(forChatID chatID: String) -> CompanionChatListEntry? {
        guard let chat = ChatListModel.instance?.chat(id: chatID) else { return nil }
        return CompanionChatListEntry(chat: chat,
                                      snippet: ChatListModel.instance?.snippet(forChatID: chatID))
    }

    private func history(chatID: String) -> [Message] {
        guard let model = ChatListModel.instance,
              let messages = model.messages(forChat: chatID, createIfNeeded: false) else {
            return []
        }
        var result = [Message]()
        for index in 0..<messages.count where !messages[index].hiddenFromClient {
            result.append(messages[index])
        }
        return result
    }

    // MARK: Sending

    /// Enqueue one envelope. Synchronous: enqueue order (main-actor order) is
    /// transmit order.
    private func send(_ payload: CompanionHostMessage, requestID: UInt64?) {
        outbox?.yield(HostEnvelope(requestID: requestID, payload: payload))
    }
}

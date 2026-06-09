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
//  Everything here runs on the main actor because ChatClient, ChatBroker, and
//  iTermController all require it. Transport I/O is async and hops off the main
//  actor while awaiting the network.
//

import Foundation
import CompanionProtocol
import CompanionNoise

@MainActor
final class CompanionHostBridge {
    private let transport: MessageTransport
    private var receiveTask: Task<Void, Never>?
    private var subscriptions: [String: ChatBroker.Subscription] = [:]

    /// Called once the transport closes, so the owner can drop this bridge.
    var onClose: (@MainActor () -> Void)?

    init(transport: MessageTransport) {
        self.transport = transport
    }

    func start() {
        ChatBroker.instance?.ensureServiceRunning()
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        for subscription in subscriptions.values {
            subscription.unsubscribe()
        }
        subscriptions.removeAll()
        let transport = self.transport
        Task { await transport.close() }
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
            await handle(envelope)
        }
        for subscription in subscriptions.values {
            subscription.unsubscribe()
        }
        subscriptions.removeAll()
        onClose?()
    }

    private func handle(_ envelope: ClientEnvelope) async {
        let requestID = envelope.requestID
        switch envelope.payload {
        case .listChatsAndSessions:
            await send(.chatsAndSessions(chats: chatDTOs(), sessions: CompanionSessionLister.sessions()),
                       requestID: requestID)
        case .createChat(let title, let mode):
            await handleCreate(title: title, mode: mode, requestID: requestID)
        case .deleteChat(let chatID):
            try? ChatClient.instance?.delete(chatID: chatID)
        case .subscribe(let chatID):
            await handleSubscribe(chatID: chatID, requestID: requestID)
        case .unsubscribe(let chatID):
            subscriptions[chatID]?.unsubscribe()
            subscriptions[chatID] = nil
        case .publish(let message, let chatID, _):
            handlePublish(message: message, toChatID: chatID)
        case .ping:
            await send(.pong, requestID: requestID)
        }
    }

    // MARK: Handlers

    private func handleCreate(title: String, mode: ChatModeDTO, requestID: UInt64?) async {
        guard let client = ChatClient.instance else {
            await send(.error(CompanionError(code: .notPaired, message: "Chat system unavailable")),
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
            if let chat = ChatListModel.instance?.chat(id: chatID) {
                await send(.chatCreated(chat: CompanionDTOMapping.chatDTO(
                    from: chat, snippet: ChatListModel.instance?.snippet(forChatID: chatID))),
                           requestID: requestID)
            } else {
                await send(.error(CompanionError(code: .internalError, message: "Chat was not created")),
                           requestID: requestID)
            }
        } catch {
            await send(.error(CompanionError(code: .internalError, message: "\(error)")),
                       requestID: requestID)
        }
    }

    private func handleSubscribe(chatID: String, requestID: UInt64?) async {
        await send(.history(chatID: chatID, messages: historyDTOs(chatID: chatID)),
                   requestID: requestID)

        subscriptions[chatID]?.unsubscribe()
        guard let client = ChatClient.instance else { return }
        let subscription = client.subscribe(chatID: chatID, registrationProvider: nil) { [weak self] update in
            self?.handleBrokerUpdate(update, chatID: chatID)
        }
        subscriptions[chatID] = subscription
    }

    private func handlePublish(message: MessageDTO, toChatID chatID: String) {
        guard let content = CompanionDTOMapping.messageContent(from: message.content) else {
            return
        }
        try? ChatClient.instance?.publishUserMessage(chatID: chatID, content: content)
    }

    private func handleBrokerUpdate(_ update: ChatBroker.Update, chatID: String) {
        switch update {
        case .delivery(let message, let deliveredChatID):
            guard let dto = CompanionDTOMapping.messageDTO(from: message) else { return }
            let partial = Self.isPartial(message.content)
            Task { await self.send(.delivery(message: dto, chatID: deliveredChatID, partial: partial),
                                   requestID: nil) }
        case .typingStatus(let isTyping, let participant):
            let mapped: ParticipantDTO = participant == .user ? .user : .agent
            Task { await self.send(.typingStatus(isTyping: isTyping, participant: mapped, chatID: chatID),
                                   requestID: nil) }
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

    private func chatDTOs() -> [ChatDTO] {
        guard let model = ChatListModel.instance else { return [] }
        var result = [ChatDTO]()
        for index in 0..<model.count {
            let chat = model.chat(at: index)
            result.append(CompanionDTOMapping.chatDTO(from: chat, snippet: model.snippet(forChatID: chat.id)))
        }
        return result
    }

    private func historyDTOs(chatID: String) -> [MessageDTO] {
        guard let model = ChatListModel.instance,
              let messages = model.messages(forChat: chatID, createIfNeeded: false) else {
            return []
        }
        var result = [MessageDTO]()
        for index in 0..<messages.count {
            if let dto = CompanionDTOMapping.messageDTO(from: messages[index]) {
                result.append(dto)
            }
        }
        return result
    }

    // MARK: Sending

    private func send(_ payload: CompanionHostMessage, requestID: UInt64?) async {
        let envelope = HostEnvelope(requestID: requestID, payload: payload)
        guard let data = try? WireCoding.encode(envelope) else { return }
        try? await transport.send(data)
    }
}

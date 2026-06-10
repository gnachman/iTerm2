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

    /// Called when the phone announces it is unpairing.
    var onPeerUnpaired: (@MainActor () -> Void)?

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
                let data: Data
                do {
                    data = try WireCoding.encode(envelope)
                } catch {
                    DLog("Companion bridge: DROPPING unencodable envelope: \(error)")
                    continue
                }
                do {
                    try await transport.send(data)
                } catch {
                    DLog("Companion bridge: outbox send failed; outbox is dead: \(error)")
                    break
                }
            }
            DLog("Companion bridge: outbox drained")
        }

        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    /// Tell the phone it has been unpaired, flush the outbox so the message
    /// actually reaches the wire, then tear down. Used by unpair; a plain
    /// stop() would race the farewell against the connection close.
    func announceUnpairedAndStop() async {
        DLog("Companion bridge: announcing unpair")
        onClose = nil
        for subscription in subscriptions.values {
            subscription.unsubscribe()
        }
        subscriptions.removeAll()
        send(.unpaired, requestID: nil)
        outbox?.finish()
        outbox = nil
        // Drain: the outbox task exits once it has sent everything enqueued
        // before finish(), including the farewell.
        await outboxTask?.value
        outboxTask = nil
        DLog("Companion bridge: farewell flushed; closing transport")
        // Tear down the receive side only AFTER the farewell is on the wire:
        // cancelling the receive task cancels the underlying connection (its
        // onCancel treats cancellation as abandoning the transport), which
        // would kill the farewell if done first.
        receiveTask?.cancel()
        receiveTask = nil
        await transport.close()
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
        case .selectSessionResponse(let chatID, let originalMessage, let sessionGuid, let terminal):
            handleSelectSessionResponse(chatID: chatID,
                                        originalMessage: originalMessage,
                                        sessionGuid: sessionGuid,
                                        terminal: terminal)
        case .remoteCommandDecision(let chatID, let messageUniqueID, let decision):
            handleRemoteCommandDecision(chatID: chatID,
                                        messageUniqueID: messageUniqueID,
                                        decision: decision)
        case .linkSession(let chatID, let sessionGuid, let terminal):
            performLinkSession(chatID: chatID, guid: sessionGuid, terminal: terminal)
        case .ping:
            send(.pong, requestID: requestID)
        case .unpairing:
            DLog("Companion bridge: peer is unpairing")
            onPeerUnpaired?()
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
            if case .orchestrator = mode {
                // create() already spun up a session-bound agent (its internal
                // setPermissions publish reaches ChatService), and an existing
                // agent never re-reads the flag. Mirror the mac toggle's exact
                // sequence: drop the agent and dispatcher FIRST, then set the
                // flag, so the next turn builds an orchestration-mode agent.
                ChatService.instance?.dropAgent(forChatID: chatID)
                OrchestratorClient.instance?.dropDispatcher(forChatID: chatID)
                try ChatListModel.instance?.setOrchestrationEnabled(true, forChatID: chatID)
                DLog("Companion bridge: chat \(chatID) created in orchestration mode")
            }
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
        // Publish the phone's Message verbatim so its uniqueID survives the
        // round trip: the delivery then matches the phone's optimistic local
        // echo (which upserts by uniqueID) instead of duplicating the bubble.
        var toPublish = message
        toPublish.chatID = chatID
        try? ChatClient.instance?.publish(message: toPublish, toChatID: chatID, partial: false)
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

    // MARK: Interactive message responses (mirroring ChatViewController)

    private func performLinkSession(chatID: String, guid: String, terminal: Bool) {
        guard let listModel = ChatListModel.instance else { return }
        do {
            if terminal {
                try listModel.setTerminalGuid(for: chatID, to: guid)
            } else {
                try listModel.setBrowserGuid(for: chatID, to: guid)
            }
            let name = iTermController.sharedInstance().anySession(withGUID: guid)?.name ?? guid
            try ChatClient.instance?.publishNotice(
                chatID: chatID,
                notice: "This chat has been linked to \(terminal ? "terminal" : "browser") session “\(name)”.")
            DLog("Companion bridge: linked \(terminal ? "terminal" : "browser") session \(guid) to chat \(chatID)")
        } catch {
            DLog("Companion bridge: linkSession failed: \(error)")
            send(.error(CompanionError(code: .internalError, message: "\(error)")), requestID: nil)
        }
    }

    private func declineRemoteCommand(chatID: String,
                                      requestUUID: UUID,
                                      message: Message,
                                      text: String) {
        try? ChatClient.instance?.respondSuccessfullyToRemoteCommandRequest(
            inChat: chatID,
            requestUUID: requestUUID,
            message: text,
            functionCallName: message.functionCallName ?? "Unknown function call name",
            functionCallID: message.functionCallID,
            userNotice: nil)
    }

    private func handleSelectSessionResponse(chatID: String,
                                             originalMessage: Message,
                                             sessionGuid: String?,
                                             terminal: Bool) {
        guard let client = ChatClient.instance else { return }
        if let sessionGuid {
            DLog("Companion bridge: select-session resolved with \(sessionGuid); republishing original")
            performLinkSession(chatID: chatID, guid: sessionGuid, terminal: terminal)
            try? client.publish(message: originalMessage, toChatID: chatID, partial: false)
        } else {
            DLog("Companion bridge: select-session declined")
            declineRemoteCommand(chatID: chatID,
                                 requestUUID: originalMessage.uniqueID,
                                 message: originalMessage,
                                 text: "The user declined to allow this function call to execute.")
        }
    }

    private func handleRemoteCommandDecision(chatID: String,
                                             messageUniqueID: UUID,
                                             decision: CompanionRemoteCommandDecision) {
        guard let client = ChatClient.instance,
              let listModel = ChatListModel.instance,
              let messages = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return
        }
        var found: Message?
        for index in 0..<messages.count where messages[index].uniqueID == messageUniqueID {
            found = messages[index]
            break
        }
        guard let message = found,
              case .remoteCommandRequest(let payload, _) = message.content,
              let remoteCommand = payload.classic else {
            DLog("Companion bridge: remoteCommandDecision for unknown message \(messageUniqueID)")
            return
        }
        DLog("Companion bridge: remote command decision \(decision.rawValue) for \(messageUniqueID)")
        let category = remoteCommand.content.permissionCategory
        let browser = category.isBrowserSpecific
        let guid = browser ? listModel.chat(id: chatID)?.browserSessionGuid
                           : listModel.chat(id: chatID)?.terminalSessionGuid
        switch decision {
        case .denyOnce, .denyAlways:
            if decision == .denyAlways, let guid {
                try? listModel.setPermission(chat: chatID,
                                             permission: .never,
                                             guid: guid,
                                             category: category)
            }
            declineRemoteCommand(chatID: chatID,
                                 requestUUID: messageUniqueID,
                                 message: message,
                                 text: "The user declined to allow this function call to execute.")
        case .allowOnce, .allowAlways:
            guard let guid,
                  let session = iTermController.sharedInstance().anySession(withGUID: guid) else {
                try? client.publishNotice(chatID: chatID,
                                          notice: "This chat is not linked to any \(browser ? "web browser" : "terminal") session.")
                declineRemoteCommand(chatID: chatID,
                                     requestUUID: messageUniqueID,
                                     message: message,
                                     text: "The user did not link a \(browser ? "web browser" : "terminal") session to chat, so the function could not be run.")
                return
            }
            if decision == .allowAlways {
                try? listModel.setPermission(chat: chatID,
                                             permission: .always,
                                             guid: guid,
                                             category: category)
            }
            try? client.performRemoteCommand(remoteCommand,
                                             in: session,
                                             chatID: chatID,
                                             messageUniqueID: messageUniqueID)
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

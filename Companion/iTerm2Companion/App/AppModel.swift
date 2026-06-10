//
//  AppModel.swift
//  iTerm2 Companion
//
//  The app-wide coordinator: owns the navigation route, establishes the paired
//  connection (rendezvous then Noise XK handshake), and keeps the UI's
//  chat/session/message state in sync with host events. State is held in the
//  real model types (Chat, Message) shared with the Mac app.
//

import Foundation
import SwiftUI
import os
import CompanionProtocol
import CompanionNoise
import CompanionTransport

private let logger = Logger(subsystem: "com.googlecode.iterm2.companion", category: "companion")

@MainActor
final class AppModel: ObservableObject {
    enum Route: Equatable {
        case launch
        case scanning
        case pairing
        case home
        case create
        case conversation(chatID: String)
    }

    @Published var route: Route = .launch
    @Published var chats: [CompanionChatListEntry] = []
    @Published var sessions: [CompanionSessionSummary] = []

    // Conversation state for the open chat.
    @Published var openChatID: String?
    @Published var messages: [Message] = []
    @Published var isAgentTyping = false

    /// A user-facing error for the pairing screen. Nil while in progress.
    @Published var pairingError: String?

    private var client: CompanionClient?

    // How the phone reaches the mac. Transport-agnostic: today this is just the
    // local-network connector, but a relay-server or iCloud connector can be
    // appended here and RaceTransportConnector will use whichever connects
    // first. Nothing else in the app knows which transport won.
    private let connector: TransportConnector

    init(connector: TransportConnector = RaceTransportConnector([BonjourTransportConnector()])) {
        self.connector = connector
        // Route the transport/crypto layers' diagnostics into the unified log
        // (visible in Console.app and `log stream`).
        CompanionLog.handler = { message in
            logger.info("\(message, privacy: .public)")
        }
    }

    // MARK: Navigation

    func beginScanning() {
        pairingError = nil
        route = .scanning
    }

    func cancelToLaunch() {
        route = .launch
    }

    func beginCreateChat() {
        route = .create
    }

    // MARK: Pairing

    /// Called by the scanning screen once it has a valid pairing code. Moves to
    /// the pairing screen and runs the rendezvous + handshake.
    func pair(with code: PairingCode) {
        logger.info("Pairing started (pid \(code.pairingID, privacy: .public))")
        route = .pairing
        pairingError = nil
        Task {
            do {
                try await establish(code: code)
                logger.info("Pairing succeeded; loading home")
                try await loadHome()
            } catch {
                logger.error("Pairing failed: \(String(describing: error), privacy: .public)")
                pairingError = userMessage(for: error)
            }
        }
    }

    private func establish(code: PairingCode) async throws {
        // A retry (PairingView "Try Again") can re-enter establish after a prior
        // attempt already built a client. Tear the old one down so its
        // connection and receive loop do not linger.
        if let existing = client {
            client = nil
            await existing.close()
        }

        let identity = try PhoneIdentity.keyPair()
        let transport = try await connector.connect(
            to: PairingRendezvous(pairingID: code.pairingID),
            timeout: 30)
        let channel = try await NoiseHandshake.perform(
            role: .initiator,
            transport: transport,
            localKeyPair: identity,
            remoteStaticPublicKey: code.responderStaticPublicKey,
            prologue: code.handshakePrologue())
        let client = CompanionClient(session: CompanionSession(transport: channel))
        await client.start { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
        self.client = client
    }

    // MARK: Home

    func loadHome() async throws {
        guard let client else { return }
        let (chats, sessions) = try await client.listChatsAndSessions()
        self.chats = chats
        self.sessions = sessions
        route = .home
    }

    func refreshHome() {
        Task {
            do {
                try await loadHome()
            } catch {
                pairingError = userMessage(for: error)
            }
        }
    }

    // MARK: Create

    func createChat(mode: CompanionNewChatMode) {
        guard let client else { return }
        Task {
            do {
                let title = (mode == .orchestrator) ? "Orchestrator" : "New Chat"
                let entry = try await client.createChat(title: title, mode: mode)
                if !chats.contains(where: { $0.chat.id == entry.chat.id }) {
                    chats.insert(entry, at: 0)
                }
                await openConversation(chatID: entry.chat.id)
            } catch {
                pairingError = userMessage(for: error)
            }
        }
    }

    // MARK: Conversation

    func openChat(_ chatID: String) {
        Task { await openConversation(chatID: chatID) }
    }

    func openConversation(chatID: String) async {
        guard let client else { return }
        do {
            let history = try await client.subscribe(chatID: chatID)
            openChatID = chatID
            messages = history.filter { !$0.hiddenFromClient }
            isAgentTyping = false
            route = .conversation(chatID: chatID)
        } catch {
            pairingError = userMessage(for: error)
        }
    }

    func leaveConversation() {
        if let chatID = openChatID, let client {
            Task { try? await client.unsubscribe(chatID: chatID) }
        }
        openChatID = nil
        messages = []
        isAgentTyping = false
        route = .home
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chatID = openChatID, let client else { return }
        let message = Message(chatID: chatID,
                              author: .user,
                              content: .plainText(trimmed, context: nil),
                              sentDate: Date(),
                              uniqueID: UUID())
        // Optimistic local echo so the bubble appears immediately.
        messages.append(message)
        Task {
            try? await client.publish(message, toChatID: chatID)
        }
    }

    // MARK: Host events

    private func handle(event: CompanionHostMessage) {
        switch event {
        case .delivery(let message, let chatID, _):
            guard chatID == openChatID, !message.hiddenFromClient else { return }
            apply(message)
        case .typingStatus(let isTyping, let participant, let chatID):
            if chatID == openChatID, participant == .agent {
                isAgentTyping = isTyping
            }
        default:
            break
        }
    }

    /// Apply one delivered message: streaming deltas mutate the targeted bubble
    /// in place (using the same Message.append logic the Mac uses); everything
    /// else upserts by uniqueID.
    private func apply(_ message: Message) {
        switch message.content {
        case .append(let string, let uuid):
            applyStreamDelta(to: uuid, fallbackDate: message.sentDate) { target in
                target.append(string, useMarkdownIfAmbiguous: true)
            } orStartWith: {
                .markdown(string)
            }
        case .appendAttachment(let attachment, let uuid):
            applyStreamDelta(to: uuid, fallbackDate: message.sentDate) { target in
                target.append(attachment, vectorStoreID: nil)
            } orStartWith: {
                .multipart([.attachment(attachment)], vectorStoreID: nil)
            }
        case .commit:
            break
        default:
            if let index = messages.firstIndex(where: { $0.uniqueID == message.uniqueID }) {
                messages[index] = message
            } else {
                messages.append(message)
            }
        }
    }

    /// Mutate the streamed message with `mutate`, or start a fresh agent bubble
    /// with `orStartWith` if no message with that id exists yet. Message.append
    /// traps on non-text content, so only text-bearing targets are mutated.
    private func applyStreamDelta(to messageID: UUID,
                                  fallbackDate: Date,
                                  mutate: (inout Message) -> Void,
                                  orStartWith makeContent: () -> Message.Content) {
        if let index = messages.firstIndex(where: { $0.uniqueID == messageID }) {
            switch messages[index].content {
            case .plainText, .markdown, .multipart:
                mutate(&messages[index])
            default:
                break
            }
        } else {
            messages.append(Message(chatID: openChatID ?? "",
                                    author: .agent,
                                    content: makeContent(),
                                    sentDate: fallbackDate,
                                    uniqueID: messageID))
        }
    }

    private func userMessage(for error: Error) -> String {
        if case TransportError.localNetworkAccessDenied = error {
            return "Local network access is off. Enable it in Settings > Privacy & Security > Local Network > iTerm2 Companion, then try again."
        }
        if let companion = error as? CompanionError {
            return companion.message
        }
        if let parseError = error as? PairingCode.ParseError {
            return parseError.userMessage
        }
        return (error as NSError).localizedDescription
    }
}

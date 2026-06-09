//
//  AppModel.swift
//  iTerm2 Companion
//
//  The app-wide coordinator: owns the navigation route, establishes the paired
//  connection (Bonjour rendezvous then Noise XK handshake), and keeps the UI's
//  chat/session/message state in sync with host events.
//

import Foundation
import SwiftUI
import CompanionProtocol
import CompanionNoise
import CompanionTransport

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
    @Published var chats: [ChatDTO] = []
    @Published var sessions: [SessionDTO] = []

    // Conversation state for the open chat.
    @Published var openChatID: String?
    @Published var messages: [MessageDTO] = []
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
        route = .pairing
        pairingError = nil
        Task {
            do {
                try await establish(code: code)
                try await loadHome()
            } catch {
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

    func createChat(mode: ChatModeDTO) {
        guard let client else { return }
        Task {
            do {
                let title = (mode == .orchestrator) ? "Orchestrator" : "New Chat"
                let chat = try await client.createChat(title: title, mode: mode)
                if !chats.contains(where: { $0.id == chat.id }) {
                    chats.insert(chat, at: 0)
                }
                await openConversation(chatID: chat.id)
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
            messages = history
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
        // Optimistic local echo so the bubble appears immediately.
        let local = MessageDTO(uniqueID: UUID(),
                               author: .user,
                               content: .plainText(trimmed),
                               sentDate: Date())
        messages.append(local)
        Task {
            try? await client.publishUserMessage(chatID: chatID, text: trimmed)
        }
    }

    // MARK: Host events

    private func handle(event: CompanionHostMessage) {
        switch event {
        case .delivery(let message, let chatID, _):
            guard chatID == openChatID else { return }
            apply(message)
        case .typingStatus(let isTyping, let participant, let chatID):
            if chatID == openChatID, participant == .agent {
                isAgentTyping = isTyping
            }
        default:
            break
        }
    }

    /// Apply one delivered message: streaming deltas mutate an existing bubble,
    /// everything else upserts by uniqueID.
    private func apply(_ message: MessageDTO) {
        switch message.content {
        case .append(let string, let messageID):
            appendStreaming(string, to: messageID, fallback: message)
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

    private func appendStreaming(_ string: String, to messageID: UUID, fallback: MessageDTO) {
        if let index = messages.firstIndex(where: { $0.uniqueID == messageID }) {
            let existing = messages[index]
            let combined = (existing.snippetTextForStreaming ?? "") + string
            messages[index] = MessageDTO(uniqueID: existing.uniqueID,
                                         author: existing.author,
                                         content: .markdown(combined),
                                         sentDate: existing.sentDate)
        } else {
            // First delta for a not-yet-seen message: start a new agent bubble.
            messages.append(MessageDTO(uniqueID: messageID,
                                       author: .agent,
                                       content: .markdown(string),
                                       sentDate: fallback.sentDate))
        }
    }

    private func userMessage(for error: Error) -> String {
        if let companion = error as? CompanionError {
            return companion.message
        }
        if let parseError = error as? PairingCode.ParseError {
            return parseError.userMessage
        }
        return (error as NSError).localizedDescription
    }
}

private extension MessageDTO {
    /// The accumulated text of a streaming bubble, for appending the next delta.
    var snippetTextForStreaming: String? {
        switch content {
        case .markdown(let text), .plainText(let text):
            return text
        default:
            return nil
        }
    }
}

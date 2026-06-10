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
import Observation
import Network
import os
import CompanionProtocol
import CompanionNoise
import CompanionTransport

private let logger = Logger(subsystem: "com.googlecode.iterm2.companion", category: "companion")

/// Logs to the unified log AND, in debug builds, to stdout so every step is
/// visible in Xcode's console without fiddling with metadata filters. Output
/// matches iTerm2's DLog shape: timestamp, file:line, function, message.
func companionLog(_ message: String,
                  file: StaticString = #fileID,
                  line: UInt = #line,
                  function: StaticString = #function) {
    let basename = "\(file)".split(separator: "/").last.map(String.init) ?? "\(file)"
    let formatted = String(format: "%0.6f %@:%u (%@): %@",
                           Date().timeIntervalSince1970,
                           basename,
                           UInt32(line),
                           "\(function)",
                           message)
    // print only in debug (Xcode console would otherwise show each line twice,
    // once from stdout and once from the unified log).
#if DEBUG
    print(formatted)
#else
    logger.info("\(formatted, privacy: .public)")
#endif
}

/// Transport-layer messages arrive with their own call-site prefix (the
/// package embeds file:line); only the timestamp is added here.
func companionLogPreformatted(_ message: String) {
    let formatted = String(format: "%0.6f %@", Date().timeIntervalSince1970, message)
#if DEBUG
    print(formatted)
#else
    logger.info("\(formatted, privacy: .public)")
#endif
}

/// Run an async step with a deadline so a wedged network call surfaces as an
/// error (with the step's name) instead of an eternal spinner.
private func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                                      _ label: String,
                                      _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TransportError.connectionFailed("\(label) timed out after \(Int(seconds)) seconds")
        }
        guard let result = try await group.next() else {
            throw TransportError.closed
        }
        group.cancelAll()
        return result
    }
}

// @Observable (not ObservableObject): views re-render only for properties
// they read. That precision matters for navigation: with ObservableObject,
// unrelated mutations (loading a conversation's history) re-rendered the view
// containing the NavigationStack mid-transition, which killed the push
// animation.
@MainActor
@Observable
final class AppModel {
    /// Full-screen phases before (and including arrival at) the chat list.
    enum Phase: Equatable {
        case launch
        case scanning
        case pairing
        case home
    }

    /// Screens pushed onto the navigation stack once paired. Driving them
    /// through NavigationStack's path gives the standard slide transition and
    /// interactive swipe-back.
    enum Destination: Hashable {
        case create
        case conversation(chatID: String)
        case settings
    }

    var phase: Phase = .launch
    var navigationPath: [Destination] = [] {
        didSet {
            // Swipe-back and the back button mutate the path directly; when
            // the conversation gets popped, tear down its subscription.
            let hadConversation = oldValue.contains { if case .conversation = $0 { return true } else { return false } }
            let hasConversation = navigationPath.contains { if case .conversation = $0 { return true } else { return false } }
            if hadConversation && !hasConversation {
                didLeaveConversation()
            }
        }
    }
    var chats: [CompanionChatListEntry] = []
    var sessions: [CompanionSessionSummary] = []

    // Conversation state for the open chat.
    var openChatID: String?
    var messages: [Message] = []
    var isAgentTyping = false

    /// A user-facing error for the pairing screen. Nil while in progress.
    var pairingError: String?
    /// Step description for the pairing screen ("Searching for your Mac…").
    var pairingStatus = ""
    /// When the in-flight pairing attempt began; drives the elapsed counter.
    var pairingStartedAt: Date?
    /// True while a freshly pushed conversation is waiting for its history.
    var isLoadingConversation = false
    /// True while transparently re-establishing a dropped connection (shown
    /// as a banner; the user keeps their place in the UI).
    var isReconnecting = false

    private var pairingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// The code the current/last pairing attempt used, so Try Again can retry
    /// it instead of dumping the user at the scanner.
    private var activePairingCode: PairingCode?
    private var activeIsReconnect = false

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
            companionLogPreformatted(message)
        }
    }

    // MARK: Stored pairing

    private static let storedKeyDefault = "PairedResponderStaticKey"
    private static let storedPIDDefault = "PairedPairingID"

    /// The pairing from the last successful handshake. The responder key is
    /// public and the pid is not a secret, so UserDefaults is fine.
    var storedPairingCode: PairingCode? {
        let defaults = UserDefaults.standard
        guard let key = defaults.data(forKey: Self.storedKeyDefault),
              key.count == 32,
              let pid = defaults.string(forKey: Self.storedPIDDefault) else {
            return nil
        }
        return PairingCode(responderStaticPublicKey: key, pairingID: pid)
    }

    private func storePairing(_ code: PairingCode) {
        let defaults = UserDefaults.standard
        defaults.set(code.responderStaticPublicKey, forKey: Self.storedKeyDefault)
        defaults.set(code.pairingID, forKey: Self.storedPIDDefault)
    }

    func forgetStoredPairing() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.storedKeyDefault)
        defaults.removeObject(forKey: Self.storedPIDDefault)
    }

    /// Called once at launch: if a pairing is stored, reconnect to it instead
    /// of demanding a fresh QR scan.
    func handleLaunch() {
        guard phase == .launch, pairingTask == nil else { return }
        guard let code = storedPairingCode else { return }
        companionLog("Reconnecting to stored pairing (pid \(code.pairingID))")
        pair(with: code, isReconnect: true)
    }

    // MARK: Navigation

    func beginScanning() {
        pairingError = nil
        phase = .scanning
    }

    func cancelToLaunch() {
        phase = .launch
    }

    func beginCreateChat() {
        navigationPath.append(.create)
    }

    func beginSettings() {
        navigationPath.append(.settings)
    }

    /// Settings: sever the pairing entirely. Notifies the mac (so it destroys
    /// its key material too), deletes this device's identity and stored
    /// pairing, clears all state, and returns to the scanner.
    func disconnectFromMac() {
        companionLog("Disconnecting and forgetting this Mac")
        pairingTask?.cancel()
        pairingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        let oldClient = client
        client = nil
        Task {
            if let oldClient {
                try? await oldClient.sendUnpairing()
                await oldClient.close()
            }
        }
        forgetStoredPairing()
        PhoneIdentity.deleteKeyPair()
        activePairingCode = nil
        chats = []
        sessions = []
        messages = []
        openChatID = nil
        isAgentTyping = false
        isLoadingConversation = false
        isReconnecting = false
        navigationPath = []
        pairingError = nil
        pairingStartedAt = nil
        phase = .scanning
    }

    // MARK: Pairing

    /// True when this code was already consumed by a successful pairing.
    /// Scanning it again should fail immediately rather than time out.
    func isUsedPairingCode(_ code: PairingCode) -> Bool {
        storedPairingCode?.pairingID == code.pairingID
    }

    /// Called by the scanning screen once it has a valid pairing code (or at
    /// launch with the stored one). Moves to the pairing screen and runs the
    /// rendezvous + handshake.
    func pair(with code: PairingCode, isReconnect: Bool = false) {
        companionLog("Pairing started (pid \(code.pairingID), reconnect: \(isReconnect))")
        activePairingCode = code
        activeIsReconnect = isReconnect
        phase = .pairing
        pairingError = nil
        pairingStartedAt = Date()
        pairingStatus = isReconnect ? "Reconnecting to your Mac" : "Searching for your Mac"
        pairingTask?.cancel()
        pairingTask = Task {
            var attempt = 0
            while true {
                attempt += 1
                do {
                    try await establish(code: code)
                    pairingStatus = "Loading chats"
                    companionLog("Pairing succeeded; loading home")
                    try await loadHome()
                    companionLog("Home loaded")
                    storePairing(code)
                } catch is CancellationError {
                    companionLog("Pairing cancelled")
                } catch {
                    companionLog("Pairing attempt \(attempt) failed: \(String(describing: error))")
                    if isReconnect {
                        // Transient network trouble must never dead-end into
                        // re-pairing; keep trying until the user cancels.
                        pairingStatus = "Mac not found yet; retrying (attempt \(attempt + 1))"
                        do {
                            try await Task.sleep(nanoseconds: 5_000_000_000)
                            continue
                        } catch {
                            companionLog("Pairing retry loop cancelled")
                        }
                    } else {
                        pairingError = userMessage(for: error)
                    }
                }
                break
            }
            pairingStartedAt = nil
            pairingTask = nil
        }
    }

    /// Retry the same pairing the failed attempt used. The scanner is only for
    /// pairing a different Mac.
    func retryPairing() {
        guard let code = activePairingCode else {
            beginScanning()
            return
        }
        pair(with: code, isReconnect: activeIsReconnect)
    }

    /// The Cancel button on the pairing screen.
    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        pairingStartedAt = nil
        pairingError = nil
        phase = .launch
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
        companionLog("Connecting (discovery + TCP)…")
        let connector = self.connector
        let transport = try await connector.connect(
            to: PairingRendezvous(pairingID: code.pairingID),
            timeout: 30)
        companionLog("Transport connected; starting Noise handshake…")
        pairingStatus = "Securing the connection"
        let channel = try await withTimeout(15, "Noise handshake") {
            try await NoiseHandshake.perform(
                role: .initiator,
                transport: transport,
                localKeyPair: identity,
                remoteStaticPublicKey: code.responderStaticPublicKey,
                prologue: code.handshakePrologue())
        }
        companionLog("Handshake complete; channel established")
        let client = CompanionClient(session: CompanionSession(transport: channel))
        await client.start(onEvent: { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }, onClose: { [weak self] in
            Task { @MainActor in
                self?.connectionLost()
            }
        })
        self.client = client
    }

    // MARK: Home

    func loadHome() async throws {
        try await refreshLists()
        navigationPath = []
        phase = .home
    }

    private func refreshLists() async throws {
        let client = try await currentClient(label: "Refresh lists")
        companionLog("Requesting chat and session lists…")
        let (chats, sessions) = try await withTimeout(15, "Chat list request") {
            try await client.listChatsAndSessions()
        }
        companionLog("Received \(chats.count) chat(s), \(sessions.count) session(s)")
        self.chats = chats
        self.sessions = sessions
    }

    // MARK: Connection lifecycle

    /// Returns the live client, waiting (bounded) for an in-flight reconnect
    /// to produce one. Throws with a readable message if none arrives, so
    /// callers surface a real error instead of spinning forever.
    private func currentClient(label: String, timeout: TimeInterval = 20) async throws -> CompanionClient {
        if let client {
            return client
        }
        companionLog("\(label): not connected; waiting up to \(Int(timeout))s for reconnect")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 250_000_000)
            if let client {
                companionLog("\(label): connection is back; proceeding")
                return client
            }
        }
        companionLog("\(label): gave up waiting for a connection")
        throw TransportError.connectionFailed("Not connected to your Mac")
    }

    /// The session's receive loop died: the mac quit, restarted, or the
    /// network dropped. Reconnect with the stored pairing, keeping the user's
    /// place in the UI.
    private func connectionLost() {
        guard !isReconnecting else { return }
        companionLog("Connection lost")
        client = nil
        guard phase == .home else { return }
        guard let code = storedPairingCode else {
            phase = .scanning
            return
        }
        isReconnecting = true
        reconnectTask = Task {
            var attempt = 0
            while true {
                attempt += 1
                do {
                    try await establish(code: code)
                    companionLog("Reconnected (attempt \(attempt))")
                    try await refreshLists()
                    if let chatID = openChatID, !isLoadingConversation {
                        // Re-subscribe the open conversation on the new
                        // session. Skipped when a load is already parked in
                        // currentClient(); it resumes by itself.
                        openChatID = nil
                        conversationDidAppear(chatID: chatID)
                    }
                } catch is CancellationError {
                    // App-driven teardown; nothing to report.
                } catch {
                    // Keep the user's place and keep trying; transient network
                    // trouble must not dump them on the pairing screen.
                    companionLog("Reconnect attempt \(attempt) failed: \(String(describing: error))")
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        continue
                    } catch {
                        companionLog("Reconnect loop cancelled")
                    }
                }
                break
            }
            isReconnecting = false
        }
    }

    /// Called when the app returns to the foreground: sockets often die
    /// silently in the background, so probe before the user hits an error.
    func checkConnectionOnForeground() {
        guard phase == .home, let client, !isReconnecting else { return }
        Task {
            do {
                try await withTimeout(5, "Connection check") {
                    try await client.ping()
                }
            } catch {
                connectionLost()
            }
        }
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
        Task {
            do {
                let client = try await currentClient(label: "Create chat")
                let title = (mode == .orchestrator) ? "Orchestrator" : "New Chat"
                let entry = try await client.createChat(title: title, mode: mode)
                if !chats.contains(where: { $0.chat.id == entry.chat.id }) {
                    chats.insert(entry, at: 0)
                }
                openConversation(chatID: entry.chat.id, replacingPath: true)
            } catch {
                pairingError = userMessage(for: error)
            }
        }
    }

    // MARK: Conversation

    /// Called from ConversationView.onAppear. Chat rows are NavigationLinks,
    /// so the system performs the (animated) push itself; this just starts the
    /// history load for the chat that appeared.
    func conversationDidAppear(chatID: String) {
        guard openChatID != chatID else {
            return
        }
        openChatID = chatID
        messages = []
        isAgentTyping = false
        isLoadingConversation = true
        Task {
            await loadConversation(chatID: chatID)
        }
    }

    /// Programmatic open used by the Create flow: replaces the stack so back
    /// returns to Home, then lets conversationDidAppear load the history.
    func openConversation(chatID: String, replacingPath: Bool) {
        withAnimation {
            if replacingPath {
                navigationPath = [.conversation(chatID: chatID)]
            } else {
                navigationPath.append(.conversation(chatID: chatID))
            }
        }
    }

    private func loadConversation(chatID: String) async {
        companionLog("Loading conversation \(chatID)")
        do {
            let client = try await currentClient(label: "Load conversation")
            let history = try await withTimeout(15, "Loading the conversation") {
                try await client.subscribe(chatID: chatID)
            }
            // The user may have popped back (or opened another chat) while the
            // history was in flight.
            guard openChatID == chatID else {
                companionLog("Conversation \(chatID) no longer open; discarding history")
                return
            }
            messages = history.filter { !$0.hiddenFromClient }
            companionLog("Conversation loaded (\(messages.count) messages)")
        } catch {
            companionLog("Conversation load failed: \(String(describing: error))")
            guard openChatID == chatID else { return }
            messages = [Message(chatID: chatID,
                                author: .agent,
                                content: .clientLocal(ClientLocal(action: .notice(
                                    "Could not load this chat: \(userMessage(for: error))"))),
                                sentDate: Date(),
                                uniqueID: UUID())]
        }
        if openChatID == chatID {
            isLoadingConversation = false
        }
    }

    /// Called from the path observer once the conversation has been popped
    /// (back button or swipe); the pop animation is already underway.
    private func didLeaveConversation() {
        if let chatID = openChatID, let client {
            Task { try? await client.unsubscribe(chatID: chatID) }
        }
        openChatID = nil
        messages = []
        isAgentTyping = false
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chatID = openChatID else { return }
        let message = Message(chatID: chatID,
                              author: .user,
                              content: .plainText(trimmed, context: nil),
                              sentDate: Date(),
                              uniqueID: UUID())
        // Optimistic local echo so the bubble appears immediately.
        messages.append(message)
        Task {
            do {
                let client = try await currentClient(label: "Send message")
                try await client.publish(message, toChatID: chatID)
            } catch {
                companionLog("Send failed: \(String(describing: error))")
            }
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
        case .unpaired:
            handleRemoteUnpair()
        default:
            break
        }
    }

    /// The mac kicked this device: forget the pairing and go back to the scan
    /// screen so the user can pair afresh.
    private func handleRemoteUnpair() {
        companionLog("Unpaired by the Mac")
        reconnectTask?.cancel()
        reconnectTask = nil
        forgetStoredPairing()
        let oldClient = client
        client = nil
        Task { await oldClient?.close() }
        chats = []
        sessions = []
        messages = []
        openChatID = nil
        isAgentTyping = false
        isLoadingConversation = false
        navigationPath = []
        pairingError = nil
        phase = .scanning
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
        if let transport = error as? TransportError {
            return transport.errorDescription ?? "The connection to your Mac was interrupted."
        }
        if let companion = error as? CompanionError {
            return companion.message
        }
        if let parseError = error as? PairingCode.ParseError {
            return parseError.userMessage
        }
        // Surface the real failure ("connection reset by peer"), not Apple's
        // bridged-NSError boilerplate ("The operation couldn't be completed.
        // (Network.NWError error 54.)").
        if let nwError = error as? NWError {
            return "Lost the connection to your Mac (\(Self.describe(nwError)))."
        }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            return "Lost the connection to your Mac (\(Self.posixDescription(Int32(ns.code))))."
        }
        companionLog("Unmapped error shown generically: \(error)")
        return "Something went wrong communicating with your Mac."
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            return posixDescription(code.rawValue)
        case .dns(let code):
            return "DNS error \(code)"
        case .tls(let status):
            return "TLS error \(status)"
        @unknown default:
            return String(describing: error)
        }
    }

    private static func posixDescription(_ code: Int32) -> String {
        guard let cString = strerror(code) else {
            return "errno \(code)"
        }
        // Lowercase so it reads naturally inside the sentence's parentheses.
        return String(cString: cString).lowercased()
    }
}

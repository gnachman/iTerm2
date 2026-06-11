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
import UIKit
import UserNotifications
import CryptoKit
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
        case session(guid: String, title: String)
        case workgroup(id: String, title: String)
    }

    /// The paired UI's top-level modes (the tab bar).
    enum AppTab: Hashable {
        case chats
        case sessions
    }

    var phase: Phase = .launch
    var selectedTab: AppTab = .chats
    /// The Sessions tab's navigation stack (the browser and what it pushes).
    var sessionsPath: [Destination] = []
    /// The Chats tab's navigation stack.
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
    /// The Sessions tab's window/tab/pane/peer hierarchy.
    var sessionTree: CompanionSessionTree?
    /// Why the tree could not be loaded; only meaningful while sessionTree is
    /// nil (a stale tree keeps showing instead of an error).
    var sessionTreeError: String?

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

    /// True when the open conversation's chat was deleted on the Mac. The
    /// conversation stays on screen (yanking it away would be disruptive)
    /// with composing disabled; it is gone from the list once the user
    /// leaves.
    var openChatWasDeleted = false

    /// Interactive bubbles the user already answered, so their buttons render
    /// disabled (mirrors the Mac's one-shot buttons).
    var respondedInteractiveMessageIDs: Set<UUID> = []

    /// Non-nil while the session-picker sheet is up for a selectSessionRequest.
    struct SessionPickerRequest: Identifiable {
        let id = UUID()
        var requestMessageID: UUID
        var originalMessage: Message
        var terminal: Bool
    }
    var sessionPicker: SessionPickerRequest?

    /// Mention identifier (the text after the "@") to how the Mac resolved it.
    /// Message bubbles read this to draw live names in place of raw UUIDs;
    /// misses are requested in batches as messages arrive.
    var mentionResolutions: [String: CompanionMentionResolution] = [:]
    private var mentionResolutionsInFlight: Set<String> = []

    private var pairingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// The code the current/last pairing attempt used, so Try Again can retry
    /// it instead of dumping the user at the scanner.
    private var activePairingCode: PairingCode?
    /// Whether the in-flight attempt is a reconnect to an existing pairing
    /// (vs a first pairing); the screen titles itself accordingly.
    private(set) var activeIsReconnect = false

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
        // Build stamp: settles "is the device running current code" instantly.
        if let url = Bundle.main.executableURL,
           let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
            companionLog("Launched; binary built \(mtime)")
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

    /// The navigation stack of whichever tab the user is looking at; mention
    /// taps and the session browser both push onto the visible stack.
    private func appendToActivePath(_ destination: Destination) {
        switch selectedTab {
        case .chats:
            navigationPath.append(destination)
        case .sessions:
            sessionsPath.append(destination)
        }
    }

    /// Tapping an @-mention in a bubble pushes the read-only session view.
    func openSession(guid: String, title: String) {
        appendToActivePath(.session(guid: guid, title: title))
    }

    /// Tapping a workgroup @-mention pushes the member list.
    func openWorkgroup(id: String, title: String) {
        appendToActivePath(.workgroup(id: id, title: title))
    }

    /// The composer's @ button refreshes the session list before showing the
    /// mention picker, so the choices are current.
    func refreshSessionsForMentionPicker() {
        Task {
            try? await refreshLists()
        }
    }

    /// Sessions tab: appearance and pull-to-refresh both re-fetch the tree.
    func refreshSessionBrowser() async {
        do {
            let client = try await currentClient(label: "Session tree")
            sessionTree = try await withTimeout(15, "Loading sessions") {
                try await client.sessionTree()
            }
            sessionTreeError = nil
        } catch {
            companionLog("Session tree refresh failed: \(String(describing: error))")
            if sessionTree == nil {
                sessionTreeError = userMessage(for: error)
            }
        }
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
        // Rotate the push secret: the old Mac knows the old one. The next
        // APNs registration re-registers the new hash with the relay.
        PhoneIdentity.deletePushRelaySecret()
        activePairingCode = nil
        chats = []
        sessions = []
        sessionTree = nil
        sessionTreeError = nil
        messages = []
        mentionResolutions = [:]
        openChatID = nil
        isAgentTyping = false
        isLoadingConversation = false
        isReconnecting = false
        navigationPath = []
        sessionsPath = []
        selectedTab = .chats
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
                    reportPushStatus()
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
        if phase != .home {
            // Arriving from pairing (not a pull-to-refresh): start clean.
            sessionsPath = []
            selectedTab = .chats
        }
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
        // Snippets can contain @-mentions; resolve them so the chat list
        // shows names instead of raw UUIDs.
        noteMentions(inTexts: chats.compactMap { $0.snippet })
        checkOpenChatStillExists()
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
                    reportPushStatus()
                    try await refreshLists()
                    if sessionTree != nil || selectedTab == .sessions {
                        // The Sessions tab loads its tree on appearance; if
                        // that load gave up while we were down (or its data
                        // is now stale), this is the retry.
                        await refreshSessionBrowser()
                    }
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

    /// Swipe-to-delete: remove the row optimistically and tell the Mac. The
    /// list snapshot pushed after the Mac-side delete confirms it (or
    /// restores the row if the Mac refused).
    func deleteChat(chatID: String) {
        chats.removeAll { $0.chat.id == chatID }
        Task {
            do {
                let client = try await currentClient(label: "Delete chat")
                try await client.deleteChat(chatID: chatID)
            } catch {
                companionLog("Delete chat failed: \(String(describing: error))")
            }
        }
    }

    /// The Session view's chat button: continue the session's most recently
    /// active chat if it was touched in the last 24 hours, otherwise start a
    /// fresh one. Conversations live on the Chats tab, so either way this
    /// switches there.
    func openOrCreateChat(forSessionGuid guid: String) {
        let attached = chats
            .filter { $0.chat.terminalSessionGuid == guid }
            .max { $0.chat.lastModifiedDate < $1.chat.lastModifiedDate }
        if let attached,
           Date().timeIntervalSince(attached.chat.lastModifiedDate) < 24 * 60 * 60 {
            companionLog("Continuing chat \(attached.chat.id) for session \(guid)")
            openConversation(chatID: attached.chat.id, replacingPath: true)
        } else {
            companionLog("Creating a new chat for session \(guid)")
            createChat(mode: .session(guid: guid))
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
        openChatWasDeleted = false
        messages = []
        isAgentTyping = false
        isLoadingConversation = true
        Task {
            await loadConversation(chatID: chatID)
        }
    }

    /// The open chat vanished from a fresh list snapshot: it was deleted on
    /// the Mac. Disable composing and say why, but leave the transcript up.
    private func checkOpenChatStillExists() {
        guard let openChatID, !openChatWasDeleted else { return }
        guard !chats.contains(where: { $0.chat.id == openChatID }) else { return }
        companionLog("Open chat \(openChatID) was deleted on the Mac")
        openChatWasDeleted = true
        messages.append(Message(chatID: openChatID,
                                author: .agent,
                                content: .clientLocal(ClientLocal(action: .notice(
                                    "This chat was deleted on your Mac. You can keep reading it until you leave, but nothing new can be sent."))),
                                sentDate: Date(),
                                uniqueID: UUID()))
    }

    /// Programmatic open used by the Create flow: replaces the stack so back
    /// returns to Home, then lets conversationDidAppear load the history.
    func openConversation(chatID: String, replacingPath: Bool) {
        withAnimation {
            // Conversations live on the Chats tab (callers can be on the
            // Sessions tab, e.g. the session view's chat button).
            selectedTab = .chats
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
            noteMentions(in: messages)
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
        openChatWasDeleted = false
        messages = []
        isAgentTyping = false
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chatID = openChatID, !openChatWasDeleted else { return }
        let message = Message(chatID: chatID,
                              author: .user,
                              content: .plainText(trimmed, context: nil),
                              sentDate: Date(),
                              uniqueID: UUID())
        // Optimistic local echo so the bubble appears immediately.
        messages.append(message)
        noteMentions(in: [message])
        Task {
            do {
                let client = try await currentClient(label: "Send message")
                try await client.publish(message, toChatID: chatID)
            } catch {
                companionLog("Send failed: \(String(describing: error))")
            }
        }
    }

    // MARK: Interactive message responses

    /// "Select a Session" on a selectSessionRequest bubble: refresh the list
    /// and put up the picker sheet.
    func beginSelectSession(requestMessage: Message, original: Message, terminal: Bool) {
        sessionPicker = SessionPickerRequest(requestMessageID: requestMessage.uniqueID,
                                             originalMessage: original,
                                             terminal: terminal)
        Task {
            try? await refreshLists()
        }
    }

    /// Completes a selectSessionRequest, from the sheet (guid set) or the
    /// bubble's Cancel button (guid nil).
    func respondSelectSession(requestMessageID: UUID,
                              original: Message,
                              terminal: Bool,
                              guid: String?) {
        sessionPicker = nil
        guard let chatID = openChatID else { return }
        respondedInteractiveMessageIDs.insert(requestMessageID)
        companionLog("Select-session response: \(guid ?? "declined")")
        Task {
            do {
                let client = try await currentClient(label: "Select session")
                try await client.sendSelectSessionResponse(chatID: chatID,
                                                           originalMessage: original,
                                                           sessionGuid: guid,
                                                           terminal: terminal)
            } catch {
                companionLog("Select-session response failed: \(String(describing: error))")
            }
        }
    }

    func respondRemoteCommand(requestMessage: Message, decision: CompanionRemoteCommandDecision) {
        guard let chatID = openChatID else { return }
        respondedInteractiveMessageIDs.insert(requestMessage.uniqueID)
        companionLog("Remote command decision: \(decision.rawValue)")
        Task {
            do {
                let client = try await currentClient(label: "Command decision")
                try await client.sendRemoteCommandDecision(chatID: chatID,
                                                           messageUniqueID: requestMessage.uniqueID,
                                                           decision: decision)
            } catch {
                companionLog("Command decision failed: \(String(describing: error))")
            }
        }
    }

    /// Approve/Deny on a workgroup permission request, and Enable/Not Now on
    /// an orchestration request: both are plain user-authored publishes, the
    /// same thing the Mac UI sends.
    func respondUserCommand(requestMessage: Message, command: UserCommand) {
        guard let chatID = openChatID else { return }
        respondedInteractiveMessageIDs.insert(requestMessage.uniqueID)
        companionLog("User command response: \(command)")
        let response = Message(chatID: chatID,
                               author: .user,
                               content: .userCommand(command),
                               sentDate: Date(),
                               uniqueID: UUID())
        Task {
            do {
                let client = try await currentClient(label: "Interactive response")
                try await client.publish(response, toChatID: chatID)
            } catch {
                companionLog("User command response failed: \(String(describing: error))")
            }
        }
    }

    /// The Link button on an offerLink bubble.
    func linkSession(requestMessage: Message, guid: String, terminal: Bool) {
        guard let chatID = openChatID else { return }
        respondedInteractiveMessageIDs.insert(requestMessage.uniqueID)
        Task {
            do {
                let client = try await currentClient(label: "Link session")
                try await client.sendLinkSession(chatID: chatID, sessionGuid: guid, terminal: terminal)
            } catch {
                companionLog("Link session failed: \(String(describing: error))")
            }
        }
    }

    // MARK: Push notifications

    // The permission prompt is never shown spontaneously: it appears just in
    // time, when the orchestrator calls its request_notification_permission
    // tool because the user asked to be alerted about something. Connects
    // only REPORT the current state (the user can revoke in Settings between
    // connections).

    private static let pushTokenDefault = "NoSyncPushDeviceToken"

    /// A debug build's APNs token belongs to the sandbox environment; the
    /// relay must use the matching endpoint.
#if DEBUG
    private static let pushSandbox = true
#else
    private static let pushSandbox = false
#endif

    /// The last APNs device token iOS issued. Persisted so connect-time
    /// status reports can carry it before re-registration completes.
    private var storedPushToken: Data? {
        get { UserDefaults.standard.data(forKey: Self.pushTokenDefault) }
        set { UserDefaults.standard.set(newValue, forKey: Self.pushTokenDefault) }
    }

    private static func authorization(from status: UNAuthorizationStatus) -> CompanionPushAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    /// Report the phone's push capability to the Mac. Called after every
    /// connection; when authorized it also refreshes the APNs token (whose
    /// arrival triggers a follow-up report carrying it).
    private func reportPushStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let authorization = Self.authorization(from: settings.authorizationStatus)
            if authorization == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await sendPushStatus(authorization)
        }
    }

    private func sendPushStatus(_ authorization: CompanionPushAuthorization) async {
        guard let client else { return }
        var token: Data?
        var secret: Data?
        if authorization == .authorized, let storedPushToken {
            token = storedPushToken
            secret = try? PhoneIdentity.pushRelaySecret()
        }
        do {
            try await client.sendPushStatus(authorization: authorization,
                                            token: token,
                                            relaySecret: secret,
                                            sandbox: Self.pushSandbox)
            companionLog("Push status sent: \(authorization.rawValue) (token: \(token != nil))")
        } catch {
            companionLog("Push status send failed: \(String(describing: error))")
        }
    }

    /// The app delegate received (or refreshed) the APNs token: register its
    /// secret hash with the push relay, then report to the Mac.
    func pushTokenDidChange(_ token: Data) {
        storedPushToken = token
        Task {
            await registerWithPushRelay(token: token)
            await sendPushStatus(.authorized)
        }
    }

    private func registerWithPushRelay(token: Data) async {
        struct Registration: Encodable {
            var token: String
            var secretHash: String
            var sandbox: Bool
        }
        guard let secret = try? PhoneIdentity.pushRelaySecret() else {
            companionLog("Push relay registration skipped: no secret")
            return
        }
        var request = URLRequest(url: CompanionPushRelay.registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        let secretHash = SHA256.hash(data: secret).map { String(format: "%02x", $0) }.joined()
        do {
            request.httpBody = try JSONEncoder().encode(
                Registration(token: token.map { String(format: "%02x", $0) }.joined(),
                             secretHash: secretHash,
                             sandbox: Self.pushSandbox))
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                companionLog("Registered with push relay")
            } else {
                companionLog("Push relay registration rejected: \(String(data: data, encoding: .utf8) ?? "")")
            }
        } catch {
            companionLog("Push relay registration failed: \(String(describing: error))")
        }
    }

    /// The Mac asked (on the orchestrator's behalf) to show iOS's
    /// notification-permission prompt. Replies with the outcome; a grant is
    /// followed by a pushStatus carrying the token once APNs issues it.
    private func handleNotificationPermissionRequest(requestID: UInt64) {
        Task {
            let center = UNUserNotificationCenter.current()
            var authorization = Self.authorization(
                from: await center.notificationSettings().authorizationStatus)
            if authorization == .notDetermined {
                let granted = (try? await center.requestAuthorization(
                    options: [.alert, .sound, .badge])) ?? false
                authorization = granted ? .authorized : .denied
                companionLog("Notification permission prompt answered: \(authorization.rawValue)")
            }
            if authorization == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
            if let client {
                try? await client.sendNotificationPermissionResponse(requestID: requestID,
                                                                     authorization: authorization)
            }
            await sendPushStatus(authorization)
        }
    }

    // MARK: Mentions

    /// The visible texts of a message that can contain @-mentions.
    private func mentionableTexts(of message: Message) -> [String] {
        switch message.content {
        case .plainText(let text, _):
            return [text]
        case .markdown(let text):
            return [text]
        case .multipart(let subparts, _):
            return subparts.compactMap {
                switch $0 {
                case .plainText(let text): return text
                case .markdown(let text): return text
                case .attachment, .context: return nil
                }
            }
        case .explanationResponse(let response, _, let markdown):
            return [markdown.isEmpty ? (response.mainResponse ?? "") : markdown]
        default:
            return []
        }
    }

    /// Scan messages for mentions and ask the Mac to resolve any we have not
    /// seen yet. Resolutions land in `mentionResolutions`, which re-renders
    /// the bubbles that reference them.
    private func noteMentions(in messages: [Message]) {
        noteMentions(inTexts: messages.flatMap { mentionableTexts(of: $0) })
    }

    private func noteMentions(inTexts texts: [String]) {
        let identifiers = Set(texts
            .flatMap { MentionParser.mentions(in: $0) }
            .map { $0.identifier })
        let unresolved = identifiers.filter {
            mentionResolutions[$0] == nil && !mentionResolutionsInFlight.contains($0)
        }
        guard !unresolved.isEmpty else { return }
        mentionResolutionsInFlight.formUnion(unresolved)
        companionLog("Resolving \(unresolved.count) mention(s)")
        Task {
            do {
                let client = try await currentClient(label: "Resolve mentions")
                let resolutions = try await client.resolveMentions(Array(unresolved))
                for resolution in resolutions {
                    mentionResolutions[resolution.identifier] = resolution
                }
            } catch {
                // Leave them unresolved; the raw identifiers stay readable and
                // the next delivery retries.
                companionLog("Mention resolution failed: \(String(describing: error))")
            }
            mentionResolutionsInFlight.subtract(unresolved)
        }
    }

    /// A chat-list snippet, ready to display: inline markdown rendered (so
    /// **bold** is bold) and @-mentions replaced with the live entity name
    /// (plain text, not a link; the row itself is the tap target).
    func renderedSnippet(_ snippet: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: snippet,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(snippet)
        let plain = String(attributed.characters)
        // Replace back to front so earlier ranges stay valid.
        for mention in MentionParser.mentions(in: plain).reversed() {
            guard let resolution = mentionResolutions[mention.identifier],
                  let range = Range(mention.range, in: attributed) else {
                continue
            }
            attributed.replaceSubrange(
                range,
                with: AttributedString(resolution.displayName ?? "[defunct session]"))
        }
        return attributed
    }

    // MARK: Session content

    func sessionScreenInfo(guid: String) async throws -> CompanionSessionScreenInfo {
        let client = try await currentClient(label: "Session info")
        return try await withTimeout(15, "Loading session info") {
            try await client.sessionScreenInfo(guid: guid)
        }
    }

    func sessionContent(guid: String, firstLine: Int, lineCount: Int) async throws -> CompanionSessionContent {
        let client = try await currentClient(label: "Session content")
        return try await withTimeout(20, "Loading session content") {
            try await client.sessionContent(guid: guid, firstLine: firstLine, lineCount: lineCount)
        }
    }

    func workgroupInfo(id: String) async throws -> CompanionWorkgroupInfo {
        let client = try await currentClient(label: "Workgroup info")
        return try await withTimeout(15, "Loading workgroup info") {
            try await client.workgroupInfo(id: id)
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
        case .chatListChanged(let entries):
            // The Mac pushes a fresh list whenever a chat is renamed, gets
            // its icon, or is created/deleted/reordered.
            chats = entries
            noteMentions(inTexts: entries.compactMap { $0.snippet })
            checkOpenChatStillExists()
        case .requestNotificationPermission(let requestID):
            handleNotificationPermissionRequest(requestID: requestID)
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
        PhoneIdentity.deletePushRelaySecret()
        let oldClient = client
        client = nil
        Task { await oldClient?.close() }
        chats = []
        sessions = []
        sessionTree = nil
        sessionTreeError = nil
        messages = []
        mentionResolutions = [:]
        openChatID = nil
        isAgentTyping = false
        isLoadingConversation = false
        navigationPath = []
        sessionsPath = []
        selectedTab = .chats
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
        // Resolve any mentions the change introduced. Streaming deltas target
        // the bubble named by their uuid, not the delta's own uniqueID.
        let affectedID: UUID
        switch message.content {
        case .append(_, let uuid), .appendAttachment(_, let uuid):
            affectedID = uuid
        default:
            affectedID = message.uniqueID
        }
        if let affected = messages.first(where: { $0.uniqueID == affectedID }) {
            noteMentions(in: [affected])
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

    func userMessage(for error: Error) -> String {
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
        default:
            // Covers cases newer than our deployment target (.wifiAware) as
            // well as truly unknown future ones.
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

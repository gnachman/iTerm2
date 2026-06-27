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
    CompanionFileLog.shared.log(formatted)
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
    CompanionFileLog.shared.log(formatted)
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
    /// Which app the user must upgrade when the companion apps are
    /// version-incompatible (shown in the full-screen blocking panel).
    enum UpgradeSide: Equatable {
        case phone   // this iPhone app is too old
        case mac     // the Mac's iTerm2 is too old
    }

    enum Phase: Equatable {
        case launch
        case scanning
        case pairing
        case home
        /// Connected and paired, but the app versions are incompatible: a
        /// blocking panel tells the user which app to upgrade. Cleared by a
        /// successful handshake after the upgrade.
        case needsUpgrade(UpgradeSide)
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

    /// On-device speech-to-text for the composer. Lazily prepared (download +
    /// load) on first use, not at launch.
    let whisperManager = WhisperModelManager()
    /// Drives live microphone dictation into the composer.
    let voiceCapture: VoiceCaptureController

    /// A user-facing error for the pairing screen. Nil while in progress.
    var pairingError: String?
    /// Step description for the pairing screen ("Searching for your Mac…").
    var pairingStatus = ""
    /// The 6-digit SAS confirmation code to display during a fresh pairing.
    /// Non-nil only while waiting for the user to type it on the Mac.
    var sasCode: String?
    /// When the in-flight pairing attempt began; drives the elapsed counter.
    var pairingStartedAt: Date?
    /// A pairing code received from an external URL (a tapped iterm2://pair link)
    /// that is awaiting user confirmation. QR scans pair directly; a link opened
    /// from elsewhere could point at an attacker's relay, so we confirm and show
    /// the host first.
    var pendingExternalPairing: PairingCode?
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

    // How the phone reaches the mac, built per pairing code: the relay connector
    // when the code carries a relay origin (off-LAN reach), else a connector that
    // fails fast. Injectable for tests; production uses
    // CompanionTransports.connector(for:).
    private let connectorForCode: (PairingCode, _ pairingTicket: String?, _ established: Bool) -> TransportConnector

    /// App Attest primitives for the relay attestation client. Off-device these
    /// are inert (isSupported == false), so attestation degrades to open mode.
    private let appAttestService: AppAttestService
    private let attestKeyStore: AttestKeyStore

    init(appAttestService: AppAttestService = DeviceCheckAppAttestService(),
         attestKeyStore: AttestKeyStore = UserDefaultsAttestKeyStore(),
         connectorForCode: @escaping (PairingCode, String?, Bool) -> TransportConnector = { code, ticket, established in
        // Sign the relay join only once THIS room is established (its verifier
        // is registered). Before that a fresh pairing must present the App
        // Attest ticket (or an empty proof in open mode), not a signature from
        // the device's global room secret, since the room has no verifier yet
        // and the relay would reject a signature under attestation.
        CompanionTransports.connector(
            for: code,
            roomSecret: { established ? PhoneIdentity.existingRoomSecret() : nil },
            pairingTicket: ticket)
    }) {
        self.appAttestService = appAttestService
        self.attestKeyStore = attestKeyStore
        self.connectorForCode = connectorForCode
        self.voiceCapture = VoiceCaptureController(modelManager: whisperManager)
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

    // Shared with the NSE (single source of truth in CompanionProtocol).
    private static let storedKeyDefault = CompanionSharedIdentifiers.pairedResponderKeyDefault
    private static let storedPIDDefault = CompanionSharedIdentifiers.pairedPairingIDDefault
    private static let storedRelayOriginDefault = CompanionSharedIdentifiers.pairedRelayOriginDefault
    /// The canonical relay host. A pairing whose relay host differs from this is
    /// shown in punycode at confirmation time so a homograph host cannot
    /// masquerade as the real one.
    static let defaultRelayHost = "companion-relay.iterm2.com"
    // The relay room name whose verifier this device has registered. Per ROOM,
    // not a global flag: pairing to a different Mac (a new pid, e.g. after the
    // user re-scans a QR) is a different room and must register (and, under
    // attestation, attest) its own verifier instead of inheriting a stale
    // "done" from the previous pairing. NoSync: local device state, not config.
    private static let registeredRoomDefault = "NoSyncRelayRegisteredRoom"

    private func roomName(for code: PairingCode) -> String {
        RelayRoom.name(responderStaticPublicKey: code.responderStaticPublicKey,
                       pairingID: code.pairingID)
    }

    /// Whether this pairing's verifier is registered with the relay (the room is
    /// established). Gates the one-time /register POST and the pairing-time
    /// attestation; false until a registration actually succeeds, so a failed
    /// attempt is retried on the next connect (self-healing).
    private func verifierRegistered(for code: PairingCode) -> Bool {
        UserDefaults.standard.string(forKey: Self.registeredRoomDefault) == roomName(for: code)
    }

    private func markVerifierRegistered(for code: PairingCode) {
        UserDefaults.standard.set(roomName(for: code), forKey: Self.registeredRoomDefault)
    }

    /// The pairing from the last successful handshake. The responder key is
    /// public and the pid is not a secret, so UserDefaults is fine. The relay
    /// origin is persisted too so an off-LAN reconnect after relaunch can still
    /// reach the mac through the relay (not just the local network).
    /// The pairing code lives in the App Group KEYCHAIN (PhoneIdentity), so it
    /// survives an app reinstall - which wipes UserDefaults but not the keychain -
    /// and the NSE can read it. (It used to be in UserDefaults, so reinstalling
    /// the app forced a re-pair even though the keychain identity survived.)
    var storedPairingCode: PairingCode? {
        if let code = PhoneIdentity.pairingCode() {
            return code
        }
        // Fallback: a pairing stored by an older build (UserDefaults). Read it so
        // the user is not forced to re-pair; migratePairingCodeToKeychain copies
        // it into the keychain at launch.
        return legacyUserDefaultsPairingCode()
    }

    private func storePairing(_ code: PairingCode) {
        do {
            try PhoneIdentity.storePairingCode(code)
        } catch {
            companionLog("Failed to store pairing code in keychain: \(error)")
        }
    }

    /// One-time migration of a pairing code stored by an older build in
    /// UserDefaults into the keychain. Idempotent; runs at launch. Leaves the old
    /// UserDefaults values in place (forgetStoredPairing clears them on unpair).
    private func migratePairingCodeToKeychain() {
        guard PhoneIdentity.pairingCode() == nil,
              let legacy = legacyUserDefaultsPairingCode() else {
            return
        }
        try? PhoneIdentity.storePairingCode(legacy)
    }

    /// Read a pairing code left by an older build in UserDefaults (App Group
    /// suite, then app-only defaults).
    private func legacyUserDefaultsPairingCode() -> PairingCode? {
        let shared = UserDefaults(suiteName: PhoneIdentity.appGroup) ?? .standard
        let std = UserDefaults.standard
        guard let key = shared.data(forKey: Self.storedKeyDefault) ?? std.data(forKey: Self.storedKeyDefault),
              key.count == 32,
              let pid = shared.string(forKey: Self.storedPIDDefault) ?? std.string(forKey: Self.storedPIDDefault) else {
            return nil
        }
        let relayOrigin = shared.string(forKey: Self.storedRelayOriginDefault)
            ?? std.string(forKey: Self.storedRelayOriginDefault)
        return PairingCode(responderStaticPublicKey: key, pairingID: pid, relayOrigin: relayOrigin)
    }

    private func resetForFreshPairing() {
        companionLog("Fresh pairing: clearing all previous key material")
        wipeAllKeyMaterial()
    }

    /// Erase EVERY piece of key material on this device, for a clean fresh start
    /// (the user may be unpairing because of a compromise): the Noise identity,
    /// the room secret, the push-relay secret, and all attest key ids, plus - via
    /// forgetStoredPairing - the pairing code, the verifier-registration marker,
    /// and the per-chat push watermarks. Every unpair / re-pair path calls this
    /// so none leaves anything behind. The keychain deletes use a nil access
    /// group, so they span all the app's access groups (the App Group copy AND
    /// any leftover pre-migration default-group copy).
    private func wipeAllKeyMaterial() {
        attestKeyStore.removeAll()
        PhoneIdentity.deleteKeyPair()
        PhoneIdentity.deleteRoomSecret()
        PhoneIdentity.deletePushRelaySecret()
        forgetStoredPairing()
    }

    func forgetStoredPairing() {
        // Clear the pairing code from the keychain (current location) and from
        // both UserDefaults suites (legacy location). The registered-room marker
        // is NoSync / app-only and stays in standard.
        PhoneIdentity.deletePairingCode()
        for defaults in [UserDefaults(suiteName: PhoneIdentity.appGroup), UserDefaults.standard].compactMap({ $0 }) {
            defaults.removeObject(forKey: Self.storedKeyDefault)
            defaults.removeObject(forKey: Self.storedPIDDefault)
            defaults.removeObject(forKey: Self.storedRelayOriginDefault)
        }
        UserDefaults.standard.removeObject(forKey: Self.registeredRoomDefault)
        // Drop the per-chat push watermarks (shared with the NSE): they are keyed
        // by the old room secret and meaningless once unpaired. reset() clears by
        // prefix, so it does not need the (possibly already-deleted) room secret.
        if let backing = UserDefaultsWatermarkBacking(appGroup: PhoneIdentity.appGroup) {
            WatermarkStore(backing: backing).reset()
        }
    }

    /// Build the best-effort relay delete-room call for the current pairing, or
    /// nil if there is nothing to delete (no relay, no stored room secret). The
    /// returned closure captures the room secret now, so callers can wipe local
    /// key material immediately after without racing the network call. Best
    /// effort: a failure just leaves the relay's idle TTL to reclaim the room.
    private func relayDeleteWork() -> (@Sendable () async -> Void)? {
        guard let code = storedPairingCode,
              let origin = code.relayOrigin,
              let secret = PhoneIdentity.existingRoomSecret() else { return nil }
        let room = roomName(for: code)
        return {
            do {
                try await RelayRoomDeleter(origin: origin).deleteRoom(roomName: room, roomSecret: secret)
                companionLog("Relay room deleted at unpair")
            } catch {
                companionLog("Relay delete-room failed (best-effort): \(String(describing: error))")
            }
        }
    }

    /// Called once at launch: if a pairing is stored, reconnect to it instead
    /// of demanding a fresh QR scan.
    func handleLaunch() {
        // Move the NSE-shared keychain items into the App Group group and the
        // pairing code into the keychain, once, at launch (idempotent +
        // crash-safe), before any reconnect reads them.
        PhoneIdentity.migrateSharedItemsToAppGroup()
        migratePairingCodeToKeychain()
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
        // Capture what the relay delete-room call needs BEFORE the secret is
        // wiped below; the phone initiates this unpair, so it owns the delete.
        let relayDelete = relayDeleteWork()
        Task {
            if let oldClient {
                try? await oldClient.sendUnpairing()
                await oldClient.close()
            }
            await relayDelete?()
        }
        // Wipe ALL key material (the relay delete-room call above already
        // captured the room secret it needs). The next pairing mints a fresh
        // Noise identity, room secret, push secret, and verifier registration.
        wipeAllKeyMaterial()
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
    /// Stash a pairing code that arrived from an external URL so the UI can
    /// confirm it (showing the relay host) before connecting.
    func requestExternalPairing(_ code: PairingCode) {
        pendingExternalPairing = code
    }

    /// The relay host to show in the confirmation: as-is when it is the known
    /// default, otherwise in punycode so a Unicode lookalike is visible.
    var pendingPairingRelayDisplay: String {
        Self.relayHostDisplay(for: pendingExternalPairing?.relayOrigin)
    }

    /// The relay host to surface on the pairing confirmation (SAS) screen when
    /// the active pairing uses a NON-default relay, in punycode; nil for the
    /// official default (nothing to disclose). This covers both entry points: a
    /// tapped iterm2:// link (which also discloses up front) and a scanned QR
    /// (which otherwise went straight into pairing without showing the host).
    var activePairingRelayHostToShow: String? {
        RelayHost.hostToDisclose(relayOrigin: activePairingCode?.relayOrigin,
                                 default: Self.defaultRelayHost)
    }

    static func relayHostDisplay(for relayOrigin: String?) -> String {
        guard let relayOrigin,
              let host = URLComponents(string: relayOrigin)?.host, !host.isEmpty else {
            return "an unspecified relay"
        }
        return host == defaultRelayHost ? host : Punycode.encodedHost(host)
    }

    func confirmExternalPairing() {
        guard let code = pendingExternalPairing else { return }
        pendingExternalPairing = nil
        pair(with: code)
    }

    func cancelExternalPairing() {
        pendingExternalPairing = nil
    }

    func pair(with code: PairingCode, isReconnect: Bool = false) {
        // Ignore a duplicate trigger for a fresh pairing already in flight for
        // this exact code. Both entry points reach here, the in-app scanner and
        // the system-camera link's confirm dialog, and they can BOTH fire for one
        // QR (scanning while the dialog is up). Cancelling and restarting would
        // open a second relay connection that displaces the first (newest-wins)
        // and breaks the Mac's in-progress handshake. A different code, or a
        // reconnect, still proceeds.
        if !isReconnect, pairingTask != nil, activePairingCode?.pairingID == code.pairingID {
            companionLog("Pairing already in progress for pid \(code.pairingID); ignoring duplicate trigger")
            return
        }
        companionLog("Pairing started (pid \(code.pairingID), reconnect: \(isReconnect))")
        if !isReconnect {
            // A fresh pairing (a scanned code, not a reconnect) supersedes any
            // previous one. Wipe carryover key material up front so the new
            // pairing starts from a clean slate and never inherits the old
            // room's secret, verifier registration, or attest key. The phone
            // cannot depend on the Mac's unpair farewell for this: that message
            // is delivered only if the phone is connected at unpair time, so an
            // offline phone would otherwise keep stale state forever.
            resetForFreshPairing()
        }
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
                    try await establish(code: code,
                                        handshakeTimeout: isReconnect
                                            ? Self.reconnectHandshakeTimeout
                                            : Self.firstPairHandshakeTimeout,
                                        requireConfirmation: !isReconnect)
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
                        // re-pairing; keep trying until the user cancels. Retry
                        // quickly: the mac may still be relaunching, and each
                        // attempt re-sends a fresh handshake until it lands.
                        pairingStatus = "Mac not found yet; retrying (attempt \(attempt + 1))"
                        do {
                            try await Task.sleep(nanoseconds: Self.reconnectRetryDelayNanos)
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

    /// Seconds to wait for the Noise handshake before giving up an attempt.
    /// First pairing is generous (the user is watching, the network may be
    /// settling). Reconnect is short: over the relay the handshake is ~1s when
    /// the mac is ready, and when it is NOT (mac still relaunching, or a stale
    /// mac socket that swallows the first message), a fast failure lets us retry
    /// promptly instead of stalling ~15s on a message that will never be answered.
    // nonisolated: used as a default argument of establish(), which is
    // evaluated in a nonisolated context. An immutable Sendable constant.
    nonisolated private static let firstPairHandshakeTimeout: TimeInterval = 15
    private static let reconnectHandshakeTimeout: TimeInterval = 6
    /// Delay between reconnect attempts. The relay does not notify the phone
    /// when the mac (re)appears and drops a handshake sent before the mac is
    /// parked, so reconnect is a poll: keep re-sending a fresh handshake on this
    /// cadence until one lands on a ready mac. Kept short so a mac that just
    /// finished relaunching is picked up quickly.
    private static let reconnectRetryDelayNanos: UInt64 = 2_000_000_000

    /// How long the phone waits for the user to type the SAS code on the Mac.
    /// Generous: a human is walking to a keyboard.
    private static let sasConfirmationTimeout: TimeInterval = 180

    private func establish(code: PairingCode,
                           handshakeTimeout: TimeInterval = firstPairHandshakeTimeout,
                           requireConfirmation: Bool = false) async throws {
        // A retry (PairingView "Try Again") can re-enter establish after a prior
        // attempt already built a client. Tear the old one down so its
        // connection and receive loop do not linger.
        if let existing = client {
            client = nil
            await existing.close()
        }

        let identity = try PhoneIdentity.keyPair()
        let established = verifierRegistered(for: code)
        companionLog("Connecting (discovery + TCP\(code.relayOrigin != nil ? " + relay" : ""))… "
            + "room \(established ? "established (will sign join)" : "fresh (will attest/empty proof)")")
        let pairingTicket = await pairingTicketIfNeeded(code)
        let connector = connectorForCode(code, pairingTicket, established)
        companionLog("Admission proof: "
            + (pairingTicket != nil ? "App Attest ticket"
               : established ? "join signature" : "empty (open mode)"))
        let transport = try await connector.connect(
            to: PairingRendezvous(pairingID: code.pairingID),
            timeout: 30)
        // The relay mints this for the phone at admission; present it to
        // /register. Captured before the handshake wraps the transport.
        let registrationToken = (transport as? RelayTransport)?.registrationToken
        companionLog("Transport connected; starting Noise handshake…")
        pairingStatus = "Securing the connection"
        let channel = try await withTimeout(handshakeTimeout, "Noise handshake") {
            try await NoiseHandshake.perform(
                role: .initiator,
                transport: transport,
                localKeyPair: identity,
                remoteStaticPublicKey: code.responderStaticPublicKey,
                prologue: code.handshakePrologue())
        }
        companionLog("Handshake complete; channel established")
        if requireConfirmation {
            // Fresh pairing: show the SAS code (derived from the handshake
            // hash, so both ends agree iff there is no man in the middle) and
            // wait for the Mac's verdict, the first frame on the channel. A
            // photographed-QR attacker pairs with their own phone, shows a
            // code the victim never sees, and the victim has nothing to type.
            sasCode = PairingSAS.code(handshakeHash: channel.handshakeHash)
            pairingStatus = "Waiting for the code to be entered on your Mac"
            defer { sasCode = nil }
            companionLog("Awaiting SAS confirmation from the mac")
            let verdictData: Data
            do {
                verdictData = try await withTimeout(Self.sasConfirmationTimeout, "Pairing confirmation") {
                    try await channel.receive()
                }
            } catch {
                await channel.close()
                throw error
            }
            guard PairingConfirmation.decode(verdictData) == .accepted else {
                companionLog("Pairing was not accepted on the mac")
                await channel.close()
                throw TransportError.connectionFailed(
                    "The pairing was declined on your Mac. Make sure the code matches and try again.")
            }
            companionLog("SAS confirmation accepted")
        }
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

        await lockRelayRoom(client: client, code: code, registrationToken: registrationToken)
    }

    /// For a fresh pairing, earn the single-use App Attest admission ticket the
    /// relay requires of a genuine app. Returns nil (an empty proof, the
    /// open-mode path) when the pairing is already established (reconnects sign
    /// with the room secret), there is no relay, or the device cannot attest /
    /// the relay is not enforcing attestation. Best-effort: a failure logs and
    /// returns nil, surfacing as an ordinary admission failure iff the relay
    /// actually required the ticket.
    private func pairingTicketIfNeeded(_ code: PairingCode) async -> String? {
        guard let relayOrigin = code.relayOrigin else {
            companionLog("Attestation: no relay origin in code; skipping ticket")
            return nil
        }
        guard !verifierRegistered(for: code) else {
            companionLog("Attestation: room already established; no ticket needed (reconnect signs)")
            return nil
        }
        companionLog("Attestation: fresh pairing, attempting App Attest ticket "
            + "(device supports App Attest: \(appAttestService.isSupported))")
        let roomName = roomName(for: code)
        let client = RelayAttestationClient(origin: relayOrigin,
                                            service: appAttestService,
                                            store: attestKeyStore)
        do {
            if let ticket = try await client.obtainTicket(roomName: roomName) {
                companionLog("Attestation: App Attest ticket obtained for pairing admission")
                return ticket
            }
            companionLog("Attestation: no ticket (open-mode relay or unsupported device); "
                + "joining with an empty proof")
            return nil
        } catch {
            companionLog("Attestation: ticket request FAILED: \(String(describing: error))")
            return nil
        }
    }

    /// Courier the room secret to the mac (every connect, idempotent) and, on a
    /// fresh pairing, register the verifier so the relay room is locked to this
    /// pairing. Best-effort: failures leave the room open-mode and are retried
    /// on the next connect (the design's self-healing re-key). Only meaningful
    /// for the relay transport.
    private func lockRelayRoom(client: CompanionClient,
                               code: PairingCode,
                               registrationToken: String?) async {
        guard let relayOrigin = code.relayOrigin else { return }
        do {
            let secret = try PhoneIdentity.roomSecret()
            // Ack-before-register: wait until the mac has stored the secret (and
            // can sign its parks) before establishing the room. The reverse
            // would let the room go established with the mac unable to park.
            companionLog("Relay room: couriering room secret to the mac…")
            try await client.registerRoomSecret(secret)
            companionLog("Relay room: mac acked the room secret")
            // Register once, the first connect after pairing. Reconnects
            // re-courier the secret but skip /register. The relay mints a token
            // on every admit, so the per-room flag, not the token, decides.
            if verifierRegistered(for: code) {
                companionLog("Relay room: verifier already registered for this room; done")
            } else if let registrationToken {
                companionLog("Relay room: registering verifier (token present)…")
                let registered = await registerRelayVerifier(
                    roomSecret: secret,
                    registrationToken: registrationToken,
                    relayOrigin: relayOrigin,
                    roomName: roomName(for: code))
                if registered {
                    markVerifierRegistered(for: code)
                }
            } else {
                companionLog("Relay room: no registration token (not a relay admission); "
                    + "verifier registration deferred")
            }
        } catch {
            companionLog("Relay room lock deferred: \(String(describing: error))")
        }
    }

    /// POST the verifier (public, derived from the room secret) to the relay's
    /// /register, authenticated by the one-time registration token.
    /// Returns true if the verifier is registered (a fresh 200, or a 403 that
    /// reports it is already registered), so the caller stops retrying. Any
    /// other outcome returns false to retry on the next connect.
    private func registerRelayVerifier(roomSecret: Data,
                                       registrationToken: String,
                                       relayOrigin: String,
                                       roomName: String) async -> Bool {
        struct Body: Encodable {
            var registrationToken: String
            var verifier: String
            // Present only under attestation; a nil optional is omitted, so an
            // open-mode register sends just the token and verifier.
            var challenge: String?
            var assertion: String?
        }
        guard let url = URL(string: relayOrigin + "/register") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(roomName, forHTTPHeaderField: "x-relay-room")
        request.setValue(CompanionUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let verifier = RelayJoin.verifier(roomSecret: roomSecret).base64EncodedString()
        // Prove current possession of the attested key (the relay requires this
        // under attestation; nil in open mode). Best-effort: a failure leaves
        // an open-mode register, which the relay rejects iff it requires it.
        let attestation = try? await RelayAttestationClient(
            origin: relayOrigin, service: appAttestService, store: attestKeyStore)
            .registerAssertion(roomName: roomName)
        companionLog("Relay /register: verifier \(verifier.prefix(12))…, "
            + "assertion \(attestation != nil ? "present" : "absent (open mode)")")
        do {
            request.httpBody = try JSONEncoder().encode(
                Body(registrationToken: registrationToken, verifier: verifier,
                     challenge: attestation?.challenge, assertion: attestation?.assertion))
            let (data, response) = try await CompanionURLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            if (200..<300).contains(status) {
                companionLog("Relay verifier registered; room locked to this pairing")
                return true
            }
            // The room is already established (e.g. a prior attempt's POST
            // landed but its reply was lost): also done, stop retrying.
            if status == 403, body.contains("already registered") {
                companionLog("Relay verifier already registered")
                return true
            }
            companionLog("Relay verifier registration rejected (\(status)): \(body)")
            return false
        } catch {
            companionLog("Relay verifier registration failed: \(String(describing: error))")
            return false
        }
    }

    // MARK: Home

    /// From the upgrade panel, after the user has updated an app.
    ///
    /// If the upgrade wall came from a FRESH pairing (a scanned QR), return to the
    /// scanner rather than reconnecting: retrying a fresh pairing means re-scanning
    /// the (now-updated) Mac's NEW QR - the one just scanned is invalidated, so a
    /// silent reconnect with that stale code is wrong. A reconnect of an
    /// already-paired device just reconnects and re-runs the handshake; a
    /// compatible one proceeds to home, an incompatible one returns to the panel.
    func retryAfterUpgrade() {
        guard activeIsReconnect, let code = storedPairingCode else {
            phase = .scanning
            return
        }
        pair(with: code, isReconnect: true)
    }

    /// Thrown by the timeout leg of the post-establish `.hello` race, so a genuine
    /// timeout is distinguishable from a transport drop or a teardown (see loadHome).
    private struct HelloHandshakeTimedOut: Error {}

    func loadHome() async throws {
        // Version handshake FIRST: if the apps are incompatible, show the blocking
        // upgrade panel instead of the home screen. Pairing itself succeeded, so
        // storePairing still runs (caller) - after the user upgrades, a reconnect
        // gets a compatible handshake and proceeds to home.
        let client = try await currentClient(label: "Version handshake")
        // We reach here only AFTER establish() completed the Noise handshake, so
        // the channel is up and the Mac is authenticated. Race .hello against a
        // timeout and keep the outcomes distinct:
        //   - TIMED OUT: the Mac is present but never answers .hello at all - an
        //     older Mac that predates the handshake. (A network drop in the very
        //     next operation after a clean establish is far less likely; the Retry
        //     button recovers that rare false positive.) Treat it as "the Mac must
        //     upgrade" so a phone-first updater gets a clear panel, not a silent
        //     reconnect loop.
        //   - FAILED with a CompanionError: the Mac RESPONDED but with a rejection
        //     or a reply we can't make sense of (an older Mac that forward-compat-
        //     decodes .hello as .unsupported and replies .error, or any unexpected
        //     reply) - also "the Mac must upgrade".
        //   - FAILED with anything else: a real transport drop (TransportError) or
        //     a deliberate teardown (CancellationError) propagates to the normal
        //     pairing retry path. We do NOT claim "upgrade the Mac" just because
        //     the connection broke.
        let handshake: CompanionClient.HandshakeResult
        do {
            handshake = try await withThrowingTaskGroup(of: CompanionClient.HandshakeResult.self) { group in
                group.addTask { try await client.handshakeVersion() }
                group.addTask {
                    // A genuine elapse throws the sentinel; a cancelled sleep
                    // (teardown, or cancelAll after the handshake already won)
                    // throws CancellationError instead, so a teardown is never
                    // mistaken for a timeout.
                    try await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                    throw HelloHandshakeTimedOut()
                }
                defer { group.cancelAll() }
                // First child to finish wins: a verdict, or a thrown error (the
                // handshake's own, or our timeout sentinel).
                guard let result = try await group.next() else {
                    throw CancellationError()
                }
                return result
            }
        } catch is HelloHandshakeTimedOut {
            companionLog("Version handshake timed out after a successful establish; assuming the Mac app must upgrade")
            phase = .needsUpgrade(.mac)
            return
        } catch let error as CompanionError {
            companionLog("Version handshake rejected by Mac (\(error)); Mac app must upgrade")
            phase = .needsUpgrade(.mac)
            return
        }
        // Any OTHER error - a real transport drop (TransportError) or a deliberate
        // teardown (CancellationError) - is not an upgrade signal and propagates
        // out of loadHome to the normal pairing retry path.
        switch handshake.compatibility {
        case .compatible:
            break
        case .selfMustUpgrade:
            companionLog("Version handshake: this phone app must upgrade")
            phase = .needsUpgrade(.phone)
            return
        case .peerMustUpgrade:
            companionLog("Version handshake: the Mac app must upgrade")
            phase = .needsUpgrade(.mac)
            return
        }
        // The mac says the user opted into phone alerts: ask iOS for notification
        // permission if we haven't yet (deferring to foreground if backgrounded).
        if handshake.wantsNotificationPermission {
            ensureNotificationPermission(replyTo: nil)
        }
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
                    try await establish(code: code,
                                        handshakeTimeout: Self.reconnectHandshakeTimeout)
                    companionLog("Reconnected (attempt \(attempt))")
                    // Re-run the version handshake on every reconnect so the mac's
                    // "user wants alerts" signal (carried in the .hello reply) is
                    // honored on each connect, not just the initial pairing. A
                    // failure here must not abort the reconnect, so it's best-effort.
                    if let client {
                        do {
                            let handshake = try await client.handshakeVersion()
                            if handshake.wantsNotificationPermission {
                                ensureNotificationPermission(replyTo: nil)
                            }
                        } catch {
                            companionLog("Reconnect version handshake failed: \(String(describing: error))")
                        }
                    }
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
                        try await Task.sleep(nanoseconds: Self.reconnectRetryDelayNanos)
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
        request.setValue(CompanionUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let secretHash = SHA256.hash(data: secret).map { String(format: "%02x", $0) }.joined()
        do {
            request.httpBody = try JSONEncoder().encode(
                Registration(token: token.map { String(format: "%02x", $0) }.joined(),
                             secretHash: secretHash,
                             sandbox: Self.pushSandbox))
            let (data, response) = try await CompanionURLSession.shared.data(for: request)
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
        companionLog("Received notification-permission request \(requestID)")
        ensureNotificationPermission(replyTo: requestID)
    }

    /// Observer token for a deferred prompt; non-nil means we're waiting for the app
    /// to become active before showing the iOS notification prompt.
    private var becomeActiveObserver: NSObjectProtocol?

    /// Ask iOS for notification permission when it makes sense, robustly:
    ///  - already decided (authorized/denied): just report (and register if granted);
    ///  - undetermined + app ACTIVE: show the prompt now;
    ///  - undetermined + app NOT active (e.g. a background reconnect delivered the
    ///    request): DEFER and show it the next time the app becomes active, so the
    ///    prompt never depends on the request happening to land while foreground.
    /// `replyTo` answers the orchestrator's request-id flow; nil for the hello flow.
    private func ensureNotificationPermission(replyTo requestID: UInt64?) {
        Task { await ensureNotificationPermissionImpl(replyTo: requestID) }
    }

    private func ensureNotificationPermissionImpl(replyTo requestID: UInt64?) async {
        let center = UNUserNotificationCenter.current()
        var authorization = Self.authorization(from: await center.notificationSettings().authorizationStatus)
        companionLog("ensureNotificationPermission: status=\(authorization.rawValue), "
            + "appState=\(UIApplication.shared.applicationState.rawValue)")
        if authorization == .notDetermined {
            guard UIApplication.shared.applicationState == .active else {
                companionLog("App not active; deferring notification prompt to next foreground")
                scheduleNotificationPromptOnNextActive()
                if let requestID, let client {
                    try? await client.sendNotificationPermissionResponse(requestID: requestID,
                                                                         authorization: .notDetermined)
                }
                return
            }
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorization = granted ? .authorized : .denied
            companionLog("Notification permission prompt answered: \(authorization.rawValue)")
        }
        if authorization == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
        if let requestID, let client {
            try? await client.sendNotificationPermissionResponse(requestID: requestID,
                                                                 authorization: authorization)
        }
        await sendPushStatus(authorization)
    }

    private func scheduleNotificationPromptOnNextActive() {
        guard becomeActiveObserver == nil else { return }
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let observer = self.becomeActiveObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.becomeActiveObserver = nil
                }
                await self.ensureNotificationPermissionImpl(replyTo: nil)
            }
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
        case .remoteCommandRequest(let payload, _):
            // MessageBubbleView renders this bubble's description with
            // textWithMentions (both the classic and orchestration branches
            // resolve to payload.markdownDescription), so its mentions must be
            // scanned here too or they never get resolved and stay raw.
            return [payload.markdownDescription]
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
        wipeAllKeyMaterial()
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

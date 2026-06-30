//
//  CompanionPairingController.swift
//  iTerm2
//
//  Drives the mac side of pairing: it advertises the companion service, waits
//  for a phone to connect, runs the Noise XK handshake as the responder, and
//  hands the encrypted channel to a CompanionHostBridge. A successful pairing
//  is persisted (the pairing id; the static identity is already in the
//  keychain) so the phone can reconnect after either side relaunches: at app
//  launch, and whenever the phone disconnects, the mac resumes advertising the
//  stored pairing id. The transport is reached through the pluggable
//  TransportListener abstraction.
//

import Foundation
import AppKit
import CoreImage
import Network
import Security
import CompanionProtocol
import CompanionNoise
import CompanionTransport

@MainActor
@objc(iTermCompanionPairingController)
final class CompanionPairingController: NSObject {
    @objc static let shared = CompanionPairingController()

    /// Posted (on the main thread) whenever the paired/connected state changes,
    /// so the presence UI (menu bar status item + toast) can update. Observers
    /// read hasPairedDevice / isConnected for the current state.
    @objc static let presenceDidChange = Notification.Name("iTermCompanionPresenceDidChange")

    private func notifyPresenceChanged() {
        NotificationCenter.default.post(name: Self.presenceDidChange, object: nil)
    }

    /// How the current connection should be treated by the presence warning.
    /// A connection only counts as user-visible presence once it is .interactive;
    /// a .solicited NSE fetch (the mac's own push response) is invisible. See
    /// docs/push.txt and CompanionPushNonceRegistry.
    enum ConnectionPresence {
        case none         // no connection
        case pending      // connected, not yet classified (within the grace window)
        case solicited    // the mac's own NSE fetch (valid push nonce): no warning
        case interactive  // a real/unexpected connection: warn
    }
    private(set) var connectionPresence: ConnectionPresence = .none {
        didSet {
            // Mirror to the (lock-guarded) flag the turn-complete push gate reads,
            // so it suppresses pushes only for a real interactive session and not
            // for the mac's own solicited NSE fetch.
            CompanionPushRegistry.setInteractivePhoneConnected(connectionPresence == .interactive)
        }
    }
    private var classificationGraceTask: Task<Void, Never>?
    /// A connection that neither presents a valid nonce nor does anything within
    /// this window is treated as interactive (a silent lurker is warn-worthy).
    private static let classificationGraceNanos: UInt64 = 3_000_000_000

    private var listener: TransportListener?
    private var acceptTask: Task<Void, Never>?
    private var bridge: CompanionHostBridge? {
        didSet {
            // Mirrored where the (nonisolated) tool-registration path can
            // read it.
            CompanionPushRegistry.setPhoneConnected(bridge != nil)
            // Reset presence classification for the new connection (or clear it).
            if let bridge {
                connectionPresence = .pending
                startClassificationGrace(for: bridge)
                // A live bridge IS relay presence; start the connected timer if a
                // park hadn't already (continuous through park -> phone -> repark).
                if relayConnectedSince == nil { relayConnectedSince = Date() }
            } else {
                connectionPresence = .none
                classificationGraceTask?.cancel()
                classificationGraceTask = nil
            }
            // Connection state changed: refresh the presence UI.
            notifyPresenceChanged()
        }
    }

    /// After the grace window, an unclassified (still pending) connection is
    /// escalated to .interactive so it surfaces. A solicited/interactive
    /// classification arriving first cancels this.
    private func startClassificationGrace(for connection: CompanionHostBridge) {
        classificationGraceTask?.cancel()
        classificationGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.classificationGraceNanos)
            guard let self, !Task.isCancelled else { return }
            guard self.bridge === connection, self.connectionPresence == .pending else { return }
            self.connectionPresence = .interactive
            self.notifyPresenceChanged()
        }
    }

    /// Show a modal alert when the companion apps are version-incompatible. The
    /// verdict is from the mac's side: .peerMustUpgrade -> the phone app is too
    /// old; .selfMustUpgrade -> iTerm2 is too old. Shown at most once per minute
    /// so a retrying phone can't spam alerts.
    private var lastVersionAlert: Date?
    private func showVersionIncompatibleAlert(_ verdict: CompanionProtocolVersion.Compatibility) {
        if let last = lastVersionAlert, Date().timeIntervalSince(last) < 60 { return }
        lastVersionAlert = Date()
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch verdict {
        case .peerMustUpgrade:
            alert.messageText = "Companion Device Needs an Update"
            alert.informativeText = "The iTerm2 Buddy app on your phone is too old to connect to "
                + "this version of iTerm2. Update the iPhone app to continue."
        case .selfMustUpgrade:
            alert.messageText = "iTerm2 Needs an Update"
            alert.informativeText = "This version of iTerm2 is too old to connect to the iTerm2 "
                + "Buddy app on your phone. Update iTerm2 to continue."
        case .compatible:
            return
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// The bridge classified its connection on the first request. solicited ==
    /// valid push nonce (the mac's own fetch); otherwise warn.
    private func connectionDidClassify(_ connection: CompanionHostBridge, solicited: Bool) {
        guard bridge === connection, connectionPresence == .pending else { return }
        classificationGraceTask?.cancel()
        classificationGraceTask = nil
        connectionPresence = solicited ? .solicited : .interactive
        notifyPresenceChanged()
    }

    private(set) var pairingCode: PairingCode?

    /// True while a fresh-pairing QR is being shown (from startPairing until the
    /// pairing completes or the window is torn down via stopAdvertising). It
    /// distinguishes "a QR is up, keep its park alive" from a stale pairingCode
    /// left over after the window closed, so retry re-parks only a live pairing.
    private var freshPairingActive = false

    // Set by the window controller; all invoked on the main actor.
    var onPaired: (@MainActor () -> Void)?
    var onFailed: (@MainActor (String) -> Void)?
    var onDisconnect: (@MainActor () -> Void)?
    var onStatus: (@MainActor (String) -> Void)?
    /// A fresh pairing finished its handshake and needs the user to type the
    /// code shown on the phone. The window switches to code-entry UI and calls
    /// submitSASEntry with what the user typed (nil = user declined).
    var onSASEntryNeeded: (@MainActor () -> Void)?
    /// The confirmation resolved (matched, declined, or too many mistypes);
    /// the window dismisses the entry UI, restoring the QR when not accepted.
    var onSASEntryDismissed: (@MainActor (_ accepted: Bool) -> Void)?
    /// The fresh-pairing pid was regenerated (it timed out, a SAS was rejected,
    /// or the relay tore the room down): the window must redraw the QR for the
    /// new code, which the stale one no longer matches.
    var onPairingCodeChanged: (@MainActor (PairingCode) -> Void)?

    /// A fresh-pairing QR is short-lived: the relay removes the proximity that
    /// made QR leakage tolerable, so a photographed QR must not stay valid
    /// indefinitely. After this idle window with no successful pairing the pid is
    /// regenerated, invalidating any photo of the old code.
    private static let freshPairingTTL: TimeInterval = 120
    private var freshPairingExpiry: Task<Void, Never>?
    /// True while a connection is being handshaked / SAS-confirmed, so the expiry
    /// timer does not regenerate the pid out from under an in-progress pairing.
    private var confirmationInProgress = false

    // Internal (not private): CompanionPushRegistry.devicePaired reads the
    // same default from nonisolated contexts. nonisolated so that read does not
    // cross actor isolation (an immutable Sendable constant).
    nonisolated static let pairedPIDKey = "NoSyncCompanionPairedPID"

    /// The pairing id of the (single, for now) paired device, persisted so
    /// reconnection survives relaunches. NoSync: device state, not a setting.
    private var pairedPID: String? {
        get { iTermUserDefaults.userDefaults().string(forKey: Self.pairedPIDKey) }
        set {
            if let newValue {
                iTermUserDefaults.userDefaults().set(newValue, forKey: Self.pairedPIDKey)
            } else {
                iTermUserDefaults.userDefaults().removeObject(forKey: Self.pairedPIDKey)
            }
        }
    }

    /// The paired phone's Noise static public key, learned and SAS-confirmed at
    /// pairing. On reconnect the mac requires the initiator to present this same
    /// static (Noise proves possession of the matching private key), which
    /// authenticates the phone END-TO-END: a relay-admitted impostor, or a
    /// QR-photo attacker, completes no session because it cannot present this
    /// key. The relay is untrusted, so this check, not the relay, is the
    /// reconnect authentication. Stored in the keychain (not UserDefaults):
    /// it is public, but its integrity is security-critical, a tampered value
    /// would authenticate an impostor. Kept beside the mac's private key.
    private var pairedPhoneStatic: Data? {
        get { CompanionMacIdentity.pairedPhoneStaticPublicKey() }
        set {
            if let newValue {
                try? CompanionMacIdentity.storePairedPhoneStaticPublicKey(newValue)
            } else {
                CompanionMacIdentity.deletePairedPhoneStaticPublicKey()
            }
        }
    }

    /// A phone is connected right now.
    var isConnected: Bool { bridge != nil }
    /// A device has paired at some point (it may or may not be connected).
    var hasPairedDevice: Bool { pairedPID != nil }
    /// The mac currently holds (or is actively re-establishing) a relay park, so
    /// a paired phone can reach it. Distinguishes the healthy "paired, parked,
    /// just waiting for the phone" state from "paired but not listening at all"
    /// (the phone cannot reconnect). Both have bridge == nil and would otherwise
    /// look identical in the UI.
    var isListening: Bool { acceptTask != nil || listenerRetryTask != nil }

    /// When the mac's CONTINUOUS relay presence began (it parked, or a phone
    /// bridged), or nil while not connected. Stays set across park -> phone
    /// connect -> repark; cleared only when a retry is scheduled (a real drop) or
    /// listening stops. Drives the "connected for…" timer in settings.
    private(set) var relayConnectedSince: Date?
    /// When the mac last ATTEMPTED to (re)establish its relay park. Drives the
    /// "last try…" timer while not connected.
    private(set) var lastRelayAttempt: Date?

    /// The mac's relay status for the settings UI.
    enum RelayStatus: Equatable {
        case idle                          // not paired: nothing to show
        case connected(since: Date)        // parked / phone-bridged: reachable
        case reconnecting(lastAttempt: Date?)  // not connected; retrying
    }
    var relayStatus: RelayStatus {
        guard hasPairedDevice else { return .idle }
        if let since = relayConnectedSince { return .connected(since: since) }
        return .reconnecting(lastAttempt: lastRelayAttempt)
    }

    /// The pairing id the mac should currently be parked for: the established
    /// device, or, during a fresh pairing, the QR being shown. Retry uses this
    /// so a dropped park is re-established in BOTH states, waiting for a first
    /// scan and after pairing. nil means there is nothing to listen for.
    private var desiredListeningPID: String? {
        if let pairedPID { return pairedPID }
        if freshPairingActive { return pairingCode?.pairingID }
        return nil
    }

    /// Everything that must hold to pair, or even listen for a paired device.
    /// Mirrors the AI feature's gating (admin setting + signed plugin + secure
    /// consent) twice: the AI prerequisite (the companion bridges AI chat) and
    /// the companion feature itself. Distinct cases so the UI names the remedy.
    enum Gate: Equatable {
        case allowed
        case aiAdminDisabled
        case aiPluginMissing
        case aiConsentNeeded
        case companionAdminDisabled
        case companionPluginMissing
        case companionConsentNeeded
    }

    static func gate() -> Gate {
        // AI prerequisites.
        if !iTermAdvancedSettingsModel.generativeAIAllowed() { return .aiAdminDisabled }
        if !iTermAITermGatekeeper.pluginInstalled() { return .aiPluginMissing }
        if !SecureUserDefaults.instance.enableAI.value { return .aiConsentNeeded }
        // Companion-specific: admin policy, the signed companion plugin (the
        // only outbound path to the relay), and the user's secure opt-in.
        if !iTermAdvancedSettingsModel.companionPairingAllowed() { return .companionAdminDisabled }
        if !CompanionPlugin.instance().isSuccess { return .companionPluginMissing }
        if !SecureUserDefaults.instance.enableCompanionPairing.value { return .companionConsentNeeded }
        return .allowed
    }

    private var gateObservers: [any NSObjectProtocol] = []

    private override init() {
        super.init()
        // Track consent and the advanced setting so the background listener
        // follows the gate: stop when AI becomes unavailable, resume when it
        // comes back. (Plugin presence has no notification; it is re-checked
        // on the next launch or pairing-window visit.)
        let center = NotificationCenter.default
        for name in [iTermSecureUserDefaults.didChange,
                     Notification.Name(iTermAdvancedSettingsDidChange)] {
            gateObservers.append(center.addObserver(forName: name,
                                                    object: nil,
                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.gateMayHaveChanged()
                }
            })
        }
    }

    private func gateMayHaveChanged() {
        if Self.gate() == .allowed {
            resumePairedListeningIfNeeded()
            return
        }
        // Gate closed (AI disabled, admin policy, etc.): stop serving. Drop a
        // live connection too, not just the accept loop. Keep the pairing keys:
        // these gates are reversible, unlike unpair(), so re-enabling lets the
        // same device reconnect. Two exceptions delete key material instead, and
        // both happen before this runs so there is nothing left to tear down
        // here: turning off the consent checkbox (handled in the pairing window)
        // and the plugin disappearing (see unpairIfPluginMissing).
        guard bridge != nil || acceptTask != nil else { return }
        RLog("Companion: gate closed; dropping any live connection and stopping listener")
        if bridge != nil {
            bridge?.stop()
            bridge = nil
            onDisconnect?()
        }
        stopAdvertising()
    }

    /// If a device is paired but the consent plugin is gone, unpair and delete
    /// all key material. The plugin is the egress path and the capability, so
    /// removing it must not leave a usable pairing behind. The plugin's presence
    /// is cached (a success is only re-probed on reload), so this is meaningful
    /// at the points that force a re-probe: app launch and the window's Check
    /// Again. Consent-off is enforced separately by the pairing window.
    func unpairIfPluginMissing() {
        guard hasPairedDevice, !CompanionPlugin.instance().isSuccess else { return }
        RLog("Companion: consent plugin missing; unpairing and deleting key material")
        relayLog("unpairIfPluginMissing: plugin gone, unpairing")
        unpair()
    }

    /// Called at app launch (and after disconnects): if a device is paired,
    /// quietly advertise its pairing id so it can reconnect.
    @objc func resumePairedListeningIfNeeded() {
        installLogHandler()
        relayLog("resumePairedListeningIfNeeded called")
        // First call is at launch (the user is present); read the keychain-backed
        // identity material (Noise keypair, paired phone key, room secret), the
        // push secret, and the outstanding-nonce list into memory now, so later
        // reconnects and background sends serve from cache and never trigger a
        // keychain prompt while the user is away. (The nonce list is its own
        // keychain item, read lazily on first push without this.) All are
        // idempotent, so reconnect-driven calls are no-ops.
        CompanionMacIdentity.primeCacheAtLaunch()
        CompanionPushRegistry.loadSecretAtLaunch()
        CompanionPushNonceRegistry.shared.primeAtLaunch()
        // Watch the broker so a completed agent turn (or a permission request)
        // can nudge an away phone. Idempotent; gated so it does nothing unless
        // paired, away, and notifications are authorized.
        CompanionAgentActivityNotifier.start()
        // If the plugin vanished while we were away, tear the pairing down rather
        // than silently keeping the keys around for a feature that can't run.
        unpairIfPluginMissing()
        guard Self.gate() == .allowed else {
            DLog("Companion: not listening; AI features are unavailable")
            relayLog("resume: SKIP (AI gate not allowed)")
            return
        }
        // Park only when nothing is connected. The relay room has a single mac
        // slot, so parking while a bridge is live would displace it. The
        // bridge's onClose nils `bridge` before calling here, so a genuine
        // reconnect (after the connection is gone) still proceeds; only callers
        // firing while connected (launch races, gate changes) are held off.
        guard acceptTask == nil, bridge == nil, let pid = desiredListeningPID else {
            relayLog("resume: SKIP guard "
                     + "(acceptTaskNil=\(acceptTask == nil) bridgeNil=\(bridge == nil) "
                     + "hasPID=\(desiredListeningPID != nil))")
            return
        }
        do {
            relayLog("resume: starting listening for pid \(pid)")
            try startListening(pairingID: pid)
            RLog("Companion: resumed listening for paired device (pid \(pid))")
        } catch {
            RLog("Companion: could not resume listening: \(error); will retry")
            relayLog("resume: startListening THREW \(error); scheduling retry")
            scheduleListenerRetry()
        }
    }

    /// The background listener must outlive transient failures (sleep/wake
    /// and network changes can kill the NW listener): whenever it dies while
    /// a device is paired, retry until it sticks. Without this the mac
    /// silently stops advertising and the phone can never reconnect.
    private var listenerRetryTask: Task<Void, Never>?

    /// Routine re-park delay after a park loss (idle reap, redeploy, network blip).
    private static let defaultListenerRetryNanos: UInt64 = 5_000_000_000
    /// A park displaced by another mac-role connection (a duplicate instance in the
    /// same room) backs off much longer than the routine delay so the two don't
    /// ping-pong evicting each other; finite so the slot is reclaimed if the other
    /// instance exits.
    private static let displacedListenerRetryNanos: UInt64 = 60_000_000_000

    private func scheduleListenerRetry(after delayNanos: UInt64 = defaultListenerRetryNanos) {
        guard listenerRetryTask == nil, desiredListeningPID != nil else {
            return
        }
        // A retry is scheduled because we are NOT connected: end the connected
        // timer so settings shows "reconnecting" with the last-attempt time.
        relayConnectedSince = nil
        notifyPresenceChanged()
        listenerRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            self.listenerRetryTask = nil
            self.resumePairedListeningIfNeeded()
        }
    }

    /// Begin a fresh pairing. Returns the pairing code whose URL should be
    /// displayed as a QR.
    func startPairing() throws -> PairingCode {
        installLogHandler()
        relayLog("startPairing() called (fresh QR)")
        stopAdvertising()
        let keyPair = try CompanionMacIdentity.keyPair()
        let pairingID = Self.makePairingID()
        let code = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                               pairingID: pairingID,
                               relayOrigin: Self.configuredRelayOrigin())
        pairingCode = code
        // A live QR is up: keep its park retried until the phone pairs or the
        // window is torn down (stopAdvertising clears this).
        freshPairingActive = true

#if DEBUG
        // Development automation hook: the iOS simulator has no camera, so
        // end-to-end tests read the pairing URL from here and hand it to the
        // phone via simctl openurl.
        try? code.urlString().write(toFile: "/tmp/iterm2-companion-pairing-url.txt",
                                    atomically: true,
                                    encoding: .utf8)
#endif

        try startListening(pairingID: pairingID)
        startFreshPairingExpiry()
        return code
    }

    /// Arm (or re-arm) the fresh-pairing expiry. On fire it regenerates the pid
    /// when idle; if a confirmation is in flight it defers a further interval so
    /// a legitimate pairing is never interrupted. startPairing re-arms it, so a
    /// regeneration restarts the clock for the new pid.
    private func startFreshPairingExpiry() {
        freshPairingExpiry?.cancel()
        freshPairingExpiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.freshPairingTTL * 1_000_000_000))
            guard let self, !Task.isCancelled, self.freshPairingActive else { return }
            self.freshPairingExpiry = nil
            if self.bridge == nil, !self.confirmationInProgress {
                self.regenerateFreshPairing(reason: "timeout")
            } else {
                // Busy (connected, or mid-confirmation): check again next interval.
                self.startFreshPairingExpiry()
            }
        }
    }

    /// Void the current fresh-pairing pid and re-advertise under a new one, so a
    /// photographed/leaked QR can no longer reach this pairing. Triggered by the
    /// expiry timer, a rejected SAS, or the relay tearing the room down. No-op
    /// once connected or no longer showing a fresh QR.
    private func regenerateFreshPairing(reason: String) {
        guard freshPairingActive, bridge == nil else { return }
        relayLog("regenerateFreshPairing(\(reason)): minting a new pid")
        do {
            let code = try startPairing()
            onPairingCodeChanged?(code)
        } catch {
            RLog("Companion: could not regenerate pairing code: \(error)")
            onFailed?(Self.userFacingDescription(of: error))
        }
    }

    /// Whether a companion phone is connected right now (a live bridge). Used
    /// to decide which push tools the orchestrator gets.
    var isPhoneConnected: Bool {
        bridge != nil
    }

    /// Ask the connected phone to prompt for notification permission. nil
    /// when no phone is connected or it didn't answer.
    func requestNotificationPermission() async -> CompanionPushAuthorization? {
        await bridge?.requestNotificationPermission()
    }

    /// The user turned on "send alerts to my iPhone". Record the durable intent so
    /// EVERY subsequent `.hello` tells the phone to ask for notification permission
    /// (the robust, timing-independent path). Also nudge a currently-connected phone
    /// immediately so opting in while the phone is foreground prompts right away
    /// instead of waiting for the next connection.
    func requestPushPermissionForAlerts() {
        CompanionPushRegistry.setAlertsEverEnabled(true)
        DLog("Companion: alerts opt-in recorded (authorization=\(CompanionPushRegistry.authorization.rawValue), presence=\(connectionPresence))")
        if connectionPresence == .interactive,
           CompanionPushRegistry.authorization == .notDetermined {
            DLog("Companion: nudging connected phone to request notification permission now")
            Task { [weak self] in _ = await self?.requestNotificationPermission() }
        }
    }

    /// Kick the paired device and delete the pairing: closes any live bridge,
    /// forgets the pairing id, and destroys the mac's static identity so a new
    /// one is generated for the next pairing.
    func unpair() {
        relayLog("unpair() called")
        RLog("Companion: unpair (bridge connected: \(bridge != nil))")
        // This Mac initiates the unpair, so it owns the authenticated relay
        // delete-room call. Build it BEFORE wiping key material below; the
        // closure captures the room secret it needs.
        let relayDelete = relayDeleteWork()
        if let bridge {
            // Fire-and-forget: the farewell flush is async, but the bridge is
            // already detached from the controller so nothing else uses it.
            Task {
                await bridge.announceUnpairedAndStop()
            }
        }
        if let relayDelete {
            Task { await relayDelete() }
        }
        bridge = nil
        stopAdvertising()
        pairedPID = nil
        pairedPhoneStatic = nil
        pairingCode = nil
        CompanionMacIdentity.deletePairedRoomSecret()
        CompanionMacIdentity.deleteKeyPair()
        CompanionPushRegistry.clear()
        DLog("Companion: unpaired; key material deleted")
        notifyPresenceChanged()
    }

    /// Build the best-effort, authenticated relay delete-room call for the
    /// current pairing, or nil if there is nothing to delete (no relay
    /// configured, no paired room secret, or no plugin egress). The returned
    /// closure captures the room secret now, so the caller can wipe local key
    /// material immediately without racing the network call. Best effort: a
    /// failure leaves the relay's idle TTL to reclaim the room.
    private func relayDeleteWork() -> (@Sendable () async -> Void)? {
        guard let origin = Self.configuredRelayOrigin(),
              let pid = pairedPID,
              let secret = CompanionMacIdentity.pairedRoomSecret(),
              let keyPair = try? CompanionMacIdentity.keyPair(),
              case .success(let plugin) = CompanionPlugin.instance() else { return nil }
        let roomName = RelayRoom.name(responderStaticPublicKey: keyPair.publicKey, pairingID: pid)
        let deleter = RelayRoomDeleter(origin: origin, http: plugin.httpClient(origin: origin))
        return {
            do {
                try await deleter.deleteRoom(roomName: roomName, roomSecret: secret)
                DLog("Companion: relay room deleted at unpair")
            } catch {
                DLog("Companion: relay delete-room failed (best-effort): \(error)")
            }
        }
    }

    /// The phone unpaired itself: mirror unpair() minus the farewell (the
    /// phone is the one leaving).
    private func peerDidUnpair() {
        relayLog("peerDidUnpair() called")
        RLog("Companion: peer unpaired; deleting key material")
        bridge?.stop()
        bridge = nil
        stopAdvertising()
        pairedPID = nil
        pairedPhoneStatic = nil
        pairingCode = nil
        CompanionMacIdentity.deletePairedRoomSecret()
        CompanionMacIdentity.deleteKeyPair()
        CompanionPushRegistry.clear()
        onDisconnect?()
        notifyPresenceChanged()
    }

    /// Stop advertising and accepting. Does NOT touch a connected bridge; the
    /// pairing window calls this when it closes.
    func stopAdvertising() {
        relayLog("stopAdvertising() called (cancelling acceptTask, stopping listener)")
        // Teardown of the current advertising intent: a fresh-pairing QR is no
        // longer live, so retry must not re-park it. An established pairing
        // (pairedPID) is unaffected and still drives reconnect.
        freshPairingActive = false
        freshPairingExpiry?.cancel()
        freshPairingExpiry = nil
        listenerRetryTask?.cancel()
        listenerRetryTask = nil
        // An accept loop parked in SAS entry must not leak its continuation.
        submitSASEntry(nil)
        acceptTask?.cancel()
        acceptTask = nil
        listener?.stop()
        listener = nil
        // The park is gone: no relay presence to time. A later resume re-parks and
        // restarts the timer from a fresh, accurate instant.
        relayConnectedSince = nil
        notifyPresenceChanged()
    }

    // MARK: SAS confirmation

    /// Pending code-entry continuation while a fresh pairing waits for the
    /// user to type the SAS code shown on the phone.
    private var sasContinuation: CheckedContinuation<String?, Never>?

    /// The window delivers the user's typed code here (nil = declined). Safe to
    /// call when no entry is pending.
    func submitSASEntry(_ code: String?) {
        sasContinuation?.resume(returning: code)
        sasContinuation = nil
    }

    /// Run the mac side of SAS confirmation: prompt for entry and allow a few
    /// mistypes before giving up. Returns whether the typed code matched.
    /// The phone SHOWS the code and the mac is input-only: a photographed-QR
    /// attacker never sees the victim's mac, so the victim has no code to type.
    private func runSASConfirmation(expected: String) async -> Bool {
        relayLog("SAS: awaiting code entry")
        onStatus?("Enter the code shown on your iPhone.")
        onSASEntryNeeded?()
        for attempt in 1...3 {
            let typed = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                sasContinuation = continuation
            }
            guard let typed else {
                relayLog("SAS: entry declined")
                return false
            }
            if typed.trimmingCharacters(in: .whitespacesAndNewlines) == expected {
                relayLog("SAS: code matched")
                return true
            }
            relayLog("SAS: mismatch (attempt \(attempt))")
            onStatus?("That code doesn’t match. Check your iPhone and try again.")
        }
        return false
    }

    private func installLogHandler() {
        CompanionLog.handler = { message in
            // RLog (retrospective): CompanionCore logs survive debug-logging-off,
            // so package-level traffic (e.g. the relay keepalive) is captured the
            // same way the rest of the companion logging is.
            RLog("\(message)")
        }
    }

    /// One-line trace of the relay lifecycle, stamped with the state that drives
    /// the single-mac-slot logic.
    private func relayLog(_ message: String) {
        // RLog (retrospective): the park / re-park / admission lifecycle stays
        // visible even with debug logging off, which is what we need to catch
        // the intermittent streaming relay wedge.
        RLog("Companion relay: \(message) "
             + "[bridge=\(bridge != nil) acceptTask=\(acceptTask != nil) "
             + "pairedPID=\(pairedPID ?? "nil") gate=\(Self.gate())]")
    }

    private func startListening(pairingID: String) throws {
        let keyPair = try CompanionMacIdentity.keyPair()
        // The relay origin comes from local config, not the stored pairing, so
        // it applies to background reconnect listening too (where there is no
        // fresh QR). nil => local-network only, the default.
        let relayOrigin = Self.configuredRelayOrigin()
        let code = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                               pairingID: pairingID,
                               relayOrigin: relayOrigin)
        let roomName = relayOrigin == nil ? "n/a"
            : RelayRoom.name(responderStaticPublicKey: keyPair.publicKey, pairingID: pairingID)
        relayLog("startListening pid=\(pairingID) relayOrigin=\(relayOrigin ?? "nil") room=\(roomName)")
        // Record the attempt for the settings "last try…" timer.
        lastRelayAttempt = Date()
        notifyPresenceChanged()
        // Route relay egress through the consent plugin (the only outbound path).
        // startListening is only reached when the gate is allowed, so the plugin
        // is installed and verified; fall back defensively just in case.
        let webSocketFactory: RelayWebSocketFactory
        if case .success(let plugin) = CompanionPlugin.instance() {
            webSocketFactory = plugin.webSocketFactory()
        } else {
            webSocketFactory = URLSessionRelayWebSocketFactory()
        }
        let listener = try CompanionTransports.listener(
            pairingID: pairingID,
            responderStaticPublicKey: keyPair.publicKey,
            relayOrigin: relayOrigin,
            webSocketFactory: webSocketFactory,
            // Parked = admitted to the relay room = reachable. Start the
            // connected timer (if a bridge hasn't already), for the settings UI.
            // onParked fires on the background accept task, so hop to the main
            // actor this controller is isolated to.
            onParked: { [weak self] in
                Task { @MainActor in
                    guard let self, self.relayConnectedSince == nil else { return }
                    self.relayConnectedSince = Date()
                    self.notifyPresenceChanged()
                }
            },
            // Sign the mac's park once the phone has couriered the room secret
            // and the room is established; nil keeps an open-mode park.
            roomSecret: { CompanionMacIdentity.pairedRoomSecret() })
        self.listener = listener
        acceptTask = Task { [weak self] in
            await self?.acceptLoop(listener: listener, keyPair: keyPair, code: code)
        }
    }

    /// The relay origin the pairing uses for connectivity. The relay is the
    /// only transport (Bonjour is currently disabled), so this must be set for
    /// pairing to work; it defaults to the project relay and can be overridden
    /// per machine via the CompanionRelayOrigin default (e.g. a fork's own
    /// Worker, or an open-mode test relay). Setting it to the empty string
    /// disables the relay entirely (no transport, pairing cannot complete).
    /// Validated as a bare https origin with the same rule the phone applies to
    /// the QR, so an invalid value is ignored (logged) rather than producing a
    /// QR the phone rejects.
    static let relayOriginKey = "CompanionRelayOrigin"
    static let defaultRelayOrigin = "https://companion-relay.iterm2.com"

    private static func configuredRelayOrigin() -> String? {
        let raw = iTermUserDefaults.userDefaults().string(forKey: relayOriginKey) ?? defaultRelayOrigin
        guard !raw.isEmpty else {
            // Explicitly disabled.
            return nil
        }
        guard let origin = try? PairingCode.canonicalRelayOrigin(raw) else {
            DLog("Companion: ignoring \(relayOriginKey)=\(raw); must be a bare https origin")
            return nil
        }
        return origin
    }

    private func acceptLoop(listener: TransportListener,
                            keyPair: NoiseKeyPair,
                            code: PairingCode) async {
        RLog("Companion pairing: accept loop started (pid \(code.pairingID))")
        relayLog("acceptLoop START pid=\(code.pairingID); awaiting a connection (park)")
        onStatus?("Waiting for your iPhone…")
        while !Task.isCancelled {
            let transport: MessageTransport
            do {
                transport = try await listener.accept()
            } catch {
                listener.stop()
                if self.listener === listener {
                    self.listener = nil
                }
                acceptTask = nil
                // Only a cancelled accept task is a deliberate local teardown:
                // stopAdvertising() cancels it, and that is the single path
                // reached by unpair, a gate close, a peer unpair, and the
                // pairing window closing. EVERY other failure, including
                // TransportError.closed, is the relay or edge closing our parked
                // socket from under us (idle reap past the keepalive, a relay
                // redeploy, a network change, sleep/wake) and must be recovered
                // from, not mistaken for a local teardown. Conflating the two
                // left the mac silently dark: paired, not parked, and
                // unreachable by the phone until the next relaunch.
                let cancelled = Task.isCancelled || error is CancellationError
                // A fresh-pairing park that dies without our cancelling it means
                // the relay tore the room down (e.g. the anti-grind cycle cap
                // tripped). Re-advertise under a new pid rather than going dark,
                // so a photographed QR cannot keep targeting the dead room.
                if !cancelled, freshPairingActive, bridge == nil {
                    relayLog("acceptLoop: fresh-pairing park closed by relay; regenerating pid")
                    regenerateFreshPairing(reason: "park-closed")
                    return
                }
                RLog("Companion pairing: accept ended: \(error), cancelled=\(cancelled)")
                relayLog("acceptLoop EXIT via accept() error (cancelled=\(cancelled)): \(error)")
                if cancelled {
                    return
                }
                // The relay evicted our park because another mac-role connection
                // took the room's single slot (closeCode 1000 "displaced") - almost
                // always a SECOND iTerm2 instance paired to the same room. Re-parking
                // on the routine 5s timer would immediately evict that other instance,
                // which re-parks and evicts us, an endless eviction storm that hammers
                // the relay and flaps the phone's reachability. Back off much longer so
                // the two instances settle instead of ping-ponging; still finite, so we
                // reclaim the slot if the other instance goes away. NOT a user-facing
                // fault (so no onFailed), and NOT the routine-churn path below.
                if error is RelayDisplacedError {
                    relayLog("acceptLoop: park displaced by another mac connection; "
                        + "backing off \(Self.displacedListenerRetryNanos / 1_000_000_000)s")
                    scheduleListenerRetry(after: Self.displacedListenerRetryNanos)
                    return
                }
                // A genuine park loss while a device is still paired. Re-park so
                // the phone can reconnect; without this the mac goes silently
                // dark. A closed park is routine churn, so retry quietly and
                // surface only real faults (e.g. a connection/DNS failure).
                if (error as? TransportError) != .closed {
                    onFailed?(Self.userFacingDescription(of: error))
                }
                scheduleListenerRetry()
                return
            }
            do {
                // A connection is being handshaked/confirmed: hold the expiry
                // timer off so it cannot regenerate the pid mid-pairing. Cleared
                // on every exit from this block (success, reject, or failure).
                confirmationInProgress = true
                defer { confirmationInProgress = false }
                RLog("Companion pairing: connection accepted; starting Noise handshake")
                relayLog("acceptLoop: connection ACCEPTED (peer joined); starting Noise handshake")
                onStatus?("Phone connected. Securing the connection…")
                let channel = try await NoiseHandshake.perform(
                    role: .responder,
                    transport: transport,
                    localKeyPair: keyPair,
                    remoteStaticPublicKey: nil,
                    prologue: code.handshakePrologue())
                RLog("Companion pairing: handshake complete")

                // The relay is untrusted: it cannot vouch for who connected.
                // Authenticate the phone end-to-end by its Noise static key,
                // learned (and decrypted) during the handshake. Fail closed if
                // we somehow did not learn it.
                guard let phoneStatic = channel.remoteStaticPublicKey else {
                    RLog("Companion pairing: no phone static key; rejecting")
                    relayLog("acceptLoop: REJECT, no phone static key from handshake")
                    await channel.close()
                    continue
                }

                if code.pairingID != pairedPID {
                    // Fresh pairing (pid not yet persisted): the user types the
                    // SAS code the phone shows; the verdict is the first frame on
                    // the encrypted channel. On acceptance the phone static is
                    // pinned below so future reconnects are authenticated.
                    let expected = PairingSAS.code(handshakeHash: channel.handshakeHash)
                    let accepted = await runSASConfirmation(expected: expected)
                    onSASEntryDismissed?(accepted)
                    let verdict: PairingConfirmation = accepted ? .accepted : .rejected
                    try await channel.send(verdict.encoded())
                    if !accepted {
                        // A rejected SAS (mistyped past the cap, or declined) is
                        // the observable signature of a hijack attempt. Void this
                        // pid and re-advertise under a fresh one so the attacker's
                        // photographed QR is invalidated and they must start over.
                        RLog("Companion pairing: SAS not confirmed; regenerating pid")
                        relayLog("acceptLoop: SAS REJECTED; closing and regenerating pid")
                        onStatus?("Pairing declined.")
                        await channel.close()
                        regenerateFreshPairing(reason: "sas-rejected")
                        return
                    }
                } else {
                    // Reconnect to a known pid: REQUIRE the SAS-confirmed pinned
                    // static. Reject end-to-end (regardless of what the relay
                    // admitted) on a mismatch (a QR-photo attacker reaching the
                    // relay) AND on a MISSING static (a partially-committed
                    // pairing: the pid persisted but the Keychain write of the
                    // static crashed or failed silently). Admitting either would
                    // be trust-on-first-use, pinning whatever phone connected
                    // first, so reject and force re-pairing instead.
                    guard let pinned = pairedPhoneStatic, pinned == phoneStatic else {
                        RLog("Companion pairing: reconnect static missing or mismatched; rejecting")
                        relayLog("acceptLoop: REJECT, reconnect static missing/mismatched; re-pair required")
                        await channel.close()
                        continue
                    }
                }
                relayLog("acceptLoop: handshake COMPLETE; creating bridge")

                let newBridge = CompanionHostBridge(transport: channel)
                newBridge.onClose = { [weak self, weak newBridge] in
                    guard let self, let newBridge, self.bridge === newBridge else {
                        // A stale bridge must not tear down its replacement.
                        DLog("Companion: stale bridge closed; ignoring")
                        self?.relayLog("bridge.onClose: STALE bridge closed; ignoring")
                        return
                    }
                    RLog("Companion: bridge closed; resuming listening for reconnect")
                    self.relayLog("bridge.onClose: LIVE bridge closed; nil-ing bridge + resuming")
                    self.bridge = nil
                    self.onDisconnect?()
                    self.resumePairedListeningIfNeeded()
                }
                newBridge.onPeerUnpaired = { [weak self] in
                    self?.peerDidUnpair()
                }
                newBridge.onConnectionClassified = { [weak self, weak newBridge] solicited in
                    guard let self, let newBridge else { return }
                    self.connectionDidClassify(newBridge, solicited: solicited)
                }
                newBridge.onVersionIncompatible = { [weak self] verdict in
                    self?.showVersionIncompatibleAlert(verdict)
                }
                newBridge.start()
                let staleBridge = bridge
                bridge = newBridge
                if let staleBridge {
                    // The phone reconnected while the previous TCP session
                    // still looked alive here (e.g. its wifi was off). The new
                    // handshake supersedes it.
                    DLog("Companion: replacing stale bridge with the new connection")
                    staleBridge.stop()
                }
                // Persist so future reconnects authenticate. Pin the phone static
                // FIRST and confirm it actually landed, then record the pid that
                // gates the SAS skip. The two stores (Keychain + UserDefaults) are
                // not atomic, so order matters: this way an interrupted or failed
                // write can leave the static without the pid (a clean re-pair) but
                // never the pid without the static (which would reopen
                // trust-on-first-use on the next reconnect).
                pairedPhoneStatic = phoneStatic
                guard pairedPhoneStatic == phoneStatic else {
                    // The Keychain write did not stick (the setter swallows the
                    // error). The live session is fine, SAS just confirmed it, but
                    // do NOT record the pid: leave the device unpaired so the next
                    // session re-pairs rather than reconnecting against a missing
                    // pinned static.
                    RLog("Companion pairing: phone static did not persist; not recording the pid")
                    relayLog("acceptLoop: phone static did not persist; leaving unpaired (re-pair required)")
                    onPaired?()
                    acceptTask = nil
                    return
                }
                pairedPID = code.pairingID
                // Now established: reconnect is keyed on pairedPID, so the
                // fresh-pairing intent is done.
                freshPairingActive = false
                onPaired?()
                // Connected: stop accepting now. The relay room has a single mac
                // slot, so parking again while connected would displace this very
                // connection (newest-wins). The next park happens only after this
                // connection is gone, driven by the bridge's onClose ->
                // resumePairedListeningIfNeeded above. (When Bonjour returns as a
                // parallel transport, this can keep accepting again.)
                acceptTask = nil
                relayLog("acceptLoop EXIT: connected, bridge up, stopped accepting "
                         + "(reconnect now driven by bridge.onClose)")
                return
            } catch {
                RLog("Companion pairing: handshake failed: \(error); still listening")
                relayLog("acceptLoop: handshake FAILED (\(error)); closing socket and re-accepting")
                onStatus?("Waiting for your iPhone…")
                // The parked socket was consumed by the failed handshake; close
                // it so the next accept() can park a fresh one (and the relay
                // listener's wait-for-close serialization is released).
                await transport.close()
            }
        }
    }

    /// Convert transport errors into actionable text.
    private static func userFacingDescription(of error: Error) -> String {
        if let transport = error as? TransportError {
            return transport.errorDescription ?? "\(error)"
        }
        // Surface the real failure, not bridged-NSError boilerplate.
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let code):
                if let cString = strerror(code.rawValue) {
                    return String(cString: cString)
                }
            case .dns(let code):
                return "Bonjour/DNS error \(code)"
            case .tls(let status):
                return "TLS error \(status)"
            default:
                // A plain default (not @unknown): NWError has availability-gated
                // cases (e.g. .wifiAware on macOS 26+) that cannot be named on
                // the macOS 12 deployment target, so they fall through to the
                // localizedDescription below.
                break
            }
        }
        return error.localizedDescription
    }

    private static func makePairingID() -> String {
        // 64-bit rendezvous id (16 hex chars). The room name is SHA(rs ‖ pid);
        // a longer pid makes the active room infeasible to find/squat for an
        // attacker who knows the long-lived rs.
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).hexEncodedString()
    }

    // MARK: QR rendering

    /// Render a QR code image for a string using CoreImage. `pointSize` is the
    /// logical size of the returned image; it is rasterized at 2x for crispness.
    static func qrImage(for string: String, pointSize: CGFloat) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage, output.extent.width > 0 else {
            return nil
        }
        let scale = (pointSize * 2) / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(representation)
        return image
    }
}

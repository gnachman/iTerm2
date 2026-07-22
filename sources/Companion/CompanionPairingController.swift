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
import LocalAuthentication
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

    /// A device is paired but the relays it was established against no longer
    /// match where this build points (the push relay it registered with, or the
    /// main relay it paired over): the phone is pinned to the old relays until
    /// the user pairs again. Only a POSITIVELY recorded origin that differs
    /// counts as a move. A never-recorded origin (nil) is NOT a move: it just
    /// means this pairing predates the mac tracking these hosts. The main relay is
    /// backfilled on the next successful reconnect (see recordCurrentMainRelay);
    /// the push relay stays nil until a re-pair, since a reconnect cannot evidence
    /// it. Either way, treating nil as "moved" here would nag a perfectly working
    /// pairing on every launch.
    private var relayConfigurationChanged: Bool {
        guard hasPairedDevice else { return false }
        if let recorded = CompanionPushRegistry.registeredPushRelayURL,
           recorded != CompanionPushRelay.baseURL.absoluteString {
            return true
        }
        // The main-relay-origin move check is a DIRECT-mode (v1) concept: it
        // exists because a v1 QR bakes in a specific relay host. In resolved (v2)
        // mode the pairing is anchored to the resolver URL instead, and the owning
        // host moves freely via the shard map (no re-pair), so this comparison is
        // meaningless here. Skip it when a resolver is configured, or a change to
        // the (v2-irrelevant) CompanionRelayOrigin setting would raise a spurious
        // "server moved" prompt. A resolver-URL move is a DNS concern (the URL is a
        // stable name), so there is nothing to detect for v2.
        if Self.configuredResolverURL() == nil,
           let recorded = CompanionPushRegistry.registeredMainRelayOrigin,
           recorded != Self.configuredRelayOrigin() {
            return true
        }
        return false
    }

    /// Called once at app launch. If a device is paired, the feature is enabled,
    /// and the pairing predates a relay host move (see CompanionPushRelay and the
    /// CompanionRelayOrigin setting), tell the user their phone must be paired
    /// again to keep working, and open Companion Device Settings if they accept.
    /// The phone need not be connected: the check is entirely local. "Later"
    /// defers to the next launch, since the condition still holds until they
    /// re-pair.
    @objc func promptToRepairAfterRelayMoveIfNeeded() {
        // Defer past launch so the alert appears after the app's windows settle,
        // and re-check the conditions on the main actor at that point.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.hasPairedDevice,
                  Self.gate() == .allowed,
                  self.relayConfigurationChanged else {
                return
            }
            // Don't stack two re-pair modals at launch: if the pairing is also
            // incomplete (missing/denied keychain credentials),
            // promptToRepairIfPairingIncompleteIfNeeded already asks the user to
            // re-pair, and re-pairing subsumes the relay-move fix. Yield to it.
            if case .incomplete = self.pairingCompleteness() {
                return
            }
            let alert = NSAlert()
            alert.messageText = "Re-pair Your Companion Device"
            alert.informativeText =
                "The iTerm2 server has moved to a new address. Your paired "
                + "iPhone is still registered with the old server. The old "
                + "server will go away soon. You should re-pair to avoid "
                + "problems when that happens."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                CompanionOnboardingRouter.openSettingsOrWizard()
            }
        }
    }

    /// Whether the persisted pairing has everything a reconnect actually needs.
    /// `pairedPID` (UserDefaults) only says "a device is paired" and is what makes
    /// the mac try to park. The credentials that authenticate the reconnect live in
    /// the keychain and can be lost INDEPENDENTLY of the pid: a code-signature change
    /// after rebuilding/reinstalling denies the login-keychain items, a `-suite`
    /// mismatch reads a different account, or a pairing committed the pid but not
    /// (yet) every keychain write. In that half-paired state the relay refuses the
    /// park forever ("signature required"), so we detect it and tell the user to
    /// re-pair rather than spin.
    enum PairingCompleteness: Equatable {
        case unpaired
        case complete
        case incomplete(missing: [String])
    }

    func pairingCompleteness() -> PairingCompleteness {
        guard hasPairedDevice else { return .unpaired }
        var missing: [String] = []
        // Only a GENUINE absence (errSecItemNotFound) counts as missing. A transient
        // keychain read failure (a denied access prompt at launch, a locked keychain,
        // a code-signature mismatch after a rebuild) must not, or the pairing would
        // look permanently incomplete: resume would skip parking forever and the
        // re-pair modal would spam on every launch. See CompanionMacIdentity.KeychainRead.
        if CompanionMacIdentity.isGenuinelyAbsent(.identityKey) { missing.append("the Mac identity key") }
        if CompanionMacIdentity.isGenuinelyAbsent(.pairedPhoneKey) { missing.append("the paired phone key") }
        // The relay room secret is intentionally NOT part of this decision: the phone
        // re-couriers it over the Noise channel on every connect, so a missing or
        // unreadable one self-heals. Blocking resume on it (or prompting re-pair)
        // would be wrong; the mac still parks and the re-courier restores it.
        return missing.isEmpty ? .complete : .incomplete(missing: missing)
    }

    /// Log exactly which pairing pieces are present vs absent, so a half-paired
    /// state is diagnosable at a glance (pid in UserDefaults; the rest in keychain).
    func logPairingState(context: String) {
        RLog("Companion pairing state (\(context)): pairedPID=\(pairedPID ?? "nil") "
            + "identityKey=\(CompanionMacIdentity.hasKeyPair()) "
            + "phoneStatic=\(CompanionMacIdentity.pairedPhoneStaticPublicKey() != nil) "
            + "roomSecret=\(CompanionMacIdentity.pairedRoomSecret() != nil) "
            + "pushSecret=\(CompanionMacIdentity.pairedPushSecret() != nil) "
            + "relayConfigured=\(Self.configuredRelayOrigin() != nil)")
    }

    /// Called once at app launch (alongside promptToRepairAfterRelayMoveIfNeeded).
    /// If the device is marked paired but the credentials a reconnect needs are
    /// missing, the pairing can never authenticate: tell the user to re-pair (and
    /// open settings/wizard on accept) instead of silently failing every park.
    @objc func promptToRepairIfPairingIncompleteIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logPairingState(context: "launch")
            guard Self.gate() == .allowed,
                  case .incomplete(let missing) = self.pairingCompleteness() else {
                return
            }
            RLog("Companion pairing incomplete at launch (missing: \(missing.joined(separator: ", "))); prompting to re-pair")
            let alert = NSAlert()
            alert.messageText = "Re-pair Your Companion Device"
            alert.informativeText =
                "Your paired iPhone can’t connect because some pairing information "
                + "stored on this Mac is missing (\(missing.joined(separator: ", "))). "
                + "This can happen after reinstalling or rebuilding iTerm2, or after a "
                + "keychain reset. Re-pair to fix it."
            alert.addButton(withTitle: "Re-pair…")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                CompanionOnboardingRouter.openSettingsOrWizard()
            }
        }
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
                // The first successful pairing makes the user "experienced": the
                // onboarding wizard is first-run only, so record this durable,
                // device-global flag (never cleared on unpair) so future visits to
                // Companion Device Settings open the plain window, not the wizard.
                CompanionPushRegistry.setEverPaired(true)
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
    var isListening: Bool { acceptTask != nil || pairedListenerRetry.isPending }

    /// When the mac's CONTINUOUS relay presence began (it parked, or a phone
    /// bridged), or nil while not connected. Stays set across park -> phone
    /// connect -> repark; cleared only when a retry is scheduled (a real drop) or
    /// listening stops. Drives the "connected for…" timer in settings.
    private(set) var relayConnectedSince: Date?
    /// When the mac last ATTEMPTED to (re)establish its relay park. Drives the
    /// "last try…" timer while not connected.
    private(set) var lastRelayAttempt: Date?
    /// Set when the relay tore the room down for hitting its daily data quota;
    /// holds the time the mac will next attempt to reconnect. While in the future
    /// the mac deliberately stays backed off (re-parking sooner only trips the same
    /// limit), and the settings UI shows the quota state instead of "reconnecting".
    /// Cleared once the mac parks successfully again.
    private(set) var relayQuotaBackoffUntil: Date?

    /// The mac's relay status for the settings UI.
    enum RelayStatus: Equatable {
        case idle                          // not paired: nothing to show
        case connected(since: Date)        // parked / phone-bridged: reachable
        case reconnecting(lastAttempt: Date?)  // not connected; retrying
        case quotaExceeded(retryAt: Date)  // relay daily data limit hit; backing off
    }
    var relayStatus: RelayStatus {
        guard hasPairedDevice else { return .idle }
        if let since = relayConnectedSince { return .connected(since: since) }
        // A quota teardown outranks the generic "reconnecting" while the backoff
        // window is still in the future, so the user learns WHY it is not connected.
        if let until = relayQuotaBackoffUntil, until > Date() {
            return .quotaExceeded(retryAt: until)
        }
        return .reconnecting(lastAttempt: lastRelayAttempt)
    }

    /// The relay room name (64-char lowercase hex) of the currently paired device,
    /// or nil when not paired (or the mac's key is unavailable). Derived, not
    /// stored, from the mac's static key and the paired pid the same way the
    /// transport does, so the settings window can show it for support/debugging (it
    /// is the pseudonym both devices and the relay log a room under).
    var pairedRoomName: String? {
        guard let pid = pairedPID,
              let keyPair = try? CompanionMacIdentity.keyPair() else { return nil }
        return RelayRoom.name(responderStaticPublicKey: keyPair.publicKey, pairingID: pid)
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
        // Pending retry/regeneration tasks count as serving: left alone they
        // would re-park (or mint a new QR) after the gate closed.
        guard bridge != nil || acceptTask != nil || pairedListenerRetry.isPending
                || freshPairingRegen.isPending else { return }
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

    /// Set once the revision-11 relay migration has run, so it does not repeat.
    /// NoSync: local device state, not a setting.
    private static let relayResolverMigrationDoneKey = "NoSyncCompanionRelayResolverMigrationDone"

    /// True from when the migration switches this mac to the resolver until either a
    /// phone connects (cleared, notice suppressed) or the grace period lapses with
    /// no phone (notice shown). Persisted so a relaunch mid-grace still resolves it.
    private static let migrationNoticePendingKey = "NoSyncCompanionRelayMigrationNoticePending"

    /// How long to wait for a phone to connect after the migration before showing
    /// the "update your iPhone" notice. Longer than the phone's grace: the phone may
    /// be asleep or away, and a needless nag is worse than a slightly delayed one.
    /// A ready phone connects within a few seconds, so 30s stays well clear of a
    /// false alarm while not feeling like nothing happened.
    private static let migrationNoticeGraceSeconds: TimeInterval = 30
    private var migrationNoticeTimer: Timer?

    /// Revision-11 migration (CompanionRelayMigration): move a mac that is parking
    /// on the legacy direct main relay onto the default resolver, and tell the user
    /// their iPhone must also update. Runs once (NoSync flag) and only for a paired
    /// mac, so the advanced-setting change is disclosed by the notice, never
    /// silently. Two parts, deliberately independent:
    ///   1. ENDPOINT REWRITE, conditional: only a mac still parking on the legacy
    ///      direct relay (resolver empty AND relay == legacy) is switched to the
    ///      default resolver. Writing CompanionResolverURL + reloading makes the park
    ///      that follows resolve through the shard map. A mac already on a resolver
    ///      (the default) or a custom relay origin is left untouched.
    ///   2. UPDATE NOTICE, for ANY paired mac: whichever side is upgraded first, the
    ///      peer that has not updated cannot connect (it stays on the old relay, and
    ///      the raised minimumPeer refuses it), so it never reaches the version
    ///      handshake's upgrade wall. We therefore ARM the notice for every paired
    ///      mac, not only ones that needed a rewrite, so a mac that was already on a
    ///      resolver but whose iPhone is still old does not sit silently "broken".
    /// The notice is only ARMED here: armMigrationNoticeIfPending shows it only if no
    /// phone connects within the grace period, and a phone that already updated
    /// connects fine and clears the pending flag.
    private func migrateDirectRelayToResolverIfNeeded() {
        let defaults = iTermUserDefaults.userDefaults()
        // Silent once done: this runs on every resume (launch, reconnect, gate
        // change), so logging the common no-op would churn the RLog ring buffer.
        // The done/pending flags are inspectable via `defaults read` if needed.
        guard !defaults.bool(forKey: Self.relayResolverMigrationDoneKey) else { return }
        // Only act (and only mark done) once PAIRED. A fresh mac's first rev-11
        // launch is unpaired; marking done there would skip the notice for the
        // pairing it forms later, leaving it silently unable to reach an old iPhone.
        guard hasPairedDevice else {
            relayLog("Relay migration: not paired yet; deferring to the first paired launch")
            return
        }
        // Now set the flag, BEFORE the advanced-setting write below: that write posts
        // iTermAdvancedSettingsDidChange, which reentrantly calls this via
        // gateMayHaveChanged, and the flag makes that reentrant call a no-op.
        defaults.set(true, forKey: Self.relayResolverMigrationDoneKey)

        let resolver = Self.configuredResolverURL()
        let relay = Self.configuredRelayOrigin()
        let inDirectMode = (resolver == nil)
        let onLegacyRelay = (relay == CompanionRelayMigration.legacyDirectRelayOrigin)
        relayLog("Relay migration: running (resolver=\(resolver ?? "nil") relay=\(relay ?? "nil") "
            + "inDirectMode=\(inDirectMode) onLegacyRelay=\(onLegacyRelay))")
        if inDirectMode && onLegacyRelay {
            relayLog("Relay migration: switching this mac from the direct legacy relay to the default resolver")
            defaults.set(CompanionRelayMigration.defaultResolverURL, forKey: "CompanionResolverURL")
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        } else {
            relayLog("Relay migration: no endpoint rewrite (already on a resolver or a custom relay)")
        }
        relayLog("Relay migration: arming the update-your-iPhone notice (cancelled if a phone connects)")
        defaults.set(true, forKey: Self.migrationNoticePendingKey)
    }

    /// If a migration notice is pending, wait out the grace period for a phone to
    /// connect before showing it. Called on every resume (launch + reconnects); the
    /// timer is armed at most once per session, and a phone connecting cancels it
    /// (clearPendingMigrationNotice).
    private func armMigrationNoticeIfPending() {
        let defaults = iTermUserDefaults.userDefaults()
        // Silent common case: this runs on every resume, and the notice is pending
        // only briefly around a migration. All the branches below execute only while
        // pending, so they stay quiet in steady state.
        guard defaults.bool(forKey: Self.migrationNoticePendingKey) else { return }
        // The notice is meaningless without a paired iPhone. If the flag leaked past
        // an unpair (this runs before the park guards), clear it rather than nag a
        // Mac with no paired device.
        guard hasPairedDevice else {
            relayLog("Relay migration: notice pending but no paired device; clearing")
            clearPendingMigrationNotice()
            return
        }
        if isConnected {
            relayLog("Relay migration: notice pending but already connected; clearing")
            clearPendingMigrationNotice()
            return
        }
        // Only nag while we are actually serving: with the gate closed (AI/consent
        // off) no phone could connect regardless, so "update your iPhone" would
        // misattribute the cause. A gate change re-enters here and arms then.
        guard Self.gate() == .allowed else {
            relayLog("Relay migration: notice pending but gate not allowed; not arming yet")
            return
        }
        guard migrationNoticeTimer == nil else {
            relayLog("Relay migration: notice grace timer already armed")
            return
        }
        relayLog("Relay migration: arming \(Int(Self.migrationNoticeGraceSeconds))s grace timer before showing the update-your-iPhone notice")
        migrationNoticeTimer = Timer.scheduledTimer(withTimeInterval: Self.migrationNoticeGraceSeconds,
                                                    repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.migrationNoticeTimer = nil
                let d = iTermUserDefaults.userDefaults()
                guard d.bool(forKey: Self.migrationNoticePendingKey) else {
                    self.relayLog("Relay migration: grace elapsed but notice already resolved; not showing")
                    return
                }
                // Unpaired during the grace window: nothing to notify about.
                guard self.hasPairedDevice else {
                    self.relayLog("Relay migration: grace elapsed but no paired device; clearing")
                    self.clearPendingMigrationNotice()
                    return
                }
                if self.isConnected {
                    self.relayLog("Relay migration: grace elapsed but a phone is now connected; clearing")
                    self.clearPendingMigrationNotice()
                    return
                }
                d.set(false, forKey: Self.migrationNoticePendingKey)
                self.relayLog("Relay migration: no phone connection within the grace period; SHOWING the update-your-iPhone notice")
                self.presentRelayMigrationNotice()
            }
        }
    }

    /// Cancel any pending "update your iPhone" notice and its grace timer. Called
    /// when a phone connects (the iPhone is up to date) and on unpair (nothing left
    /// to notify about). Idempotent.
    private func clearPendingMigrationNotice() {
        let defaults = iTermUserDefaults.userDefaults()
        migrationNoticeTimer?.invalidate()
        migrationNoticeTimer = nil
        guard defaults.bool(forKey: Self.migrationNoticePendingKey) else { return }
        defaults.set(false, forKey: Self.migrationNoticePendingKey)
        relayLog("Relay migration: clearing the pending update-your-iPhone notice")
    }

    /// The one-time modal telling the user their iPhone must update. Deferred to the
    /// next main-loop turn so it does not run modally in the middle of the launch
    /// path, and posted at most once (guarded by the pending flag above).
    private func presentRelayMigrationNotice() {
        relayLog("Relay migration: presenting the update-your-iPhone alert")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update iTerm2 Buddy on your iPhone"
            alert.informativeText = "iTerm2 has moved to the new relay. For your Mac and iPhone to keep connecting, "
                + "update the iTerm2 Buddy app on your iPhone to the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Called at app launch (and after disconnects): if a device is paired,
    /// quietly advertise its pairing id so it can reconnect.
    @objc func resumePairedListeningIfNeeded() {
        installLogHandler()
        relayLog("resumePairedListeningIfNeeded called")
        // Revision-11 relay migration: move a mac still on the direct legacy relay
        // onto the resolver BEFORE the park below reads the resolver setting. Once-
        // guarded, so the reconnect-driven calls skip it. armMigrationNoticeIfPending
        // then waits out the grace period for a phone before nagging (a phone that
        // already updated connects and cancels it).
        migrateDirectRelayToResolverIfNeeded()
        armMigrationNoticeIfPending()
        // First call is at launch (the user is present); read the keychain-backed
        // identity material (Noise keypair, paired phone key, room secret), the
        // push secret, and the outstanding-nonce list into memory now, so later
        // reconnects and background sends serve from cache and never trigger a
        // keychain prompt while the user is away. (The nonce list is its own
        // keychain item, read lazily on first push without this.) All are
        // idempotent, so reconnect-driven calls are no-ops.
        //
        // Gated on evidence companion is or was paired: a live pairing (pairedPID)
        // or the keychain's own "has material" hint. A never-paired install skips
        // this whole block, so it never plants or rewrites the push-nonce keychain
        // item - which pops a code-signature confirmation prompt for anyone who
        // alternates differently-signed builds (a notarized nightly and an ad-hoc
        // self-build) - for a feature it never enabled. The hint is ONLY a launch
        // optimization: the on-demand connect/push reads elsewhere are NOT gated by
        // it, so a stale-false hint can never prevent a genuinely-needed keychain
        // read, and primeCacheAtLaunch reconciles the hint from ground truth (true
        // if it finds material, false if the keychain is genuinely empty).
        if hasPairedDevice || CompanionMacIdentity.keychainMayHaveMaterial {
            CompanionMacIdentity.primeCacheAtLaunch()
            CompanionPushRegistry.loadSecretAtLaunch()
            CompanionPushNonceRegistry.shared.primeAtLaunch()
        } else {
            relayLog("resume: skipping keychain prime (no pairing and no material hint)")
        }
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
        // A paired device means an AI query can arrive from the phone while the
        // user is away. Warm the API key cache now (at launch, or after a
        // disconnect) so that query serves its key from memory rather than
        // blocking on, or prompting for, keychain access with nobody present.
        // Gated on an actual pairing and idempotent, so this is a cheap no-op
        // on the reconnect-driven calls.
        if hasPairedDevice {
            AITermControllerObjC.prewarmAPIKeyCache()
        }
        // Park only when nothing is connected. The relay room has a single mac
        // slot, so parking while a bridge is live would displace it. The
        // bridge's onClose nils `bridge` before calling here, so a genuine
        // reconnect (after the connection is gone) still proceeds; only callers
        // firing while connected (launch races, gate changes) are held off.
        // A pending fresh-pairing regeneration owns the next park (under a NEW
        // pid): an externally triggered resume (the gate-change notifications
        // fire on every settings write) must not re-park the pid being retired,
        // sidestepping the failure backoff.
        guard acceptTask == nil, bridge == nil, !freshPairingRegen.isPending,
              let pid = desiredListeningPID else {
            relayLog("resume: SKIP guard "
                     + "(acceptTaskNil=\(acceptTask == nil) bridgeNil=\(bridge == nil) "
                     + "regenPending=\(freshPairingRegen.isPending) "
                     + "hasPID=\(desiredListeningPID != nil))")
            return
        }
        // A persisted pid whose keychain credentials are missing can never
        // authenticate a reconnect: the relay just refuses the park forever
        // ("signature required"). Don't spin - the launch prompt (and settings) tell
        // the user to re-pair. Fresh pairing is exempt (it legitimately parks
        // open-mode before any credential exists; pairedPID is still nil then, so
        // pairingCompleteness would report .unpaired anyway - the flag is belt and
        // suspenders for a re-pair over an existing pairing).
        if !freshPairingActive, case .incomplete(let missing) = pairingCompleteness() {
            relayLog("resume: SKIP - pairing incomplete (missing: \(missing.joined(separator: ", "))); re-pair required, not parking")
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
    /// silently stops advertising and the phone can never reconnect. Retries
    /// back off (see RelayRetryScheduler) so a relay that fails every connect,
    /// e.g. with a bad TLS certificate, is not hammered on a fixed cadence.
    private let pairedListenerRetry = RelayRetryScheduler()

    /// A park displaced by another mac-role connection (a duplicate instance in the
    /// same room) backs off much longer than the routine delay so the two don't
    /// ping-pong evicting each other; finite so the slot is reclaimed if the other
    /// instance exits.
    private static let displacedListenerRetryNanos: UInt64 = 60_000_000_000

    /// After a relay daily-quota teardown, wait this long before re-parking:
    /// reconnecting sooner just trips the same limit and hammers an already
    /// exhausted quota. Fixed (the relay reports no reset time), so this is a
    /// gentle poll that recovers once the relay's 24h window rolls over.
    private static let quotaListenerRetryNanos: UInt64 = 30 * 60 * 1_000_000_000

    /// Failure-driven fresh-pairing regeneration uses the same backoff: a dead
    /// QR park is re-advertised under a NEW pid, and doing that instantly for a
    /// connection that fails in milliseconds would mint pids, redraw the QR, and
    /// hit the relay dozens of times per second.
    private let freshPairingRegen = RelayRetryScheduler()

    private func scheduleListenerRetry(after overrideNanos: UInt64? = nil) {
        guard !pairedListenerRetry.isPending, desiredListeningPID != nil else {
            return
        }
        // A retry is scheduled because we are NOT connected: end the connected
        // timer so settings shows "reconnecting" with the last-attempt time.
        relayConnectedSince = nil
        notifyPresenceChanged()
        pairedListenerRetry.schedule(overrideNanos: overrideNanos) { [weak self] in
            self?.resumePairedListeningIfNeeded()
        }
    }

    /// Enter the relay daily-quota backoff: record when we will next try (for the
    /// settings UI) and schedule the re-park far enough out that we do not hammer
    /// the exhausted quota. Called from both the live-bridge close and a parked
    /// socket close, since either can carry the quota teardown.
    private func enterRelayQuotaBackoff(reason: String) {
        let minutes = Self.quotaListenerRetryNanos / 1_000_000_000 / 60
        relayQuotaBackoffUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        relayLog("relay daily quota exceeded (\(reason)); backing off \(minutes)m before re-parking")
        // Drop any pending routine (5s) retry so the long quota backoff wins;
        // otherwise a re-park fires in seconds and trips the same limit again.
        pairedListenerRetry.cancel()
        // Schedules the re-park AND clears relayConnectedSince + notifies presence,
        // so relayStatus flips to .quotaExceeded for the settings UI.
        scheduleListenerRetry(after: Self.quotaListenerRetryNanos)
    }

    /// Require the device owner to authenticate before showing a fresh pairing
    /// QR, so brief physical access to an unlocked Mac is not enough to pair a
    /// new device. Authentication uses biometrics when available and falls back
    /// to the device passcode/login password. Shared by the Companion Device
    /// Settings window and the onboarding wizard.
    func authenticateToPair() async -> Bool {
        let context = LAContext()
        var error: NSError?
        // .deviceOwnerAuthentication uses biometrics when available and falls
        // back to the device passcode/login password otherwise.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics and no passcode configured: there is nothing to
            // authenticate against, so let pairing proceed (the Mac is unsecured
            // regardless).
            RLog("Companion: no device authentication available (\(error?.localizedDescription ?? "none")); proceeding")
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: "pair a companion device with this Mac") { success, authError in
                if let authError {
                    RLog("Companion: pairing authentication failed: \(authError.localizedDescription)")
                }
                continuation.resume(returning: success)
            }
        }
    }

    /// Begin a fresh pairing. Returns the pairing code whose URL should be
    /// displayed as a QR.
    func startPairing() throws -> PairingCode {
        installLogHandler()
        relayLog("startPairing() called (fresh QR)")
        // A user-initiated session starts the backoff ratchets over. A
        // failure-driven regeneration re-enters here with freshPairingActive
        // still true and must NOT reset, or the backoff would forget itself on
        // every retry.
        if !freshPairingActive {
            pairedListenerRetry.reset()
            freshPairingRegen.reset()
        }
        stopAdvertising()
        let keyPair = try CompanionMacIdentity.keyPair()
        let pairingID = Self.makePairingID()
        // The two modes are exclusive (design docs/companion-relay-design.md):
        // when a resolver is configured (the default) the QR is resolved mode
        // (v2, resolver=, no relay=); with an empty resolver setting it falls
        // back to direct mode (v1, relay=). In resolved mode BOTH endpoints
        // resolve the owning shard host from the map and rendezvous there (the mac
        // in parkAndAccept, the phone in ResolvingTransportConnector); they must
        // resolve identically or rendezvous fails (§6.4). In direct mode the mac
        // parks at its configured relay origin.
        let code: PairingCode
        if let resolverURL = Self.configuredResolverURL() {
            code = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                               pairingID: pairingID,
                               resolverURL: resolverURL)
        } else {
            code = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                               pairingID: pairingID,
                               relayOrigin: Self.configuredRelayOrigin())
        }
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

    /// Regenerate the fresh-pairing pid after a park loss, on the scheduler's
    /// capped doubling delay. A park that succeeded resets the delay to the
    /// floor (onParked calls noteSuccess), so the routine relay-teardown case
    /// re-advertises promptly, while a park that never succeeds backs off
    /// toward the cap however long each failure takes (an instant bad-cert
    /// rejection or a slow connect timeout alike).
    private func scheduleFreshPairingRegeneration(reason: String) {
        guard !freshPairingRegen.isPending else { return }
        relayLog("scheduleFreshPairingRegeneration(\(reason)): regenerating in "
                 + "\(freshPairingRegen.nextDelaySeconds)s")
        // Not parked while waiting: end the connected timer, as scheduleListenerRetry does.
        relayConnectedSince = nil
        notifyPresenceChanged()
        freshPairingRegen.schedule { [weak self] in
            guard let self else { return }
            // Never yank the pid out from under a phone mid-handshake or
            // mid-SAS; those paths decide what happens next themselves (the
            // same deferral startFreshPairingExpiry applies).
            guard self.bridge == nil, !self.confirmationInProgress else { return }
            self.regenerateFreshPairing(reason: reason)
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
        CompanionChatMuteRegistry.clear()
        // No paired device left, so a pending migration notice is moot; clear it
        // (and cancel its timer) so a later resume cannot nag an unpaired Mac.
        clearPendingMigrationNotice()
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
        guard let pid = pairedPID,
              let secret = CompanionMacIdentity.pairedRoomSecret(),
              let keyPair = try? CompanionMacIdentity.keyPair(),
              case .success(let plugin) = CompanionPlugin.instance() else { return nil }
        let resolverURL = Self.configuredResolverURL()
        let directOrigin = Self.configuredRelayOrigin()
        // Nothing to delete against if neither transport is configured.
        guard resolverURL != nil || directOrigin != nil else { return nil }
        let rs = keyPair.publicKey
        let roomName = RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid)
        // Resolved (v2) mode resolves the owning shard host through the plugin
        // egress; v1 uses the direct origin. Shared helper so the mac and phone
        // delete the same way.
        let deleteCode = PairingCode(responderStaticPublicKey: rs, pairingID: pid,
                                     resolverURL: resolverURL)
        let shardFetcher = plugin.shardMapFetcher()
        let makeHTTP: @Sendable (String) -> RelayHTTPClient = { plugin.httpClient(origin: $0) }
        return {
            guard let origin = await ShardHostResolver.resolveDeleteOrigin(
                    code: deleteCode, fetcher: shardFetcher, directOrigin: directOrigin) else {
                DLog("Companion: relay delete-room skipped (could not resolve owning host); idle TTL will reclaim")
                return
            }
            let deleter = RelayRoomDeleter(origin: origin, http: makeHTTP(origin))
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
        CompanionChatMuteRegistry.clear()
        // No paired device left, so a pending migration notice is moot; clear it.
        clearPendingMigrationNotice()
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
        // Cancel pending retries but keep their ratcheted delays: teardown is
        // not evidence the relay recovered. The ratchets reset on a successful
        // park (onParked) or a genuinely new session (startPairing).
        freshPairingRegen.cancel()
        pairedListenerRetry.cancel()
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

    /// The SAS the user types is exactly six decimal digits. Shared by the plain
    /// pairing window and the onboarding wizard so the accepted format is defined
    /// in one place.
    static func isCompleteSAS(_ s: String) -> Bool {
        return s.count == 6 && s.allSatisfy { ("0"..."9").contains($0) }
    }

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
        // Record the attempt for the settings "last try…" timer.
        lastRelayAttempt = Date()
        notifyPresenceChanged()
        // All egress (relay traffic and, in resolved mode, the shard-map fetch)
        // MUST go through the consent plugin, the feature's only sanctioned
        // outbound path. startListening is only reached when the gate is allowed,
        // which already requires the plugin, so this is defensive: if the plugin
        // is somehow unavailable, fail CLOSED (do not park) rather than fall back
        // to a raw URLSession that would carry traffic around the consent gate.
        guard case .success(let plugin) = CompanionPlugin.instance() else {
            relayLog("startListening: consent plugin unavailable; not parking (fail closed)")
            throw TransportError.connectionFailed("companion consent plugin unavailable")
        }
        let webSocketFactory = plugin.webSocketFactory()
        let shardFetcher = plugin.shardMapFetcher()
        // Identity of the plugin's client, so the shard-resolver cache can rebuild
        // after a plugin reload (which mints a new client): the shard fetch must
        // follow the current plugin like the relay socket does, not stay pinned to
        // a torn-down client.
        let shardClientID = ObjectIdentifier(plugin.client)
        // acceptLoop only needs the pid (and the pid-derived handshake prologue);
        // the park origin is resolved in parkAndAccept, which may require an async
        // shard-map lookup (resolved mode).
        let code = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                               pairingID: pairingID)
        acceptTask = Task { [weak self] in
            await self?.parkAndAccept(pairingID: pairingID,
                                      keyPair: keyPair,
                                      code: code,
                                      webSocketFactory: webSocketFactory,
                                      shardFetcher: shardFetcher,
                                      shardClientID: shardClientID)
        }
    }

    /// Resolve the origin the mac should park at, build the relay listener, and
    /// run the accept loop. Split off from startListening because resolved (v2)
    /// mode needs an async shard-map lookup before the origin is known, while
    /// direct (v1) mode uses the statically configured origin. Runs on acceptTask.
    private func parkAndAccept(pairingID: String,
                               keyPair: NoiseKeyPair,
                               code: PairingCode,
                               webSocketFactory: RelayWebSocketFactory,
                               shardFetcher: ShardMapFetching,
                               shardClientID: ObjectIdentifier) async {
        let relayOrigin: String?
        if let resolverURL = Self.configuredResolverURL() {
            // Resolved mode: look the owning host up in the shard map, exactly as
            // the phone does, so both land on the same box. A resolve failure (a
            // CDN blip, or a map that names no host) is a transient park failure:
            // retry, don't surface a hard error. A reshard drops the park later,
            // and that retry re-enters here and re-resolves onto the new owner.
            relayLog("parkAndAccept: resolved mode, resolver=\(resolverURL)")
            do {
                // Keyed on the plugin client identity so a plugin reload rebuilds
                // against the new egress rather than pinning the shard fetch to a
                // torn-down client.
                let resolver = shardResolverCache.resolver(resolverURL: resolverURL,
                                                           token: shardClientID,
                                                           fetcher: shardFetcher,
                                                           floorStore: shardMapFloorStore)
                let resolveCode = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                                              pairingID: pairingID,
                                              resolverURL: resolverURL)
                relayOrigin = try await resolver.relayOrigin(for: resolveCode)
            } catch {
                // If stopAdvertising cancelled us mid-resolve, it already owns the
                // teardown (it nilled acceptTask and cancelled the retry). Matching
                // the success-path check below, bail WITHOUT touching acceptTask or
                // rescheduling, or we would clobber a replacement task and re-park
                // after an intended teardown.
                if Task.isCancelled { return }
                acceptTask = nil
                parkSetupDidFail(error, what: "shard resolve")
                return
            }
        } else {
            // Direct mode: the statically configured relay origin from local config
            // (not the stored pairing), so it applies to background reconnect
            // listening too. nil => local-network only, the default.
            relayOrigin = Self.configuredRelayOrigin()
            relayLog("parkAndAccept: direct mode, relayOrigin=\(relayOrigin ?? "nil")")
        }
        // stopAdvertising cancels acceptTask and nils it; if that raced the resolve
        // above, bail without parking.
        if Task.isCancelled { return }

        let roomName = relayOrigin == nil ? "n/a"
            : RelayRoom.name(responderStaticPublicKey: keyPair.publicKey, pairingID: pairingID)
        relayLog("startListening pid=\(pairingID) relayOrigin=\(relayOrigin ?? "nil") room=\(roomName)")
        if relayOrigin != nil {
            // The park is signed only if we can read the couriered room secret from
            // the keychain. A rebuilt app whose code signature differs from the writer
            // is denied that item (see keychainLoad logging), so the secret reads as
            // nil and we park open-mode -- which the relay refuses with "signature
            // required" once the room's mac verifier is registered. Re-pair (or grant
            // the keychain prompt) to recover.
            let hasSecret = CompanionMacIdentity.pairedRoomSecret() != nil
            relayLog("startListening park proof: room secret \(hasSecret ? "present -> SIGNED park" : "MISSING -> open-mode park (relay will refuse \"signature required\" if the verifier is registered; re-pair or grant the keychain prompt)")")
        }

        let listener: TransportListener
        do {
            listener = try CompanionTransports.listener(
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
                        guard let self else { return }
                        // A successful park proves the relay reachable: the failure
                        // backoffs start over, and the waiting status becomes true.
                        // Emitted here rather than at accept-loop start so it cannot
                        // paper over a connection error surfaced while re-parking.
                        self.pairedListenerRetry.noteSuccess()
                        self.freshPairingRegen.noteSuccess()
                        // The park succeeded, so any prior quota teardown is behind us:
                        // clear the backoff marker so the UI leaves the quota state.
                        self.relayQuotaBackoffUntil = nil
                        self.onStatus?("Waiting for your iPhone…")
                        guard self.relayConnectedSince == nil else { return }
                        self.relayConnectedSince = Date()
                        self.notifyPresenceChanged()
                    }
                },
                // Sign the mac's park once the phone has couriered the room secret
                // and the room is established; nil keeps an open-mode park.
                roomSecret: { CompanionMacIdentity.pairedRoomSecret() })
        } catch {
            // Same as the resolve catch above: if stopAdvertising cancelled us,
            // it owns the teardown, so bail without touching acceptTask/retry.
            if Task.isCancelled { return }
            acceptTask = nil
            parkSetupDidFail(error, what: "listener build")
            return
        }
        if Task.isCancelled {
            listener.stop()
            return
        }
        self.listener = listener
        await acceptLoop(listener: listener, keyPair: keyPair, code: code)
    }

    /// A resolve or listener build failed before we could park (assumes acceptTask
    /// was already nil'd). On the fresh-pairing path this surfaces the failure to
    /// the pairing window and re-mints the pid on the regeneration backoff, exactly
    /// as acceptLoop's fresh-pairing park-closed branch does for a direct-mode
    /// park that dies. Without this a resolved (v2) QR whose resolver is
    /// unreachable (or names no host for the bucket) would sit silent forever: the
    /// window would show neither an error nor "Waiting for your iPhone…". For an
    /// established pairing there is usually no window to notify, so it just retries.
    private func parkSetupDidFail(_ error: Error, what: String) {
        if freshPairingActive, bridge == nil {
            relayLog("parkAndAccept: fresh-pairing \(what) failed: \(error); surfacing and regenerating")
            onFailed?(Self.userFacingDescription(of: error))
            scheduleFreshPairingRegeneration(reason: "\(what)-failed")
        } else {
            relayLog("parkAndAccept: \(what) failed: \(error); scheduling retry")
            scheduleListenerRetry()
        }
    }

    /// The per-session shard resolver cache (shared value type), keyed by resolver
    /// URL + plugin client identity so a plugin reload rebuilds against the new
    /// egress.
    private var shardResolverCache = ShardResolverCache()

    /// Durable per-resolver version floor (§6.4), so the highest shard-map version
    /// this mac has adopted survives a relaunch: a freshly launched mac must not
    /// adopt a map older than one it already trusted from a lagging CDN edge, or it
    /// would park a bucket on a host that no longer owns it. NoSync: local device
    /// state, not a synced setting, and stored in the iTermUserDefaults suite.
    private let shardMapFloorStore = UserDefaultsShardMapVersionFloorStore(
        defaults: iTermUserDefaults.userDefaults(),
        keyPrefix: "NoSyncCompanionShardMapFloor.")

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

    private static func configuredRelayOrigin() -> String? {
        // Configurable via the CompanionRelayOrigin advanced setting, which
        // supplies the default project relay when unset.
        let raw = iTermAdvancedSettingsModel.companionRelayOrigin() ?? ""
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

    /// The resolver URL embedded in the pairing QR: the control-plane endpoint
    /// the client asks which relay shard serves its room. Configurable via the
    /// CompanionResolverURL advanced setting, which defaults to the project
    /// resolver. Setting it to the empty string omits it from the QR, so the
    /// client falls back to connecting the relay origin directly (direct mode).
    /// Validated as an https URL with the same rule the phone applies to the QR,
    /// so an invalid value is ignored (logged) rather than producing a QR the
    /// phone rejects.
    private static func configuredResolverURL() -> String? {
        let raw = iTermAdvancedSettingsModel.companionResolverURL() ?? ""
        guard !raw.isEmpty else {
            // Explicitly disabled: fall back to direct mode.
            return nil
        }
        guard let url = try? PairingCode.canonicalResolverURL(raw) else {
            DLog("Companion: ignoring CompanionResolverURL=\(raw); must be an https URL")
            return nil
        }
        return url
    }

    /// Full-jitter delay for a re-park after a reshard evict (§7.3 / Appendix C),
    /// so a whole-fleet reshard does not have every mac re-park in lockstep.
    private let reconnectBackoff = RelayReconnectBackoff()
    private func jitteredReparkNanos() -> UInt64 {
        UInt64(reconnectBackoff.delay(consecutiveFailures: 1) * 1_000_000_000)
    }

    /// A stale-map reject/evict (§6.9): force the shared shard resolver to fetch a
    /// fresh map so the next park resolves the new owner instead of the cached
    /// (rejecting) host. Uses the same cached resolver (keyed on the plugin client)
    /// parkAndAccept reads, so the refresh is what the re-park picks up. No-op in
    /// direct mode or if the plugin is unavailable.
    private func forceReResolveCurrentPairing(keyPair: NoiseKeyPair, pairingID: String) async {
        guard let resolverURL = Self.configuredResolverURL(),
              case .success(let plugin) = CompanionPlugin.instance() else { return }
        let resolver = shardResolverCache.resolver(resolverURL: resolverURL,
                                                   token: ObjectIdentifier(plugin.client),
                                                   fetcher: plugin.shardMapFetcher(),
                                                   floorStore: shardMapFloorStore)
        let code = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                               pairingID: pairingID, resolverURL: resolverURL)
        _ = try? await resolver.relayOrigin(for: code, forceFresh: true)
    }

    private func acceptLoop(listener: TransportListener,
                            keyPair: NoiseKeyPair,
                            code: PairingCode) async {
        RLog("Companion pairing: accept loop started (pid \(code.pairingID))")
        relayLog("acceptLoop START pid=\(code.pairingID); awaiting a connection (park)")
        // No status here: "Waiting for your iPhone…" is emitted from onParked,
        // once the relay actually admits the park.
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
                // Classify once for both lanes below: a routine relay close
                // (idle reap, redeploy, network blip) retries quietly; anything
                // else (DNS, TLS, refused) is actionable and surfaced. Without
                // that, a misconfigured relay is just a QR that never pairs.
                let routineClose = (error as? TransportError) == .closed
                // A fresh-pairing park that dies without our cancelling it means
                // the relay tore the room down (e.g. the anti-grind cycle cap
                // tripped). Re-advertise under a new pid rather than going dark,
                // so a photographed QR cannot keep targeting the dead room.
                if !cancelled, freshPairingActive, bridge == nil {
                    relayLog("acceptLoop: fresh-pairing park closed; scheduling pid regeneration")
                    if routineClose {
                        // The displayed QR is dead until the regeneration
                        // fires; say so instead of leaving the stale
                        // "Waiting for your iPhone…" up.
                        onStatus?("Reconnecting to the relay…")
                    } else {
                        onFailed?(Self.userFacingDescription(of: error))
                    }
                    scheduleFreshPairingRegeneration(reason: "park-closed")
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
                // The relay hit its daily data quota and tore the room down. Re-parking
                // on the routine 5s timer just trips the same limit again all day, so
                // back off long and let the settings UI explain the wait. Not a
                // user-facing FAULT (no onFailed); the quota status carries it.
                if (error as? TransportError) == .quotaExceeded {
                    enterRelayQuotaBackoff(reason: "park closed")
                    return
                }
                // A stale-map reject/evict (§6.9, WS 4421 / HTTP 421): a reshard
                // moved this pairing's bucket to another host. Force a fresh map
                // fetch so the re-park resolves the new owner (not the cached,
                // rejecting host), then re-park promptly on a jittered delay that
                // flattens a whole-fleet reshard storm. Not a user-facing fault, so
                // no onFailed; symmetric with the phone reconnect loop.
                if case .reResolve(let owner)? = (error as? TransportError) {
                    relayLog("acceptLoop: park evicted by reshard (reResolve\(owner.map { ", owner hint \($0)" } ?? "")); re-resolving + re-parking")
                    await forceReResolveCurrentPairing(keyPair: keyPair, pairingID: code.pairingID)
                    scheduleListenerRetry(after: jitteredReparkNanos())
                    return
                }
                // A genuine park loss while a device is still paired. Re-park so
                // the phone can reconnect; without this the mac goes silently
                // dark. A closed park is routine churn, so retry quietly and
                // surface only real faults (e.g. a connection/DNS failure).
                if !routineClose {
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

                let isFreshPairing = code.pairingID != pairedPID
                if isFreshPairing {
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
                newBridge.onClose = { [weak self, weak newBridge] error in
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
                    // The relay tore the live connection down for its daily quota:
                    // re-parking now just trips the same limit, so back off long and
                    // let the settings UI explain it instead of the routine re-park.
                    if (error as? TransportError) == .quotaExceeded {
                        self.enterRelayQuotaBackoff(reason: "live bridge closed")
                        return
                    }
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
                if isFreshPairing {
                    // Fresh pairing: as part of pairing the phone registers its APNs
                    // token against its (current) push relay, and this connection was
                    // carried over the main relay, so BOTH origins are evidenced.
                    // Record them so a later host move can prompt a re-pair (see
                    // relayConfigurationChanged).
                    CompanionPushRegistry.recordCurrentRelays(
                        pushRelayURL: CompanionPushRelay.baseURL.absoluteString,
                        mainRelayOrigin: Self.configuredRelayOrigin())
                    // A brand-new device just paired while the user is present
                    // (they just confirmed the SAS code): warm the AI key cache
                    // now so a query later driven from the away phone serves its
                    // key from memory without a keychain prompt. The launch path
                    // covers devices already paired at startup; this covers a
                    // pairing that happens while the app is already running.
                    AITermControllerObjC.prewarmAPIKeyCache()
                } else {
                    // Reconnect: refresh ONLY the main relay. This connection is
                    // carried over the main relay, so it proves the phone still
                    // reaches us there (and backfills a pairing older than this
                    // tracking so a later main-relay move is detectable). It proves
                    // NOTHING about the push relay: the phone registers against its
                    // OWN build's CompanionPushRelay URL, which after a mac-only
                    // upgrade differs from ours until the phone app is itself updated
                    // and APNs re-registers. Stamping our push URL here would make
                    // relayConfigurationChanged see recorded == current and suppress a
                    // legitimate re-pair prompt while the phone still cannot receive
                    // pushes. So leave the recorded push relay untouched.
                    CompanionPushRegistry.recordCurrentMainRelay(Self.configuredRelayOrigin())
                }
                // Now established: reconnect is keyed on pairedPID, so the
                // fresh-pairing intent is done.
                freshPairingActive = false
                onPaired?()
                // A phone reached us, so the revision-11 migration succeeded: the
                // iPhone is up to date. Cancel any pending "update your iPhone" notice.
                clearPendingMigrationNotice()
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

/// One-shot retry scheduling with capped exponential backoff, shared by the
/// paired re-park lane and the fresh-pairing regeneration lane. schedule()
/// waits the current delay and doubles it for next time; noteSuccess() (a
/// successful relay park) resets it to the floor. So routine churn retries at
/// the floor while a relay that fails every connection attempt, at whatever
/// latency (an instant bad-cert rejection or a slow connect timeout alike),
/// backs off toward the cap instead of spinning.
@MainActor
private final class RelayRetryScheduler {
    private static let minDelayNanos: UInt64 = 5_000_000_000
    private static let maxDelayNanos: UInt64 = 60_000_000_000
    private var delayNanos = RelayRetryScheduler.minDelayNanos
    private var task: Task<Void, Never>?

    nonisolated init() {}

    var isPending: Bool { task != nil }

    /// Seconds schedule() would wait right now; for logging.
    var nextDelaySeconds: Int { Int(delayNanos / 1_000_000_000) }

    /// The relay was reached: the next failure starts over at the floor.
    func noteSuccess() {
        delayNanos = Self.minDelayNanos
    }

    /// Cancel a pending retry, keeping the ratcheted delay (teardown is not
    /// evidence of recovery).
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Cancel and forget the ratchet, for a genuinely new pairing session.
    func reset() {
        cancel()
        delayNanos = Self.minDelayNanos
    }

    /// Run `action` after the current delay, doubling it for next time; or
    /// after `overrideNanos` (the displaced-park case), leaving the ratchet
    /// alone. No-op while a retry is already pending.
    func schedule(overrideNanos: UInt64? = nil, action: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        let delay: UInt64
        if let overrideNanos {
            delay = overrideNanos
        } else {
            delay = delayNanos
            delayNanos = min(delayNanos * 2, Self.maxDelayNanos)
        }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            action()
        }
    }
}

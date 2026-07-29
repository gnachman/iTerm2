//
//  CompanionPushRegistry.swift
//  iTerm2
//
//  Holds the paired phone's push capability, reported over the companion
//  protocol on every connection: notification-permission state, the APNs
//  device token, and the phone-minted secret the relay requires (see
//  Companion/PushRelay). The orchestrator's notify tool keys off canNotify,
//  and everything here is destroyed with the rest of the pairing state on
//  unpair.
//

import Foundation
import CompanionProtocol

enum CompanionPushRegistry {
    private static let tokenKey = "NoSyncCompanionPushToken"
    // The relay secret now lives in the keychain (CompanionMacIdentity). This
    // flag records that we have one, so launch knows to load it without probing
    // the keychain unnecessarily. legacySecretKey is where an older build kept
    // the secret (plaintext) in UserDefaults; it is migrated and removed at launch.
    private static let hasSecretKey = "NoSyncCompanionPushHasRelaySecret"
    private static let legacySecretKey = "NoSyncCompanionPushRelaySecret"
    private static let sandboxKey = "NoSyncCompanionPushTokenSandbox"
    private static let authorizationKey = "NoSyncCompanionPushAuthorization"
    private static let peerRevisionKey = "NoSyncCompanionPeerRevision"
    private static let alertsEverEnabledKey = "NoSyncCompanionAlertsEverEnabled"
    private static let everPairedKey = "NoSyncCompanionEverPaired"
    private static let pushRelayURLKey = "NoSyncCompanionPushRelayBaseURL"
    private static let mainRelayOriginKey = "NoSyncCompanionMainRelayOrigin"

    // The secret authorizes push to the paired phone, so it is kept in the
    // keychain, not UserDefaults. To avoid a keychain prompt while the user is
    // away (background sends), it is loaded into memory once at launch (when the
    // user is present) and read from this cache thereafter.
    private static let secretLock = NSLock()
    private static var cachedSecretHex: String?
    private static var didLoadSecret = false

    /// The paired phone's APNs device token as lowercase hex, or nil when no
    /// device has registered.
    static var deviceTokenHex: String? {
        iTermUserDefaults.userDefaults().string(forKey: tokenKey)
    }

    /// The phone-minted relay secret as lowercase hex; presented to the push
    /// relay with each send so only the paired Mac can notify this phone. Reads
    /// the in-memory cache (loaded from the keychain at launch), never the
    /// keychain directly, so a background send cannot trigger a keychain prompt.
    static var relaySecretHex: String? {
        secretLock.lock()
        defer { secretLock.unlock() }
        return cachedSecretHex
    }

    /// Load the relay secret from the keychain into memory. Call once at launch,
    /// while the user is at the keyboard, so a keychain prompt (if the login
    /// keychain ever requires one) can be answered then; later background sends
    /// use the cache and never touch the keychain. Idempotent.
    static func loadSecretAtLaunch() {
        guard !didLoadSecret else { return }
        didLoadSecret = true
        let defaults = iTermUserDefaults.userDefaults()
        // Migrate a secret an older build kept in UserDefaults into the keychain,
        // then drop the plaintext copy regardless.
        if !defaults.bool(forKey: hasSecretKey),
           let legacyHex = defaults.string(forKey: legacySecretKey),
           let data = data(fromHex: legacyHex) {
            try? CompanionMacIdentity.storePairedPushSecret(data)
            defaults.set(true, forKey: hasSecretKey)
        }
        defaults.removeObject(forKey: legacySecretKey)
        guard defaults.bool(forKey: hasSecretKey),
              let data = CompanionMacIdentity.pairedPushSecret() else {
            return
        }
        let hex = data.hexEncodedString()
        secretLock.lock()
        cachedSecretHex = hex
        secretLock.unlock()
    }

    private static func data(fromHex hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let byte = UInt8(hex[i..<j], radix: 16) else { return nil }
            bytes.append(byte)
            i = j
        }
        return bytes
    }

    /// True when the token came from a development (sandbox) build, which
    /// must be sent through APNs' sandbox environment.
    static var sandbox: Bool {
        iTermUserDefaults.userDefaults().bool(forKey: sandboxKey)
    }

    /// The phone's notification-permission state as of its last report (the
    /// user can change it in iOS Settings between connections).
    static var authorization: CompanionPushAuthorization {
        guard let raw = iTermUserDefaults.userDefaults().string(forKey: authorizationKey),
              let value = CompanionPushAuthorization(rawValue: raw) else {
            return .notDetermined
        }
        return value
    }

    /// True when a notification could actually be delivered right now.
    static var canNotify: Bool {
        authorization == .authorized && deviceTokenHex != nil && relaySecretHex != nil
    }

    /// True when a companion device is paired, whether or not it is
    /// connected right now. Push-related prompt guidance keys off this so
    /// users without a companion device never see it.
    static var devicePaired: Bool {
        iTermUserDefaults.userDefaults()
            .string(forKey: CompanionPairingController.pairedPIDKey) != nil
    }

    /// The protocol revision the paired phone last advertised in its `.hello`
    /// (0 if never recorded: paired before this mac learned to store it, or paired
    /// long ago and not reconnected since the phone updated). Consulted at push
    /// time, when the phone may be offline, to choose the wakeup format and to gate
    /// the alert UI. Self-corrects on the next handshake.
    static var peerRevision: Int {
        iTermUserDefaults.userDefaults().integer(forKey: peerRevisionKey)
    }

    static func setPeerRevision(_ revision: Int) {
        iTermUserDefaults.userDefaults().set(revision, forKey: peerRevisionKey)
    }

    /// The paired phone understands the contentless wakeup + unified syncSince
    /// (revision >= 2). When false, the mac sends the legacy per-chat collapse push
    /// for chat and offers no terminal alerts.
    static var supportsContentlessWakeup: Bool {
        peerRevision >= CompanionProtocolVersion.contentlessWakeupRevision
    }

    /// Whether terminal alerts can actually be DELIVERED to the phone right now:
    /// paired, new enough, AND able to be notified (authorized + token + secret).
    /// The send path (CompanionAlertBridge.postTerminalAlert) gates on this.
    static var canSendAlertsToPhone: Bool {
        devicePaired && supportsContentlessWakeup && canNotify
    }

    /// Whether the desktop should OFFER the "send to phone" option: a revision-2
    /// phone is paired. Deliberately does NOT require canNotify - the user opting in
    /// is the immediate need that justifies asking iOS for notification permission,
    /// so the control is enabled without a push token and enabling it triggers the
    /// permission request (see CompanionPairingController.requestPushPermissionForAlerts).
    static var canEnableAlertsToPhone: Bool {
        devicePaired && supportsContentlessWakeup
    }

    /// Durable "the user has opted into phone alerts" flag, set the first time the
    /// user turns the setting on. The mac advertises it in every `.hello` reply so a
    /// connecting phone that hasn't yet been asked for notification permission knows
    /// to ask - on connect, not on fragile timing. NOT cleared when permission is
    /// decided (the phone gates re-asks on its own authorization) nor on unpair (the
    /// intent is device-global, so a freshly paired phone is still asked).
    static var alertsEverEnabled: Bool {
        iTermUserDefaults.userDefaults().bool(forKey: alertsEverEnabledKey)
    }

    static func setAlertsEverEnabled(_ value: Bool) {
        iTermUserDefaults.userDefaults().set(value, forKey: alertsEverEnabledKey)
    }

    /// Durable "the user has successfully paired a companion device at least once"
    /// flag, set the first time a pairing completes. The onboarding wizard is a
    /// first-run experience: once this is set, the menu opens today's Companion
    /// Device Settings window instead of the wizard. Like alertsEverEnabled this is
    /// device-global intent, so it is deliberately NOT cleared on unpair, a user who
    /// has paired before and then unpaired is experienced and gets the plain window.
    static var everPaired: Bool {
        iTermUserDefaults.userDefaults().bool(forKey: everPairedKey)
    }

    static func setEverPaired(_ value: Bool) {
        iTermUserDefaults.userDefaults().set(value, forKey: everPairedKey)
    }

    /// The push relay origin the current pairing registered its phone against,
    /// recorded ONLY when the pairing completed: that is the one moment we know
    /// the phone registered its APNs token against this same push relay. A
    /// reconnect does NOT refresh it (it proves nothing about push registration,
    /// see recordCurrentMainRelay). nil for a device paired before the mac tracked
    /// this; relayConfigurationChanged treats nil as "unknown, not moved", NOT as
    /// an old host.
    static var registeredPushRelayURL: String? {
        iTermUserDefaults.userDefaults().string(forKey: pushRelayURLKey)
    }

    /// The main (pairing/transport) relay origin this pairing was established
    /// against, recorded when the pairing completed AND refreshed on each
    /// successful reconnect (see recordCurrentMainRelay). nil for a device paired
    /// before the mac tracked this and not reconnected since, or for a pairing
    /// made with the relay disabled.
    static var registeredMainRelayOrigin: String? {
        iTermUserDefaults.userDefaults().string(forKey: mainRelayOriginKey)
    }

    /// Stamp both relays this pairing is reachable through. Called ONLY when a
    /// fresh pairing completes: pairing is the one point where the phone both
    /// registers its APNs token against the current push relay AND carries this
    /// connection over the current main relay, so both origins are evidenced.
    /// Recording them makes a later host move (see CompanionPushRelay and the
    /// CompanionRelayOrigin setting) detectable. A reconnect refreshes only the
    /// main relay (see recordCurrentMainRelay); it must not touch the push relay,
    /// which a reconnect does not evidence.
    static func recordCurrentRelays(pushRelayURL: String, mainRelayOrigin: String?) {
        iTermUserDefaults.userDefaults().set(pushRelayURL, forKey: pushRelayURLKey)
        recordCurrentMainRelay(mainRelayOrigin)
    }

    /// Refresh ONLY the recorded main relay origin, leaving the push relay alone.
    /// Called on each successful reconnect: the connection is carried over the main
    /// relay, so it proves the phone still reaches us there and backfills a pairing
    /// older than this tracking (nil) so a later main-relay move is detectable. It
    /// does NOT prove which push relay the phone's APNs token is registered against
    /// (the phone registers against its own build's push-relay URL, which after a
    /// mac-only upgrade differs from ours until the phone app is updated), so
    /// stamping the push URL on a reconnect would falsely satisfy
    /// relayConfigurationChanged and suppress a legitimate re-pair prompt.
    static func recordCurrentMainRelay(_ mainRelayOrigin: String?) {
        let defaults = iTermUserDefaults.userDefaults()
        if let mainRelayOrigin {
            defaults.set(mainRelayOrigin, forKey: mainRelayOriginKey)
        } else {
            defaults.removeObject(forKey: mainRelayOriginKey)
        }
    }

    /// True when asking for permission could possibly succeed: iOS only ever
    /// shows the prompt while the state is notDetermined; after a decline,
    /// only the Settings app can change it. Gating the request tool on this
    /// keeps the model from badgering a user who already said no.
    static var canPromptForPermission: Bool {
        phoneIsConnected && authorization == .notDetermined
    }

    // Whether a companion phone is connected right now. Mirrors the pairing
    // controller's bridge (main actor) behind a lock so the tool-registration
    // path, which is not actor-isolated, can read it.
    private static let connectionLock = NSLock()
    private static var connectionFlag = false

    static var phoneIsConnected: Bool {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return connectionFlag
    }

    static func setPhoneConnected(_ connected: Bool) {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        connectionFlag = connected
    }

    /// Whether the connected phone is an INTERACTIVE connection (a foreground app
    /// session), as opposed to the mac's own solicited NSE fetch (which also holds
    /// a live bridge). Used to gate turn-complete pushes: suppress for interactive
    /// (the user is looking), but NOT for a background NSE fetch. Mirrors the
    /// pairing controller's connectionPresence == .interactive.
    private static var interactiveFlag = false

    static var interactivePhoneConnected: Bool {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return interactiveFlag
    }

    static func setInteractivePhoneConnected(_ interactive: Bool) {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        interactiveFlag = interactive
    }

    /// Apply a pushStatus report from the phone.
    static func update(authorization: CompanionPushAuthorization,
                       token: Data?,
                       relaySecret: Data?,
                       sandbox: Bool) {
        let defaults = iTermUserDefaults.userDefaults()
        defaults.set(authorization.rawValue, forKey: authorizationKey)
        defaults.set(sandbox, forKey: sandboxKey)
        if let token {
            defaults.set(token.hexEncodedString(), forKey: tokenKey)
        }
        if let relaySecret {
            do {
                try CompanionMacIdentity.storePairedPushSecret(relaySecret)
                defaults.set(true, forKey: hasSecretKey)
                let hex = relaySecret.hexEncodedString()
                secretLock.lock()
                cachedSecretHex = hex
                secretLock.unlock()
            } catch {
                RLog("Companion push: failed to store relay secret in keychain: \(error)")
            }
        }
        RLog("Companion push: status \(authorization.rawValue), token \(token != nil ? "present" : "absent"), secret \(relaySecret != nil ? "present" : "absent"), sandbox \(sandbox); canNotify=\(canNotify)")
    }

    static func clear() {
        let defaults = iTermUserDefaults.userDefaults()
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: hasSecretKey)
        defaults.removeObject(forKey: legacySecretKey)
        defaults.removeObject(forKey: sandboxKey)
        defaults.removeObject(forKey: authorizationKey)
        defaults.removeObject(forKey: peerRevisionKey)
        defaults.removeObject(forKey: pushRelayURLKey)
        defaults.removeObject(forKey: mainRelayOriginKey)
        // alertsEverEnabled is intentionally NOT cleared: it is device-global user
        // intent, so a freshly paired phone is still asked for permission.
        CompanionMacIdentity.deletePairedPushSecret()
        secretLock.lock()
        cachedSecretHex = nil
        secretLock.unlock()
        RLog("Companion push: cleared device registration")
    }
}

//
//  CompanionMacIdentity.swift
//  iTerm2
//
//  The Mac's long-term Noise static identity for companion pairing. The public
//  key is what the phone pins (it travels in the QR code's rs field); the
//  private key is generated once and kept in the login keychain so the
//  advertised public key stays stable across launches.
//

import Foundation
import CompanionNoise

@objc(iTermCompanionMacIdentity)
final class CompanionMacIdentity: NSObject {
    private static let service = "com.googlecode.iterm2.companion"
    private static let account = "mac-noise-static-private-key"
    // The paired phone's static PUBLIC key, the reconnect authentication anchor.
    // Public, so not secret, but it lives in the keychain (not UserDefaults)
    // because its INTEGRITY is what matters: a tampered value would let an
    // impostor's static be accepted on reconnect. Kept beside the private key it
    // is matched against.
    private static let pairedPhoneAccount = "paired-phone-noise-static-public-key"
    // The room secret the phone couriered over the Noise channel. Secret (it
    // derives the relay join signing key), so the keychain is the right home.
    private static let roomSecretAccount = "paired-relay-room-secret"

    /// The persisted keypair, generating and storing one on first use. Reads the
    /// in-memory cache (primed at launch) so a reconnect never touches the
    /// keychain; only first-use generation writes.
    static func keyPair() throws -> NoiseKeyPair {
        if let privateKey = loadedData(account: account) {
            return try NoiseKeyPair.from(privateKey: privateKey)
        }
        let generated = try NoiseKeyPair.generate()
        try store(generated.privateKey, account: account)
        return generated
    }

    /// Whether a persisted identity key exists, WITHOUT generating one (unlike
    /// keyPair(), which mints and stores one on a miss). For a pairing-completeness
    /// check that must not create new key material for an unpaired / half-paired mac.
    static func hasKeyPair() -> Bool {
        loadedData(account: account) != nil
    }

    /// Destroy the stored identity (used when unpairing); the next pairing
    /// generates a fresh keypair.
    static func deleteKeyPair() {
        delete(account: account)
        // The identity keypair is the root of all pairing material: deleting it (at
        // unpair, or when the peer unpairs) tears the pairing down, so forget the
        // prime hint immediately. Any sibling item left behind is unusable without
        // this key, and the next launch's prime would clear the hint regardless.
        setKeychainMayHaveMaterial(false)
    }

    /// The paired phone's pinned static public key, or nil if none is pinned.
    static func pairedPhoneStaticPublicKey() -> Data? {
        loadedData(account: pairedPhoneAccount)
    }

    static func storePairedPhoneStaticPublicKey(_ key: Data) throws {
        try store(key, account: pairedPhoneAccount)
    }

    static func deletePairedPhoneStaticPublicKey() {
        delete(account: pairedPhoneAccount)
    }

    /// The room secret couriered from the phone (nil if none stored yet).
    static func pairedRoomSecret() -> Data? {
        loadedData(account: roomSecretAccount)
    }

    static func storePairedRoomSecret(_ secret: Data) throws {
        try store(secret, account: roomSecretAccount)
    }

    static func deletePairedRoomSecret() {
        delete(account: roomSecretAccount)
    }

    // The phone-minted push relay secret (32 bytes). It authorizes pushing to
    // the paired phone, so the keychain is the right home (not UserDefaults).
    private static let pushSecretAccount = "paired-push-relay-secret"

    static func pairedPushSecret() -> Data? {
        loadedData(account: pushSecretAccount)
    }

    static func storePairedPushSecret(_ secret: Data) throws {
        try store(secret, account: pushSecretAccount)
    }

    static func deletePairedPushSecret() {
        delete(account: pushSecretAccount)
    }

    // In-memory mirror of the keychain items, populated at launch and on every
    // write, so the connection and push hot paths never read the keychain. The
    // login keychain gates each item by the code signature of the binary that
    // wrote it; a build signed differently from the writer (e.g. a notarized
    // Nightly reading an item a local debug build created) pops a confirmation
    // prompt. Reading at launch, while the user is present, keeps that prompt off
    // the mid-connection path where nobody is at the keyboard. An inner nil
    // records “loaded and absent”, so a missing item is not re-read every call.
    private static let cacheLock = NSLock()
    private static var cache = [String: Data?]()

    // A NoSync hint, mirrored from the keychain, recording whether the companion
    // keychain currently holds pairing material worth priming at launch. The
    // keychain is the ground truth; this cache lets a never-paired install skip the
    // launch-time keychain touch (the identity reads AND the push-nonce write)
    // entirely, so it never plants a keychain item - and the code-signature
    // confirmation prompt that item causes across differently-signed builds - for a
    // feature it never enabled. NoSync: local device state, not a setting.
    private static let hasMaterialKey = "NoSyncCompanionKeychainHasMaterial"

    /// Whether the keychain is believed to hold companion pairing material, used by
    /// the launch path to decide whether to prime. Deliberately NOT used to gate an
    /// actual keychain read (those happen on demand regardless), so a stale-false
    /// value only defers priming; the next read that finds material corrects it.
    static var keychainMayHaveMaterial: Bool {
        iTermUserDefaults.userDefaults().bool(forKey: hasMaterialKey)
    }

    /// Reconcile the hint. Change-guarded so a repeated same-value write does not
    /// churn a settings write (a non-NoSync store would be re-uploaded).
    private static func setKeychainMayHaveMaterial(_ value: Bool) {
        let defaults = iTermUserDefaults.userDefaults()
        if defaults.bool(forKey: hasMaterialKey) != value {
            defaults.set(value, forKey: hasMaterialKey)
        }
    }

    /// Read every keychain-backed item into the cache. Call once at launch, while
    /// the user is at the keyboard, so any keychain confirmation prompt is
    /// answered then rather than mid-connection while the user is away. Idempotent
    /// (cached items are not re-read), and side-effect-free: it does not generate
    /// a Noise keypair, so an unpaired user gets no new key material.
    ///
    /// Returns whether any account held material, and reconciles the persisted
    /// hint from this ground-truth read: true if any account is found, false if
    /// EVERY account reads back a genuine absent. A transient unreadable (a locked
    /// keychain, a denied confirmation prompt) leaves the hint untouched, so it can
    /// never wrongly clear a real pairing's hint.
    @discardableResult
    static func primeCacheAtLaunch() -> Bool {
        let reads = [account, pairedPhoneAccount, roomSecretAccount, pushSecretAccount]
            .map { load(account: $0) }
        let anyFound = reads.contains { if case .found = $0 { return true } else { return false } }
        let anyUnreadable = reads.contains { if case .unreadable = $0 { return true } else { return false } }
        if anyFound {
            setKeychainMayHaveMaterial(true)
        } else if !anyUnreadable {
            setKeychainMayHaveMaterial(false)
        }
        return anyFound
    }

    private static func load(account: String) -> KeychainRead {
        cacheLock.lock()
        if let cached = cache[account] {
            cacheLock.unlock()
            return cached.map { KeychainRead.found($0) } ?? .absent
        }
        cacheLock.unlock()
        // The keychain read runs unlocked so a confirmation prompt can't block
        // other accounts behind the lock. A concurrent store/delete may therefore
        // populate the cache while this read is in flight; that value is fresher,
        // so on writeback only fill a still-absent entry rather than clobbering it.
        let result = keychainLoad(account: account)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[account] {
            return cached.map { KeychainRead.found($0) } ?? .absent
        }
        switch result {
        case .found(let data):
            cache.updateValue(data, forKey: account)
        case .absent:
            cache.updateValue(nil, forKey: account)
        case .unreadable:
            // Do NOT cache a transient failure. The cache persists for the process
            // lifetime, so caching one denied/locked read would make the item look
            // absent for good, wedging resume and spamming the re-pair prompt. Leave
            // it uncached so the next call re-reads once the keychain is available.
            break
        }
        return result
    }

    /// The item's bytes if present and valid, else nil (absent OR unreadable). Hot
    /// paths that only need the data use this: a transient failure reads as nil
    /// exactly as before, so signing / connect behavior is unchanged. Only the
    /// pairing-completeness check needs the finer absent-vs-unreadable distinction.
    private static func loadedData(account: String) -> Data? {
        if case .found(let data) = load(account: account) {
            return data
        }
        return nil
    }

    /// A pairing item whose GENUINE absence should mark the pairing incomplete. The
    /// room secret is deliberately absent from this enum: the phone re-couriers it
    /// on every connect, so a missing/unreadable one self-heals and must not block
    /// resume or trigger a re-pair prompt.
    enum RequiredPairingItem {
        case identityKey
        case pairedPhoneKey
    }

    /// True only when the item is genuinely absent (errSecItemNotFound). A present
    /// item, or one merely unreadable right now (a transient access failure),
    /// returns false, so a rebuilt or locked keychain does not report the pairing
    /// permanently incomplete.
    static func isGenuinelyAbsent(_ item: RequiredPairingItem) -> Bool {
        let acct: String
        switch item {
        case .identityKey: acct = account
        case .pairedPhoneKey: acct = pairedPhoneAccount
        }
        if case .absent = load(account: acct) {
            return true
        }
        return false
    }

    private static func store(_ key: Data, account: String) throws {
        try keychainStore(key, account: account)
        cacheLock.lock()
        cache.updateValue(key, forKey: account)
        cacheLock.unlock()
        // Material now exists (a keypair, the paired phone key, a room or push
        // secret), so the next launch should prime rather than skip.
        setKeychainMayHaveMaterial(true)
    }

    private static func delete(account: String) {
        keychainDelete(account: account)
        cacheLock.lock()
        cache.updateValue(nil, forKey: account)
        cacheLock.unlock()
    }

    // When -suite is given the app runs against a separate settings suite, so a
    // second build can run beside the released one. Namespace the keychain items
    // by suite too, so the two don't share or clobber each other's companion
    // identity. Without -suite the account is the bare name, preserving items
    // already written by released builds.
    private static func suitedAccount(_ account: String) -> String {
        guard let suite = iTermUserDefaults.customSuiteName() as String?, !suite.isEmpty else {
            return account
        }
        return "\(account).\(suite)"
    }

    /// Tri-state keychain read. `.found` carries the valid 32-byte item; `.absent`
    /// is a genuine errSecItemNotFound; `.unreadable` is anything else (a real
    /// access error, or a success-but-malformed item) where the item likely EXISTS
    /// but cannot be used right now. The distinction is what P5 turns on: only a
    /// genuine `.absent` may mark the pairing incomplete; a transient `.unreadable`
    /// (a denied keychain confirmation prompt at launch, a locked keychain) must
    /// not, or the pairing looks permanently broken and spams the re-pair modal.
    enum KeychainRead: Equatable {
        case found(Data)
        case absent
        case unreadable(OSStatus)
    }

    /// Pure interpretation of a SecItemCopyMatching result, split out so the
    /// absent-vs-unreadable distinction is unit-testable without a live keychain.
    static func interpretKeychainStatus(_ status: OSStatus, data: Data?) -> KeychainRead {
        if status == errSecSuccess {
            if let data, data.count == 32 {
                return .found(data)
            }
            // Present but malformed: the item exists yet is unusable. Not absent.
            return .unreadable(status)
        }
        if status == errSecItemNotFound {
            return .absent
        }
        return .unreadable(status)
    }

    private static func keychainLoad(account: String) -> KeychainRead {
        // Read from the data-protection keychain (entitlement-gated, so upgrades
        // don't re-prompt), transparently migrating any value a pre-migration build
        // wrote to the login keychain. The item stays this-device-only, matching how
        // it was written before.
        let (status, data) = iTermUpgradeSafeKeychain.copyGenericPassword(
            service: service,
            account: suitedAccount(account),
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        let result = interpretKeychainStatus(status, data: data)
        switch result {
        case .found:
            break
        case .absent:
            // Genuinely absent (never stored under this account, or deleted). Normal
            // for an unpaired item; for the room secret it means the mac parks
            // open-mode and the relay refuses. RLog (not DLog) so the absent-vs-denied
            // distinction is captured even with debug logging off. Note the account is
            // suite-namespaced: `make run` launches with `-suite <dir>`, so a pairing
            // stored by a differently-suited (or released) build lives under a
            // different account and reads as not-found here.
            RLog("Companion keychain: '\(suitedAccount(account))' not found (absent, not access-denied)")
        case .unreadable(let osStatus) where osStatus == errSecSuccess:
            RLog("Companion keychain: '\(suitedAccount(account))' present but malformed (\(data?.count ?? -1) bytes)")
        case .unreadable(let osStatus):
            // A real error (errSecAuthFailed / errSecInteractionNotAllowed / a denied
            // confirmation prompt): the item likely EXISTS but this binary's code
            // signature differs from the writer's, so the login keychain refuses it.
            // For the relay room secret this makes the mac park unsigned and the relay
            // refuse admission ("signature required"). Re-pair (or grant the keychain
            // prompt) to recover. RLog so it is captured without debug logging on.
            let message = (SecCopyErrorMessageString(osStatus, nil) as String?) ?? "unknown"
            RLog("Companion keychain: FAILED to read '\(suitedAccount(account))': OSStatus \(osStatus) (\(message)). A code-signature mismatch (e.g. a rebuilt app) denies access; this breaks relay park signing.")
        }
        return result
    }

    private static func keychainStore(_ key: Data, account: String) throws {
        let status = iTermUpgradeSafeKeychain.setGenericPassword(
            key,
            service: service,
            account: suitedAccount(account),
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        guard status == errSecSuccess else {
            throw CompanionMacError.keychain(status)
        }
    }

    private static func keychainDelete(account: String) {
        iTermUpgradeSafeKeychain.deleteGenericPassword(service: service,
                                                       account: suitedAccount(account))
    }
}

enum CompanionMacError: Error, CustomStringConvertible {
    case keychain(OSStatus)
    case chatSystemUnavailable
    case unknownChat(String)

    var description: String {
        switch self {
        case .keychain(let status):
            return "Keychain error \(status)"
        case .chatSystemUnavailable:
            return "The chat system is not available"
        case .unknownChat(let id):
            return "Unknown chat \(id)"
        }
    }
}

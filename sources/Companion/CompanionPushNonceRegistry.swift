//
//  CompanionPushNonceRegistry.swift
//  iTerm2
//
//  One-time nonces the mac places in outbound mutable pushes, so a relay
//  connection that echoes a still-outstanding nonce can be recognized as the
//  mac's OWN solicited NSE fetch and not warned about (the connect/disconnect
//  toast). The nonce reaches the phone sealed in the push payload
//  (CompanionPushNonceCrypto); only the phone (which holds the room secret)
//  opens it. An attacker with stolen Noise credentials never receives the push,
//  so it cannot present a valid nonce and any connection it makes is surfaced.
//
//  Persisted in the KEYCHAIN: a nonce is a secret capability (knowing one, plus
//  the Noise key, suppresses the intrusion warning), so it is kept encrypted at
//  rest rather than in UserDefaults, and it survives a mac restart so an
//  APNs-delayed push still matches after one.
//
//  Expiry is by CAPACITY, not time. APNs may delay a push arbitrarily, so a
//  time-based TTL would wrongly drop a delayed push's nonce and false-alarm on
//  the mac's own late fetch. Holding a nonce indefinitely has no security cost:
//  only the push recipient (the phone) ever holds it, so it never weakens with
//  age. The capacity bound is purely a memory runaway guard.
//
//  @MainActor: both the producer (CompanionAgentActivityNotifier) and the
//  consumer (CompanionHostBridge) run on the main actor, so no locking is needed.
//

import Foundation
import Security
import CompanionProtocol

/// Persistence seam for the outstanding-nonce list (injected so tests are
/// keychain-free). The list is the live nonces in insertion order. Only ever
/// touched from the registry's main actor.
protocol CompanionNonceStore {
    func load() -> [String]
    func save(_ nonces: [String])
}

@MainActor
final class CompanionPushNonceRegistry {
    static let shared = CompanionPushNonceRegistry()

    private var order: [String]              // live nonces, oldest first
    private var live: Set<String>
    private let capacity: Int
    private let makeRandom: () -> String
    private let store: CompanionNonceStore

    /// Recently CONSUMED nonces, kept only for classification (not re-serving):
    /// APNs can deliver the same push twice, and the second NSE fetch echoes the
    /// same nonce after the first already consumed it. Without this, that
    /// duplicate would be classified interactive and warn the user about their own
    /// fetch. Bounded + in-memory (a duplicate after a mac restart - rare - simply
    /// warns), oldest first.
    private var recentlyConsumedOrder: [String] = []
    private var recentlyConsumed: Set<String> = []
    private let recentlyConsumedCapacity = 256

    /// - capacity: how many recent nonces to retain. Generous so an APNs-delayed
    ///   push still matches; bounded so the set can never grow without limit.
    init(capacity: Int = 1024,
         makeRandom: @escaping () -> String = { CompanionPushNonceRegistry.randomHex(16) },
         store: CompanionNonceStore = KeychainNonceStore()) {
        self.capacity = max(capacity, 1)
        self.makeRandom = makeRandom
        self.store = store
        let loaded = Array(store.load().suffix(self.capacity))
        self.order = loaded
        self.live = Set(loaded)
    }

    /// A fresh nonce VALUE, without recording it. The caller records it (below)
    /// only after the push that carries it is successfully sealed and sent, so a
    /// failed seal/send doesn't burn a capacity slot on a nonce no push delivered.
    func mintNonce() -> String {
        makeRandom()
    }

    /// Record a minted nonce as outstanding (persisted). Call after the push that
    /// carries it has actually been sent.
    func record(_ nonce: String) {
        order.append(nonce)
        live.insert(nonce)
        if order.count > capacity {
            let evicted = order.removeFirst()
            live.remove(evicted)
        }
        store.save(order)
    }

    /// Mint and record in one step (generate, record, persist, return). Prefer
    /// mintNonce() + record() when the push send can fail.
    func makeNonce() -> String {
        let nonce = mintNonce()
        record(nonce)
        return nonce
    }

    /// Touch the keychain at launch, while the user is present, so the push hot
    /// path never does. Simply CONSTRUCTING `shared` reads the persisted list
    /// (init -> store.load()); call this at launch so that read does not happen
    /// later inside dispatchPush() while the user is away. It also REWRITES the
    /// list so the item is owned by the current binary, so the record()/consume()
    /// saves on the push and fetch paths - and any code-signature confirmation
    /// prompt after a rebuild - are answered now rather than mid-send. Idempotent.
    func primeAtLaunch() {
        store.save(order)
    }

    /// Undo a record() when the push that would have carried the nonce failed to
    /// send. Removes it from the live set (persisted); it was never delivered, so
    /// nothing will echo it, and the capacity slot is freed. No-op if absent (e.g.
    /// already evicted). Used by the record-before-send ordering so a nonce that
    /// rides out in a push is recorded BEFORE the send completes (closing the
    /// suspend-between-send-and-record window that would misclassify the mac's own
    /// fetch as unsolicited), while a genuinely failed send still doesn't keep a
    /// slot.
    func unrecord(_ nonce: String) {
        guard live.remove(nonce) != nil else { return }
        if let index = order.firstIndex(of: nonce) {
            order.remove(at: index)
        }
        store.save(order)
    }

    /// Whether a nonce is recognizable as the mac's OWN, WITHOUT consuming it.
    /// True for an outstanding nonce OR a recently-consumed one (a duplicate APNs
    /// delivery of the same push). Used only to classify a connection as solicited
    /// (so a peek/retry, or a duplicate, still skips the presence warning).
    func contains(_ nonce: String) -> Bool {
        live.contains(nonce) || recentlyConsumed.contains(nonce)
    }

    /// Consume a nonce echoed by a connection; true iff it was still outstanding.
    /// Single-use for SERVING: a matched nonce moves out of the live set (change
    /// persisted) into the bounded recently-consumed set, so it can no longer be
    /// re-served but a duplicate delivery is still classified as solicited.
    func consume(_ nonce: String) -> Bool {
        guard live.remove(nonce) != nil else { return false }
        if let index = order.firstIndex(of: nonce) {
            order.remove(at: index)
        }
        rememberConsumed(nonce)
        store.save(order)
        return true
    }

    private func rememberConsumed(_ nonce: String) {
        guard !recentlyConsumed.contains(nonce) else { return }
        recentlyConsumedOrder.append(nonce)
        recentlyConsumed.insert(nonce)
        if recentlyConsumedOrder.count > recentlyConsumedCapacity {
            let evicted = recentlyConsumedOrder.removeFirst()
            recentlyConsumed.remove(evicted)
        }
    }

    /// 128-bit random hex. The nonce is a security capability (it lets the mac
    /// recognize its own solicited fetch), so a silent RNG failure that left the
    /// buffer all-zeros would ship a predictable nonce; fail loudly instead.
    nonisolated static func randomHex(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!)
        }
        if status != errSecSuccess {
            it_fatalError("SecRandomCopyBytes failed (\(status)); refusing to use a predictable nonce")
        }
        return data.hexEncodedString()
    }
}

/// Keychain-backed store: the nonce list as a JSON array in one generic-password
/// item (this-device-only), beside the other companion mac keychain items.
final class KeychainNonceStore: CompanionNonceStore {
    private let service = "com.googlecode.iterm2.companion"
    private let baseAccount = "push-nonce-registry"

    // Namespace the keychain account by the -suite name when the app runs against a
    // custom settings suite (a side-by-side dev build, e.g. `make run` launches with
    // -suite), so two differently-suited instances get their OWN outstanding-nonce
    // lists instead of sharing one item and clobbering each other's on save (a
    // last-writer-wins overwrite that silently drops the other pairing's nonces, so
    // its next solicited fetch is misclassified as an intrusion). Without -suite
    // (every shipping build) this returns the bare name, so production items already
    // written under it are found unchanged. Mirrors CompanionMacIdentity.suitedAccount.
    private var account: String {
        guard let suite = iTermUserDefaults.customSuiteName() as String?, !suite.isEmpty else {
            return baseAccount
        }
        return "\(baseAccount).\(suite)"
    }

    func load() -> [String] {
        // Data-protection keychain (entitlement-gated, upgrade-silent), migrating a
        // pre-migration login-keychain copy forward on first read.
        let (status, item) = iTermUpgradeSafeKeychain.copyGenericPassword(
            service: service,
            account: account,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        // errSecItemNotFound is normal (first run / after a reset); anything else
        // is a real failure that silently disables cross-restart nonce
        // suppression, so log it for diagnosis.
        if status != errSecSuccess && status != errSecItemNotFound {
            RLog("CompanionPushNonceRegistry: keychain load failed (\(status))")
        }
        guard status == errSecSuccess,
              let data = item,
              let nonces = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return nonces
    }

    func save(_ nonces: [String]) {
        guard let data = try? JSONEncoder().encode(nonces) else { return }
        let addStatus = iTermUpgradeSafeKeychain.setGenericPassword(
            data,
            service: service,
            account: account,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        // A persistent add failure means nonces don't survive a restart, so a
        // post-relaunch fetch is misclassified as unsolicited (spurious presence
        // warning) with no other clue; surface it.
        if addStatus != errSecSuccess {
            RLog("CompanionPushNonceRegistry: keychain add failed (\(addStatus)); nonce won't survive restart")
        }
    }
}

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

    /// Generate, record, persist, and return a fresh nonce to place in a push.
    func makeNonce() -> String {
        let nonce = makeRandom()
        order.append(nonce)
        live.insert(nonce)
        if order.count > capacity {
            let evicted = order.removeFirst()
            live.remove(evicted)
        }
        store.save(order)
        return nonce
    }

    /// Consume a nonce echoed by a connection; true iff it was still outstanding.
    /// Single-use: a matched nonce is removed (and the change persisted) so it
    /// cannot be replayed, even across a restart.
    func consume(_ nonce: String) -> Bool {
        guard live.remove(nonce) != nil else { return false }
        if let index = order.firstIndex(of: nonce) {
            order.remove(at: index)
        }
        store.save(order)
        return true
    }

    /// 128-bit random hex.
    nonisolated static func randomHex(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!)
        }
        return data.map { String(format: "%02x", $0) }.joined()
    }
}

/// Keychain-backed store: the nonce list as a JSON array in one generic-password
/// item (this-device-only), beside the other companion mac keychain items.
final class KeychainNonceStore: CompanionNonceStore {
    private let service = "com.googlecode.iterm2.companion"
    private let account = "push-nonce-registry"

    func load() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let nonces = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return nonces
    }

    func save(_ nonces: [String]) {
        guard let data = try? JSONEncoder().encode(nonces) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(base as CFDictionary)
        SecItemAdd(add as CFDictionary, nil)
    }
}

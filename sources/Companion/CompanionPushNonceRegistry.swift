//
//  CompanionPushNonceRegistry.swift
//  iTerm2
//
//  One-time nonces the mac places in outbound mutable pushes, so a relay
//  connection that echoes a still-outstanding nonce can be recognized as the
//  mac's OWN solicited NSE fetch and not warned about (the connect/disconnect
//  toast). The nonce exists ONLY in the push delivered to the paired phone via
//  APNs: an attacker with stolen Noise credentials never receives the push, so
//  it cannot present a valid nonce and any connection it makes is surfaced. The
//  relay/Apple see the nonce but lack the Noise key, so they cannot connect at
//  all. Only the real phone has both. See docs/push.txt.
//
//  Expiry is by CAPACITY, not time. APNs may delay a push arbitrarily (minutes,
//  hours, or until the device is next reachable), so a time-based TTL would
//  wrongly drop a legitimately-delayed push's nonce and false-alarm on the mac's
//  own late fetch. There is no security cost to holding a nonce indefinitely: it
//  is a one-time capability only the push recipient (the phone) ever has, so it
//  never weakens with age and an attacker never holds it. The capacity bound is
//  purely memory hygiene / a runaway guard; a delayed push still matches unless
//  an implausible number of newer pushes were issued in the meantime.
//
//  @MainActor: both the producer (CompanionAgentActivityNotifier) and the
//  consumer (CompanionHostBridge) run on the main actor, so no locking is
//  needed. The RNG is injected so capacity/single-use are testable.
//

import Foundation
import Security

@MainActor
final class CompanionPushNonceRegistry {
    static let shared = CompanionPushNonceRegistry()

    // Insertion order (FIFO eviction) + a set for O(1) lookup. Consumed nonces
    // are removed from `live` but stay in `order` as tombstones until evicted, so
    // `order.count` stays bounded by `capacity`.
    private var order: [String] = []
    private var live: Set<String> = []
    private let capacity: Int
    private let makeRandom: () -> String

    /// - capacity: how many recent nonces to retain. Generous so an APNs-delayed
    ///   push still matches; bounded so the set can never grow without limit.
    init(capacity: Int = 1024,
         makeRandom: @escaping () -> String = { CompanionPushNonceRegistry.randomHex(16) }) {
        self.capacity = max(capacity, 1)
        self.makeRandom = makeRandom
    }

    /// Generate, record, and return a fresh nonce to place in a push.
    func makeNonce() -> String {
        let nonce = makeRandom()
        order.append(nonce)
        live.insert(nonce)
        if order.count > capacity {
            let evicted = order.removeFirst()
            live.remove(evicted)   // no-op if it was already consumed
        }
        return nonce
    }

    /// Consume a nonce echoed by a connection; true iff it was still outstanding.
    /// Single-use: a matched nonce is removed so it cannot be replayed (its slot
    /// in `order` is left as a tombstone, reclaimed by FIFO eviction).
    func consume(_ nonce: String) -> Bool {
        return live.remove(nonce) != nil
    }

    /// 128-bit random hex, matching the collapse-token shape the wire already
    /// carries (so the relay's hex validation accepts it).
    nonisolated static func randomHex(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!)
        }
        return data.map { String(format: "%02x", $0) }.joined()
    }
}

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
//  @MainActor: both the producer (CompanionAgentActivityNotifier) and the
//  consumer (CompanionHostBridge) run on the main actor, so no locking is
//  needed. The clock and RNG are injected so expiry/single-use are testable.
//

import Foundation
import Security

@MainActor
final class CompanionPushNonceRegistry {
    static let shared = CompanionPushNonceRegistry()

    private var outstanding: [String: Date] = [:]
    private let ttl: TimeInterval
    private let now: () -> Date
    private let makeRandom: () -> String

    /// - ttl: a push-driven fetch arrives within seconds; expire generously but
    ///   bounded so a never-answered push cannot leak a usable nonce for long.
    init(ttl: TimeInterval = 120,
         now: @escaping () -> Date = { Date() },
         makeRandom: @escaping () -> String = { CompanionPushNonceRegistry.randomHex(16) }) {
        self.ttl = ttl
        self.now = now
        self.makeRandom = makeRandom
    }

    /// Generate, record, and return a fresh nonce to place in a push.
    func makeNonce() -> String {
        prune()
        let nonce = makeRandom()
        outstanding[nonce] = now()
        return nonce
    }

    /// Consume a nonce echoed by a connection; true iff it was outstanding and
    /// unexpired. Single-use: a matched nonce is removed so it cannot be replayed.
    func consume(_ nonce: String) -> Bool {
        prune()
        return outstanding.removeValue(forKey: nonce) != nil
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-ttl)
        outstanding = outstanding.filter { $0.value >= cutoff }
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

//
//  PairingSAS.swift
//  CompanionCore
//
//  The Short Authentication String shown during pairing. Both ends derive it
//  from the Noise handshake hash (the channel-binding value, which commits to
//  both static keys and the prologue), so they agree only if they handshook
//  with each other and no one is interposed. The phone displays it; the user
//  types it into the Mac, which compares against its own. See
//  docs/companion-relay-design.md.
//

import Foundation
import CryptoKit

public enum PairingSAS {
    /// HKDF label domain-separating the SAS from other uses of the handshake
    /// hash.
    private static let label = "iterm2-sas-v1"

    /// Number of decimal digits shown to the user.
    public static let digits = 6

    /// Derive the SAS from the Noise handshake hash. Returns a zero-padded
    /// 6-digit decimal string.
    public static func code(handshakeHash: Data) -> String {
        // HKDF compresses the (32-byte) handshake hash down to exactly 8
        // output bytes; `derived` is those 8 bytes, not the input. Reading 8
        // bytes big-endian fills a UInt64 precisely (8 * 8 = 64 bits), so the
        // shift-and-OR below assembles them without truncation.
        let outputByteCount = MemoryLayout<UInt64>.size  // 8; keep tied to UInt64
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: handshakeHash),
            info: Data(label.utf8),
            outputByteCount: outputByteCount)
        let value = derived.withUnsafeBytes { raw in
            raw.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        let modulus = UInt64(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)u", value % modulus)
    }
}

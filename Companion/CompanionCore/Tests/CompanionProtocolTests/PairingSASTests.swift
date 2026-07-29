//
//  PairingSASTests.swift
//  CompanionCore
//
//  The Short Authentication String the user compares to confirm pairing. It is
//  derived from the Noise handshake hash (which commits to both static keys),
//  so the two ends produce the same digits only if no one is interposed. See
//  docs/companion-relay-design.md.
//

import XCTest
import CryptoKit
@testable import CompanionProtocol

final class PairingSASTests: XCTestCase {
    private let h0 = Data(repeating: 0x77, count: 32)

    func test_isSixDigits() {
        let sas = PairingSAS.code(handshakeHash: h0)
        XCTAssertEqual(sas.count, 6)
        XCTAssertTrue(sas.allSatisfy { $0.isNumber })
    }

    func test_isDeterministic() {
        XCTAssertEqual(PairingSAS.code(handshakeHash: h0),
                       PairingSAS.code(handshakeHash: h0))
    }

    func test_differentHashGivesDifferentCode() {
        var other = h0; other[0] ^= 0x01
        XCTAssertNotEqual(PairingSAS.code(handshakeHash: h0),
                          PairingSAS.code(handshakeHash: other))
    }

    func test_matchesKDFVector() {
        // SAS = first 8 bytes of HKDF(hash, "iterm2-sas-v1") as big-endian
        // UInt64, mod 1_000_000, zero-padded to 6 digits.
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: h0),
            info: Data("iterm2-sas-v1".utf8),
            outputByteCount: 8)
        let bytes = derived.withUnsafeBytes { Data($0) }
        let value = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let expected = String(format: "%06u", value % 1_000_000)
        XCTAssertEqual(PairingSAS.code(handshakeHash: h0), expected)
    }

    func test_leadingZerosPreserved() {
        // Search for a hash whose SAS starts with 0, to prove zero-padding.
        for i in 0..<5000 {
            let h = Data((0..<32).map { _ in UInt8(i & 0xFF) }) + Data([UInt8(i & 0xFF), UInt8((i >> 8) & 0xFF)])
            let sas = PairingSAS.code(handshakeHash: h)
            if sas.hasPrefix("0") {
                XCTAssertEqual(sas.count, 6)
                return
            }
        }
        XCTFail("expected to find a SAS with a leading zero within the search budget")
    }
}

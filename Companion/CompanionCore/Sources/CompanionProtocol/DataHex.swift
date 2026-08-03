//
//  DataHex.swift
//  CompanionCore
//
//  One lowercase hex encoder for Data, shared by the companion code (the Mac app
//  and the iOS companion both link CompanionProtocol). The
//  `map { String(format: "%02x", $0) }.joined()` idiom was re-derived at several
//  sites (collapse tokens, push nonces, the push registry, pairing); this
//  centralizes it.
//

import Foundation

public extension Data {
    /// Lowercase hex, two characters per byte (e.g. Data([0x0a, 0xff]) -> "0aff").
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

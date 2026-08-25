//
//  KittyDnDMachineID.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  The machine id lets a peer detect the cross-machine (SSH) case without
//  disclosing its raw hardware identity: the base id is HMAC-SHA256 hashed with
//  a fixed protocol key and sent as "1:<hex>". If the peer's id differs from
//  ours, the drag/drop crosses machines and the byte-transfer path is used.
//

import Foundation
import CryptoKit
import IOKit

enum KittyDnDMachineID {
    /// Fixed HMAC key mandated by the protocol.
    static let hmacKey = "tty-dnd-protocol-machine-id"

    /// The hashed id of the machine we are running on, derived from the hardware
    /// platform UUID. Falls back to a fixed string if the UUID is unavailable
    /// (only affects local-vs-remote detection, which then defaults to local).
    static func localHashed() -> String {
        return hashed(localBaseID() ?? "unknown-machine")
    }

    private static func localBaseID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }
        let property = IORegistryEntryCreateCFProperty(service,
                                                       "IOPlatformUUID" as CFString,
                                                       kCFAllocatorDefault, 0)
        return property?.takeRetainedValue() as? String
    }

    /// Hash a base machine id into the wire form "1:<lowercase hex>".
    static func hashed(_ baseID: String) -> String {
        let key = SymmetricKey(data: Data(hmacKey.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(baseID.utf8), using: key)
        let hex = code.map { String(format: "%02x", $0) }.joined()
        return "1:\(hex)"
    }

    /// Whether a peer that reported `theirID` is on a different machine than us.
    /// A nil or empty peer id means the peer did not report one, so we cannot
    /// conclude it is remote and default to local.
    static func isRemote(theirID: String?, ourID: String) -> Bool {
        guard let theirID, !theirID.isEmpty else {
            return false
        }
        return theirID != ourID
    }
}

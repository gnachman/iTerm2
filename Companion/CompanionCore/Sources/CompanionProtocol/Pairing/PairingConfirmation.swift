//
//  PairingConfirmation.swift
//  CompanionCore
//
//  The mac's verdict on a fresh pairing, sent as the FIRST frame over the
//  newly established encrypted channel, before any RPC traffic. The phone
//  shows the SAS code (derived from the handshake hash, see PairingSAS) and
//  waits for this frame; the mac sends .accepted only after its user typed the
//  matching code. This is what defeats a photographed QR: an attacker who
//  pairs with a stolen QR never sees the victim's mac, so the victim cannot be
//  tricked into typing the attacker's code.
//
//  Reconnects to an established pairing skip confirmation entirely; both ends
//  know which case they are in (the phone from its stored pairing, the mac
//  from its persisted pairing id), so this frame is exchanged only on fresh
//  pairings and never collides with RPC frames.
//

import Foundation

public enum PairingConfirmation: Equatable, Sendable {
    case accepted
    case rejected

    private static let key = "pairing"

    public func encoded() -> Data {
        let value = self == .accepted ? "accepted" : "rejected"
        return Data("{\"\(Self.key)\":\"\(value)\"}".utf8)
    }

    /// Strict: anything but the two exact verdicts is nil, so a garbled or
    /// unexpected first frame reads as "not confirmed", never as acceptance.
    public static func decode(_ data: Data) -> PairingConfirmation? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let value = dictionary[key] as? String else {
            return nil
        }
        switch value {
        case "accepted": return .accepted
        case "rejected": return .rejected
        default: return nil
        }
    }
}

//
//  RelayRoom.swift
//  CompanionCore
//
//  The relay room pseudonym. Both devices derive it identically from the
//  responder static key (rs, delivered out of band by the QR) and the pairing
//  id, so it is unguessable to anyone who has not scanned the code, yet needs
//  no coordination. It is the rendezvous address the Cloudflare Durable Object
//  is keyed by. See docs/companion-relay-design.md.
//

import Foundation
import CryptoKit

public enum RelayRoom {
    /// Domain-separation label, versioned so this hash can never collide with
    /// any other use of rs/pid.
    private static let label = "iterm2-room-v1"

    /// roomName = SHA256(label || rs || pid), lowercase hex. Passed to the
    /// relay in a request header (never the URL path, to keep the pseudonym
    /// out of edge logs).
    public static func name(responderStaticPublicKey rs: Data, pairingID: String) -> String {
        var preimage = Data(label.utf8)
        preimage.append(rs)
        preimage.append(Data(pairingID.utf8))
        return SHA256.hash(data: preimage)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

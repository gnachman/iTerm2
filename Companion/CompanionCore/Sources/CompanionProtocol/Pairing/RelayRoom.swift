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
    /// roomName = SHA256(canonical("iterm2-room", [rs, pid])), lowercase hex.
    /// The length-prefixed, domain-separated encoding makes the rs/pid boundary
    /// unambiguous and keeps this hash from colliding with any other use of
    /// rs/pid. Passed to the relay in a request header (never the URL path, to
    /// keep the pseudonym out of edge logs).
    public static func name(responderStaticPublicKey rs: Data, pairingID: String) -> String {
        let preimage = CanonicalEncoding.encode(domain: "iterm2-room",
                                                [rs, Data(pairingID.utf8)])
        return SHA256.hash(data: preimage)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

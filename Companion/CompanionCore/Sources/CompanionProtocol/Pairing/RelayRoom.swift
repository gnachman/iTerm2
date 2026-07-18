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
    /// The raw SHA256 digest (32 bytes) both the room name and the shard bucket
    /// are derived from. Kept private so the two derivations share one hash and
    /// can never disagree on the preimage.
    private static func digest(responderStaticPublicKey rs: Data, pairingID: String) -> [UInt8] {
        let preimage = CanonicalEncoding.encode(domain: "iterm2-room",
                                                [rs, Data(pairingID.utf8)])
        return Array(SHA256.hash(data: preimage))
    }

    /// roomName = SHA256(canonical("iterm2-room", [rs, pid])), lowercase hex.
    /// The length-prefixed, domain-separated encoding makes the rs/pid boundary
    /// unambiguous and keeps this hash from colliding with any other use of
    /// rs/pid. Passed to the relay in a request header (never the URL path, to
    /// keep the pseudonym out of edge logs).
    public static func name(responderStaticPublicKey rs: Data, pairingID: String) -> String {
        digest(responderStaticPublicKey: rs, pairingID: pairingID)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// The shard bucket for a pairing: the last two bytes of the room-name digest
    /// taken big-endian, i.e. `digest[30] << 8 | digest[31]`, in `[0, 65535]`.
    /// N_BUCKETS is 2^16 (ShardMap.expectedBuckets), so this is exactly the low
    /// 16 bits of the digest, uniformly distributed with no modulo bias. The Node
    /// relay MUST extract the identical value byte-for-byte (Appendix A invariant
    /// 1); RoomBucketVectors pins it on both sides.
    public static func bucket(responderStaticPublicKey rs: Data, pairingID: String) -> Int {
        let bytes = digest(responderStaticPublicKey: rs, pairingID: pairingID)
        return Int(bytes[30]) << 8 | Int(bytes[31])
    }

    /// The shard bucket from an already-computed room name (the 64-char lowercase
    /// hex `x-relay-room` header): the numeric value of its last four hex
    /// characters, which are exactly digest bytes 30 and 31 big-endian. Returns
    /// nil if the string is not 64 hex characters. Lets a holder of the header
    /// (e.g. the relay) derive the bucket without the rs/pid or re-hashing.
    public static func bucket(forRoomName roomName: String) -> Int? {
        guard roomName.count == 64, roomName.allSatisfy(\.isHexDigit) else { return nil }
        return Int(roomName.suffix(4), radix: 16)
    }
}

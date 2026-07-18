//
//  RoomBucketVectors.swift
//  CompanionCore
//
//  THE canonical cross-language vector for the roomName and shard-bucket
//  derivation. The Swift side (RelayRoom) is checked against it in
//  RoomBucketTests; the Node relay MUST reproduce every `room_name` and `bucket`
//  byte-for-byte (Appendix A invariant 1). Copy this JSON verbatim into the Node
//  relay's test suite so both sides pin the same values: a change to the
//  derivation updates this once and fails the other side until it matches. The
//  values are fixed forever (N_BUCKETS is immutable), so this file should never
//  need to change.
//
//  Derivation, both sides:
//    room_name = SHA256(canonicalEncode("iterm2-room", [rs, utf8(pid)])), lowercase hex
//    bucket    = digest[30] << 8 | digest[31]   (big-endian last two bytes; 0..65535)
//  where digest is the 32 raw bytes SHA256 produces (room_name is its hex form,
//  so bucket is also the numeric value of room_name's last four hex characters).
//

import Foundation

enum RoomBucketVectors {
    struct Vector: Decodable {
        let rsHex: String
        let pid: String
        let roomName: String
        let bucket: Int
    }

    struct File: Decodable {
        let nBuckets: Int
        let vectors: [Vector]
    }

    /// The vector as JSON. Kept as text (not Swift literals) precisely so it can
    /// be dropped, unchanged, into a non-Swift test suite.
    static let json = #"""
    {
      "comment": "roomName = SHA256(canonicalEncode(iterm2-room, [rs, utf8(pid)])) lowercase hex; bucket = digest[30] << 8 | digest[31] big-endian; n_buckets = 65536. Fixed forever.",
      "n_buckets": 65536,
      "vectors": [
        {
          "rs_hex": "abababababababababababababababababababababababababababababababab",
          "pid": "0123456789abcdef",
          "room_name": "611c035897cf71eebc08e531616a3470f666cd001532e1bd4957dd762efae220",
          "bucket": 57888
        },
        {
          "rs_hex": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
          "pid": "companion",
          "room_name": "de5613dbe578aeb70a6885a481e0252dbc4bb279bcb120235a38cda8a999d07e",
          "bucket": 53374
        },
        {
          "rs_hex": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "pid": "z",
          "room_name": "28396c094119a4f1948f69a5ab2971d8126fdc11c040a280b912f1a48f56bc08",
          "bucket": 48136
        }
      ]
    }
    """#

    static func decoded() throws -> File {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(File.self, from: Data(json.utf8))
    }
}

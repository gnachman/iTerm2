//
//  RoomBucketTests.swift
//  CompanionCore
//
//  Pins the roomName -> shard bucket derivation, including the cross-language
//  vector (RoomBucketVectors) the Node relay must also satisfy. See
//  docs/companion-relay-design.md (§6.2, Appendix A invariant 1).
//

import XCTest
@testable import CompanionProtocol

final class RoomBucketTests: XCTestCase {

    // MARK: Cross-language vector

    func test_crossLanguageVectors() throws {
        let file = try RoomBucketVectors.decoded()
        XCTAssertEqual(file.nBuckets, ShardMap.expectedBuckets)
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            let rs = try XCTUnwrap(Data(hexString: v.rsHex), "bad rs_hex \(v.rsHex)")
            // The two derivations both reproduce the vector.
            XCTAssertEqual(RelayRoom.name(responderStaticPublicKey: rs, pairingID: v.pid),
                           v.roomName, "roomName mismatch for pid \(v.pid)")
            XCTAssertEqual(RelayRoom.bucket(responderStaticPublicKey: rs, pairingID: v.pid),
                           v.bucket, "bucket mismatch for pid \(v.pid)")
            XCTAssertEqual(RelayRoom.bucket(forRoomName: v.roomName),
                           v.bucket, "bucket(forRoomName:) mismatch for \(v.roomName)")
            XCTAssertTrue((0..<ShardMap.expectedBuckets).contains(v.bucket))
        }
    }

    // MARK: The two derivations agree

    func test_bucketFromRsPidMatchesBucketFromRoomName() {
        let rs = Data(repeating: 0x5A, count: 32)
        let pid = "consistency"
        let name = RelayRoom.name(responderStaticPublicKey: rs, pairingID: pid)
        XCTAssertEqual(RelayRoom.bucket(responderStaticPublicKey: rs, pairingID: pid),
                       RelayRoom.bucket(forRoomName: name))
    }

    // MARK: bucket(forRoomName:) - byte order and bounds

    func test_bucketFromRoomName_isBigEndianLastTwoBytes() {
        // A name ending in "0102" is 0x0102 = 258 big-endian, NOT 0x0201; this is
        // the check that catches an endianness flip between Swift and Node.
        let name = String(repeating: "0", count: 60) + "0102"
        XCTAssertEqual(RelayRoom.bucket(forRoomName: name), 0x0102)
        XCTAssertEqual(RelayRoom.bucket(forRoomName: name), 258)
    }

    func test_bucketFromRoomName_highBitByteHasNoSignError() {
        // 0xff00 = 65280; a signed-byte bug would misread the high bit.
        let name = String(repeating: "0", count: 60) + "ff00"
        XCTAssertEqual(RelayRoom.bucket(forRoomName: name), 0xff00)
    }

    func test_bucketFromRoomName_minAndMax() {
        XCTAssertEqual(RelayRoom.bucket(forRoomName: String(repeating: "0", count: 64)), 0)
        XCTAssertEqual(RelayRoom.bucket(forRoomName: String(repeating: "f", count: 64)),
                       ShardMap.expectedBuckets - 1)   // 65535
    }

    func test_bucketFromRoomName_rejectsUppercaseHex() {
        // A canonical room name is lowercase (name() emits lowercase); uppercase
        // is not a valid room name even though it is "hex".
        XCTAssertNil(RelayRoom.bucket(forRoomName: String(repeating: "0", count: 60) + "ABCD"))
    }

    func test_bucketFromRoomName_rejectsFullwidthHex() {
        // Character.isHexDigit follows Unicode Hex_Digit, which admits fullwidth
        // forms (U+FF10...); those are not canonical room names, so 60 fullwidth
        // digits + 4 ASCII hex must be rejected, not silently bucketed.
        let fullwidthZero = "\u{FF10}"   // fullwidth digit zero
        let name = String(repeating: fullwidthZero, count: 60) + "abcd"
        XCTAssertEqual(name.count, 64)
        XCTAssertNil(RelayRoom.bucket(forRoomName: name))
    }

    func test_bucketFromRoomName_rejectsWrongLength() {
        XCTAssertNil(RelayRoom.bucket(forRoomName: "abcd"))
        XCTAssertNil(RelayRoom.bucket(forRoomName: String(repeating: "a", count: 63)))
        XCTAssertNil(RelayRoom.bucket(forRoomName: String(repeating: "a", count: 65)))
        XCTAssertNil(RelayRoom.bucket(forRoomName: ""))
    }

    func test_bucketFromRoomName_rejectsNonHex() {
        XCTAssertNil(RelayRoom.bucket(forRoomName: String(repeating: "g", count: 64)))
    }
}

// Test-local hex -> Data decoder (the package ships only the encoder).
private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

//
//  ShardMapTests.swift
//  CompanionCore
//
//  Decoding, validation (exact partition of the bucket space), and bucket ->
//  host lookup for the shard map. See docs/companion-relay-design.md.
//

import XCTest
@testable import CompanionProtocol

final class ShardMapTests: XCTestCase {
    private let N = ShardMap.expectedBuckets   // 65536

    private func decode(_ json: String) throws -> ShardMap {
        try JSONDecoder().decode(ShardMap.self, from: Data(json.utf8))
    }

    // MARK: Decoding

    func testDecodesExample() throws {
        let map = try decode("""
        {
          "version": 37,
          "ranges": [
            { "low": 0,     "high": 32767, "host": "relay1.iterm2.com" },
            { "low": 32768, "high": 65535, "host": "relay2.iterm2.com" }
          ]
        }
        """)
        XCTAssertEqual(map.version, 37)
        XCTAssertEqual(map.ranges.count, 2)
        XCTAssertEqual(map.ranges[0], ShardMap.Entry(low: 0, high: 32767, host: "relay1.iterm2.com"))
        XCTAssertEqual(map.ranges[1], ShardMap.Entry(low: 32768, high: 65535, host: "relay2.iterm2.com"))
    }

    // MARK: Validation - valid shapes

    func testValidatesSingleHostWholeRing() throws {
        let map = ShardMap(version: 1, ranges: [.init(low: 0, high: N - 1, host: "relay1.iterm2.com")])
        XCTAssertNoThrow(try map.validate())
    }

    func testValidatesWrapArcAsTwoRangesSharingHost() throws {
        // A single arc crossing the 0/65535 seam serializes as two ranges with
        // the same host; coverage still tiles the space, so it validates.
        let map = ShardMap(version: 5, ranges: [
            .init(low: 0, high: 5000, host: "relay1.iterm2.com"),
            .init(low: 5001, high: 59999, host: "relay2.iterm2.com"),
            .init(low: 60000, high: N - 1, host: "relay1.iterm2.com")
        ])
        XCTAssertNoThrow(try map.validate())
    }

    func testValidatesRangesGivenOutOfOrder() throws {
        // Order in the file does not matter; validation sorts by low.
        let map = ShardMap(version: 2, ranges: [
            .init(low: 32768, high: N - 1, host: "relay2.iterm2.com"),
            .init(low: 0, high: 32767, host: "relay1.iterm2.com")
        ])
        XCTAssertNoThrow(try map.validate())
    }

    // MARK: Validation - rejected shapes

    func testRejectsGap() {
        let map = ShardMap(version: 1, ranges: [
            .init(low: 0, high: 100, host: "relay1.iterm2.com"),
            .init(low: 102, high: N - 1, host: "relay2.iterm2.com")   // 101 uncovered
        ])
        XCTAssertThrowsError(try map.validate()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .gapOrOverlap)
        }
    }

    func testRejectsOverlap() {
        let map = ShardMap(version: 1, ranges: [
            .init(low: 0, high: 200, host: "relay1.iterm2.com"),
            .init(low: 200, high: N - 1, host: "relay2.iterm2.com")   // 200 shared
        ])
        XCTAssertThrowsError(try map.validate()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .gapOrOverlap)
        }
    }

    func testRejectsUncoveredTail() {
        let map = ShardMap(version: 1, ranges: [
            .init(low: 0, high: N - 2, host: "relay1.iterm2.com")     // last bucket uncovered
        ])
        XCTAssertThrowsError(try map.validate()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .gapOrOverlap)
        }
    }

    func testRejectsEmptyRanges() {
        let map = ShardMap(version: 1, ranges: [])
        XCTAssertThrowsError(try map.validate()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .emptyRanges)
        }
    }

    func testRejectsEmptyHost() {
        let map = ShardMap(version: 1, ranges: [.init(low: 0, high: N - 1, host: "")])
        XCTAssertThrowsError(try map.validate()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .emptyHost)
        }
    }

    func testRejectsLowGreaterThanHigh() {
        let map = ShardMap(version: 1, ranges: [
            .init(low: 100, high: 50, host: "relay1.iterm2.com"),
            .init(low: 0, high: N - 1, host: "relay2.iterm2.com")
        ])
        XCTAssertThrowsError(try map.validate()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .invalidRange(low: 100, high: 50))
        }
    }

    func testRejectsHighOutOfBounds() {
        let map = ShardMap(version: 1, ranges: [.init(low: 0, high: N, host: "relay1.iterm2.com")])
        XCTAssertThrowsError(try map.validate()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .invalidRange(low: 0, high: N))
        }
    }

    func testRejectsNegativeVersion() {
        let map = ShardMap(version: -1, ranges: [.init(low: 0, high: N - 1, host: "relay1.iterm2.com")])
        XCTAssertThrowsError(try map.validate()) {
            XCTAssertEqual($0 as? ShardMap.ValidationError, .negativeVersion)
        }
    }

    // MARK: Lookup

    func testHostForBucketAtBoundaries() {
        let map = ShardMap(version: 1, ranges: [
            .init(low: 0, high: 32767, host: "relay1.iterm2.com"),
            .init(low: 32768, high: N - 1, host: "relay2.iterm2.com")
        ])
        XCTAssertEqual(map.host(forBucket: 0), "relay1.iterm2.com")
        XCTAssertEqual(map.host(forBucket: 32767), "relay1.iterm2.com")
        XCTAssertEqual(map.host(forBucket: 32768), "relay2.iterm2.com")
        XCTAssertEqual(map.host(forBucket: N - 1), "relay2.iterm2.com")
    }

    func testHostForBucketOutOfRangeIsNil() {
        let map = ShardMap(version: 1, ranges: [.init(low: 0, high: N - 1, host: "relay1.iterm2.com")])
        XCTAssertNil(map.host(forBucket: -1))
        XCTAssertNil(map.host(forBucket: N))
    }

    func testHostForBucketFindsWrapArc() {
        let map = ShardMap(version: 1, ranges: [
            .init(low: 0, high: 5000, host: "relay1.iterm2.com"),
            .init(low: 5001, high: 59999, host: "relay2.iterm2.com"),
            .init(low: 60000, high: N - 1, host: "relay1.iterm2.com")
        ])
        XCTAssertEqual(map.host(forBucket: 3000), "relay1.iterm2.com")
        XCTAssertEqual(map.host(forBucket: 30000), "relay2.iterm2.com")
        XCTAssertEqual(map.host(forBucket: 65000), "relay1.iterm2.com")
    }
}

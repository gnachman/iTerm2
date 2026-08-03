//
//  iTermRowOutputCacheTests.swift
//  ModernTests
//
//  Tests for the LRU behavior of the per-row draw-output cache.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermRowOutputCacheTests: XCTestCase {

    private func makeKey(config: UInt64, generation: Int64) -> iTermRowCacheKey {
        var k = iTermRowCacheKey()
        k.configGeneration = config
        k.contentIdentity.generation = generation
        return k
    }

    // A glyph-keys buffer with plenty of room (bytes; the cache grows it if needed).
    private func makeGlyphKeys() -> iTermGlyphKeyData {
        return iTermGlyphKeyData(ofLength: 4096)
    }

    // Store one entry, read the attributes/background/scalars back byte-for-byte,
    // and confirm a different key misses.
    func testStoreThenLookupRoundTrips() {
        let cache = iTermRowOutputCache(capacity: 8)
        var key = makeKey(config: 1, generation: 10)
        let glyphs: [UInt8] = [1, 2, 3, 4]
        let attrs: [UInt8] = [5, 6]
        let bg: [UInt8] = [7]
        glyphs.withUnsafeBytes { g in attrs.withUnsafeBytes { a in bg.withUnsafeBytes { b in
            cache.store(&key,
                        glyphKeys: g.baseAddress!, glyphKeysLength: 4,
                        attributes: a.baseAddress!, attributesLength: 2,
                        background: b.baseAddress!, backgroundLength: 1,
                        glyphKeyCount: 1, rleCount: 1, drawableGlyphs: 3,
                        hasUnderlineOrStrikethrough: true)
        }}}

        let gkd = makeGlyphKeys()
        var oa = [UInt8](repeating: 0, count: 2)
        var ob = [UInt8](repeating: 0, count: 1)
        var gc: UInt = 0, rc: Int32 = 0, dg: Int32 = 0
        var hu: ObjCBool = false
        let hit = oa.withUnsafeMutableBytes { a in ob.withUnsafeMutableBytes { b in
            cache.lookup(&key,
                         glyphKeys: gkd, attributes: a.baseAddress!, background: b.baseAddress!,
                         glyphKeyCount: &gc, rleCount: &rc, drawableGlyphs: &dg,
                         hasUnderlineOrStrikethrough: &hu)
        }}
        XCTAssertTrue(hit)
        XCTAssertEqual(oa, [5, 6])
        XCTAssertEqual(ob, [7])
        XCTAssertEqual(gc, 1)
        XCTAssertEqual(rc, 1)
        XCTAssertEqual(dg, 3)
        XCTAssertTrue(hu.boolValue)
        // Glyph keys copied into the growable buffer.
        let gbytes = gkd.mutableBytes.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual([gbytes[0], gbytes[1], gbytes[2], gbytes[3]], [1, 2, 3, 4])

        var other = makeKey(config: 1, generation: 99)
        XCTAssertFalse(lookupTiny(cache, &other))
    }

    // The config generation is part of the key: same content, different config -> miss.
    func testConfigGenerationIsPartOfKey() {
        let cache = iTermRowOutputCache(capacity: 8)
        var stored = makeKey(config: 1, generation: 10)
        storeTiny(cache, &stored)
        var differentConfig = makeKey(config: 2, generation: 10)
        XCTAssertFalse(lookupTiny(cache, &differentConfig))
    }

    // Capacity is enforced with least-recently-used eviction.
    func testLRUEviction() {
        let cache = iTermRowOutputCache(capacity: 2)
        var k1 = makeKey(config: 1, generation: 1)
        var k2 = makeKey(config: 1, generation: 2)
        var k3 = makeKey(config: 1, generation: 3)
        storeTiny(cache, &k1)
        storeTiny(cache, &k2)
        // Touch k1 so k2 is now least-recently-used.
        XCTAssertTrue(lookupTiny(cache, &k1))
        storeTiny(cache, &k3)  // evicts k2
        XCTAssertTrue(lookupTiny(cache, &k1))
        XCTAssertTrue(lookupTiny(cache, &k3))
        XCTAssertFalse(lookupTiny(cache, &k2))
        XCTAssertEqual(cache.count, 2)
    }

    // MARK: - Helpers using a 1-byte blob

    private func storeTiny(_ cache: iTermRowOutputCache, _ key: inout iTermRowCacheKey) {
        var byte: UInt8 = 0xAB
        withUnsafeBytes(of: &byte) { p in
            cache.store(&key,
                        glyphKeys: p.baseAddress!, glyphKeysLength: 1,
                        attributes: p.baseAddress!, attributesLength: 1,
                        background: p.baseAddress!, backgroundLength: 1,
                        glyphKeyCount: 1, rleCount: 1, drawableGlyphs: 1,
                        hasUnderlineOrStrikethrough: false)
        }
    }

    private func lookupTiny(_ cache: iTermRowOutputCache, _ key: inout iTermRowCacheKey) -> Bool {
        let gkd = makeGlyphKeys()
        var a: UInt8 = 0, b: UInt8 = 0
        var gc: UInt = 0, rc: Int32 = 0, dg: Int32 = 0
        var hu: ObjCBool = false
        return withUnsafeMutableBytes(of: &a) { ap in
            withUnsafeMutableBytes(of: &b) { bp in
                cache.lookup(&key, glyphKeys: gkd, attributes: ap.baseAddress!, background: bp.baseAddress!,
                             glyphKeyCount: &gc, rleCount: &rc, drawableGlyphs: &dg, hasUnderlineOrStrikethrough: &hu)
            }
        }
    }
}

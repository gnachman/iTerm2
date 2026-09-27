//
//  BidiPasteStripTests.swift
//  ModernTests
//
//  The "strip zero-width bidi/format characters on paste" option is titled for
//  bidi/format characters, so its set must include the actual bidi reordering
//  controls (the Trojan-Source set: directional embeddings/overrides, isolates,
//  and the Arabic Letter Mark), not just the cosmetic <200c> subset.
//

import XCTest
@testable import iTerm2SharedARC

final class BidiPasteStripTests: XCTestCase {
    func testZeroWidthFormatSetIncludesBidiReorderingControls() {
        let set = iTermPasteHelper.zeroWidthFormatCharacterSet() as CharacterSet

        // The reordering controls a "bidi/format" stripper is most expected to remove.
        let required: [UInt32] = [0x202A, 0x202B, 0x202C, 0x202D, 0x202E,  // LRE RLE PDF LRO RLO
                                  0x2066, 0x2067, 0x2068, 0x2069,          // LRI RLI FSI PDI
                                  0x061C]                                   // ALM
        for cp in required {
            XCTAssertTrue(set.contains(UnicodeScalar(cp)!),
                          "strip set must include U+\(String(cp, radix: 16, uppercase: true))")
        }

        // The original cosmetic subset must still be present.
        let original: [UInt32] = [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x00AD, 0x2060, 0xFEFF]
        for cp in original {
            XCTAssertTrue(set.contains(UnicodeScalar(cp)!),
                          "strip set must still include U+\(String(cp, radix: 16, uppercase: true))")
        }
    }
}

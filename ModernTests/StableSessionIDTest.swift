//
//  StableSessionIDTest.swift
//  iTerm2 ModernTests
//
//  The stable per-session identifier (ptys_ + 12 Crockford base32 + 1 checksum
//  char). These properties are what let it stand in for the rotating guid:
//  detection in text keys on the strict canonical form, a candidate id
//  round-trips through case/confusable mangling via canonical(), and a truncated
//  or corrupted id fails validation instead of resolving to the wrong session.
//

import XCTest
@testable import iTerm2SharedARC

final class StableSessionIDTest: XCTestCase {
    private let prefix = "ptys_"

    func testGeneratedIsWellFormed() {
        for _ in 0..<200 {
            let id = StableSessionID.generate()
            XCTAssertTrue(id.hasPrefix(prefix), "\(id) missing prefix")
            XCTAssertEqual(id.count, prefix.count + 13, "\(id) wrong length")
            XCTAssertTrue(StableSessionID.isValid(id), "\(id) should be valid")
        }
    }

    func testGeneratedIsCanonical() {
        for _ in 0..<200 {
            let id = StableSessionID.generate()
            XCTAssertEqual(StableSessionID.canonical(id), id)
        }
    }

    func testUniqueness() {
        var seen = Set<String>()
        for _ in 0..<2000 {
            seen.insert(StableSessionID.generate())
        }
        // 60 bits of entropy: 2000 draws should never collide.
        XCTAssertEqual(seen.count, 2000)
    }

    func testRejectsGarbage() {
        let bad = [
            "",
            "ptys_",
            "hello world",
            "01234567-89ab-cdef-0123-456789abcdef",     // a UUID
            "@ptys_9QK3ZM7WX4VBT",                       // has the @ sigil, not bare
            "6727e51d7a1b2c3d4e5f60718293a4b5c6d7e8f9",  // a git-hash-shaped hex string
            "c2Vzc2lvbmlkZGF0YQ==",                       // base64-ish
            "sess_9QK3ZM7WX4VBT",                        // wrong prefix
        ]
        for s in bad {
            XCTAssertFalse(StableSessionID.isValid(s), "\(s) should be rejected")
            XCTAssertNil(StableSessionID.canonical(s), "\(s) should not canonicalize")
        }
    }

    func testRejectsWrongLength() {
        let id = StableSessionID.generate()
        XCTAssertFalse(StableSessionID.isValid(String(id.dropLast())))        // 12 after prefix
        XCTAssertFalse(StableSessionID.isValid(String(id.dropLast(5))))       // truncated
        XCTAssertFalse(StableSessionID.isValid(id + "9"))                     // 14 after prefix
    }

    func testChecksumCatchesCheckCharChange() {
        // Replacing only the check (last) char with any other alphabet char
        // must always invalidate.
        let id = StableSessionID.generate()
        let last = id.last!
        for replacement in "0123456789ABCDEFGHJKMNPQRSTVWXYZ" where replacement != last {
            let mutated = String(id.dropLast()) + String(replacement)
            XCTAssertFalse(StableSessionID.isValid(mutated),
                           "check-char change \(last)->\(replacement) not caught")
        }
    }

    func testChecksumCatchesFirstBodyChange() {
        // The first body position has weight 1, so any single substitution there
        // is always caught by the mod-32 checksum.
        let id = StableSessionID.generate()
        let chars = Array(id)
        let bodyStart = prefix.count
        let original = chars[bodyStart]
        for replacement in "0123456789ABCDEFGHJKMNPQRSTVWXYZ" where replacement != original {
            var mutated = chars
            mutated[bodyStart] = replacement
            XCTAssertFalse(StableSessionID.isValid(String(mutated)),
                           "first-body change \(original)->\(replacement) not caught")
        }
    }

    func testCaseInsensitive() {
        let id = StableSessionID.generate()
        // Both the prefix and the body fold: a fully lowercased or fully
        // uppercased id validates and canonicalizes back to the same value.
        for variant in [id.lowercased(), id.uppercased()] {
            XCTAssertTrue(StableSessionID.isValid(variant), "\(variant)")
            XCTAssertEqual(StableSessionID.canonical(variant), id)
        }
    }

    func testPrefixCaseInsensitive() {
        // The recommended case-insensitive scan can capture an uppercased or
        // mixed-case prefix; canonical() must accept it and normalize back.
        let id = StableSessionID.generate()
        let body = id.dropFirst(prefix.count)
        for p in ["PTYS_", "PtYs_", "ptYS_"] {
            let variant = p + body
            XCTAssertTrue(StableSessionID.isValid(variant), "\(variant)")
            XCTAssertEqual(StableSessionID.canonical(variant), id)
        }
    }

    func testCrockfordConfusables() {
        // Find a generated id whose body contains a '0' or '1' so we can test
        // that O/o -> 0 and I/i/L/l -> 1 fold back to the same canonical id.
        var sample: String?
        for _ in 0..<500 {
            let id = StableSessionID.generate()
            if id.dropFirst(prefix.count).contains(where: { $0 == "0" || $0 == "1" }) {
                sample = id
                break
            }
        }
        guard let id = sample else {
            XCTFail("could not produce an id containing 0 or 1")
            return
        }
        var confused = ""
        for (i, ch) in id.enumerated() {
            if i < prefix.count {
                confused.append(ch)
            } else if ch == "0" {
                confused.append("O")
            } else if ch == "1" {
                confused.append("L")
            } else {
                confused.append(ch)
            }
        }
        XCTAssertEqual(StableSessionID.canonical(confused), id)
    }

    func testDetectionRegexFindsTokenAndSkipsUUID() {
        let regex = try! NSRegularExpression(pattern: "\\b\(StableSessionID.tokenPattern)\\b")
        let id = StableSessionID.generate()
        let text = "See session \(id) for details."
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(ns.substring(with: matches[0].range), id)

        let uuidText = "id 01234567-89ab-cdef-0123-456789abcdef here"
        let uuidNS = uuidText as NSString
        XCTAssertEqual(regex.matches(in: uuidText,
                                     range: NSRange(location: 0, length: uuidNS.length)).count, 0)
    }
}

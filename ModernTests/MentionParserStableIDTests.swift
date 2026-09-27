//
//  MentionParserStableIDTests.swift
//  iTerm2 ModernTests
//
//  MentionParser must recognize the ptys_ stableID form (the orchestrator now
//  emits stableIDs in the <workgroups> snapshot) in addition to legacy UUIDs,
//  fold a case/confusable-mangled stableID to canonical form, and keep rejecting
//  non-mentions.
//

import XCTest
@testable import iTerm2SharedARC

final class MentionParserStableIDTests: XCTestCase {
    func testMatchesBareStableID() {
        let id = StableSessionID.generate()
        let mentions = MentionParser.mentions(in: "see @\(id) now")
        XCTAssertEqual(mentions.count, 1)
        XCTAssertNil(mentions.first?.prefix)
        XCTAssertEqual(mentions.first?.token, id)
        XCTAssertEqual(mentions.first?.identifier, id)
    }

    func testMatchesSessionScopedStableID() {
        let id = StableSessionID.generate()
        let mentions = MentionParser.mentions(in: "@session:\(id)")
        XCTAssertEqual(mentions.first?.prefix, "session:")
        XCTAssertEqual(mentions.first?.token, id)
        XCTAssertEqual(mentions.first?.identifier, "session:" + id)
    }

    func testStableIDMatchedCaseInsensitivelyAndCanonicalized() {
        let id = StableSessionID.generate()   // ptys_ + uppercase body
        let mentions = MentionParser.mentions(in: "@\(id.lowercased())")
        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions.first?.token, id)   // folded back to canonical
    }

    func testLegacyUuidStillMatches() {
        let uuid = "01234567-89ab-cdef-0123-456789abcdef"
        let mentions = MentionParser.mentions(in: "@\(uuid) and @session:\(uuid) and @wg-\(uuid)")
        XCTAssertEqual(mentions.count, 3)
        XCTAssertEqual(mentions[0].token, uuid)     // verbatim
        XCTAssertNil(mentions[0].prefix)
        XCTAssertEqual(mentions[1].prefix, "session:")
        XCTAssertEqual(mentions[2].prefix, "wg-")
    }

    func testNonMentionsNotMatched() {
        XCTAssertTrue(MentionParser.mentions(in: "@world hello @notanid").isEmpty)
        XCTAssertTrue(MentionParser.mentions(in: "ping foo@example.com").isEmpty)
        // A stableID with one extra trailing base32 char must not partial-match.
        XCTAssertTrue(MentionParser.mentions(in: "@\(StableSessionID.generate())Z").isEmpty)
    }

    // MARK: - Optional "@" (AI-authored text)

    func testBareStableIDMatchesWhenAtSignOptional() {
        let id = StableSessionID.generate()
        let mentions = MentionParser.mentions(in: "look at \(id) please", atSignOptional: true)
        XCTAssertEqual(mentions.count, 1)
        XCTAssertNil(mentions.first?.prefix)
        XCTAssertEqual(mentions.first?.token, id)
    }

    func testBareStableIDNotMatchedByDefault() {
        let id = StableSessionID.generate()
        XCTAssertTrue(MentionParser.mentions(in: "look at \(id) please").isEmpty)
    }

    func testAtSignedStillMatchesWhenAtSignOptional() {
        let id = StableSessionID.generate()
        let mentions = MentionParser.mentions(in: "see @\(id) now", atSignOptional: true)
        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions.first?.token, id)
    }

    func testBareStableIDCanonicalizedWhenAtSignOptional() {
        let id = StableSessionID.generate()
        let mentions = MentionParser.mentions(in: "\(id.lowercased())", atSignOptional: true)
        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions.first?.token, id)  // folded to canonical
    }

    func testBareUuidNotMatchedEvenWhenAtSignOptional() {
        // A bare UUID is too common in prose to admit without an "@".
        let uuid = "01234567-89ab-cdef-0123-456789abcdef"
        XCTAssertTrue(MentionParser.mentions(in: "run id \(uuid) done", atSignOptional: true).isEmpty)
    }

    func testBarePrefixedFormsNotMatchedEvenWhenAtSignOptional() {
        let id = StableSessionID.generate()
        XCTAssertTrue(MentionParser.mentions(in: "session:\(id)", atSignOptional: true).isEmpty)
        XCTAssertTrue(MentionParser.mentions(in: "wg-\(id)", atSignOptional: true).isEmpty)
    }

    func testBareStableIDGluedToPrecedingCharNotMatched() {
        let id = StableSessionID.generate()
        // No boundary before the token: not a mention.
        XCTAssertTrue(MentionParser.mentions(in: "x\(id)", atSignOptional: true).isEmpty)
    }

    func testBareStableIDWithBadChecksumNotMatched() {
        // A ptys_-shaped run of the right length (12 body + 1 check) whose check
        // char is wrong: all-zero body checksums to '0', so any other check char
        // is invalid. Must not match bare even though it fits the shape.
        let mangled = "ptys_0000000000001"
        XCTAssertNil(StableSessionID.canonical(mangled))  // shape-valid but bad checksum
        XCTAssertTrue(MentionParser.mentions(in: "id \(mangled) x", atSignOptional: true).isEmpty)
    }

    func testBareStableIDAtStartOfStringMatches() {
        let id = StableSessionID.generate()
        let mentions = MentionParser.mentions(in: "\(id) is the one", atSignOptional: true)
        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions.first?.token, id)
    }

    func testSplitRoundTripsCanonical() {
        let id = StableSessionID.generate()
        XCTAssertEqual(MentionParser.split(identifier: "session:" + id.lowercased())?.token, id)
        XCTAssertEqual(MentionParser.split(identifier: id)?.prefix ?? "nil-ok", "nil-ok")
        XCTAssertNil(MentionParser.split(identifier: "not a mention"))
        XCTAssertNil(MentionParser.split(identifier: id + " trailing"))
    }
}

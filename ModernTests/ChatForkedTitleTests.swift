//
//  ChatForkedTitleTests.swift
//  iTerm2
//
//  Regression tests for locale-independent stripping of the forked-chat title
//  suffix. A chat forked under one language and re-forked under another must
//  replace the existing suffix rather than append a second one.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatForkedTitleTests: XCTestCase {
    private let englishPrefix = "(Forked at "

    // Loads a shipped localization's ForkedAtPrefix at runtime.
    private func prefix(forLocalization localization: String) -> String? {
        guard let lprojPath = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: lprojPath) else {
            return nil
        }
        let prefix = bundle.localizedString(forKey: "ChatWindowController.ForkedAtPrefix",
                                            value: "",
                                            table: "Localizable")
        return prefix.isEmpty ? nil : prefix
    }

    // A chat whose title carries a pt-BR fork suffix, re-forked under English,
    // must end up with exactly one English suffix and no pt-BR remnant.
    func testCrossLanguageForkReplacesSuffix() throws {
        guard let ptPrefix = prefix(forLocalization: "pt-BR") else {
            throw XCTSkip("pt-BR localization not present in this build")
        }
        XCTAssertNotEqual(ptPrefix, englishPrefix)

        let originalTitle = "My Chat " + ptPrefix + "1/1/25)"
        let newTimestamp = "2/2/26, 3:04 PM"

        let result = ChatWindowController.forkedChatTitle(from: originalTitle,
                                                          timestamp: newTimestamp)

        XCTAssertEqual(result, "My Chat " + englishPrefix + newTimestamp + ")")
        XCTAssertFalse(result.contains(ptPrefix))
        // The English prefix should appear exactly once.
        XCTAssertEqual(result.components(separatedBy: englishPrefix).count - 1, 1)
    }

    // Same-locale re-fork replaces the existing suffix rather than appending.
    func testSameLocaleForkReplacesSuffix() {
        let originalTitle = "My Chat " + englishPrefix + "1/1/25)"
        let newTimestamp = "2/2/26, 3:04 PM"

        let result = ChatWindowController.forkedChatTitle(from: originalTitle,
                                                          timestamp: newTimestamp)

        XCTAssertEqual(result, "My Chat " + englishPrefix + newTimestamp + ")")
        XCTAssertEqual(result.components(separatedBy: englishPrefix).count - 1, 1)
    }

    // A title with no fork suffix gets one appended (with a separating space).
    func testTitleWithoutSuffixGetsOneAppended() {
        let originalTitle = "My Chat"
        let newTimestamp = "2/2/26, 3:04 PM"

        let result = ChatWindowController.forkedChatTitle(from: originalTitle,
                                                          timestamp: newTimestamp)

        XCTAssertEqual(result, "My Chat " + englishPrefix + newTimestamp + ")")
    }

    // A user title that merely CONTAINS the prefix in the middle (not as a
    // trailing suffix) must not be truncated: the suffix is appended, not
    // substituted. This guards the anchored-at-end hardening.
    func testTitleContainingPrefixInMiddleIsNotTruncated() {
        let originalTitle = "Notes " + englishPrefix + "the office) todo"
        let newTimestamp = "2/2/26, 3:04 PM"

        let result = ChatWindowController.forkedChatTitle(from: originalTitle,
                                                          timestamp: newTimestamp)

        XCTAssertEqual(result, originalTitle + " " + englishPrefix + newTimestamp + ")")
    }

    // A title that ends in "<prefix>...)" but whose "timestamp" has no digit is
    // not a real fork suffix and must be preserved. This guards the
    // plausible-timestamp hardening.
    func testTrailingPrefixWithoutTimestampIsNotStripped() {
        let originalTitle = "My Chat " + englishPrefix + "the beach)"
        let newTimestamp = "2/2/26, 3:04 PM"

        let result = ChatWindowController.forkedChatTitle(from: originalTitle,
                                                          timestamp: newTimestamp)

        XCTAssertEqual(result, originalTitle + " " + englishPrefix + newTimestamp + ")")
    }
}

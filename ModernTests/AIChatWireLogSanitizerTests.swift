//
//  AIChatWireLogSanitizerTests.swift
//  ModernTests
//
//  Credential scrubbing for the AI chat wire log. A real Anthropic key
//  ended up in a wire log checked into a working tree; these tests pin
//  the scrubbing behavior for every vendor key format we know about.
//

import XCTest
@testable import iTerm2SharedARC

final class AIChatWireLogSanitizerTests: XCTestCase {
    // Same shapes as real keys, but fabricated (never issued by anyone).
    private let anthropicKey = "sk-ant-api03-FAKEfakeFAKEfakeFAKEfake-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234-fakeAAA"
    private let openAIKey = "sk-FAKE0123456789abcdefghijklmnopqrstuvwxyzFAKE0123"
    private let openAIProjectKey = "sk-proj-abcDEF123456789_abcDEF123456789-abcDEF123456789"
    // Hyphenated on purpose: any plausible sk-<32 alphanumeric> string
    // trips GitHub push protection's DeepSeek detector even when it is
    // an obvious fake. Our scrubber only needs sk- plus 16+ token
    // chars, and its character class includes hyphens.
    private let deepSeekKey = "sk-FAKE-deepseek-FAKE-deepseek-FAKE00"
    private let geminiKey = "AIzaSyA1bC2dE3fG4hI5jK6lM7nO8pQ9rS0tUvW"

    // MARK: - Body/URL scrubbing

    func testScrubsAnthropicKey() {
        let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets("key: \(anthropicKey), done")
        XCTAssertFalse(scrubbed.contains(anthropicKey))
        XCTAssertTrue(scrubbed.hasPrefix("key: sk-ant-a"))
        XCTAssertTrue(scrubbed.contains("[redacted \(anthropicKey.count) chars]"))
        XCTAssertTrue(scrubbed.hasSuffix(", done"))
    }

    func testScrubsOpenAIKeys() {
        for key in [openAIKey, openAIProjectKey] {
            let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets(key)
            XCTAssertFalse(scrubbed.contains(key))
            XCTAssertTrue(scrubbed.contains("[redacted"))
        }
    }

    func testScrubsDeepSeekKey() {
        let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets(deepSeekKey)
        XCTAssertFalse(scrubbed.contains(deepSeekKey))
    }

    func testScrubsGeminiKeyInURLQuery() {
        let url = "https://generativelanguage.googleapis.com/v1beta/models/gemini:generateContent?key=\(geminiKey)"
        let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets(url)
        XCTAssertFalse(scrubbed.contains(geminiKey))
        XCTAssertTrue(scrubbed.contains("?key=AIzaSyA1"))
        XCTAssertTrue(scrubbed.hasPrefix("https://generativelanguage.googleapis.com/"))
    }

    func testScrubsMultipleKeysInOneBody() {
        let body = "{\"a\":\"\(anthropicKey)\",\"b\":\"\(geminiKey)\",\"c\":\"\(openAIKey)\"}"
        let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets(body)
        XCTAssertFalse(scrubbed.contains(anthropicKey))
        XCTAssertFalse(scrubbed.contains(geminiKey))
        XCTAssertFalse(scrubbed.contains(openAIKey))
        // The surrounding JSON structure survives.
        XCTAssertTrue(scrubbed.hasPrefix("{\"a\":\"sk-ant-a"))
        XCTAssertTrue(scrubbed.hasSuffix("\"}"))
    }

    func testLeavesOrdinaryProseAlone() {
        let prose = "Use sk-learn (scikit-learn) and set AIzalike=false. Short sk-abc stays."
        XCTAssertEqual(AIChatWireLogSanitizer.scrubbingSecrets(prose), prose)
    }

    func testLeavesHyphenatedIdentifiersEndingInSKAlone() {
        // Words ending in "sk" followed by a long hyphenated tail
        // contain an embedded "sk-<16+ token chars>" substring. The
        // leading anchor must keep these from being mangled.
        let prose = """
            {"files":["disk-configuration-manager-2024.swift",
            "task-management-migration-script.py"],
            "note":"risk-assessment-framework-v2 and desk-reservation-system-prod"}
            """
        XCTAssertEqual(AIChatWireLogSanitizer.scrubbingSecrets(prose), prose)
    }

    func testStillScrubsKeyAfterNonTokenBoundary() {
        // The anchor requires a non-token character before sk-, not a
        // word boundary in the \\b sense; keys after quotes, colons,
        // spaces, and at start of text must all still match.
        for text in ["\"\(openAIKey)\"", "key: \(openAIKey)", openAIKey] {
            XCTAssertFalse(AIChatWireLogSanitizer.scrubbingSecrets(text).contains(openAIKey))
        }
    }

    // MARK: - Header sanitizing

    func testCredentialHeaderIsFingerprintedRegardlessOfFormat() {
        let unknownFormatKey = "totally-proprietary-key-format-1234567890"
        let scrubbed = AIChatWireLogSanitizer.sanitizedHeaderValue(unknownFormatKey,
                                                                   forHeader: "x-api-key")
        XCTAssertFalse(scrubbed.contains(unknownFormatKey))
        XCTAssertTrue(scrubbed.contains("[redacted \(unknownFormatKey.count) chars]"))
    }

    func testCredentialHeaderMatchingIsCaseInsensitive() {
        let scrubbed = AIChatWireLogSanitizer.sanitizedHeaderValue(openAIKey,
                                                                   forHeader: "X-Api-Key")
        XCTAssertFalse(scrubbed.contains(openAIKey))
    }

    func testAuthorizationBearerKeepsScheme() {
        let scrubbed = AIChatWireLogSanitizer.sanitizedHeaderValue("Bearer \(openAIKey)",
                                                                   forHeader: "Authorization")
        XCTAssertTrue(scrubbed.hasPrefix("Bearer "))
        XCTAssertFalse(scrubbed.contains(openAIKey))
    }

    func testNonCredentialHeaderStillPatternScrubbed() {
        // A key that leaks into an unexpected header is still caught by
        // the pattern layer.
        let scrubbed = AIChatWireLogSanitizer.sanitizedHeaderValue(anthropicKey,
                                                                   forHeader: "x-custom-debug")
        XCTAssertFalse(scrubbed.contains(anthropicKey))
    }

    func testInnocentHeaderValueUnchanged() {
        XCTAssertEqual(AIChatWireLogSanitizer.sanitizedHeaderValue("application/json",
                                                                   forHeader: "Content-Type"),
                       "application/json")
    }

    // MARK: - Fingerprint

    func testFingerprintOfShortSecretHidesEverything() {
        let fingerprint = AIChatWireLogSanitizer.fingerprint("tiny")
        XCTAssertFalse(fingerprint.contains("tiny"))
        XCTAssertEqual(fingerprint, "[redacted 4 chars]")
    }

    func testFingerprintOfMediumSecretRevealsNothing() {
        // A 16-char credential-header value must not have 12 of its 16
        // chars disclosed; below the threshold the whole thing is hidden.
        let secret = "0123456789abcdef"
        XCTAssertEqual(AIChatWireLogSanitizer.fingerprint(secret),
                       "[redacted 16 chars]")
        let boundary = String(repeating: "x", count: 31)
        XCTAssertEqual(AIChatWireLogSanitizer.fingerprint(boundary),
                       "[redacted 31 chars]")
    }
}

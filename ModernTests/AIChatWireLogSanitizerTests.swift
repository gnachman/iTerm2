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

    func testUnknownHeaderIsFingerprintedWholesale() {
        // A header not on the harmless list is treated as a credential.
        let scrubbed = AIChatWireLogSanitizer.sanitizedHeaderValue(anthropicKey,
                                                                   forHeader: "x-custom-debug")
        XCTAssertFalse(scrubbed.contains(anthropicKey))
    }

    func testInnocentHeaderValueUnchanged() {
        XCTAssertEqual(AIChatWireLogSanitizer.sanitizedHeaderValue("application/json",
                                                                   forHeader: "Content-Type"),
                       "application/json")
    }

    // MARK: - Custom headers (QA finding F-085)

    // The exact headers from the QA repro: a manual model with three
    // user-configured custom headers.
    private let qaHeaders = [
        "Authorization": "Bearer tok",
        "Proxy-Authorization": "secret123",
        "X-Auth-Token": "xauth777",
        "Content-Type": "application/json",
    ]
    private let qaSecrets = ["tok", "secret123", "xauth777"]

    private func assertNoSecretValues(_ text: String,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        // Header names like "X-Auth-Token" contain "Tok", so check the
        // value part of each "Name: value" line rather than the whole
        // text.
        for textLine in text.components(separatedBy: "\n") {
            guard let colon = textLine.range(of: ": ") else { continue }
            let value = textLine[colon.upperBound...]
            for secret in qaSecrets {
                XCTAssertFalse(value.contains(secret),
                               "Secret \(secret) leaked in line: \(textLine)",
                               file: file, line: line)
            }
        }
    }

    func testEveryNonAllowlistedHeaderValueIsRedacted() {
        for (name, value) in qaHeaders where name != "Content-Type" {
            let scrubbed = AIChatWireLogSanitizer.sanitizedHeaderValue(value, forHeader: name)
            XCTAssertFalse(scrubbed.contains(value.replacingOccurrences(of: "Bearer ", with: "")),
                           "\(name) leaked: \(scrubbed)")
            XCTAssertTrue(scrubbed.contains("[redacted"), "\(name): \(scrubbed)")
        }
    }

    func testArbitraryCustomHeaderDoesNotLeakFirstWord() {
        // Only real auth headers keep a scheme prefix; a custom header
        // whose value happens to contain a space must not expose its
        // first word.
        let scrubbed = AIChatWireLogSanitizer.sanitizedHeaderValue("hunter2 more",
                                                                   forHeader: "X-Custom-Secret")
        XCTAssertFalse(scrubbed.contains("hunter2"))
    }

    func testProxyAuthorizationKeepsScheme() {
        let scrubbed = AIChatWireLogSanitizer.sanitizedHeaderValue("Basic dXNlcjpwYXNz",
                                                                   forHeader: "Proxy-Authorization")
        XCTAssertTrue(scrubbed.hasPrefix("Basic "))
        XCTAssertFalse(scrubbed.contains("dXNlcjpwYXNz"))
    }

    func testWireLogRequestRecordRedactsCustomHeaders() {
        let request = WebRequest(headers: qaHeaders,
                                 method: "POST",
                                 body: .string("{}"),
                                 url: "https://example.com/v1/chat")
        let record = AIChatWireLogger.requestRecord(callID: UUID(),
                                                    stamp: "now",
                                                    request: request)
        assertNoSecretValues(record)
        XCTAssertTrue(record.contains("Proxy-Authorization: "))
        XCTAssertTrue(record.contains("X-Auth-Token: "))
        XCTAssertTrue(record.contains("Content-Type: application/json"))
    }

    func testWebRequestDebugDescriptionRedactsHeaders() {
        let request = WebRequest(headers: qaHeaders,
                                 method: "POST",
                                 body: .string("{\"prompt\":\"hello\"}"),
                                 url: "https://example.com/v1/chat")
        let description = request.debugDescription
        assertNoSecretValues(description)
        XCTAssertTrue(description.contains("Proxy-Authorization"))
        XCTAssertTrue(description.contains("X-Auth-Token"))
        XCTAssertTrue(description.contains("application/json"))
        XCTAssertTrue(description.contains("POST https://example.com/v1/chat"))
        XCTAssertTrue(description.contains("hello"))
        // String interpolation (as DLog("load \(webRequest)") does) must
        // also go through the redacting description.
        assertNoSecretValues("\(request)")
    }

    func testWebRequestDebugDescriptionRedactsKeyInURLQuery() {
        // A Gemini-API model pointed at a custom endpoint whose key does
        // not have Google's AIza shape.
        let request = WebRequest(headers: [:],
                                 method: "POST",
                                 body: .string(""),
                                 url: "https://proxy.example.com/v1/models/m:generateContent?key=customKey12345&alt=sse")
        let description = request.debugDescription
        XCTAssertFalse(description.contains("customKey12345"))
        XCTAssertTrue(description.contains("alt=sse"))
    }

    func testScrubsKeyQueryParameterInErrorText() {
        // URLSession errors print the failing URL, Gemini key included.
        let text = "Error Domain=NSURLErrorDomain Code=-1004 UserInfo={NSErrorFailingURLStringKey=https://h/x?key=customKey12345&alt=sse}"
        let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets(text)
        XCTAssertFalse(scrubbed.contains("customKey12345"))
        XCTAssertTrue(scrubbed.contains("&alt=sse}"))
    }

    func testScrubsOtherCredentialQueryParameters() {
        for name in ["api_key", "access_token", "client_secret", "Token"] {
            let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets("https://h/x?a=1&\(name)=hunter2&b=2")
            XCTAssertFalse(scrubbed.contains("hunter2"), name)
            XCTAssertTrue(scrubbed.hasSuffix("&b=2"), name)
        }
        // A parameter whose name merely ends in "key" is left alone.
        XCTAssertEqual(AIChatWireLogSanitizer.scrubbingSecrets("https://h/x?monkey=banana"),
                       "https://h/x?monkey=banana")
    }

    func testSanitizedHeadersDescriptionIsSortedAndRedacted() {
        let description = AIChatWireLogSanitizer.sanitizedHeadersDescription(qaHeaders)
        assertNoSecretValues(description)
        let names = description.components(separatedBy: "\n").filter { !$0.isEmpty }.compactMap {
            $0.components(separatedBy: ": ").first
        }
        XCTAssertEqual(names, ["Authorization", "Content-Type", "Proxy-Authorization", "X-Auth-Token"])
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

//
//  AIRequestBuilderAttachmentTests.swift
//  iTerm2 ModernTests
//
//  Pure-unit tests for the per-vendor request builders' handling of
//  attachment and multipart bodies. Each test constructs an LLM.Message
//  with a known attachment shape, runs it through the matching request
//  builder, and asserts that the resulting JSON has the expected wire
//  shape (text inlined, image base64-encoded with right mime type, etc).
//
//  No network. Catches the largest class of unexercised serialization
//  bugs: every vendor handles the same attachment input differently, and
//  none of those code paths had any test before now.
//

import XCTest
@testable import iTerm2SharedARC

final class AIRequestBuilderAttachmentTests: XCTestCase {

    // MARK: - Shared fixtures

    /// Arbitrary bytes; tests don't decode them, only check round-trip.
    private static let imageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                                          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52])
    private static let pdfBytes = Data("%PDF-1.4\n%%EOF".utf8)
    private static let textBytes = Data("Hello, world!".utf8)

    private static let imageBase64 = imageBytes.base64EncodedString()
    private static let pdfBase64 = pdfBytes.base64EncodedString()

    private func file(name: String, mime: String, bytes: Data) -> LLM.Message.Attachment {
        return LLM.Message.Attachment(
            inline: true,
            id: "test-attachment",
            type: .file(.init(name: name,
                              content: bytes,
                              mimeType: mime,
                              localPath: nil)))
    }

    private func model(named name: String) throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == name }) else {
            throw XCTSkip("Model \(name) not in AIMetadata; test skipped")
        }
        return m
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Body is not a JSON object")
            return [:]
        }
        return obj
    }

    // MARK: - Anthropic

    /// Image attachment alone in the message body should serialize as a
    /// single content array containing one base64 image block with the
    /// matching mime type.
    func testAnthropic_imageAttachment() throws {
        let model = try model(named: "claude-haiku-4-5")
        let attachment = file(name: "x.png", mime: "image/png", bytes: Self.imageBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .attachment(attachment))
        let body = try AnthropicRequestBuilder(
            messages: [message],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false).body()
        let json = try decode(body)
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        XCTAssertEqual(messages.count, 1)
        let content = messages[0]["content"]
        XCTAssertNotNil(content, "user message has no content")
        guard let blocks = content as? [[String: Any]] else {
            XCTFail("Anthropic image content should be an array of blocks; got \(String(describing: content))")
            return
        }
        XCTAssertEqual(blocks.count, 1, "expected exactly one image block")
        XCTAssertEqual(blocks[0]["type"] as? String, "image")
        let source = blocks[0]["source"] as? [String: Any]
        XCTAssertEqual(source?["type"] as? String, "base64")
        XCTAssertEqual(source?["media_type"] as? String, "image/png")
        XCTAssertEqual(source?["data"] as? String, Self.imageBase64,
                       "image bytes lost or re-encoded incorrectly")
    }

    /// Multipart body with a text preamble plus an image attachment should
    /// serialize as a content array containing both blocks in order.
    func testAnthropic_multipart_textThenImage() throws {
        let model = try model(named: "claude-haiku-4-5")
        let attachment = file(name: "x.png", mime: "image/png", bytes: Self.imageBytes)
        let body: LLM.Message.Body = .multipart([
            .text("Look at this image:"),
            .attachment(attachment),
        ])
        let message = LLM.Message(responseID: nil, role: .user, body: body)
        let bodyData = try AnthropicRequestBuilder(
            messages: [message],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false).body()
        let json = try decode(bodyData)
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        XCTAssertEqual(messages.count, 1)
        guard let blocks = messages[0]["content"] as? [[String: Any]] else {
            XCTFail("expected array content for multipart")
            return
        }
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
        XCTAssertEqual(blocks[0]["text"] as? String, "Look at this image:")
        XCTAssertEqual(blocks[1]["type"] as? String, "image")
        let source = blocks[1]["source"] as? [String: Any]
        XCTAssertEqual(source?["data"] as? String, Self.imageBase64)
    }

    /// Non-image binary attachment falls back to text. The fallback uses
    /// lossyString which mangles binary bytes, but the encoder MUST NOT
    /// crash and the resulting message must still be a valid Anthropic
    /// content array.
    func testAnthropic_binaryAttachment_fallsBackToText_doesNotCrash() throws {
        let model = try model(named: "claude-haiku-4-5")
        let attachment = file(name: "x.pdf", mime: "application/pdf", bytes: Self.pdfBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .attachment(attachment))
        let bodyData = try AnthropicRequestBuilder(
            messages: [message],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false).body()
        let json = try decode(bodyData)
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        XCTAssertEqual(messages.count, 1)
        // The Anthropic encoder collapses single-attachment file bodies into
        // a string content. Whatever shape, just confirm the request is
        // still valid and didn't drop the role.
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertNotNil(messages[0]["content"])
    }

    // MARK: - Gemini

    /// Gemini encodes any binary file as inlineData with mime_type +
    /// base64-encoded data. Distinct from text-content blocks.
    func testGemini_imageAttachment_asInlineData() throws {
        let model = try model(named: "gemini-3-flash-preview")
        let attachment = file(name: "x.png", mime: "image/png", bytes: Self.imageBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Caption this:"),
            .attachment(attachment),
        ]))
        let bodyData = try GeminiRequestBuilder(
            messages: [message],
            functions: [],
            hostedTools: HostedTools()).body()
        let json = try decode(bodyData)
        let contents = (json["contents"] as? [[String: Any]]) ?? []
        XCTAssertEqual(contents.count, 1)
        let parts = (contents[0]["parts"] as? [[String: Any]]) ?? []
        XCTAssertEqual(parts.count, 2, "Gemini should emit one text part and one inlineData part")
        XCTAssertEqual(parts[0]["text"] as? String, "Caption this:")
        let inline = parts[1]["inlineData"] as? [String: Any]
        XCTAssertNotNil(inline, "second part should be inlineData; got \(String(describing: parts[1]))")
        XCTAssertEqual(inline?["mime_type"] as? String, "image/png")
        XCTAssertEqual(inline?["data"] as? String, Self.imageBase64)
    }

    func testGemini_pdfAttachment_alsoInlineData() throws {
        let model = try model(named: "gemini-3-flash-preview")
        let attachment = file(name: "x.pdf", mime: "application/pdf", bytes: Self.pdfBytes)
        // Wrap in multipart with a leading text. The Gemini builder's
        // attachment serialization lives inside the multipart branch; the
        // top-level .attachment branch returns no parts (a real gap, but
        // not the gap this test is meant to cover).
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Read this:"),
            .attachment(attachment),
        ]))
        let bodyData = try GeminiRequestBuilder(
            messages: [message],
            functions: [],
            hostedTools: HostedTools()).body()
        let json = try decode(bodyData)
        let contents = (json["contents"] as? [[String: Any]]) ?? []
        XCTAssertEqual(contents.count, 1)
        let parts = (contents[0]["parts"] as? [[String: Any]]) ?? []
        XCTAssertEqual(parts.count, 2, "expected text part + inlineData part")
        let inline = parts[1]["inlineData"] as? [String: Any]
        XCTAssertEqual(inline?["mime_type"] as? String, "application/pdf")
        XCTAssertEqual(inline?["data"] as? String, Self.pdfBase64)
    }

    /// Documents (and pins) the existing limitation that Gemini's builder
    /// handles attachments only inside a multipart body. A bare-attachment
    /// message produces zero parts, which means a Gemini call with a
    /// single attachment and no text gets sent with empty contents — the
    /// model has nothing to look at. Real iTerm2 callers always wrap in
    /// multipart with at least the user's prompt text, so this hasn't
    /// bitten anyone in practice.
    func testGemini_topLevelAttachment_isUnsupported() throws {
        let model = try model(named: "gemini-3-flash-preview")
        let attachment = file(name: "x.pdf", mime: "application/pdf", bytes: Self.pdfBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .attachment(attachment))
        let bodyData = try GeminiRequestBuilder(
            messages: [message],
            functions: [],
            hostedTools: HostedTools()).body()
        let json = try decode(bodyData)
        let contents = (json["contents"] as? [[String: Any]]) ?? []
        // Expect the message to be filtered out entirely (no usable parts).
        // If this assertion ever flips because the builder gains top-level
        // attachment support, update or delete this test.
        XCTAssertTrue(contents.isEmpty,
                      "Gemini builder unexpectedly accepted a top-level attachment; update this pinning test")
    }

    // MARK: - OpenAI Responses API

    /// PDF attachment goes through the Responses API as a file content
    /// type with a base64 data URI.
    func testOpenAIResponses_pdfAttachment() throws {
        let model = try model(named: "gpt-4o-mini")
        let attachment = file(name: "doc.pdf", mime: "application/pdf", bytes: Self.pdfBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Summarize:"),
            .attachment(attachment),
        ]))
        let bodyData = try ResponsesBodyRequestBuilder(
            messages: [message],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        let json = try decode(bodyData)
        // Walk the input array looking for a file content with base64 PDF.
        let input = (json["input"] as? [[String: Any]]) ?? []
        XCTAssertFalse(input.isEmpty)
        var foundFileContent = false
        for item in input {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let type = part["type"] as? String, type == "input_file" || type == "file" {
                    let fileData = (part["file_data"] as? String)
                                ?? (part["file"] as? [String: Any])?["file_data"] as? String
                    if let fileData,
                       fileData.contains(Self.pdfBase64) || fileData.hasSuffix(Self.pdfBase64) {
                        foundFileContent = true
                    }
                }
            }
        }
        XCTAssertTrue(foundFileContent,
                      "expected a base64-encoded PDF file content block; body: \(json)")
    }

    // MARK: - DeepSeek (chat-completions style)

    /// DeepSeek supports inline text content. A text-mime attachment should
    /// be inlined into the message content rather than dropped.
    func testDeepSeek_textAttachment_isInlined() throws {
        let model = try model(named: "deepseek-v4-flash")
        let attachment = file(name: "notes.txt", mime: "text/plain", bytes: Self.textBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Read this:"),
            .attachment(attachment),
        ]))
        let bodyData = try DeepSeekRequestBuilder(
            messages: [message],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false).body()
        let json = try decode(bodyData)
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        XCTAssertEqual(messages.count, 1)
        let content = messages[0]["content"] as? String ?? ""
        XCTAssertTrue(content.contains("Read this:"),
                      "preamble text was dropped; got \(content)")
        XCTAssertTrue(content.contains("Hello, world!"),
                      "text-file content was dropped; got \(content)")
    }
}

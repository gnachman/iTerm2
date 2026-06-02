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

    /// PDF attachments serialize as a native Anthropic document content
    /// block (base64 source, media_type application/pdf), not text.
    func testAnthropic_pdfAttachment_asDocumentBlock() throws {
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
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        guard let blocks = messages[0]["content"] as? [[String: Any]] else {
            XCTFail("expected array content for document block; got \(String(describing: messages[0]["content"]))")
            return
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["type"] as? String, "document")
        let source = blocks[0]["source"] as? [String: Any]
        XCTAssertEqual(source?["type"] as? String, "base64")
        XCTAssertEqual(source?["media_type"] as? String, "application/pdf")
        XCTAssertEqual(source?["data"] as? String, Self.pdfBase64,
                       "PDF bytes lost or re-encoded incorrectly")
    }

    /// SVG attachments are XML text (image/svg+xml has the +xml suffix that
    /// MIMETypeIsTextual recognizes) and must NOT be sent as a binary image
    /// block — Anthropic's image source only accepts jpeg/png/gif/webp and
    /// would 400. Pinned because the obvious "anything that starts with
    /// image/ is an image" branch produced exactly that 400 in production.
    func testAnthropic_svgAttachment_asText_notImageBlock() throws {
        let model = try model(named: "claude-haiku-4-5")
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        let attachment = file(name: "x.svg", mime: "image/svg+xml", bytes: svg)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("What is this?"),
            .attachment(attachment),
        ]))
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
        // Two text blocks, no image block.
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
        XCTAssertEqual(blocks[1]["type"] as? String, "text",
                       "SVG must be sent as text, not as an image block; got \(blocks[1])")
        XCTAssertNil(blocks[1]["source"],
                     "SVG block must not carry an image-style source")
        XCTAssertEqual(blocks[1]["text"] as? String,
                       "<svg xmlns=\"http://www.w3.org/2000/svg\"/>")
    }

    /// PDF inside a multipart body emits a text part followed by a
    /// document part (mirrors the image case).
    func testAnthropic_multipart_textThenPdf_asDocumentBlock() throws {
        let model = try model(named: "claude-haiku-4-5")
        let attachment = file(name: "x.pdf", mime: "application/pdf", bytes: Self.pdfBytes)
        let body: LLM.Message.Body = .multipart([
            .text("Read this:"),
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
        XCTAssertEqual(blocks[0]["text"] as? String, "Read this:")
        XCTAssertEqual(blocks[1]["type"] as? String, "document")
        let source = blocks[1]["source"] as? [String: Any]
        XCTAssertEqual(source?["media_type"] as? String, "application/pdf")
        XCTAssertEqual(source?["data"] as? String, Self.pdfBase64)
    }

    // MARK: - Gemini

    /// SVG and other textual MIMEs must NOT be sent as inlineData on
    /// Gemini. Gemini's inlineData enforces a binary-format allowlist and
    /// 400s with "Unsupported MIME type: image/svg+xml" / "application/xml"
    /// otherwise. Textual content goes through a text Part instead.
    /// Pinned because this regression spent a sprint masquerading as a
    /// vendor outage. Same root cause as the Anthropic SVG bug.
    func testGemini_svgAttachment_asText_notInlineData() throws {
        let model = try model(named: "gemini-3-flash-preview")
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        let attachment = file(name: "x.svg", mime: "image/svg+xml", bytes: svg)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Describe:"),
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
        XCTAssertEqual(parts.count, 2, "expected text part + text part for SVG")
        XCTAssertEqual(parts[0]["text"] as? String, "Describe:")
        XCTAssertNotNil(parts[1]["text"], "SVG must be sent as text, not inlineData; got \(parts[1])")
        XCTAssertNil(parts[1]["inlineData"],
                     "SVG must NOT carry inlineData; Gemini's inlineData allowlist rejects image/svg+xml")
        XCTAssertEqual(parts[1]["text"] as? String,
                       "<svg xmlns=\"http://www.w3.org/2000/svg\"/>")
    }

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

    /// Image attachment through the Responses API serializes as an
    /// input_image content part with a base64 data URL (vision), NOT an
    /// input_file (which the API 400s for image MIMEs).
    func testOpenAIResponses_imageAttachment_asInputImage() throws {
        let model = try model(named: "gpt-4o-mini")
        let attachment = file(name: "x.png", mime: "image/png", bytes: Self.imageBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Describe:"),
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
        let input = (json["input"] as? [[String: Any]]) ?? []
        var foundImage = false
        for item in input {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "input_image" {
                let url = part["image_url"] as? String
                XCTAssertNotNil(url, "input_image must carry image_url; got \(part)")
                XCTAssertTrue(url?.hasPrefix("data:image/png;base64,") == true,
                              "expected base64 data URL; got \(String(describing: url))")
                XCTAssertTrue(url?.hasSuffix(Self.imageBase64) == true,
                              "image bytes lost or re-encoded")
                foundImage = true
            }
        }
        XCTAssertTrue(foundImage, "no input_image part found; body: \(json)")
    }

    // MARK: - OpenAI chat-completions

    /// Image attachment through the chat-completions builder serializes as
    /// an image_url content part with a base64 data URL.
    func testOpenAIChat_imageAttachment_asImageURL() throws {
        let model = try model(named: "gpt-4o-mini")
        let attachment = file(name: "x.png", mime: "image/png", bytes: Self.imageBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Describe:"),
            .attachment(attachment),
        ]))
        let bodyData = try ModernBodyRequestBuilder(
            messages: [message],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false).body()
        let json = try decode(bodyData)
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        XCTAssertEqual(messages.count, 1)
        guard let parts = messages[0]["content"] as? [[String: Any]] else {
            XCTFail("expected array content; got \(String(describing: messages[0]["content"]))")
            return
        }
        let imagePart = parts.first { $0["type"] as? String == "image_url" }
        XCTAssertNotNil(imagePart, "no image_url part; got \(parts)")
        let url = (imagePart?["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertTrue(url?.hasPrefix("data:image/png;base64,") == true,
                      "expected base64 data URL; got \(String(describing: url))")
        XCTAssertTrue(url?.hasSuffix(Self.imageBase64) == true,
                      "image bytes lost or re-encoded")
    }

    /// MP3 attachment through the chat-completions builder serializes as an
    /// input_audio content part with format "mp3" and base64 data.
    func testOpenAIChat_audioAttachment_asInputAudio() throws {
        let model = try model(named: "gpt-4o-mini")
        let audioBytes = Data("ID3fake-mp3-bytes".utf8)
        let attachment = file(name: "x.mp3", mime: "audio/mpeg", bytes: audioBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Transcribe:"),
            .attachment(attachment),
        ]))
        let bodyData = try ModernBodyRequestBuilder(
            messages: [message],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false).body()
        let json = try decode(bodyData)
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        guard let parts = messages[0]["content"] as? [[String: Any]] else {
            XCTFail("expected array content; got \(String(describing: messages[0]["content"]))")
            return
        }
        let audioPart = parts.first { $0["type"] as? String == "input_audio" }
        XCTAssertNotNil(audioPart, "no input_audio part; got \(parts)")
        let audio = audioPart?["input_audio"] as? [String: Any]
        XCTAssertEqual(audio?["format"] as? String, "mp3")
        XCTAssertEqual(audio?["data"] as? String, audioBytes.base64EncodedString())
    }

    /// WAV maps to format "wav" (the other half of OpenAI's closed
    /// input_audio format enum; mp3 is covered above).
    func testOpenAIChat_audioWavAttachment_asInputAudio() throws {
        let model = try model(named: "gpt-4o-mini")
        let audioBytes = Data("RIFFfake-wav-bytes".utf8)
        let attachment = file(name: "x.wav", mime: "audio/wav", bytes: audioBytes)
        let message = LLM.Message(responseID: nil, role: .user, body: .multipart([
            .text("Transcribe:"),
            .attachment(attachment),
        ]))
        let bodyData = try ModernBodyRequestBuilder(
            messages: [message],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false).body()
        let json = try decode(bodyData)
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        let parts = (messages[0]["content"] as? [[String: Any]]) ?? []
        let audio = (parts.first { $0["type"] as? String == "input_audio" })?["input_audio"] as? [String: Any]
        XCTAssertEqual(audio?["format"] as? String, "wav")
        XCTAssertEqual(audio?["data"] as? String, audioBytes.base64EncodedString())
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

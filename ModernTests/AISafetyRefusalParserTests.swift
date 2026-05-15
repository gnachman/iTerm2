//
//  AISafetyRefusalParserTests.swift
//  iTerm2 ModernTests
//
//  Drives every captured refusal fixture through the matching response
//  parser and asserts that the resulting LLM.Message:
//    1. is produced (parser doesn't throw or return nil),
//    2. has non-empty content (the refusal explanation isn't dropped on
//       the floor by a parser that doesn't recognize the response shape).
//
//  This is the parser-side counterpart to AILiveHarness's refusal scenario:
//  the harness captures real wire data; this test replays it offline.
//  Catches "I added a model and the parser silently strips its refusal
//  text" regressions without spending API money.
//
//  Covers both non-streaming (single JSON body) and streaming (replay of
//  captured SSE chunks through the matching streaming parser, accumulating
//  via Body.tryAppend the same way AITermController does at runtime).
//  Streaming is where most parser bugs hide so the offline coverage is
//  worth the slightly heavier setup.
//

import XCTest
@testable import iTerm2SharedARC

final class AISafetyRefusalParserTests: XCTestCase {
    func testEachNonStreamingFixtureProducesNonEmptyMessage() throws {
        let fixturesDir = AISafetyRefusalParserTests.fixturesDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: fixturesDir, includingPropertiesForKeys: nil)
        let nonStreaming = files
            .filter { $0.lastPathComponent.hasSuffix("_noStream.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(nonStreaming.isEmpty,
                       "No non-streaming refusal fixtures under \(fixturesDir.path).")

        var failures: [String] = []

        for url in nonStreaming {
            let filename = url.lastPathComponent
            guard let parsed = parseFilename(filename) else {
                failures.append("\(filename): malformed filename")
                continue
            }

            let json: [String: Any]
            do {
                let data = try Data(contentsOf: url)
                json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            } catch {
                failures.append("\(filename): unreadable JSON (\(error))")
                continue
            }

            guard let response = json["response"] as? [String: Any] else {
                failures.append("\(filename): no response object")
                continue
            }

            // Skip captures whose request itself failed (rate limit, model
            // not found, transient 5xx). They carry no refusal payload to
            // exercise the parser against; treating them as test failures
            // poisons the suite on whatever vendor was unhealthy the day
            // the fixture was refreshed.
            if response["error"] != nil {
                continue
            }

            // The body in the fixture was already parsed-as-JSON for
            // readability when serialized; re-encode it for the parser.
            let bodyData: Data
            if let bodyDict = response["body"] as? [String: Any] {
                do {
                    bodyData = try JSONSerialization.data(withJSONObject: bodyDict)
                } catch {
                    failures.append("\(parsed.vendor)/\(parsed.model): re-encode failed (\(error))")
                    continue
                }
            } else if let bodyString = response["body"] as? String {
                bodyData = Data(bodyString.utf8)
            } else {
                failures.append("\(parsed.vendor)/\(parsed.model): response.body is missing or unsupported type")
                continue
            }

            let messages: [LLM.Message]
            do {
                messages = try AISafetyRefusalParserTests.parseBody(
                    vendor: parsed.vendor, body: bodyData)
            } catch {
                failures.append("\(parsed.vendor)/\(parsed.model): parser threw \(error)")
                continue
            }

            guard !messages.isEmpty else {
                failures.append("\(parsed.vendor)/\(parsed.model): parser returned no messages; refusal silently dropped")
                continue
            }

            // Concatenate content across all messages: Anthropic in particular
            // returns multiple message-shaped items (text + maybe more); the
            // assistant-visible text is the union.
            let combined = messages
                .compactMap { $0.body.maybeContent }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if combined.isEmpty {
                failures.append("\(parsed.vendor)/\(parsed.model): produced messages but combined content is empty")
                continue
            }
        }

        if !failures.isEmpty {
            print("\n[AISafetyRefusalParserTests] failures:")
            for f in failures {
                print("  - \(f)")
            }
            print("")
            XCTFail("\(failures.count) refusal fixture(s) failed parsing; see stdout for details.")
        }
    }

    func testEachStreamingFixtureProducesNonEmptyMessage() throws {
        let fixturesDir = AISafetyRefusalParserTests.fixturesDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: fixturesDir, includingPropertiesForKeys: nil)
        let streaming = files
            .filter { $0.lastPathComponent.hasSuffix("_stream.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(streaming.isEmpty,
                       "No streaming refusal fixtures under \(fixturesDir.path).")

        var failures: [String] = []

        for url in streaming {
            let filename = url.lastPathComponent
            guard let parsed = parseFilename(filename) else {
                failures.append("\(filename): malformed filename")
                continue
            }

            let json: [String: Any]
            do {
                let data = try Data(contentsOf: url)
                json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            } catch {
                failures.append("\(filename): unreadable JSON (\(error))")
                continue
            }

            // Skip captures whose streaming request itself failed (rate
            // limit, transient 5xx, model unavailable). The "chunk" they
            // carry is an HTTP error envelope, not refusal-shaped SSE.
            if let response = json["response"] as? [String: Any],
               response["error"] != nil {
                continue
            }

            guard let chunks = json["streamChunks"] as? [String], !chunks.isEmpty else {
                // Some reasoning models (o3, o3-pro) honor stream=true at the
                // API level but never emit text deltas. The response arrives
                // as a single completed event. They have no streaming-shaped
                // wire data to test, so skip them rather than fail. The
                // non-streaming test already covers their response shape.
                continue
            }

            let combinedSSE = chunks.joined()

            do {
                let content = try AISafetyRefusalParserTests.driveStreamingParser(
                    vendor: parsed.vendor, sse: combinedSSE)
                if content.isEmpty {
                    failures.append("\(parsed.vendor)/\(parsed.model): streaming parser produced empty content")
                }
            } catch {
                failures.append("\(parsed.vendor)/\(parsed.model): streaming parser threw \(error)")
            }
        }

        if !failures.isEmpty {
            print("\n[AISafetyRefusalParserTests] streaming failures:")
            for f in failures {
                print("  - \(f)")
            }
            print("")
            XCTFail("\(failures.count) streaming refusal fixture(s) failed parsing; see stdout for details.")
        }
    }

    // MARK: - Helpers

    private struct ParsedFilename {
        let vendor: String
        let model: String
    }

    private func parseFilename(_ name: String) -> ParsedFilename? {
        // Format: <vendor>_<model>_refusal_<mode>_<seq>.json
        // <model> can contain underscores after sanitize; split on "_refusal_".
        guard let refusalRange = name.range(of: "_refusal_") else {
            return nil
        }
        let prefix = String(name[..<refusalRange.lowerBound])
        guard let firstUnderscore = prefix.firstIndex(of: "_") else {
            return nil
        }
        let vendor = String(prefix[..<firstUnderscore])
        let model = String(prefix[prefix.index(after: firstUnderscore)...])
        guard !vendor.isEmpty, !model.isEmpty else {
            return nil
        }
        return ParsedFilename(vendor: vendor, model: model)
    }

    private static func parseBody(vendor: String, body: Data) throws -> [LLM.Message] {
        switch vendor {
        case "anthropic":
            var parser = AnthropicResponseParser()
            return (try parser.parse(data: body))?.choiceMessages ?? []
        case "openai":
            // All current AIMetadata OpenAI models use the Responses API.
            // If chat-completions or legacy completions models ever land in
            // AIMetadata, this dispatch needs to look at the captured request
            // URL to pick the right parser.
            var parser = ResponsesResponseParser()
            return (try parser.parse(data: body))?.choiceMessages ?? []
        case "gemini":
            var parser = LLMGeminiResponseParser()
            return (try parser.parse(data: body))?.choiceMessages ?? []
        case "deepseek":
            var parser = DeepSeekResponseParser()
            return (try parser.parse(data: body))?.choiceMessages ?? []
        default:
            return []
        }
    }

    /// Drive the streaming parser for a vendor over a full captured SSE
    /// stream, accumulating the resulting choiceMessages into a single
    /// LLM.Message.Body via the same tryAppend logic AITermController uses.
    /// Returns the final accumulated content string (trimmed). Throws if
    /// any individual chunk fails to parse.
    private static func driveStreamingParser(vendor: String, sse: String) throws -> String {
        switch vendor {
        case "anthropic":
            var p = AnthropicStreamingResponseParser()
            return try drive(parser: &p, sse: sse)
        case "openai":
            var p = ResponsesResponseStreamingParser()
            return try drive(parser: &p, sse: sse)
        case "gemini":
            var p = LLMGeminiStreamingResponseParser()
            return try drive(parser: &p, sse: sse)
        case "deepseek":
            var p = DeepSeekStreamingResponseParser()
            return try drive(parser: &p, sse: sse)
        default:
            return ""
        }
    }

    private static func drive<P: LLMStreamingResponseParser>(
        parser: inout P, sse: String) throws -> String {
        var accumulator = LLM.Message.Body.uninitialized
        var (first, rest) = parser.splitFirstJSONEvent(from: sse)
        while let event = first {
            if event != "[DONE]", let data = event.data(using: .utf8) {
                if let response = try parser.parse(data: data) {
                    for choice in response.choiceMessages {
                        accumulator.append(choice.body)
                    }
                }
            }
            (first, rest) = parser.splitFirstJSONEvent(from: rest)
        }
        return (accumulator.maybeContent ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fixturesDirectory() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("SafetyRefusalFixtures")
    }
}

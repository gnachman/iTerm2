//
//  AICassetteReplayTests.swift
//  iTerm2 ModernTests
//
//  Exercises the production replay seam end to end and offline: a cassette
//  written to disk is served back through iTermAIClient.request without
//  touching the plugin or network. Covers non-streaming and streaming hits
//  and the strict replay-mode miss. Not gated by the live-harness config.
//

import XCTest
@testable import iTerm2SharedARC

final class AICassetteReplayTests: XCTestCase {
    private var tempDir: URL!
    private var session: AICassetteSession!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AICassetteReplayTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        session?.uninstall()
        session = nil
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeRequest(body: String) -> WebRequest {
        WebRequest(headers: ["Content-Type": "application/json"],
                   method: "POST",
                   body: .string(body),
                   url: "https://api.example.com/v1/chat")
    }

    private func installSession(mode: AICassetteMode) -> AICassetteCanonicalizer {
        let canon = AICassetteCanonicalizer(secrets: [])
        session = AICassetteSession(
            mode: mode,
            store: AICassetteStore(directory: tempDir),
            canon: canon)
        session.install()
        return canon
    }

    func testNonStreamingReplayHit() {
        let canon = installSession(mode: .replay)
        let request = makeRequest(body: "{\"input\":\"hi\"}")
        let key = canon.canonicalize(request).key
        AICassetteStore(directory: tempDir).save(
            AICassette(key: key, canonicalRequest: "x", streaming: false,
                       streamChunks: [],
                       response: WebResponse(data: "RECORDED-BODY", error: nil),
                       errorReason: nil))

        let exp = expectation(description: "replay")
        var got: Result<WebResponse, PluginError>?
        _ = iTermAIClient.instance.request(webRequest: request, stream: nil) {
            got = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        guard case .success(let response)? = got else {
            return XCTFail("expected success, got \(String(describing: got))")
        }
        XCTAssertEqual(response.data, "RECORDED-BODY")
    }

    func testStreamingReplayHit() {
        let canon = installSession(mode: .replay)
        let request = makeRequest(body: "{\"input\":\"stream\"}")
        let key = canon.canonicalize(request).key
        AICassetteStore(directory: tempDir).save(
            AICassette(key: key, canonicalRequest: "x", streaming: true,
                       streamChunks: ["chunk-a", "chunk-b", "chunk-c"],
                       response: WebResponse(data: "chunk-achunk-bchunk-c", error: nil),
                       errorReason: nil))

        let exp = expectation(description: "stream replay")
        var chunks: [String] = []
        _ = iTermAIClient.instance.request(
            webRequest: request,
            stream: { chunks.append($0) }) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(chunks, ["chunk-a", "chunk-b", "chunk-c"])
    }

    func testReplayMissFailsOffline() {
        _ = installSession(mode: .replay)
        // No cassette saved for this request.
        let request = makeRequest(body: "{\"input\":\"never-recorded\"}")

        let exp = expectation(description: "miss")
        var got: Result<WebResponse, PluginError>?
        _ = iTermAIClient.instance.request(webRequest: request, stream: nil) {
            got = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        guard case .failure(let error)? = got else {
            return XCTFail("expected failure on miss, got \(String(describing: got))")
        }
        XCTAssertTrue(error.reason.contains("CASSETTE MISS"),
                      "unexpected reason: \(error.reason)")
    }

    // Regression: OpenAI streaming delivers a capacity/quota error as an SSE
    // content event (HTTP 200, error in the body), not as an error status.
    // recordIfNeeded must treat that as transient and NOT cache it, or the
    // error replays forever. This is the bug that poisoned 31 cassettes.
    func testErrorDeliveredAsStreamContentIsNotRecorded() {
        let canon = AICassetteCanonicalizer(secrets: [])
        let store = AICassetteStore(directory: tempDir)
        let session = AICassetteSession(mode: .auto, store: store, canon: canon)
        let request = makeRequest(body: "{\"input\":\"echo\"}")
        let key = canon.canonicalize(request).key
        let capture = iTermAIClient.LiveCapture(
            request: request,
            streaming: true,
            streamChunks: [
                "event: response.created\ndata: {\"type\":\"response.created\"}",
                "data: {\"error\":{\"code\":\"insufficient_quota\",\"message\":\"You exceeded your current quota\"}}"],
            response: WebResponse(
                data: "data: {\"error\":{\"code\":\"insufficient_quota\"}}", error: nil),
            error: nil,
            elapsed: 0)
        session.recordIfNeeded(capture: capture)
        XCTAssertFalse(store.exists(key: key),
                       "error delivered as stream content must not be recorded")
    }

    func testCleanStreamingResponseIsRecorded() {
        let canon = AICassetteCanonicalizer(secrets: [])
        let store = AICassetteStore(directory: tempDir)
        let session = AICassetteSession(mode: .auto, store: store, canon: canon)
        let request = makeRequest(body: "{\"input\":\"echo clean\"}")
        let key = canon.canonicalize(request).key
        let capture = iTermAIClient.LiveCapture(
            request: request,
            streaming: true,
            streamChunks: [
                "data: {\"delta\":\"hello\"}",
                "data: {\"type\":\"response.completed\"}"],
            response: WebResponse(data: "hello world", error: nil),
            error: nil,
            elapsed: 0)
        session.recordIfNeeded(capture: capture)
        XCTAssertTrue(store.exists(key: key), "a clean response must be recorded")
    }
}

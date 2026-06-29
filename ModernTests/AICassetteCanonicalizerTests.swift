//
//  AICassetteCanonicalizerTests.swift
//  iTerm2 ModernTests
//
//  Pins the cassette canonicalizer: the property the whole record/playback
//  layer rests on is that two runs which build the same logical request
//  hash to the same key once the per-run noise (API keys, UUIDs, JSON key
//  ordering, multipart boundary) is stripped, while genuinely different
//  requests do not collide. These run offline and are not gated by the
//  live-harness config.
//

import XCTest
@testable import iTerm2SharedARC

final class AICassetteCanonicalizerTests: XCTestCase {
    private func key(_ request: WebRequest, secrets: [String]) -> String {
        AICassetteCanonicalizer(secrets: secrets).canonicalize(request).key
    }

    func testDifferentApiKeySameRequestSameKey() {
        let a = WebRequest(
            headers: ["Authorization": "Bearer sk-AAAAAAAAAAAAAAAA",
                      "Content-Type": "application/json"],
            method: "POST",
            body: .string("{\"model\":\"x\",\"input\":\"hi\"}"),
            url: "https://api.example.com/v1/chat")
        let b = WebRequest(
            headers: ["Authorization": "Bearer sk-BBBBBBBBBBBBBBBBBB",
                      "Content-Type": "application/json"],
            method: "POST",
            body: .string("{\"model\":\"x\",\"input\":\"hi\"}"),
            url: "https://api.example.com/v1/chat")
        XCTAssertEqual(key(a, secrets: ["sk-AAAAAAAAAAAAAAAA"]),
                       key(b, secrets: ["sk-BBBBBBBBBBBBBBBBBB"]))
    }

    func testJsonKeyOrderDoesNotAffectKey() {
        let a = WebRequest(headers: [:], method: "POST",
                           body: .string("{\"a\":1,\"b\":2,\"c\":[1,2,3]}"),
                           url: "https://x/y")
        let b = WebRequest(headers: [:], method: "POST",
                           body: .string("{\"c\":[1,2,3],\"b\":2,\"a\":1}"),
                           url: "https://x/y")
        XCTAssertEqual(key(a, secrets: []), key(b, secrets: []))
    }

    func testGeminiUrlKeyRedacted() {
        let a = WebRequest(headers: [:], method: "POST", body: .string("{}"),
                           url: "https://g/v1/m:generateContent?key=AIzaAAAA&alt=sse")
        let b = WebRequest(headers: [:], method: "POST", body: .string("{}"),
                           url: "https://g/v1/m:generateContent?key=AIzaBBBB&alt=sse")
        XCTAssertEqual(key(a, secrets: ["AIzaAAAA"]), key(b, secrets: ["AIzaBBBB"]))
    }

    func testDifferentBodyDifferentKey() {
        let a = WebRequest(headers: [:], method: "POST",
                           body: .string("{\"input\":\"hello\"}"), url: "https://x/y")
        let b = WebRequest(headers: [:], method: "POST",
                           body: .string("{\"input\":\"goodbye\"}"), url: "https://x/y")
        XCTAssertNotEqual(key(a, secrets: []), key(b, secrets: []))
    }

    func testUuidInBodyAndHeaderCollapsesAcrossRuns() {
        // A request whose body and a header both carry the same fresh UUID
        // (the multipart-boundary shape) must canonicalize identically no
        // matter which UUID each run minted.
        func make(_ uuid: String) -> WebRequest {
            WebRequest(
                headers: ["Content-Type": "multipart/form-data; boundary=Boundary-\(uuid)"],
                method: "POST",
                body: .string("--Boundary-\(uuid)\r\nbody\r\n--Boundary-\(uuid)--"),
                url: "https://x/upload")
        }
        let u1 = "11111111-1111-1111-1111-111111111111"
        let u2 = "22222222-2222-2222-2222-222222222222"
        XCTAssertEqual(key(make(u1), secrets: []), key(make(u2), secrets: []))
    }

    func testMultipartBytesBoundaryNeutralizedButContentDistinguished() {
        func multipart(boundary: String, payload: [UInt8]) -> WebRequest {
            var bytes = Array("--\(boundary)\r\nContent-Type: image/png\r\n\r\n".utf8)
            bytes.append(contentsOf: payload)
            bytes.append(contentsOf: Array("\r\n--\(boundary)--\r\n".utf8))
            return WebRequest(
                headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                method: "POST",
                body: .bytes(bytes),
                url: "https://x/files")
        }
        let payload: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02]
        // Same file, different random boundary -> same key.
        XCTAssertEqual(
            key(multipart(boundary: "Boundary-AAAA", payload: payload), secrets: []),
            key(multipart(boundary: "Boundary-BBBB", payload: payload), secrets: []))
        // Different file bytes -> different key.
        XCTAssertNotEqual(
            key(multipart(boundary: "Boundary-AAAA", payload: payload), secrets: []),
            key(multipart(boundary: "Boundary-AAAA", payload: payload + [0xFF]), secrets: []))
    }
}

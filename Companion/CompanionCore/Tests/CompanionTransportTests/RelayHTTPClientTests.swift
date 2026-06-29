//
//  RelayHTTPClientTests.swift
//  CompanionCore
//
//  Pins the wire request the production URLSessionRelayHTTPClient sends, using a
//  URLProtocol stub so a real URLSession (and the real JSON/body/header path)
//  runs without a network. The relay Worker reads x-relay-room and a JSON body;
//  if this drifts, attestation silently breaks, so assert it directly.
//

import XCTest
@testable import CompanionTransport

/// Captures the outbound request and replays a canned response. URLSession
/// streams httpBody, so the body is read from httpBodyStream.
final class StubURLProtocol: URLProtocol {
    struct Captured: @unchecked Sendable {
        var method: String?
        var roomHeader: String?
        var contentType: String?
        var url: URL?
        var body: Data?
    }
    nonisolated(unsafe) static var captured: Captured?
    nonisolated(unsafe) static var responseStatus = 200
    nonisolated(unsafe) static var responseBody = Data("{\"ok\":true}".utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var c = Captured()
        c.method = request.httpMethod
        c.roomHeader = request.value(forHTTPHeaderField: "x-relay-room")
        c.contentType = request.value(forHTTPHeaderField: "Content-Type")
        c.url = request.url
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            c.body = data
        } else {
            c.body = request.httpBody
        }
        Self.captured = c

        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseStatus,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RelayHTTPClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func setUp() {
        StubURLProtocol.captured = nil
        StubURLProtocol.responseStatus = 200
        StubURLProtocol.responseBody = Data("{\"ok\":true}".utf8)
    }

    func test_post_withBody_setsMethodRoomHeaderAndJSON() async throws {
        let client = URLSessionRelayHTTPClient(origin: "https://relay.example", session: makeSession())
        StubURLProtocol.responseStatus = 200
        StubURLProtocol.responseBody = Data("{\"ok\":true,\"ticket\":\"t1\"}".utf8)

        let (status, body) = try await client.post(
            path: "/attest", roomName: "the-room",
            json: ["challenge": "abc", "attestationObject": "def"])

        XCTAssertEqual(status, 200)
        let cap = try XCTUnwrap(StubURLProtocol.captured)
        XCTAssertEqual(cap.method, "POST")
        XCTAssertEqual(cap.url?.absoluteString, "https://relay.example/attest")
        XCTAssertEqual(cap.roomHeader, "the-room")
        XCTAssertEqual(cap.contentType, "application/json")
        let json = try JSONSerialization.jsonObject(with: try XCTUnwrap(cap.body)) as? [String: String]
        XCTAssertEqual(json?["challenge"], "abc")
        XCTAssertEqual(json?["attestationObject"], "def")
        XCTAssertEqual(String(data: body, encoding: .utf8), "{\"ok\":true,\"ticket\":\"t1\"}")
    }

    func test_post_withoutBody_sendsNoContentTypeAndPropagatesStatus() async throws {
        let client = URLSessionRelayHTTPClient(origin: "https://relay.example", session: makeSession())
        StubURLProtocol.responseStatus = 429

        let (status, _) = try await client.post(path: "/attest/challenge", roomName: "r", json: nil)

        XCTAssertEqual(status, 429)
        let cap = try XCTUnwrap(StubURLProtocol.captured)
        XCTAssertEqual(cap.roomHeader, "r")
        XCTAssertNil(cap.contentType, "a bodyless GET-style POST carries no JSON content type")
        XCTAssertNil(cap.body)
    }

    func test_post_invalidOrigin_throws() async throws {
        let client = URLSessionRelayHTTPClient(origin: "ht tp://bad origin", session: makeSession())
        do {
            _ = try await client.post(path: "/attest/challenge", roomName: "r", json: nil)
            XCTFail("an unparseable origin must throw")
        } catch let error as RelayAttestationError {
            XCTAssertEqual(error, .invalidOrigin)
        }
    }
}

//
//  CompanionURLSessionTests.swift
//  CompanionCore
//
//  The companion session must REFUSE HTTP redirects: no relay/push endpoint
//  legitimately returns a 3xx, and following one would re-send egress to a
//  server-named host. These pin both halves: the delegate declines a redirect
//  (hands back nil instead of the proposed cross-host request), and the session
//  CompanionURLSession builds is actually wired with that delegate.
//

import XCTest
@testable import CompanionTransport

final class CompanionURLSessionTests: XCTestCase {
    func test_delegateDeclinesRedirect() async {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://relay.test/start")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://relay.test/start")!,
            statusCode: 302, httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://evil.test/landed"])!
        let proposed = URLRequest(url: URL(string: "https://evil.test/landed")!)

        let followed: URLRequest? = await withCheckedContinuation { continuation in
            NoRedirectSessionDelegate.shared.urlSession(
                session, task: task, willPerformHTTPRedirection: response,
                newRequest: proposed) { continuation.resume(returning: $0) }
        }

        // nil = do not follow; the cross-host request is never issued.
        XCTAssertNil(followed)
    }

    func test_companionSessionInstallsTheNoRedirectDelegate() {
        let session = CompanionURLSession.make()
        defer { session.invalidateAndCancel() }
        XCTAssertTrue(session.delegate is NoRedirectSessionDelegate)
    }

    func test_sharedSessionInstallsTheNoRedirectDelegate() {
        XCTAssertTrue(CompanionURLSession.shared.delegate is NoRedirectSessionDelegate)
    }
}

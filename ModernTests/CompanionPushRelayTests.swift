//
//  CompanionPushRelayTests.swift
//  iTerm2 ModernTests
//
//  The failover rules shared by the phone (registration) and the Mac (pushes)
//  across the push relay instances in CompanionPushRelay.baseURLs.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionPushRelayTests: XCTestCase {
    // MARK: - shouldTryNextInstance

    func testTransportErrorTriesNext() {
        XCTAssertTrue(CompanionPushRelay.shouldTryNextInstance(afterStatus: nil, relayAnswered: false))
    }

    func testRelaysBadRequestAndRateLimitAreFinal() {
        XCTAssertFalse(CompanionPushRelay.shouldTryNextInstance(afterStatus: 400, relayAnswered: true))
        XCTAssertFalse(CompanionPushRelay.shouldTryNextInstance(afterStatus: 429, relayAnswered: true))
    }

    func testBadRequestFromSomethingElseTriesNext() {
        // A proxy, WAF, or misrouted vhost in front of the relay.
        XCTAssertTrue(CompanionPushRelay.shouldTryNextInstance(afterStatus: 400, relayAnswered: false))
        XCTAssertTrue(CompanionPushRelay.shouldTryNextInstance(afterStatus: 429, relayAnswered: false))
    }

    func testHostSpecificFailuresTryNext() {
        // 403: unknown device / bad secret on this instance, or a WAF block.
        // 404/405: a misrouted proxy. 5xx: the relay or Cloudflare's 52x.
        for status in [403, 404, 405, 500, 502, 503, 521, 522, 524] {
            XCTAssertTrue(CompanionPushRelay.shouldTryNextInstance(afterStatus: status, relayAnswered: true), "\(status)")
        }
    }

    func testRegistrationFailsOverOnARelays429() {
        // Each instance has its own per-IP register limit.
        XCTAssertTrue(CompanionPushRelay.shouldTryNextInstance(afterStatus: 429, relayAnswered: true,
                                                               finalStatuses: [400]))
        XCTAssertFalse(CompanionPushRelay.shouldTryNextInstance(afterStatus: 400, relayAnswered: true,
                                                                finalStatuses: [400]))
    }

    func testTryInOrderHonorsFinalStatuses() async {
        var attempted = [URL]()
        let outcome = await CompanionPushRelay.tryInOrder(urls, finalStatuses: [400]) { url in
            attempted.append(url)
            return attempted.count == 1 ? .failed(status: 429, relayAnswered: true) : .succeeded
        }
        XCTAssertEqual(outcome, .init(succeeded: urls[1], failedOver: true))
    }

    // MARK: - isRelayError

    func testIsRelayError() {
        XCTAssertTrue(CompanionPushRelay.isRelayError(Data(#"{"error":"bad token or secret"}"#.utf8)))
        XCTAssertFalse(CompanionPushRelay.isRelayError(Data("<html>400 Bad Request</html>".utf8)))
        XCTAssertFalse(CompanionPushRelay.isRelayError(Data(#"{"ok":true}"#.utf8)))
        XCTAssertFalse(CompanionPushRelay.isRelayError(Data()))
    }

    // MARK: - ordered

    private let urls = [
        URL(string: "https://push.iterm2.com/push")!,
        URL(string: "https://push2.iterm2.com/push")!,
        URL(string: "https://push3.iterm2.com/push")!,
    ]

    func testNoPreferenceKeepsOrder() {
        XCTAssertEqual(CompanionPushRelay.ordered(urls, preferringHost: nil), urls)
    }

    func testPreferredHostMovesToFront() {
        XCTAssertEqual(CompanionPushRelay.ordered(urls, preferringHost: "push3.iterm2.com"),
                       [urls[2], urls[0], urls[1]])
    }

    func testUnknownPreferredHostKeepsOrder() {
        XCTAssertEqual(CompanionPushRelay.ordered(urls, preferringHost: "elsewhere.example"), urls)
    }

    // MARK: - tryInOrder

    /// Runs tryInOrder over `urls` with each attempt answered from `results` in
    /// order; returns the outcome and the URLs actually attempted.
    private func run(_ results: [CompanionPushRelay.AttemptResult]) async -> (CompanionPushRelay.Outcome, [URL]) {
        var attempted = [URL]()
        let outcome = await CompanionPushRelay.tryInOrder(urls) { url in
            attempted.append(url)
            return results[attempted.count - 1]
        }
        return (outcome, attempted)
    }

    func testFirstSuccessStops() async {
        let (outcome, attempted) = await run([.succeeded])
        XCTAssertEqual(outcome, .init(succeeded: urls[0], failedOver: false))
        XCTAssertEqual(attempted, [urls[0]])
    }

    func testTransportErrorFailsOver() async {
        let (outcome, attempted) = await run([.failed(status: nil, relayAnswered: false), .succeeded])
        XCTAssertEqual(outcome, .init(succeeded: urls[1], failedOver: true))
        XCTAssertEqual(attempted, [urls[0], urls[1]])
    }

    func testHostSpecificStatusesFailOver() async {
        let (outcome, attempted) = await run([.failed(status: 403, relayAnswered: true), .failed(status: 502, relayAnswered: true), .succeeded])
        XCTAssertEqual(outcome, .init(succeeded: urls[2], failedOver: true))
        XCTAssertEqual(attempted.count, 3)
    }

    func testRelaysBadRequestStopsWithoutTryingTheNext() async {
        let (outcome, attempted) = await run([.failed(status: 400, relayAnswered: true)])
        XCTAssertEqual(outcome, .init(succeeded: nil, failedOver: false))
        XCTAssertEqual(attempted, [urls[0]])
    }

    func testRateLimitAfterFailoverStops() async {
        let (outcome, attempted) = await run([.failed(status: 503, relayAnswered: true),
                                              .failed(status: 429, relayAnswered: true)])
        XCTAssertEqual(outcome, .init(succeeded: nil, failedOver: true))
        XCTAssertEqual(attempted, [urls[0], urls[1]])
    }

    func testProxyBadRequestFailsOver() async {
        let (outcome, attempted) = await run([.failed(status: 400, relayAnswered: false), .succeeded])
        XCTAssertEqual(outcome, .init(succeeded: urls[1], failedOver: true))
        XCTAssertEqual(attempted.count, 2)
    }

    func testRejectedStops() async {
        let (outcome, attempted) = await run([.rejected])
        XCTAssertEqual(outcome, .init(succeeded: nil, failedOver: false))
        XCTAssertEqual(attempted, [urls[0]])
    }

    func testAllFail() async {
        let (outcome, _) = await run([.failed(status: nil, relayAnswered: false), .failed(status: 500, relayAnswered: true), .failed(status: 404, relayAnswered: true)])
        XCTAssertEqual(outcome, .init(succeeded: nil, failedOver: true))
    }

    // MARK: - CompanionPushSender.httpStatus

    func testHTTPStatusParsesThePluginsHTTPError() {
        XCTAssertEqual(CompanionPushSender.httpStatus(pluginError: "HTTP 502"), 502)
        XCTAssertEqual(CompanionPushSender.httpStatus(pluginError: "HTTP -1"), -1)
    }

    func testHTTPStatusIsNilForATransportError() {
        XCTAssertNil(CompanionPushSender.httpStatus(pluginError: "URLError -1001: The request timed out."))
        XCTAssertNil(CompanionPushSender.httpStatus(pluginError: "something else"))
    }

    // MARK: - CompanionPushSender.isSharedAPNsRejection

    func testAPNsClientRejectionsAreShared() {
        XCTAssertTrue(CompanionPushSender.isSharedAPNsRejection(#"APNs 410: {"reason":"Unregistered"}"#))
        XCTAssertTrue(CompanionPushSender.isSharedAPNsRejection(#"APNs 400: {"reason":"BadDeviceToken"}"#))
        XCTAssertTrue(CompanionPushSender.isSharedAPNsRejection(#"APNs 429: {"reason":"TooManyRequests"}"#))
    }

    func testAPNsTopicConfigReasonsAreNotShared() {
        for reason in ["BadTopic", "TopicDisallowed", "MissingTopic", "DeviceTokenNotForTopic"] {
            XCTAssertFalse(CompanionPushSender.isSharedAPNsRejection(#"APNs 400: {"reason":"\#(reason)"}"#), reason)
        }
    }

    func testAPNsKeyAndServerErrorsAreNotShared() {
        XCTAssertFalse(CompanionPushSender.isSharedAPNsRejection(#"APNs 403: {"reason":"InvalidProviderToken"}"#))
        XCTAssertFalse(CompanionPushSender.isSharedAPNsRejection(#"APNs 503: {"reason":"ServiceUnavailable"}"#))
        XCTAssertFalse(CompanionPushSender.isSharedAPNsRejection("unknown device token"))
    }

    // MARK: - CompanionPushSender.attemptResult

    func testSharedAPNsRejectionFromTheRelayIsFinal() {
        // What the relay sends (as 422) for an uninstalled app.
        let body = #"{"error":"APNs 410: {\"reason\":\"Unregistered\"}"}"#
        XCTAssertEqual(CompanionPushSender.attemptResult(pluginError: "HTTP 422", body: body), .rejected)
    }

    func testCloudflareErrorPageFailsOver() {
        // Cloudflare's own page in place of an origin 502.
        let body = "<!DOCTYPE html><html><title>502 Bad gateway</title></html>"
        XCTAssertEqual(CompanionPushSender.attemptResult(pluginError: "HTTP 502", body: body),
                       .failed(status: 502, relayAnswered: false))
    }

    func testRelaysKeyProblemFailsOver() {
        let body = #"{"error":"APNs 403: {\"reason\":\"InvalidProviderToken\"}"}"#
        XCTAssertEqual(CompanionPushSender.attemptResult(pluginError: "HTTP 502", body: body),
                       .failed(status: 502, relayAnswered: true))
    }

    func testRelaysBadSecretIsFinal() {
        // The phone re-paired: this Mac's secret is revoked, so don't try a
        // relay that hasn't heard yet.
        XCTAssertEqual(CompanionPushSender.attemptResult(pluginError: "HTTP 403", body: #"{"error":"bad secret"}"#),
                       .rejected)
    }

    func testBadSecretOnThePreferredSecondaryTriesThePrimary() {
        // Right after a re-pair the phone registered with the primary; the
        // relay we preferred after a blip may not have the new secret yet.
        XCTAssertEqual(CompanionPushSender.attemptResult(pluginError: "HTTP 403", body: #"{"error":"bad secret"}"#,
                                                         onPreferredSecondary: true),
                       .failed(status: 403, relayAnswered: true))
    }

    func testUnknownDeviceTokenFailsOver() {
        XCTAssertEqual(CompanionPushSender.attemptResult(pluginError: "HTTP 403",
                                                         body: #"{"error":"unknown device token"}"#),
                       .failed(status: 403, relayAnswered: true))
    }

    func testRelaysBadRequestIsFinalButAProxysIsNot() {
        XCTAssertFalse(CompanionPushRelay.shouldTryNextInstance(
            afterStatus: 400, relayAnswered: CompanionPushRelay.isRelayError(Data(#"{"error":"bad token or secret"}"#.utf8))))
        XCTAssertEqual(CompanionPushSender.attemptResult(pluginError: "HTTP 400", body: "<html>400</html>"),
                       .failed(status: 400, relayAnswered: false))
    }

    func testBaseURLsArePrimaryFirst() {
        XCTAssertEqual(CompanionPushRelay.baseURLs.first?.host, "push.iterm2.com")
        XCTAssertEqual(Set(CompanionPushRelay.baseURLs.map(\.host)).count,
                       CompanionPushRelay.baseURLs.count)
    }
}

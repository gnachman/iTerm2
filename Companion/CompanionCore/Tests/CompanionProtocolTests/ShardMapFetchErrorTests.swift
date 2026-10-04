//
//  ShardMapFetchErrorTests.swift
//  CompanionCore
//
//  The error reported when no source produced a shard map. Its details are
//  shown to users, many of whom debug their own networks, so they say which
//  server failed, what happened, and what that usually means, in plain words
//  rather than error domains and codes.
//

import XCTest
import Foundation
@testable import CompanionProtocol

final class ShardMapFetchErrorTests: XCTestCase {
    private let primary = "https://resolver.iterm2.com/shardmap.json"
    private let mirror = "https://gnachman.github.io/iterm2-companion-relay/shardmap.json"

    /// A timeout shaped like the one in the field logs.
    private func fieldTimeout() -> URLError {
        let underlying = NSError(domain: "kCFErrorDomainCFNetwork", code: -1001)
        return URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "The request timed out.",
                                              NSUnderlyingErrorKey: underlying,
                                              "_kCFStreamErrorDomainKey": 4,
                                              "_kCFStreamErrorCodeKey": -2102])
    }

    private func details(_ error: Error, duration: TimeInterval? = nil) -> String {
        ShardMapFetchError(attempts: [.init(url: primary, error: error, duration: duration)]).details
    }

    func testDetailsNameEachServerByHostInOrder() {
        let text = ShardMapFetchError(attempts: [
            .init(url: primary, error: fieldTimeout(), duration: 15),
            .init(url: mirror, error: ShardMapLoaderError.httpStatus(503), duration: 0.3),
        ]).details

        XCTAssertTrue(text.contains("resolver.iterm2.com"), text)
        XCTAssertTrue(text.contains("gnachman.github.io"), text)
        XCTAssertFalse(text.contains("https://"), text)
        XCTAssertLessThan(text.range(of: "resolver.iterm2.com")!.lowerBound,
                          text.range(of: "gnachman.github.io")!.lowerBound)
    }

    func testDetailsHaveNoOpaqueErrorCodes() {
        let text = details(fieldTimeout(), duration: 15)
        for opaque in ["NSURLErrorDomain", "-1001", "kCF", "-2102", "domain", "code"] {
            XCTAssertFalse(text.contains(opaque), "\(opaque) in: \(text)")
        }
    }

    func testTimeoutSaysHowLongItWaitedAndWhatThatSuggests() {
        let text = details(fieldTimeout(), duration: 15.2)
        XCTAssertTrue(text.contains("No response after 15 seconds"), text)
        XCTAssertTrue(text.contains("firewall or filter"), text)
    }

    func testDNSFailureSaysTheLookupFailed() {
        XCTAssertTrue(details(URLError(.cannotFindHost)).contains("look up"))
        XCTAssertTrue(details(URLError(.dnsLookupFailed)).contains("look up"))
    }

    func testRefusedConnectionIsDistinguishedFromNoResponse() {
        XCTAssertTrue(details(URLError(.cannotConnectToHost)).contains("couldn’t connect"))
    }

    func testTLSAndCertificateFailuresPointAtInterception() {
        XCTAssertTrue(details(URLError(.secureConnectionFailed)).contains("secure connection"))
        XCTAssertTrue(details(URLError(.serverCertificateUntrusted)).contains("certificate"))
    }

    func testServerResponsesAreDescribed() {
        XCTAssertTrue(details(ShardMapLoaderError.httpStatus(503)).contains("HTTP 503"))
        XCTAssertTrue(details(ShardMapLoaderError.malformedMap).contains("captive portal"))
        XCTAssertTrue(details(ShardMap.ValidationError.gapOrOverlap).contains("incomplete or inconsistent"))
    }

    func testOutdatedCopyNamesBothVersions() {
        let text = details(ShardMapLoaderError.outdatedMap(served: 9, latestSeen: 10))
        XCTAssertTrue(text.contains("out of date"), text)
        XCTAssertTrue(text.contains("version 9"), text)
        XCTAssertTrue(text.contains("version 10"), text)
    }

    func testOutdatedCopyDoesNotDecideTheHeadline() {
        // The root cause is whatever happened to the other sources.
        XCTAssertTrue(ShardMapFetchError(attempts: [
            .init(url: primary, error: fieldTimeout()),
            .init(url: mirror, error: ShardMapLoaderError.outdatedMap(served: 9, latestSeen: 10)),
        ]).isNetworkFailure)
        XCTAssertFalse(ShardMapFetchError(attempts: [
            .init(url: primary, error: ShardMapLoaderError.httpStatus(503)),
            .init(url: mirror, error: ShardMapLoaderError.outdatedMap(served: 9, latestSeen: 10)),
        ]).isNetworkFailure)
    }

    func testUnknownURLErrorUsesURLSessionsText() {
        let error = URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "The server sent something odd."])
        XCTAssertTrue(details(error).contains("The server sent something odd."))
    }

    func testRequestFailedKeepsThePluginsMessage() {
        XCTAssertTrue(details(ShardMapLoaderError.requestFailed("invalid url")).contains("invalid url"))
    }

    func testIsNetworkFailureOnlyWhenEveryAttemptFailedInTheNetwork() {
        XCTAssertTrue(ShardMapFetchError(attempts: [
            .init(url: primary, error: fieldTimeout()),
            .init(url: mirror, error: URLError(.cannotConnectToHost)),
        ]).isNetworkFailure)
        // A reply that isn't a server list is usually a captive portal or proxy
        // on this network, so another network is the right advice.
        XCTAssertTrue(ShardMapFetchError(attempts: [
            .init(url: primary, error: fieldTimeout()),
            .init(url: mirror, error: ShardMapLoaderError.malformedMap),
        ]).isNetworkFailure)
        // A server answered with an error or a bad list: not the network's doing.
        XCTAssertFalse(ShardMapFetchError(attempts: [
            .init(url: primary, error: fieldTimeout()),
            .init(url: mirror, error: ShardMapLoaderError.httpStatus(503)),
        ]).isNetworkFailure)
        XCTAssertFalse(ShardMapFetchError(attempts: [
            .init(url: primary, error: ShardMap.ValidationError.gapOrOverlap),
        ]).isNetworkFailure)
        // On the Mac, network errors arrive as URLError; requestFailed is only
        // the plugin's own refusals (an invalid URL, a policy refusal), which
        // another network won't fix.
        XCTAssertFalse(ShardMapFetchError(attempts: [
            .init(url: primary, error: ShardMapLoaderError.requestFailed("invalid url")),
        ]).isNetworkFailure)
        XCTAssertFalse(ShardMapFetchError(attempts: [
            .init(url: primary, error: fieldTimeout()),
            .init(url: mirror, error: ShardMapLoaderError.requestFailed("invalid url")),
        ]).isNetworkFailure)
    }

    // MARK: Summary

    func testSummaryStatesWhatWentWrongWithEachHost() {
        // A DNS failure at the primary and a timeout at the mirror are different
        // problems; the summary says so instead of blaming a firewall.
        let summary = ShardMapFetchError(attempts: [
            .init(url: primary, error: URLError(.cannotFindHost), duration: 0.1),
            .init(url: mirror, error: fieldTimeout(), duration: 15, isMirror: true),
        ]).summary
        XCTAssertTrue(summary.contains("resolver.iterm2.com because its address couldn’t be looked up"), summary)
        XCTAssertTrue(summary.contains("its mirror gnachman.github.io because it didn’t respond within 15 seconds"), summary)
        XCTAssertFalse(summary.contains("firewall"), summary)
        XCTAssertFalse(summary.contains("blocking"), summary)
        XCTAssertFalse(summary.contains("https://"), summary)
    }

    func testSummaryAdvisesAnotherNetworkOnlyForNetworkFailures() {
        let network = ShardMapFetchError(attempts: [
            .init(url: primary, error: URLError(.cannotFindHost)),
            .init(url: mirror, error: fieldTimeout(), duration: 15),
        ]).summary
        XCTAssertTrue(network.hasSuffix("Try another network or a VPN."), network)

        let server = ShardMapFetchError(attempts: [
            .init(url: primary, error: ShardMapLoaderError.httpStatus(503)),
            .init(url: mirror, error: fieldTimeout(), duration: 15),
        ]).summary
        XCTAssertTrue(server.contains("HTTP 503"), server)
        XCTAssertFalse(server.contains("another network"), server)
    }

    func testSummaryForASingleSource() {
        // A self-hosted resolver has no mirror.
        let summary = ShardMapFetchError(attempts: [
            .init(url: "https://resolver.example.com/map.json", error: URLError(.cannotConnectToHost)),
        ]).summary
        XCTAssertTrue(summary.contains("from resolver.example.com because the connection was refused"), summary)
        XCTAssertFalse(summary.contains("mirror"), summary)
    }

    func testMirrorReportedAloneIsNotPresentedAsThePrimary() {
        // The primary's fetch was cancelled (the Mac's plugin reloading) and so
        // left out; the mirror is then the first attempt, but still a mirror.
        let summary = ShardMapFetchError(attempts: [
            .init(url: mirror, error: URLError(.cannotFindHost), isMirror: true),
        ]).summary
        XCTAssertTrue(summary.contains("from the mirror gnachman.github.io because its address couldn’t be looked up"),
                      summary)
    }

    func testDurationsAreRoundedAndNeverZero() {
        XCTAssertEqual(ShardMapFetchError.seconds(0.4), "1 second")
        XCTAssertEqual(ShardMapFetchError.seconds(1.2), "1 second")
        XCTAssertEqual(ShardMapFetchError.seconds(9.6), "10 seconds")
        let text = details(fieldTimeout(), duration: 0.4)
        XCTAssertFalse(text.contains("0 seconds"), text)
    }

    func testSourceCutShortIsNotBlamedOnTheNetwork() {
        // The mirror started just before the overall timeout. Its silence means
        // nothing, so it must not read as a firewall dropping traffic, and the
        // primary's failure alone decides the advice.
        let error = ShardMapFetchError(attempts: [
            .init(url: primary, error: URLError(.cannotFindHost)),
            .init(url: mirror, error: ShardMapLoaderError.cutShort, duration: 0.4, isMirror: true),
        ])
        XCTAssertTrue(error.summary.contains("its mirror gnachman.github.io because it wasn’t given enough time to respond"),
                      error.summary)
        XCTAssertFalse(error.details.contains("firewall"), error.details)
        XCTAssertTrue(error.details.contains("after 1 second,"), error.details)
        XCTAssertTrue(error.isNetworkFailure)

        let alone = ShardMapFetchError(attempts: [.init(url: primary, error: ShardMapLoaderError.cutShort)])
        XCTAssertFalse(alone.isNetworkFailure)
    }

    func testCancelledRequestIsDescribedPlainly() {
        let error = ShardMapFetchError(attempts: [.init(url: primary, error: URLError(.cancelled))])
        XCTAssertTrue(error.summary.contains("because the request was cancelled"), error.summary)
        XCTAssertTrue(error.details.contains("The request was cancelled"), error.details)
    }

    func testNoAnswerSummaryNamesTheSourcesItIsGiven() {
        XCTAssertEqual(ShardMapFetchError.noAnswerSummary(urls: [primary, mirror], within: 10),
                       "Couldn’t get the list of relay servers from resolver.iterm2.com or from its mirror "
                       + "gnachman.github.io within 10 seconds. Try another network or a VPN.")
        XCTAssertEqual(ShardMapFetchError.noAnswerSummary(urls: [], within: 10),
                       "Couldn’t get the list of relay servers within 10 seconds. Try another network or a VPN.")
    }

    func testLocalizedDescriptionIsTheSummaryAlone() {
        // localizedDescription ends up in one-line status text, which has no
        // room for a paragraph per server.
        let error = ShardMapFetchError(attempts: [.init(url: primary, error: fieldTimeout(), duration: 15)])
        XCTAssertEqual(error.localizedDescription, error.summary)
        XCTAssertFalse(error.localizedDescription.contains("firewall"))
    }
}

//
//  TmuxPaneInferredHostTests.swift
//  iTerm2 ModernTests
//
//  A tmux Integration pane on a host reached through SSH Integration takes its gateway's host
//  until its own shell reports one.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxPaneInferredHostTests: XCTestCase {
    private typealias T = TmuxPaneInferredHost
    private let remote = T.Host(hostname: "example.com", username: "u")

    func testAPaneWithNoHostTakesTheGatewaysOnSSHIntegration() {
        XCTAssertEqual(T.decide(paneReportedHost: false, gatewayOnSSHIntegration: true,
                                gatewayHost: remote, published: nil),
                       .publish(remote))
    }

    // A host the pane's shell reports wins, whatever was published before.
    func testAReportedHostWins() {
        XCTAssertEqual(T.decide(paneReportedHost: true, gatewayOnSSHIntegration: true,
                                gatewayHost: remote, published: nil), .leave)
        XCTAssertEqual(T.decide(paneReportedHost: true, gatewayOnSSHIntegration: true,
                                gatewayHost: remote, published: remote), .leave)
    }

    // A tmux server on this Mac, or one not reached through SSH Integration: nothing is inferred.
    func testNothingWithoutSSHIntegration() {
        XCTAssertEqual(T.decide(paneReportedHost: false, gatewayOnSSHIntegration: false,
                                gatewayHost: remote, published: nil), .leave)
        XCTAssertEqual(T.decide(paneReportedHost: false, gatewayOnSSHIntegration: true,
                                gatewayHost: nil, published: nil), .leave)
        XCTAssertEqual(T.decide(paneReportedHost: false, gatewayOnSSHIntegration: true,
                                gatewayHost: T.Host(hostname: "", username: nil), published: nil), .leave)
    }

    // The connection ended, or the gateway no longer knows its host: what was inferred goes.
    func testWhatNoLongerAppliesIsCleared() {
        XCTAssertEqual(T.decide(paneReportedHost: false, gatewayOnSSHIntegration: false,
                                gatewayHost: remote, published: remote), .clear)
        XCTAssertEqual(T.decide(paneReportedHost: false, gatewayOnSSHIntegration: true,
                                gatewayHost: nil, published: remote), .clear)
    }

    func testTheGatewaysNewHostReplacesTheOld() {
        let other = T.Host(hostname: "other.example.com", username: nil)
        XCTAssertEqual(T.decide(paneReportedHost: false, gatewayOnSSHIntegration: true,
                                gatewayHost: other, published: remote), .publish(other))
        XCTAssertEqual(T.decide(paneReportedHost: false, gatewayOnSSHIntegration: true,
                                gatewayHost: remote, published: remote), .leave, "unchanged")
    }
}

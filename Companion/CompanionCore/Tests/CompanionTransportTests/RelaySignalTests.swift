//
//  RelaySignalTests.swift
//  CompanionCore
//
//  Pins the re-resolution wire-code taxonomy (design §6.9): which relay close
//  codes / HTTP statuses mean "leave this host" vs "retry here" vs "back off long"
//  vs "fatal", and that the long-backoff cases are reason-disambiguated.
//

import XCTest
import CompanionProtocol
@testable import CompanionTransport

final class RelaySignalTests: XCTestCase {

    // MARK: Re-resolve (leave this host)

    func test_ws4421_isReResolve() {
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 4421, reason: ""),
                       .reResolve(ownerHint: nil))
    }

    func test_reshardSentinelReason_isReResolve_evenWithoutCode() {
        // URLSessionWebSocketTask cannot surface 4421, so the sentinel reason is
        // the fallback (code arrives as something else, here 1000/0).
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 0, reason: "reshard"),
                       .reResolve(ownerHint: nil))
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1000, reason: "reshard"),
                       .reResolve(ownerHint: nil))
    }

    func test_reshardSentinel_carriesOwnerHint() {
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 4421, reason: "reshard relay7.iterm2.com"),
                       .reResolve(ownerHint: "relay7.iterm2.com"))
        // Bare sentinel -> no owner.
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 4421, reason: "reshard"),
                       .reResolve(ownerHint: nil))
    }

    func test_reshardPrefix_doesNotFalseMatchResharding() {
        // "resharding" must NOT be read as the sentinel.
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1000, reason: "resharding now"),
                       .retryHere)
    }

    func test_4421_withNonSentinelReason_yieldsNoOwnerHint() {
        // When code 4421 short-circuits to re-resolve, the owner extraction must use
        // the SAME sentinel guard as the classifier: a reason that merely begins with
        // the letters "reshard" must not be sliced mid-word into a garbage hint.
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 4421, reason: "resharding now"),
                       .reResolve(ownerHint: nil))
    }

    func test_http421_isReResolve_withOwnerFromHeader() {
        XCTAssertEqual(RelaySignal.forHTTPStatus(421, ownerHint: "relay3.iterm2.com"),
                       .reResolve(ownerHint: "relay3.iterm2.com"))
        XCTAssertEqual(RelaySignal.forHTTPStatus(421), .reResolve(ownerHint: nil))
    }

    // MARK: Long backoff (same host, reason-disambiguated)

    func test_1008DailyQuota_isLongBackoff() {
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1008, reason: "daily quota exceeded"),
                       .longBackoff(.dailyQuota))
    }

    func test_1000Displaced_isLongBackoff() {
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1000, reason: "displaced"),
                       .longBackoff(.displaced))
    }

    func test_1008OtherReasons_areTransient_notLongBackoff() {
        // The relay overloads 1008; only the "daily quota" reason takes the long
        // backoff, or a frame-rate/admission-timeout close would wrongly slow to a
        // 30-minute cadence.
        for reason in ["frame rate exceeded", "bad hello", "too many pending", "admission timeout"] {
            XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1008, reason: reason), .retryHere,
                           "1008 \"\(reason)\" should be transient")
        }
    }

    func test_1000Ordinary_isTransient_notDisplaced() {
        // A normal-closure without the "displaced" reason is just a transient close.
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1000, reason: ""), .retryHere)
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1000, reason: "peer gone"), .retryHere)
    }

    // MARK: Retry here (transient; same host)

    func test_transientWSCodes_areRetryHere() {
        for code in [1001, 1011, 1006] {
            XCTAssertEqual(RelaySignal.forWebSocketClose(code: code, reason: ""), .retryHere,
                           "WS \(code) should be retry-here")
        }
    }

    func test_transientHTTPStatuses_areRetryHere() {
        for status in [429, 500, 503] {
            XCTAssertEqual(RelaySignal.forHTTPStatus(status), .retryHere, "HTTP \(status)")
        }
    }

    // MARK: Fatal

    func test_fatalHTTPStatuses() {
        XCTAssertEqual(RelaySignal.forHTTPStatus(403), .fatal)
        XCTAssertEqual(RelaySignal.forHTTPStatus(413), .fatal)
        // Another 4xx client error defaults to fatal, not an endless loop.
        XCTAssertEqual(RelaySignal.forHTTPStatus(404), .fatal)
    }

    // MARK: Bridge to TransportError

    func test_transportError_bridge() {
        XCTAssertEqual(RelaySignal.reResolve(ownerHint: "relay7").transportError(),
                       .reResolve(ownerHint: "relay7"))
        XCTAssertEqual(RelaySignal.reResolve(ownerHint: nil).transportError(),
                       .reResolve(ownerHint: nil))
        XCTAssertEqual(RelaySignal.longBackoff(.dailyQuota).transportError(), .quotaExceeded)
        // Displaced maps to .displaced so the phone's URLSession transport applies
        // its own long backoff (the mac short-circuits to RelayDisplacedError before
        // reaching this bridge, so its 60 s park backoff is unaffected).
        XCTAssertEqual(RelaySignal.longBackoff(.displaced).transportError(), .displaced)
        // Transient/fatal keep the original error, so they map to nil here.
        XCTAssertNil(RelaySignal.retryHere.transportError())
        XCTAssertNil(RelaySignal.fatal.transportError())
    }

    func test_transportError_endToEnd_fromCloseAndStatus() {
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 4421, reason: "reshard relay7.iterm2.com")
                        .transportError(),
                       .reResolve(ownerHint: "relay7.iterm2.com"))
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1008, reason: "daily quota exceeded")
                        .transportError(),
                       .quotaExceeded)
        XCTAssertEqual(RelaySignal.forWebSocketClose(code: 1000, reason: "displaced").transportError(),
                       .displaced)
        XCTAssertNil(RelaySignal.forWebSocketClose(code: 1001, reason: "").transportError())
        XCTAssertEqual(RelaySignal.forHTTPStatus(421, ownerHint: "relay3.iterm2.com").transportError(),
                       .reResolve(ownerHint: "relay3.iterm2.com"))
        XCTAssertNil(RelaySignal.forHTTPStatus(403).transportError())
    }

    // MARK: The load-bearing invariant

    func test_onlyReResolveCodesLeaveTheHost() {
        // Everything that is NOT 421/4421/reshard keeps the client on the same host
        // (retryHere or longBackoff or fatal), never re-resolve. This is the §6.9
        // invariant that lets cached-host optimism and reject-on-doubt compose.
        let nonReResolve: [RelaySignal] = [
            .forWebSocketClose(code: 1000, reason: "displaced"),
            .forWebSocketClose(code: 1008, reason: "daily quota exceeded"),
            .forWebSocketClose(code: 1001, reason: ""),
            .forWebSocketClose(code: 1011, reason: ""),
            .forHTTPStatus(429), .forHTTPStatus(503), .forHTTPStatus(403), .forHTTPStatus(500)
        ]
        for signal in nonReResolve {
            if case .reResolve = signal { XCTFail("\(signal) must not be a re-resolve") }
        }
    }
}

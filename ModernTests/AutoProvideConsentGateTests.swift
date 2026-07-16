//
//  AutoProvideConsentGateTests.swift
//  ModernTests
//
//  P1: auto-sending a session's terminal state + visible screen with every AI
//  message must require an explicit, informed global consent, not merely a
//  per-chat .always permission. A legacy "Always" grant (e.g. an old
//  "View History = Always" carried across the rename to "View Contents") reaches
//  .always without ever passing the per-chat "Send Automatically" confirmation, so
//  gating on the permission alone would silently start sending the screen.
//  ChatAgent.shouldSuppressAutoProvide is the gate: suppress whenever auto-send is
//  wanted but consent is not granted.
//

import XCTest
@testable import iTerm2SharedARC

final class AutoProvideConsentGateTests: XCTestCase {
    func testGrantedAllowsAutoSend() {
        XCTAssertFalse(ChatAgent.shouldSuppressAutoProvide(wantsAutoSend: true, consent: .granted))
    }

    func testUnknownSuppressesWhenWanted() {
        // The default for everyone until they consent: nothing auto-sends yet.
        XCTAssertTrue(ChatAgent.shouldSuppressAutoProvide(wantsAutoSend: true, consent: .unknown))
    }

    func testDeniedSuppressesWhenWanted() {
        XCTAssertTrue(ChatAgent.shouldSuppressAutoProvide(wantsAutoSend: true, consent: .denied))
    }

    func testNoAutoSendWantedNeverSuppresses() {
        // No category is at .always, so nothing would auto-send regardless of
        // consent; the gate must not report suppression (there is nothing to gate).
        XCTAssertFalse(ChatAgent.shouldSuppressAutoProvide(wantsAutoSend: false, consent: .unknown))
        XCTAssertFalse(ChatAgent.shouldSuppressAutoProvide(wantsAutoSend: false, consent: .granted))
    }
}

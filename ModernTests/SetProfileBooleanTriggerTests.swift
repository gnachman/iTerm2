//
//  SetProfileBooleanTriggerTests.swift
//  ModernTests
//
//  Tests that SetProfileBooleanTrigger.description is safe to call off the main thread (it is
//  invoked from a DLog on the trigger mutation queue), i.e. it does not read main-thread-only
//  AppKit via ProfileBoolSettingCatalog/PreferencePanel.allSettings() (F14).
//

import XCTest
@testable import iTerm2SharedARC

final class SetProfileBooleanTriggerTests: XCTestCase {
    private func makeTrigger(key: String, on: Bool) -> Trigger? {
        let param = TwoParameterTriggerCodec.convert(tuple: (key, on ? "1" : "0"))
        let dict: [String: Any] = [
            "action": "iTermSetProfileBooleanTrigger",
            "parameter": param,
            "regex": "",
            "matchType": NSNumber(value: iTermTriggerMatchType.regex.rawValue)
        ]
        return Trigger(fromUntrustedDict: dict)
    }

    // F14: off the main thread, description must fall back to the raw key rather than building the
    // catalog (which reads AppKit). The raw key "Prevent Sleep" is readable enough for a log line.
    func testDescriptionOffMainThreadUsesRawKeyAndDoesNotTouchAppKit() {
        guard let trigger = makeTrigger(key: "Prevent Sleep", on: true) else {
            XCTFail("could not create trigger")
            return
        }
        let exp = expectation(description: "off-main description")
        DispatchQueue.global().async {
            let desc = trigger.description
            XCTAssertTrue(desc.contains("Prevent Sleep"), "expected raw key in \(desc)")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    // F-201: firing the trigger used to crash. Its side effect reaches
    // PTYSession.setSessionSpecificProfileValues, which reloads the profile and
    // joins threads. Joining from inside an ordinary (non-paused) side effect
    // trips the assert in -[VT100Screen performBlockWithJoinedThreads:], so the
    // side effect must be a paused one. This fires a real trigger through the
    // real side-effect path and checks, at the moment the delegate is called,
    // the same condition that assert checks.
    func testFiredTriggerRunsInSideEffectThatPermitsJoiningThreads() {
        let harness = TerminalTestHarness()
        let param = TwoParameterTriggerCodec.convert(tuple: ("Prevent Sleep", "1"))
        let triggerDict: [String: Any] = [
            "regex": "ZAPME",
            "action": "iTermSetProfileBooleanTrigger",
            "parameter": param
        ]
        harness.screen.performBlock(joinedThreads: { _, ms, _ in
            let config = VT100MutableScreenConfiguration()
            config.triggerProfileDicts = [triggerDict]
            ms.setConfig(config)
        })

        let screen = harness.screen
        var joinPermitted: Bool?
        let delivered = expectation(description: "set profile bool side effect")
        harness.delegate.onSetSessionSpecificProfileBool = { _, _ in
            let ms: VT100ScreenMutableState = screen.mutableState
            joinPermitted = !ms.performingSideEffect || ms.performingPausedSideEffect
            delivered.fulfill()
        }

        harness.send(Array("ZAPME\r\n".utf8))
        harness.sync()
        wait(for: [delivered], timeout: 30)

        XCTAssertEqual(harness.delegate.setSessionSpecificProfileBoolCalls.count, 1)
        XCTAssertEqual(harness.delegate.setSessionSpecificProfileBoolCalls.first?.key, "Prevent Sleep")
        XCTAssertEqual(harness.delegate.setSessionSpecificProfileBoolCalls.first?.value, true)
        XCTAssertEqual(joinPermitted, true,
                       "Side effect must be paused so the delegate may join threads")

        // The executor must be unpaused afterwards, or later output would stall.
        harness.send(Array("after\r\n".utf8))
        harness.sync()
        let dump: String = harness.screen.compactLineDump()
        XCTAssertTrue(dump.contains("after"), "Expected later output to be processed: \(dump)")
    }
}

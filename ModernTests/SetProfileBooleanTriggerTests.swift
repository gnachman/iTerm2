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
}

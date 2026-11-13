//
//  VT100ScreenEventTriggerNilDelegateTests.swift
//  ModernTests
//
//  An event trigger can fire while its session has no delegate: a split pane's new session is
//  not set up until after the tab learns of it, and a terminating session clears the delegate
//  before its tab removes it. Evaluating an interpolated parameter then asked the nil delegate
//  for the variable scope and crashed in SwiftyStringWithBackreferencesEvaluator.amendedScope.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100ScreenEventTriggerNilDelegateTests: XCTestCase {
    func testInterpolatedParameterWithoutDelegateDoesNotCrash() throws {
        let screen = VT100Screen()
        XCTAssertNil(screen.delegate)
        let trigger = try XCTUnwrap(Trigger(fromUntrustedDict: [
            "action": "ScriptTrigger",
            "parameter": #"\(tab.id)"#,
            "matchType": NSNumber(value: iTermTriggerMatchType.eventVariableChanged.rawValue)
        ]))

        screen.fireEventTrigger(trigger, capturedStrings: ["42", "tab"], useInterpolation: true)
    }
}

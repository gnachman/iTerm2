//
//  VT100ScreenEventTriggerNilDelegateTests.swift
//  ModernTests
//
//  Evaluating an interpolated parameter asks the screen's delegate for the variable scope. With
//  no delegate, -[VT100Screen performBlockWithScope:] passed a nil scope to Swift, which crashed
//  in SwiftyStringWithBackreferencesEvaluator.amendedScope. PTYSession now holds event trigger
//  fires until the screen has a delegate and stops them when it terminates; this checks that a
//  fire that gets through anyway doesn't crash.
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

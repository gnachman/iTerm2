//
//  iTermColorScopeVariablesTests.swift
//  ModernTests
//
//  Verifies that binding a color to a `colors.*` variable tracks the live
//  palette, with emphasis on the indexed colors whose references are recorded at
//  array granularity.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermColorScopeVariablesTests: XCTestCase, iTermObject {
    private var scope: iTermVariableScope!
    private var variables: iTermVariables!
    private var colorVariables: iTermColorScopeVariables!
    private var observers: [iTermExpressionObserver] = []

    // ANSI yellow is palette index 3, i.e. colors.ansi.yellow and colors.indexed[3].
    private let ansiYellowKey = kColorMap8bitBase + 3

    override func setUp() {
        super.setUp()
        scope = iTermVariableScope()
        variables = iTermVariables(context: [], owner: self)
        scope.add(variables, toScopeNamed: nil)
        colorVariables = iTermColorScopeVariables(scope: scope, owner: self)
    }

    override func tearDown() {
        for observer in observers {
            observer.invalidate()
        }
        observers = []
        super.tearDown()
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - Helpers

    // Observe `expression` and fulfill the returned expectation once its evaluated
    // value equals `expected`. Mirrors how PTYSession binds a color to an
    // expression via iTermExpressionObserver.
    private func expectValue(_ expected: String, ofExpression expression: String) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "\(expression) becomes \(expected)")
        var fulfilled = false
        let observer = iTermExpressionObserver(string: expression,
                                               scope: scope,
                                               sideEffectsAllowed: false) { newValue, _ in
            if let string = newValue as? String, string == expected, !fulfilled {
                fulfilled = true
                expectation.fulfill()
            }
            return newValue
        }
        observers.append(observer)
        return expectation
    }

    private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    // MARK: - Tests

    func testNamedAnsiScalarReactivity() {
        let red = color(1, 0, 0)
        let expectation = expectValue(red.hexString(), ofExpression: "colors.ansi.yellow")
        colorVariables.didChangeColor(forKey: ansiYellowKey, to: red)
        wait(for: [expectation], timeout: 2)
    }

    func testNamedColorReactivity() {
        let blue = color(0, 0, 1)
        let expectation = expectValue(blue.hexString(), ofExpression: "colors.foreground")
        colorVariables.didChangeColor(forKey: kColorMapForeground, to: blue)
        wait(for: [expectation], timeout: 2)
    }

    func testIndexedReactivity() {
        let green = color(0, 1, 0)
        let expectation = expectValue(green.hexString(), ofExpression: "colors.indexed[20]")
        colorVariables.didChangeColor(forKey: kColorMap8bitBase + 20, to: green)
        wait(for: [expectation], timeout: 2)
    }

    // Indices 0-15 alias the ANSI colors, so changing the ANSI-yellow key also
    // updates colors.indexed[3].
    func testIndexedAnsiAliasing() {
        let magenta = color(1, 0, 1)
        let expectation = expectValue(magenta.hexString(), ofExpression: "colors.indexed[3]")
        colorVariables.didChangeColor(forKey: ansiYellowKey, to: magenta)
        wait(for: [expectation], timeout: 2)
    }

    // Alpha survives a hexStringWithAlpha -> colorFromHexString round-trip, which
    // is how a translucent bound color is carried through the binding.
    func testAlphaHexRoundTrip() {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
        guard let back = NSColor(fromHexString: color.hexStringWithAlpha(), allowingAlpha: true) else {
            XCTFail("Failed to parse \(color.hexStringWithAlpha())")
            return
        }
        XCTAssertEqual(back.alphaComponent, 0.5, accuracy: 0.02)
    }

    // Without opting in, the alpha form is rejected so transparency can't leak
    // into colors that render opaque.
    func testAlphaRejectedByDefault() {
        XCTAssertNil(NSColor(fromHexString: "#ff000080"))
        XCTAssertNotNil(NSColor(fromHexString: "#ff0000"))
    }

    // A malformed alpha byte is rejected rather than partially scanned (a bad second
    // nibble must not slip through as a near-invisible color).
    func testMalformedAlphaByteRejected() {
        XCTAssertNil(NSColor(fromHexString: "#ffffff5z", allowingAlpha: true))
        XCTAssertNotNil(NSColor(fromHexString: "#ffffff80", allowingAlpha: true))
    }

    // iterm2.with_alpha applies transparency to a color string, which is how the
    // OSC SetColors=badge=i:N@A path and settings bindings overlay alpha.
    func testWithAlphaFunction() {
        let expectation = XCTestExpectation(description: "with_alpha")
        var output: Any?
        let evaluator = iTermExpressionEvaluator(
            expressionString: "iterm2.with_alpha(color: \"#ff0000\", alpha: 0.5)",
            scope: scope)
        evaluator.evaluate(withTimeout: 1, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        guard let hex = output as? String,
              let color = NSColor(fromHexString: hex, allowingAlpha: true) else {
            XCTFail("with_alpha returned \(String(describing: output))")
            return
        }
        XCTAssertEqual(color.alphaComponent, 0.5, accuracy: 0.02)
    }

    // with_alpha must parse alpha-bearing input (its own output form) so a nested
    // call replaces the alpha instead of dropping it.
    func testWithAlphaOnAlphaBearingInput() {
        let expectation = XCTestExpectation(description: "nested with_alpha")
        var output: Any?
        let evaluator = iTermExpressionEvaluator(
            expressionString: "iterm2.with_alpha(color: iterm2.with_alpha(color: \"#ff0000\", alpha: 0.5), alpha: 0.25)",
            scope: scope)
        evaluator.evaluate(withTimeout: 1, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        guard let hex = output as? String,
              let color = NSColor(fromHexString: hex, allowingAlpha: true) else {
            XCTFail("nested with_alpha returned \(String(describing: output))")
            return
        }
        XCTAssertEqual(color.alphaComponent, 0.25, accuracy: 0.02)
    }

    // A palette-owned binding value round-trips its expression and is identifiable
    // as palette-owned; a plain string is a user binding.
    func testBindingOwnership() {
        let paletteValue = iTermProfilePreferences.paletteBindingValue(withExpression: "colors.ansi.red")
        XCTAssertEqual(iTermProfilePreferences.expression(forBindingValue: paletteValue), "colors.ansi.red")
        XCTAssertTrue(iTermProfilePreferences.bindingValueIsPaletteOwned(paletteValue))

        XCTAssertEqual(iTermProfilePreferences.expression(forBindingValue: "user.myColor"), "user.myColor")
        XCTAssertFalse(iTermProfilePreferences.bindingValueIsPaletteOwned("user.myColor"))
    }

    // A nil color clears the published value, matching reload(from:), so the
    // incremental and full-reload paths agree.
    func testDidChangeColorToNilClears() {
        colorVariables.didChangeColor(forKey: kColorMapLink, to: color(1, 0, 0))
        XCTAssertNotNil(scope.value(forVariableName: "colors.link"))
        colorVariables.didChangeColor(forKey: kColorMapLink, to: nil)
        XCTAssertNil(scope.value(forVariableName: "colors.link"))
    }

    // The OSC SetColors=i:N path builds its binding expression from this, so the
    // names must match the published variables.
    func testExpressionForPaletteIndex() {
        XCTAssertEqual(iTermColorScopeVariables.expression(forPaletteIndex: 0), "colors.ansi.black")
        XCTAssertEqual(iTermColorScopeVariables.expression(forPaletteIndex: 3), "colors.ansi.yellow")
        XCTAssertEqual(iTermColorScopeVariables.expression(forPaletteIndex: 15), "colors.ansi.brightWhite")
        XCTAssertEqual(iTermColorScopeVariables.expression(forPaletteIndex: 16), "colors.indexed[16]")
        XCTAssertEqual(iTermColorScopeVariables.expression(forPaletteIndex: 255), "colors.indexed[255]")
    }

    // Reloading from a map that lacks a key must clear the previously published
    // value so the scope stays authoritative across profile switches.
    func testReloadClearsStaleNamedVariables() {
        let map1 = iTermColorMap()
        map1.setColor(color(1, 0, 0), forKey: kColorMapLink)
        colorVariables.reload(from: map1)
        XCTAssertNotNil(scope.value(forVariableName: "colors.link"))

        let map2 = iTermColorMap()
        colorVariables.reload(from: map2)
        XCTAssertNil(scope.value(forVariableName: "colors.link"))
    }

    // Indexed slots are cleared too (to "", which a binding no-ops on) when the
    // new map lacks them, not carried over from the previous profile.
    func testReloadClearsStaleIndexedValues() {
        let map1 = iTermColorMap()
        map1.setColor(color(0, 1, 1), forKey: kColorMap8bitBase + 200)
        colorVariables.reload(from: map1)
        let populated = expectValue(map1.color(forKey: kColorMap8bitBase + 200).hexString(),
                                    ofExpression: "colors.indexed[200]")
        wait(for: [populated], timeout: 2)

        colorVariables.reload(from: iTermColorMap())
        let cleared = expectValue("", ofExpression: "colors.indexed[200]")
        wait(for: [cleared], timeout: 2)
    }

    // reload populates every variable from a color map, which is how a session
    // captures the palette at load. Colors round-trip through the map's default
    // color space, so the expected hex comes from the map, not the input color.
    func testReloadPopulatesFromColorMap() {
        let map = iTermColorMap()
        map.setColor(color(0, 1, 1), forKey: kColorMap8bitBase + 200)
        map.setColor(color(1, 0.5, 0), forKey: kColorMapBackground)

        colorVariables.reload(from: map)

        // Observers created after reload evaluate against the reloaded values.
        let indexedExpectation = expectValue(map.color(forKey: kColorMap8bitBase + 200).hexString(),
                                             ofExpression: "colors.indexed[200]")
        let backgroundExpectation = expectValue(map.color(forKey: kColorMapBackground).hexString(),
                                                ofExpression: "colors.background")
        wait(for: [indexedExpectation, backgroundExpectation], timeout: 2)
    }
}

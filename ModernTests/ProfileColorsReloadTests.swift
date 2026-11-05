//
//  ProfileColorsReloadTests.swift
//  ModernTests
//
//  Drives a real session through the escape-sequence color path (what OSC 12 and OSC 112 do) and
//  checks that only the colors are reloaded. The observable difference between the colors-only
//  reload and the full one is that the full reload resets the session mode, so a session in copy
//  mode stays there only if the fast path ran. The full reloads these tests trigger along the way
//  (session setup in every test, and the non-color change in one of them) also exercise the debug
//  build linter that asserts no colors-scope key is read outside reloadColorsFromProfile:.
//

import XCTest
@testable import iTerm2SharedARC

final class ProfileColorsReloadTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private var session: PTYSession!
    private var originalProfileCursorColor: NSColor?
    private var originalCursorColor: NSColor?
    private let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    private let green = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        session = fixture.terminal.currentSession()
        XCTAssertNotNil(session)
        originalProfileCursorColor = profileCursorColor
        originalCursorColor = cursorColor
        // Session creation above ran a full reload, so the debug linter has run once per test.
        // The first session-specific write divorces the session from its shared profile. The
        // divorce is a profile swap, not a reload, and the color write that follows it already
        // takes the colors-only path. Get it out of the way so the tests below see steady-state
        // behavior.
        _ = session.screenSetColor(green, profileKey: KEY_CURSOR_COLOR)
        XCTAssertTrue(session.isDivorced)
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        session = nil
        super.tearDown()
    }

    private var cursorColor: NSColor? {
        return session.screen.colorMap.color(forKey: kColorMapCursor)
    }

    private var profileCursorColor: NSColor? {
        guard let dict = session.profile?[KEY_CURSOR_COLOR] as? [AnyHashable: Any] else {
            return nil
        }
        return ITAddressBookMgr.decodeColor(dict)
    }

    // Colors go through a dictionary and a color space conversion on the way into the profile and
    // back, so compare components with a tolerance rather than exact values.
    private func assertColor(_ actual: NSColor?, equals expected: NSColor?, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let actual, let expected else {
            XCTAssertNil(actual, message, file: file, line: line)
            XCTAssertNil(expected, message, file: file, line: line)
            return
        }
        guard let a = actual.usingColorSpace(.sRGB), let e = expected.usingColorSpace(.sRGB) else {
            XCTFail("Could not convert to sRGB. " + message, file: file, line: line)
            return
        }
        XCTAssertEqual(a.redComponent, e.redComponent, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(a.greenComponent, e.greenComponent, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(a.blueComponent, e.blueComponent, accuracy: 0.01, message, file: file, line: line)
    }

    func testCursorColorEscapeSequenceTakesColorsOnlyPath() {
        session.modeHandler.mode = .copy

        _ = session.screenSetColor(blue, profileKey: KEY_CURSOR_COLOR)

        assertColor(cursorColor, equals: blue, "color map should follow the escape sequence")
        assertColor(profileCursorColor, equals: blue, "profile should hold the new color")
        XCTAssertEqual(session.modeHandler.mode, .copy, "a colors-only change must not run the full reload")
        let published = session.genericScope.value(forVariableName: "colors.cursor") as? String
        assertColor(published.flatMap { NSColor(fromHexString: $0) }, equals: blue,
                    "colors.* variables should follow the color map")
    }

    func testCursorColorResetTakesColorsOnlyPath() {
        _ = session.screenSetColor(blue, profileKey: KEY_CURSOR_COLOR)
        session.modeHandler.mode = .copy

        _ = session.screenResetColor(withColorMapKey: kColorMapCursor, profileKey: KEY_CURSOR_COLOR, dark: false)

        assertColor(profileCursorColor, equals: originalProfileCursorColor,
                    "reset should restore the color from before the first escape sequence")
        assertColor(cursorColor, equals: originalCursorColor)
        XCTAssertEqual(session.modeHandler.mode, .copy, "a colors-only reset must not run the full reload")
    }

    func testNonColorChangeStillRunsFullReload() {
        session.modeHandler.mode = .copy

        session.setSessionSpecificProfileValues([KEY_TRANSPARENCY: 0.5])

        XCTAssertEqual(session.transparency, 0.5, accuracy: 0.001)
        XCTAssertEqual(session.modeHandler.mode, .default, "a non-color change takes the full reload")
    }

    func testBadgeColorEscapeSequenceUpdatesBadgeColor() {
        // The badge caches its color rather than reading the profile at draw time, so the
        // colors-only path has to refresh the cache (and re-render the badge from it, which
        // happens in the same place).
        session.modeHandler.mode = .copy

        _ = session.screenSetColor(blue, profileKey: KEY_BADGE_COLOR)

        assertColor(session.textViewBadgeColor(), equals: blue)
        XCTAssertEqual(session.modeHandler.mode, .copy)
    }

    func testFullReloadThatChangesBackgroundWithTabColorSet() {
        // In the Minimal tab style a background change recomputes the window's tab colors
        // synchronously, in the middle of the colors load. The tab color must come from the cache
        // seeded by that load rather than from the live profile, which the debug linter wraps
        // during a full reload. A color key plus a non-color key forces the full reload.
        let savedTabStyle = iTermPreferences.int(forKey: kPreferenceKeyTabStyle)
        iTermPreferences.setInt(5, forKey: kPreferenceKeyTabStyle)  // TAB_STYLE_MINIMAL
        defer {
            iTermPreferences.setInt(savedTabStyle, forKey: kPreferenceKeyTabStyle)
        }
        session.setSessionSpecificProfileValues([KEY_USE_TAB_COLOR: true])
        _ = session.screenSetColor(green, profileKey: KEY_TAB_COLOR)

        // Write every variant of the background key so the test does not depend on whether the
        // profile uses separate light and dark colors.
        var values: [String: Any] = [KEY_TRANSPARENCY: 0.25]
        for key in iTermProfilePreferences.colorVariantKeys(forBaseKey: KEY_BACKGROUND_COLOR) {
            values[key] = ITAddressBookMgr.encode(blue)
        }
        session.setSessionSpecificProfileValues(values)

        assertColor(session.screen.colorMap.color(forKey: kColorMapBackground), equals: blue)
        assertColor(session.tabColor, equals: green)
        XCTAssertEqual(session.modeHandler.mode, .default, "a mixed change takes the full reload")
    }

    func testTabColorEscapeSequenceUpdatesTabColor() {
        session.setSessionSpecificProfileValues([KEY_USE_TAB_COLOR: true])
        session.modeHandler.mode = .copy

        _ = session.screenSetColor(blue, profileKey: KEY_TAB_COLOR)

        assertColor(session.tabColor, equals: blue)
        XCTAssertEqual(session.modeHandler.mode, .copy)
    }
}

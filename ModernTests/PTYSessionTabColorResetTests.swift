//
//  PTYSessionTabColorResetTests.swift
//  iTerm2 ModernTests
//
//  OSC 6;1;bg;*;default (and OSC 1337 SetColors=tab=default) must put the tab
//  color back exactly the way the profile had it. The hard case is a profile
//  that has separate light/dark colors turned on but carries its tab color on
//  the base key alone, which is what a profile predating the per-appearance
//  variants looks like: the escape sequence invents the (Light)/(Dark) keys, so
//  the reset has to remove them again rather than leave them holding a value the
//  profile never had. Issue 13058.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionTabColorResetTests: XCTestCase {
    private let lightTabColorKey = KEY_TAB_COLOR + COLORS_LIGHT_MODE_SUFFIX
    private let darkTabColorKey = KEY_TAB_COLOR + COLORS_DARK_MODE_SUFFIX
    private let lightUseTabColorKey = KEY_USE_TAB_COLOR + COLORS_LIGHT_MODE_SUFFIX
    private let darkUseTabColorKey = KEY_USE_TAB_COLOR + COLORS_DARK_MODE_SUFFIX

    private let green = NSColor(srgbRed: 0, green: 0.8, blue: 0.2, alpha: 1)

    private func makeSession(profile: [AnyHashable: Any],
                             file: StaticString = #filePath,
                             line: UInt = #line) -> PTYSession {
        let session = PTYSession(synthetic: false)!
        // Assign the profile directly. setProfile(_:preservingName:) is the API a
        // window would use, but it refuses a session that has no profile yet.
        session.profile = profile.merging([KEY_GUID: ProfileModel.freshGuid()!]) { a, _ in a }
        XCTAssertNotNil(session.profile, "Test setup: the session must have a profile",
                        file: file, line: line)
        return session
    }

    /// NSColor equality is too strict here: a color that round-tripped through the
    /// profile carries a different colorspace flavor than the literal it came from,
    /// so compare the components.
    private func assertSameColor(_ actual: NSColor?,
                                 _ expected: NSColor,
                                 _ message: String = "",
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        guard let actual = actual?.usingColorSpace(.sRGB) else {
            XCTFail("Expected a tab color. " + message, file: file, line: line)
            return
        }
        let want = expected.usingColorSpace(.sRGB)!
        XCTAssertEqual(actual.redComponent, want.redComponent, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, want.greenComponent, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, want.blueComponent, accuracy: 0.001, message, file: file, line: line)
    }

    /// The session's profile, or an empty dictionary plus a failure. Going through
    /// this keeps a nil profile from satisfying the XCTAssertNil checks vacuously.
    private func profile(of session: PTYSession,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> [AnyHashable: Any] {
        guard let profile = session.profile else {
            XCTFail("The session lost its profile", file: file, line: line)
            return [:]
        }
        return profile
    }

    /// A profile that uses separate light/dark colors and has a tab color on the
    /// base key only.
    private func baseOnlyTabColorProfile() -> [AnyHashable: Any] {
        return [KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: true,
                KEY_USE_TAB_COLOR: true,
                KEY_TAB_COLOR: ITAddressBookMgr.encode(green)!]
    }

    /// The three-write form every wrapper script uses: one control sequence per
    /// component. The first write is the one that invents the variant keys.
    private func setTabColorByEscapeSequence(_ session: PTYSession,
                                             red: CGFloat,
                                             green: CGFloat,
                                             blue: CGFloat) {
        session.screenSetTabColorRedComponent(to: red)
        session.screenSetTabColorGreenComponent(to: green)
        session.screenSetTabColorBlueComponent(to: blue)
    }

    func testResetRestoresBaseTabColorAndRemovesInventedVariants() {
        let session = makeSession(profile: baseOnlyTabColorProfile())

        setTabColorByEscapeSequence(session, red: 1, green: 0.5, blue: 0)
        XCTAssertNotNil(profile(of: session)[darkTabColorKey],
                        "Baseline: the escape sequence writes the variant keys")

        session.screenSetCurrentTabColor(nil)

        let after = profile(of: session)
        XCTAssertNil(after[darkTabColorKey],
                     "The reset must remove the Tab Color (Dark) key the escape sequence invented, not leave a color there")
        XCTAssertNil(after[lightTabColorKey],
                     "The reset must remove the Tab Color (Light) key the escape sequence invented, not leave a color there")
        XCTAssertNil(after[darkUseTabColorKey],
                     "The reset must not leave a Use Tab Color (Dark) bit behind, which would shadow the profile's own Use Tab Color")
        XCTAssertNil(after[lightUseTabColorKey],
                     "The reset must not leave a Use Tab Color (Light) bit behind, which would shadow the profile's own Use Tab Color")

        XCTAssertEqual(after[KEY_TAB_COLOR] as? NSDictionary,
                       ITAddressBookMgr.encode(green) as NSDictionary?,
                       "The reset must restore the profile's own tab color")
        XCTAssertEqual(after[KEY_USE_TAB_COLOR] as? Bool, true,
                       "The reset must restore the profile's own enable bit")
        assertSameColor(session.tabColor, green,
                        "The effective tab color must be the profile's again")
    }

    func testResetAfterASingleWriteAlsoRemovesInventedVariants() {
        // A single write can't capture a polluted baseline, but it still invents
        // the variant keys, so the reset has the same work to do.
        let session = makeSession(profile: baseOnlyTabColorProfile())

        session.screenSetCurrentTabColor(.red)
        XCTAssertNotNil(profile(of: session)[darkTabColorKey],
                        "Baseline: the escape sequence writes the variant keys")

        session.screenSetCurrentTabColor(nil)

        let after = profile(of: session)
        XCTAssertNil(after[darkTabColorKey])
        XCTAssertNil(after[darkUseTabColorKey])
        assertSameColor(session.tabColor, green,
                        "The effective tab color must be the profile's again")
    }

    func testResetRestoresVariantsTheProfileActuallyHas() {
        // The other shape: the profile carries all three variants. Those are real
        // profile values, so the reset must put them back rather than remove them.
        let encoded = ITAddressBookMgr.encode(green)!
        let session = makeSession(profile: [KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: true,
                                            KEY_USE_TAB_COLOR: true,
                                            lightUseTabColorKey: true,
                                            darkUseTabColorKey: true,
                                            KEY_TAB_COLOR: encoded,
                                            lightTabColorKey: encoded,
                                            darkTabColorKey: encoded])

        setTabColorByEscapeSequence(session, red: 1, green: 0.5, blue: 0)
        session.screenSetCurrentTabColor(nil)

        let after = profile(of: session)
        XCTAssertEqual(after[darkTabColorKey] as? NSDictionary, encoded as NSDictionary,
                       "A variant the profile really had must be restored, not removed")
        XCTAssertEqual(after[darkUseTabColorKey] as? Bool, true)
        assertSameColor(session.tabColor, green)
    }

    func testResetWithNoTabColorInProfileLeavesNoTabColor() {
        // A profile with no tab color at all: the reset must leave the session
        // with no tab color and no invented keys.
        let session = makeSession(profile: [KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: true])

        setTabColorByEscapeSequence(session, red: 1, green: 0, blue: 0)
        session.screenSetCurrentTabColor(nil)

        let after = profile(of: session)
        XCTAssertNil(session.tabColor, "The session must end up with no tab color")
        XCTAssertNil(after[darkTabColorKey])
        XCTAssertNil(after[lightTabColorKey])
    }
}

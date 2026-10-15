//
//  BidiAltScreenToggleTests.swift
//  ModernTests
//
//  Turning on “Do not reorder right-to-left text in the alternate screen” while
//  an alternate-screen app is showing RTL text must drop the alternate grid's
//  existing bidi tables. Otherwise the renderer keeps drawing the rows
//  reordered (it reads the grid's bidi info) while selection treats them as
//  unreordered, so highlights and copies land on the mirror-image cells.
//  QA findings F-074 and F-313.
//

import XCTest
@testable import iTerm2SharedARC

class BidiAltScreenToggleTests: XCTestCase {
    private var session = FakeSession()
    private let key = "DisableBidiInAlternateScreen"
    private var savedSetting: Any?

    private func setBidi(_ on: Bool) {
        iTermPreferences.setBool(on, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != on && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private func setDisableBidiInAlternateScreen(_ value: Bool) {
        iTermUserDefaults.userDefaults().set(value, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }

    override func setUp() {
        super.setUp()
        savedSetting = iTermUserDefaults.userDefaults().object(forKey: key)
        setBidi(true)
        setDisableBidiInAlternateScreen(false)
    }

    override func tearDown() {
        if let savedSetting {
            iTermUserDefaults.userDefaults().set(savedSetting, forKey: key)
        } else {
            iTermUserDefaults.userDefaults().removeObject(forKey: key)
        }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidi(false)
        super.tearDown()
    }

    private func makeScreen() -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, m, _ in
            m.terminalEnabled = true
            m.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(20, height: 4, mutableState: m)
        })
        return screen
    }

    private func gridBidiInfo(_ screen: VT100Screen) -> BidiDisplayInfoObjc? {
        var info: BidiDisplayInfoObjc?
        screen.performBlock(joinedThreads: { _, m, _ in
            info = m.currentGrid.bidiInfo(forLine: 0)
        })
        return info
    }

    func testEnablingSettingInAlternateScreenDropsStaleBidiInfo() {
        let screen = makeScreen()
        screen.inject("\u{1b}[?1049h".data(using: .utf8)!)
        screen.performBlock(joinedThreads: { _, m, _ in
            XCTAssertTrue(m.terminal!.softAlternateScreenMode)
            m.appendString(atCursor: "שלום עולם")
            m.populateRTLStateIfNeeded()
        })
        XCTAssertNotNil(gridBidiInfo(screen), "precondition: alternate grid is reordered")

        setDisableBidiInAlternateScreen(true)
        XCTAssertTrue(iTermAdvancedSettingsModel.disableBidiInAlternateScreen())
        screen.performBlock(joinedThreads: { _, m, _ in
            XCTAssertTrue(m.currentGrid === m.altGrid)
            XCTAssertTrue(m.terminal!.softAlternateScreenMode)
            m.populateRTLStateIfNeeded()
        })

        XCTAssertNil(gridBidiInfo(screen),
                     "the drawn (grid) bidi table must match the unreordered selection mapping")
        XCTAssertNil(screen.bidiInfo(forLine: 0))
        XCTAssertNil(screen.screenCharArray(forLine: 0).bidiInfo)
    }

    func testSettingOnLeavesPrimaryScreenReordered() {
        setDisableBidiInAlternateScreen(true)
        let screen = makeScreen()
        screen.performBlock(joinedThreads: { _, m, _ in
            m.appendString(atCursor: "שלום עולם")
            m.populateRTLStateIfNeeded()
        })
        XCTAssertNotNil(gridBidiInfo(screen))
    }
}

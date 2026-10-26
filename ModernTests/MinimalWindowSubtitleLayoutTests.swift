//
//  MinimalWindowSubtitleLayoutTests.swift
//  ModernTests
//
//  In the Minimal theme a window with one tab draws its title (and the profile's
//  subtitle) in place of the tab bar. The label's frame is sized for one line
//  or two depending on whether there is a subtitle. A window made with Shell >
//  New Window got its title before the session's path was known, so the label
//  was laid out for one line; when the subtitle arrived later without the title
//  changing, nothing laid the label out again and the second line was clipped
//  until the window was resized.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class MinimalWindowSubtitleLayoutTests: XCTestCase {
    private var savedTabStyle: Int32 = 0
    private var terminal: PseudoTerminal?

    override func setUp() {
        super.setUp()
        savedTabStyle = iTermPreferences.int(forKey: kPreferenceKeyTabStyle)
        // TAB_STYLE_MINIMAL is not imported into Swift.
        iTermPreferences.setInt(5, forKey: kPreferenceKeyTabStyle)
    }

    override func tearDown() {
        terminal?.window?.close()
        terminal = nil
        iTermPreferences.setInt(savedTabStyle, forKey: kPreferenceKeyTabStyle)
        super.tearDown()
    }

    private func makeTerminal() -> PseudoTerminal {
        guard let profile = ProfileModel.sharedInstance().defaultBookmark(),
              let terminal = PseudoTerminal(smartLayout: false,
                                            windowType: iTermThemedWindowType(.WINDOW_TYPE_NORMAL),
                                            savedWindowType: .WINDOW_TYPE_NORMAL,
                                            percentage: iTermPercentage(width: 0, height: 0),
                                            screen: -1,
                                            profile: profile),
              let session = PTYSession(synthetic: false) else {
            it_fatalError("Could not create a terminal window")
        }
        session.profile = profile
        iTermController.sharedInstance()?.addTerminalWindow(terminal)
        terminal.setupSession(session, with: nil)
        terminal.insert(session, at: 0)
        terminal.window?.makeKeyAndOrderFront(nil)
        self.terminal = terminal
        return terminal
    }

    // iTermFakeWindowTitleLabel is not visible to Swift, so find it by class name.
    private func titleLabel(in terminal: PseudoTerminal) -> NSTextField? {
        return terminal.window?.contentView?.subviews.first {
            NSStringFromClass(type(of: $0)) == "iTermFakeWindowTitleLabel"
        } as? NSTextField
    }

    func testSubtitleArrivingAfterTitleIsLaidOutForTwoLines() throws {
        let terminal = makeTerminal()
        terminal.setWindowTitle("-zsh", subtitle: "")
        let label = try XCTUnwrap(titleLabel(in: terminal))
        XCTAssertFalse(label.isHidden, "Precondition: the title takes the tab bar's place")
        let oneLineHeight = label.frame.height

        // Same title, so only the subtitle changes.
        terminal.setWindowTitle("-zsh", subtitle: "/private/tmp")

        XCTAssertEqual(label.value(forKey: "subtitle") as? String, "/private/tmp")
        XCTAssertGreaterThan(label.frame.height, oneLineHeight,
                             "The label must grow to show the subtitle's line")
        XCTAssertGreaterThanOrEqual(label.frame.height, ceil(label.fittingSize.height))
    }

    func testSubtitleGoingAwayShrinksLabel() throws {
        let terminal = makeTerminal()
        terminal.setWindowTitle("-zsh", subtitle: "")
        terminal.setWindowTitle("-zsh", subtitle: "/private/tmp")
        let label = try XCTUnwrap(titleLabel(in: terminal))
        let twoLineHeight = label.frame.height

        terminal.setWindowTitle("-zsh", subtitle: "")

        XCTAssertLessThan(label.frame.height, twoLineHeight)
    }
}

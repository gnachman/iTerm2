//
//  AnnouncementDismissKeyTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-282: a “Press any key to dismiss” announcement stays current while it
/// animates away, and it used to swallow every key typed in that time.
final class AnnouncementDismissKeyTests: XCTestCase {
    private func keyDown(_ characters: String) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown,
                                              location: .zero,
                                              modifierFlags: [],
                                              timestamp: 0,
                                              windowNumber: 0,
                                              context: nil,
                                              characters: characters,
                                              charactersIgnoringModifiers: characters,
                                              isARepeat: false,
                                              keyCode: 0))
    }

    func testOnlyTheDismissingKeyIsConsumed() throws {
        var completions = [Int32]()
        let announcement = try XCTUnwrap(iTermAnnouncementViewController.announcement(withTitle: "Clear scrollback?",
                                                                        style: .kiTermAnnouncementViewStyleQuestion,
                                                                        withActions: [],
                                                                        completion: { completions.append($0) }))
        announcement.dismissOnKeyDown = true

        XCTAssertTrue(announcement.handleKeyDown(try keyDown("e")))
        XCTAssertEqual(completions, [-2])
        XCTAssertFalse(announcement.handleKeyDown(try keyDown("c")))
        XCTAssertFalse(announcement.handleKeyDown(try keyDown("h")))
        XCTAssertEqual(completions, [-2])
    }
}

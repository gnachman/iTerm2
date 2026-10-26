//
//  TmuxCloseAfterDetachPromptTests.swift
//  ModernTests
//
//  When tmux detaches, each of its windows that stays open asks “Close tmux windows after
//  detaching?”. Answering Always closes the windows that asked. Every session's nagging controller
//  hears the answer, and every one of them used to close its session, whether or not it had
//  asked: answering in a detached tmux pane also closed the tmux gateway's session and any other
//  session in the app.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

/// Stands in for a session: records messages shown and whether it was asked to close.
private final class RecordingNaggingDelegate: NSObject, iTermNaggingControllerDelegate {
    var completions = [String: (Int32) -> Void]()
    var closed = false

    func naggingControllerCanShowMessage(withIdentifier identifier: String) -> Bool { true }
    func naggingControllerShowMessage(_ message: String, isQuestion: Bool, important: Bool, identifier: String,
                                      options: [String], completion: @escaping (Int32) -> Void) {
        completions[identifier] = completion
    }
    func naggingControllerShowMarkdownMessage(_ message: String, isQuestion: Bool, important: Bool, identifier: String,
                                              options: [String], completion: @escaping (Int32) -> Void) {
        completions[identifier] = completion
    }
    func naggingControllerRepairSavedArrangement(_ savedArrangementName: String, missingProfileNamed profileName: String,
                                                 guid: String) {}
    func naggingControllerRemoveMessage(withIdentifier identifier: String) {}
    func naggingControllerRestart() {}
    func naggingControllerAbortDownload() {}
    func naggingControllerAbortUpload() {}
    func naggingControllerSetBackgroundImageToFile(withName filename: String?) {}
    func naggingControllerDisableMouseReportingPermanently(_ permanently: Bool) {}
    func naggingControllerDisableBracketedPasteMode() {}
    func naggingControllerResetKeyReportingMode() {}
    func naggingControllerRestoreIconName(to iconName: String, windowName: String) {}
    func naggingControllerCloseSession() { closed = true }
    func naggingControllerRepairInitialWorkingDirectoryOfSession(withGUID guid: String,
                                                                 inArrangementWithName arrangementName: String) {}
    func naggingControllerDisableTriggersInInteractiveApps() {}
    func naggingControllerAssignProfile(toSession arrangementName: String, guid: String) {}
    func naggingControllerPrettyPrintJSON() {}
    func naggingControllerWindow() -> NSWindow? { nil }
    func naggingControllerSetProfileProperties(_ dict: [AnyHashable: Any]) {}
    func naggingControllerAnnouncementWouldObscureCursor(forText text: String) -> Bool { false }
}

final class TmuxCloseAfterDetachPromptTests: XCTestCase {
    private var saved: Bool?

    override func setUp() {
        super.setUp()
        saved = iTermAdvancedSettingsModel.tmuxWindowsShouldCloseAfterDetach()?.pointee.boolValue
        iTermAdvancedSettingsModel.setTmuxWindowsShouldCloseAfterDetach(nil)
    }

    override func tearDown() {
        if let saved {
            var value = ObjCBool(saved)
            iTermAdvancedSettingsModel.setTmuxWindowsShouldCloseAfterDetach(&value)
        } else {
            iTermAdvancedSettingsModel.setTmuxWindowsShouldCloseAfterDetach(nil)
        }
        super.tearDown()
    }

    private func controller(_ delegate: RecordingNaggingDelegate) -> iTermNaggingController {
        let controller = iTermNaggingController()
        controller.delegate = delegate
        return controller
    }

    // Always closes the detached tmux windows that asked, and nothing else.
    func testAlwaysClosesOnlyTheSessionsThatAsked() throws {
        let asker = RecordingNaggingDelegate()
        let otherAsker = RecordingNaggingDelegate()
        let bystander = RecordingNaggingDelegate()
        let controllers = [controller(asker), controller(otherAsker), controller(bystander)]
        XCTAssertFalse(controllers[0].tmuxWindowsShouldCloseAfterDetach())
        XCTAssertFalse(controllers[1].tmuxWindowsShouldCloseAfterDetach())

        try XCTUnwrap(asker.completions["TmuxWindowsShouldCloseAfterDetach"])(0)

        XCTAssertTrue(asker.closed)
        XCTAssertTrue(otherAsker.closed, "another window that asked closes too")
        XCTAssertFalse(bystander.closed, "a session that never asked, like the tmux gateway, stays open")
        withExtendedLifetime(controllers) {}
    }

    func testNeverClosesNothing() throws {
        let asker = RecordingNaggingDelegate()
        let bystander = RecordingNaggingDelegate()
        let controllers = [controller(asker), controller(bystander)]
        XCTAssertFalse(controllers[0].tmuxWindowsShouldCloseAfterDetach())

        try XCTUnwrap(asker.completions["TmuxWindowsShouldCloseAfterDetach"])(1)

        XCTAssertFalse(asker.closed)
        XCTAssertFalse(bystander.closed)
        withExtendedLifetime(controllers) {}
    }
}

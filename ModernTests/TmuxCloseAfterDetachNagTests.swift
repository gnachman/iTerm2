//
//  TmuxCloseAfterDetachNagTests.swift
//  ModernTests
//
//  Answering the “Close tmux windows after detaching?” announcement broadcasts
//  the choice to every session's nagging controller so that all the leftover
//  tmux windows that asked can act on it. Only those windows may close. Every
//  other session (the gateway, which is a plain shell again after detaching,
//  and any unrelated session) must be left alone. QA finding F-252.
//

import XCTest
@testable import iTerm2SharedARC

private final class RecordingNaggingDelegate: NSObject, iTermNaggingControllerDelegate {
    var closeSessionCount = 0
    var shownIdentifiers = [String]()
    var removedIdentifiers = [String]()
    var completions = [String: (Int32) -> Void]()

    func naggingControllerCanShowMessage(withIdentifier identifier: String) -> Bool { true }

    func naggingControllerShowMessage(_ message: String,
                                      isQuestion: Bool,
                                      important: Bool,
                                      identifier: String,
                                      options: [String],
                                      completion: @escaping (Int32) -> Void) {
        shownIdentifiers.append(identifier)
        completions[identifier] = completion
    }

    func naggingControllerShowMarkdownMessage(_ message: String,
                                              isQuestion: Bool,
                                              important: Bool,
                                              identifier: String,
                                              options: [String],
                                              completion: @escaping (Int32) -> Void) {
        shownIdentifiers.append(identifier)
        completions[identifier] = completion
    }

    func naggingControllerRepairSavedArrangement(_ savedArrangementName: String,
                                                 missingProfileNamed profileName: String,
                                                 guid: String) {}
    func naggingControllerRemoveMessage(withIdentifier identifier: String) {
        removedIdentifiers.append(identifier)
    }
    func naggingControllerRestart() {}
    func naggingControllerAbortDownload() {}
    func naggingControllerAbortUpload() {}
    func naggingControllerSetBackgroundImageToFile(withName filename: String?) {}
    func naggingControllerDisableMouseReportingPermanently(_ permanently: Bool) {}
    func naggingControllerDisableBracketedPasteMode() {}
    func naggingControllerResetKeyReportingMode() {}
    func naggingControllerRestoreIconName(to iconName: String, windowName: String) {}
    func naggingControllerCloseSession() {
        closeSessionCount += 1
    }
    func naggingControllerRepairInitialWorkingDirectoryOfSession(withGUID guid: String,
                                                                 inArrangementWithName arrangementName: String) {}
    func naggingControllerDisableTriggersInInteractiveApps() {}
    func naggingControllerAssignProfile(toSession arrangementName: String, guid: String) {}
    func naggingControllerPrettyPrintJSON() {}
    func naggingControllerWindow() -> NSWindow? { nil }
    func naggingControllerSetProfileProperties(_ dict: [AnyHashable: Any]) {}
    func naggingControllerAnnouncementWouldObscureCursor(forText text: String) -> Bool { false }
}

final class TmuxCloseAfterDetachNagTests: XCTestCase {
    private static let identifier = "TmuxWindowsShouldCloseAfterDetach"
    private static let alwaysSelection: Int32 = 0
    private static let neverSelection: Int32 = 1

    private var savedSetting: Bool?

    override func setUp() {
        super.setUp()
        savedSetting = iTermAdvancedSettingsModel.tmuxWindowsShouldCloseAfterDetach()?.pointee.boolValue
        iTermAdvancedSettingsModel.setTmuxWindowsShouldCloseAfterDetach(nil)
    }

    override func tearDown() {
        if let savedSetting {
            var value = ObjCBool(savedSetting)
            iTermAdvancedSettingsModel.setTmuxWindowsShouldCloseAfterDetach(&value)
        } else {
            iTermAdvancedSettingsModel.setTmuxWindowsShouldCloseAfterDetach(nil)
        }
        super.tearDown()
    }

    private func makeController() -> (iTermNaggingController, RecordingNaggingDelegate) {
        let controller = iTermNaggingController()
        let delegate = RecordingNaggingDelegate()
        controller.delegate = delegate
        return (controller, delegate)
    }

    // Asks the question the way a detached tmux window does in tmuxDidDisconnect.
    private func offer(_ controller: iTermNaggingController,
                       _ delegate: RecordingNaggingDelegate) -> (Int32) -> Void {
        XCTAssertFalse(controller.tmuxWindowsShouldCloseAfterDetach())
        XCTAssertEqual(delegate.shownIdentifiers, [Self.identifier])
        return delegate.completions[Self.identifier]!
    }

    func testAlwaysClosesOnlyTheTmuxWindowsThatAsked() {
        let (tmuxWindow, tmuxDelegate) = makeController()
        let (otherTmuxWindow, otherTmuxDelegate) = makeController()
        let (gateway, gatewayDelegate) = makeController()
        let (unrelated, unrelatedDelegate) = makeController()

        let answer = offer(tmuxWindow, tmuxDelegate)
        _ = offer(otherTmuxWindow, otherTmuxDelegate)

        answer(Self.alwaysSelection)

        XCTAssertEqual(tmuxDelegate.closeSessionCount, 1,
                       "The window that showed the announcement should close")
        XCTAssertEqual(otherTmuxDelegate.closeSessionCount, 1,
                       "Another detached window that asked should also close")
        XCTAssertEqual(gatewayDelegate.closeSessionCount, 0,
                       "The gateway never asked and must stay open")
        XCTAssertEqual(unrelatedDelegate.closeSessionCount, 0,
                       "An unrelated session never asked and must stay open")
        XCTAssertTrue(otherTmuxDelegate.removedIdentifiers.contains(Self.identifier),
                      "The other window's copy of the question should be removed")
        withExtendedLifetime([tmuxWindow, otherTmuxWindow, gateway, unrelated]) {}
    }

    func testNeverClosesNothing() {
        let (tmuxWindow, tmuxDelegate) = makeController()
        let (otherTmuxWindow, otherTmuxDelegate) = makeController()
        let (unrelated, unrelatedDelegate) = makeController()

        let answer = offer(tmuxWindow, tmuxDelegate)
        _ = offer(otherTmuxWindow, otherTmuxDelegate)

        answer(Self.neverSelection)

        XCTAssertEqual(tmuxDelegate.closeSessionCount, 0)
        XCTAssertEqual(otherTmuxDelegate.closeSessionCount, 0)
        XCTAssertEqual(unrelatedDelegate.closeSessionCount, 0)
        XCTAssertTrue(otherTmuxDelegate.removedIdentifiers.contains(Self.identifier))
        withExtendedLifetime([tmuxWindow, otherTmuxWindow, unrelated]) {}
    }

    func testRecycledSessionDoesNotCloseOnLaterAlways() {
        let (tmuxWindow, tmuxDelegate) = makeController()
        let (recycled, recycledDelegate) = makeController()

        let answer = offer(tmuxWindow, tmuxDelegate)
        _ = offer(recycled, recycledDelegate)
        // The session was restarted with a new shell, so it is no longer a
        // leftover tmux window.
        recycled.willRecycleSession()

        answer(Self.alwaysSelection)

        XCTAssertEqual(tmuxDelegate.closeSessionCount, 1)
        XCTAssertEqual(recycledDelegate.closeSessionCount, 0)
        withExtendedLifetime([tmuxWindow, recycled]) {}
    }

    // Dismissing the question without answering leaves the window a leftover
    // tmux window, so an Always given elsewhere still closes it.
    func testDismissedOfferStillClosesOnLaterAlways() {
        let (tmuxWindow, tmuxDelegate) = makeController()
        let (dismissed, dismissedDelegate) = makeController()

        let answer = offer(tmuxWindow, tmuxDelegate)
        let dismiss = offer(dismissed, dismissedDelegate)
        dismiss(-2)

        answer(Self.alwaysSelection)

        XCTAssertEqual(tmuxDelegate.closeSessionCount, 1)
        XCTAssertEqual(dismissedDelegate.closeSessionCount, 1)
        withExtendedLifetime([tmuxWindow, dismissed]) {}
    }

    // A window asked twice (for example, after two detaches) closes once.
    func testAskedTwiceClosesOnce() {
        let (tmuxWindow, tmuxDelegate) = makeController()
        let (unrelated, unrelatedDelegate) = makeController()

        let first = offer(tmuxWindow, tmuxDelegate)
        XCTAssertFalse(tmuxWindow.tmuxWindowsShouldCloseAfterDetach())
        let second = tmuxDelegate.completions[Self.identifier]!
        // Replacing the first copy dismisses it.
        first(-2)

        second(Self.alwaysSelection)

        XCTAssertEqual(tmuxDelegate.closeSessionCount, 1)
        XCTAssertEqual(unrelatedDelegate.closeSessionCount, 0)
        withExtendedLifetime([tmuxWindow, unrelated]) {}
    }
}

//
//  NotifyOnStatusChangeControllerTests.swift
//  ModernTests
//
//  Notify on Status Change is a one-shot watch: the next real change to a
//  session's status alerts and disarms. Typing in a session whose status is
//  done or error turns it idle, but that is the user acknowledging a result
//  they have now seen, not news, so it must neither alert nor disarm. And a
//  status that was already showing before anything was watching is still the
//  baseline a later change is measured from.
//

import Carbon
import XCTest
@testable import iTerm2SharedARC

final class NotifyOnStatusChangeControllerTests: XCTestCase {
    private struct Alert: Equatable {
        var session: String
        var from: String?
        var to: String?
    }

    private let windowGuid = UUID().uuidString
    private var sessionGuid = ""
    private var alerts = [Alert]()
    private var tabStatusController: TabStatusController!

    override func setUp() {
        super.setUp()
        sessionGuid = UUID().uuidString
        alerts = []
        let guid = sessionGuid
        tabStatusController = TabStatusController(sessionID: { guid },
                                                  didChange: { _ in })
    }

    override func tearDown() {
        // Clearing removes the status from the shared SessionStatusController
        // so it does not leak into other tests.
        _ = tabStatusController.clearStatus()
        XCTAssertNil(SessionStatusController.instance.statuses[sessionGuid])
        tabStatusController = nil
        super.tearDown()
    }

    private func makeController() -> NotifyOnStatusChangeController {
        let guid = sessionGuid
        let window = windowGuid
        return NotifyOnStatusChangeController(
            windowGuidForSession: { $0 == guid ? window : nil },
            presentAlert: { [weak self] session, from, to in
                self?.alerts.append(Alert(session: session, from: from, to: to))
            })
    }

    private func setStatus(_ text: String) {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = text
        tabStatusController.apply(update)
    }

    // What PTYSession does when the user types in the session.
    private func typeKey() {
        tabStatusController.acknowledge {
            tabStatusController.userDidPressKey()
        }
    }

    func test_windowScope_typingInDoneSessionDoesNotAlertOrDisarm() {
        setStatus("done")
        let controller = makeController()
        controller.toggleWindowArmed(forGuid: windowGuid)
        controller.flush()

        typeKey()
        XCTAssertEqual(SessionStatusController.instance.statuses[sessionGuid]?.statusText, "idle",
                       "Precondition: typing turns a done status idle")
        controller.flush()

        XCTAssertEqual(alerts, [], "Acknowledging a result by typing is not a status change")
        XCTAssertTrue(controller.isWindowArmed(forGuid: windowGuid),
                      "The watch must stay armed for the next real change")

        setStatus("working")
        controller.flush()
        XCTAssertEqual(alerts, [Alert(session: sessionGuid, from: "idle", to: "working")])
        XCTAssertFalse(controller.isWindowArmed(forGuid: windowGuid))
    }

    func test_windowScope_typingInErrorSessionDoesNotAlert() {
        setStatus("error")
        let controller = makeController()
        controller.toggleWindowArmed(forGuid: windowGuid)
        typeKey()
        XCTAssertEqual(SessionStatusController.instance.statuses[sessionGuid]?.statusText, "idle",
                       "Precondition: typing turns an error status idle")
        controller.flush()
        XCTAssertEqual(alerts, [])
        XCTAssertTrue(controller.isWindowArmed(forGuid: windowGuid))
    }

    // The program updates something other than the status text (e.g., its
    // detail or background-task count) in the same debounce burst as the
    // keypress. That is not a status change either, so the acknowledgment
    // still must not alert.
    func test_detailOnlyUpdateInSameBurstAsAcknowledgmentDoesNotAlert() {
        setStatus("done")
        let controller = makeController()
        controller.toggleWindowArmed(forGuid: windowGuid)
        controller.toggleSessionArmed(forGuid: sessionGuid)
        controller.flush()

        typeKey()
        let update = VT100TabStatusUpdate()
        update.detailPresence = .set
        update.detail = "reacting to the key"
        tabStatusController.apply(update)
        controller.flush()

        XCTAssertEqual(alerts, [])
        XCTAssertTrue(controller.isWindowArmed(forGuid: windowGuid))
        XCTAssertTrue(controller.isSessionArmed(forGuid: sessionGuid))
    }

    func test_sessionScope_typingInDoneSessionDoesNotAlertOrDisarm() {
        setStatus("done")
        let controller = makeController()
        controller.toggleSessionArmed(forGuid: sessionGuid)

        typeKey()
        controller.flush()
        XCTAssertEqual(alerts, [])
        XCTAssertTrue(controller.isSessionArmed(forGuid: sessionGuid))

        setStatus("working")
        controller.flush()
        XCTAssertEqual(alerts, [Alert(session: sessionGuid, from: "idle", to: "working")])
        XCTAssertFalse(controller.isSessionArmed(forGuid: sessionGuid))
    }

    // An acknowledgment and a real change landing in the same debounce burst:
    // the real change still alerts, measured from before the burst.
    func test_realChangeInSameBurstAsAcknowledgmentStillAlerts() {
        setStatus("done")
        let controller = makeController()
        controller.toggleWindowArmed(forGuid: windowGuid)
        controller.flush()

        typeKey()
        setStatus("working")
        controller.flush()
        XCTAssertEqual(alerts, [Alert(session: sessionGuid, from: "done", to: "working")])
    }

    // Typing when the status is not done or error changes nothing, and
    // certainly does not alert.
    func test_typingWithNoStatusDoesNotAlert() {
        let controller = makeController()
        controller.toggleWindowArmed(forGuid: windowGuid)
        typeKey()
        controller.flush()
        XCTAssertEqual(alerts, [])
        XCTAssertTrue(controller.isWindowArmed(forGuid: windowGuid))
    }

    // The status was set before the controller existed (it is created lazily,
    // typically when the Window menu is first validated). It is still the
    // baseline, so a later change reports the right “from”.
    func test_windowScope_statusSetBeforeControllerExistedIsTheBaseline() {
        setStatus("done")
        let controller = makeController()
        controller.toggleWindowArmed(forGuid: windowGuid)
        setStatus("working")
        controller.flush()
        XCTAssertEqual(alerts, [Alert(session: sessionGuid, from: "done", to: "working")])
    }

    // Restating the status that was already showing before the controller
    // existed is not a change.
    func test_windowScope_restatingPreexistingStatusDoesNotAlert() {
        setStatus("working")
        let controller = makeController()
        controller.toggleWindowArmed(forGuid: windowGuid)
        let update = VT100TabStatusUpdate()
        update.detailPresence = .set
        update.detail = "still working"
        tabStatusController.apply(update)
        controller.flush()
        XCTAssertEqual(alerts, [])
        XCTAssertTrue(controller.isWindowArmed(forGuid: windowGuid))
    }

    // End to end through PTYSession with an OSC 7501 report, the path in the
    // original report: printf '\033]7501;state=done\007', arm, type a key.
    func test_osc7501DoneThenKeyDownInSessionDoesNotAlert() throws {
        let session = PTYSession(synthetic: false)!
        let guid = session.guid
        defer {
            session.screenRemoveProgramStatusRecords()
            session.screenSetTabStatus(VT100TabStatusUpdate.clear)
            XCTAssertNil(SessionStatusController.instance.statuses[guid])
        }
        session.screenReportProgramStatusReports([ProgramStatusReport.parse("state=done")!])
        XCTAssertEqual(SessionStatusController.instance.statuses[guid]?.statusText, "done")

        let window = windowGuid
        let controller = NotifyOnStatusChangeController(
            windowGuidForSession: { $0 == guid ? window : nil },
            presentAlert: { [weak self] session, from, to in
                self?.alerts.append(Alert(session: session, from: from, to: to))
            })
        controller.toggleWindowArmed(forGuid: windowGuid)
        controller.toggleSessionArmed(forGuid: guid)

        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown,
                                                   location: .zero,
                                                   modifierFlags: [],
                                                   timestamp: 0,
                                                   windowNumber: 0,
                                                   context: nil,
                                                   characters: "x",
                                                   charactersIgnoringModifiers: "x",
                                                   isARepeat: false,
                                                   keyCode: UInt16(kVK_ANSI_X)))
        _ = session.textViewShouldAcceptKeyDownEvent(event)
        XCTAssertEqual(SessionStatusController.instance.statuses[guid]?.statusText, "idle",
                       "Precondition: the keypress acknowledged the done status")
        controller.flush()
        XCTAssertEqual(alerts, [])
        XCTAssertTrue(controller.isWindowArmed(forGuid: windowGuid))
        XCTAssertTrue(controller.isSessionArmed(forGuid: guid))

        session.screenReportProgramStatusReports([ProgramStatusReport.parse("state=working")!])
        controller.flush()
        XCTAssertEqual(alerts, [Alert(session: guid, from: "idle", to: "working")])
        XCTAssertFalse(controller.isWindowArmed(forGuid: windowGuid))
        XCTAssertFalse(controller.isSessionArmed(forGuid: guid))
    }
}

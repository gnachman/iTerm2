//
//  AppModelMacStatusTests.swift
//  iTerm2CompanionTests
//
//  A revision-14 Mac tells the phone which alerts are showing on it and whether
//  it can serve requests (CompanionMacStatus), in its hello reply and in live
//  macStatusChanged events. These tests pin what the phone does with that:
//
//    - What is presented: the full card for an alert that is blocking the Mac,
//      a pill for one that is not (or that the user set aside), a banner when
//      the Mac is blocked by something the phone cannot answer.
//    - Answering: what is sent, that it is sent once, and when “don’t ask
//      again” is honored.
//    - A rejected answer leaves the alert up as “answer this on your Mac”.
//    - When requests should hold their timeouts.
//

import XCTest
import CompanionProtocol
@testable import iTerm2Companion

@MainActor
final class AppModelMacStatusTests: XCTestCase {
    private func alert(_ id: String,
                       isAppModal: Bool = true,
                       suppressionLabel: String? = "Remember my choice") -> CompanionModalAlert {
        return CompanionModalAlert(
            id: id,
            heading: "Heading \(id)",
            body: "Body \(id)",
            buttons: [.init(title: "Allow", isCancel: false, isDestructive: false, rememberable: true),
                      .init(title: "Deny", isCancel: false, isDestructive: true, rememberable: false),
                      .init(title: "Cancel", isCancel: true, isDestructive: false, rememberable: false)],
            suppressionLabel: suppressionLabel,
            hasAccessory: false,
            isAppModal: isAppModal)
    }

    private func status(_ alerts: [CompanionModalAlert], blocked: Bool = false) -> CompanionMacStatus {
        return CompanionMacStatus(modalAlerts: alerts, mainBlocked: blocked)
    }

    private func handshake(revision: Int = CompanionProtocolVersion.modalAlertRevision,
                           macStatus: CompanionMacStatus? = nil) -> CompanionClient.HandshakeResult {
        return CompanionClient.HandshakeResult(compatibility: .compatible,
                                               wantsNotificationPermission: false,
                                               peerRevision: revision,
                                               aiAvailable: true,
                                               macStatus: macStatus)
    }

    /// A model connected to a revision-14 Mac.
    private func connectedModel(_ macStatus: CompanionMacStatus? = nil) -> AppModel {
        let model = AppModel()
        model.testApplyHandshake(handshake(macStatus: macStatus))
        return model
    }

    // MARK: What is presented

    func test_nothingIsPresentedByDefault() {
        let model = AppModel()
        XCTAssertEqual(model.macAlertPresentation, .none)
        XCTAssertFalse(model.macIsBlocked)
    }

    /// The status rides the hello reply so it is known before the phone asks for
    /// its lists, which a blocked Mac would not answer.
    func test_handshakeAppliesTheStatusItCarries() {
        let model = connectedModel(status([alert("A")], blocked: true))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .ready))
        XCTAssertTrue(model.macIsBlocked)
    }

    func test_handshakeWithoutStatusClearsAnEarlierOne() {
        let model = connectedModel(status([alert("A")], blocked: true))
        // Reconnected, and the Mac (or an older Mac) reports nothing.
        model.testApplyHandshake(handshake(macStatus: nil))
        XCTAssertEqual(model.macAlertPresentation, .none)
        XCTAssertFalse(model.macIsBlocked)
    }

    func test_appModalAlertIsShownAsTheCardAndTheTopOneWins() {
        let model = connectedModel()
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("Bottom"), alert("Top")])))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("Top"), .ready),
                       "only the alert in front can be answered")
    }

    func test_alertGoingAwayClearsTheCard() {
        let model = connectedModel(status([alert("A")]))
        model.testHandleHostEvent(.macStatusChanged(status: status([])))
        XCTAssertEqual(model.macAlertPresentation, .none)
    }

    /// A sheet that does not block the Mac is not worth interrupting for.
    func test_alertThatDoesNotBlockTheMacIsShownAsAPill() {
        let model = connectedModel(status([alert("A", isAppModal: false)]))
        XCTAssertEqual(model.macAlertPresentation, .pill(alert("A", isAppModal: false)))
        model.showMacAlert()
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A", isAppModal: false), .ready))
    }

    func test_blockedWithNothingToAnswerShowsTheBanner() {
        let model = connectedModel(status([], blocked: true))
        XCTAssertEqual(model.macAlertPresentation, .blockedBanner)
        model.testHandleHostEvent(.macStatusChanged(status: status([], blocked: false)))
        XCTAssertEqual(model.macAlertPresentation, .none)
    }

    // MARK: Not now

    func test_notNowSetsTheAlertAsideUntilReopened() {
        let model = connectedModel(status([alert("A")]))
        model.dismissMacAlert()
        XCTAssertEqual(model.macAlertPresentation, .pill(alert("A")))
        // The Mac repeating the same status must not bring the card back.
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A")], blocked: true)))
        XCTAssertEqual(model.macAlertPresentation, .pill(alert("A")))
        model.showMacAlert()
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .ready))
    }

    func test_aNewAlertIsShownEvenAfterAnEarlierOneWasSetAside() {
        let model = connectedModel(status([alert("A")]))
        model.dismissMacAlert()
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("B")])))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("B"), .ready))
    }

    // MARK: Answering

    func test_answerIsSentOnceAndTheCardShowsItIsWaiting() {
        let model = connectedModel(status([alert("A")]))
        model.answerMacAlert(buttonIndex: 0, suppress: true)
        XCTAssertEqual(model.testSentAlertAnswers, [.init(alertID: "A", buttonIndex: 0, suppress: true)])
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .sending))
        // A second tap while waiting sends nothing.
        model.answerMacAlert(buttonIndex: 1, suppress: false)
        XCTAssertEqual(model.testSentAlertAnswers.count, 1)

        model.testHandleHostEvent(.macStatusChanged(status: status([])))
        XCTAssertEqual(model.macAlertPresentation, .none)
    }

    func test_suppressIsSentOnlyForAButtonThatCanBeRemembered() {
        let model = connectedModel(status([alert("A")]))
        model.answerMacAlert(buttonIndex: 1, suppress: true)
        XCTAssertEqual(model.testSentAlertAnswers, [.init(alertID: "A", buttonIndex: 1, suppress: false)],
                       "“Deny” cannot be remembered, so the toggle does not apply to it")
    }

    func test_suppressIsNotSentForAnAlertWithoutACheckbox() {
        let model = connectedModel(status([alert("A", suppressionLabel: nil)]))
        model.answerMacAlert(buttonIndex: 0, suppress: true)
        XCTAssertEqual(model.testSentAlertAnswers, [.init(alertID: "A", buttonIndex: 0, suppress: false)])
    }

    func test_answerWithABadIndexOrNoAlertSendsNothing() {
        let model = connectedModel()
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A")])))
        model.answerMacAlert(buttonIndex: 3, suppress: false)
        model.answerMacAlert(buttonIndex: -1, suppress: false)
        XCTAssertEqual(model.testSentAlertAnswers, [])
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .ready))
    }

    /// After the first alert is answered, the next one in the stack is ready to
    /// answer: the waiting state belongs to the alert, not the card.
    func test_theNextAlertIsReadyAfterTheFirstIsAnswered() {
        let model = connectedModel(status([alert("Under"), alert("Top")]))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("Under")])))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("Under"), .ready))
        model.answerMacAlert(buttonIndex: 2, suppress: false)
        XCTAssertEqual(model.testSentAlertAnswers.map { $0.alertID }, ["Top", "Under"])
    }

    // MARK: Rejection

    func test_rejectedAnswerLeavesTheAlertUpToBeAnsweredOnTheMac() {
        let model = connectedModel(status([alert("A")]))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        model.testHandleHostEvent(.modalAlertAnswerRejected(alertID: "A"))
        // The Mac follows a rejection with its status, unchanged here.
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A")])))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .answerOnMac))
        // Tapping again would only be rejected again.
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        XCTAssertEqual(model.testSentAlertAnswers.count, 1)
    }

    func test_rejectionClearsWhenTheAlertsChange() {
        let model = connectedModel(status([alert("A")]))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        model.testHandleHostEvent(.modalAlertAnswerRejected(alertID: "A"))
        // Whatever was in front of it is gone, and so is the alert.
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("B")])))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("B"), .ready))
    }

    func test_rejectionForAnAlertThatIsNotShowingIsIgnored() {
        let model = connectedModel(status([alert("A")]))
        model.testHandleHostEvent(.modalAlertAnswerRejected(alertID: "Gone"))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .ready))
    }

    // MARK: Holding timeouts

    func test_requestsHoldTheirTimeoutsWhileTheMacCannotAnswer() {
        let model = connectedModel()
        XCTAssertFalse(model.macIsBlocked)
        // The Mac says its main thread is not responding.
        model.testHandleHostEvent(.macStatusChanged(status: status([], blocked: true)))
        XCTAssertTrue(model.macIsBlocked)
        // An alert that blocks the Mac counts even before the Mac's own stall
        // detector has noticed.
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A")], blocked: false)))
        XCTAssertTrue(model.macIsBlocked)
        // A sheet that does not block it does not.
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A", isAppModal: false)], blocked: false)))
        XCTAssertFalse(model.macIsBlocked)
        model.testHandleHostEvent(.macStatusChanged(status: status([])))
        XCTAssertFalse(model.macIsBlocked)
    }

    // MARK: Unpairing

    /// The status belongs to the Mac it came from. Once unpaired, nothing of it
    /// may remain: not the card over the pairing scanner, not held timeouts.
    func test_beingUnpairedByTheMacClearsItsStatus() {
        let model = connectedModel(status([alert("A")], blocked: true))
        XCTAssertTrue(model.macIsBlocked)
        model.testHandleHostEvent(.unpaired)
        XCTAssertEqual(model.macAlertPresentation, .none)
        XCTAssertFalse(model.macIsBlocked)
        XCTAssertEqual(model.macStatus, status([]))
    }

    func test_unpairingFromThePhoneClearsTheMacStatus() {
        let model = connectedModel(status([alert("A")], blocked: true))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        model.disconnectFromMac()
        XCTAssertEqual(model.macAlertPresentation, .none)
        XCTAssertFalse(model.macIsBlocked)
        // Nothing carries over to the next Mac: an alert with the same ID
        // there starts out ready, not "sending".
        model.testApplyHandshake(handshake(macStatus: status([alert("A")])))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .ready))
    }

    // MARK: An answer the Mac never acts on

    /// The Mac reports an accepted answer only by the alert going away. If it
    /// never does (the press had no effect, or the Mac cannot run it yet), the
    /// card must not sit on its spinner with every button disabled forever.
    func test_sendingStateTimesOutAndRestoresTheButtons() {
        let model = connectedModel(status([alert("A")]))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .sending))
        model.testExpireAlertAnswerTimeout(alertID: "A")
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .ready))
        // And the user can try again.
        model.answerMacAlert(buttonIndex: 1, suppress: false)
        XCTAssertEqual(model.testSentAlertAnswers.map { $0.buttonIndex }, [0, 1])
    }

    func test_timeoutForAnEarlierAlertDoesNotDisturbTheCurrentOne() {
        let model = connectedModel(status([alert("A")]))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("B")])))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        // A's timer fires late.
        model.testExpireAlertAnswerTimeout(alertID: "A")
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("B"), .sending))
    }

    // MARK: An older Mac

    /// A pre-14 Mac never sends a status. If one somehow arrived, the phone must
    /// not send an answer the Mac would not understand.
    func test_nothingIsSentToAMacThatDoesNotUnderstandAnswers() {
        let model = AppModel()
        model.testApplyHandshake(handshake(revision: CompanionProtocolVersion.modalAlertRevision - 1))
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A")])))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        XCTAssertEqual(model.testSentAlertAnswers, [])
    }
}

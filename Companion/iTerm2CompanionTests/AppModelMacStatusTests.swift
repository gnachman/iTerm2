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
                       suppressionLabel: String? = "Remember my choice",
                       sessionGuids: [String] = []) -> CompanionModalAlert {
        return CompanionModalAlert(
            id: id,
            heading: "Heading \(id)",
            body: "Body \(id)",
            buttons: [.init(title: "Allow", isCancel: false, isDestructive: false, rememberable: true),
                      .init(title: "Deny", isCancel: false, isDestructive: true, rememberable: false),
                      .init(title: "Cancel", isCancel: true, isDestructive: false, rememberable: false)],
            suppressionLabel: suppressionLabel,
            hasAccessory: false,
            isAppModal: isAppModal,
            sessionGuids: sessionGuids)
    }

    /// Unless a test says otherwise, an alert that can block the Mac is
    /// blocking it, which is the case these tests were first written for. The
    /// tests under “An alert that is not blocking the Mac” cover the rest.
    private func status(_ alerts: [CompanionModalAlert], blocked: Bool? = nil) -> CompanionMacStatus {
        return CompanionMacStatus(modalAlerts: alerts,
                                  mainBlocked: blocked ?? alerts.contains { $0.isAppModal })
    }

    private func viewSession(_ guid: String, in model: AppModel) {
        model.selectedTab = .sessions
        model.sessionsPath = [.session(guid: guid, title: "Session", originatingChatID: nil)]
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

    // MARK: An alert that is not blocking the Mac

    /// An alert started by something the user did at the Mac leaves the Mac
    /// able to serve the phone. It has nothing to do with what the phone is
    /// looking at, so it does not interrupt.
    func test_alertThatCouldBlockTheMacButIsNotWaitsBehindThePill() {
        let model = connectedModel(status([alert("A")], blocked: false))
        XCTAssertEqual(model.macAlertPresentation, .pill(alert("A")))
        XCTAssertFalse(model.macIsBlocked)
        model.showMacAlert()
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .ready))
    }

    /// The Mac finds out a moment after the alert appears that it is blocked.
    func test_thePillBecomesTheCardWhenTheMacTurnsOutToBeBlocked() {
        let model = connectedModel(status([alert("A")], blocked: false))
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A")], blocked: true)))
        XCTAssertEqual(model.macAlertPresentation, .overlay(alert("A"), .ready))
        XCTAssertTrue(model.macIsBlocked)
    }

    // MARK: Alerts about a session

    func test_alertAboutTheSessionOnScreenIsShownAsTheCard() {
        let about = alert("A", sessionGuids: ["pane-1", "pane-2"])
        let model = connectedModel()
        viewSession("pane-2", in: model)
        model.testHandleHostEvent(.macStatusChanged(status: status([about], blocked: false)))
        XCTAssertEqual(model.macAlertPresentation, .overlay(about, .ready))
    }

    func test_alertAboutAnotherSessionWaitsBehindThePill() {
        let about = alert("A", sessionGuids: ["pane-1"])
        let model = connectedModel()
        viewSession("other", in: model)
        model.testHandleHostEvent(.macStatusChanged(status: status([about], blocked: false)))
        XCTAssertEqual(model.macAlertPresentation, .pill(about))
    }

    func test_navigatingToTheSessionAnAlertIsAboutBringsUpTheCard() {
        let about = alert("A", sessionGuids: ["pane-1"])
        let model = connectedModel(status([about], blocked: false))
        XCTAssertEqual(model.macAlertPresentation, .pill(about))
        viewSession("pane-1", in: model)
        XCTAssertEqual(model.macAlertPresentation, .overlay(about, .ready))
        // And leaving puts it away again.
        model.sessionsPath = []
        XCTAssertEqual(model.macAlertPresentation, .pill(about))
    }

    func test_alertAboutASessionStillInterruptsEverywhereWhenTheMacIsBlocked() {
        let about = alert("A", sessionGuids: ["pane-1"])
        let model = connectedModel()
        viewSession("other", in: model)
        model.testHandleHostEvent(.macStatusChanged(status: status([about], blocked: true)))
        XCTAssertEqual(model.macAlertPresentation, .overlay(about, .ready))
    }

    func test_sheetAboutTheSessionOnScreenIsShownAsTheCard() {
        let sheet = alert("A", isAppModal: false, sessionGuids: ["pane-1"])
        let model = connectedModel(status([sheet]))
        XCTAssertEqual(model.macAlertPresentation, .pill(sheet))
        viewSession("pane-1", in: model)
        XCTAssertEqual(model.macAlertPresentation, .overlay(sheet, .ready))
    }

    func test_notNowSticksForAnAlertAboutTheSessionOnScreen() {
        let about = alert("A", sessionGuids: ["pane-1"])
        let model = connectedModel(status([about], blocked: false))
        viewSession("pane-1", in: model)
        model.dismissMacAlert()
        XCTAssertEqual(model.macAlertPresentation, .pill(about))
        // Leaving and coming back does not undo “Not now”.
        model.sessionsPath = []
        viewSession("pane-1", in: model)
        XCTAssertEqual(model.macAlertPresentation, .pill(about))
    }

    func test_theSessionOnScreenIsTheTopOfTheSelectedTabsStack() {
        let model = connectedModel()
        XCTAssertNil(model.viewedSessionGuid)
        model.sessionsPath = [.workgroup(id: "w", title: "W"),
                              .session(guid: "pane-1", title: "One", originatingChatID: nil)]
        XCTAssertNil(model.viewedSessionGuid, "the Sessions tab is not the one showing")
        model.selectedTab = .sessions
        XCTAssertEqual(model.viewedSessionGuid, "pane-1")
        // A chat pushed over the session covers it.
        model.sessionsPath.append(.conversation(chatID: "c"))
        XCTAssertNil(model.viewedSessionGuid)
        // A session reached from a chat, on the Chats tab.
        model.selectedTab = .chats
        model.navigationPath = [.conversation(chatID: "c"),
                                .session(guid: "pane-9", title: "Nine", originatingChatID: "c")]
        XCTAssertEqual(model.viewedSessionGuid, "pane-9")
    }

    /// The session list marks the sessions that have an alert waiting.
    func test_sessionsWithAnAlertWaitingAreListed() {
        let model = connectedModel(status([alert("Under", sessionGuids: ["pane-1"]),
                                           alert("Top", sessionGuids: ["pane-2", "pane-3"])], blocked: false))
        XCTAssertEqual(model.macAlertSessionGuids, ["pane-1", "pane-2", "pane-3"])
        model.testHandleHostEvent(.macStatusChanged(status: status([])))
        XCTAssertEqual(model.macAlertSessionGuids, [])
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
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A")], blocked: true)))
        XCTAssertTrue(model.macIsBlocked)
        // An alert being up is not enough: the Mac says within a moment of
        // showing one whether it is blocked, and until it does it is serving
        // requests as usual.
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A")], blocked: false)))
        XCTAssertFalse(model.macIsBlocked)
        model.testHandleHostEvent(.macStatusChanged(status: status([alert("A", isAppModal: false)], blocked: false)))
        XCTAssertFalse(model.macIsBlocked)
        model.testHandleHostEvent(.macStatusChanged(status: status([])))
        XCTAssertFalse(model.macIsBlocked)
    }

    // MARK: Inputs

    private func alertWithInputs() -> CompanionModalAlert {
        var alert = alert("A")
        alert.inputs = [
            .init(id: "name", label: nil, kind: CompanionModalAlert.Input.textKind, value: "draft"),
            .init(id: "spaces", label: "Tab size in spaces:", kind: CompanionModalAlert.Input.integerKind,
                  value: "4", minimum: 0, maximum: 100),
        ]
        return alert
    }

    func test_answerCarriesWhatWasEnteredForTheAlertsInputs() {
        let model = connectedModel(status([alertWithInputs()]))
        model.answerMacAlert(buttonIndex: 0, suppress: false,
                             inputs: ["name": "requests", "spaces": "8", "notAnInput": "x"])
        XCTAssertEqual(model.testSentAlertAnswers,
                       [.init(alertID: "A", buttonIndex: 0, suppress: false,
                              inputs: ["name": "requests", "spaces": "8"])],
                       "only the inputs the alert has are sent")
    }

    func test_answerWithoutInputsSendsNone() {
        let model = connectedModel(status([alertWithInputs()]))
        model.answerMacAlert(buttonIndex: 0, suppress: false)
        XCTAssertEqual(model.testSentAlertAnswers, [.init(alertID: "A", buttonIndex: 0, suppress: false)])
    }

    /// The Mac refuses the whole answer if a number is out of range or not a
    /// number, so the phone never sends one.
    func test_numbersAreMadeAcceptableBeforeTheyAreSent() {
        let spaces = alertWithInputs().inputs[1]
        XCTAssertEqual(AppModel.valueToSend(for: spaces, entered: "8"), "8")
        XCTAssertEqual(AppModel.valueToSend(for: spaces, entered: " 8 "), "8")
        XCTAssertEqual(AppModel.valueToSend(for: spaces, entered: "250"), "100", "clamped to the maximum")
        XCTAssertEqual(AppModel.valueToSend(for: spaces, entered: "-3"), "0", "clamped to the minimum")
        XCTAssertEqual(AppModel.valueToSend(for: spaces, entered: ""), "4", "falls back to the Mac's value")
        XCTAssertEqual(AppModel.valueToSend(for: spaces, entered: "eight"), "4")

        let name = alertWithInputs().inputs[0]
        XCTAssertEqual(AppModel.valueToSend(for: name, entered: " as typed "), " as typed ")
        XCTAssertEqual(AppModel.valueToSend(for: name, entered: ""), "")

        let model = connectedModel(status([alertWithInputs()]))
        model.answerMacAlert(buttonIndex: 0, suppress: false, inputs: ["spaces": "999"])
        XCTAssertEqual(model.testSentAlertAnswers.first?.inputs, ["spaces": "100"])
    }

    /// A password is sent exactly as typed: no trimming, no fallback.
    func test_secretIsSentAsTyped() {
        var asking = alert("A")
        asking.inputs = [.init(id: "password", label: "Password:",
                               kind: CompanionModalAlert.Input.secretKind, value: "")]
        XCTAssertEqual(AppModel.valueToSend(for: asking.inputs[0], entered: " correct horse "), " correct horse ")
        let model = connectedModel(status([asking]))
        model.answerMacAlert(buttonIndex: 0, suppress: false, inputs: ["password": " correct horse "])
        XCTAssertEqual(model.testSentAlertAnswers.first?.inputs, ["password": " correct horse "])
    }

    /// The phone never knows what a password field holds on the Mac, so a
    /// secret left blank is left out: the Mac keeps whatever is in its field
    /// (typed there, or filled by a password manager) instead of clearing it.
    func test_secretLeftBlankIsNotSent() {
        var asking = alert("A")
        asking.inputs = [.init(id: "user", label: nil, kind: CompanionModalAlert.Input.textKind, value: "me"),
                         .init(id: "password", label: "Password:",
                               kind: CompanionModalAlert.Input.secretKind, value: "")]
        let model = connectedModel(status([asking]))
        model.answerMacAlert(buttonIndex: 0, suppress: false, inputs: ["user": "", "password": ""])
        XCTAssertEqual(model.testSentAlertAnswers.first?.inputs, ["user": ""],
                       "ordinary text may be cleared; a blank secret is not sent")
    }

    /// A button the Mac does not offer to the phone is not shown, and nothing
    /// is sent for it even if something asks.
    func test_buttonThatIsNotOfferedCannotBeAnswered() {
        var asking = alert("A")
        asking.buttons.append(.init(title: "Password Manager", isCancel: false, isDestructive: false,
                                    rememberable: false, offered: false))
        let model = connectedModel(status([asking]))
        model.answerMacAlert(buttonIndex: asking.buttons.count - 1, suppress: false)
        XCTAssertEqual(model.testSentAlertAnswers, [])
        XCTAssertEqual(model.macAlertPresentation, .overlay(asking, .ready))
    }

    // MARK: Which connection a callback came from

    /// A transport that stays open until closed and says when it was.
    private final class FakeTransport: MessageTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var closed = false
        private var waiters: [CheckedContinuation<Data, Error>] = []
        var isClosed: Bool { lock.withLock { closed } }
        func send(_ frame: Data) async throws {
            if isClosed { throw TransportError.closed }
        }
        func receive() async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                let alreadyClosed = lock.withLock { () -> Bool in
                    if closed { return true }
                    waiters.append(continuation)
                    return false
                }
                if alreadyClosed {
                    continuation.resume(throwing: TransportError.closed)
                }
            }
        }
        func close() async {
            let pending = lock.withLock { () -> [CheckedContinuation<Data, Error>] in
                closed = true
                defer { waiters = [] }
                return waiters
            }
            pending.forEach { $0.resume(throwing: TransportError.closed) }
        }
    }

    private func makeClient() -> (CompanionClient, FakeTransport) {
        let transport = FakeTransport()
        return (CompanionClient(session: CompanionSession(transport: transport)), transport)
    }

    /// Waits for a client the model dropped to be closed. Closing is started by
    /// the model and finishes on its own, so this returns as soon as it has.
    /// The bound is far longer than that takes; it only keeps a failure from
    /// hanging the test.
    private func waitUntilClosed(_ transport: FakeTransport, _ message: String) async {
        for _ in 0..<30_000 where !transport.isClosed {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(transport.isClosed, message)
    }

    /// The liveness probe gave up on a connection and a new one replaced it.
    /// When the old socket finally reports its close, that must not tear down
    /// the new connection or wipe what the Mac just said over it.
    func test_lateCloseFromAnAbandonedConnectionIsIgnored() {
        let model = connectedModel(status([alert("A")], blocked: true))
        let (abandoned, _) = makeClient()
        let (current, _) = makeClient()
        model.testInstallClient(current)

        model.testClientDidClose(abandoned, error: TransportError.closed)

        XCTAssertTrue(model.testIsCurrentClient(current))
        XCTAssertEqual(model.macStatus, status([alert("A")], blocked: true))
        XCTAssertFalse(model.isReconnecting)
    }

    func test_lateEventFromAnAbandonedConnectionIsIgnored() {
        let model = connectedModel(status([]))
        let (abandoned, _) = makeClient()
        let (current, _) = makeClient()
        model.testInstallClient(current)

        model.testClientDidReceive(.macStatusChanged(status: status([alert("Stale")], blocked: true)), from: abandoned)
        XCTAssertEqual(model.macStatus, status([]))

        model.testClientDidReceive(.macStatusChanged(status: status([alert("Fresh")], blocked: true)), from: current)
        XCTAssertEqual(model.macStatus, status([alert("Fresh")], blocked: true))
    }

    /// A connection the phone gives up on is closed, not just forgotten, so it
    /// cannot go on delivering events or report its own end later.
    func test_aConnectionThatIsGivenUpOnIsClosed() async {
        let model = connectedModel(status([alert("A")], blocked: true))
        let (client, transport) = makeClient()
        model.testInstallClient(client)

        model.testLivenessProbeFoundDeadConnection()

        XCTAssertFalse(model.testIsCurrentClient(client))
        XCTAssertEqual(model.macStatus, status([]))
        await waitUntilClosed(transport, "the abandoned connection was left open")
    }

    /// The probe can find the connection dead while a reconnect is still under
    /// way (the new connection said the Mac is blocked, then died). The request
    /// the reconnect is waiting on is held because the Mac was blocked, so the
    /// status must be cleared and the connection closed for that request to
    /// fail and the reconnect to try again.
    func test_probeFailureDuringAReconnectReleasesWhatTheReconnectIsWaitingOn() async {
        let model = connectedModel()
        let (client, transport) = makeClient()
        model.testInstallClient(client)
        model.isReconnecting = true
        model.testApplyHandshake(handshake(macStatus: status([alert("A")], blocked: true)))
        XCTAssertTrue(model.macIsBlocked)

        model.testLivenessProbeFoundDeadConnection()

        XCTAssertFalse(model.macIsBlocked, "held requests keep waiting while this is set")
        XCTAssertEqual(model.macAlertPresentation, .none, "a card from the dead connection is still up")
        await waitUntilClosed(transport, "the reconnect's request is never failed")
        model.isReconnecting = false
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

//
//  iTermWarningRemoteAnswerTests.swift
//  iTerm2 ModernTests
//
//  iTermWarning publishes each alert it shows to ModalAlertRegistry so the
//  paired companion app can show it and press a button. These tests pin:
//
//    - How a warning is described: its text, buttons and their roles, the
//      "don't ask again" checkbox, and what is deliberately left out.
//    - What pressing a button does: it clicks that button, and first checks
//      the "don't ask again" box only when the warning has one and the button's
//      choice may be remembered.
//
//    - End to end: a warning run from a main-queue callout (so its nested run
//      loop freezes the main queue) registers itself, is answered from another
//      thread, returns the pressed button, remembers the choice when asked to,
//      and unregisters.
//
//  No alert is ever shown. The press tests build the warning's NSAlert without
//  running it and point its buttons at a spy. The end-to-end tests use
//  iTermWarning's headless mode, in which a warning does everything it normally
//  does except put the alert on screen.
//

import AppKit
import XCTest
import os
@testable import iTerm2SharedARC

final class iTermWarningRemoteAnswerTests: XCTestCase {
    private var identifiers: [String] = []

    override func setUp() {
        super.setUp()
        iTermWarning.setRunsHeadlessModals(true)
    }

    override func tearDown() {
        iTermWarning.cancelHeadlessModals()
        iTermWarning.setRunsHeadlessModals(false)
        let defaults = iTermUserDefaults.userDefaults()
        for identifier in identifiers {
            defaults.removeObject(forKey: identifier)
            defaults.removeObject(forKey: identifier + "_selection")
            defaults.removeObject(forKey: identifier + "_SilenceUntil")
        }
        identifiers = []
        super.tearDown()
    }

    private func uniqueIdentifier() -> String {
        let identifier = "NoSyncRemoteAnswerTest_" + UUID().uuidString
        identifiers.append(identifier)
        return identifier
    }

    @MainActor
    private func makeWarning(actions: [String] = ["Allow", "Deny", "Cancel"],
                             type: iTermWarningType = .kiTermWarningTypePermanentlySilenceable,
                             identifier: String?) -> iTermWarning {
        let warning = iTermWarning()
        warning.heading = "Heading"
        warning.title = "The main text."
        warning.actionLabels = actions
        warning.cancelLabel = "Cancel"
        warning.warningType = type
        warning.identifier = identifier
        return warning
    }

    // MARK: Describing a warning

    @MainActor
    func testDescriptorCarriesTextButtonsAndRoles() throws {
        let warning = makeWarning(identifier: uniqueIdentifier())
        warning.doNotRememberLabels = ["Deny"]
        warning.warningActions?[1].destructive = true
        XCTAssertTrue(warning.remotelyAnswerable, "warnings are answerable unless they opt out")

        let descriptor = try XCTUnwrap(warning.modalAlertDescriptor(whenAppModal: true))
        XCTAssertEqual(descriptor.heading, "Heading")
        XCTAssertEqual(descriptor.body, "The main text.")
        XCTAssertEqual(descriptor.buttons.map { $0.title }, ["Allow", "Deny", "Cancel"])
        XCTAssertEqual(descriptor.buttons.map { $0.isCancel }, [false, false, true])
        XCTAssertEqual(descriptor.buttons.map { $0.isDestructive }, [false, true, false])
        XCTAssertEqual(descriptor.buttons.map { $0.rememberable }, [true, false, false],
                       "neither Cancel nor a do-not-remember action can be remembered")
        XCTAssertFalse(descriptor.hasAccessory)
        XCTAssertTrue(descriptor.isAppModal)

        let sheet = try XCTUnwrap(warning.modalAlertDescriptor(whenAppModal: false))
        XCTAssertFalse(sheet.isAppModal)
    }

    @MainActor
    func testDefaultHeadingIsUsedWhenNoneIsSet() throws {
        let warning = makeWarning(identifier: uniqueIdentifier())
        warning.heading = nil
        let descriptor = try XCTUnwrap(warning.modalAlertDescriptor(whenAppModal: true))
        XCTAssertFalse(descriptor.heading.isEmpty)
    }

    @MainActor
    func testSuppressionLabelFollowsTheWarningType() throws {
        // No checkbox, no label.
        let persistent = makeWarning(type: .kiTermWarningTypePersistent, identifier: nil)
        XCTAssertNil(try XCTUnwrap(persistent.modalAlertDescriptor(whenAppModal: true)).suppressionLabel)

        // Each silenceable type has its own wording, and a one-action warning
        // ("suppress") is worded differently from a several-action one
        // ("remember my choice").
        var labels = Set<String>()
        for type in [iTermWarningType.kiTermWarningTypeTemporarilySilenceable,
                     .kiTermWarningTypeSilenceableForOneMonth,
                     .kiTermWarningTypePermanentlySilenceable] {
            for actions in [["OK", "Cancel"], ["Allow", "Deny", "Cancel"]] {
                let warning = makeWarning(actions: actions, type: type, identifier: uniqueIdentifier())
                let descriptor = try XCTUnwrap(warning.modalAlertDescriptor(whenAppModal: true))
                let label = try XCTUnwrap(descriptor.suppressionLabel)
                XCTAssertFalse(label.isEmpty)
                labels.insert(label)
            }
        }
        XCTAssertEqual(labels.count, 6)
    }

    @MainActor
    func testAccessoryIsFlaggedButNotDescribed() throws {
        let warning = makeWarning(identifier: uniqueIdentifier())
        warning.accessory = NSTextField(labelWithString: "Details only shown on the Mac")
        let descriptor = try XCTUnwrap(warning.modalAlertDescriptor(whenAppModal: true))
        XCTAssertTrue(descriptor.hasAccessory)
        XCTAssertEqual(descriptor.body, "The main text.")
    }

    /// With “Always show alerts with remembered selections” on, the alert gains
    /// a “Permanently Forget Saved Selection” button after the real ones. It is
    /// not offered remotely, so button indexes still match the warning's actions.
    @MainActor
    func testForgetButtonIsNotOffered() throws {
        let warning = makeWarning(identifier: uniqueIdentifier())
        warning.shownDueToRememberedAlertsMode = true
        warning.savedSelectionLabel = "Allow"
        let descriptor = try XCTUnwrap(warning.modalAlertDescriptor(whenAppModal: true))
        XCTAssertEqual(descriptor.buttons.map { $0.title }, ["Allow", "Deny", "Cancel"])
        XCTAssertTrue(descriptor.body.contains("The main text."))
        XCTAssertTrue(descriptor.body.contains("Allow"), "the body explains the saved selection, as on the Mac")
    }

    @MainActor
    func testWarningThatOptsOutIsNotDescribed() {
        let warning = makeWarning(identifier: uniqueIdentifier())
        warning.remotelyAnswerable = false
        XCTAssertNil(warning.modalAlertDescriptor(whenAppModal: true))
    }

    // MARK: Pressing a button

    /// Stands in for NSAlert's own button handling, so a press can be observed
    /// without running (or showing) the alert.
    private final class ClickSpy: NSObject {
        var clickedTitles: [String] = []
        @objc func clicked(_ sender: NSButton) {
            clickedTitles.append(sender.title)
        }
    }

    /// Builds the warning's alert WITHOUT showing it, points its buttons at a
    /// spy, and returns the block the registry would call to press one.
    @MainActor
    private func pressFixture(type: iTermWarningType = .kiTermWarningTypePermanentlySilenceable,
                              identifier: String?,
                              configure: ((iTermWarning) -> Void)? = nil)
        -> (alert: NSAlert, spy: ClickSpy, press: (Int, Bool) -> Bool, warning: iTermWarning,
            pressWithInputs: (Int, Bool, [String: String]) -> Bool) {
        let warning = makeWarning(type: type, identifier: identifier)
        configure?(warning)
        let alert = warning.makeAlertForRemoteAnswer()
        let spy = ClickSpy()
        for button in alert.buttons {
            button.target = spy
            button.action = #selector(ClickSpy.clicked(_:))
        }
        let press = warning.modalAlertPressBlock(for: alert)
        return (alert, spy, { press($0, $1, [:]) }, warning, { press($0, $1, $2) })
    }

    @MainActor
    func testPressClicksTheButtonAndChecksTheBoxWhenAsked() {
        let fixture = pressFixture(identifier: uniqueIdentifier())
        XCTAssertTrue(fixture.press(1, true))
        XCTAssertEqual(fixture.spy.clickedTitles, ["Deny"])
        XCTAssertEqual(fixture.alert.suppressionButton?.state, .on,
                       "the box is checked before the click, which is when the warning reads it")
    }

    @MainActor
    func testPressWithoutSuppressLeavesTheBoxUnchecked() {
        let fixture = pressFixture(identifier: uniqueIdentifier())
        XCTAssertTrue(fixture.press(0, false))
        XCTAssertEqual(fixture.spy.clickedTitles, ["Allow"])
        XCTAssertEqual(fixture.alert.suppressionButton?.state, .off)
    }

    @MainActor
    func testCancelIsClickedButNeverChecksTheBox() {
        let fixture = pressFixture(identifier: uniqueIdentifier())
        XCTAssertTrue(fixture.press(2, true))
        XCTAssertEqual(fixture.spy.clickedTitles, ["Cancel"])
        XCTAssertEqual(fixture.alert.suppressionButton?.state, .off, "Cancel is never remembered")
    }

    @MainActor
    func testDoNotRememberActionNeverChecksTheBox() {
        let fixture = pressFixture(identifier: uniqueIdentifier()) { $0.doNotRememberLabels = ["Deny"] }
        XCTAssertTrue(fixture.press(1, true))
        XCTAssertEqual(fixture.spy.clickedTitles, ["Deny"])
        XCTAssertEqual(fixture.alert.suppressionButton?.state, .off)
    }

    /// A warning without a checkbox must not be remembered just because the
    /// answer asked for it: the warning reads the (hidden) box's state when it
    /// handles the click.
    @MainActor
    func testSuppressIsIgnoredForAWarningWithoutACheckbox() {
        let fixture = pressFixture(type: .kiTermWarningTypePersistent, identifier: nil)
        XCTAssertFalse(fixture.alert.showsSuppressionButton)
        XCTAssertTrue(fixture.press(0, true))
        XCTAssertEqual(fixture.spy.clickedTitles, ["Allow"])
        XCTAssertEqual(fixture.alert.suppressionButton?.state, .off)
    }

    @MainActor
    func testPressRefusesAnIndexThatIsNotOneOfTheWarningsActions() {
        // In remembered-alerts mode the alert has a fourth button, “Permanently
        // Forget Saved Selection”, which is not one of the warning's actions.
        let fixture = pressFixture(identifier: uniqueIdentifier()) {
            $0.shownDueToRememberedAlertsMode = true
            $0.savedSelectionLabel = "Allow"
        }
        XCTAssertEqual(fixture.alert.buttons.count, 4)
        XCTAssertFalse(fixture.press(3, false), "the Forget button cannot be pressed remotely")
        XCTAssertFalse(fixture.press(-1, false))
        XCTAssertFalse(fixture.press(7, false))
        XCTAssertEqual(fixture.spy.clickedTitles, [])
    }

    /// A click on a disabled or hidden button does nothing, so it must not be
    /// reported as a press: the phone would wait forever for the alert to go.
    @MainActor
    func testPressIsRefusedForAButtonThatCannotBeClicked() {
        let disabled = pressFixture(identifier: uniqueIdentifier())
        disabled.alert.buttons[0].isEnabled = false
        XCTAssertFalse(disabled.press(0, true))
        XCTAssertEqual(disabled.spy.clickedTitles, [])
        XCTAssertEqual(disabled.alert.suppressionButton?.state, .off, "a refused press must not check the box")
        XCTAssertTrue(disabled.press(1, false), "the other buttons still work")

        let hidden = pressFixture(identifier: uniqueIdentifier())
        hidden.alert.buttons[1].isHidden = true
        XCTAssertFalse(hidden.press(1, false))
        XCTAssertEqual(hidden.spy.clickedTitles, [])
    }

    @MainActor
    func testPressDoesNothingOnceTheAlertIsGone() {
        let warning = makeWarning(identifier: uniqueIdentifier())
        var press: ((Int, Bool) -> Bool)?
        autoreleasepool {
            let alert = warning.makeAlertForRemoteAnswer()
            let block = warning.modalAlertPressBlock(for: alert)
            press = { block($0, $1, [:]) }
        }
        XCTAssertEqual(press?(0, false), false, "the block must not keep a dismissed alert alive")
    }

    // MARK: Inputs

    /// A warning whose accessory is a text field, like the one that asks for a
    /// Python dependency's name.
    @MainActor
    private func textInputFixture() -> (field: NSTextField,
                                        fixture: (alert: NSAlert, spy: ClickSpy, press: (Int, Bool) -> Bool,
                                                  warning: iTermWarning,
                                                  pressWithInputs: (Int, Bool, [String: String]) -> Bool)) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "draft"
        let fixture = pressFixture(type: .kiTermWarningTypePersistent, identifier: nil) { warning in
            warning.accessory = field
            warning.remoteInputs = [iTermWarningRemoteInput.textInput(withIdentifier: "name", label: nil, textField: field)]
        }
        return (field, fixture)
    }

    @MainActor
    func testRemoteInputsAreDescribedAndStandInForTheAccessory() throws {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "draft"
        let spaces = OSAllocatedUnfairLock(initialState: 4)
        let warning = makeWarning(type: .kiTermWarningTypePersistent, identifier: nil)
        warning.accessory = field
        warning.remoteInputs = [
            iTermWarningRemoteInput.textInput(withIdentifier: "name", label: "Name:", textField: field),
            iTermWarningRemoteInput.integerInput(withIdentifier: "spaces", label: nil, minimum: 0, maximum: 100,
                                                 getter: { spaces.withLock { $0 } },
                                                 setter: { value in spaces.withLock { $0 = value } }),
        ]
        let descriptor = try XCTUnwrap(warning.modalAlertDescriptor(whenAppModal: true))
        XCTAssertEqual(descriptor.inputs.map { $0.identifier }, ["name", "spaces"])
        XCTAssertEqual(descriptor.inputs.map { $0.label }, ["Name:", nil])
        XCTAssertEqual(descriptor.inputs.map { $0.isInteger }, [false, true])
        XCTAssertEqual(descriptor.inputs.map { $0.value }, ["draft", "4"], "the controls' current contents")
        XCTAssertEqual(descriptor.inputs[1].minimum, 0)
        XCTAssertEqual(descriptor.inputs[1].maximum, 100)
        XCTAssertFalse(descriptor.hasAccessory,
                       "the inputs are everything in the accessory, so there is nothing more to see on the Mac")
    }

    @MainActor
    func testPressPutsTheValuesInTheControlsBeforeClicking() {
        let (field, fixture) = textInputFixture()
        XCTAssertTrue(fixture.pressWithInputs(0, false, ["name": "requests"]))
        XCTAssertEqual(field.stringValue, "requests")
        XCTAssertEqual(fixture.spy.clickedTitles, ["Allow"])
    }

    @MainActor
    func testAnInputThatIsNotSentKeepsWhatItHolds() {
        let (field, fixture) = textInputFixture()
        XCTAssertTrue(fixture.pressWithInputs(0, false, ["somethingElse": "ignored"]))
        XCTAssertEqual(field.stringValue, "draft")
        XCTAssertEqual(fixture.spy.clickedTitles, ["Allow"])
    }

    /// A number that is not a number, or is out of range, refuses the whole
    /// press: no control changes and nothing is clicked.
    @MainActor
    func testUnacceptableIntegerRefusesThePressAndChangesNothing() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "draft"
        let spaces = OSAllocatedUnfairLock(initialState: 4)
        let fixture = pressFixture(type: .kiTermWarningTypePersistent, identifier: nil) { warning in
            warning.accessory = field
            warning.remoteInputs = [
                iTermWarningRemoteInput.textInput(withIdentifier: "name", label: nil, textField: field),
                iTermWarningRemoteInput.integerInput(withIdentifier: "spaces", label: nil, minimum: 0, maximum: 100,
                                                     getter: { spaces.withLock { $0 } },
                                                     setter: { value in spaces.withLock { $0 = value } }),
            ]
        }
        for bad in ["101", "-1", "eight", "8 spaces", "", "8.5"] {
            XCTAssertFalse(fixture.pressWithInputs(0, false, ["name": "changed", "spaces": bad]),
                           "“\(bad)” must be refused")
        }
        XCTAssertEqual(field.stringValue, "draft", "a refused press must not change the other control either")
        XCTAssertEqual(spaces.withLock { $0 }, 4)
        XCTAssertEqual(fixture.spy.clickedTitles, [])

        XCTAssertTrue(fixture.pressWithInputs(0, false, ["name": "changed", "spaces": "100"]))
        XCTAssertEqual(field.stringValue, "changed")
        XCTAssertEqual(spaces.withLock { $0 }, 100)
    }

    /// The real accessory for the “paste with tabs” warning.
    @MainActor
    func testNumberOfSpacesAccessoryDescribesAndAppliesItsField() throws {
        let controller = iTermNumberOfSpacesAccessoryViewController()
        let input = try XCTUnwrap(controller.remoteInput())
        XCTAssertTrue(input.isInteger)
        XCTAssertEqual(input.minimum, 0)
        XCTAssertEqual(input.maximum, 100)
        XCTAssertEqual(input.label?.isEmpty, false, "it takes its label from the field's own, in the nib")
        XCTAssertEqual(input.currentValue(), "\(controller.numberOfSpaces)")

        XCTAssertTrue(input.acceptsValue("8"))
        XCTAssertFalse(input.acceptsValue("101"))
        input.applyValue("8")
        XCTAssertEqual(controller.numberOfSpaces, 8)
        XCTAssertEqual(input.currentValue(), "8")
    }

    // MARK: End to end, headless

    private struct Outcome: Sendable {
        let selection: iTermWarningSelection
        let snapshot: ModalAlertSnapshot
        let answerAccepted: Bool
        /// Whether a @MainActor task queued just before the warning ran had run
        /// by the time the warning was answered. It must not have: that is the
        /// freeze the registry exists to work through.
        let mainActorRanWhileShowing: Bool
    }

    /// Ends any headless warning that is still waiting. A waiting warning has
    /// the main thread inside its nested run loop, and XCTest needs the main
    /// thread back to finish the test, so a test that fails while one is
    /// waiting must do this or it would hang. From a run loop block because the
    /// main queue is frozen.
    private static func cancelHeadlessModals() {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            iTermWarning.cancelHeadlessModals()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func endingHeadlessModalsOnFailure<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            Self.cancelHeadlessModals()
            throw error
        }
    }

    /// The next alert to appear in the shared registry.
    private func nextRegisteredAlert(_ changes: AsyncStream<Void>) async throws -> ModalAlertSnapshot {
        return try await FrozenMainQueue.withFailsafe("the warning to register") {
            for await _ in changes {
                if let top = ModalAlertRegistry.shared.currentAlerts().last {
                    return top
                }
            }
            throw CancellationError()
        }
    }

    /// Runs a warning from a main-queue callout, waits (off the main thread)
    /// for it to appear in the shared registry, answers it there, and returns
    /// what runModal reported.
    private func runAndAnswer(identifier: String?,
                              type: iTermWarningType,
                              buttonIndex: Int,
                              suppress: Bool) async throws -> Outcome {
        let registry = ModalAlertRegistry.shared
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        defer { _ = token }
        let (finished, finishedContinuation) = AsyncStream<iTermWarningSelection>.makeStream()
        let mainActorRan = OSAllocatedUnfairLock(initialState: false)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let warning = self.makeWarning(type: type, identifier: identifier)
                Task { @MainActor in mainActorRan.withLock { $0 = true } }
                finishedContinuation.yield(warning.runModal())
            }
        }

        return try await endingHeadlessModalsOnFailure {
            let snapshot = try await nextRegisteredAlert(changes)
            let accepted = try await FrozenMainQueue.withFailsafe("the answer") {
                await registry.answer(id: snapshot.id, buttonIndex: buttonIndex, suppress: suppress)
            }
            let ranWhileShowing = mainActorRan.withLock { $0 }
            if !accepted {
                // Nothing was pressed, so the warning is still waiting.
                Self.cancelHeadlessModals()
            }
            let selection = try await FrozenMainQueue.withFailsafe("runModal to return") { () -> iTermWarningSelection in
                for await selection in finished {
                    return selection
                }
                throw CancellationError()
            }
            return Outcome(selection: selection,
                           snapshot: snapshot,
                           answerAccepted: accepted,
                           mainActorRanWhileShowing: ranWhileShowing)
        }
    }

    func testWarningIsAnsweredFromAnotherThreadAndRemembersTheChoice() async throws {
        let identifier = uniqueIdentifier()
        let outcome = try await runAndAnswer(identifier: identifier,
                                             type: .kiTermWarningTypePermanentlySilenceable,
                                             buttonIndex: 1,
                                             suppress: true)
        XCTAssertEqual(outcome.snapshot.heading, "Heading")
        XCTAssertEqual(outcome.snapshot.buttons.map { $0.title }, ["Allow", "Deny", "Cancel"])
        XCTAssertTrue(outcome.snapshot.isAppModal)
        XCTAssertFalse(outcome.mainActorRanWhileShowing, "the warning did not freeze the main queue")
        XCTAssertTrue(outcome.answerAccepted)
        XCTAssertEqual(outcome.selection, .kiTermWarningSelection1, "runModal reports the button that was pressed")
        XCTAssertTrue(iTermWarning.identifierIsSilenced(identifier), "the choice was remembered")
        XCTAssertEqual(iTermUserDefaults.userDefaults().integer(forKey: identifier + "_selection"), 1)
        XCTAssertEqual(ModalAlertRegistry.shared.currentAlerts(), [], "the warning unregistered when it closed")
    }

    func testAnswerWithoutSuppressDoesNotRememberTheChoice() async throws {
        let identifier = uniqueIdentifier()
        let outcome = try await runAndAnswer(identifier: identifier,
                                             type: .kiTermWarningTypePermanentlySilenceable,
                                             buttonIndex: 0,
                                             suppress: false)
        XCTAssertTrue(outcome.answerAccepted)
        XCTAssertEqual(outcome.selection, .kiTermWarningSelection0)
        XCTAssertFalse(iTermWarning.identifierIsSilenced(identifier))
    }

    func testCancelIsNotRememberedEndToEnd() async throws {
        let identifier = uniqueIdentifier()
        let outcome = try await runAndAnswer(identifier: identifier,
                                             type: .kiTermWarningTypePermanentlySilenceable,
                                             buttonIndex: 2,
                                             suppress: true)
        XCTAssertTrue(outcome.answerAccepted)
        XCTAssertEqual(outcome.selection, .kiTermWarningSelection2)
        XCTAssertFalse(iTermWarning.identifierIsSilenced(identifier))
    }

    /// A warning that asks for a value, answered completely from another thread:
    /// the registry lists the input, the answer carries a value, and by the
    /// time runModal returns the control holds it, as if typed at the Mac.
    func testWarningWithAnInputIsAnsweredCompletelyFromAnotherThread() async throws {
        let registry = ModalAlertRegistry.shared
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        defer { _ = token }
        let (finished, finishedContinuation) = AsyncStream<String>.makeStream()

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                let warning = self.makeWarning(actions: ["OK", "Cancel"],
                                               type: .kiTermWarningTypePersistent,
                                               identifier: nil)
                warning.accessory = field
                warning.remoteInputs = [iTermWarningRemoteInput.textInput(withIdentifier: "name", label: nil,
                                                                          textField: field)]
                let selection = warning.runModal()
                finishedContinuation.yield("selection \(selection.rawValue), field “\(field.stringValue)”")
            }
        }

        let outcome = try await endingHeadlessModalsOnFailure { () -> String in
            let snapshot = try await nextRegisteredAlert(changes)
            XCTAssertEqual(snapshot.inputs, [.init(id: "name", label: nil, kind: .text, value: "")])
            XCTAssertFalse(snapshot.hasAccessory)
            let accepted = await registry.answer(id: snapshot.id, buttonIndex: 0, suppress: false,
                                                 inputs: ["name": "requests"])
            XCTAssertTrue(accepted)
            if !accepted {
                Self.cancelHeadlessModals()
            }
            return try await FrozenMainQueue.withFailsafe("runModal to return") {
                for await outcome in finished {
                    return outcome
                }
                throw CancellationError()
            }
        }
        XCTAssertEqual(outcome, "selection 0, field “requests”")
    }

    /// A stale answer (the alert was already dismissed) presses nothing on the
    /// alert that replaced it.
    func testAnswerForADismissedWarningDoesNotPressTheNextOne() async throws {
        let first = try await runAndAnswer(identifier: nil,
                                           type: .kiTermWarningTypePersistent,
                                           buttonIndex: 0,
                                           suppress: false)
        let registry = ModalAlertRegistry.shared
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        defer { _ = token }
        let (finished, finishedContinuation) = AsyncStream<iTermWarningSelection>.makeStream()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let warning = self.makeWarning(type: .kiTermWarningTypePersistent, identifier: nil)
                finishedContinuation.yield(warning.runModal())
            }
        }
        let selection = try await endingHeadlessModalsOnFailure { () -> iTermWarningSelection in
            let second = try await nextRegisteredAlert(changes)
            XCTAssertNotEqual(second.id, first.snapshot.id)

            let staleAccepted = await registry.answer(id: first.snapshot.id, buttonIndex: 1, suppress: false)
            XCTAssertFalse(staleAccepted)
            XCTAssertEqual(registry.currentAlerts().map { $0.id }, [second.id], "the second warning is still waiting")

            let accepted = await registry.answer(id: second.id, buttonIndex: 2, suppress: false)
            XCTAssertTrue(accepted)
            if !accepted {
                Self.cancelHeadlessModals()
            }
            return try await FrozenMainQueue.withFailsafe("runModal to return") {
                for await selection in finished {
                    return selection
                }
                throw CancellationError()
            }
        }
        XCTAssertEqual(selection, .kiTermWarningSelection2)
    }

    /// A sheet started with runModalAsync does not block, so it is registered
    /// as not app-modal, and its completion runs when it is answered.
    func testAsyncSheetIsRegisteredAsNotAppModalAndCompletesWhenAnswered() async throws {
        let registry = ModalAlertRegistry.shared
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        defer { _ = token }
        let (finished, finishedContinuation) = AsyncStream<iTermWarningSelection>.makeStream()
        await MainActor.run {
            let warning = self.makeWarning(type: .kiTermWarningTypePersistent, identifier: nil)
            warning.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                                      styleMask: [.titled], backing: .buffered, defer: true)
            warning.runModalAsync { selection, _ in
                finishedContinuation.yield(selection)
            }
        }
        let selection = try await endingHeadlessModalsOnFailure { () -> iTermWarningSelection in
            let snapshot = try await nextRegisteredAlert(changes)
            XCTAssertFalse(snapshot.isAppModal)
            let accepted = await registry.answer(id: snapshot.id, buttonIndex: 1, suppress: false)
            XCTAssertTrue(accepted)
            if !accepted {
                Self.cancelHeadlessModals()
            }
            return try await FrozenMainQueue.withFailsafe("the sheet's completion") {
                for await selection in finished {
                    return selection
                }
                throw CancellationError()
            }
        }
        XCTAssertEqual(selection, .kiTermWarningSelection1)
        XCTAssertEqual(registry.currentAlerts(), [])
    }

    /// AppKit does not call a sheet's completion handler when the parent window
    /// closes first. The warning must still leave the registry, or the phone
    /// would go on showing an alert that no longer exists.
    func testAsyncSheetIsUnregisteredWhenItsParentWindowCloses() async throws {
        let registry = ModalAlertRegistry.shared
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        defer { _ = token }
        let completions = OSAllocatedUnfairLock(initialState: 0)
        let parent = await MainActor.run { () -> NSWindow in
            let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                                  styleMask: [.titled], backing: .buffered, defer: true)
            parent.isReleasedWhenClosed = false
            let warning = self.makeWarning(type: .kiTermWarningTypePersistent, identifier: nil)
            warning.window = parent
            warning.runModalAsync { _, _ in
                completions.withLock { $0 += 1 }
            }
            return parent
        }
        _ = try await nextRegisteredAlert(changes)

        await MainActor.run { parent.close() }

        XCTAssertEqual(registry.currentAlerts(), [], "the warning is still registered after its window closed")
        XCTAssertEqual(completions.withLock { $0 }, 0, "as with a real sheet, the completion does not run")
        // Closing again, or a late answer, must be harmless.
        await MainActor.run { parent.close() }
    }

    func testWarningThatOptsOutIsNeverRegistered() async throws {
        let registry = ModalAlertRegistry.shared
        let (finished, finishedContinuation) = AsyncStream<iTermWarningSelection>.makeStream()
        let registeredWhileShowing = OSAllocatedUnfairLock<Int?>(initialState: nil)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let warning = self.makeWarning(type: .kiTermWarningTypePersistent, identifier: nil)
                warning.remotelyAnswerable = false
                // Runs inside the warning's nested run loop: record what the
                // registry holds, then end the wait.
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    registeredWhileShowing.withLock { $0 = registry.currentAlerts().count }
                    iTermWarning.cancelHeadlessModals()
                }
                finishedContinuation.yield(warning.runModal())
            }
        }
        let selection = try await FrozenMainQueue.withFailsafe("runModal to return") { () -> iTermWarningSelection in
            for await selection in finished {
                return selection
            }
            throw CancellationError()
        }
        XCTAssertEqual(registeredWhileShowing.withLock { $0 }, 0)
        XCTAssertEqual(selection, .kItermWarningSelectionError, "a cancelled headless warning reports an error")
    }

    /// The headless mode itself: nothing is shown, the caller is blocked in a
    /// nested run loop, and a programmatic click ends it with that button.
    func testHeadlessWarningBlocksUntilAButtonIsClickedAndShowsNoWindow() async throws {
        let (finished, finishedContinuation) = AsyncStream<iTermWarningSelection>.makeStream()
        let observed = OSAllocatedUnfairLock<(windowVisible: Bool, modalWindow: Bool)?>(initialState: nil)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let warning = self.makeWarning(type: .kiTermWarningTypePersistent, identifier: nil)
                let visibleBefore = Set(NSApp.windows.filter { $0.isVisible }.map { ObjectIdentifier($0) })
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    let visibleNow = Set(NSApp.windows.filter { $0.isVisible }.map { ObjectIdentifier($0) })
                    observed.withLock {
                        $0 = (windowVisible: !visibleNow.subtracting(visibleBefore).isEmpty,
                              modalWindow: NSApp.modalWindow != nil)
                    }
                    iTermWarning.cancelHeadlessModals()
                }
                finishedContinuation.yield(warning.runModal())
            }
        }
        _ = try await FrozenMainQueue.withFailsafe("runModal to return") { () -> iTermWarningSelection in
            for await selection in finished {
                return selection
            }
            throw CancellationError()
        }
        let result = try XCTUnwrap(observed.withLock { $0 })
        XCTAssertFalse(result.windowVisible, "a headless warning must not put a window on screen")
        XCTAssertFalse(result.modalWindow, "a headless warning must not start a real modal session")
    }
}

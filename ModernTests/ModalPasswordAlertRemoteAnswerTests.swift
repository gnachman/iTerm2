//
//  ModalPasswordAlertRemoteAnswerTests.swift
//  ModernTests
//
//  The password prompt (used for a password manager's master password, among
//  others) can come up because of something done from the companion app, with
//  nobody at the Mac. These tests pin that it is published for the phone with
//  the password as a secret input, and that an answer from another thread,
//  while the prompt has the main queue frozen, is what its caller gets back.
//
//  Nothing is shown: the prompt runs as a headless modal (see
//  iTermWarning.setRunsHeadlessModals).
//

import XCTest
@testable import iTerm2SharedARC

final class ModalPasswordAlertRemoteAnswerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        iTermWarning.setRunsHeadlessModals(true)
    }

    override func tearDown() {
        iTermWarning.cancelHeadlessModals()
        iTermWarning.setRunsHeadlessModals(false)
        super.tearDown()
    }

    /// A prompt that is waiting holds the main thread, which XCTest needs back,
    /// so a failing test must end it. From a run loop block because the main
    /// queue is frozen.
    private static func cancelHeadlessModals() {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            iTermWarning.cancelHeadlessModals()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    /// Shows a prompt from a main-queue callout (so the main queue is frozen
    /// while it waits), lets `answer` see what was published and say which
    /// button to press with which values, and returns what `show` reported.
    private func showAndAnswer(
        show: @escaping @MainActor (_ report: @escaping (String) -> Void) -> Void,
        answer: (ModalAlertSnapshot) -> (buttonIndex: Int, inputs: [String: String]),
        suppress: Bool = false
    ) async throws -> String {
        let registry = ModalAlertRegistry.shared
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        defer { _ = token }
        let (finished, finishedContinuation) = AsyncStream<String>.makeStream()

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                show { finishedContinuation.yield($0) }
            }
        }

        do {
            let snapshot = try await FrozenMainQueue.withFailsafe("the prompt to register") { () -> ModalAlertSnapshot in
                for await _ in changes {
                    if let top = registry.currentAlerts().last {
                        return top
                    }
                }
                throw CancellationError()
            }
            let (buttonIndex, inputs) = answer(snapshot)
            let accepted = await registry.answer(id: snapshot.id, buttonIndex: buttonIndex, suppress: suppress,
                                                 inputs: inputs)
            XCTAssertTrue(accepted)
            if !accepted {
                Self.cancelHeadlessModals()
            }
            return try await FrozenMainQueue.withFailsafe("the prompt to return") {
                for await outcome in finished {
                    return outcome
                }
                throw CancellationError()
            }
        } catch {
            Self.cancelHeadlessModals()
            throw error
        }
    }

    func testPasswordEnteredOnThePhoneIsWhatThePromptReturns() async throws {
        let outcome = try await showAndAnswer(show: { report in
            let prompt = ModalPasswordAlert("Enter your master password:")
            report(prompt.run(window: nil) ?? "(cancelled)")
        }, answer: { snapshot in
            XCTAssertEqual(snapshot.heading, "Enter your master password:")
            XCTAssertEqual(snapshot.buttons.map { $0.isCancel }, [false, true])
            XCTAssertEqual(snapshot.inputs.map { $0.id }, ["password"])
            XCTAssertEqual(snapshot.inputs.map { $0.kind }, [.secret])
            XCTAssertFalse(snapshot.hasAccessory, "the password field is all there is")
            return (0, ["password": "correct horse"])
        })
        XCTAssertEqual(outcome, "correct horse")
    }

    func testCancelFromThePhoneReturnsNothing() async throws {
        let outcome = try await showAndAnswer(show: { report in
            let prompt = ModalPasswordAlert("Enter your master password:")
            report(prompt.run(window: nil) ?? "(cancelled)")
        }, answer: { _ in
            // Cancel wins even if something was typed.
            return (1, ["password": "ignored"])
        })
        XCTAssertEqual(outcome, "(cancelled)")
    }

    /// A password already in the field (one that was remembered and just
    /// failed) is not published, and is what the prompt returns if the phone
    /// presses OK without entering another.
    func testInitialPasswordStaysOnTheMac() async throws {
        let outcome = try await showAndAnswer(show: { report in
            let prompt = ModalPasswordAlert("Enter your master password:")
            prompt.initialPassword = "hunter2"
            report(prompt.run(window: nil) ?? "(cancelled)")
        }, answer: { snapshot in
            XCTAssertEqual(snapshot.inputs.map { $0.value }, [""])
            return (0, [:])
        })
        XCTAssertEqual(outcome, "hunter2")
    }

    func testUserNameCanBeSeenAndChangedFromThePhone() async throws {
        let outcome = try await showAndAnswer(show: { report in
            let prompt = ModalPasswordAlert("Please log in")
            prompt.username = "george"
            let password = prompt.run(window: nil) ?? "(cancelled)"
            report("\(prompt.username ?? "(none)") / \(password)")
        }, answer: { snapshot in
            XCTAssertEqual(snapshot.inputs.map { $0.id }, ["username", "password"])
            XCTAssertEqual(snapshot.inputs.map { $0.kind }, [.text, .secret])
            XCTAssertEqual(snapshot.inputs.map { $0.value }, ["george", ""])
            XCTAssertEqual(snapshot.inputs.first?.label, "User name")
            return (0, ["username": "gnachman", "password": "pw"])
        })
        XCTAssertEqual(outcome, "gnachman / pw")
    }

    /// “Remember this password” is shown and set on the phone the way a
    /// warning's “don’t ask again” box is.
    func testRememberCheckboxCanBeCheckedFromThePhone() async throws {
        let outcome = try await showAndAnswer(show: { report in
            let prompt = ModalPasswordAlert("Enter your master password:")
            prompt.showRememberCheckbox = true
            let password = prompt.run(window: nil) ?? "(cancelled)"
            report("\(password), remember=\(prompt.rememberChecked)")
        }, answer: { snapshot in
            XCTAssertEqual(snapshot.suppressionLabel, "Remember this password")
            XCTAssertFalse(snapshot.suppressionDefault)
            XCTAssertFalse(snapshot.hasAccessory)
            return (0, ["password": "pw"])
        }, suppress: true)
        XCTAssertEqual(outcome, "pw, remember=true")
    }

    /// The phone starts from the state the Mac gave the checkbox, and can
    /// uncheck it.
    func testRememberCheckboxThatStartsCheckedCanBeUncheckedFromThePhone() async throws {
        let outcome = try await showAndAnswer(show: { report in
            let prompt = ModalPasswordAlert("Enter your master password:")
            prompt.showRememberCheckbox = true
            prompt.rememberByDefault = true
            let password = prompt.run(window: nil) ?? "(cancelled)"
            report("\(password), remember=\(prompt.rememberChecked)")
        }, answer: { snapshot in
            XCTAssertTrue(snapshot.suppressionDefault)
            return (0, ["password": "pw"])
        }, suppress: false)
        XCTAssertEqual(outcome, "pw, remember=false")
    }

    func testPromptWithoutARememberCheckboxOffersNone() async throws {
        _ = try await showAndAnswer(show: { report in
            report(ModalPasswordAlert("Enter your master password:").run(window: nil) ?? "(cancelled)")
        }, answer: { snapshot in
            XCTAssertNil(snapshot.suppressionLabel)
            return (1, [:])
        })
    }

    /// The Password Manager button opens a window on the Mac that the phone
    /// cannot see, so it is not offered to the phone, and an answer naming it
    /// is refused and leaves the prompt up.
    func testPasswordManagerButtonIsNotOfferedToThePhone() async throws {
        let registry = ModalAlertRegistry.shared
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        defer { _ = token }
        let (finished, finishedContinuation) = AsyncStream<String>.makeStream()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let prompt = ModalPasswordAlert("Authenticate")
                prompt.showPasswordManagerButton = true
                prompt.runAsyncOutcome(window: nil) { finishedContinuation.yield("\($0)") }
            }
        }
        do {
            let snapshot = try await FrozenMainQueue.withFailsafe("the prompt to register") { () -> ModalAlertSnapshot in
                for await _ in changes {
                    if let top = registry.currentAlerts().last {
                        return top
                    }
                }
                throw CancellationError()
            }
            XCTAssertEqual(snapshot.buttons.map { $0.offered }, [true, true, false])
            let refused = await registry.answer(id: snapshot.id, buttonIndex: 2, suppress: false,
                                                inputs: ["password": "typed"])
            XCTAssertFalse(refused)
            XCTAssertEqual(registry.currentAlerts().map { $0.id }, [snapshot.id], "the prompt is still up")
            let cancelled = await registry.answer(id: snapshot.id, buttonIndex: 1, suppress: false)
            XCTAssertTrue(cancelled)
            if !cancelled {
                Self.cancelHeadlessModals()
            }
            let outcome = try await FrozenMainQueue.withFailsafe("the prompt to return") { () -> String in
                for await outcome in finished {
                    return outcome
                }
                throw CancellationError()
            }
            XCTAssertEqual(outcome, "cancel")
        } catch {
            Self.cancelHeadlessModals()
            throw error
        }
    }
}

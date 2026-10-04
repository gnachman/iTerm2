//
//  ModalAlertRegistryTests.swift
//  iTerm2 ModernTests
//
//  ModalAlertRegistry lets code that is off the main thread see the modal
//  alerts on screen and press a button on one, even while the alert's own run
//  loop has the main queue frozen. These tests use registered stand-ins rather
//  than real alerts (iTermWarningRemoteAnswerTests covers the real thing) and
//  pin:
//
//    - The list other threads read: its order, and that it changes at the
//      moment of register/unregister, before the main thread can freeze.
//    - Observers are told synchronously, once per change.
//    - Which answers are refused: a stale id, an alert that is not on top, a
//      bad index, and an alert with something unregistered in front of it.
//    - An answer is delivered on the main thread during a freeze.
//

import AppKit
import XCTest
import os
@testable import iTerm2SharedARC

final class ModalAlertRegistryTests: XCTestCase {
    /// Records what a registered stand-in alert was asked to press.
    private final class Presses: Sendable {
        struct Press: Equatable, Sendable {
            let buttonIndex: Int
            let suppress: Bool
            let onMainThread: Bool
        }
        private let state = OSAllocatedUnfairLock(initialState: [Press]())
        var all: [Press] { state.withLock { $0 } }
        func record(_ buttonIndex: Int, _ suppress: Bool) {
            let press = Press(buttonIndex: buttonIndex, suppress: suppress, onMainThread: Thread.isMainThread)
            state.withLock { $0.append(press) }
        }
    }

    /// The window the fake "app-modal session" is running for.
    private final class ModalWindowBox: @unchecked Sendable {
        @MainActor var window: NSWindow?
    }

    private func descriptor(_ heading: String,
                            buttons: [String] = ["OK", "Cancel"],
                            isAppModal: Bool = true) -> ModalAlertDescriptor {
        return ModalAlertDescriptor(
            heading: heading,
            body: "Body of \(heading)",
            buttons: buttons.map {
                ModalAlertDescriptor.Button(title: $0,
                                            isCancel: $0 == "Cancel",
                                            isDestructive: false,
                                            rememberable: $0 != "Cancel")
            },
            suppressionLabel: "Remember my choice",
            hasAccessory: false,
            isAppModal: isAppModal)
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    // MARK: The list

    @MainActor
    func testAlertsAreListedBottomToTopAndRemovedOnUnregister() {
        let registry = ModalAlertRegistry(modalWindow: { nil })
        XCTAssertEqual(registry.currentAlerts(), [])

        let first = registry.register(descriptor("First"), window: nil) { _, _ in true }
        let second = registry.register(descriptor("Second", buttons: ["Yes", "No", "Cancel"]),
                                       window: nil) { _, _ in true }
        let alerts = registry.currentAlerts()
        XCTAssertEqual(alerts.map { $0.heading }, ["First", "Second"])
        XCTAssertEqual(alerts.map { $0.id }, [first.identifier, second.identifier])
        guard alerts.count == 2 else {
            return
        }
        XCTAssertEqual(alerts[1], ModalAlertSnapshot(
            id: second.identifier,
            heading: "Second",
            body: "Body of Second",
            buttons: [.init(title: "Yes", isCancel: false, isDestructive: false, rememberable: true),
                      .init(title: "No", isCancel: false, isDestructive: false, rememberable: true),
                      .init(title: "Cancel", isCancel: true, isDestructive: false, rememberable: false)],
            suppressionLabel: "Remember my choice",
            hasAccessory: false,
            isAppModal: true))

        first.unregister()
        XCTAssertEqual(registry.currentAlerts().map { $0.heading }, ["Second"])
        first.unregister()  // idempotent
        second.unregister()
        XCTAssertEqual(registry.currentAlerts(), [])
    }

    @MainActor
    func testObserverIsCalledSynchronouslyOncePerChangeWhileSubscribed() {
        let registry = ModalAlertRegistry(modalWindow: { nil })
        let calls = OSAllocatedUnfairLock(initialState: 0)
        var token: AnyObject? = registry.addObserver { calls.withLock { $0 += 1 } }
        XCTAssertEqual(calls.withLock { $0 }, 0)

        let registration = registry.register(descriptor("A"), window: nil) { _, _ in true }
        XCTAssertEqual(calls.withLock { $0 }, 1, "told before register returns, with no hop")
        registration.unregister()
        XCTAssertEqual(calls.withLock { $0 }, 2)
        registration.unregister()
        XCTAssertEqual(calls.withLock { $0 }, 2, "a repeated unregister changes nothing")

        // Dropping the token unsubscribes.
        token = nil
        _ = token
        _ = registry.register(descriptor("B"), window: nil) { _, _ in true }
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    /// An alert registered on the main thread, in the same callout that then
    /// freezes, must already be visible to other threads, and its observer must
    /// already have fired. This is exactly what showing an alert does.
    func testAlertRegisteredInsideTheFreezingCalloutIsVisibleOffMain() async throws {
        let registry = ModalAlertRegistry(modalWindow: { nil })
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        try await FrozenMainQueue.run(setup: {
            _ = registry.register(self.descriptor("Frozen"), window: nil) { _, _ in true }
        }) { _ in
            try await FrozenMainQueue.withFailsafe("the observer to fire") {
                for await _ in changes { break }
            }
            XCTAssertEqual(registry.currentAlerts().map { $0.heading }, ["Frozen"])
        }
        _ = token
    }

    // MARK: Answering

    func testAnswerPressesTheButtonOnTheMainThreadWhileMainQueueIsFrozen() async throws {
        let box = ModalWindowBox()
        let registry = ModalAlertRegistry(modalWindow: { box.window })
        let presses = Presses()
        let id = OSAllocatedUnfairLock<UUID?>(initialState: nil)
        try await FrozenMainQueue.run(setup: {
            let window = self.makeWindow()
            box.window = window  // this alert IS the running modal session
            let registration = registry.register(self.descriptor("Frozen"), window: window) { index, suppress in
                presses.record(index, suppress)
                return true
            }
            id.withLock { $0 = registration.identifier }
        }) { _ in
            let alertID = try XCTUnwrap(id.withLock { $0 })
            let accepted = try await FrozenMainQueue.withFailsafe("the answer") {
                await registry.answer(id: alertID, buttonIndex: 1, suppress: true)
            }
            XCTAssertTrue(accepted)
        }
        XCTAssertEqual(presses.all, [.init(buttonIndex: 1, suppress: true, onMainThread: true)])
    }

    func testAnswerIsRefusedForAStaleIDOrABadIndexOrAnAlertThatIsNotOnTop() async throws {
        let registry = ModalAlertRegistry(modalWindow: { nil })
        let presses = Presses()
        let (bottom, top, gone) = await MainActor.run { () -> (UUID, UUID, UUID) in
            let press: (Int, Bool) -> Bool = { index, suppress in
                presses.record(index, suppress)
                return true
            }
            let gone = registry.register(self.descriptor("Gone"), window: nil, press: press)
            gone.unregister()
            // No window: these stand-ins skip the modal-session check.
            let bottom = registry.register(self.descriptor("Bottom"), window: nil, press: press)
            let top = registry.register(self.descriptor("Top"), window: nil, press: press)
            return (bottom.identifier, top.identifier, gone.identifier)
        }

        let staleAccepted = await registry.answer(id: gone, buttonIndex: 0, suppress: false)
        XCTAssertFalse(staleAccepted, "the alert was already dismissed")
        let coveredAccepted = await registry.answer(id: bottom, buttonIndex: 0, suppress: false)
        XCTAssertFalse(coveredAccepted, "only the alert on top can be clicked")
        let highAccepted = await registry.answer(id: top, buttonIndex: 2, suppress: false)
        XCTAssertFalse(highAccepted, "there are only two buttons")
        let negativeAccepted = await registry.answer(id: top, buttonIndex: -1, suppress: false)
        XCTAssertFalse(negativeAccepted)
        XCTAssertEqual(presses.all, [], "a refused answer presses nothing")

        let accepted = await registry.answer(id: top, buttonIndex: 0, suppress: false)
        XCTAssertTrue(accepted)
        XCTAssertEqual(presses.all, [.init(buttonIndex: 0, suppress: false, onMainThread: true)])
    }

    func testAnswerIsRefusedWhenThePressItselfFails() async throws {
        let registry = ModalAlertRegistry(modalWindow: { nil })
        let id = await MainActor.run {
            registry.register(self.descriptor("A"), window: nil) { _, _ in false }.identifier
        }
        let accepted = await registry.answer(id: id, buttonIndex: 0, suppress: false)
        XCTAssertFalse(accepted)
    }

    /// A plain NSAlert or an open panel over a registered warning: the warning
    /// is still the newest registered alert, but clicking its button would end
    /// the OTHER modal session.
    func testAnswerIsRefusedWhileAnUnregisteredModalIsInFront() async throws {
        let box = ModalWindowBox()
        let registry = ModalAlertRegistry(modalWindow: { box.window })
        let presses = Presses()
        let (id, alertWindow) = await MainActor.run { () -> (UUID, NSWindow) in
            let alertWindow = self.makeWindow()
            box.window = self.makeWindow()  // something else is the modal session
            let registration = registry.register(self.descriptor("Covered"), window: alertWindow) { index, suppress in
                presses.record(index, suppress)
                return true
            }
            return (registration.identifier, alertWindow)
        }
        let refused = await registry.answer(id: id, buttonIndex: 0, suppress: false)
        XCTAssertFalse(refused)
        XCTAssertEqual(presses.all, [])

        // Once the other modal is gone and the warning's own session is the
        // running one, the same answer goes through.
        await MainActor.run { box.window = alertWindow }
        let accepted = await registry.answer(id: id, buttonIndex: 0, suppress: false)
        XCTAssertTrue(accepted)
        XCTAssertEqual(presses.all.count, 1)
    }

    @MainActor
    func testMayAnswerRules() {
        let alertWindow = makeWindow()
        let other = makeWindow()
        // App-modal: the alert must be the running modal session.
        XCTAssertTrue(ModalAlertRegistry.mayAnswer(isAppModal: true, alertWindow: alertWindow,
                                                   alertWindowIsAttachedSheet: false, modalWindow: alertWindow))
        XCTAssertTrue(ModalAlertRegistry.mayAnswer(isAppModal: true, alertWindow: alertWindow,
                                                   alertWindowIsAttachedSheet: true, modalWindow: alertWindow),
                      "a sheet run with a nested modal loop is its own modal session")
        XCTAssertFalse(ModalAlertRegistry.mayAnswer(isAppModal: true, alertWindow: alertWindow,
                                                    alertWindowIsAttachedSheet: false, modalWindow: other))
        XCTAssertFalse(ModalAlertRegistry.mayAnswer(isAppModal: true, alertWindow: alertWindow,
                                                    alertWindowIsAttachedSheet: false, modalWindow: nil))
        // A sheet without a nested loop: still attached, and nothing app-modal
        // over it.
        XCTAssertTrue(ModalAlertRegistry.mayAnswer(isAppModal: false, alertWindow: alertWindow,
                                                   alertWindowIsAttachedSheet: true, modalWindow: nil))
        XCTAssertFalse(ModalAlertRegistry.mayAnswer(isAppModal: false, alertWindow: alertWindow,
                                                    alertWindowIsAttachedSheet: true, modalWindow: other))
        XCTAssertFalse(ModalAlertRegistry.mayAnswer(isAppModal: false, alertWindow: alertWindow,
                                                    alertWindowIsAttachedSheet: false, modalWindow: nil))
        // No window to check (a stand-in registered by a test): allowed.
        XCTAssertTrue(ModalAlertRegistry.mayAnswer(isAppModal: true, alertWindow: nil,
                                                   alertWindowIsAttachedSheet: false, modalWindow: other))
    }
}

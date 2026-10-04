//
//  iTermModalAlertRegistry.swift
//  iTerm2
//
//  A thread-safe record of the modal alerts currently on screen, so something
//  that is NOT on the main thread can see them and answer one.
//
//  A modal alert started from a main-queue callout freezes the main dispatch
//  queue and every @MainActor job until it is dismissed. The companion app's
//  connection keeps running off the main actor through such a freeze, and this
//  registry is how it shows the alert on the phone and presses a button for the
//  user. iTermWarning registers each alert just before it runs and unregisters
//  it right after.
//
//  Nothing here knows about the companion app. It subscribes as an observer.
//

import AppKit
import os

/// What an alert looks like, as plain values that can cross threads.
struct ModalAlertSnapshot: Equatable, Sendable {
    struct Button: Equatable, Sendable {
        let title: String
        let isCancel: Bool
        let isDestructive: Bool
        /// Whether choosing this button may be remembered (it is not Cancel and
        /// not excluded by the alert).
        let rememberable: Bool
    }

    /// A value the alert asks for: a control in its accessory view.
    struct Input: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case text
            case integer(minimum: Int, maximum: Int)
        }
        let id: String
        /// The control's label, or nil if it has none.
        let label: String?
        let kind: Kind
        /// What the control held when the alert was registered.
        let value: String
    }

    let id: UUID
    let heading: String
    let body: String
    /// In the alert's own order. Index 0 is the default button.
    let buttons: [Button]
    /// The label of the "don't ask again" checkbox, or nil if the alert has none.
    let suppressionLabel: String?
    /// The values the alert asks for. Usually empty.
    let inputs: [Input]
    /// The alert shows an extra view (details, a control) that is not described
    /// here. False when `inputs` covers everything in it.
    let hasAccessory: Bool
    /// False for a sheet shown without a nested run loop, which does not freeze
    /// the main queue.
    let isAppModal: Bool

    init(id: UUID,
         heading: String,
         body: String,
         buttons: [Button],
         suppressionLabel: String?,
         inputs: [Input] = [],
         hasAccessory: Bool,
         isAppModal: Bool) {
        self.id = id
        self.heading = heading
        self.body = body
        self.buttons = buttons
        self.suppressionLabel = suppressionLabel
        self.inputs = inputs
        self.hasAccessory = hasAccessory
        self.isAppModal = isAppModal
    }
}

/// The registry as its off-main consumer sees it. A protocol so tests can
/// substitute a fake.
protocol ModalAlertSource: AnyObject, Sendable {
    /// The alerts on screen, bottom to top. The last one is the one a user
    /// could click. Alerts that block the app are above sheets that do not,
    /// whichever was shown first.
    func currentAlerts() -> [ModalAlertSnapshot]

    /// `changed` is called, synchronously and on the main thread, each time the
    /// list changes. The main thread may be about to freeze, so it must not
    /// depend on anything that needs the main thread to run afterwards: yield
    /// into a stream and return. Keep the returned token to stay subscribed.
    func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject

    /// Press a button on the alert with this id. Works while the alert's modal
    /// run loop has the main queue frozen. Returns false, pressing nothing, if
    /// that alert is no longer the one on top, the index is out of range, or
    /// something that is not registered here (a plain NSAlert, an open panel)
    /// is in front of it, or a value in `inputs` is not acceptable. `suppress`
    /// checks the alert's "don't ask again" box first, when it has one and the
    /// button allows it. `inputs` maps the id of each of the alert's inputs to
    /// the value to put in its control first; a control whose id is absent is
    /// left as it is.
    func answer(id: UUID, buttonIndex: Int, suppress: Bool, inputs: [String: String]) async -> Bool
}

extension ModalAlertSource {
    func answer(id: UUID, buttonIndex: Int, suppress: Bool) async -> Bool {
        return await answer(id: id, buttonIndex: buttonIndex, suppress: suppress, inputs: [:])
    }
}

/// Describes an alert being registered. Objective-C friendly.
@objc(iTermModalAlertDescriptor)
final class ModalAlertDescriptor: NSObject {
    @objc(iTermModalAlertButton)
    final class Button: NSObject {
        @objc let title: String
        @objc let isCancel: Bool
        @objc let isDestructive: Bool
        @objc let rememberable: Bool

        @objc init(title: String, isCancel: Bool, isDestructive: Bool, rememberable: Bool) {
            self.title = title
            self.isCancel = isCancel
            self.isDestructive = isDestructive
            self.rememberable = rememberable
        }
    }

    /// A value the alert asks for.
    @objc(iTermModalAlertInput)
    final class Input: NSObject {
        @objc let identifier: String
        @objc let label: String?
        @objc let isInteger: Bool
        /// The range for an integer. Ignored for text.
        @objc let minimum: Int
        @objc let maximum: Int
        @objc let value: String

        @objc init(identifier: String, label: String?, isInteger: Bool, minimum: Int, maximum: Int, value: String) {
            self.identifier = identifier
            self.label = label
            self.isInteger = isInteger
            self.minimum = minimum
            self.maximum = maximum
            self.value = value
        }
    }

    @objc let heading: String
    @objc let body: String
    @objc let buttons: [Button]
    @objc let suppressionLabel: String?
    @objc let inputs: [Input]
    @objc let hasAccessory: Bool
    @objc let isAppModal: Bool

    @objc init(heading: String,
               body: String,
               buttons: [Button],
               suppressionLabel: String?,
               inputs: [Input],
               hasAccessory: Bool,
               isAppModal: Bool) {
        self.heading = heading
        self.body = body
        self.buttons = buttons
        self.suppressionLabel = suppressionLabel
        self.inputs = inputs
        self.hasAccessory = hasAccessory
        self.isAppModal = isAppModal
    }

    convenience init(heading: String,
                     body: String,
                     buttons: [Button],
                     suppressionLabel: String?,
                     hasAccessory: Bool,
                     isAppModal: Bool) {
        self.init(heading: heading, body: body, buttons: buttons, suppressionLabel: suppressionLabel,
                  inputs: [], hasAccessory: hasAccessory, isAppModal: isAppModal)
    }
}

/// Returned by register. Call unregister when the alert is gone.
@objc(iTermModalAlertRegistration)
final class ModalAlertRegistration: NSObject {
    @objc let identifier: UUID
    private weak var registry: ModalAlertRegistry?

    fileprivate init(identifier: UUID, registry: ModalAlertRegistry) {
        self.identifier = identifier
        self.registry = registry
    }

    /// Idempotent. Main thread only.
    @MainActor
    @objc func unregister() {
        registry?.unregister(identifier)
    }
}

@objc(iTermModalAlertRegistry)
final class ModalAlertRegistry: NSObject, ModalAlertSource {
    @objc static let shared = ModalAlertRegistry()

    private struct Entry {
        let snapshot: ModalAlertSnapshot
        /// False for a stand-in registered without a window, which skips the
        /// what-is-in-front check.
        let hasWindow: Bool
        weak var window: NSWindow?
        let press: (Int, Bool, [String: String]) -> Bool
    }

    /// The alerts on screen, bottom to top, with what is needed to press their
    /// buttons. Only the main thread can do that, so this lives there.
    @MainActor private var entries: [Entry] = []
    /// What other threads read. Updated in the same main-thread call that
    /// changes `entries`, so it is current before the main queue can freeze.
    private let snapshots = OSAllocatedUnfairLock(initialState: [ModalAlertSnapshot]())
    private let observers = WeakObserverList()
    private let modalWindow: @MainActor @Sendable () -> NSWindow?

    /// - modalWindow: the window of the app-modal session that is running right
    ///   now, if any. Injected for tests.
    init(modalWindow: @escaping @MainActor @Sendable () -> NSWindow? = { NSApp.modalWindow }) {
        self.modalWindow = modalWindow
    }

    /// Record an alert that is about to be shown. Main thread only.
    ///
    /// - window: the alert's own window, used to check that it is still the
    ///   one in front when an answer arrives.
    /// - press: clicks the button at an index, first putting the given values
    ///   into the alert's input controls and checking the "don't ask again" box
    ///   if asked. Called on the main thread, inside the alert's modal run loop.
    ///   Returns false if it could not.
    @MainActor
    @objc(registerAlert:window:press:)
    func register(_ descriptor: ModalAlertDescriptor,
                  window: NSWindow?,
                  press: @escaping (_ buttonIndex: Int, _ suppress: Bool, _ inputs: [String: String]) -> Bool) -> ModalAlertRegistration {
        let snapshot = ModalAlertSnapshot(
            id: UUID(),
            heading: descriptor.heading,
            body: descriptor.body,
            buttons: descriptor.buttons.map {
                ModalAlertSnapshot.Button(title: $0.title,
                                          isCancel: $0.isCancel,
                                          isDestructive: $0.isDestructive,
                                          rememberable: $0.rememberable)
            },
            suppressionLabel: descriptor.suppressionLabel,
            inputs: descriptor.inputs.map {
                ModalAlertSnapshot.Input(
                    id: $0.identifier,
                    label: $0.label,
                    kind: $0.isInteger ? .integer(minimum: $0.minimum, maximum: $0.maximum) : .text,
                    value: $0.value)
            },
            hasAccessory: descriptor.hasAccessory,
            isAppModal: descriptor.isAppModal)
        let entry = Entry(snapshot: snapshot, hasWindow: window != nil, window: window, press: press)
        // Kept in front-to-back order, last in front. Registration order alone
        // is not that: a sheet that does not block can be started while an
        // app-modal alert is up (from a timer, say), and the app-modal alert is
        // still the one in front and in the way. So sheets go behind every
        // app-modal alert, and each group stays in the order it was registered.
        if descriptor.isAppModal {
            entries.append(entry)
        } else {
            let firstAppModal = entries.firstIndex { $0.snapshot.isAppModal } ?? entries.endIndex
            entries.insert(entry, at: firstAppModal)
        }
        DLog("Modal alert registered: \(snapshot.id) “\(snapshot.heading)”")
        entriesDidChange()
        return ModalAlertRegistration(identifier: snapshot.id, registry: self)
    }

    @MainActor
    fileprivate func unregister(_ identifier: UUID) {
        guard let index = entries.firstIndex(where: { $0.snapshot.id == identifier }) else {
            return
        }
        entries.remove(at: index)
        DLog("Modal alert unregistered: \(identifier)")
        entriesDidChange()
    }

    @MainActor
    private func entriesDidChange() {
        let current = entries.map { $0.snapshot }
        snapshots.withLock { $0 = current }
        // Synchronous, on purpose: the caller is about to run a modal loop,
        // which may freeze the main queue. Anything deferred to it would not
        // happen until the alert was dismissed.
        observers.notify()
    }

    /// For an alert with no inputs.
    @MainActor
    func register(_ descriptor: ModalAlertDescriptor,
                  window: NSWindow?,
                  press: @escaping (_ buttonIndex: Int, _ suppress: Bool) -> Bool) -> ModalAlertRegistration {
        return register(descriptor, window: window) { buttonIndex, suppress, _ in
            press(buttonIndex, suppress)
        }
    }

    /// Whether an alert may be answered right now, given what is in front.
    ///
    /// An app-modal alert must itself be the running modal session. A sheet
    /// shown without a nested run loop must still be attached, with no
    /// app-modal session over it. Otherwise something unregistered is on top,
    /// and a click would end THAT session instead, with a bogus result.
    static func mayAnswer(isAppModal: Bool,
                          alertWindow: NSWindow?,
                          alertWindowIsAttachedSheet: Bool,
                          modalWindow: NSWindow?) -> Bool {
        guard let alertWindow else {
            // A stand-in registered without a window. Nothing to check.
            return true
        }
        if isAppModal {
            return modalWindow === alertWindow
        }
        return alertWindowIsAttachedSheet && modalWindow == nil
    }

    @MainActor
    private func press(id: UUID, buttonIndex: Int, suppress: Bool, inputs: [String: String]) -> Bool {
        // Looked up here, on the main thread, at the moment of the click: an
        // answer for an alert the user already dismissed finds nothing.
        guard let top = entries.last, top.snapshot.id == id else {
            DLog("Modal alert answer refused: \(id) is not the alert on top")
            return false
        }
        guard top.snapshot.buttons.indices.contains(buttonIndex) else {
            DLog("Modal alert answer refused: no button \(buttonIndex)")
            return false
        }
        if top.hasWindow {
            guard let window = top.window,
                  Self.mayAnswer(isAppModal: top.snapshot.isAppModal,
                                 alertWindow: window,
                                 alertWindowIsAttachedSheet: window.sheetParent != nil,
                                 modalWindow: modalWindow()) else {
                DLog("Modal alert answer refused: something else is in front of \(id)")
                return false
            }
        }
        return top.press(buttonIndex, suppress, inputs)
    }

    // MARK: ModalAlertSource

    func currentAlerts() -> [ModalAlertSnapshot] {
        return snapshots.withLock { $0 }
    }

    func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject {
        return observers.add(changed)
    }

    func answer(id: UUID, buttonIndex: Int, suppress: Bool, inputs: [String: String]) async -> Bool {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // A run loop block in the common modes is one of the few things
            // that still runs on the main thread inside a modal run loop that
            // was started from a main-queue callout. The main queue and
            // @MainActor tasks do not.
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                let pressed = MainActor.assumeIsolated {
                    self.press(id: id, buttonIndex: buttonIndex, suppress: suppress, inputs: inputs)
                }
                continuation.resume(returning: pressed)
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }
}

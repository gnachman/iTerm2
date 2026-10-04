//
//  CompanionModalFreezeDebug.swift
//  iTerm2
//
//  Debug-menu triggers for manually testing the companion app while the main
//  queue is frozen. A modal started from a main-queue callout (a @MainActor
//  task or a DispatchQueue.main.async block) stops the main dispatch queue and
//  every @MainActor job until it is dismissed. Alerts opened straight from a
//  menu action do not, so these deliberately hop first.
//

import AppKit

@objc(iTermCompanionModalFreezeDebug)
final class CompanionModalFreezeDebug: NSObject {
    private static func showWarning(origin: String) {
        // Localization unneeded
        iTermWarning.show(withTitle: "This alert was started from \(origin), so the main queue is frozen until you dismiss it.",
                          actions: ["OK", "Cancel"],
                          accessory: nil,
                          identifier: "NoSyncDebugCompanionModalFreeze",
                          silenceable: .kiTermWarningTypeTemporarilySilenceable,
                          heading: "Main Queue Freeze Test",
                          window: nil)
    }

    @objc static func showWarningFromMainActorTask() {
        Task { @MainActor in
            showWarning(origin: "a @MainActor task")
        }
    }

    @objc static func showWarningFromMainQueueBlock() {
        DispatchQueue.main.async {
            showWarning(origin: "a DispatchQueue.main.async block")
        }
    }

    /// A plain NSAlert, which the companion app will never be able to answer.
    @objc static func showPlainAlertFromMainQueueBlock() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            // Localization unneeded
            alert.messageText = "Main Queue Freeze Test"
            alert.informativeText = "This plain NSAlert was started from a DispatchQueue.main.async block, so the main queue is frozen until you dismiss it."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

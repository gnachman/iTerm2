//
//  SessionView+DiffWaitingPromptOverlay.swift
//  iTerm2SharedARC
//
//  Owns the lifecycle of the in-session diff-waiting overlay so the
//  rest of the codebase doesn’t reach into SessionView’s subview tree
//  directly. Parallels SessionView+CodeReviewPromptOverlay.swift.
//

import AppKit

extension SessionView {
    // Initial-spawn variant: the .diff session has never run its
    // command and the overlay explains why nothing is happening yet.
    // No Cancel button (canceling here would just leave the buried
    // session sitting empty forever).
    @objc(presentDiffWaitingPromptOverlayWithOnRunAnyway:)
    func presentDiffWaitingPromptOverlay(onRunAnyway: @escaping () -> Void) {
        installOverlay(
            DiffWaitingPromptView(
                frame: scrollview.frame,
                title: "Diff session is waiting for changes.",
                body: "This session is set to Diff mode and only starts its "
                    + "command when git reports staged or unstaged changes. "
                    + "The working tree is currently clean, or iTerm2 hasn’t "
                    + "finished its first check yet. Edit a file (or stage one) "
                    + "and the command will start on its own. To run it now "
                    + "anyway, click below.",
                showCancel: false),
            onRunAnyway: onRunAnyway,
            onCancel: nil)
    }

    // Queued-reload variant: the user clicked Reload while the tree
    // was clean. The previous program is still on-screen underneath;
    // the overlay describes the queue state and offers a Cancel
    // button so the user can back out without restarting (which
    // would otherwise fire as soon as the next change is detected).
    @objc(presentDiffWaitingPromptOverlayForQueuedReloadWithOnRunAnyway:onCancel:)
    func presentDiffWaitingPromptOverlayForQueuedReload(
        onRunAnyway: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        installOverlay(
            DiffWaitingPromptView(
                frame: scrollview.frame,
                title: "Reload queued. Waiting for changes.",
                body: "This session is set to Diff mode, so Reload will "
                    + "re-run the command only after git reports staged or "
                    + "unstaged changes. The previous output is still on "
                    + "screen behind this panel. Cancel to keep that output "
                    + "and abandon the reload, or run the command now anyway.",
                showCancel: true),
            onRunAnyway: onRunAnyway,
            onCancel: onCancel)
    }

    @objc
    func dismissDiffWaitingPromptOverlay() {
        diffWaitingPromptOverlay?.removeFromSuperview()
    }

    // Shared install path: drop any existing overlay so a rapid
    // re-present doesn't stack two views, wire up frame tracking
    // and the action closures, and add the view below the find
    // overlay. The closures wrap the user-supplied callback with
    // an automatic removeFromSuperview so the caller doesn't have
    // to dismiss the overlay from inside its own action.
    private func installOverlay(_ promptView: DiffWaitingPromptView,
                                onRunAnyway: @escaping () -> Void,
                                onCancel: (() -> Void)?) {
        diffWaitingPromptOverlay?.removeFromSuperview()

        promptView.frameProvider = { [weak self] in
            guard let self else { return .zero }
            var rect = self.scrollview.frame
            rect.size.width = max(0, rect.size.width - self.actualPanelReservation)
            return rect
        }
        promptView.onRunAnyway = { [weak promptView] in
            onRunAnyway()
            promptView?.removeFromSuperview()
        }
        if let onCancel {
            promptView.onCancel = { [weak promptView] in
                onCancel()
                promptView?.removeFromSuperview()
            }
        }
        diffWaitingPromptOverlay = promptView
        addSubview(belowFind: promptView)
    }
}

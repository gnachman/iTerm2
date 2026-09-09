//
//  iTermUndoCloseMigrationWarning.swift
//  iTerm2SharedARC
//
//  Shows a one-time alert the first time the user presses ⌘Z (Undo) while a
//  session they just closed can still be restored. ⌘Z used to perform Undo
//  Close; that moved to Shell > Undo Close (⌘⇧T) and ⌘Z is now idiomatic text
//  undo. The alert explains the change and lets the user pick what they meant
//  this time (reopen the closed session, or do a normal undo).
//
//  While the alert is up the restorable sessions' termination countdowns are
//  paused, so the session the user is about to reopen doesn't expire out from
//  under them.
//

import AppKit

@objc(iTermUndoCloseMigrationWarning)
class iTermUndoCloseMigrationWarning: NSObject {
    // Presents the one-time notice if it applies. Returns true if it handled this
    // Undo press (by showing the alert and acting on the choice); false if the
    // caller should just perform a normal undo itself.
    @objc(maybeShowWithUndoClose:regularUndo:)
    static func maybeShow(undoClose: @escaping () -> Void,
                          regularUndo: @escaping () -> Void) -> Bool {
        guard let controller = iTermController.sharedInstance(),
              !iTermUserDefaults.haveWarnedAboutUndoKeyChange,
              controller.hasRestorableSession else {
            return false
        }

        let warning = iTermWarning()
        warning.heading = "Undo Close Moved"
        warning.title = """
            ⌘Z now undoes text editing. To reopen a session you just closed, use \
            Shell ▸ Undo Close (⌘⇧T).

            What would you like to do now?
            """
        warning.warningActions = [
            iTermWarningAction(label: "Undo Close"),
            iTermWarningAction(label: "Regular Undo"),
            iTermWarningAction(label: "Cancel"),
        ]
        warning.warningType = .kiTermWarningTypePersistent
        // Deliberately app-modal (no owning window). This is triggered by a global
        // ⌘Z and what is being restored may be a whole window, or the front
        // terminal may itself be mid-close, so no window sensibly owns this alert.
        // Attaching it as a sheet to currentTerminal would put it on the wrong (or
        // a doomed) window; a windowless modal sidesteps that ownership problem.

        // Keep the restorable session(s) alive while the modal alert is up. Run
        // the modal inside the ObjC pause/resume wrapper so the resume is
        // guaranteed even if runModal raises an ObjC exception (Swift `defer`
        // would not run on ObjC exception unwinding). The resume therefore also
        // happens before the action closures below, so a throwing closure can't
        // strand the paused timers either.
        var selection: iTermWarningSelection = .kItermWarningSelectionError
        controller.performBlock(restorableSessionTerminationPaused: {
            selection = warning.runModal()
        })

        switch selection {
        case .kiTermWarningSelection0:
            // Only mark the notice shown once the user actually chose an action, so
            // Cancel leaves it to appear again next time.
            iTermUserDefaults.haveWarnedAboutUndoKeyChange = true
            undoClose()
        case .kiTermWarningSelection1:
            iTermUserDefaults.haveWarnedAboutUndoKeyChange = true
            regularUndo()
        default:
            break
        }
        return true
    }
}

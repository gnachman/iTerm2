//
//  iTermUndoCloseShortcutChangeWarning.swift
//  iTerm2SharedARC
//
//  Shows a one-time alert the first time a user triggers the new ⌘⇧T shortcut
//  while in full screen. ⌘⇧T used to toggle Show Tabs in Fullscreen but now
//  performs Undo Close (Show Tabs moved to ⌘⇧U). The alert explains this and
//  offers to add a global key binding that maps ⌘⇧T back to Show Tabs in
//  Fullscreen, restoring the behavior the user is used to. A global key binding
//  is consulted before menu key equivalents, so it overrides the new ⌘⇧T ->
//  Undo Close menu shortcut.
//
//  There are two entry points because the trigger depends on whether there is
//  anything to undo:
//
//  * If a closed session can be restored, the ⌘⇧T menu shortcut fires Undo
//    Close normally and -undoCloseSession: calls maybeShow(forTriggeringEvent:
//    wasFullScreen:) afterward.
//
//  * If nothing can be restored, the Undo Close menu item is disabled and its
//    key equivalent never fires, so iTermApplication's key-down path calls
//    maybeHandleKeyDownWhenUndoCloseDisabled(_:) to still show the notice.
//

import AppKit

@objc(iTermUndoCloseShortcutChangeWarning)
class iTermUndoCloseShortcutChangeWarning: NSObject {
    // Title and identifier of the Show Tabs in Fullscreen menu item in
    // MainMenu.xib. Used to build the KEY_ACTION_SELECT_MENU_ITEM parameter
    // (title\nidentifier).
    private static let showTabsMenuItemTitle = "Show Tabs in Fullscreen"

    // Call right after Undo Close runs. If `event` is a ⌘⇧T key-down,
    // `wasFullScreen` is YES, and the notice has not been shown before, displays
    // it. Does nothing otherwise. Safe to call with a nil event.
    @objc(maybeShowForTriggeringEvent:wasFullScreen:)
    static func maybeShow(forTriggeringEvent event: NSEvent?, wasFullScreen: Bool) {
        guard wasFullScreen,
              !iTermUserDefaults.haveWarnedAboutUndoCloseShortcutChange,
              let event,
              isCommandShiftT(event) else {
            return
        }
        presentNoticeOnce(for: event)
    }

    // Call from the key-down path. When Undo Close is disabled (nothing to
    // restore) its ⌘⇧T menu shortcut never fires, so we detect the keystroke
    // here to still show the one-time notice. Returns true if the event was
    // consumed. When there IS something to undo this returns false so the menu
    // shortcut performs Undo Close normally (the notice is then shown from
    // -undoCloseSession:).
    @objc(maybeHandleKeyDownWhenUndoCloseDisabled:)
    static func maybeHandleKeyDownWhenUndoCloseDisabled(_ event: NSEvent) -> Bool {
        guard isCommandShiftT(event),
              !iTermUserDefaults.haveWarnedAboutUndoCloseShortcutChange,
              let term = iTermController.sharedInstance().currentTerminal,
              term.anyFullScreen(),
              !iTermController.sharedInstance().hasRestorableSession else {
            return false
        }
        presentNoticeOnce(for: event)
        return true
    }

    private static func presentNoticeOnce(for event: NSEvent) {
        iTermUserDefaults.haveWarnedAboutUndoCloseShortcutChange = true

        // Capture the keystroke now, while we still have the event, so that an
        // added binding serializes exactly the way the keyboard handler will
        // look it up later. isCommandShiftT(_:) has already excluded leader
        // sequences, so this is a plain ⌘⇧T.
        let keystroke = iTermKeystroke.withEvent(event)

        // Let any Undo Close visibly finish before interrupting with a modal alert.
        DispatchQueue.main.async {
            showWarning(offeringBindingFor: keystroke)
        }
    }

    private static func isCommandShiftT(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return false
        }
        // A leader-flagged ⌘⇧T is a leader sequence, not the plain ⌘⇧T shortcut
        // this notice is about, so reject it. (iTermApplication re-dispatches
        // events with iTermLeaderModifierFlag set on modifierFlags while leader
        // mode is active.)
        let leaderFlag = NSEvent.ModifierFlags(rawValue: iTermEventModifierFlags.leaderModifierFlag.rawValue)
        guard !event.modifierFlags.contains(leaderFlag) else {
            return false
        }
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        guard event.modifierFlags.intersection(relevant) == [.command, .shift] else {
            return false
        }
        return event.charactersIgnoringModifiers?.lowercased() == "t"
    }

    private static func showWarning(offeringBindingFor keystroke: iTermKeystroke) {
        let ok = iTermWarningAction(label: "Keep New Shortcut")
        let restore = iTermWarningAction(label: "Restore ⌘⇧T to Show Tabs") { _ in
            addGlobalShowTabsBinding(for: keystroke)
        }

        let warning = iTermWarning()
        warning.heading = "Keyboard Shortcut Changed"
        warning.title = """
            ⌘⇧T now restores recently closed tabs (Undo Close). The Show Tabs in \
            Fullscreen shortcut has moved to ⌘⇧U.

            Would you like to keep ⌘⇧T as the shortcut for Show Tabs in Fullscreen \
            by adding a key binding?
            """
        warning.warningActions = [ok, restore]
        warning.warningType = .kiTermWarningTypePersistent
        warning.window = iTermController.sharedInstance().currentTerminal?.window()
        warning.runModal()
    }

    private static func addGlobalShowTabsBinding(for keystroke: iTermKeystroke) {
        let parameter = "\(showTabsMenuItemTitle)\n\(showTabsMenuItemTitle)"
        guard let action = iTermKeyBindingAction.withAction(.ACTION_SELECT_MENU_ITEM,
                                                            parameter: parameter,
                                                            escaping: .none,
                                                            applyMode: .currentSession) else {
            return
        }
        // Mirror what +[iTermKeyMappings setMappingAtIndex:...inDictionary:] does:
        // store the action keyed by the serialized keystroke, replacing any
        // existing binding for the same keystroke. A global binding is consulted
        // ahead of menu key equivalents, so this overrides ⌘⇧T -> Undo Close.
        var globalKeyMap = iTermKeyMappings.globalKeyMap()
        globalKeyMap[keystroke.serialized] = action.dictionaryValue
        iTermKeyMappings.setGlobalKeyMap(globalKeyMap)
    }
}

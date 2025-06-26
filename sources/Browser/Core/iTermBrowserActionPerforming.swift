//
//  iTermBrowserActionPerforming.swift
//  iTerm2
//
//  Created by George Nachman on 6/25/25.
//

enum ScrollMovement {
    case end
    case home
    case down
    case up
    case pageDown
    case pageUp
}

protocol iTermBrowserActionPerforming: AnyObject {
    func actionPerformingScroll(movement: ScrollMovement)
    func actionPerformingSend(data: Data, broadcastAllowed: Bool)

    // Extend the start or end of the selection forward (to the right) or leftwards (to the left)
    func actionPerformingExtendSelect(start: Bool, forward: Bool, by: PTYTextViewSelectionExtensionUnit)
    func actionPerformExtendSelection(toPointInWindow point: NSPoint)
    func actionPerformingHasSelection() async -> Bool
    func actionPerformingCopyToClipboard()
    func actionPerformingPasteFromClipboard()

    // TODO: This should do semantic history but opening a link will have to do for now
    func actionPerformingOpen(atWindowLocation: NSPoint,
                              inBackground: Bool)

    // This should copy if kPreferenceKeySelectionCopiesText is set.
    func actionPerformingSmartSelect(atWindowLocation: NSPoint)

    func actionPerformingOpenContextMenu(atWindowLocation: NSPoint)

    func actionPerformingMovePane()

    func actionPerformingCurrentTerminal() -> PseudoTerminal?

    func actionPerformingSplit(vertically: Bool, guid: String)

    // delegate.previousSession or nextSession
    func actionPerformingSelectPane(forward: Bool)
    func actionPerformingInvoke(scriptFunction: String)
    func actionPerformingOpenQuickLook(atPointInWindow point: NSPoint)
}


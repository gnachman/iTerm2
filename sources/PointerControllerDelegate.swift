//
//  PointerController.swift
//  iTerm
//
//  Created by George Nachman on 8/4/25.
//  Copyright © 2025 George Nachman. All rights reserved.
//

import AppKit

@MainActor
@objc(PointerControllerDelegate)
protocol PointerControllerDelegate: AnyObject {
    @objc(pasteFromClipboardWithEvent:)
    func pasteFromClipboard(with event: NSEvent)

    @objc(pasteFromSelectionWithEvent:)
    func pasteFromSelection(with event: NSEvent)

    @objc(openTargetWithEvent:)
    func openTarget(with event: NSEvent)

    @objc(openTargetInBackgroundWithEvent:)
    func openTargetInBackground(with event: NSEvent)

    @objc(smartSelectAndMaybeCopyWithEvent:ignoringNewlines:)
    func smartSelectAndMaybeCopy(with event: NSEvent,
                                 ignoringNewlines: Bool)

    @objc(openContextMenuWithEvent:)
    func openContextMenu(with event: NSEvent)

    @objc(nextTabWithEvent:)
    func nextTab(with event: NSEvent)

    @objc(previousTabWithEvent:)
    func previousTab(with event: NSEvent)

    @objc(nextWindowWithEvent:)
    func nextWindow(with event: NSEvent)

    @objc(previousWindowWithEvent:)
    func previousWindow(with event: NSEvent)

    @objc(movePaneWithEvent:)
    func movePane(with event: NSEvent)

    @objc(sendEscapeSequence:withEvent:)
    func sendEscapeSequence(_ text: String,
                            withEvent event: NSEvent)

    @objc(sendHexCode:withEvent:)
    func sendHexCode(_ codes: String,
                     withEvent event: NSEvent)

    @objc(sendText:withEvent:escaping:)
    func sendText(_ text: String,
                  withEvent event: NSEvent,
                  escaping: iTermSendTextEscaping)

    @objc(selectPaneLeftWithEvent:)
    func selectPaneLeft(with event: NSEvent)

    @objc(selectPaneRightWithEvent:)
    func selectPaneRight(with event: NSEvent)

    @objc(selectPaneAboveWithEvent:)
    func selectPaneAbove(with event: NSEvent)

    @objc(selectPaneBelowWithEvent:)
    func selectPaneBelow(with event: NSEvent)

    @objc(newWindowWithProfile:withEvent:)
    func newWindow(withProfile guid: String,
                   withEvent event: NSEvent)

    @objc(newTabWithProfile:withEvent:)
    func newTab(withProfile guid: String,
                withEvent event: NSEvent)

    @objc(newVerticalSplitWithProfile:withEvent:)
    func newVerticalSplit(withProfile guid: String,
                          withEvent event: NSEvent)

    @objc(newHorizontalSplitWithProfile:withEvent:)
    func newHorizontalSplit(withProfile guid: String,
                            withEvent event: NSEvent)

    @objc(selectNextPaneWithEvent:)
    func selectNextPane(with event: NSEvent)

    @objc(selectPreviousPaneWithEvent:)
    func selectPreviousPane(with event: NSEvent)

    @objc(extendSelectionWithEvent:)
    func extendSelection(with event: NSEvent)

    @objc(quickLookWithEvent:)
    func quickLook(with event: NSEvent)

    @objc(advancedPasteWithConfiguration:fromSelection:withEvent:)
    func advancedPaste(withConfiguration configuration: String,
                       fromSelection: Bool,
                       withEvent event: NSEvent)

    @objc(selectMenuItemWithIdentifier:title:event:)
    func selectMenuItem(withIdentifier identifier: String?,
                        title: String?,
                        event: NSEvent)

    @objc(invokeScriptFunction:withEvent:)
    func invokeScriptFunction(_ function: String,
                              withEvent event: NSEvent)
}

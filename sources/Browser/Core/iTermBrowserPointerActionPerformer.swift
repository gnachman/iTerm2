//
//  iTermBrowserPointerActionPerformer.swift
//  iTerm2
//
//  Created by George Nachman on 6/25/25.
//

@MainActor
@objc
class iTermBrowserPointerActionPerformer: NSObject, PointerControllerDelegate {
    weak var delegate: iTermBrowserActionPerforming?

    func pasteFromClipboard(with event: NSEvent) {
        if !NSString.fromPasteboard().isEmpty {
            delegate?.actionPerformingPasteFromClipboard()
        }
    }

    private func data(for event: NSEvent) -> Data? {
        return event.characters?.lossyData
    }

    func pasteFromSelection(with event: NSEvent) {
        withClipboardPreserved {
            delegate?.actionPerformingCopyToClipboard()
            if !NSString.fromPasteboard().isEmpty {
                delegate?.actionPerformingPasteFromClipboard()
            }
        }
    }

    private func withClipboardPreserved<T>(_ block: () throws -> T) rethrows -> T {
        let pasteboard = NSPasteboard.general
        let originalItems = pasteboard.pasteboardItems ?? []

        let result = try block()

        pasteboard.clearContents()
        if originalItems.isEmpty == false {
            pasteboard.writeObjects(originalItems)
        }

        return result
    }

    func openTarget(with event: NSEvent) {
        delegate?.actionPerformingOpen(atWindowLocation: event.locationInWindow,
                                       inBackground: false)
    }

    func openTargetInBackground(with event: NSEvent) {
        delegate?.actionPerformingOpen(atWindowLocation: event.locationInWindow,
                                       inBackground: true)
    }

    func smartSelectAndMaybeCopy(with event: NSEvent, ignoringNewlines: Bool) {
        delegate?.actionPerformingSmartSelect(atWindowLocation: event.locationInWindow)
    }

    func openContextMenu(with event: NSEvent) {
        delegate?.actionPerformingOpenContextMenu(
            atWindowLocation: event.locationInWindow,)
    }

    func nextTab(with event: NSEvent) {
        delegate?.actionPerformingCurrentTerminal()?.tabView().cycleForwards(true)
    }

    func previousTab(with event: NSEvent) {
        delegate?.actionPerformingCurrentTerminal()?.tabView().cycleForwards(false)
    }

    func nextWindow(with event: NSEvent) {
        iTermController.sharedInstance().nextTerminal()
    }

    func previousWindow(with event: NSEvent) {
        iTermController.sharedInstance().previousTerminal()
    }

    func movePane(with event: NSEvent) {
        delegate?.actionPerformingMovePane()
    }

    func sendEscapeSequence(_ text: String, withEvent event: NSEvent) {
    }

    func sendHexCode(_ codes: String, withEvent event: NSEvent) {
        if let data = NSString.data(forHexCodes: codes) {
            delegate?.actionPerformingSend(
                data: data,
                broadcastAllowed: true)
        }
    }

    func sendText(_ text: String, withEvent event: NSEvent, escaping: iTermSendTextEscaping) {
        let data = iTermKeyBindingAction.escapedText(text,
                                                     mode: escaping).lossyData
        delegate?.actionPerformingSend(data: data, broadcastAllowed: true)
    }

    func selectPaneLeft(with event: NSEvent) {
        delegate?.actionPerformingCurrentTerminal()?.selectPaneLeft(self)
    }

    func selectPaneRight(with event: NSEvent) {
        delegate?.actionPerformingCurrentTerminal()?.selectPaneRight(self)
    }

    func selectPaneAbove(with event: NSEvent) {
        delegate?.actionPerformingCurrentTerminal()?.selectPaneUp(self)
    }

    func selectPaneBelow(with event: NSEvent) {
        delegate?.actionPerformingCurrentTerminal()?.selectPaneDown(self)
    }

    func newWindow(withProfile guid: String, withEvent event: NSEvent) {
        delegate?.actionPerformingCurrentTerminal()?.newWindow(withBookmarkGuid: guid)
    }

    func newTab(withProfile guid: String, withEvent event: NSEvent) {
        delegate?.actionPerformingCurrentTerminal()?.newTab(withBookmarkGuid: guid)
    }

    func newVerticalSplit(withProfile guid: String, withEvent event: NSEvent) {
        delegate?.actionPerformingSplit(vertically: true, guid: guid)
    }

    func newHorizontalSplit(withProfile guid: String, withEvent event: NSEvent) {
        delegate?.actionPerformingSplit(vertically: false, guid: guid)
    }

    func selectNextPane(with event: NSEvent) {
        delegate?.actionPerformingSelectPane(forward: true)
    }

    func selectPreviousPane(with event: NSEvent) {
        delegate?.actionPerformingSelectPane(forward: false)
    }

    func extendSelection(with event: NSEvent) {
        delegate?.actionPerformExtendSelection(toPointInWindow: event.locationInWindow)
    }

    func advancedPaste(withConfiguration configuration: String, fromSelection: Bool, withEvent event: NSEvent) {
        // TODO
    }

    func selectMenuItem(withIdentifier identifier: String?, title: String?, event: NSEvent) {
        NSApp.mainMenu?.it_selectItem(withTitle: title, identifier: identifier)
    }

    func invokeScriptFunction(_ function: String, withEvent event: NSEvent) {
        delegate?.actionPerformingInvoke(scriptFunction: function)
    }

    func quickLook(with event: NSEvent) {
        delegate?.actionPerformingOpenQuickLook(atPointInWindow: event.locationInWindow)
    }
}

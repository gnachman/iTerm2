//
//  iTermOpenQuicklyTableView.swift
//  iTerm2SharedARC
//

import AppKit

// A table view for the Open Quickly window. It never accepts first
// responder. An up or down arrow pressed without Command, Option, Shift or
// Control wraps the selection from the first row to the last, or from the
// last to the first.
@objc(iTermOpenQuicklyTableView)
class iTermOpenQuicklyTableView: NSTableView {
    override var acceptsFirstResponder: Bool {
        return false
    }

    override func keyDown(with event: NSEvent) {
        let unicode = event.characters?.utf16.first ?? 0
        let mask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        if event.modifierFlags.isDisjoint(with: mask) && numberOfRows > 0 {
            switch Int(unicode) {
            case NSDownArrowFunctionKey:
                if selectedRow + 1 == numberOfRows {
                    selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    return
                }
            case NSUpArrowFunctionKey:
                if selectedRow == 0 {
                    selectRowIndexes(IndexSet(integer: numberOfRows - 1), byExtendingSelection: false)
                    return
                }
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}

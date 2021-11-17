//
//  SearchableComboTableView.swift
//  SearchableComboListView
//
//  Created by George Nachman on 1/24/20.
//

import AppKit

protocol SearchableComboTableViewDelegate: AnyObject {
    func searchableComboTableView(_ tableView: SearchableComboTableView,
                                  didClickRow row: Int)
    func searchableComboTableView(_ tableView: SearchableComboTableView,
                                  keyDown event: NSEvent)
    func searchableComboTableViewWillResignFirstResponder(_ tableView: SearchableComboTableView)
}

@objc(iTermSearchableComboTableView)
class SearchableComboTableView: NSTableView, MouseObservingTableView {
    weak var searchableComboTableViewDelegate: SearchableComboTableViewDelegate?

    static let enterNotificationName = Notification.Name("SearchableComboTableView.Enter")
    private(set) var handlingKeyDown = false
    private var trackingArea: NSTrackingArea?
    private(set) var selectionChangedBecauseOfMovement = false
    private var usingKeyboardSelection = false

    var drawSelectionWhenMouseOutside: Bool {
        return usingKeyboardSelection
    }

    var shouldDrawSelection: Bool {
        guard let window = window else {
            return false
        }
        if usingKeyboardSelection {
            return true
        }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return selectableRowAt(point) >= 0
    }

    public override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.function) {
            handlingKeyDown = true
            super.keyDown(with: event)
            handlingKeyDown = false
            return
        }
        usingKeyboardSelection = true
        handlingKeyDown = true
        searchableComboTableViewDelegate?.searchableComboTableView(self, keyDown: event)
        handlingKeyDown = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let new = NSTrackingArea(rect: bounds,
                                 options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .assumeInside],
                                 owner: self,
                                 userInfo: nil)
        trackingArea = new
        addTrackingArea(new)
    }

    private func selectableRowAt(_ mouseLocationInWindowCoords: NSPoint) -> Int {
        let mouseLocationInViewCoords =
            convert(mouseLocationInWindowCoords, from: nil)
        let i = row(at: mouseLocationInViewCoords)
        guard i >= 0 else {
            return -1
        }
        let isGroupRow = delegate?.tableView?(self, isGroupRow: i) ?? false
        guard !isGroupRow else {
            return -1
        }
        return i
    }

    private func selectRowUnderMouse(_ event: NSEvent,
                                     becauseOfMovement: Bool = true) {
        usingKeyboardSelection = false
        let i = selectableRowAt(event.locationInWindow)
        window?.makeFirstResponder(self)
        if selectedRow == i {
            return
        }
        let indexSet = i < 0 ? IndexSet() : IndexSet(integer: i)
        let saved = selectionChangedBecauseOfMovement
        selectionChangedBecauseOfMovement = becauseOfMovement
        selectRowIndexes(indexSet,
                         byExtendingSelection: false)
        selectionChangedBecauseOfMovement = saved
    }

    override func mouseEntered(with event: NSEvent) {
        selectRowUnderMouse(event)
    }

    override func mouseExited(with event: NSEvent) {
        selectRowUnderMouse(event)
    }

    override func mouseMoved(with event: NSEvent) {
        selectRowUnderMouse(event)
    }

    override func mouseDown(with event: NSEvent) {
        selectRowUnderMouse(event, becauseOfMovement: false)
        searchableComboTableViewDelegate?.searchableComboTableView(self, didClickRow: selectableRowAt(event.locationInWindow))
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 51 /* delete */ {
            _ = delegate?.tableView?(self, shouldTypeSelectFor: event, withCurrentSearch: nil)
            return true
        }
        return false
    }

    func keyboardSelect(row: Int) {
        precondition(row >= 0)
        usingKeyboardSelection = true
        usingKeyboardSelection = true
        handlingKeyDown = true
        selectRowIndexes(IndexSet(integer: row),
                         byExtendingSelection: false)
        handlingKeyDown = false
    }

    override func resignFirstResponder() -> Bool {
        searchableComboTableViewDelegate?.searchableComboTableViewWillResignFirstResponder(self)
        return super.resignFirstResponder()
    }
}

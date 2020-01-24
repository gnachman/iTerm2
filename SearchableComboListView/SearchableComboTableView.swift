//
//  SearchableComboTableView.swift
//  SearchableComboListView
//
//  Created by George Nachman on 1/24/20.
//

import AppKit

@objc(iTermSearchableComboTableView)
class SearchableComboTableView: NSTableView {
    static let enterNotificationName = Notification.Name("SearchableComboTableView.Enter")
    private(set) var handlingKeyDown = false
    public override func keyDown(with event: NSEvent) {
        if event.characters == "\r" {
            delegate?.tableViewSelectionDidChange?(Notification(name: Self.enterNotificationName))
        }
        handlingKeyDown = true
        super.keyDown(with: event)
        handlingKeyDown = false
    }
}

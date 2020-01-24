//
//  SearchableComboListSearchField.swift
//  SearchableComboListView
//
//  Created by George Nachman on 1/24/20.
//

import AppKit

@objc(iTermSearchableComboListSearchFieldDelegate)
protocol SearchableComboListSearchFieldDelegate: NSObjectProtocol {
    func searchFieldPerformKeyEquivalent(with event: NSEvent) -> Bool
}

@objc(iTermSearchableComboListSearchField)
class SearchableComboListSearchField: NSSearchField {
    @IBOutlet weak var searchableComboListSearchFieldDelegate: SearchableComboListSearchFieldDelegate?
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let theDelegate = searchableComboListSearchFieldDelegate {
            return theDelegate.searchFieldPerformKeyEquivalent(with: event)
        }
        return false
    }
}


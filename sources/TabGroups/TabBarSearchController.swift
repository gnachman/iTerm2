//
//  TabBarSearchController.swift
//  iTerm2SharedARC
//
//  The search field at the top of a vertical tab bar. It reports what's typed
//  and the keys that end a search; the window does the filtering (see
//  TabBarSearch).
//

import AppKit

@objc(iTermTabBarSearchController)
final class TabBarSearchController: NSObject, NSSearchFieldDelegate {
    /// Height of the band the field sits in. The window adds it to the tab
    /// bar's top inset.
    @objc static let bandHeight: CGFloat = 32

    @objc let searchField: NSSearchField
    /// The query changed.
    @objc var queryDidChange: ((String) -> Void)?
    /// Return: go to the first match.
    @objc var commit: (() -> Void)?
    /// Esc: stop searching.
    @objc var cancel: (() -> Void)?

    @objc var query: String {
        return searchField.stringValue
    }
    // Typing sends both the action and controlTextDidChange; the clear button
    // sends only the action. Report each value once.
    private var reported = ""

    override init() {
        searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        super.init()
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.sizeToFit()
        // The tab bar sets its frame whenever its own changes. A flexible
        // width would give the window a minimum width.
        searchField.autoresizingMask = []
        searchField.placeholderString = String(localized: "TabBarSearch.Placeholder",
                                               defaultValue: "Search Tabs",
                                               comment: "Placeholder in the search field at the top of a vertical tab bar. Typing in it hides tabs that don't match.")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldDidChange(_:))
    }

    /// Clears the field without reporting a change.
    @objc func clear() {
        searchField.stringValue = ""
        reported = ""
    }

    @objc private func searchFieldDidChange(_ sender: NSSearchField) {
        guard sender.stringValue != reported else {
            return
        }
        reported = sender.stringValue
        DLog("Tab bar search query is now \(reported)")
        queryDidChange?(reported)
    }

    func controlTextDidChange(_ obj: Notification) {
        searchFieldDidChange(searchField)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            commit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel?()
            return true
        default:
            return false
        }
    }
}

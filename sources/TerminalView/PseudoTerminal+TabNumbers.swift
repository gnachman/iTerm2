//
//  PseudoTerminal+TabNumbers.swift
//  iTerm2
//

import Foundation

// Tab numbers, and the modifier+digit shortcuts that select tabs by number,
// follow the order the tab bar shows. While the bar is sorted by status or
// directory that differs from the window's own order, which is unchanged.
@objc
extension PseudoTerminal {
    // The tabs in the order their numbers and modifier+digit shortcuts follow:
    // the order the bar shows while it is sorted, otherwise the window's.
    // This is what was last applied to the bar, not the order tabs would
    // sort in now: a directory change shows only when a poll notices it.
    @objc func tabsInShortcutOrder() -> [PTYTab] {
        let tabs = self.tabs() ?? []
        guard tabBarIsSorted(), let displayOrder = contentView?.tabBarControl?.displayOrder else {
            return tabs
        }
        return Self.tabs(tabs, inDisplayOrder: displayOrder.compactMap { $0.identifier as? PTYTab })
    }

    // Numbers every tab as -tabsInShortcutOrder lists them.
    @objc func assignTabObjectCounts() {
        for (position, tab) in tabsInShortcutOrder().enumerated() {
            tab.setObjectCount(Int32(position + 1))
        }
    }

    // Puts `tabs` in the order the bar draws them given `displayOrder`: the
    // tabs it lists, in its order, then any it doesn't, in their own order.
    // Listed tabs that are gone are skipped.
    static func tabs(_ tabs: [PTYTab], inDisplayOrder displayOrder: [PTYTab]) -> [PTYTab] {
        let current = Set(tabs.map(ObjectIdentifier.init))
        var listed = Set<ObjectIdentifier>()
        var result = [PTYTab]()
        for tab in displayOrder where current.contains(ObjectIdentifier(tab)) {
            if listed.insert(ObjectIdentifier(tab)).inserted {
                result.append(tab)
            }
        }
        result.append(contentsOf: tabs.filter { !listed.contains(ObjectIdentifier($0)) })
        return result
    }
}

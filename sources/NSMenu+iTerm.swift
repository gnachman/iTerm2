//
//  NSMenu+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/22.
//

import Foundation

extension NSMenu {
    @objc(itemWithSelector:)
    func itemWithSelector(_ selector: Selector) -> NSMenuItem? {
        return itemWithSelector(selector, maybeTag: nil)
    }

    @objc(itemWithSelector:tag:)
    func itemWithSelector(_ selector: Selector, tag: Int) -> NSMenuItem? {
        return itemWithSelector(selector, maybeTag: tag)
    }

    func itemWithSelector(_ selector: Selector, maybeTag tag: Int?) -> NSMenuItem? {
        for item in items {
            if item.action == selector {
                if tag == nil || tag == item.tag {
                    return item
                }
            }
            if let submenu = item.submenu,
               let item = submenu.itemWithSelector(selector, maybeTag: tag) {
                return item
            }
        }
        return nil
    }

    @objc
    func performActionForItemWithSelector(_ selector: Selector) -> Bool {
        guard let item = itemWithSelector(selector) else {
            return false
        }
        guard let containerMenu = item.menu else {
            return false
        }
        guard let i = containerMenu.items.firstIndex(of: item) else {
            return false
        }
        containerMenu.update()
        if !item.isEnabled {
            return false
        }
        containerMenu.performActionForItem(at: i)
        return true
    }

    @objc(it_deepCopy)
    func deepCopy() -> NSMenu {
        let copiedMenu = NSMenu(title: title)

        // Iterate through the menu items and clone them
        for menuItem in items {
            if let copiedItem = menuItem.deepCopy() {
                copiedMenu.addItem(copiedItem)
            }
        }

        // Since items with custom views don't get copied, remove trailing separators.
        while copiedMenu.items.last?.isSeparatorItem ?? false {
            copiedMenu.removeItem(at: copiedMenu.items.count - 1)
        }
        return copiedMenu
    }
}

extension NSMenuItem {
    func deepCopy() -> NSMenuItem? {
        if isSeparatorItem {
            return NSMenuItem.separator()
        }
        if view != nil {
            return nil
        }
        let copiedItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        copiedItem.target = target
        copiedItem.state = state
        copiedItem.tag = tag
        copiedItem.toolTip = toolTip
        copiedItem.isAlternate = isAlternate
        copiedItem.image = image

        // Clone submenu if it exists
        if let submenu = submenu {
            let copiedSubmenu = submenu.deepCopy()
            copiedItem.submenu = copiedSubmenu
        }

        // Copy other properties as needed (e.g., state, tag, etc.)

        return copiedItem
    }
}

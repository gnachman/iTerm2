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
}

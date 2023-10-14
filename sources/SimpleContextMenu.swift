//
//  SimpleContextMenu.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/13/23.
//

import Foundation

@objc(iTermSimpleContextMenu)
class SimpleContextMenu: NSObject, NSMenuDelegate {
    private struct Item {
        var title: String
        var action: () -> ()
    }
    private var items = [Item]()
    private let menu = NSMenu(title: "Context menu")
    private var cycle: SimpleContextMenu?

    @objc
    override init() {
        super.init()

        menu.delegate = self
        menu.allowsContextMenuPlugIns = false
    }

    @objc(addItemWithTitle:action:)
    func addItem(title: String, action: @escaping () -> ()) {
        items.append(Item(title: title, action: action))
    }

    @objc(showInView:forEvent:)
    func show(in view: NSView, for event: NSEvent) {
        if menu.items.isEmpty {
            for (i, item) in items.enumerated() {
                let menuItem =  NSMenuItem(title: item.title,
                                           action: #selector(action(_:)),
                                           keyEquivalent: "")
                menuItem.tag = i
                menuItem.target = self
                menu.addItem(menuItem)
            }
        }
        cycle = self
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func action(_ menuItem: NSMenuItem) {
        items[menuItem.tag].action()
    }

    func menuDidClose(_ menu: NSMenu) {
        cycle = nil
    }
}

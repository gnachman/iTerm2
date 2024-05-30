//
//  SimpleContextMenu.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/13/23.
//

import Foundation

@objc(iTermSimpleContextMenu)
class SimpleContextMenu: NSObject, NSMenuDelegate {
    private enum Item {
        case regular(RegularItem)
        case separator

        func action() {
            switch self {
            case .regular(let item):
                item.action()
            case .separator:
                break
            }
        }
    }
    private struct RegularItem {
        var title: String
        var action: () -> ()
    }
    private var items = [Item]()
    private let menu = NSMenu(title: "Context menu")
    private var cycle: SimpleContextMenu?
    var isEmpty: Bool { items.isEmpty }
    
    @objc
    override init() {
        super.init()

        menu.delegate = self
        menu.allowsContextMenuPlugIns = false
    }

    @objc(addItemWithTitle:action:)
    func addItem(title: String, action: @escaping () -> ()) {
        items.append(.regular(RegularItem(title: title, action: action)))
    }

    func addSeparator() {
        items.append(.separator)
    }
    @objc(showInView:forEvent:)
    func show(in view: NSView, for event: NSEvent) {
        if menu.items.isEmpty {
            for (i, item) in items.enumerated() {
                switch item {
                case .regular(let regularItem):
                    let menuItem =  NSMenuItem(title: regularItem.title,
                                               action: #selector(action(_:)),
                                               keyEquivalent: "")
                    menuItem.tag = i
                    menuItem.target = self
                    menu.addItem(menuItem)
                case .separator:
                    menu.addItem(NSMenuItem.separator())
                }
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

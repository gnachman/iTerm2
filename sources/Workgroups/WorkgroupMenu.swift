//
//  WorkgroupMenu.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import AppKit

// Owns the "Workgroups" submenu in the Shell menu. The menu item
// itself is defined in MainMenu.xib and reaches us through the
// app delegate's `workgroupsMenuItem` IBOutlet — install() wires
// the existing item to this delegate, which populates the submenu
// on demand from iTermWorkgroupModel. The xib also carries a
// trailing separator + "Exit Workgroup" item that we leave alone;
// dynamic workgroup entries are inserted above the separator.
@objc(iTermWorkgroupMenu)
final class WorkgroupMenu: NSObject, NSMenuDelegate {
    @objc static let instance = WorkgroupMenu()

    private weak var separator: NSMenuItem?

    @objc
    static func attach(to menuItem: NSMenuItem, separator: NSMenuItem) {
        instance.attach(to: menuItem, separator: separator)
    }

    private func attach(to menuItem: NSMenuItem, separator: NSMenuItem) {
        let submenu = menuItem.submenu ?? {
            let m = NSMenu(title: menuItem.title)
            menuItem.submenu = m
            return m
        }()
        submenu.delegate = self
        self.separator = separator
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Drop previous dynamic entries (everything above the
        // separator); leave the separator and "Exit Workgroup" item
        // from the xib in place.
        while let first = menu.items.first, first !== separator {
            menu.removeItem(first)
        }
        let workgroups = iTermWorkgroupModel.instance.workgroups
        separator?.isHidden = workgroups.isEmpty
        for (index, wg) in workgroups.enumerated() {
            let title = wg.name.isEmpty ? "Untitled" : wg.name
            let entry = NSMenuItem(
                title: title,
                action: #selector(enterWorkgroup(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.representedObject = wg.uniqueIdentifier
            menu.insertItem(entry, at: index)
        }
    }

    // Disabled when there's no current session, or when the current
    // session is already part of a workgroup (entering a second
    // workgroup on top would clobber the existing peerPort and leak
    // the spawned splits/tabs).
    func menu(_ menu: NSMenu,
              update item: NSMenuItem,
              at index: Int,
              shouldCancel: Bool) -> Bool {
        item.isEnabled = canEnter
        return false
    }

    // NSMenu also routes validation through the action target's
    // validateMenuItem:. Without this, items show as enabled
    // (greyed-out flag from menuNeedsUpdate gets overridden) when
    // there's no current terminal window.
    @objc
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return canEnter
    }

    private var canEnter: Bool {
        guard let session = currentSession() else { return false }
        return session.workgroupInstance == nil
    }

    // MARK: - Action

    @objc
    private func enterWorkgroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let session = currentSession() else {
            return
        }
        iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: id,
                                                on: session)
    }

    private func currentSession() -> PTYSession? {
        guard let term = iTermController.sharedInstance()?.currentTerminal else {
            return nil
        }
        return term.currentSession()
    }
}

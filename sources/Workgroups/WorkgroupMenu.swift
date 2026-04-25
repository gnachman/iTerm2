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
// on demand from iTermWorkgroupModel.
@objc(iTermWorkgroupMenu)
final class WorkgroupMenu: NSObject, NSMenuDelegate {
    @objc static let instance = WorkgroupMenu()

    @objc
    static func attach(to menuItem: NSMenuItem) {
        instance.attach(to: menuItem)
    }

    private func attach(to menuItem: NSMenuItem) {
        let submenu = menuItem.submenu ?? {
            let m = NSMenu(title: menuItem.title)
            menuItem.submenu = m
            return m
        }()
        submenu.delegate = self
        // Wipe any placeholder items the xib carried so menuNeedsUpdate
        // is the sole source of truth.
        submenu.removeAllItems()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let workgroups = iTermWorkgroupModel.instance.workgroups
        if workgroups.isEmpty {
            let placeholder = NSMenuItem(
                title: "No Workgroups Configured",
                action: nil,
                keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
            return
        }
        for wg in workgroups {
            let title = wg.name.isEmpty ? "Untitled" : wg.name
            let entry = menu.addItem(
                withTitle: title,
                action: #selector(enterWorkgroup(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.representedObject = wg.uniqueIdentifier
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

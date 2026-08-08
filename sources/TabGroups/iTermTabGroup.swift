//
//  iTermTabGroup.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/26.
//

import AppKit

// A tab group: a named, colored, contiguous run of tabs in one
// window's tab bar (Chrome/Firefox-style). The group's identity —
// its name and color — lives here. Which tabs belong to it is stored
// per-tab (PTYTab.tabGroupID), and the group's visible order is just
// the tab bar's own tab order; nothing here holds a tab list.
//
// The identifier is a UUID rather than anything window-scoped so a
// group can be dragged into another window (its definition moves to
// that window's registry) without colliding or losing identity.
@objc(iTermTabGroup)
final class iTermTabGroup: NSObject {
    @objc let uniqueIdentifier: String
    @objc var name: String
    @objc var color: NSColor

    @objc init(uniqueIdentifier: String, name: String, color: NSColor) {
        self.uniqueIdentifier = uniqueIdentifier
        self.name = name
        self.color = color
        super.init()
    }

    @objc convenience init(name: String, color: NSColor) {
        self.init(uniqueIdentifier: UUID().uuidString, name: name, color: color)
    }

    // MARK: - Arrangement

    private enum Key {
        static let identifier = "id"
        static let name = "name"
        static let color = "color"
    }

    // Serializable form for window arrangements. The color uses the
    // same dictionary encoding as KEY_TAB_COLOR (NSColor.dictionaryValue
    // / NSDictionary.colorValue) so it round-trips across color spaces.
    @objc var arrangement: [String: Any] {
        return [Key.identifier: uniqueIdentifier,
                Key.name: name,
                Key.color: color.dictionaryValue]
    }

    // Fails only when the identifier or name is missing/mistyped; a
    // missing or unreadable color falls back to a neutral gray so a
    // partially-written arrangement still yields a usable group rather
    // than dropping it.
    @objc init?(arrangement: [String: Any]) {
        guard let identifier = arrangement[Key.identifier] as? String,
              let name = arrangement[Key.name] as? String else {
            return nil
        }
        self.uniqueIdentifier = identifier
        self.name = name
        if let colorDict = arrangement[Key.color] as? [AnyHashable: Any],
           let color = (colorDict as NSDictionary).colorValue() {
            self.color = color
        } else {
            self.color = .gray
        }
        super.init()
    }
}

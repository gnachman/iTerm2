//
//  iTermTabGroup.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/26.
//

import AppKit

// A tab group's definition: its identity, name, and color. Identity is a UUID
// (not window-scoped) so a group keeps its identity when dragged into another
// window. The definition is not stored centrally: it rides each member tab
// (PTYTab.tabGroupID / tabGroupName / tabGroupColor). The window controller
// builds one of these on demand from a member tab to answer the tab bar's
// PSMTabGroupDataSource queries. Which tabs belong to the group, and their run
// order, come from the tabs themselves; nothing here holds a tab list.
@objc(iTermTabGroup)
final class iTermTabGroup: NSObject, PSMTabGroup {
    @objc let uniqueIdentifier: String
    @objc let name: String
    @objc let color: NSColor

    @objc init(uniqueIdentifier: String, name: String, color: NSColor) {
        self.uniqueIdentifier = uniqueIdentifier
        self.name = name
        self.color = color
        super.init()
    }
}

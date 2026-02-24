import Cocoa

private let iTermTabGroupsArrangementKey = "Tab Groups"

extension PseudoTerminal {

    @objc var tabGroups: [iTermTabGroup] {
        return mutableTabGroups as! [iTermTabGroup]
    }

    private var mutableTabGroups: NSMutableArray {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.tabGroups) as? NSMutableArray {
            return existing
        }
        let array = NSMutableArray()
        objc_setAssociatedObject(self, &AssociatedKeys.tabGroups, array, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return array
    }

    @objc @discardableResult
    func createTabGroup(name: String, color: NSColor, forTab tab: PTYTab) -> iTermTabGroup {
        let group = iTermTabGroup(name: name, color: color)
        mutableTabGroups.add(group)
        addTab(tab, toGroup: group)
        return group
    }

    @objc func addTab(_ tab: PTYTab, toGroup group: iTermTabGroup) {
        let tabID = Int(tab.uniqueId)
        guard !group.memberTabIDs.contains(tabID) else { return }
        group.memberTabIDs.append(tabID)
        enforceContiguity(of: group)
        updateTabGroupDecorations()
    }

    @objc func removeTab(_ tab: PTYTab, fromGroup group: iTermTabGroup) {
        let tabID = Int(tab.uniqueId)
        group.memberTabIDs.removeAll { $0 == tabID }
        if group.memberTabIDs.isEmpty {
            deleteTabGroup(group)
        } else {
            updateTabGroupDecorations()
        }
    }

    @objc func deleteTabGroup(_ group: iTermTabGroup) {
        if group.isCollapsed {
            toggleCollapseGroup(group)
        }
        group.memberTabIDs.removeAll()
        mutableTabGroups.remove(group)
        updateTabGroupDecorations()
    }

    @objc func toggleCollapseGroup(_ group: iTermTabGroup) {
        if group.isCollapsed {
            expandGroup(group)
        } else {
            collapseGroup(group)
        }
    }

    @objc func tabGroupForTab(_ tab: PTYTab) -> iTermTabGroup? {
        let tabID = Int(tab.uniqueId)
        return tabGroups.first { $0.memberTabIDs.contains(tabID) }
    }

    @objc func tabWillBeRemoved(_ tab: PTYTab) {
        guard let group = tabGroupForTab(tab) else { return }
        if group.isCollapsed {
            group.stashedTabViewItems.removeAll { $0.identifier as? PTYTab === tab }
        }
        removeTab(tab, fromGroup: group)
    }

    @objc func updateTabGroupDecorations() {
        let tabBar = contentView.tabBarControl
        let allCells = tabBar?.cells

        for cell in allCells ?? [] {
            guard let psmCell = cell as? PSMTabBarCell,
                  let tabViewItem = psmCell.representedObject as? NSTabViewItem,
                  let tab = tabViewItem.identifier as? PTYTab else {
                continue
            }
            if let group = tabGroupForTab(tab) {
                let isRepresentative = group.memberTabIDs.first == Int(tab.uniqueId)
                psmCell.isGroupHeader = isRepresentative
                psmCell.isGroupMember = !isRepresentative
                psmCell.isGroupCollapsed = group.isCollapsed
                psmCell.groupName = group.name
                psmCell.groupColor = group.color
                psmCell.groupMemberCount = group.memberTabIDs.count
            } else {
                psmCell.isGroupHeader = false
                psmCell.isGroupMember = false
                psmCell.isGroupCollapsed = false
                psmCell.groupName = nil
                psmCell.groupColor = nil
                psmCell.groupMemberCount = 0
            }
        }
        tabBar?.setNeedsDisplay(true)
    }

    @objc func encodeTabGroupsForArrangement() -> [[String: Any]] {
        return tabGroups.map { $0.toDictionary() }
    }

    @objc func restoreTabGroupsFromArrangement(_ arrangement: [[String: Any]]) {
        let allTabs = tabs()
        for dict in arrangement {
            guard let group = iTermTabGroup(dictionary: dict) else { continue }
            let validIDs = group.memberTabIDs.filter { id in
                allTabs.contains { Int($0.uniqueId) == id }
            }
            guard !validIDs.isEmpty else { continue }
            group.memberTabIDs = validIDs
            mutableTabGroups.add(group)
        }
        updateTabGroupDecorations()
    }

    @objc func showCreateTabGroupSheet(forTab tab: PTYTab) {
        let vc = iTermCreateTabGroupViewController()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
                            styleMask: [.titled, .docModalWindow],
                            backing: .buffered,
                            defer: false)
        panel.contentViewController = vc
        vc.completion = { [weak self, weak panel] result in
            guard let self, let panel else { return }
            self.window?.endSheet(panel)
            guard let (name, color) = result else { return }
            self.createTabGroup(name: name, color: color, forTab: tab)
        }
        window?.beginSheet(panel) { _ in }
    }

    @objc func addTabToNewGroup(_ sender: Any?) {
        guard let tab = tabFromSender(sender) else { return }
        showCreateTabGroupSheet(forTab: tab)
    }

    @objc func moveTabToGroup(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let dict = item.representedObject as? [String: AnyObject],
              let tabViewItem = dict["tabViewItem"] as? NSTabViewItem,
              let tab = tabViewItem.identifier as? PTYTab,
              let group = dict["group"] as? iTermTabGroup else { return }
        if let currentGroup = tabGroupForTab(tab), currentGroup === group { return }
        if let currentGroup = tabGroupForTab(tab) {
            removeTab(tab, fromGroup: currentGroup)
        }
        addTab(tab, toGroup: group)
    }

    @objc func removeTabFromGroup(_ sender: Any?) {
        guard let tab = tabFromSender(sender),
              let group = tabGroupForTab(tab) else { return }
        removeTab(tab, fromGroup: group)
    }

    private func tabFromSender(_ sender: Any?) -> PTYTab? {
        guard let item = sender as? NSMenuItem,
              let tabViewItem = item.representedObject as? NSTabViewItem else { return nil }
        return tabViewItem.identifier as? PTYTab
    }

    private func collapseGroup(_ group: iTermTabGroup) {
        let allTabs = tabs()
        let memberTabs = group.memberTabIDs.compactMap { id in allTabs.first { Int($0.uniqueId) == id } }
        guard let representative = memberTabs.first else { return }

        if let selected = currentTab(),
           group.memberTabIDs.contains(Int(selected.uniqueId)),
           selected !== representative {
            contentView.tabView.selectTabViewItem(representative.tabViewItem)
        }

        for tab in memberTabs.dropFirst() {
            guard let item = tab.tabViewItem else { continue }
            contentView.tabView.removeTabViewItem(item)
            group.stashedTabViewItems.append(item)
        }
        group.isCollapsed = true
        updateTabGroupDecorations()
    }

    private func expandGroup(_ group: iTermTabGroup) {
        guard let representativeID = group.memberTabIDs.first,
              let representativeTab = tabs().first(where: { Int($0.uniqueId) == representativeID }),
              let representativeItem = representativeTab.tabViewItem else { return }

        let tabView = contentView.tabView
        let baseIndex = tabView.indexOfTabViewItem(representativeItem)
        guard baseIndex != NSNotFound else { return }

        for (offset, item) in group.stashedTabViewItems.enumerated() {
            let targetIndex = baseIndex + 1 + offset
            let safeIndex = min(targetIndex, tabView.numberOfTabViewItems)
            tabView.insertTabViewItem(item, at: safeIndex)
        }
        group.stashedTabViewItems.removeAll()
        group.isCollapsed = false
        updateTabGroupDecorations()
    }

    private func enforceContiguity(of group: iTermTabGroup) {
        guard group.memberTabIDs.count > 1 else { return }
        let allTabs = tabs()
        let memberTabs = group.memberTabIDs.compactMap { id in allTabs.first { Int($0.uniqueId) == id } }
        guard let representativeItem = memberTabs.first?.tabViewItem else { return }

        let tabView = contentView.tabView
        let anchorIndex = tabView.indexOfTabViewItem(representativeItem)
        guard anchorIndex != NSNotFound else { return }

        for (i, tab) in memberTabs.dropFirst().enumerated() {
            guard let item = tab.tabViewItem else { continue }
            let currentIndex = tabView.indexOfTabViewItem(item)
            let targetIndex = anchorIndex + 1 + i
            if currentIndex != targetIndex {
                tabView.removeTabViewItem(item)
                let safeTarget = min(targetIndex, tabView.numberOfTabViewItems)
                tabView.insertTabViewItem(item, at: safeTarget)
            }
        }
    }
}

private enum AssociatedKeys {
    static var tabGroups = "iTermTabGroupsKey"
}

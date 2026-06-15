import Cocoa

private let iTermTabGroupsArrangementKey = "Tab Groups"

extension PseudoTerminal {

    @objc var tabGroups: [iTermTabGroup] {
        return mutableTabGroups as! [iTermTabGroup]
    }

    @objc @discardableResult
    func createTabGroup(name: String, color: NSColor, forTab tab: PTYTab) -> iTermTabGroup {
        let group = iTermTabGroup(name: name, color: color)
        mutableTabGroups.add(group)
        insertHeaderItem(for: group, adjacentTo: tab)
        addTab(tab, toGroup: group)
        moveGroupAfterLastGroup(group)
        autoManageGroupCollapseForTab(tab)
        if let tabViewItem = tab.tabViewItem {
            contentView.tabView.selectTabViewItem(tabViewItem)
        }
        return group
    }

    private func insertHeaderItem(for group: iTermTabGroup, adjacentTo tab: PTYTab) {
        guard let tabItem = tab.tabViewItem else { return }
        let tabView = contentView.tabView
        let tabIndex = tabView.indexOfTabViewItem(tabItem)
        if tabIndex != NSNotFound {
            tabView.insertTabViewItem(group.headerTabViewItem, at: tabIndex)
        } else {
            tabView.insertTabViewItem(group.headerTabViewItem, at: tabView.numberOfTabViewItems)
        }
    }

    private func moveGroupAfterLastGroup(_ group: iTermTabGroup) {
        let tabView = contentView.tabView
        let allTabs = tabs() ?? []

        // Find the index just after the last tab that belongs to any other group.
        var insertionIndex = 0
        for i in 0..<tabView.numberOfTabViewItems {
            let item = tabView.tabViewItem(at: i)
            if item === group.headerTabViewItem { continue }
            if let tab = item.identifier as? PTYTab, tab.isPinned {
                insertionIndex = i + 1
                continue
            }
            let belongsToOtherGroup = tabGroups.contains { g in
                g !== group && (g.headerTabViewItem === item || g.memberTabIDs.contains { id in
                    allTabs.first { Int($0.uniqueId) == id }?.tabViewItem === item
                })
            }
            if belongsToOtherGroup {
                insertionIndex = i + 1
            }
        }

        let memberTabs = group.memberTabIDs.compactMap { id in allTabs.first { Int($0.uniqueId) == id } }
        var itemsToMove: [NSTabViewItem] = [group.headerTabViewItem]
        itemsToMove += memberTabs.compactMap { $0.tabViewItem }

        for (offset, item) in itemsToMove.enumerated() {
            let currentIndex = tabView.indexOfTabViewItem(item)
            guard currentIndex != NSNotFound else { continue }
            tabView.removeTabViewItem(item)
            let target = min(insertionIndex + offset, tabView.numberOfTabViewItems)
            tabView.insertTabViewItem(item, at: target)
        }
    }

    @objc func addTab(_ tab: PTYTab, toGroup group: iTermTabGroup) {
        let tabID = Int(tab.uniqueId)
        guard !group.memberTabIDs.contains(tabID) else { return }
        group.memberTabIDs.append(tabID)
        if group.isCollapsed {
            expandGroupSilently(group)
        }
        enforceContiguity(of: group)
        updateTabGroupDecorations()
    }

    @objc func removeTab(_ tab: PTYTab, fromGroup group: iTermTabGroup) {
        let tabID = Int(tab.uniqueId)
        group.memberTabIDs.removeAll { $0 == tabID }
        if group.isCollapsed {
            group.stashedTabViewItems.removeAll { $0.identifier as? PTYTab === tab }
        }
        if group.memberTabIDs.isEmpty {
            deleteTabGroup(group)
        } else {
            updateTabGroupDecorations()
        }
    }

    @objc func deleteTabGroup(_ group: iTermTabGroup) {
        if group.isCollapsed {
            unstashItems(for: group)
        }
        contentView.tabView.removeTabViewItem(group.headerTabViewItem)
        group.headerTabViewItem.identifier = nil
        group.memberTabIDs.removeAll()
        mutableTabGroups.remove(group)
        updateTabGroupDecorations()
    }

    @objc func ungroupTabs(_ sender: Any?) {
        guard let group = tabGroupFromSender(sender) else { return }
        deleteTabGroup(group)
    }

    @objc func newTabInGroup(_ sender: Any?) {
        guard let group = tabGroupFromSender(sender) else { return }
        newTab(inGroup: group)
    }

    func newTab(inGroup group: iTermTabGroup) {
        let profile = currentSession()?.profile ?? ProfileModel.sharedInstance().defaultProfile()
        asyncCreateTab(withProfile: profile,
                       withCommand: nil,
                       environment: nil,
                       tabIndex: nil,
                       didMakeSession: nil) { [weak self] session, ok in
            guard let self, ok, let tab = session?.delegate as? PTYTab else { return }
            self.addTab(tab, toGroup: group)
        }
    }

    @objc func closeTabGroup(_ sender: Any?) {
        guard let group = tabGroupFromSender(sender) else { return }
        closeGroup(group)
    }

    @objc func closeGroup(_ group: iTermTabGroup) {
        if group.isCollapsed {
            expandGroupSilently(group)
        }
        let allTabs = tabs() ?? []
        let members = group.memberTabIDs.compactMap { id in allTabs.first { Int($0.uniqueId) == id } }
        for tab in members {
            close(tab)
        }
    }

    @objc func toggleCollapseGroupFromMenu(_ sender: Any?) {
        guard let group = tabGroupFromSender(sender) else { return }
        toggleCollapseGroup(group)
    }

    @objc func showRenameGroupSheet(_ sender: Any?) {
        guard let group = tabGroupFromSender(sender) else { return }
        showManageGroupPopover(for: group)
    }

    // Chrome-style transient popover anchored to the group header chip. Name and
    // colour edits apply live; the action rows reuse the same group operations as
    // the context menu and close the popover.
    @objc func showManageGroupPopover(for group: iTermTabGroup) {
        let vc = iTermCreateTabGroupViewController(initialColor: group.color,
                                                   initialName: group.name,
                                                   manageMode: true)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = vc
        // Match the window's light/dark theme so the popover never clashes with
        // the active tab style (minimal, compact, dark, light, …).
        popover.appearance = sheetAppearance
        weak let weakPopover = popover

        vc.onNameChange = { [weak self] name in
            guard let self else { return }
            group.name = name
            group.headerTabViewItem.label = name
            self.updateTabGroupDecorations()
        }
        vc.onColorChange = { [weak self] color in
            guard let self else { return }
            group.color = color
            self.updateTabGroupDecorations()
        }
        vc.onNewTabInGroup = { [weak self] in
            weakPopover?.close()
            self?.newTab(inGroup: group)
        }
        vc.onUngroup = { [weak self] in
            weakPopover?.close()
            self?.deleteTabGroup(group)
        }
        vc.onCloseGroup = { [weak self] in
            weakPopover?.close()
            self?.closeGroup(group)
        }

        let tabBar = contentView.tabBarControl
        var anchorRect = tabBar.frameOfCell(for: group.headerTabViewItem)
        if anchorRect.isEmpty {
            anchorRect = tabBar.bounds
        }
        popover.show(relativeTo: anchorRect, of: tabBar, preferredEdge: .maxY)
    }

    @objc func reconcileGroupsAfterReorder() {
        guard !tabGroups.isEmpty else { return }
        let tabView = contentView.tabView
        for group in tabGroups where !group.isCollapsed {
            let headerIndex = tabView.indexOfTabViewItem(group.headerTabViewItem)
            guard headerIndex != NSNotFound, !group.memberTabIDs.isEmpty else { continue }

            // Walk the span after the header. Members stay; a single foreign tab
            // dropped between members joins (Chrome-style drag-in); members that no
            // longer appear in the span were dragged out and leave the group.
            var remaining = Set(group.memberTabIDs)
            var newMemberIDs: [Int] = []
            var pendingJoiner: Int?
            var index = headerIndex + 1
            while index < tabView.numberOfTabViewItems, !remaining.isEmpty {
                guard let tab = tabView.tabViewItem(at: index).identifier as? PTYTab else {
                    break
                }
                let tabID = Int(tab.uniqueId)
                let belongsToOtherGroup = tabGroups.contains { $0 !== group && $0.memberTabIDs.contains(tabID) }
                if remaining.contains(tabID) {
                    if let joiner = pendingJoiner {
                        newMemberIDs.append(joiner)
                        pendingJoiner = nil
                    }
                    newMemberIDs.append(tabID)
                    remaining.remove(tabID)
                } else if belongsToOtherGroup || pendingJoiner != nil {
                    break
                } else {
                    pendingJoiner = tabID
                }
                index += 1
            }

            if newMemberIDs.isEmpty {
                deleteTabGroup(group)
            } else if newMemberIDs != group.memberTabIDs {
                group.memberTabIDs = newMemberIDs
            }
        }
        updateTabGroupDecorations()
    }

    private func tabGroupFromSender(_ sender: Any?) -> iTermTabGroup? {
        guard let item = sender as? NSMenuItem,
              let group = item.representedObject as? iTermTabGroup else { return nil }
        return group
    }

    private func unstashItems(for group: iTermTabGroup) {
        let tabView = contentView.tabView
        let headerIndex = tabView.indexOfTabViewItem(group.headerTabViewItem)
        guard headerIndex != NSNotFound else { return }

        contentView.tabBarControl.markNextInsertions(asAnimated:group.stashedTabViewItems.count)
        for (offset, item) in group.stashedTabViewItems.enumerated() {
            let targetIndex = headerIndex + 1 + offset
            let safeIndex = min(targetIndex, tabView.numberOfTabViewItems)
            tabView.insertTabViewItem(item, at: safeIndex)
        }
        group.stashedTabViewItems.removeAll()
        group.isCollapsed = false
    }

    @objc func autoManageGroupCollapseForTab(_ tab: PTYTab) {
        guard !groupCollapseManaging else { return }
        groupCollapseManaging = true
        defer { groupCollapseManaging = false }
        let activeGroup = tabGroupForTab(tab)
        for group in tabGroups {
            if group === activeGroup {
                if group.isCollapsed {
                    expandGroup(group)
                }
            } else if !group.isCollapsed {
                collapseGroup(group)
            }
        }
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
        } else if currentTab() === tab {
            // Pre-select another group member before NSTabView auto-selects outside the group,
            // which would trigger autoManageGroupCollapseForTab and collapse the whole group.
            let remainingIDs = group.memberTabIDs.filter { $0 != Int(tab.uniqueId) }
            if let next = (tabs() ?? []).first(where: { remainingIDs.contains(Int($0.uniqueId)) }),
               let item = next.tabViewItem {
                contentView.tabView.selectTabViewItem(item)
            }
        }
        removeTab(tab, fromGroup: group)
    }

    @objc func updateTabGroupDecorations() {
        let tabBar = contentView.tabBarControl
        let allCells = tabBar.cells()
        let selectedTabID: Int? = currentTab().map { Int($0.uniqueId) }

        for cell in allCells {
            guard let psmCell = cell as? PSMTabBarCell,
                  let tabViewItem = psmCell.representedObject as? NSTabViewItem else {
                continue
            }
            if let group = tabViewItem.identifier as? iTermTabGroup {
                psmCell.isGroupHeader = true
                psmCell.isGroupMember = false
                psmCell.isGroupCollapsed = group.isCollapsed
                psmCell.isGroupActive = selectedTabID.map { group.memberTabIDs.contains($0) } ?? false
                psmCell.groupName = group.name
                psmCell.groupColor = group.color
                psmCell.groupMemberCount = group.memberTabIDs.count
            } else if let tab = tabViewItem.identifier as? PTYTab,
                      let group = tabGroupForTab(tab) {
                psmCell.isGroupHeader = false
                psmCell.isGroupMember = true
                psmCell.isGroupCollapsed = group.isCollapsed
                psmCell.isGroupActive = false
                psmCell.groupName = group.name
                psmCell.groupColor = group.color
                psmCell.groupMemberCount = group.memberTabIDs.count
            } else {
                psmCell.isGroupHeader = false
                psmCell.isGroupMember = false
                psmCell.isGroupCollapsed = false
                psmCell.isGroupActive = false
                psmCell.groupName = nil
                psmCell.groupColor = nil
                psmCell.groupMemberCount = 0
            }
        }
        tabBar.needsDisplay = true
    }

    @objc func encodeTabGroupsForArrangement() -> [[String: Any]] {
        let allTabs = tabs() ?? []
        return tabGroups.map { $0.toDictionary(allTabs: allTabs) }
    }

    @objc func restoreTabGroupsFromArrangement(_ arrangement: [[String: Any]]) {
        let allTabs = tabs() ?? []
        for dict in arrangement {
            guard let group = iTermTabGroup(dictionary: dict) else { continue }
            let resolvedIDs = group.memberTabIDs.compactMap { index -> Int? in
                guard index >= 0, index < allTabs.count else { return nil }
                return Int(allTabs[index].uniqueId)
            }
            guard !resolvedIDs.isEmpty else { continue }
            group.memberTabIDs = resolvedIDs

            if let firstTab = allTabs.first(where: { resolvedIDs.first == Int($0.uniqueId) }),
               let firstItem = firstTab.tabViewItem {
                let idx = contentView.tabView.indexOfTabViewItem(firstItem)
                if idx != NSNotFound {
                    contentView.tabView.insertTabViewItem(group.headerTabViewItem, at: idx)
                }
            }

            let shouldCollapse = group.isCollapsed
            group.isCollapsed = false
            mutableTabGroups.add(group)
            if shouldCollapse {
                collapseGroupSilently(group)
            }
        }
        updateTabGroupDecorations()
    }

    @objc func collapseGroupSilently(_ group: iTermTabGroup) {
        let memberTabs = group.memberTabIDs.compactMap { id in
            (tabs() ?? []).first { Int($0.uniqueId) == id }
        }
        for tab in memberTabs {
            guard let item = tab.tabViewItem else { continue }
            contentView.tabView.removeTabViewItem(item)
            group.stashedTabViewItems.append(item)
        }
        group.isCollapsed = true
    }

    @objc func expandGroupSilently(_ group: iTermTabGroup) {
        let tabView = contentView.tabView
        let headerIndex = tabView.indexOfTabViewItem(group.headerTabViewItem)
        guard headerIndex != NSNotFound else { return }
        contentView.tabBarControl.markNextInsertions(asAnimated:group.stashedTabViewItems.count)
        for (offset, item) in group.stashedTabViewItems.enumerated() {
            let targetIndex = headerIndex + 1 + offset
            let safeIndex = min(targetIndex, tabView.numberOfTabViewItems)
            tabView.insertTabViewItem(item, at: safeIndex)
        }
        group.stashedTabViewItems.removeAll()
        group.isCollapsed = false
    }

    @objc func showCreateTabGroupSheet(forTab tab: PTYTab) {
        showCreateTabGroupSheet(forTab: tab, completion: nil)
    }

    @objc(showCreateTabGroupSheetForTab:completion:) func showCreateTabGroupSheet(forTab tab: PTYTab, completion: ((iTermTabGroup) -> Void)?) {
        let vc = iTermCreateTabGroupViewController()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
                            styleMask: [.titled, .docModalWindow],
                            backing: .buffered,
                            defer: false)
        panel.appearance = sheetAppearance
        panel.contentViewController = vc
        vc.completion = { [weak self, weak panel] result in
            guard let self, let panel else { return }
            self.window?.endSheet(panel)
            guard let (name, color) = result else { return }
            let group = self.createTabGroup(name: name, color: color, forTab: tab)
            completion?(group)
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
        autoManageGroupCollapseForTab(tab)
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
        let allTabs = tabs() ?? []
        let memberTabs = group.memberTabIDs.compactMap { id in allTabs.first { Int($0.uniqueId) == id } }
        guard !memberTabs.isEmpty else { return }

        let wasManaging = groupCollapseManaging
        groupCollapseManaging = true
        defer { groupCollapseManaging = wasManaging }

        if let selected = currentTab(), group.memberTabIDs.contains(Int(selected.uniqueId)) {
            selectNearestTabOutside(group: group)
        }

        group.isCollapsed = true
        let itemsToStash = memberTabs.compactMap { $0.tabViewItem }
        updateTabGroupDecorations()

        contentView.tabBarControl.beginCollapseAnimation(for: itemsToStash) { [weak self] in
            guard let self else { return }
            for item in itemsToStash {
                self.contentView.tabView.removeTabViewItem(item)
                group.stashedTabViewItems.append(item)
            }
            self.contentView.tabBarControl.update(true)
        }
    }

    private func selectNearestTabOutside(group: iTermTabGroup) {
        let tabView = contentView.tabView
        let headerIndex = tabView.indexOfTabViewItem(group.headerTabViewItem)
        guard headerIndex != NSNotFound else { return }
        let groupSize = group.memberTabIDs.count
        let afterGroupIndex = headerIndex + groupSize + 1

        for i in afterGroupIndex..<tabView.numberOfTabViewItems {
            let item = tabView.tabViewItem(at: i)
            if item.identifier is PTYTab {
                tabView.selectTabViewItem(item)
                return
            }
        }
        for i in stride(from: headerIndex - 1, through: 0, by: -1) {
            let item = tabView.tabViewItem(at: i)
            if item.identifier is PTYTab {
                tabView.selectTabViewItem(item)
                return
            }
        }
    }

    private func expandGroup(_ group: iTermTabGroup) {
        // If a collapse animation is in-flight for this group, finish it synchronously
        // so stashedTabViewItems is populated before we try to expand.
        contentView.tabBarControl.cancelCollapseAnimation()

        let tabView = contentView.tabView
        let headerIndex = tabView.indexOfTabViewItem(group.headerTabViewItem)
        guard headerIndex != NSNotFound else { return }

        group.isCollapsed = false
        let itemsToInsert = group.stashedTabViewItems
        group.stashedTabViewItems.removeAll()
        contentView.tabBarControl.markNextInsertions(asAnimated:itemsToInsert.count)
        for (offset, item) in itemsToInsert.enumerated() {
            let targetIndex = headerIndex + 1 + offset
            let safeIndex = min(targetIndex, tabView.numberOfTabViewItems)
            tabView.insertTabViewItem(item, at: safeIndex)
        }
        contentView.tabBarControl.update(true)
        updateTabGroupDecorations()
    }

    @objc func enforceContiguityOfAllGroups() {
        for group in tabGroups where !group.isCollapsed {
            enforceContiguity(of: group)
        }
        updateTabGroupDecorations()
    }

    private func enforceContiguity(of group: iTermTabGroup) {
        guard !group.memberTabIDs.isEmpty else { return }
        let allTabs = tabs() ?? []
        let memberTabs = group.memberTabIDs.compactMap { id in allTabs.first { Int($0.uniqueId) == id } }

        let tabView = contentView.tabView
        let headerIndex = tabView.indexOfTabViewItem(group.headerTabViewItem)
        guard headerIndex != NSNotFound else { return }

        for (i, tab) in memberTabs.enumerated() {
            guard let item = tab.tabViewItem else { continue }
            let currentIndex = tabView.indexOfTabViewItem(item)
            let targetIndex = headerIndex + 1 + i
            if currentIndex != targetIndex {
                tabView.removeTabViewItem(item)
                let safeTarget = min(targetIndex, tabView.numberOfTabViewItems)
                tabView.insertTabViewItem(item, at: safeTarget)
            }
        }
    }
}

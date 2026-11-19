//
//  TabBarSearch.swift
//  iTerm2SharedARC
//
//  Searching a vertical tab bar hides the tabs that don't match. It works by
//  changing what the window tells the tab bar about groups, not the groups
//  themselves, so clearing the search puts everything back:
//
//  - A tab that doesn't match is hidden, as a collapsed group's tabs are.
//  - A group with a match is shown expanded, so its matches show.
//  - A group without a match goes away. Its tabs, all hidden, leave it.
//  - A group's name, or its parent group's, matching makes all its tabs match.
//  - Only matches are shown, the selected tab included. Going to a hidden tab
//    other than by search navigation, acting on a hidden current tab, or a
//    tab arriving (a new one, or one dropped from another window), ends the
//    search instead. A background tab arriving while the user types a query
//    leaves it alone.
//
//  Selecting a tab in a collapsed group during a search doesn't expand the
//  group, so browsing matches leaves groups as they were. When the search
//  ends, the selected tab's group
//  expands, since the selected tab is never in a collapsed group. Everything
//  else about groups is restored. A group's collapsed state can't change
//  during a search: clicking its chip beeps, and its menu leaves out Expand
//  and Collapse.
//

import Foundation

/// What the window knows about one tab, in tab order.
@objc(iTermTabBarSearchTab)
final class TabBarSearchTab: NSObject {
    /// The text the tab shows: its title and any rich content lines.
    let texts: [String]
    /// The names of its group and its group's parent. A match shows the
    /// group's tabs.
    let groupNames: [String]
    let groupID: String?
    let parentGroupID: String?
    /// Whether the tab is hidden by a collapsed group.
    let hidden: Bool
    /// Whether its group's parent is collapsed.
    let parentCollapsed: Bool

    @objc convenience init(texts: [String],
                           groupID: String?,
                           parentGroupID: String?,
                           hidden: Bool,
                           parentCollapsed: Bool) {
        self.init(texts: texts,
                  groupNames: [],
                  groupID: groupID,
                  parentGroupID: parentGroupID,
                  hidden: hidden,
                  parentCollapsed: parentCollapsed)
    }

    @objc init(texts: [String],
               groupNames: [String],
               groupID: String?,
               parentGroupID: String?,
               hidden: Bool,
               parentCollapsed: Bool) {
        self.texts = texts
        self.groupNames = groupNames
        self.groupID = groupID
        self.parentGroupID = parentGroupID
        self.hidden = hidden
        self.parentCollapsed = parentCollapsed
    }
}

/// What to tell the tab bar, parallel to the tabs.
@objc(iTermTabBarSearchResult)
final class TabBarSearchResult: NSObject {
    /// A group identifier or NSNull for each tab.
    @objc let groupIDs: [Any]
    /// A parent group identifier or NSNull for each tab.
    @objc let parentGroupIDs: [Any]
    @objc let hidden: [Bool]
    @objc let parentCollapsed: [Bool]
    /// Whether each tab matches. All do when not searching.
    @objc let matches: [Bool]
    @objc let isSearching: Bool

    init(groupIDs: [Any],
         parentGroupIDs: [Any],
         hidden: [Bool],
         parentCollapsed: [Bool],
         matches: [Bool],
         isSearching: Bool) {
        self.groupIDs = groupIDs
        self.parentGroupIDs = parentGroupIDs
        self.hidden = hidden
        self.parentCollapsed = parentCollapsed
        self.matches = matches
        self.isSearching = isSearching
    }

    /// The index of the first tab that matches, or NSNotFound.
    @objc var firstMatchIndex: Int {
        return matches.firstIndex(of: true) ?? NSNotFound
    }

    /// For moving tabs while searching: a key per tab that is equal for tabs
    /// the bar shows in the same group, with the same pinned state.
    @objc(groupKeysWithPinned:)
    func groupKeys(pinned: [Bool]) -> [String] {
        return groupIDs.indices.map { i in
            let group = groupIDs[i] as? String ?? ""
            let parent = parentGroupIDs[i] as? String ?? ""
            let isPinned = i < pinned.count && pinned[i]
            return "\(isPinned ? "pinned" : "unpinned")\u{1}\(parent)\u{1}\(group)"
        }
    }
}

@objc(iTermTabBarSearch)
final class TabBarSearch: NSObject {
    /// The text a tab is searched by, which is what it draws, so every match
    /// can be highlighted: its rich content lines when it has them, otherwise
    /// its label (title and subtitle). A pinned tab draws only its label.
    @objc static func searchedTexts(label: String?, richLines: [String], pinned: Bool) -> [String] {
        if !pinned && !richLines.isEmpty {
            return richLines
        }
        return label.map { [$0] } ?? []
    }

    /// Whether any of the texts contains the query, ignoring case and accents.
    @objc static func matches(query: String, texts: [String]) -> Bool {
        return texts.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private static func objectOrNull(_ string: String?) -> Any {
        if let string {
            return string
        }
        return NSNull()
    }

    /// Moving a tab while some are hidden: the index of the tab it trades
    /// places with, which is the nearest visible tab in that direction with
    /// the same group key, or NSNotFound. Others are skipped, so an ungrouped
    /// tab passes over a group, and a group's direct member passes over a
    /// sub-group. A group's tabs are contiguous, so its tabs stay in it. A
    /// move never changes a tab's group. This finds no neighbor at the ends;
    /// moveOrder wraps around there.
    @objc static func swapIndex(groupKeys: [String],
                                visible: [Bool],
                                selectedIndex: Int,
                                offset: Int) -> Int {
        guard groupKeys.indices.contains(selectedIndex),
              visible.indices.contains(selectedIndex),
              visible[selectedIndex],
              offset != 0 else {
            return NSNotFound
        }
        let step = offset > 0 ? 1 : -1
        var i = selectedIndex + step
        while groupKeys.indices.contains(i) && visible.indices.contains(i) {
            if visible[i] && groupKeys[i] == groupKeys[selectedIndex] {
                return i
            }
            i += step
        }
        return NSNotFound
    }

    /// Move Tab Left or Right while some tabs are hidden: the new tab order,
    /// as indices into the old one, or nil to stay put. One step, by what
    /// the bar shows:
    /// - An ungrouped tab moves past the next shown group as a whole, and a
    ///   group's direct tab past the next shown sub-group of that group,
    ///   hidden members included.
    /// - Otherwise the tab trades places with the nearest shown tab with the
    ///   same group key (swapIndex).
    /// - At the end, it wraps around: an ungrouped tab to the other end of the
    ///   pinned or unpinned tabs (never inside a group), a group's direct tab
    ///   to the other end of the group's shown tabs (never inside a
    ///   sub-group), and a sub-group's tab to the other end of its shown tabs
    ///   in the sub-group.
    /// Hidden tabs keep their places, a tab keeps its group, and no tab
    /// crosses between pinned and unpinned.
    @objc static func moveOrder(groupKeys: [String],
                                visible: [Bool],
                                selectedIndex: Int,
                                offset: Int) -> [Int]? {
        guard groupKeys.count == visible.count,
              groupKeys.indices.contains(selectedIndex),
              visible[selectedIndex],
              offset != 0 else {
            return nil
        }
        if let hop = orderHoppingRun(groupKeys: groupKeys, visible: visible, selectedIndex: selectedIndex, offset: offset) {
            return hop
        }
        var order = Array(groupKeys.indices)
        let other = swapIndex(groupKeys: groupKeys, visible: visible, selectedIndex: selectedIndex, offset: offset)
        if other != NSNotFound {
            order.swapAt(selectedIndex, other)
            return order
        }
        let mine = keyParts(groupKeys[selectedIndex])
        if mine.parent.isEmpty {
            // Ungrouped, or a group's direct tab.
            return orderWrappingToSectionEdge(groupKeys: groupKeys, visible: visible, selectedIndex: selectedIndex, offset: offset)
        }
        let key = groupKeys[selectedIndex]
        let peers = groupKeys.indices.filter { visible[$0] && groupKeys[$0] == key }
        guard peers.count > 1, let first = peers.first, let last = peers.last else {
            return nil
        }
        order.remove(at: selectedIndex)
        if offset > 0 {
            // It's the last peer, so the first is before it and keeps its index.
            order.insert(selectedIndex, at: first)
        } else {
            // It's the first peer. Removing it moved the last back by one, so
            // this goes just after it.
            order.insert(selectedIndex, at: last)
        }
        return order
    }

    private struct KeyParts: Equatable {
        var pinned: String
        var parent: String
        var group: String
        /// The parent if any, else the group, or "" for none.
        var topLevel: String { parent.isEmpty ? group : parent }
    }

    /// The parts of a group key from groupKeys(pinned:).
    private static func keyParts(_ key: String) -> KeyParts {
        let parts = key.components(separatedBy: "\u{1}")
        return KeyParts(pinned: parts.first ?? "",
                        parent: parts.count > 1 ? parts[1] : "",
                        group: parts.count > 2 ? parts[2] : "")
    }

    /// The tab moved to just past the run from `start` that `inRun` accepts,
    /// in the direction of `step`.
    private static func order(moving selectedIndex: Int,
                              pastRunFrom start: Int,
                              step: Int,
                              count: Int,
                              inRun: (Int) -> Bool) -> [Int] {
        var end = start
        while (0..<count).contains(end + step) && inRun(end + step) {
            end += step
        }
        var order = Array(0..<count)
        order.remove(at: selectedIndex)
        // Moving forward, removing the tab moved the run back by one, so this
        // goes just after it; moving backward, just before it.
        order.insert(selectedIndex, at: end)
        return order
    }

    /// An ungrouped tab moving past the next shown group, or a group's direct
    /// tab past the next shown sub-group of the group; nil otherwise.
    private static func orderHoppingRun(groupKeys: [String],
                                        visible: [Bool],
                                        selectedIndex: Int,
                                        offset: Int) -> [Int]? {
        let mine = keyParts(groupKeys[selectedIndex])
        let step = offset > 0 ? 1 : -1
        var j = selectedIndex + step
        while groupKeys.indices.contains(j) && !visible[j] {
            j += step
        }
        guard groupKeys.indices.contains(j) else {
            return nil
        }
        let theirs = keyParts(groupKeys[j])
        guard theirs.pinned == mine.pinned else {
            return nil
        }
        if mine.topLevel.isEmpty && !theirs.topLevel.isEmpty {
            return order(moving: selectedIndex, pastRunFrom: j, step: step, count: groupKeys.count) {
                let k = keyParts(groupKeys[$0])
                return k.pinned == theirs.pinned && k.topLevel == theirs.topLevel
            }
        }
        if mine.parent.isEmpty && !mine.group.isEmpty && theirs.parent == mine.group {
            return order(moving: selectedIndex, pastRunFrom: j, step: step, count: groupKeys.count) {
                keyParts(groupKeys[$0]) == theirs
            }
        }
        return nil
    }

    /// A tab at the end wrapping to the other end of its section: for an
    /// ungrouped tab, the pinned or unpinned tabs; for a group's direct tab,
    /// the group's tabs. It goes before the section's first shown tab (or
    /// after the last), moved out to the edge of that tab's group (or
    /// sub-group) so it never lands inside one. Nil if nothing else in the
    /// section is shown.
    private static func orderWrappingToSectionEdge(groupKeys: [String],
                                                   visible: [Bool],
                                                   selectedIndex: Int,
                                                   offset: Int) -> [Int]? {
        let mine = keyParts(groupKeys[selectedIndex])
        // An ungrouped tab's section is all tabs with its pinned state; a
        // group's direct tab's is the group.
        let inSection: (KeyParts) -> Bool = { k in
            k.pinned == mine.pinned && (mine.topLevel.isEmpty || k.topLevel == mine.topLevel)
        }
        let shown = groupKeys.indices.filter {
            $0 != selectedIndex && visible[$0] && inSection(keyParts(groupKeys[$0]))
        }
        let forward = offset > 0
        guard var edge = forward ? shown.first : shown.last else {
            return nil
        }
        // The run to step out of: a group's, for an ungrouped tab; a
        // sub-group's, for a group's direct tab.
        let edgeParts = keyParts(groupKeys[edge])
        let sameRun: ((KeyParts) -> Bool)?
        if mine.topLevel.isEmpty {
            sameRun = edgeParts.topLevel.isEmpty ? nil : { k in
                k.pinned == edgeParts.pinned && k.topLevel == edgeParts.topLevel
            }
        } else {
            sameRun = edgeParts.parent.isEmpty ? nil : { k in k == edgeParts }
        }
        if let sameRun {
            let step = forward ? -1 : 1
            while groupKeys.indices.contains(edge + step) && sameRun(keyParts(groupKeys[edge + step])) {
                edge += step
            }
        }
        var order = Array(groupKeys.indices)
        order.remove(at: selectedIndex)
        // Forward, the edge is before the tab and keeps its index, so this
        // goes just before it. Backward, removing the tab moved the edge back
        // by one, so this goes just after it.
        order.insert(selectedIndex, at: edge)
        return order
    }

    /// Next or previous tab while searching: the index of the nearest shown
    /// tab in that direction, wrapping around, or NSNotFound if there's no
    /// other. From a hidden tab, the nearest shown one.
    @objc static func adjacentVisibleIndex(visible: [Bool], selectedIndex: Int, offset: Int) -> Int {
        let count = visible.count
        guard count > 0, offset != 0, (0..<count).contains(selectedIndex) else {
            return NSNotFound
        }
        let step = offset > 0 ? 1 : -1
        var i = selectedIndex
        for _ in 1..<max(count, 2) {
            i = (i + step + count) % count
            if i == selectedIndex {
                break
            }
            if visible[i] {
                return i
            }
        }
        return NSNotFound
    }

    /// A shown tab to select when the selected one leaves: the nearest in the
    /// preferred direction, else the nearest the other way, without wrapping,
    /// as the tab view does without a search. NSNotFound if none is shown.
    @objc static func replacementIndex(visible: [Bool], closingIndex: Int, preferLeft: Bool) -> Int {
        guard visible.indices.contains(closingIndex) else {
            return NSNotFound
        }
        let left = (0..<closingIndex).reversed().first { visible[$0] }
        let right = ((closingIndex + 1)..<visible.count).first { visible[$0] }
        return (preferLeft ? (left ?? right) : (right ?? left)) ?? NSNotFound
    }

    /// Only tabs that match are shown, the selected one included.
    @objc static func apply(query: String, tabs: [TabBarSearchTab]) -> TabBarSearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TabBarSearchResult(groupIDs: tabs.map { Self.objectOrNull($0.groupID) },
                                      parentGroupIDs: tabs.map { Self.objectOrNull($0.parentGroupID) },
                                      hidden: tabs.map { $0.hidden },
                                      parentCollapsed: tabs.map { $0.parentCollapsed },
                                      matches: tabs.map { _ in true },
                                      isSearching: false)
        }
        let matches = tabs.map {
            Self.matches(query: trimmed, texts: $0.texts) || Self.matches(query: trimmed, texts: $0.groupNames)
        }
        // Groups that contain a shown tab, directly or in a sub-group.
        var keptGroups = Set<String>()
        for (tab, isShown) in zip(tabs, matches) where isShown {
            if let group = tab.groupID {
                keptGroups.insert(group)
            }
            if let parent = tab.parentGroupID {
                keptGroups.insert(parent)
            }
        }
        var groupIDs = [Any]()
        var parentGroupIDs = [Any]()
        for tab in tabs {
            if let group = tab.groupID, keptGroups.contains(group) {
                groupIDs.append(group)
                parentGroupIDs.append(Self.objectOrNull(tab.parentGroupID))
            } else if let parent = tab.parentGroupID, keptGroups.contains(parent) {
                // Its sub-group goes away, but the parent stays one run.
                groupIDs.append(parent)
                parentGroupIDs.append(NSNull())
            } else {
                groupIDs.append(NSNull())
                parentGroupIDs.append(NSNull())
            }
        }
        DLog("Tab bar search for \(trimmed) matches \(matches)")
        return TabBarSearchResult(groupIDs: groupIDs,
                                  parentGroupIDs: parentGroupIDs,
                                  hidden: matches.map { !$0 },
                                  parentCollapsed: tabs.map { _ in false },
                                  matches: matches,
                                  isSearching: true)
    }
}

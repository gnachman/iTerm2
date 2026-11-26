//
//  TabBarOrder.swift
//  iTerm2SharedARC
//
//  The order a vertical tab bar shows tabs in. It changes only how the bar
//  shows them, never the window's tabs, so ⌘-number and saved arrangements
//  are unaffected.
//
//  - Manual: the window's order, with its tab groups.
//  - Status: by status, ranked by the status priority settings, then in
//    manual order, with a section for each status priority pattern. Snoozed
//    tabs go in a last section.
//  - Working Directory: a section for each directory, sorted by path, with
//    tabs in manual order. Tabs with no directory, such
//    as web browser tabs, go in a last section.
//
//  Tab groups don't apply in the Status and Working Directory orders. Pinned
//  tabs stay first, in manual order.
//

import Foundation

@objc(iTermTabBarOrderMode)
enum TabBarOrderMode: Int {
    case manual = 0
    case status = 1
    case workingDirectory = 2
}

/// What the order needs to know about one tab, in manual order.
@objc(iTermTabBarOrderTab)
final class TabBarOrderTab: NSObject {
    let pinned: Bool
    /// Lower is more urgent. NSIntegerMax for no status.
    let statusPriority: Int
    let snoozed: Bool
    /// The directory of its active session, or nil when it has none.
    let directory: String?
    /// Its tab group, or nil. The bar doesn't show groups in a sorted order,
    /// but the window keeps a group's tabs together, so a move stays among
    /// tabs in the same group.
    let group: String?

    @objc init(pinned: Bool, statusPriority: Int, snoozed: Bool, directory: String?, group: String?) {
        self.pinned = pinned
        self.statusPriority = statusPriority
        self.snoozed = snoozed
        self.directory = directory
        self.group = group
    }
}

/// A heading in the bar for tabs that go together.
@objc(iTermTabBarOrderSection)
final class TabBarOrderSection: NSObject {
    /// Used as a tab group identifier, so the bar draws the heading as it
    /// draws a group's.
    @objc let identifier: String
    @objc let name: String
    /// Shown before the name, dimmer, so the two read as the path: where the
    /// directory is, as “~/git/”, or nil.
    @objc let detail: String?
    /// The full path, or nil.
    @objc let toolTip: String?

    init(identifier: String, name: String, detail: String?, toolTip: String?) {
        self.identifier = identifier
        self.name = name
        self.detail = detail
        self.toolTip = toolTip
    }
}

@objc(iTermTabBarOrderResult)
final class TabBarOrderResult: NSObject {
    /// Indices into the tabs, in the order the bar shows them.
    @objc let order: [Int]
    /// For each tab, in manual order, the identifier of its section, or
    /// NSNull when it has no heading.
    @objc let sectionIdentifiers: [Any]
    /// The headings, in the order they're shown.
    @objc let sections: [TabBarOrderSection]
    /// For each tab, in manual order: equal for tabs that a move can trade
    /// places with each other.
    let moveKeys: [String]

    init(order: [Int], sectionIdentifiers: [Any], sections: [TabBarOrderSection], moveKeys: [String]) {
        self.order = order
        self.sectionIdentifiers = sectionIdentifiers
        self.sections = sections
        self.moveKeys = moveKeys
    }
}

@objc(iTermTabBarOrder)
final class TabBarOrder: NSObject {
    /// Every section identifier starts with this, so it can't be mistaken
    /// for a tab group's.
    @objc static let sectionIdentifierPrefix = "iTermTabBarOrderSection:"
    @objc static let otherSectionIdentifier = sectionIdentifierPrefix + "other"

    @objc static func isSectionIdentifier(_ identifier: String?) -> Bool {
        return identifier?.hasPrefix(sectionIdentifierPrefix) ?? false
    }

    @objc static func apply(mode: TabBarOrderMode, tabs: [TabBarOrderTab]) -> TabBarOrderResult {
        return apply(mode: mode, tabs: tabs, statusPatterns: StatusPrioritySettings.shared.patterns)
    }

    /// `statusPatterns` are the status priority patterns, most urgent first.
    /// They name the Status order's sections.
    static func apply(mode: TabBarOrderMode,
                      tabs: [TabBarOrderTab],
                      statusPatterns: [String]) -> TabBarOrderResult {
        let indices = Array(tabs.indices)
        let pinned = indices.filter { tabs[$0].pinned }
        let unpinned = indices.filter { !tabs[$0].pinned }
        let pinnedKey = "pinned"
        // Moves stay in a group, since the window keeps groups together.
        func moveKey(_ i: Int, _ key: String) -> String {
            return "\(tabs[i].pinned ? pinnedKey : key)\u{1}\(tabs[i].group ?? "")"
        }
        switch mode {
        case .manual:
            return TabBarOrderResult(order: indices,
                                     sectionIdentifiers: indices.map { _ in NSNull() },
                                     sections: [],
                                     moveKeys: indices.map { moveKey($0, "unpinned") })
        case .status:
            // Ties keep manual order. Swift's sort isn't documented as
            // stable, so compare indices too.
            let sorted = unpinned.sorted { lhs, rhs in
                let l = tabs[lhs], r = tabs[rhs]
                if l.snoozed != r.snoozed {
                    return !l.snoozed
                }
                if l.statusPriority != r.statusPriority {
                    return l.statusPriority < r.statusPriority
                }
                return lhs < rhs
            }
            let moveKeys = indices.map { i -> String in
                let tab = tabs[i]
                return moveKey(i, "status:\(tab.snoozed):\(tab.statusPriority)")
            }
            // Sorted, so each section's tabs are one run.
            var sections = [TabBarOrderSection]()
            var identifiers = [Any](repeating: NSNull(), count: tabs.count)
            for i in sorted {
                let section = statusSection(for: tabs[i], patterns: statusPatterns)
                if sections.last?.identifier != section.identifier {
                    sections.append(section)
                }
                identifiers[i] = section.identifier
            }
            return TabBarOrderResult(order: pinned + sorted,
                                     sectionIdentifiers: identifiers,
                                     sections: sections,
                                     moveKeys: moveKeys)
        case .workingDirectory:
            var sectionOrder = [String]()
            var members = [String: [Int]]()
            var sections = [String: TabBarOrderSection]()
            var identifiers = [Any](repeating: NSNull(), count: tabs.count)
            for i in unpinned {
                let section = self.section(for: tabs[i])
                if members[section.identifier] == nil {
                    if section.identifier != otherSectionIdentifier {
                        sectionOrder.append(section.identifier)
                    }
                    sections[section.identifier] = section
                }
                members[section.identifier, default: []].append(i)
                identifiers[i] = section.identifier
            }
            sectionOrder.sort { lhs, rhs in
                directoryPrecedes(sections[lhs]?.toolTip ?? "", sections[rhs]?.toolTip ?? "")
            }
            // Last.
            if members[otherSectionIdentifier] != nil {
                sectionOrder.append(otherSectionIdentifier)
            }
            let order = pinned + sectionOrder.flatMap { members[$0] ?? [] }
            let moveKeys = indices.map { i in
                moveKey(i, identifiers[i] as? String ?? "")
            }
            return TabBarOrderResult(order: order,
                                     sectionIdentifiers: identifiers,
                                     sections: sectionOrder.compactMap { sections[$0] },
                                     moveKeys: moveKeys)
        }
    }

    private static func statusSection(for tab: TabBarOrderTab, patterns: [String]) -> TabBarOrderSection {
        let prefix = sectionIdentifierPrefix + "status:"
        if tab.snoozed {
            return TabBarOrderSection(
                identifier: prefix + "snoozed",
                name: String(localized: "TabBarOrder.SnoozedSection",
                             defaultValue: "Snoozed",
                             comment: "Heading in a vertical tab bar ordered by status, over tabs the user snoozed."),
                detail: nil,
                toolTip: nil)
        }
        let priority = tab.statusPriority
        if priority >= 0 && priority < patterns.count {
            let pattern = patterns[priority]
            // The pattern is in the identifier so that changing it renames
            // the heading.
            return TabBarOrderSection(identifier: prefix + "\(priority):" + pattern,
                                      name: statusSectionName(pattern: pattern),
                                      detail: nil,
                                      toolTip: nil)
        }
        if priority == patterns.count {
            return TabBarOrderSection(
                identifier: prefix + "unmatched",
                name: String(localized: "TabBarOrder.OtherStatusSection",
                             defaultValue: "Other",
                             comment: "Heading in a vertical tab bar ordered by status, over tabs whose status matches none of the user’s status priority patterns."),
                detail: nil,
                toolTip: nil)
        }
        return TabBarOrderSection(
            identifier: prefix + "none",
            name: String(localized: "TabBarOrder.NoStatusSection",
                         defaultValue: "No Status",
                         comment: "Heading in a vertical tab bar ordered by status, over tabs that have no status."),
            detail: nil,
            toolTip: nil)
    }

    /// Patterns match status text, which is English, so the built-in ones
    /// get localized names. One the user added is shown as written.
    private static func statusSectionName(pattern: String) -> String {
        switch pattern.lowercased() {
        case "wait":
            return String(localized: "TabBarOrder.WaitingSection", defaultValue: "Waiting",
                          comment: "Heading in a vertical tab bar ordered by status, over tabs whose program is waiting for the user.")
        case "done":
            return String(localized: "TabBarOrder.DoneSection", defaultValue: "Done",
                          comment: "Heading in a vertical tab bar ordered by status, over tabs whose program finished its work.")
        case "error":
            return String(localized: "TabBarOrder.ErrorSection", defaultValue: "Error",
                          comment: "Heading in a vertical tab bar ordered by status, over tabs whose program reported an error.")
        case "work":
            return String(localized: "TabBarOrder.WorkingSection", defaultValue: "Working",
                          comment: "Heading in a vertical tab bar ordered by status, over tabs whose program is working.")
        case "background":
            return String(localized: "TabBarOrder.BackgroundSection", defaultValue: "Background",
                          comment: "Heading in a vertical tab bar ordered by status, over tabs whose program is waiting on work it started in the background.")
        case "idle":
            return String(localized: "TabBarOrder.IdleSection", defaultValue: "Idle",
                          comment: "Heading in a vertical tab bar ordered by status, over tabs whose program is idle.")
        default:
            return pattern.prefix(1).uppercased() + pattern.dropFirst()
        }
    }

    private static func section(for tab: TabBarOrderTab) -> TabBarOrderSection {
        guard let directory = tab.directory, !directory.isEmpty else {
            return TabBarOrderSection(
                identifier: otherSectionIdentifier,
                name: String(localized: "TabBarOrder.OtherSection",
                             defaultValue: "Other",
                             comment: "Heading in a vertical tab bar ordered by working directory, over tabs that have no directory, such as web browser tabs."),
                detail: nil,
                toolTip: nil)
        }
        let standardized = (directory as NSString).standardizingPath
        let home = NSHomeDirectory()
        let name: String
        let detail: String?
        if standardized == home || standardized == "/" {
            name = standardized == home ? String(localized: "TabBarOrder.HomeSection",
                                                 defaultValue: "Home",
                                                 comment: "Heading in a vertical tab bar ordered by working directory, over tabs whose working directory is the user’s home directory.") : "/"
            detail = nil
        } else {
            name = (standardized as NSString).lastPathComponent
            let parent = abbreviatingHome((standardized as NSString).deletingLastPathComponent)
            if parent.isEmpty {
                // Not an absolute path, so there's no parent to show.
                detail = nil
            } else {
                detail = parent.hasSuffix("/") ? parent : parent + "/"
            }
        }
        return TabBarOrderSection(identifier: sectionIdentifierPrefix + "dir:" + standardized,
                                  name: name,
                                  detail: detail,
                                  toolTip: standardized)
    }

    /// Compares a component at a time, as Finder does, so a directory's
    /// subdirectories come right after it.
    static func directoryPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        let l = (lhs as NSString).pathComponents
        let r = (rhs as NSString).pathComponents
        for (a, b) in zip(l, r) {
            switch a.localizedStandardCompare(b) {
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            case .orderedSame:
                if a != b {
                    // Different directories it considers equal.
                    return a < b
                }
            }
        }
        return l.count < r.count
    }

    private static func abbreviatingHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Move Tab Left or Right in a sorted order: the new manual order, as
    /// indices into the old one, or nil to stay put. The tab trades places
    /// with the nearest visible tab the bar shows in that direction that it
    /// can trade with (the same section, status, or pinned state). At the
    /// end, it wraps to the other end of those. Only the tabs it can trade
    /// with change places among themselves, so every other tab keeps its
    /// place, and the bar shows the move as one step.
    @objc static func moveOrder(result: TabBarOrderResult,
                                visible: [Bool],
                                selectedIndex: Int,
                                offset: Int) -> [Int]? {
        let count = result.moveKeys.count
        guard visible.count == count,
              (0..<count).contains(selectedIndex),
              visible[selectedIndex],
              offset != 0 else {
            return nil
        }
        let key = result.moveKeys[selectedIndex]
        // Its peers in the order the bar shows them, which is manual order.
        let peers = result.order.filter { result.moveKeys[$0] == key }
        let shown = peers.filter { visible[$0] }
        guard shown.count > 1, let position = shown.firstIndex(of: selectedIndex) else {
            return nil
        }
        var newShown = shown
        newShown.remove(at: position)
        if offset > 0 {
            if position + 1 < shown.count {
                newShown.insert(selectedIndex, at: position + 1)
            } else {
                newShown.insert(selectedIndex, at: 0)
            }
        } else {
            if position > 0 {
                newShown.insert(selectedIndex, at: position - 1)
            } else {
                newShown.append(selectedIndex)
            }
        }
        // Put the shown peers back in the places shown peers had, in their
        // new order. Hidden peers and everything else keep their places.
        var order = Array(0..<count)
        let places = shown.sorted()
        for (place, tab) in zip(places, newShown) {
            order[place] = tab
        }
        return order
    }

    /// Next or previous tab in the order the bar shows: the index (in manual
    /// order) of the nearest visible tab in that direction, wrapping around,
    /// or NSNotFound if there's no other.
    @objc static func adjacentVisibleIndex(order: [Int],
                                           visible: [Bool],
                                           selectedIndex: Int,
                                           offset: Int) -> Int {
        guard let position = order.firstIndex(of: selectedIndex) else {
            return NSNotFound
        }
        let visibleInOrder = order.map { visible.indices.contains($0) && visible[$0] }
        let i = TabBarSearch.adjacentVisibleIndex(visible: visibleInOrder,
                                                  selectedIndex: position,
                                                  offset: offset)
        return i == NSNotFound ? NSNotFound : order[i]
    }
}

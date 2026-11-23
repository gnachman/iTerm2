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
//    manual order. Snoozed tabs go after the rest.
//  - Working Directory: a section for each directory, in the manual order of
//    its first tab, with tabs in manual order. Tabs whose directory isn't
//    known go in a section after those, and tabs at a shell prompt in a last
//    section, since their directory changes with every cd.
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
    /// The directory of its active session, or nil when it isn't known.
    let directory: String?
    /// Whether it's waiting for a command at a shell prompt, where its
    /// directory changes with every cd.
    let atPrompt: Bool
    /// Its tab group, or nil. The bar doesn't show groups in a sorted order,
    /// but the window keeps a group's tabs together, so a move stays among
    /// tabs in the same group.
    let group: String?

    @objc init(pinned: Bool, statusPriority: Int, snoozed: Bool, directory: String?, atPrompt: Bool, group: String?) {
        self.pinned = pinned
        self.statusPriority = statusPriority
        self.snoozed = snoozed
        self.directory = directory
        self.atPrompt = atPrompt
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
    /// The full path, or nil.
    @objc let toolTip: String?

    init(identifier: String, name: String, toolTip: String?) {
        self.identifier = identifier
        self.name = name
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
    @objc static let promptSectionIdentifier = sectionIdentifierPrefix + "prompt"
    @objc static let unknownSectionIdentifier = sectionIdentifierPrefix + "unknown"

    @objc static func isSectionIdentifier(_ identifier: String?) -> Bool {
        return identifier?.hasPrefix(sectionIdentifierPrefix) ?? false
    }

    @objc static func apply(mode: TabBarOrderMode, tabs: [TabBarOrderTab]) -> TabBarOrderResult {
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
            return TabBarOrderResult(order: pinned + sorted,
                                     sectionIdentifiers: indices.map { _ in NSNull() },
                                     sections: [],
                                     moveKeys: moveKeys)
        case .workingDirectory:
            var sectionOrder = [String]()
            var members = [String: [Int]]()
            var sections = [String: TabBarOrderSection]()
            var identifiers = [Any](repeating: NSNull(), count: tabs.count)
            // These go last, in this order.
            let trailing = [unknownSectionIdentifier, promptSectionIdentifier]
            for i in unpinned {
                let section = self.section(for: tabs[i])
                if members[section.identifier] == nil {
                    if !trailing.contains(section.identifier) {
                        sectionOrder.append(section.identifier)
                    }
                    sections[section.identifier] = section
                }
                members[section.identifier, default: []].append(i)
                identifiers[i] = section.identifier
            }
            sectionOrder.append(contentsOf: trailing.filter { members[$0] != nil })
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

    private static func section(for tab: TabBarOrderTab) -> TabBarOrderSection {
        if tab.atPrompt {
            return TabBarOrderSection(
                identifier: promptSectionIdentifier,
                name: String(localized: "TabBarOrder.PromptSection",
                             defaultValue: "At a Shell Prompt",
                             comment: "Heading in a vertical tab bar ordered by working directory, over the tabs whose shell is waiting for a command. Their directory changes as the user types cd, so they aren’t put under a directory."),
                toolTip: nil)
        }
        guard let directory = tab.directory, !directory.isEmpty else {
            return TabBarOrderSection(
                identifier: unknownSectionIdentifier,
                name: String(localized: "TabBarOrder.UnknownSection",
                             defaultValue: "Unknown Directory",
                             comment: "Heading in a vertical tab bar ordered by working directory, over tabs whose directory isn’t known, such as web browser tabs."),
                toolTip: nil)
        }
        let standardized = (directory as NSString).standardizingPath
        let name: String
        if standardized == NSHomeDirectory() {
            name = "~"
        } else {
            let last = (standardized as NSString).lastPathComponent
            name = last.isEmpty ? standardized : last
        }
        return TabBarOrderSection(identifier: sectionIdentifierPrefix + "dir:" + standardized,
                                  name: name,
                                  toolTip: standardized)
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

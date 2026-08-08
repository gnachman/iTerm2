//
//  iTermTabGroupRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/26.
//

import Foundation

// Per-window store of tab-group definitions, keyed by group id. One
// registry lives on each window (PseudoTerminal); a tab points at a
// group by id (PTYTab.tabGroupID) and looks up its name/color here.
//
// The registry only holds definitions, not membership: which tabs are
// in a group is per-tab, and the group's run order is the tab bar's
// order. Groups that no membership references any longer are pruned so
// a closed-out group's definition doesn't linger in the arrangement.
@objc(iTermTabGroupRegistry)
final class iTermTabGroupRegistry: NSObject, PSMTabGroupDataSource {
    private var groupsByID: [String: iTermTabGroup] = [:]

    @objc func group(withID identifier: String) -> iTermTabGroup? {
        return groupsByID[identifier]
    }

    // PSMTabGroupDataSource: the tab bar's typed view of group(withID:).
    // Returns the concrete iTermTabGroup as an id<PSMTabGroup> so the
    // vendored control reads name/color without knowing the model type.
    @objc func tabGroup(withIdentifier identifier: String) -> PSMTabGroup? {
        return groupsByID[identifier]
    }

    @objc func add(_ group: iTermTabGroup) {
        groupsByID[group.uniqueIdentifier] = group
    }

    @objc func removeGroup(withID identifier: String) {
        groupsByID.removeValue(forKey: identifier)
    }

    @objc var allGroups: [iTermTabGroup] {
        return Array(groupsByID.values)
    }

    @objc var isEmpty: Bool {
        return groupsByID.isEmpty
    }

    // Drop every group whose id isn't in `inUseIdentifiers` (the set of
    // group ids currently referenced by this window's tabs). Called
    // after a tab closes or moves so orphaned definitions don't persist.
    @objc(pruneGroupsKeepingIDs:)
    func pruneGroups(keepingIDs inUseIdentifiers: Set<String>) {
        for identifier in groupsByID.keys where !inUseIdentifiers.contains(identifier) {
            groupsByID.removeValue(forKey: identifier)
        }
    }

    // MARK: - Arrangement

    // Array of per-group arrangement dicts, for embedding in the window
    // arrangement alongside the tab list. Order is unimportant: a
    // group's run position is reconstructed from tab order on restore.
    @objc var arrangement: [[String: Any]] {
        return allGroups.map { $0.arrangement }
    }

    // Merge decoded groups into the registry. Additive so a restore into
    // an existing window (rare) doesn't drop live groups; a decoded id
    // that collides replaces the existing definition.
    @objc func load(arrangement: [[String: Any]]) {
        for dict in arrangement {
            if let group = iTermTabGroup(arrangement: dict) {
                add(group)
            }
        }
    }
}

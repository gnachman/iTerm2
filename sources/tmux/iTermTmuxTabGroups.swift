//
//  iTermTmuxTabGroups.swift
//  iTerm2SharedARC
//
//  Tab groups of tmux integration tabs are remembered in the tmux session's @tab_groups option so
//  they survive detach and reattach. It is a separate option rather than more keys in
//  @per_tab_settings because an older iTerm2 attached to the same server rewrites
//  @per_tab_settings wholesale with only the keys it knows, which would erase the groups.
//
//  The value is JSON:
//    {"groups": {"<group id>": {"name": "...", "color": "<hex>", "collapsed": false}},
//     "tabs": {"<tmux window id>": "<group id>"}}
//  Keys are sorted so equal state always encodes to the same string.
//
//  Nesting lives in a separate option, @tab_group_parents, for the same reason: an iTerm2 that
//  predates nested groups rewrites @tab_groups with only what it knows. @tab_groups maps each tab
//  to its own group, so such an iTerm2 shows sub-groups as ordinary groups, and the nesting
//  survives for a newer one. Its value is JSON mapping each sub-group to its parent's definition:
//    {"<sub-group id>": {"id": "<parent id>", "name": "...", "color": "<hex>", "collapsed": false}}
//

import AppKit

// One tmux window's tab group membership, with the group's definition.
@objc(iTermTmuxTabGroupMembership)
final class iTermTmuxTabGroupMembership: NSObject {
    @objc let groupID: String
    @objc let name: String?
    @objc let color: NSColor?
    @objc let collapsed: Bool

    @objc init(groupID: String, name: String?, color: NSColor?, collapsed: Bool) {
        self.groupID = groupID
        self.name = name
        self.color = color
        self.collapsed = collapsed
        super.init()
    }
}

@objc(iTermTmuxTabGroups)
final class iTermTmuxTabGroups: NSObject {
    private enum Key {
        static let groups = "groups"
        static let tabs = "tabs"
        static let name = "name"
        static let color = "color"
        static let collapsed = "collapsed"
        static let id = "id"
    }

    private static func definition(_ membership: iTermTmuxTabGroupMembership) -> [String: Any] {
        var group: [String: Any] = [Key.collapsed: membership.collapsed]
        if let name = membership.name {
            group[Key.name] = name
        }
        if let color = membership.color {
            group[Key.color] = color.hexString()
        }
        return group
    }

    private static func membership(groupID: String, definition group: [String: Any]) -> iTermTmuxTabGroupMembership {
        let color = (group[Key.color] as? String).flatMap { NSColor(fromHexString: $0) }
        return iTermTmuxTabGroupMembership(groupID: groupID,
                                           name: group[Key.name] as? String,
                                           color: color,
                                           collapsed: group[Key.collapsed] as? Bool ?? false)
    }

    private static func jsonString(_ root: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            DLog("Failed to encode \(root)")
            return ""
        }
        return string
    }

    // Maps tmux window ID to membership. Returns an empty string when there are no memberships.
    // When members of one group disagree about its definition, the lowest window ID wins.
    @objc(encodedStringForMemberships:)
    static func encode(_ memberships: [NSNumber: iTermTmuxTabGroupMembership]) -> String {
        if memberships.isEmpty {
            return ""
        }
        var groups = [String: [String: Any]]()
        var tabs = [String: String]()
        for (windowID, membership) in memberships.sorted(by: { $0.key.intValue < $1.key.intValue }) {
            tabs[windowID.stringValue] = membership.groupID
            if groups[membership.groupID] != nil {
                continue
            }
            groups[membership.groupID] = definition(membership)
        }
        return jsonString([Key.groups: groups, Key.tabs: tabs])
    }

    // Maps sub-group ID to its parent's definition (whose groupID is the parent's ID). Returns an
    // empty string when there are none.
    @objc(encodedStringForParents:)
    static func encodeParents(_ parents: [String: iTermTmuxTabGroupMembership]) -> String {
        if parents.isEmpty {
            return ""
        }
        var root = [String: [String: Any]]()
        for (subgroupID, parent) in parents {
            var group = definition(parent)
            group[Key.id] = parent.groupID
            root[subgroupID] = group
        }
        return jsonString(root)
    }

    // Inverse of encodeParents. Malformed input yields as many entries as can be recovered.
    @objc(parentsFromEncodedString:)
    static func decodeParents(_ string: String) -> [String: iTermTmuxTabGroupMembership] {
        guard let data = string.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if !string.isEmpty {
                DLog("Failed to decode tab group parents \(string)")
            }
            return [:]
        }
        var result = [String: iTermTmuxTabGroupMembership]()
        for (subgroupID, value) in root {
            guard let group = value as? [String: Any],
                  let parentID = group[Key.id] as? String,
                  parentID != subgroupID else {
                continue
            }
            result[subgroupID] = membership(groupID: parentID, definition: group)
        }
        return result
    }

    // Keeps only the parents of sub-groups that some window still belongs to, and drops any that
    // would nest two levels deep (a parent that is itself listed as a sub-group). An older iTerm2
    // may have ungrouped a sub-group's tabs while it was attached.
    @objc(parentsByPruning:toGroupsOfMemberships:)
    static func prune(_ parents: [String: iTermTmuxTabGroupMembership],
                      memberships: [NSNumber: iTermTmuxTabGroupMembership]) -> [String: iTermTmuxTabGroupMembership] {
        let referenced = Set(memberships.values.map(\.groupID))
        return parents.filter { subgroupID, parent in
            referenced.contains(subgroupID) && parents[parent.groupID] == nil
        }
    }

    // A tab group lives in one window, but an iTerm2 that predates tab groups can move a member
    // into another window without updating @tab_groups. Each group stays with the window holding
    // most of its saved members (on a tie, the one with the lowest window ID); members saved in
    // other windows lose their membership, as they would by being dragged out of the group.
    // `windowKey` names the iTerm2 window a tmux window will open in, or returns nil if unknown.
    // Members with an unknown window are left alone.
    @objc(membershipsConfiningEachGroupToOneWindow:windowKey:)
    static func confineEachGroupToOneWindow(
        _ memberships: [NSNumber: iTermTmuxTabGroupMembership],
        windowKey: (NSNumber) -> String?) -> [NSNumber: iTermTmuxTabGroupMembership] {
        // group ID -> window key -> member window IDs
        var placement = [String: [String: [Int32]]]()
        for (windowID, membership) in memberships {
            guard let key = windowKey(windowID) else {
                continue
            }
            placement[membership.groupID, default: [:]][key, default: []].append(windowID.int32Value)
        }
        var result = memberships
        for (groupID, windows) in placement where windows.count > 1 {
            let owner = windows.max { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count < rhs.value.count
                }
                return lhs.value.min()! > rhs.value.min()!
            }!.key
            for (key, windowIDs) in windows where key != owner {
                DLog("Group \(groupID) lives in window \(owner); dropping members \(windowIDs) in \(key)")
                for windowID in windowIDs {
                    result[NSNumber(value: windowID)] = nil
                }
            }
        }
        return result
    }

    // A parent with direct members also has a definition in @tab_groups, and that one is the
    // authority: an iTerm2 that predates nesting rewrites only @tab_groups, so a rename, recolor
    // or collapse it made is there and not in @tab_group_parents. Each parent takes its
    // definition from @tab_groups when it has one (from the lowest window ID, so the result
    // doesn't depend on order).
    @objc(parentsByAdoptingDefinitions:fromMemberships:)
    static func adoptDefinitions(_ parents: [String: iTermTmuxTabGroupMembership],
                                 from memberships: [NSNumber: iTermTmuxTabGroupMembership]) -> [String: iTermTmuxTabGroupMembership] {
        var definitions = [String: iTermTmuxTabGroupMembership]()
        for windowID in memberships.keys.sorted(by: { $0.int32Value > $1.int32Value }) {
            let membership = memberships[windowID]!
            definitions[membership.groupID] = membership
        }
        return parents.mapValues { parent in
            definitions[parent.groupID] ?? parent
        }
    }

    // The parent-side counterpart of confineEachGroupToOneWindow, for memberships already confined
    // by it. A parent with direct members lives where they do (confineEachGroupToOneWindow already
    // put them all in one window). Otherwise it lives in the window holding most of its sub-groups'
    // members (on a tie, the one with the lowest window ID). Sub-groups in other windows lose their
    // parent and become top-level, as they would by being dragged away.
    @objc(parentsByConfiningEachParentToOneWindow:memberships:windowKey:)
    static func confineEachParentToOneWindow(
        _ parents: [String: iTermTmuxTabGroupMembership],
        memberships: [NSNumber: iTermTmuxTabGroupMembership],
        windowKey: (NSNumber) -> String?) -> [String: iTermTmuxTabGroupMembership] {
        // parent ID -> window key of its direct members
        var directOwners = [String: String]()
        // parent ID -> window key -> sub-group member window IDs
        var placement = [String: [String: [Int32]]]()
        for (windowID, membership) in memberships {
            guard let key = windowKey(windowID) else {
                continue
            }
            if let parentID = parents[membership.groupID]?.groupID {
                placement[parentID, default: [:]][key, default: []].append(windowID.int32Value)
            } else {
                directOwners[membership.groupID] = key
            }
        }
        var owners = directOwners
        for (parentID, windows) in placement where owners[parentID] == nil {
            owners[parentID] = windows.max { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count < rhs.value.count
                }
                return lhs.value.min()! > rhs.value.min()!
            }!.key
        }
        var result = parents
        for (windowID, membership) in memberships {
            guard let parent = parents[membership.groupID],
                  let key = windowKey(windowID),
                  let owner = owners[parent.groupID],
                  key != owner else {
                continue
            }
            DLog("Parent \(parent.groupID) lives in window \(owner); sub-group \(membership.groupID) in \(key) becomes top-level")
            result[membership.groupID] = nil
        }
        return result
    }

    // Inverse of encode. Malformed input yields as many memberships as can be recovered.
    @objc(membershipsFromEncodedString:)
    static func decode(_ string: String) -> [NSNumber: iTermTmuxTabGroupMembership] {
        guard let data = string.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = root[Key.groups] as? [String: [String: Any]],
              let tabs = root[Key.tabs] as? [String: String] else {
            if !string.isEmpty {
                DLog("Failed to decode tab groups \(string)")
            }
            return [:]
        }
        var result = [NSNumber: iTermTmuxTabGroupMembership]()
        for (windowIDString, groupID) in tabs {
            guard let windowID = Int32(windowIDString), let group = groups[groupID] else {
                continue
            }
            result[NSNumber(value: windowID)] = membership(groupID: groupID, definition: group)
        }
        return result
    }
}

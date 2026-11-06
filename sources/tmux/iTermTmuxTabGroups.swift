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
            var group: [String: Any] = [Key.collapsed: membership.collapsed]
            if let name = membership.name {
                group[Key.name] = name
            }
            if let color = membership.color {
                group[Key.color] = color.hexString()
            }
            groups[membership.groupID] = group
        }
        let root: [String: Any] = [Key.groups: groups, Key.tabs: tabs]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            DLog("Failed to encode tab groups \(root)")
            return ""
        }
        return string
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
            let color = (group[Key.color] as? String).flatMap { NSColor(fromHexString: $0) }
            result[NSNumber(value: windowID)] = iTermTmuxTabGroupMembership(
                groupID: groupID,
                name: group[Key.name] as? String,
                color: color,
                collapsed: group[Key.collapsed] as? Bool ?? false)
        }
        return result
    }
}

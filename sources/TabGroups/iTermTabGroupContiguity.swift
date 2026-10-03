//
//  iTermTabGroupContiguity.swift
//  iTerm2SharedARC
//
//  Pure logic for resolving a dropped tab's group membership so that a group's
//  tabs stay consecutive. A drop moves exactly one tab without changing any
//  membership, so we resolve just that tab from where it landed:
//    - strictly between two members of the same group -> join that group
//      (this is how an ungrouped tab is added, or a tab moves between groups);
//    - otherwise (at a group's edge, or not near a group) -> leave any group,
//      so dragging a member out removes it -- including a one-tab group's sole
//      member, whose group dissolves when its last tab is dragged out. (An
//      in-place drop keeps membership, but that is signalled by the drop
//      landing on the tab's own gid-carrying slot, upstream of this rule.)
//  Only the dragged tab's membership ever changes, so neighbors are never
//  absorbed. See PseudoTerminal.resolveDroppedTabGroupMembership:.
//

import Foundation

@objc(iTermTabGroupContiguity)
class iTermTabGroupContiguity: NSObject {
    // Swift-native core (unit-tested directly). `order[i]` is tab i's group id,
    // or nil when ungrouped; `index` is the tab that was just dropped. Returns
    // the group id that tab should have (nil = ungrouped).
    static func resolvedGroup(forTabAt index: Int, order: [String?]) -> String? {
        guard index >= 0, index < order.count else {
            return nil
        }
        let left = index > 0 ? order[index - 1] : nil
        let right = index + 1 < order.count ? order[index + 1] : nil
        // Strictly inside a run of a single group: join it.
        if let left, left == right {
            return left
        }
        // At a group's edge or away from any group: not a member. A one-tab
        // group's sole member dragged out dissolves its group.
        return nil
    }

    // Nested variant. `parents[i]` is the parent group of tab i's group, or nil.
    // Each neighbor is seen as a path (parent, group); the dropped tab joins the
    // deepest group both neighbors share. So landing between two members of a
    // sub-group joins the sub-group; landing between a parent's direct member and
    // one of its sub-groups (or between two of its sub-groups) joins the parent
    // directly; anything else leaves every group. With no parents this matches
    // resolvedGroup(forTabAt:order:).
    static func resolvedGroup(forTabAt index: Int, order: [String?], parents: [String?]) -> String? {
        guard index >= 0, index < order.count, order.count == parents.count else {
            return nil
        }
        func path(_ i: Int) -> [String] {
            guard i >= 0, i < order.count, let gid = order[i] else {
                return []
            }
            if let parent = parents[i] {
                return [parent, gid]
            }
            return [gid]
        }
        let left = path(index - 1)
        let right = path(index + 1)
        var shared: String? = nil
        for (l, r) in zip(left, right) {
            guard l == r else {
                break
            }
            shared = l
        }
        return shared
    }

    // ObjC bridge: `order` elements are NSString group ids or NSNull for
    // ungrouped tabs. Returns the resolved group id, or nil for ungrouped.
    @objc(resolvedGroupForTabAt:order:)
    static func resolvedGroup(forTabAt index: Int, order: [Any]) -> String? {
        return resolvedGroup(forTabAt: index, order: order.map { $0 as? String })
    }

    // ObjC bridge for the nested variant; `parents` is parallel to `order`.
    @objc(resolvedGroupForTabAt:order:parents:)
    static func resolvedGroup(forTabAt index: Int, order: [Any], parents: [Any]) -> String? {
        return resolvedGroup(forTabAt: index,
                             order: order.map { $0 as? String },
                             parents: parents.map { $0 as? String })
    }
}

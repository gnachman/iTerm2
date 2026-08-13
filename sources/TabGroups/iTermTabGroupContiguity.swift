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

    // ObjC bridge: `order` elements are NSString group ids or NSNull for
    // ungrouped tabs. Returns the resolved group id, or nil for ungrouped.
    @objc(resolvedGroupForTabAt:order:)
    static func resolvedGroup(forTabAt index: Int, order: [Any]) -> String? {
        return resolvedGroup(forTabAt: index, order: order.map { $0 as? String })
    }
}

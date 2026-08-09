//
//  iTermTabGroupContiguity.swift
//  iTerm2SharedARC
//
//  Pure logic for resolving a dropped tab's group membership so that a group's
//  tabs stay consecutive. A drop moves exactly one tab without changing any
//  membership, so we resolve just that tab from where it landed:
//    - strictly between two members of the same group -> join that group
//      (this is how an ungrouped tab is added, or a tab moves between groups);
//    - the sole member of its own group -> keep it (a one-tab group is
//      contiguous by itself and shouldn't dissolve just because it was moved);
//    - otherwise (at a multi-tab group's edge, or not near a group) -> leave any
//      group, so dragging a member to the group's boundary removes it.
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
        let current = order[index]
        let left = index > 0 ? order[index - 1] : nil
        let right = index + 1 < order.count ? order[index + 1] : nil
        // Strictly inside a run of a single group: join it.
        if let left, left == right {
            return left
        }
        // The sole member of its own group keeps it (a one-tab group survives).
        if let current, order.reduce(0, { $0 + ($1 == current ? 1 : 0) }) <= 1 {
            return current
        }
        // At a group's edge or away from any group: not a member.
        return nil
    }

    // ObjC bridge: `order` elements are NSString group ids or NSNull for
    // ungrouped tabs. Returns the resolved group id, or nil for ungrouped.
    @objc(resolvedGroupForTabAt:order:)
    static func resolvedGroup(forTabAt index: Int, order: [Any]) -> String? {
        return resolvedGroup(forTabAt: index, order: order.map { $0 as? String })
    }
}

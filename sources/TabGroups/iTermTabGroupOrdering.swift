//
//  iTermTabGroupOrdering.swift
//  iTerm2SharedARC
//
//  Pure logic for the tab bar's two ordering invariants:
//    1. Pinned tabs form a prefix (pinned-left, unpinned-right).
//    2. A group's members are contiguous.
//  When both cannot hold (a group with pinned and unpinned members), the
//  pinned invariant wins: the repair never moves a tab across the pinned
//  boundary, so such a group spans the boundary as at most two runs.
//
//  The canonical order is computed as: stable-partition into pinned prefix and
//  unpinned suffix, then within each class independently compact every group
//  into one block anchored at its first member in that class. The result is
//  idempotent, which every caller relies on (the repair runs inside
//  -tabsDidReorder; a non-idempotent repair would re-trigger itself forever).
//

import Foundation

@objc(iTermTabGroupOrdering)
class iTermTabGroupOrdering: NSObject {
    // Swift-native core (unit-tested directly). `groupIDs[i]` is tab i's group
    // id or nil; `pinned[i]` is whether tab i is pinned. Returns the canonical
    // permutation: result[k] is the index (into the input) of the tab that
    // belongs at position k.
    static func canonicalOrder(groupIDs: [String?], pinned: [Bool]) -> [Int] {
        it_assert(groupIDs.count == pinned.count, "parallel arrays required")
        func compacted(_ indices: [Int]) -> [Int] {
            var result: [Int] = []
            var placedGroups = Set<String>()
            for i in indices {
                guard let gid = groupIDs[i] else {
                    result.append(i)
                    continue
                }
                if placedGroups.contains(gid) {
                    continue  // already emitted with its group's block
                }
                placedGroups.insert(gid)
                result.append(contentsOf: indices.filter { groupIDs[$0] == gid })
            }
            return result
        }
        let pinnedIndexes = groupIDs.indices.filter { pinned[$0] }
        let unpinnedIndexes = groupIDs.indices.filter { !pinned[$0] }
        return compacted(pinnedIndexes) + compacted(unpinnedIndexes)
    }

    // ObjC bridge: `groupIDs` elements are NSString group ids or NSNull for
    // ungrouped tabs.
    @objc(canonicalOrderForGroupIDs:pinned:)
    static func canonicalOrder(groupIDs: [Any], pinned: [NSNumber]) -> [NSNumber] {
        return canonicalOrder(groupIDs: groupIDs.map { $0 as? String },
                              pinned: pinned.map { $0.boolValue }).map { NSNumber(value: $0) }
    }

    // The index of the nearest VISIBLE tab OUTSIDE `group`, used when collapsing a
    // group that holds the active tab: selection must move out of the group first,
    // so the invariant "the active tab is never in a collapsed group" holds. A tab
    // that is a hidden member of some OTHER collapsed group is NOT a valid landing
    // spot -- selecting it would auto-expand that group and yank focus into it -- so
    // `collapsed` (parallel to `order`; empty means treat all as visible) is used to
    // skip such tabs and land on the nearest genuinely visible one. nil when the
    // group is the whole window, or every tab outside it is hidden -> collapse is
    // refused. `order[i]` is tab i's group id or nil.
    //
    // A group is usually contiguous, but canonicalOrder deliberately leaves a group
    // whose members straddle the pinned boundary as up to two runs, so a valid
    // landing spot can lie BETWEEN the first and last member. Scan every index and
    // pick the visible non-member nearest any member (distance to the closest
    // member); among equal distances prefer the later tab, matching the
    // contiguous-group behavior of landing just after the group's last member.
    static func indexOfNearestTabOutsideGroup(order: [String?],
                                              collapsed: [Bool] = [],
                                              group gid: String) -> Int? {
        let memberIndexes = order.indices.filter { order[$0] == gid }
        guard !memberIndexes.isEmpty else {
            return nil  // no such group
        }
        func visibleOutside(_ i: Int) -> Bool {
            if order[i] == gid {
                return false  // still inside the group being collapsed
            }
            if i < collapsed.count && collapsed[i] {
                return false  // a hidden member of another collapsed group
            }
            return true
        }
        var best: Int? = nil
        var bestDistance = Int.max
        for i in order.indices where visibleOutside(i) {
            let distance = memberIndexes.map { abs($0 - i) }.min()!
            // Iterating ascending, a later tab with equal distance replaces the
            // earlier one, so ties resolve to the larger index (prefer-after).
            if distance <= bestDistance {
                best = i
                bestDistance = distance
            }
        }
        return best
    }

    // The invariant predicate: the active tab is not a member of a collapsed
    // group. Pure, for tests over reorder/collapse sequences.
    static func activeTabNotInCollapsedGroup(groupIDs: [String?],
                                             collapsed: [Bool],
                                             activeIndex: Int) -> Bool {
        it_assert(groupIDs.count == collapsed.count, "parallel arrays required")
        guard activeIndex >= 0, activeIndex < groupIDs.count else {
            return true
        }
        if groupIDs[activeIndex] == nil {
            return true
        }
        return !collapsed[activeIndex]
    }

    // ObjC bridge: `order` elements are NSString group ids or NSNull; `collapsed`
    // is a parallel array of NSNumber booleans. Returns the index as an NSNumber,
    // or nil when there is no visible tab outside the group.
    @objc(indexOfNearestTabOutsideGroupInOrder:collapsed:group:)
    static func indexOfNearestTabOutsideGroup(order: [Any],
                                              collapsed: [NSNumber],
                                              group gid: String) -> NSNumber? {
        guard let index = indexOfNearestTabOutsideGroup(order: order.map { $0 as? String },
                                                        collapsed: collapsed.map { $0.boolValue },
                                                        group: gid) else {
            return nil
        }
        return NSNumber(value: index)
    }
}

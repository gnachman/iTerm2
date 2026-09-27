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

    // MARK: - Single-tab keyboard move (Move Tab Left/Right)

    // One step of moving a single tab one position in `offset`'s direction
    // (+1 = right, -1 = left), with group membership changing at boundaries so
    // the tab enters or exits a group instead of the whole group moving as a
    // unit. Pure logic; the pinned-prefix and contiguity invariants are enforced
    // afterward by canonicalOrder, so this ignores pinning. Rules for the tab at
    // `selectedIndex` (group id `g`), looking at the neighbor it would cross:
    //   - g is set with other members, neighbor is the same group: swap within
    //     the group (a move).
    //   - g is set with other members, neighbor differs or the tab is at the
    //     group's edge in the travel direction: leave the group (membership ->
    //     nil, no move) -- it separates from the siblings it leaves behind.
    //   - g is set and the tab is the group's ONLY member: there are no siblings
    //     to separate from and the group would be pointless left in place, so the
    //     tab moves as a one-tab unit, keeping its group. It jumps the adjacent
    //     unit -- an ungrouped tab (a swap) or a whole group (leaping the block to
    //     keep both groups contiguous) -- or wraps at the end.
    //   - g is nil, neighbor is in a group: join that group (no move).
    //   - g is nil, neighbor is ungrouped: swap (a move).
    //   - g is nil and there is no neighbor (tab at the end): wrap to the far end,
    //     matching the pre-group Move Tab behavior.
    static func singleTabMove(groupIDs: [String?],
                              selectedIndex s: Int,
                              offset: Int) -> SingleTabMove {
        let n = groupIDs.count
        guard n >= 2, s >= 0, s < n, offset != 0 else {
            return SingleTabMove(order: Array(0..<n), newGroupID: nil, changesMembership: false)
        }
        let identity = Array(0..<n)
        let dir = offset > 0 ? 1 : -1
        let g = groupIDs[s]
        let neighbor = s + dir
        let inGroup = (g != nil && !g!.isEmpty)
        let soleMember = inGroup && groupIDs.filter { $0 == g }.count == 1

        // Wrap an end tab (any kind) to the opposite end, keeping its membership.
        func wrapped() -> SingleTabMove {
            var order = identity
            order.remove(at: s)
            order.insert(s, at: dir > 0 ? 0 : n - 1)
            return SingleTabMove(order: order, newGroupID: nil, changesMembership: false)
        }

        if inGroup && !soleMember {
            if neighbor >= 0, neighbor < n, groupIDs[neighbor] == g {
                // Move within the group.
                var order = identity
                order.swapAt(s, neighbor)
                return SingleTabMove(order: order, newGroupID: nil, changesMembership: false)
            }
            // At the group's edge in the travel direction: leave the group in place.
            return SingleTabMove(order: identity, newGroupID: nil, changesMembership: true)
        }

        if soleMember {
            // A one-tab group moves as a unit, keeping its group.
            if neighbor < 0 || neighbor >= n {
                return wrapped()
            }
            // Span the adjacent unit: a whole group's run, or a single ungrouped
            // tab. Then place the tab on the far side of it.
            let ng = groupIDs[neighbor]
            var order = identity
            order.remove(at: s)
            if let ng, !ng.isEmpty {
                if dir > 0 {
                    var e = neighbor
                    while e < n && groupIDs[e] == ng { e += 1 }
                    order.insert(s, at: e - 1)  // just past the group's last member
                } else {
                    var b = neighbor
                    while b >= 0 && groupIDs[b] == ng { b -= 1 }
                    order.insert(s, at: b + 1)  // just before the group's first member
                }
            } else {
                order.insert(s, at: neighbor)  // swap with the lone neighbor
            }
            return SingleTabMove(order: order, newGroupID: nil, changesMembership: false)
        }

        // Ungrouped tab.
        if neighbor < 0 || neighbor >= n {
            return wrapped()
        }
        let ng = groupIDs[neighbor]
        if let ng, !ng.isEmpty {
            // Ungrouped tab crossing into a group: join it, in place.
            return SingleTabMove(order: identity, newGroupID: ng, changesMembership: true)
        }
        // Both ungrouped: plain swap.
        var order = identity
        order.swapAt(s, neighbor)
        return SingleTabMove(order: order, newGroupID: nil, changesMembership: false)
    }

    // ObjC bridge for -[PseudoTerminal moveCurrentTabByOffset:]. `groupIDs`
    // elements are NSString group ids or NSNull for ungrouped tabs.
    @objc(singleTabMoveForGroupIDs:selectedIndex:offset:)
    static func singleTabMove(groupIDs: [Any],
                              selectedIndex: Int,
                              offset: Int) -> SingleTabMove {
        return singleTabMove(groupIDs: groupIDs.map { $0 as? String },
                             selectedIndex: selectedIndex,
                             offset: offset)
    }
}

// The result of one single-tab keyboard move: the new tab order (as a
// permutation of input indices) plus, when the selected tab's group membership
// changes, its new group id (nil = ungrouped). When `changesMembership` is
// false the caller only reorders; `order` is the identity for a pure membership
// change.
@objc(iTermSingleTabMove)
class SingleTabMove: NSObject {
    @objc let order: [NSNumber]
    @objc let newGroupID: String?
    @objc let changesMembership: Bool

    init(order: [Int], newGroupID: String?, changesMembership: Bool) {
        self.order = order.map { NSNumber(value: $0) }
        self.newGroupID = newGroupID
        self.changesMembership = changesMembership
        super.init()
    }
}

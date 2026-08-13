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
}

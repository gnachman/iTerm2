//
//  iTermTabGroupNesting.swift
//  iTerm2SharedARC
//
//  Rules for making an existing tab group a sub-group of another one, or
//  making a sub-group top-level. Pure logic over parallel per-tab arrays (as in
//  iTermTabGroupOrdering): `groupIDs[i]` is tab i's own group and `parentIDs[i]`
//  that group's parent (nil for a top-level group or no group).
//

import Foundation

@objc(iTermTabGroupNesting)
final class iTermTabGroupNesting: NSObject {
    enum Refusal: Equatable {
        case noSuchGroup
        case noSuchParent
        case sameGroup
        case parentIsSubgroup
        case groupHasSubgroups

        // English, for the API's error and the debug log.
        var reason: String {
            switch self {
            case .noSuchGroup:
                return "No such tab group in this window"
            case .noSuchParent:
                return "No such parent tab group in this window"
            case .sameGroup:
                return "A tab group can't be nested in itself"
            case .parentIsSubgroup:
                return "The parent tab group is itself a sub-group; tab groups nest only one level deep"
            case .groupHasSubgroups:
                return "The tab group has sub-groups of its own; tab groups nest only one level deep"
            }
        }
    }

    // Why `groupID` can't become a sub-group of `parentID`, or nil if it can. A
    // nil `parentID` asks whether it can become top-level, which any existing
    // group can.
    static func refusal(nesting groupID: String,
                        in parentID: String?,
                        groupIDs: [String?],
                        parentIDs: [String?]) -> Refusal? {
        it_assert(groupIDs.count == parentIDs.count, "parallel arrays required")
        let indices = groupIDs.indices
        // A parent whose tabs are all in its sub-groups appears only in parentIDs.
        guard indices.contains(where: { groupIDs[$0] == groupID || parentIDs[$0] == groupID }) else {
            return .noSuchGroup
        }
        guard let parentID else {
            return nil
        }
        if parentID == groupID {
            return .sameGroup
        }
        guard indices.contains(where: { groupIDs[$0] == parentID || parentIDs[$0] == parentID }) else {
            return .noSuchParent
        }
        if indices.contains(where: { groupIDs[$0] == parentID && parentIDs[$0] != nil }) {
            return .parentIsSubgroup
        }
        if indices.contains(where: { groupIDs[$0] != nil && parentIDs[$0] == groupID }) {
            return .groupHasSubgroups
        }
        return nil
    }

    @objc(refusalReasonForNestingGroup:inGroup:groupIDs:parentIDs:)
    static func refusalReason(nesting groupID: String,
                              in parentID: String?,
                              groupIDs: [Any],
                              parentIDs: [Any]) -> String? {
        return refusal(nesting: groupID,
                       in: parentID,
                       groupIDs: groupIDs.map { $0 as? String },
                       parentIDs: parentIDs.map { $0 as? String })?.reason
    }

    // The tab order after `groupID` moves under `parentID` (or, when nil, out of
    // the parent it has now), as a permutation of tab indices. The group's tabs
    // keep their order and go just past the last tab of the run they join or
    // leave, so a newly nested group is the parent's last member and a group
    // made top-level lands right after its old parent. Returns the identity when
    // there's no such run.
    static func order(moving groupID: String,
                      to parentID: String?,
                      groupIDs: [String?],
                      parentIDs: [String?]) -> [Int] {
        it_assert(groupIDs.count == parentIDs.count, "parallel arrays required")
        let identity = Array(groupIDs.indices)
        let moving = identity.filter { groupIDs[$0] == groupID }
        guard let first = moving.first else {
            return identity
        }
        guard let runID = parentID ?? parentIDs[first] else {
            return identity
        }
        let rest = identity.filter { groupIDs[$0] != groupID }
        guard let anchor = rest.lastIndex(where: { groupIDs[$0] == runID || parentIDs[$0] == runID }) else {
            return identity
        }
        var result = rest
        result.insert(contentsOf: moving, at: anchor + 1)
        return result
    }

    @objc(orderMovingGroup:toParent:groupIDs:parentIDs:)
    static func order(moving groupID: String,
                      to parentID: String?,
                      groupIDs: [Any],
                      parentIDs: [Any]) -> [NSNumber] {
        return order(moving: groupID,
                     to: parentID,
                     groupIDs: groupIDs.map { $0 as? String },
                     parentIDs: parentIDs.map { $0 as? String }).map { NSNumber(value: $0) }
    }

    // The groups that break the one-level rule: each has a parent and is itself
    // some group's parent, or is nested in itself. Listed once each, in tab
    // order; nestingDepthRepairs says how to fix them. `parentIDs[i]` must be
    // nil when `groupIDs[i]` is.
    static func groupsViolatingNestingDepth(groupIDs: [String?],
                                            parentIDs: [String?]) -> [String] {
        it_assert(groupIDs.count == parentIDs.count, "parallel arrays required")
        let parents = Set(parentIDs.compactMap { $0 })
        var result = [String]()
        for (groupID, parentID) in zip(groupIDs, parentIDs) {
            guard let groupID, let parentID, !result.contains(groupID) else {
                continue
            }
            if parentID == groupID || parents.contains(groupID) {
                result.append(groupID)
            }
        }
        return result
    }

    // Moves that bring a hierarchy deeper than one level back to the rule, to be
    // applied in order: every tab in `groupID` gets `newParentID` as its parent
    // (nil makes the group top-level). A violator normally becomes top-level,
    // keeping its sub-groups. But a parent with no direct tabs exists only on
    // its sub-groups' tabs, so if the violator is the last thing in its parent,
    // promoting it would erase the parent's name and color. Then the violator
    // stays put and its own sub-groups move up beside it instead.
    static func nestingDepthRepairs(groupIDs: [String?],
                                    parentIDs: [String?]) -> [iTermTabGroupNestingRepair] {
        it_assert(groupIDs.count == parentIDs.count, "parallel arrays required")
        var parents = parentIDs
        var result = [iTermTabGroupNestingRepair]()
        func move(_ groupID: String, to newParentID: String?) {
            for i in groupIDs.indices where groupIDs[i] == groupID {
                parents[i] = newParentID
            }
            result.append(iTermTabGroupNestingRepair(groupID: groupID, newParentID: newParentID))
        }
        // Each step un-nests some tabs or moves some up a level, so this is
        // ample. The bound only guards against a hang on input I didn't foresee.
        for _ in 0...(2 * groupIDs.count) {
            guard let violator = groupsViolatingNestingDepth(groupIDs: groupIDs, parentIDs: parents).first,
                  let i = groupIDs.firstIndex(of: violator),
                  let parentID = parents[i] else {
                break
            }
            let parentOutlivesPromotion = groupIDs.indices.contains {
                groupIDs[$0] == parentID || (parents[$0] == parentID && groupIDs[$0] != violator)
            }
            if parentID == violator || parentOutlivesPromotion {
                move(violator, to: nil)
                continue
            }
            var children = [String]()
            for j in groupIDs.indices where parents[j] == violator {
                if let child = groupIDs[j], child != violator, !children.contains(child) {
                    children.append(child)
                }
            }
            for child in children {
                move(child, to: parentID)
            }
        }
        return result
    }

    @objc(nestingDepthRepairsWithGroupIDs:parentIDs:)
    static func nestingDepthRepairs(groupIDs: [Any], parentIDs: [Any]) -> [iTermTabGroupNestingRepair] {
        return nestingDepthRepairs(groupIDs: groupIDs.map { $0 as? String },
                                   parentIDs: parentIDs.map { $0 as? String })
    }
}

@objc(iTermTabGroupNestingRepair)
final class iTermTabGroupNestingRepair: NSObject {
    @objc let groupID: String
    @objc let newParentID: String?

    init(groupID: String, newParentID: String?) {
        self.groupID = groupID
        self.newParentID = newParentID
    }

    override var description: String {
        return "\(groupID)→\(newParentID ?? "top level")"
    }
}

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
}

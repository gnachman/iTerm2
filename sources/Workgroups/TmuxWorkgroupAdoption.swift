//
//  TmuxWorkgroupAdoption.swift
//  iTerm2SharedARC
//
//  Deciding what to do with the workgroup instances on a tmux server, from what tmux reports.
//  Pure: no sessions, no I/O. TmuxWorkgroupAttacher queries tmux and carries the steps out.
//
//  Everything parsed here came from tmux and may be attacker-controlled; it is validated by
//  TmuxWorkgroupState's decoders, and only selects among the user's own workgroups.
//

import Foundation

enum TmuxWorkgroupAdoption {
    typealias S = TmuxWorkgroupState

    // MARK: - Queries

    /// Sent as one command list so the replies are a consistent snapshot: tmux does not run another
    /// client's commands in the middle of a list.
    static func queries(sessionID: Int) -> [String] {
        return ["show -q -t $\(sessionID)",
                "list-panes -s -t $\(sessionID) -F '#{pane_id} #{window_id} #{pane_width}x#{pane_height} #{\(S.paneOptionName)}'",
                "list-windows -t $\(sessionID) -F '#{window_id} #{\(S.parkedOptionName)}'"]
    }

    /// Instance option values by instance ID, from a `show` reply. Other options are ignored.
    static func instanceOptions(showReply: String) -> [String: String] {
        var result = [String: String]()
        for line in showReply.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 1)
            guard fields.count == 2, let instanceID = S.instanceID(fromOptionName: String(fields[0])) else {
                continue
            }
            result[instanceID] = String(fields[1])
        }
        return result
    }

    static func panes(listPanesReply: String) -> [S.Pane] {
        return listPanesReply.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count >= 2,
                  let paneID = id(fields[0], prefix: "%"),
                  let windowID = id(fields[1], prefix: "@") else {
                return nil
            }
            return S.Pane(paneID: paneID, windowID: windowID, tag: tagField(fields, at: 3),
                          size: fields.count > 2 ? size(fields[2]) : nil)
        }
    }

    static func windows(listWindowsReply: String) -> [S.Window] {
        return listWindowsReply.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            guard let windowID = fields.first.flatMap({ id($0, prefix: "@") }) else {
                return nil
            }
            return S.Window(windowID: windowID, parkedTag: tagField(fields, at: 1))
        }
    }

    private static func id(_ field: Substring, prefix: String) -> Int? {
        guard field.hasPrefix(prefix) else {
            return nil
        }
        let digits = field.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        return Int(digits)
    }

    /// "<width>x<height>", both positive.
    private static func size(_ field: Substring) -> S.PaneSize? {
        let parts = field.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let width = number(parts[0]), let height = number(parts[1]),
              width > 0, height > 0 else {
            return nil
        }
        return S.PaneSize(width: width, height: height)
    }

    private static func number(_ field: Substring) -> Int? {
        guard !field.isEmpty, field.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        return Int(field)
    }

    private static func tagField(_ fields: [Substring], at index: Int) -> String? {
        guard index < fields.count, !fields[index].isEmpty else {
            return nil
        }
        return String(fields[index])
    }

    // MARK: - Planning

    /// What adopting an instance with a local workgroup takes.
    struct Adoption: Equatable {
        var instanceID: String
        var workgroup: iTermWorkgroup
        var gitBase: String
        var leaderPaneID: Int
        /// Split and tab members with panes.
        var memberPaneIDsByConfigID: [String: Int]
        /// Peers with panes, of the leader's group and of nested groups (a split or tab that hosts
        /// peers), whether in view or parked.
        var peerPaneIDsByConfigID: [String: Int]
        /// The member of the leader's group in view: the leader unless a peer is.
        var activeConfigID: String
        /// For each nested group with a member in view, by its host's config ID, that member.
        var nestedActiveConfigIDs: [String: String] = [:]
    }

    enum Step: Equatable {
        case adopt(Adoption)
        /// Several local workgroups have the shape and none is the one it was entered from.
        case choose(instance: TmuxWorkgroupState.Instance, candidates: [iTermWorkgroup])
        /// No local workgroup has the shape. Its panes stay ordinary.
        case unmatched(instanceID: String)
        /// Its leader is gone: the instance has ended, but nobody removed it.
        case removeFromServer(instanceID: String)
        /// Adopted here, but its record is gone: another client ended it.
        case forget(instanceID: String)
        /// Tags left by an interrupted removal: kill the members, only untag the leaders.
        case cleanUpOrphans(killPaneIDs: [Int], untagPaneIDs: [Int])
    }

    /// - Parameter adoptedHere: Instances this client already has, entered or adopted, as of when
    ///   the query was sent (so one entered since then is not mistaken for one that ended).
    static func plan(derivation: TmuxWorkgroupState.Derivation,
                     localWorkgroups: [iTermWorkgroup],
                     adoptedHere: Set<String>) -> [Step] {
        var steps = [Step]()
        for instance in derivation.instances {
            if instance.problems.contains(.leaderMissing) {
                steps.append(.removeFromServer(instanceID: instance.instanceID))
                continue
            }
            if adoptedHere.contains(instance.instanceID) {
                continue
            }
            switch S.match(instance.record, among: localWorkgroups) {
            case .unique(let workgroup):
                if let step = adoptStep(instance: instance, workgroup: workgroup) {
                    steps.append(step)
                }
            case .ambiguous(let candidates):
                steps.append(.choose(instance: instance, candidates: candidates))
            case .noMatch:
                steps.append(.unmatched(instanceID: instance.instanceID))
            }
        }
        let present = Set(derivation.instances.map(\.instanceID)).union(derivation.undecodableInstanceIDs)
        for instanceID in adoptedHere.sorted() where !present.contains(instanceID) {
            steps.append(.forget(instanceID: instanceID))
        }
        if !derivation.orphanMemberPaneIDs.isEmpty || !derivation.orphanLeaderPaneIDs.isEmpty {
            steps.append(.cleanUpOrphans(killPaneIDs: derivation.orphanMemberPaneIDs,
                                         untagPaneIDs: derivation.orphanLeaderPaneIDs))
        }
        return steps
    }

    /// The adopt step for an instance and a local workgroup with the same skeleton. Nil if the
    /// leader has no pane or the workgroup's shape does not fit.
    static func adoptStep(instance: TmuxWorkgroupState.Instance, workgroup: iTermWorkgroup) -> Step? {
        guard let leaderPaneID = instance.paneForPosition[0],
              let configIDs = S.Skeleton.configIDsByPosition(in: workgroup),
              S.Skeleton(workgroup: workgroup) == instance.record.skeleton else {
            return nil
        }
        let nodes = instance.record.skeleton.nodes
        let leadersGroup = instance.peerGroups.first { $0.host == 0 }
        var members = [String: Int]()
        var peers = [String: Int]()
        for (position, paneID) in instance.paneForPosition where position > 0 && position < nodes.count {
            switch nodes[position].kind {
            case .split, .tab:
                members[configIDs[position]] = paneID
            case .peer:
                peers[configIDs[position]] = paneID
            case .root:
                break
            }
        }
        var nestedActive = [String: String]()
        for group in instance.peerGroups where group.host != 0 {
            if let visible = group.visible {
                nestedActive[configIDs[group.host]] = configIDs[visible]
            }
        }
        return .adopt(Adoption(instanceID: instance.instanceID,
                               workgroup: workgroup,
                               gitBase: instance.record.gitBase,
                               leaderPaneID: leaderPaneID,
                               memberPaneIDsByConfigID: members,
                               peerPaneIDsByConfigID: peers,
                               activeConfigID: configIDs[leadersGroup?.visible ?? 0],
                               nestedActiveConfigIDs: nestedActive))
    }
}

//
//  TmuxWorkgroupHiddenPanes.swift
//  iTerm2SharedARC
//
//  Panes in parked windows that no workgroup on this Mac can show. A parked window never becomes a
//  tab, so only an adopted instance's peer switcher reaches what is in it. Panes are hidden from
//  this Mac when their window is parked for an instance it has not adopted: one no local workgroup
//  matches, one whose choice of workgroup the user declined, one whose record this version cannot
//  read, or one whose record is gone. Nothing may stay hidden, so the user is offered to open them
//  in tabs or stop them (TmuxWorkgroupHiddenPaneOffer).
//
//  An instance a local workgroup matches is this Mac's even when it is not adopted at the
//  moment, as when its leader's window is hidden in iTerm2 so the leader has no session: its
//  peers are not offered, since opening or stopping them would take them from the workgroup.
//
//  An adopted instance's own stranded panes are repaired by its binding instead
//  (TmuxWorkgroupRepair), as are its members found in another instance's parked window.
//

import Foundation

enum TmuxWorkgroupHiddenPanes {
    typealias S = TmuxWorkgroupState

    /// The hidden panes of one instance's parked windows.
    struct Group: Equatable {
        var instanceID: String
        /// Sorted.
        var paneIDs: [Int]
        /// The instance is still on the server, so another Mac may be using these panes as its peers.
        var inUseElsewhere: Bool
        /// The instance's leader, which is in view here, if it has one.
        var leaderPaneID: Int?
    }

    /// Instances whose parked panes are not offered: those adopted here, and those a local
    /// workgroup matches that the user did not decline, adopted or not.
    static func instancesOfThisMac(derivation: S.Derivation,
                                   localWorkgroups: [iTermWorkgroup],
                                   adoptedHere: Set<String>,
                                   declined: Set<String>) -> Set<String> {
        var result = adoptedHere
        for instance in derivation.instances where !declined.contains(instance.instanceID) {
            if S.match(instance.record, among: localWorkgroups) != .noMatch {
                result.insert(instance.instanceID)
            }
        }
        return result
    }

    /// Sorted by instance ID.
    static func find(panes: [S.Pane],
                     windows: [S.Window],
                     derivation: S.Derivation,
                     adoptedHere: Set<String>) -> [Group] {
        var instanceForParkedWindow = [Int: String]()
        for window in windows {
            if let raw = window.parkedTag, let tag = S.ParkedTag(encoded: raw) {
                instanceForParkedWindow[window.windowID] = tag.instanceID
            }
        }
        let instances = Dictionary(derivation.instances.map { ($0.instanceID, $0) }, uniquingKeysWith: { first, _ in first })
        // An instance whose leader is gone is being removed, members and all.
        let beingRemoved = Set(derivation.instances.filter { $0.problems.contains(.leaderMissing) }.map(\.instanceID))
        let live = Set(instances.keys).union(derivation.undecodableInstanceIDs)
        // Killed by the adoption plan's clean-up.
        let orphanMembers = Set(derivation.orphanMemberPaneIDs)

        var paneIDsByInstance = [String: [Int]]()
        for pane in panes {
            guard let instanceID = instanceForParkedWindow[pane.windowID],
                  !adoptedHere.contains(instanceID),
                  !beingRemoved.contains(instanceID),
                  !orphanMembers.contains(pane.paneID) else {
                continue
            }
            if let tag = pane.tag.flatMap({ S.PaneTag(encoded: $0) }), adoptedHere.contains(tag.instanceID) {
                // A member of an instance adopted here: its binding brings it out.
                continue
            }
            paneIDsByInstance[instanceID, default: []].append(pane.paneID)
        }
        return paneIDsByInstance.keys.sorted().map { instanceID in
            Group(instanceID: instanceID,
                  paneIDs: paneIDsByInstance[instanceID]!.sorted(),
                  inUseElsewhere: live.contains(instanceID),
                  leaderPaneID: instances[instanceID]?.paneForPosition[0])
        }
    }
}

/// Opens or stops the hidden panes the user was offered, once the session's workgroup lock is held,
/// as a state machine with no I/O, like TmuxWorkgroupRepair. Each pane is handled in one command
/// list decided from a fresh snapshot, so a pane that another client already brought out, or that
/// exited, is skipped.
struct TmuxWorkgroupHiddenPaneRelease: TmuxWorkgroupLockedRepair {
    typealias Action = TmuxWorkgroupRepair.Action

    enum Choice: Equatable {
        /// Each pane, untagged so no workgroup parks it again, goes into an ordinary window,
        /// which clients show as a tab.
        case open
        case stop
    }

    private enum State {
        case idle
        case snapshotting
        case releasing
        case done
    }

    let sessionID: Int
    let instanceID: String
    let choice: Choice
    private let offered: Set<Int>
    private let adoptedHere: Set<String>
    private let limit: Int
    private var state = State.idle
    private var released = 0

    /// - Parameter adoptedHere: Instances adopted on this connection when the user chose.
    init(sessionID: Int, instanceID: String, paneIDs: [Int], choice: Choice, adoptedHere: Set<String>) {
        self.sessionID = sessionID
        self.instanceID = instanceID
        self.choice = choice
        offered = Set(paneIDs)
        self.adoptedHere = adoptedHere
        // One step per pane, so a server that never settles can't keep a client at it.
        limit = paneIDs.count
    }

    mutating func start() -> Action? {
        guard state == .idle else {
            return nil
        }
        guard limit > 0 else {
            state = .done
            return .finished(repairs: 0)
        }
        state = .snapshotting
        return .snapshot(TmuxWorkgroupAdoption.queries(sessionID: sessionID))
    }

    mutating func didSnapshot(_ replies: [String?]) -> Action? {
        guard state == .snapshotting else {
            return nil
        }
        guard replies.count == 3, let options = replies[0], let paneReply = replies[1], let windowReply = replies[2] else {
            state = .done
            return .abandoned
        }
        let panes = TmuxWorkgroupAdoption.panes(listPanesReply: paneReply)
        let windows = TmuxWorkgroupAdoption.windows(listWindowsReply: windowReply)
        let derivation = TmuxWorkgroupState.derive(panes: panes,
                                                   windows: windows,
                                                   instanceOptions: TmuxWorkgroupAdoption.instanceOptions(showReply: options))
        let group = TmuxWorkgroupHiddenPanes.find(panes: panes,
                                                  windows: windows,
                                                  derivation: derivation,
                                                  adoptedHere: adoptedHere).first { $0.instanceID == instanceID }
        guard let paneID = group?.paneIDs.first(where: { offered.contains($0) }),
              let windowID = panes.first(where: { $0.paneID == paneID })?.windowID else {
            state = .done
            return .finished(repairs: released)
        }
        state = .releasing
        switch choice {
        case .open:
            let sharesWindow = panes.filter { $0.windowID == windowID }.count > 1
            return .repair(TmuxWorkgroupCommands.releasePane(paneID: paneID) +
                           TmuxWorkgroupCommands.bringOutPane(sessionID: sessionID,
                                                              paneID: paneID,
                                                              windowID: windowID,
                                                              sharesWindow: sharesWindow))
        case .stop:
            return .repair([TmuxWorkgroupCommands.killPane(paneID)])
        }
    }

    mutating func didRepair() -> Action? {
        guard state == .releasing else {
            return nil
        }
        released += 1
        guard released < limit else {
            state = .done
            return .finished(repairs: released)
        }
        state = .snapshotting
        return .snapshot(TmuxWorkgroupAdoption.queries(sessionID: sessionID))
    }
}

//
//  TmuxWorkgroupRepair.swift
//  iTerm2SharedARC
//
//  Repairing an instance's state on the tmux server, once the session's workgroup lock is held, as
//  a state machine with no I/O. A crash, a lost connection, or someone working in tmux directly can
//  leave what TmuxWorkgroupState reports as problems: two panes claiming one member, a tag naming
//  no member, a peer group with two members in view or none, or a pane stranded in a parked window.
//
//  Each repair is one command list (TmuxWorkgroupCommands.parkPane, bringOutPane, untagPane),
//  decided from a fresh snapshot, and is followed by another snapshot that shows what is left. So
//  clients repairing at once, which the lock serializes, or a client that crashes partway, leave
//  the next one only what is still wrong. Nothing the user runs is killed: a pane that is not a
//  member is untagged, and panes are moved, never closed. An instance whose leader is gone is being
//  removed and is left alone.
//

import Foundation

/// Work done on the server while holding the session's workgroup lock (TmuxWorkgroupRepairer): a
/// snapshot, then one command list, and again until nothing is left.
protocol TmuxWorkgroupLockedRepair {
    mutating func start() -> TmuxWorkgroupRepair.Action?
    mutating func didSnapshot(_ replies: [String?]) -> TmuxWorkgroupRepair.Action?
    mutating func didRepair() -> TmuxWorkgroupRepair.Action?
}

struct TmuxWorkgroupRepair: TmuxWorkgroupLockedRepair {
    enum Action: Equatable {
        /// Send as one list; report with didSnapshot(_:).
        case snapshot([String])
        /// Send as one list; report with didRepair().
        case repair([String])
        /// Nothing (more) to repair, or the limit was reached.
        case finished(repairs: Int)
        /// The instance is gone, unreadable, or tmux could not say.
        case abandoned
    }

    private enum State {
        case idle
        case snapshotting
        case repairing
        case done
    }

    /// Repairs in one run. A server that never settles, or a fake one, can't keep a client at it.
    static let defaultLimit = 8

    let sessionID: Int
    let instanceID: String
    private let limit: Int
    private var state = State.idle
    private var repairs = 0

    init(sessionID: Int, instanceID: String, limit: Int = TmuxWorkgroupRepair.defaultLimit) {
        self.sessionID = sessionID
        self.instanceID = instanceID
        self.limit = limit
    }

    mutating func start() -> Action? {
        guard state == .idle else {
            return nil
        }
        state = .snapshotting
        return .snapshot(TmuxWorkgroupAdoption.queries(sessionID: sessionID))
    }

    mutating func didSnapshot(_ replies: [String?]) -> Action? {
        guard state == .snapshotting else {
            return nil
        }
        guard replies.count == 3, let options = replies[0], let paneReply = replies[1], let windows = replies[2] else {
            state = .done
            return .abandoned
        }
        let panes = TmuxWorkgroupAdoption.panes(listPanesReply: paneReply)
        let derivation = TmuxWorkgroupState.derive(
            panes: panes,
            windows: TmuxWorkgroupAdoption.windows(listWindowsReply: windows),
            instanceOptions: TmuxWorkgroupAdoption.instanceOptions(showReply: options))
        guard let instance = derivation.instances.first(where: { $0.instanceID == instanceID }) else {
            state = .done
            return .abandoned
        }
        guard let commands = Self.nextRepair(instance: instance, panes: panes, sessionID: sessionID) else {
            state = .done
            return .finished(repairs: repairs)
        }
        state = .repairing
        return .repair(commands)
    }

    mutating func didRepair() -> Action? {
        guard state == .repairing else {
            return nil
        }
        repairs += 1
        guard repairs < limit else {
            state = .done
            return .finished(repairs: repairs)
        }
        state = .snapshotting
        return .snapshot(TmuxWorkgroupAdoption.queries(sessionID: sessionID))
    }

    /// The command list that repairs the first of the instance's problems, or nil if there is
    /// nothing to repair.
    static func nextRepair(instance: TmuxWorkgroupState.Instance,
                           panes: [TmuxWorkgroupState.Pane],
                           sessionID: Int) -> [String]? {
        guard !instance.problems.contains(.leaderMissing) else {
            return nil
        }
        let windowOfPane = Dictionary(panes.map { ($0.paneID, $0.windowID) }, uniquingKeysWith: { first, _ in first })
        let panesPerWindow = Dictionary(grouping: panes, by: \.windowID).mapValues(\.count)
        func sharesWindow(_ paneID: Int) -> Bool {
            return windowOfPane[paneID].map { (panesPerWindow[$0] ?? 0) > 1 } ?? false
        }
        for problem in instance.problems {
            switch problem {
            case let .duplicateMember(_, paneID), let .unknownPosition(paneID, _):
                return TmuxWorkgroupCommands.releasePane(paneID: paneID)
            case .leaderMissing:
                return nil
            case let .extraVisiblePeers(host, positions):
                guard let position = positions.first,
                      let paneID = instance.paneForPosition[position],
                      let windowID = windowOfPane[paneID] else {
                    continue
                }
                // The slot is the visible member's; without a size for it, the host's or the peer's own.
                let group = instance.peerGroups.first { $0.host == host }
                guard let size = group?.visible.flatMap({ instance.sizeForPosition[$0] }) ??
                        instance.sizeForPosition[position] else {
                    continue
                }
                return TmuxWorkgroupCommands.parkPane(sessionID: sessionID,
                                                      instanceID: instance.instanceID,
                                                      paneID: paneID,
                                                      windowID: windowID,
                                                      sharesWindow: sharesWindow(paneID),
                                                      width: size.width,
                                                      height: size.height)
            case let .noVisiblePeer(host):
                guard let group = instance.peerGroups.first(where: { $0.host == host }),
                      let position = group.hidden.contains(host) ? host : group.hidden.first,
                      let paneID = instance.paneForPosition[position],
                      let windowID = windowOfPane[paneID] else {
                    continue
                }
                return TmuxWorkgroupCommands.bringOutPane(sessionID: sessionID,
                                                          paneID: paneID,
                                                          windowID: windowID,
                                                          sharesWindow: sharesWindow(paneID))
            case let .strandedInParkedWindow(paneID):
                guard let windowID = windowOfPane[paneID] else {
                    continue
                }
                return TmuxWorkgroupCommands.bringOutPane(sessionID: sessionID,
                                                          paneID: paneID,
                                                          windowID: windowID,
                                                          sharesWindow: sharesWindow(paneID))
            }
        }
        return nil
    }
}

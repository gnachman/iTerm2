//
//  TmuxWorkgroupPeerCreation.swift
//  iTerm2SharedARC
//
//  Creating an instance's peers in tmux, once the session's workgroup lock is held, as a state
//  machine with no I/O. It takes a fresh snapshot, then creates only the requested peers that the
//  snapshot shows as missing, each complete in one command list: its parked window, both tags, and
//  the window pinned to the size of its group's visible slot (TmuxWorkgroupCommands.createParkedPeer).
//
//  A client can crash between any two lists. Nothing it leaves is half made: a peer exists complete
//  or not at all, so the next creation's snapshot finds what is there and creates the rest. That
//  makes creating the same at entry and on demand.
//

import Foundation

struct TmuxWorkgroupPeerCreation {
    enum Action: Equatable {
        /// Send as one list; report with didSnapshot(_:).
        case snapshot([String])
        /// Send as one list; report the first reply with didCreate(reply:).
        case create(position: Int, commands: [String])
        /// Positions created, by pane ID, and positions tmux would not create.
        case finished(created: [Int: Int], failed: [Int])
        /// The instance is gone, unreadable, or tmux could not say: nothing was created.
        case abandoned
    }

    private enum State {
        case idle
        case snapshotting
        case creating(position: Int)
        case done
    }

    /// Used when tmux reports no size for the slot.
    private static let defaultSize = TmuxWorkgroupState.PaneSize(width: 80, height: 24)

    let sessionID: Int
    let instanceID: String
    private let scriptsByPosition: [Int: String]
    private var state = State.idle
    private var pending = [(position: Int, size: TmuxWorkgroupState.PaneSize, waiting: Bool)]()
    private var created = [Int: Int]()
    private var failed = [Int]()

    /// - Parameter scriptsByPosition: The peers to create and what each runs.
    init(sessionID: Int, instanceID: String, scriptsByPosition: [Int: String]) {
        self.sessionID = sessionID
        self.instanceID = instanceID
        self.scriptsByPosition = scriptsByPosition
    }

    mutating func start() -> Action? {
        guard case .idle = state else {
            return nil
        }
        state = .snapshotting
        return .snapshot(TmuxWorkgroupAdoption.queries(sessionID: sessionID))
    }

    mutating func didSnapshot(_ replies: [String?]) -> Action? {
        guard case .snapshotting = state else {
            return nil
        }
        guard replies.count == 3, let options = replies[0], let panes = replies[1], let windows = replies[2] else {
            state = .done
            return .abandoned
        }
        let derivation = TmuxWorkgroupState.derive(
            panes: TmuxWorkgroupAdoption.panes(listPanesReply: panes),
            windows: TmuxWorkgroupAdoption.windows(listWindowsReply: windows),
            instanceOptions: TmuxWorkgroupAdoption.instanceOptions(showReply: options))
        guard let instance = derivation.instances.first(where: { $0.instanceID == instanceID }) else {
            state = .done
            return .abandoned
        }
        let nodes = instance.record.skeleton.nodes
        pending = scriptsByPosition.keys.sorted().compactMap { position in
            guard position < nodes.count,
                  nodes[position].kind == .peer,
                  instance.paneForPosition[position] == nil,
                  let group = instance.peerGroups.first(where: { $0.members.contains(position) }) else {
                return nil
            }
            // The slot is wherever the group's visible member is; failing that, any member's pane.
            let slot = group.visible.flatMap { instance.sizeForPosition[$0] } ??
                group.members.lazy.compactMap { instance.sizeForPosition[$0] }.first ??
                Self.defaultSize
            return (position, slot, TmuxWorkgroupState.startsWaiting(nodes[position].mode))
        }
        return next()
    }

    mutating func didCreate(reply: String?) -> Action? {
        guard case .creating(let position) = state else {
            return nil
        }
        if let paneID = TmuxWorkgroupCommands.paneID(fromReply: reply) {
            created[position] = paneID
        } else {
            failed.append(position)
        }
        return next()
    }

    private mutating func next() -> Action {
        guard !pending.isEmpty else {
            state = .done
            return .finished(created: created, failed: failed)
        }
        let (position, size, waiting) = pending.removeFirst()
        state = .creating(position: position)
        return .create(position: position,
                       commands: TmuxWorkgroupCommands.createParkedPeer(sessionID: sessionID,
                                                                        instanceID: instanceID,
                                                                        position: position,
                                                                        width: size.width,
                                                                        height: size.height,
                                                                        script: scriptsByPosition[position] ?? "",
                                                                        waiting: waiting))
    }
}

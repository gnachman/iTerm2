//
//  CompanionSessionLister.swift
//  iTerm2
//
//  Enumerates terminal sessions for the companion's Create screen, projecting
//  each PTYSession down to the wire-level CompanionSessionSummary (a session
//  reference + display text). Must run on the main thread, like all
//  iTermController access.
//

import Foundation
import CompanionProtocol

@MainActor
enum CompanionSessionLister {
    static func sessions() -> [CompanionSessionSummary] {
        guard let controller = iTermController.sharedInstance() else {
            return []
        }
        return controller.allSessions().map(summary(of:))
    }

    private static func summary(of session: PTYSession) -> CompanionSessionSummary {
        // Project the reload-durable stableID (the wire field is named `guid`
        // but the phone treats it opaquely and sends it back through
        // anySession(forReference:)), so a picked/linked session survives a
        // shell reload that rotates the guid.
        CompanionSessionSummary(guid: session.stableID,
                                name: session.name,
                                subtitle: session.subtitle ?? "")
    }

    /// The window > tab > pane hierarchy the phone's Sessions tab browses,
    /// with a peer level under panes that host a peer group.
    static func tree() -> CompanionSessionTree {
        guard let controller = iTermController.sharedInstance() else {
            return CompanionSessionTree(windows: [])
        }
        let windows = (controller.terminals() ?? []).enumerated().map { index, term -> CompanionSessionTree.Window in
            let tabs = (term.tabs() ?? []).map { tab -> CompanionSessionTree.Tab in
                let panes = (tab.sessions() ?? []).map { session -> CompanionSessionTree.Pane in
                    CompanionSessionTree.Pane(session: summary(of: session),
                                              peers: peers(of: session))
                }
                return CompanionSessionTree.Tab(title: tab.title, panes: panes)
            }
            let windowTitle = term.window().title
            return CompanionSessionTree.Window(
                title: windowTitle.isEmpty ? "Window \(index + 1)" : windowTitle,
                tabs: tabs)
        }
        return CompanionSessionTree(windows: windows)
    }

    /// All members of a pane's peer group, in toolbar order, when there is
    /// more than one (e.g. a workgroup with a Code Review peer). A pane with
    /// a single occupant returns [] so the phone doesn't add a useless level.
    private static func peers(of session: PTYSession) -> [CompanionSessionTree.Peer] {
        guard let port = session.peerPort else {
            return []
        }
        let members = port.realizedMembers
        guard members.count > 1 else {
            return []
        }
        let workgroupPort = port as? iTermWorkgroupPeerPort
        return members
            .sorted { lhs, rhs in
                (workgroupPort?.position(forPeerID: lhs.id) ?? 0)
                    < (workgroupPort?.position(forPeerID: rhs.id) ?? 0)
            }
            .map { member in
                CompanionSessionTree.Peer(
                    roleName: workgroupPort?.label(forPeerID: member.id) ?? member.session.name,
                    session: summary(of: member.session))
            }
    }
}

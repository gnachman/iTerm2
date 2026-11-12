//
//  WorkgroupPeerStartingDirectory.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/11/26.
//

import Foundation

/// Where a session that a workgroup opens beside its leader (a peer, split, or tab) starts.
///
/// The leader can be several kinds of session, and “its local directory” means something
/// different for each. Rather than ask every leader for one and count on later fallbacks to make
/// the answer harmless, the choice is made here, by kind.
///
/// A workgroup whose leader is in a tmux integration tab normally doesn't get here: its members are
/// tmux panes, started in the leader pane's directory as tmux reports it (see
/// TmuxWorkgroupBinding). Its leader gets here only when no binding could be made, such as for a
/// workgroup whose shape can't be stored on the tmux server, and then its members are ordinary
/// sessions on this Mac. (tmux older than 3.2 never gets this far: entry refuses it.)
enum WorkgroupPeerStartingDirectory: Equatable {
    /// On this Mac, where the leader is now: the shell the user is in, for a local session, or
    /// the pane's directory as tmux reports it, for a pane on a local tmux server.
    case leadersCurrentDirectory
    /// On the leader's host, in the leader's directory there. The launch plan takes it from
    /// WorkgroupRemoteHost.currentDirectory (see PTYSession.workgroupPeerLaunchCommand), so no
    /// directory on this Mac is involved.
    case leadersDirectoryOnHost
    /// On this Mac, in the home directory, because there is no local directory that corresponds
    /// to the leader's.
    case homeDirectory

    enum LeaderKind: Equatable, CustomStringConvertible {
        /// A shell on this Mac. That includes one running plain ssh: a peer can only run here, so
        /// it starts in the directory where the user ran ssh.
        case localShell
        /// On a host reached through SSH Integration, tmux integration panes included. Sessions
        /// the workgroup opens run on that host too.
        case sshIntegration
        /// A tmux integration pane whose server runs on this Mac.
        case tmuxLocalServer
        /// A tmux integration pane whose server is on another machine, or not yet known to be on
        /// this one. Its directory is a path on that machine. Here, it could name nothing (and
        /// the session would show a notice that its directory is unavailable) or an unrelated
        /// directory.
        case tmuxOtherServer

        var description: String {
            switch self {
            case .localShell: return "local shell"
            case .sshIntegration: return "SSH Integration"
            case .tmuxLocalServer: return "tmux pane on a local server"
            case .tmuxOtherServer: return "tmux pane on another or unknown server"
            }
        }
    }

    /// SSH Integration comes first: a tmux integration pane reached through it is on the host
    /// too.
    static func leaderKind(hasRemoteHost: Bool,
                           isTmuxClient: Bool,
                           tmuxServerKnownToBeLocal: Bool) -> LeaderKind {
        if hasRemoteHost {
            return .sshIntegration
        }
        if isTmuxClient {
            return tmuxServerKnownToBeLocal ? .tmuxLocalServer : .tmuxOtherServer
        }
        return .localShell
    }

    init(leaderKind: LeaderKind) {
        switch leaderKind {
        case .localShell, .tmuxLocalServer:
            self = .leadersCurrentDirectory
        case .sshIntegration:
            self = .leadersDirectoryOnHost
        case .tmuxOtherServer:
            self = .homeDirectory
        }
    }
}

extension PTYSession {
    /// `runsOnRemoteHost` is whether the new session runs on the leader's host: whether its
    /// workgroupRemoteHost is set. Pass that rather than reading remoteHostForNewWorkgroupPeer
    /// again, so this can't disagree with where the session actually runs.
    func workgroupLeaderKind(runsOnRemoteHost: Bool) -> WorkgroupPeerStartingDirectory.LeaderKind {
        let tmuxServerKnownToBeLocal: Bool
        if isTmuxClient, let controller = tmuxController {
            tmuxServerKnownToBeLocal = controller.serverLocalityKnown && controller.serverIsLocal
        } else {
            tmuxServerKnownToBeLocal = false
        }
        return WorkgroupPeerStartingDirectory.leaderKind(
            hasRemoteHost: runsOnRemoteHost,
            isTmuxClient: isTmuxClient,
            tmuxServerKnownToBeLocal: tmuxServerKnownToBeLocal)
    }

    /// The directory on this Mac to give the launch of a session the workgroup opens beside this
    /// leader. nil when it runs on the leader's host, which picks the directory there, or when it
    /// should start in the home directory. See WorkgroupPeerStartingDirectory and
    /// workgroupLeaderKind(runsOnRemoteHost:).
    func asyncWorkgroupPeerStartingDirectory(runsOnRemoteHost: Bool,
                                             _ completion: @escaping (String?) -> Void) {
        let kind = workgroupLeaderKind(runsOnRemoteHost: runsOnRemoteHost)
        switch WorkgroupPeerStartingDirectory(leaderKind: kind) {
        case .leadersDirectoryOnHost:
            DLog("Workgroup sessions beside \(guid) (\(kind)) start in the leader's directory on its host")
            completion(nil)
        case .homeDirectory:
            DLog("Workgroup sessions beside \(guid) (\(kind)) start in the home directory")
            completion(nil)
        case .leadersCurrentDirectory:
            asyncFreshInitialDirectoryForNewSession { [guid] pwd in
                DLog("Workgroup sessions beside \(guid) (\(kind)) start in \(pwd ?? "(none)")")
                completion(pwd)
            }
        }
    }
}

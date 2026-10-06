//
//  WorkgroupRemoteHost.swift
//  iTerm2SharedARC
//
//  Where a workgroup peer runs when its leader is on a host reached through SSH Integration: on
//  that host, not this Mac, since the files a diff or a code review looks at are there.
//
//  A peer connects the way the leader did, replaying every hop of the leader's chain, the way
//  Duplicate Session does. The last hop carries the peer's command as its remote command and
//  starts in the leader's directory. Only the connection is reused, never the leader's profile
//  command, which could run anything.
//
//  ITERM_WORKGROUP_ID rides in the command itself (env … /bin/sh -c '<command>'): the launch
//  request's environment only reaches the local it2ssh, and forwarding variables only works for
//  the first hop. /bin/sh runs the command whatever the remote login shell is; the login shell
//  has already read the user's profile, so PATH is the user's.
//

import Foundation

@objc(iTermWorkgroupRemoteHost)
final class WorkgroupRemoteHost: NSObject {
    /// The leader's chain, outermost first.
    let hops: [SSHReconnectionInfo]
    /// The leader's directory on the innermost host when the workgroup was entered.
    let directory: String?
    /// For looking the directory up again at launch when it was not known at entry (the leader's
    /// shell had not reported it yet). Weak: a peer must not keep its leader alive.
    private weak var leader: PTYSession?
    /// The SSH configuration of the session that made the first hop (which ssh, whether it uses
    /// SSH Integration).
    let sshConfig: [AnyHashable: Any]?

    init(hops: [SSHReconnectionInfo], directory: String?, sshConfig: [AnyHashable: Any]?,
         leader: PTYSession? = nil) {
        it_assert(!hops.isEmpty)
        self.hops = hops
        self.directory = directory
        self.sshConfig = sshConfig
        self.leader = leader
        super.init()
    }

    /// The leader's directory on the host: as of entry, or, if that was unknown, as of now.
    @MainActor
    var currentDirectory: String? {
        if let directory {
            return directory
        }
        guard let leader else {
            return nil
        }
        return Self.directory(of: leader)
    }

    /// The session's directory on its host: what its shell last reported, else what its
    /// connection last recorded.
    @MainActor
    private static func directory(of session: PTYSession) -> String? {
        if let path = session.genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String,
           !path.isEmpty {
            return path
        }
        return session.hostConductor?.currentDirectory
    }

    /// For a leader on a host reached through SSH Integration, its host; nil for a leader on this
    /// Mac. A tmux pane's chain is its gateway's.
    @MainActor
    static func forLeader(_ leader: PTYSession) -> WorkgroupRemoteHost? {
        guard let conductor = leader.hostConductor, conductor.framing else {
            return nil
        }
        let owner: PTYSession? = leader.conductor != nil ? leader : leader.tmuxGateway
        guard let owner, owner.conductor != nil else {
            return nil
        }
        let hops = owner.sshCommandLineSequence?.map(\.state) ?? []
        guard !hops.isEmpty else {
            return nil
        }
        let directory = Self.directory(of: leader)
        DLog("Workgroup peer of \(leader.guid) will run on its host, directory \(directory ?? "(unknown at entry)")")
        return WorkgroupRemoteHost(
            hops: hops,
            directory: directory,
            sshConfig: owner.profile?[KEY_SSH_CONFIG] as? [AnyHashable: Any],
            leader: leader)
    }

    struct LaunchPlan {
        /// The ssh arguments the local it2ssh connects with.
        let firstHopArguments: String
        /// The session's pending jumps: the first is the first hop (for its directory), the rest
        /// are replayed from there, the last running the command.
        let jumps: [SSHReconnectionInfo]
    }

    /// An empty `remoteCommand` means an interactive login shell on the host.
    func launchPlan(remoteCommand: String, workgroupInstanceID: String?,
                    directory: String? = nil) -> LaunchPlan {
        let directory = directory ?? self.directory
        var command: String?
        if !remoteCommand.isEmpty {
            var wrapped = "/bin/sh -c " + Self.shellQuote(remoteCommand)
            if let workgroupInstanceID {
                wrapped = "env ITERM_WORKGROUP_ID=" + Self.shellQuote(workgroupInstanceID) + " " + wrapped
            }
            command = wrapped
        }
        var jumps = hops
        let last = jumps.count - 1
        for i in jumps.indices {
            jumps[i].sshargs = ParsedSSHArguments.sshargs(jumps[i].sshargs,
                                                          booleanArgs: jumps[i].boolargs,
                                                          replacingCommandWith: i == last ? command : nil)
        }
        if let directory {
            jumps[last].initialDirectory = directory
        }
        return LaunchPlan(firstHopArguments: jumps[0].sshargs, jumps: jumps)
    }

    /// What the local session runs for `plan`: it2ssh (or ssh) with the first hop's arguments,
    /// through the login shell, as an SSH profile would.
    func localCommand(for plan: LaunchPlan) -> String {
        let profile: [AnyHashable: Any] = [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeSSHValue,
                                           KEY_SSH_CONFIG: sshConfig ?? [:]]
        return ITAddressBookMgr.command(byWrappingCommandLine: plan.firstHopArguments, forProfile: profile)
    }

    /// Writes the code review's input files to ~/.iterm2/code-review on the host, over the
    /// leader's connection (the same host), and delivers their paths there, or nil if the leader
    /// is gone or a write failed. `name` keeps each review peer's system prompt apart.
    @MainActor
    func writeCodeReviewInputs(systemPrompt: String,
                               settings: Data,
                               name: String,
                               completion: @escaping ((systemPrompt: String, settings: String)?) -> Void) {
        guard let conductor = leader?.hostConductor, conductor.framing,
              let home = conductor.homeDirectory, !home.isEmpty else {
            RLog("Code review inputs not written: the leader's connection is gone")
            completion(nil)
            return
        }
        let directory = (home as NSString).appendingPathComponent(".iterm2/code-review")
        let promptPath = (directory as NSString).appendingPathComponent("system-prompt-\(name).txt")
        let settingsPath = (directory as NSString).appendingPathComponent("settings.txt")
        let files = ConductorClaudeCodeRemoteFiles(conductor: conductor)
        Task { @MainActor in
            guard await files.write(promptPath, Data(systemPrompt.utf8)),
                  await files.write(settingsPath, settings) else {
                RLog("Code review inputs could not be written to the remote host")
                completion(nil)
                return
            }
            completion((promptPath, settingsPath))
        }
    }

    private static func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

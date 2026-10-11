//
//  TmuxWorkgroupCommands.swift
//  iTerm2SharedARC
//
//  tmux commands that change a workgroup's state when several iTerm2s may be attached to the same
//  session. tmux runs one client's command list without interleaving another client's, which
//  gives two tools:
//    - Guards. A change that depends on where panes are is a single `if -F` whose condition tmux
//      evaluates when it runs, so a client acting on a stale picture changes nothing. Each branch
//      is exactly one command, so tmux always sends two reply blocks (a branch that runs gets a
//      block of its own); the second is empty when the action ran, holds guardFailedMarker when the
//      guard did not hold, and is an error when the action failed. A failure inside a branch does
//      not stop the rest of a list, so a guard is never followed by dependent commands in a list.
//    - A per-session lock for work that takes several round trips (creating a pane and then
//      tagging it). `set -o` fails when the option is set and the failure stops the rest of its
//      list. A lock names its holder by `#{client_pid}:#{client_created}`; tmux has no client ID
//      that is never reused, and this one would repeat only if a PID wrapped around onto a new
//      client within the same second. A lock whose holder is not connected may be evicted, by a
//      guard on the lock still holding that value, so two evicting clients cannot both win.
//  Verified on tmux 3.2a and 3.7c with two control-mode clients.
//
//  Everything sent is fixed text, IDs that are integers, or lowercase hex we produced or validated:
//  what tmux reports may come from a fake server, and iTerm2's commands are then typed into a shell.
//

import Foundation

enum TmuxWorkgroupCommands {
    static let guardFailedMarker = "iterm2_wg_guard_failed"
    static let lockOptionName = "@iterm2_wg_lock"

    /// What a guarded command's second reply block says.
    enum GuardOutcome: Equatable {
        case applied
        case guardFailed
        /// The action ran and failed, or the guard itself could not be evaluated (e.g. its target
        /// window is gone). Either way, re-derive from what tmux reports.
        case failed

        /// - Parameter branchReply: The second block's text, or nil if it was an error.
        init(branchReply: String?) {
            switch branchReply {
            case nil:
                self = .failed
            case TmuxWorkgroupCommands.guardFailedMarker:
                self = .guardFailed
            default:
                self = .applied
            }
        }
    }

    private static func guarded(target: String, condition: String, action: String) -> String {
        return "if -F -t \(target) '\(condition)' '\(action)' 'display -p \(guardFailedMarker)'"
    }

    /// True if the pane is in one of the instance's parked windows. The parked panes are listed by
    /// looping over every window in the session for the parked tag, so the guard is evaluated
    /// against the session; spaces around the IDs keep %3 from matching %30. Verified on tmux 3.2a
    /// and 3.7c with `if -F`. (`display -p` evaluates this match as 0, so it is no way to check it.)
    private static func isParked(_ paneID: Int, instanceID: String) -> String {
        let tag = TmuxWorkgroupState.ParkedTag(instanceID: instanceID).encoded
        let parked = "#{W:#{?#{==:#{\(TmuxWorkgroupState.parkedOptionName)},\(tag)},#{P:#{pane_id} },}}"
        return "#{m:* %\(paneID) *, \(parked)}"
    }

    // MARK: - Panes

    /// Bring a parked peer into view in place of the visible one, if the target is still parked
    /// and the visible one still is not. The visible one takes the target's parked window.
    static func switchPeer(sessionID: Int, instanceID: String, visiblePaneID: Int, targetPaneID: Int) -> String {
        return guarded(target: "$\(sessionID)",
                       condition: "#{&&:\(isParked(targetPaneID, instanceID: instanceID)),#{!:\(isParked(visiblePaneID, instanceID: instanceID))}}",
                       action: "swap-pane -d -s %\(visiblePaneID) -t %\(targetPaneID)")
    }

    /// A new peer, parked: a window of its own running `script`, tagged as parked and its pane
    /// tagged as the member, in one list so no client ever sees the window untagged (a client that
    /// did would open it as a tab). The window is created after the last one, so `{end}` is it.
    /// The first reply is the new pane's ID. See waitingMemberOptions for `waiting`.
    static func createParkedPeer(sessionID: Int,
                                 instanceID: String,
                                 position: Int,
                                 width: Int,
                                 height: Int,
                                 script: String,
                                 waiting: Bool = false) -> [String] {
        let end = "'$\(sessionID):{end}'"
        let tag = TmuxWorkgroupState.PaneTag(instanceID: instanceID, position: position, waiting: waiting)
        return ["new-window -d -a -t \(end) -P -F '#{pane_id}' " + encodedCommand(script: script),
                "set -w -t \(end) \(TmuxWorkgroupState.parkedOptionName) \(TmuxWorkgroupState.ParkedTag(instanceID: instanceID).encoded)",
                "set -p -t \(end) \(TmuxWorkgroupState.paneOptionName) \(tag.encoded)"] +
            waitingMemberOptions(target: "-t \(end) ", tag: tag) +
            ["resize-window -t \(end) -x \(width) -y \(height)"]
    }

    /// Pin a parked peer's window to its slot's new size, if the peer is still parked: a client
    /// acting on a stale snapshot must not pin a window in view, which would then no longer follow
    /// the clients' size.
    static func repinParkedPeer(sessionID: Int, instanceID: String, paneID: Int, width: Int, height: Int) -> String {
        return guarded(target: "$\(sessionID)",
                       condition: isParked(paneID, instanceID: instanceID),
                       action: pinWindow(ofPaneID: paneID, width: width, height: height))
    }

    // MARK: - Repairs

    /// Moves a pane into a parked window of its own for the instance, pinned to its slot's size: a
    /// peer in view that should not be. A pane that shares its window is broken out into a new one.
    /// One alone in its window goes through a new window instead, because break-pane would keep its
    /// window and clients would not see it become parked: a placeholder starts in the new window,
    /// the two are swapped, and the old window, now holding the placeholder, is closed. One list, so
    /// no client sees the pane unparked in a new window. No pane ID ends a command but the last
    /// (see relaunchMember).
    static func parkPane(sessionID: Int,
                         instanceID: String,
                         paneID: Int,
                         windowID: Int,
                         sharesWindow: Bool,
                         width: Int,
                         height: Int) -> [String] {
        let end = "'$\(sessionID):{end}'"
        let tagAndPin = ["set -w -t \(end) \(TmuxWorkgroupState.parkedOptionName) \(TmuxWorkgroupState.ParkedTag(instanceID: instanceID).encoded)",
                         "resize-window -t \(end) -x \(width) -y \(height)"]
        if sharesWindow {
            return ["break-pane -d -a -s %\(paneID) -t \(end)"] + tagAndPin
        }
        return [placeholderWindow(end: end)] + tagAndPin +
            ["swap-pane -d -t %\(paneID) -s \(end)",
             "kill-window -t @\(windowID)"]
    }

    /// Moves a pane out of a parked window into an ordinary one, which clients show as a tab: a
    /// group's host when none of its members is in view, or a pane stranded in a parked window. As
    /// with parkPane, a pane alone in its window goes through a new window.
    static func bringOutPane(sessionID: Int, paneID: Int, windowID: Int, sharesWindow: Bool) -> [String] {
        let end = "'$\(sessionID):{end}'"
        if sharesWindow {
            return ["break-pane -d -a -s %\(paneID) -t \(end)"]
        }
        return [placeholderWindow(end: end),
                "swap-pane -d -t %\(paneID) -s \(end)",
                "kill-window -t @\(windowID)"]
    }

    private static func placeholderWindow(end: String) -> String {
        return "new-window -d -a -t \(end) -P -F '#{pane_id}' " + encodedCommand(script: waitingScript)
    }

    /// Size the window holding a pane, e.g. a parked peer's window to the slot it fills when shown.
    /// This makes the window's size manual, so attached clients no longer resize it.
    static func pinWindow(ofPaneID paneID: Int, width: Int, height: Int) -> String {
        return "resize-window -t %\(paneID) -x \(width) -y \(height)"
    }

    // MARK: - Members

    /// A command line for tmux that runs `script` with /bin/sh, as a remote workgroup member does
    /// (WorkgroupRemoteHost). It is given to tmux as separate arguments, so tmux runs it directly
    /// rather than through its default-shell, which may be tcsh or fish. The script travels only
    /// as octal escapes for printf (POSIX, unlike \x), and % is doubled so printf does not take it
    /// as a conversion. The line holds no quote from the script, so a shell that reads it from a
    /// fake server sees only arguments to a command that does not exist.
    static func encodedCommand(script: String) -> String {
        let escaped = script.utf8.map { byte -> String in
            byte == UInt8(ascii: "%") ? "%%" : String(format: "\\%03o", UInt32(byte))
        }.joined()
        return #"/bin/sh -c 'eval "$(printf ""# + escaped + #"")"'"#
    }

    /// The script a member runs: its command in `directory`. An empty command means an interactive
    /// login shell, as for a remote member with no command.
    static func memberScript(command: String, directory: String?) -> String {
        let run = command.isEmpty ? #"exec "${SHELL:-/bin/sh}" -l"# : command
        guard let directory else {
            return run
        }
        return "cd \(shellQuoted(directory)) 2>/dev/null; \(run)"
    }

    /// Split a pane and tag the new one, in one list so no client ever sees it untagged. Without -d
    /// the new pane becomes current, so an untargeted set -p tags it; last-pane then gives focus
    /// back to whichever pane had it. Clients are told only the final state (verified on tmux 3.2a
    /// and 3.7c). The first reply is the new pane's ID, which is unambiguous even if another client
    /// splits at the same moment.
    static func splitWindow(targetPaneID: Int,
                            settings: SplitSettings,
                            script: String,
                            tag: TmuxWorkgroupState.PaneTag) -> [String] {
        var args = ["split-window", "-P", "-F", "'#{pane_id}'"]
        switch settings.orientation {
        case .vertical:
            args.append("-h")
        case .horizontal:
            args.append("-v")
        }
        switch settings.side {
        case .leadingOrTop:
            args.append("-b")
        case .trailingOrBottom:
            break
        }
        let percent = max(1, min(99, Int((settings.location * 100).rounded())))
        args += ["-l", "\(percent)%", "-t", "%\(targetPaneID)", encodedCommand(script: script)]
        return [args.joined(separator: " "),
                "set -p \(TmuxWorkgroupState.paneOptionName) \(tag.encoded)"] +
            waitingMemberOptions(target: "", tag: tag) +
            ["last-pane -t %\(targetPaneID)"]
    }

    /// A new window after the last one, not selected, with its pane tagged in the same list ({end}
    /// is the window just created). The first reply is the new pane's ID.
    static func newWindow(sessionID: Int, script: String, tag: TmuxWorkgroupState.PaneTag) -> [String] {
        let end = "'$\(sessionID):{end}'"
        return ["new-window -d -a -t \(end) -P -F '#{pane_id}' " + encodedCommand(script: script),
                "set -p -t \(end) \(TmuxWorkgroupState.paneOptionName) \(tag.encoded)"] +
            waitingMemberOptions(target: "-t \(end) ", tag: tag)
    }

    /// A member created waiting (a code review or diff) keeps its pane when its program exits, as a
    /// local one shows that it ended until Reload, which respawns the pane.
    private static func waitingMemberOptions(target: String, tag: TmuxWorkgroupState.PaneTag) -> [String] {
        return tag.waiting ? ["set -p \(target)remain-on-exit on"] : []
    }

    /// Replace what a pane runs, e.g. a code review member started after its prompt is entered.
    static func respawnPane(paneID: Int, script: String) -> String {
        return "respawn-pane -k -t %\(paneID) " + encodedCommand(script: script)
    }

    // MARK: - Starting and relaunching members

    /// What a waiting member runs until it is started: nothing to see, and no shell to type into,
    /// since starting it replaces whatever runs. Run with memberScript, so it runs in the member's
    /// directory and a client starting it later reads that directory from tmux.
    static let waitingScript = "while :; do sleep 86400; done"

    /// Claims the first start of a waiting member by clearing its waiting flag, if it is still set,
    /// so that of several clients that would start it (each one's diff poller sees the changes),
    /// one does. The winner then relaunches it. A client that crashes in between leaves it started
    /// but still running the waiting script, until Reload.
    static func startWaitingMember(paneID: Int, tag: TmuxWorkgroupState.PaneTag) -> String {
        return guarded(target: "%\(paneID)",
                       condition: "#{==:#{\(TmuxWorkgroupState.paneOptionName)},\(tag.encoded)}",
                       action: tagPane(paneID: paneID, tag: tag.started))
    }

    /// How a member's program is replaced.
    enum RelaunchMethod: Equatable {
        /// respawn-pane: the member keeps its pane. tmux 3.8 and later.
        case respawn
        /// Before tmux 3.8, respawn-pane can crash the server: it drops the pane's buffered output
        /// while a control client still has some of it queued, and the server exits on a fatal
        /// error when it next writes to that client (fixed by tmux commit 4714f478). So the member
        /// gets a new pane instead, swapped into its place, and the old one is killed.
        case replace(sessionID: Int, instanceID: String)

        /// The first tmux whose respawn-pane is safe with control clients attached.
        static let safeRespawnVersion = "3.8"

        init(respawnIsSafe: Bool, sessionID: Int, instanceID: String) {
            self = respawnIsSafe ? .respawn : .replace(sessionID: sessionID, instanceID: instanceID)
        }
    }

    /// Replaces a member's program whatever it is doing, as Reload or picking a file in a diff does.
    /// A member still waiting is started by it, in the same list. With .replace, the new program
    /// starts in a window of its own (tagged parked, so no client opens it as a tab) and takes the
    /// member's tag; it is swapped into the member's place, and killing the old pane closes that
    /// window. One list, so no client sees two members at the position. The first reply is then
    /// the new pane's ID. `remainOnExit` is for the new pane; a respawned pane keeps its own.
    static func relaunchMember(paneID: Int,
                               script: String,
                               tag: TmuxWorkgroupState.PaneTag,
                               method: RelaunchMethod,
                               remainOnExit: Bool) -> [String] {
        switch method {
        case .respawn:
            return [respawnPane(paneID: paneID, script: script)] +
                (tag.waiting ? [tagPane(paneID: paneID, tag: tag.started)] : [])
        case let .replace(sessionID, instanceID):
            let end = "'$\(sessionID):{end}'"
            return ["new-window -d -a -t \(end) -P -F '#{pane_id}' " + encodedCommand(script: script),
                    "set -w -t \(end) \(TmuxWorkgroupState.parkedOptionName) \(TmuxWorkgroupState.ParkedTag(instanceID: instanceID).encoded)",
                    "set -p -t \(end) \(TmuxWorkgroupState.paneOptionName) \(tag.started.encoded)"] +
                (remainOnExit ? ["set -p -t \(end) remain-on-exit on"] : []) +
                // tmux cannot parse a list in which a pane ID is followed by the semicolon that
                // ends its command (verified on 3.2a and 3.7c), so the pane is not swap-pane's last
                // argument, and kill-pane comes last.
                ["swap-pane -d -t %\(paneID) -s \(end)",
                 killPane(paneID)]
        }
    }

    /// A member's tag and directory, read before relaunching it.
    static func memberQuery(paneID: Int) -> String {
        return "display -p -t %\(paneID) '#{\(TmuxWorkgroupState.paneOptionName)} #{pane_current_path}'"
    }

    /// The tag (nil unless it decodes) and the absolute directory, if tmux knows one: a pane whose
    /// program exited has none. The directory is from tmux, so it goes back only in a script.
    static func parseMemberQuery(_ reply: String?) -> (tag: TmuxWorkgroupState.PaneTag, directory: String?)? {
        guard let reply, let space = reply.firstIndex(of: " "),
              let tag = TmuxWorkgroupState.PaneTag(encoded: String(reply[..<space])) else {
            return nil
        }
        let directory = String(reply[reply.index(after: space)...])
        return (tag, isAbsolutePath(directory) ? directory : nil)
    }

    /// The server's home, where a code review's input files are written.
    static let homeQuery = "show-environment -g HOME"

    /// From tmux, so it goes back only in a script.
    static func home(fromReply reply: String?) -> String? {
        let prefix = "HOME="
        guard let reply, reply.hasPrefix(prefix) else {
            return nil
        }
        let home = String(reply.dropFirst(prefix.count))
        return isAbsolutePath(home) ? home : nil
    }

    static func isAbsolutePath(_ path: String) -> Bool {
        return path.hasPrefix("/") && !path.contains("\n")
    }

    /// Shell that writes `files` to `directory` (made if need be), readable only by the user, and
    /// exits if it cannot. For a code review's input files, written by the script that runs it.
    static func writeFilesScript(directory: String, files: [(name: String, contents: String)]) -> String {
        let writes = files.map { file in
            "printf '%s' \(shellQuoted(file.contents)) >\(shellQuoted(directory + "/" + file.name))"
        }
        return (["umask 077", "mkdir -p \(shellQuoted(directory))"] + writes).joined(separator: " && ") + " || exit 1"
    }

    private static func shellQuoted(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The pane ID tmux printed for `-P -F '#{pane_id}'`.
    static func paneID(fromReply reply: String?) -> Int? {
        guard let reply, reply.hasPrefix("%") else {
            return nil
        }
        let digits = reply.dropFirst()
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        return Int(digits)
    }

    static func tagPane(paneID: Int, tag: TmuxWorkgroupState.PaneTag) -> String {
        return "set -p -t %\(paneID) \(TmuxWorkgroupState.paneOptionName) \(tag.encoded)"
    }

    static func untagPane(paneID: Int) -> String {
        return "set -p -u -t %\(paneID) \(TmuxWorkgroupState.paneOptionName)"
    }

    static func setRecord(sessionID: Int, instanceID: String, record: TmuxWorkgroupState.InstanceRecord) -> String {
        return "set -t $\(sessionID) \(TmuxWorkgroupState.instanceOptionName(instanceID: instanceID)) \(record.encoded)"
    }

    static func unsetRecord(sessionID: Int, instanceID: String) -> String {
        return "set -u -t $\(sessionID) \(TmuxWorkgroupState.instanceOptionName(instanceID: instanceID))"
    }

    /// Ends an instance: untags its leader, if it still exists, and unsets its record, in one list.
    /// Its members are then killed one at a time (killPane), so one that is already gone fails
    /// alone rather than stopping the list. A crash in between leaves member tags with no record,
    /// which any client cleans up as orphans.
    static func endInstance(sessionID: Int, instanceID: String, leaderPaneID: Int?) -> [String] {
        return (leaderPaneID.map { [untagPane(paneID: $0)] } ?? []) +
            [unsetRecord(sessionID: sessionID, instanceID: instanceID)]
    }

    static func killPane(_ paneID: Int) -> String {
        return "kill-pane -t %\(paneID)"
    }

    // MARK: - Lock

    /// A control-mode client as tmux reports it.
    struct ClientIdentity: Equatable {
        var pid: Int
        var created: Int

        private static let lockPrefix = "l_"

        private struct Wire: Codable {
            var v: Int
            var p: Int
            var c: Int
        }

        init(pid: Int, created: Int) {
            self.pid = pid
            self.created = created
        }

        /// Parses "<pid>:<created>" as printed for `#{client_pid}:#{client_created}`. Strict: two
        /// non-negative decimal integers and nothing else.
        init?(reported: String) {
            let parts = reported.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (0x30...0x39).contains($0) } }),
                  let pid = Int(parts[0]),
                  let created = Int(parts[1]) else {
                return nil
            }
            self.init(pid: pid, created: created)
        }

        /// The connected clients in a `list-clients` reply. Lines that do not parse are ignored.
        static func parseClientList(_ reply: String) -> [ClientIdentity] {
            return reply.components(separatedBy: "\n").compactMap { ClientIdentity(reported: $0) }
        }

        /// The value of @iterm2_wg_lock while this client holds it: "l_<hex of JSON>".
        var lockValue: String {
            return TmuxWorkgroupState.encode(Wire(v: TmuxWorkgroupState.currentVersion, p: pid, c: created),
                                             prefix: Self.lockPrefix)
        }

        init?(lockValue: String) {
            guard let wire = TmuxWorkgroupState.decode(Wire.self, from: lockValue, prefix: Self.lockPrefix),
                  wire.v == TmuxWorkgroupState.currentVersion,
                  wire.p >= 0,
                  wire.c >= 0 else {
                return nil
            }
            self.init(pid: wire.p, created: wire.c)
        }

        /// Whether a value read from tmux may be sent back: our prefix and lowercase hex only.
        static func isWellFormedLockValue(_ value: String) -> Bool {
            return value.hasPrefix(lockPrefix) &&
                TmuxWorkgroupState.hexDecoded(String(value.dropFirst(lockPrefix.count))) != nil
        }
    }

    static let identityQuery = "display -p '#{client_pid}:#{client_created}'"

    /// Fails, stopping the rest of its list, if the lock is held.
    static func tryLock(sessionID: Int, identity: ClientIdentity) -> String {
        return "set -o -t $\(sessionID) \(lockOptionName) \(identity.lockValue)"
    }

    /// The holder, then the connected clients. Sent as one list so the holder is read first: a
    /// client that connected and took the lock after the client list was read would otherwise look
    /// dead.
    static func lockSnapshot(sessionID: Int) -> [String] {
        return ["show -v -q -t $\(sessionID) \(lockOptionName)",
                "list-clients -F '#{client_pid}:#{client_created}'"]
    }

    /// Take the lock from a holder that is gone, if it still holds it. Nil if the held value is not
    /// one we may echo.
    static func evictLock(sessionID: Int, heldValue: String, identity: ClientIdentity) -> String? {
        guard ClientIdentity.isWellFormedLockValue(heldValue) else {
            return nil
        }
        return guarded(target: "$\(sessionID)",
                       condition: "#{==:#{\(lockOptionName)},\(heldValue)}",
                       action: "set -t $\(sessionID) \(lockOptionName) \(identity.lockValue)")
    }

    /// Take the lock if its value is not one we could have written, without echoing that value.
    static func evictMalformedLock(sessionID: Int, identity: ClientIdentity) -> String {
        return guarded(target: "$\(sessionID)",
                       condition: "#{!:#{m/r:^l_[0-9a-f]+$,#{\(lockOptionName)}}}",
                       action: "set -t $\(sessionID) \(lockOptionName) \(identity.lockValue)")
    }

    /// Release the lock if this client still holds it.
    static func unlock(sessionID: Int, identity: ClientIdentity) -> String {
        return guarded(target: "$\(sessionID)",
                       condition: "#{==:#{\(lockOptionName)},\(identity.lockValue)}",
                       action: "set -u -t $\(sessionID) \(lockOptionName)")
    }

    /// The loop that acquires the lock, as a state machine with no I/O. The owner sends what each
    /// step asks for and reports the reply. While waiting, the owner calls wake() when the lock
    /// option changes (a `refresh-client -B` subscription) or a client detaches; there is no
    /// polling. Every failed attempt means another client made progress.
    struct LockAcquisition {
        enum Request: Equatable {
            /// Send one command; report with didTryLock(succeeded:).
            case tryLock(String)
            /// Send as one list; report with didSnapshot(holder:clients:).
            case snapshot([String])
            /// Send as a guarded command; report with didEvict(_:).
            case evict(String)
            /// Send as a guarded command; nothing to report. A lock taken after cancel().
            case release(String)
        }

        enum Action: Equatable {
            case send(Request)
            /// A connected client holds the lock. Show the member as pending after a few seconds,
            /// offering cancel and force.
            case wait(holder: ClientIdentity)
            case acquired
            case cancelled
        }

        enum State: Equatable {
            case idle
            case trying
            case snapshotting
            case evicting
            case waiting(holder: ClientIdentity)
            case acquired
            case cancelled
        }

        let sessionID: Int
        let identity: ClientIdentity
        private(set) var state = State.idle
        // The holder's value as read, kept for force(). Always well-formed.
        private var heldValue: String?

        init(sessionID: Int, identity: ClientIdentity) {
            self.sessionID = sessionID
            self.identity = identity
        }

        mutating func start() -> Action? {
            guard state == .idle else {
                return nil
            }
            return attempt()
        }

        mutating func didTryLock(succeeded: Bool) -> Action? {
            if state == .cancelled {
                return succeeded ? release : nil
            }
            guard state == .trying else {
                return nil
            }
            if succeeded {
                state = .acquired
                return .acquired
            }
            state = .snapshotting
            return .send(.snapshot(TmuxWorkgroupCommands.lockSnapshot(sessionID: sessionID)))
        }

        /// - Parameters:
        ///   - holder: The lock's value, empty if unset.
        ///   - clients: The list-clients reply.
        mutating func didSnapshot(holder: String, clients: String) -> Action? {
            if state == .cancelled {
                return holder == identity.lockValue ? release : nil
            }
            guard state == .snapshotting else {
                return nil
            }
            if holder.isEmpty {
                // Released since the attempt.
                return attempt()
            }
            guard ClientIdentity.isWellFormedLockValue(holder) else {
                state = .evicting
                return .send(.evict(TmuxWorkgroupCommands.evictMalformedLock(sessionID: sessionID,
                                                                             identity: identity)))
            }
            if let holderIdentity = ClientIdentity(lockValue: holder) {
                if holderIdentity == identity {
                    state = .acquired
                    return .acquired
                }
                let connected = ClientIdentity.parseClientList(clients)
                // Our own client must be listed, or the list cannot show who is gone.
                if connected.contains(holderIdentity) || !connected.contains(identity) {
                    heldValue = holder
                    state = .waiting(holder: holderIdentity)
                    return .wait(holder: holderIdentity)
                }
            }
            // Gone, or a value we could have written but cannot read: take it if it is unchanged.
            return evict(holder)
        }

        mutating func didEvict(_ outcome: GuardOutcome) -> Action? {
            if state == .cancelled {
                return outcome == .applied ? release : nil
            }
            guard state == .evicting else {
                return nil
            }
            if outcome == .applied {
                state = .acquired
                return .acquired
            }
            return attempt()
        }

        /// The lock changed or a client detached.
        mutating func wake() -> Action? {
            guard case .waiting = state else {
                return nil
            }
            return attempt()
        }

        /// The user chose to take the lock from a holder that is connected but seems stuck.
        mutating func force() -> Action? {
            guard case .waiting = state, let heldValue else {
                return nil
            }
            return evict(heldValue)
        }

        mutating func cancel() -> Action? {
            switch state {
            case .acquired, .cancelled:
                return nil
            case .idle, .trying, .snapshotting, .evicting, .waiting:
                state = .cancelled
                return .cancelled
            }
        }

        /// A reply that arrives after cancel() can mean this client took the lock after all. It
        /// lets go at once, or every other client would wait on a lock nobody uses.
        private var release: Action {
            return .send(.release(TmuxWorkgroupCommands.unlock(sessionID: sessionID, identity: identity)))
        }

        private mutating func attempt() -> Action {
            heldValue = nil
            state = .trying
            return .send(.tryLock(TmuxWorkgroupCommands.tryLock(sessionID: sessionID, identity: identity)))
        }

        private mutating func evict(_ held: String) -> Action {
            guard let command = TmuxWorkgroupCommands.evictLock(sessionID: sessionID,
                                                                heldValue: held,
                                                                identity: identity) else {
                it_fatalError("Evicting a lock value that was not validated")
            }
            state = .evicting
            return .send(.evict(command))
        }
    }
}

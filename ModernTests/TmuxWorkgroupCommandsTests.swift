//
//  TmuxWorkgroupCommandsTests.swift
//  iTerm2 ModernTests
//
//  Several iTerm2s may be attached to one tmux session, and any of them may switch a peer or create
//  a member at any moment. tmux runs one client's command list without interleaving another's, so:
//    - A change that depends on where panes are is one `if -F` whose condition tmux evaluates when
//      it runs. Both branches are exactly one command, so tmux always sends two reply blocks, and
//      the second says whether the guard held. A stale client's change is a no-op.
//    - Creating something takes several round trips, so it holds a per-session lock: a session
//      option set with `set -o`, which fails if already set. A lock whose holder is no longer
//      connected may be evicted, guarded so that only one client evicts it.
//  The holder is named by `#{client_pid}:#{client_created}`, which tmux never reuses for another
//  client in practice. Everything sent is fixed text, numbers, or hex we produced.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupCommandsTests: XCTestCase {
    private typealias C = TmuxWorkgroupCommands
    private typealias Identity = TmuxWorkgroupCommands.ClientIdentity
    private typealias Lock = TmuxWorkgroupCommands.LockAcquisition

    private let me = Identity(pid: 4242, created: 1791320000)
    private let other = Identity(pid: 99, created: 1791310000)

    // MARK: - Guarded pane commands

    /// The panes in windows parked for instance "I", as the guards compute them.
    private var parked: String {
        let tag = TmuxWorkgroupState.ParkedTag(instanceID: "I").encoded
        return "#{W:#{?#{==:#{@iterm2_wg_parked},\(tag)},#{P:#{pane_id} },}}"
    }

    // Swap only if the target is still parked and the visible pane still is not. The parked panes
    // are found by tag over every window in the session.
    func testSwitchPeer() {
        XCTAssertEqual(C.switchPeer(sessionID: 2, instanceID: "I", visiblePaneID: 1, targetPaneID: 3),
                       "if -F -t $2 '#{&&:#{m:* %3 *, \(parked)},#{!:#{m:* %1 *, \(parked)}}}' " +
                       "'swap-pane -d -s %1 -t %3' 'display -p iterm2_wg_guard_failed'")
    }

    // One list, so no client ever sees the window untagged or unpinned; {end} is the window just
    // created.
    func testCreateParkedPeer() {
        let script = "true"
        XCTAssertEqual(C.createParkedPeer(sessionID: 2, instanceID: "I", position: 1, width: 80, height: 24,
                                          script: script), [
            "new-window -d -a -t '$2:{end}' -P -F '#{pane_id}' " + C.encodedCommand(script: script),
            "set -w -t '$2:{end}' @iterm2_wg_parked " + TmuxWorkgroupState.ParkedTag(instanceID: "I").encoded,
            "set -p -t '$2:{end}' @iterm2_wg " + TmuxWorkgroupState.PaneTag(instanceID: "I", position: 1).encoded,
            "resize-window -t '$2:{end}' -x 80 -y 24",
        ])
    }

    // A code review or diff peer is created waiting, and its pane stays when its program exits, as
    // a local one shows that it ended until Reload.
    func testCreateWaitingParkedPeer() {
        let script = "true"
        XCTAssertEqual(C.createParkedPeer(sessionID: 2, instanceID: "I", position: 1, width: 80, height: 24,
                                          script: script, waiting: true), [
            "new-window -d -a -t '$2:{end}' -P -F '#{pane_id}' " + C.encodedCommand(script: script),
            "set -w -t '$2:{end}' @iterm2_wg_parked " + TmuxWorkgroupState.ParkedTag(instanceID: "I").encoded,
            "set -p -t '$2:{end}' @iterm2_wg " + TmuxWorkgroupState.PaneTag(instanceID: "I", position: 1, waiting: true).encoded,
            "set -p -t '$2:{end}' remain-on-exit on",
            "resize-window -t '$2:{end}' -x 80 -y 24",
        ])
    }

    // Pinning a parked peer to a new slot size, only if it is still parked: a client acting on a
    // stale snapshot must not pin a window in view, which would stop it following the client size.
    func testRepinParkedPeer() {
        XCTAssertEqual(C.repinParkedPeer(sessionID: 2, instanceID: "I", paneID: 3, width: 100, height: 30),
                       "if -F -t $2 '#{m:* %3 *, \(parked)}' " +
                       "'resize-window -t %3 -x 100 -y 30' 'display -p iterm2_wg_guard_failed'")
    }

    func testPinParkedWindow() {
        XCTAssertEqual(C.pinWindow(ofPaneID: 4, width: 80, height: 24), "resize-window -t %4 -x 80 -y 24")
    }

    func testGuardOutcome() {
        XCTAssertEqual(C.GuardOutcome(branchReply: ""), .applied)
        XCTAssertEqual(C.GuardOutcome(branchReply: "iterm2_wg_guard_failed"), .guardFailed)
        XCTAssertEqual(C.GuardOutcome(branchReply: nil), .failed)
    }

    // MARK: - Running a member's command

    // The variable text (command, directory) reaches tmux only as octal escapes inside a fixed
    // wrapper that tmux runs directly, not through its default-shell (which may be tcsh or fish).
    // A shell reading it from a fake server sees arguments to a command that does not exist.
    func testEncodedCommand() {
        XCTAssertEqual(C.encodedCommand(script: "ls -l"),
                       #"/bin/sh -c 'eval "$(printf "\154\163\040\055\154")"'"#)
        // printf would treat % as a conversion; it is doubled, the one byte not made octal.
        XCTAssertEqual(C.encodedCommand(script: "%d"), #"/bin/sh -c 'eval "$(printf "%%\144")"'"#)
    }

    func testEncodedCommandHoldsNoQuotesFromTheScript() {
        let hostile = "x' \"; rm -rf ~; echo $(id) `id` \\ #{pane_id} \u{1b}]\n"
        let encoded = C.encodedCommand(script: hostile)
        let body = encoded.dropFirst(#"/bin/sh -c 'eval "$(printf ""#.count).dropLast(#"")"'"#.count)
        XCTAssertNotNil(String(body).range(of: #"^(\\[0-7]{3}|%%)*$"#, options: .regularExpression), encoded)
    }

    func testMemberScript() {
        XCTAssertEqual(C.memberScript(command: "git diff", directory: "/home/u/repo"),
                       "cd '/home/u/repo' 2>/dev/null; git diff")
        XCTAssertEqual(C.memberScript(command: "git diff", directory: "/it's here"),
                       #"cd '/it'\''s here' 2>/dev/null; git diff"#)
        XCTAssertEqual(C.memberScript(command: "git diff", directory: nil), "git diff")
        // No command: an interactive login shell, as for a remote member with no command.
        XCTAssertEqual(C.memberScript(command: "", directory: "/d"),
                       #"cd '/d' 2>/dev/null; exec "${SHELL:-/bin/sh}" -l"#)
    }

    // Created and tagged in one list. Without -d the new pane becomes current, so the untargeted
    // set -p tags it; last-pane then gives focus back to whichever pane had it. Clients are told
    // only the final state.
    func testSplitWindow() {
        let script = "true"
        let tag = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 2)
        func split(_ settings: SplitSettings) -> [String] {
            return C.splitWindow(targetPaneID: 3, settings: settings, script: script, tag: tag)
        }
        func expected(_ flags: String) -> [String] {
            return ["split-window -P -F '#{pane_id}' \(flags) -t %3 " + C.encodedCommand(script: script),
                    "set -p @iterm2_wg \(tag.encoded)",
                    "last-pane -t %3"]
        }
        XCTAssertEqual(split(SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.4)),
                       expected("-h -l 40%"))
        XCTAssertEqual(split(SplitSettings(orientation: .horizontal, side: .leadingOrTop, location: 0)),
                       expected("-v -b -l 1%"))
        XCTAssertEqual(split(SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 2)),
                       expected("-h -l 99%"))
    }

    func testWaitingSplitAndWindow() {
        let tag = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 2, waiting: true)
        let settings = SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)
        XCTAssertEqual(C.splitWindow(targetPaneID: 3, settings: settings, script: "true", tag: tag), [
            "split-window -P -F '#{pane_id}' -h -l 50% -t %3 " + C.encodedCommand(script: "true"),
            "set -p @iterm2_wg \(tag.encoded)",
            "set -p remain-on-exit on",
            "last-pane -t %3",
        ])
        XCTAssertEqual(C.newWindow(sessionID: 4, script: "true", tag: tag), [
            "new-window -d -a -t '$4:{end}' -P -F '#{pane_id}' " + C.encodedCommand(script: "true"),
            "set -p -t '$4:{end}' @iterm2_wg \(tag.encoded)",
            "set -p -t '$4:{end}' remain-on-exit on",
        ])
    }

    // MARK: - Starting and relaunching a member

    // What a waiting member runs until it is started: nothing to see, and not a shell to type into,
    // since starting it replaces whatever runs. It runs in the member's directory, so a client
    // starting it later can read the directory from tmux.
    func testWaitingScript() {
        XCTAssertEqual(C.waitingScript, "while :; do sleep 86400; done")
    }

    // The first start of a waiting member is claimed by clearing its waiting flag, guarded on the
    // flag still being set, so when several clients would start it (each one's diff poller sees
    // changes) only one does. The winner then respawns the pane.
    func testStartWaitingMember() {
        let tag = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 2, waiting: true)
        XCTAssertEqual(C.startWaitingMember(paneID: 5, tag: tag),
                       "if -F -t %5 '#{==:#{@iterm2_wg},\(tag.encoded)}' " +
                       "'set -p -t %5 @iterm2_wg \(tag.started.encoded)' 'display -p iterm2_wg_guard_failed'")
    }

    // Reload and picking a file replace the program whatever it is doing. A member that was still
    // waiting is started by it, in the same list. On tmux 3.8 and later the pane is respawned.
    func testRelaunchMemberByRespawning() {
        let started = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 2)
        XCTAssertEqual(C.relaunchMember(paneID: 5, script: "true", tag: started, method: .respawn, remainOnExit: true),
                       [C.respawnPane(paneID: 5, script: "true")])
        let waiting = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 2, waiting: true)
        XCTAssertEqual(C.relaunchMember(paneID: 5, script: "true", tag: waiting, method: .respawn, remainOnExit: true),
                       [C.respawnPane(paneID: 5, script: "true"), C.tagPane(paneID: 5, tag: started)])
    }

    // Before tmux 3.8, respawn-pane can crash the server: it drops the pane's buffered output while
    // a control client still has some of it queued (fixed by tmux commit 4714f478). So the member's
    // pane is replaced instead: the new program starts in a window of its own (tagged parked, so no
    // client opens it as a tab), takes the member's tag, is swapped into the member's place, and the
    // old pane is killed, which closes that window. One list, so no client sees two members at the
    // position. The first reply is the new pane's ID.
    func testRelaunchMemberByReplacing() {
        let waiting = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 2, waiting: true)
        let replace = C.RelaunchMethod.replace(sessionID: 3, instanceID: "I")
        let end = "'$3:{end}'"
        let expected = [
            "new-window -d -a -t \(end) -P -F '#{pane_id}' " + C.encodedCommand(script: "true"),
            "set -w -t \(end) @iterm2_wg_parked " + TmuxWorkgroupState.ParkedTag(instanceID: "I").encoded,
            "set -p -t \(end) @iterm2_wg " + waiting.started.encoded,
        ]
        // A pane ID just before the semicolon ending its command is a parse error in a list.
        let swap = ["swap-pane -d -t %5 -s \(end)", "kill-pane -t %5"]
        XCTAssertEqual(C.relaunchMember(paneID: 5, script: "true", tag: waiting, method: replace, remainOnExit: true),
                       expected + ["set -p -t \(end) remain-on-exit on"] + swap)
        XCTAssertEqual(C.relaunchMember(paneID: 5, script: "true", tag: waiting.started, method: replace, remainOnExit: false),
                       expected + swap)
    }

    func testRelaunchMethodForServer() {
        XCTAssertEqual(C.RelaunchMethod(respawnIsSafe: true, sessionID: 3, instanceID: "I"), .respawn)
        XCTAssertEqual(C.RelaunchMethod(respawnIsSafe: false, sessionID: 3, instanceID: "I"),
                       .replace(sessionID: 3, instanceID: "I"))
    }

    // Before relaunching, a client reads the member's tag (it must still be this instance's) and its
    // directory. Both come from tmux: the tag is decoded and checked, and the directory goes back
    // only inside an encoded script.
    func testMemberQuery() throws {
        XCTAssertEqual(C.memberQuery(paneID: 5), "display -p -t %5 '#{@iterm2_wg} #{pane_current_path}'")
        let tag = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 2, waiting: true)
        let parsed = try XCTUnwrap(C.parseMemberQuery(tag.encoded + " /home/u/my repo"))
        XCTAssertEqual(parsed.tag, tag)
        XCTAssertEqual(parsed.directory, "/home/u/my repo")
        // A pane whose program exited has no current directory.
        XCTAssertNil(try XCTUnwrap(C.parseMemberQuery(tag.encoded + " ")).directory)
        XCTAssertNil(try XCTUnwrap(C.parseMemberQuery(tag.encoded + " relative")).directory)
        XCTAssertNil(try XCTUnwrap(C.parseMemberQuery(tag.encoded + " /a\n/b")).directory)
        for bad in [nil, "", " /d", "garbage /d", "m_00 /d"] as [String?] {
            XCTAssertNil(C.parseMemberQuery(bad), String(describing: bad))
        }
    }

    // The code review's input files are written where it runs, under the server's home.
    func testServerHome() {
        XCTAssertEqual(C.homeQuery, "show-environment -g HOME")
        XCTAssertEqual(C.home(fromReply: "HOME=/home/u"), "/home/u")
        for bad in [nil, "", "HOME=", "HOME=relative", "-HOME", "PATH=/bin", "HOME=/a\nHOME=/b"] as [String?] {
            XCTAssertNil(C.home(fromReply: bad), String(describing: bad))
        }
    }

    // The script that writes the code review's inputs before it runs. Contents are single-quoted,
    // so anything in them (quotes, %, $, newlines) is written as is; printf's format is fixed.
    func testWriteFilesScript() {
        XCTAssertEqual(C.writeFilesScript(directory: "/h/.iterm2/code-review",
                                          files: [("a.txt", "it's 100%\n$HOME"), ("b.txt", "{}")]),
                       "umask 077 && mkdir -p '/h/.iterm2/code-review' && " +
                       #"printf '%s' 'it'\''s 100%"# + "\n" + #"$HOME' >'/h/.iterm2/code-review/a.txt' && "# +
                       "printf '%s' '{}' >'/h/.iterm2/code-review/b.txt' || exit 1")
    }

    func testNewWindowAndRespawn() {
        let tag = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 3)
        XCTAssertEqual(C.newWindow(sessionID: 4, script: "true", tag: tag), [
            "new-window -d -a -t '$4:{end}' -P -F '#{pane_id}' " + C.encodedCommand(script: "true"),
            "set -p -t '$4:{end}' @iterm2_wg \(tag.encoded)",
        ])
        XCTAssertEqual(C.respawnPane(paneID: 7, script: "true"),
                       "respawn-pane -k -t %7 " + C.encodedCommand(script: "true"))
    }

    // Ending an instance is one list: untag the leader (if it still exists) and unset the record.
    // Its members are killed afterwards one by one, so one that is already gone fails alone instead
    // of stopping the list. A crash in between leaves orphan member tags, which any client removes.
    func testEndInstanceCommands() {
        XCTAssertEqual(C.endInstance(sessionID: 2, instanceID: "I", leaderPaneID: 1),
                       [C.untagPane(paneID: 1), C.unsetRecord(sessionID: 2, instanceID: "I")])
        XCTAssertEqual(C.endInstance(sessionID: 2, instanceID: "I", leaderPaneID: nil),
                       [C.unsetRecord(sessionID: 2, instanceID: "I")])
        XCTAssertEqual(C.killPane(5), "kill-pane -t %5")
    }

    func testParsePaneID() {
        XCTAssertEqual(C.paneID(fromReply: "%12"), 12)
        for bad in [nil, "", "12", "%", "%-1", "%1 ", "%1\n%2", "%x"] as [String?] {
            XCTAssertNil(C.paneID(fromReply: bad), String(describing: bad))
        }
    }

    // MARK: - Tags and records

    func testTagAndRecordCommands() {
        let tag = TmuxWorkgroupState.PaneTag(instanceID: "I", position: 2)
        XCTAssertEqual(C.tagPane(paneID: 5, tag: tag), "set -p -t %5 @iterm2_wg \(tag.encoded)")
        XCTAssertEqual(C.untagPane(paneID: 5), "set -p -u -t %5 @iterm2_wg")
        let skeleton = TmuxWorkgroupState.Skeleton(root: .init(kind: .root, mode: .regular, children: []))!
        let record = TmuxWorkgroupState.InstanceRecord(workgroupID: "W", gitBase: "main", skeleton: skeleton)
        XCTAssertEqual(C.setRecord(sessionID: 2, instanceID: "I", record: record),
                       "set -t $2 \(TmuxWorkgroupState.instanceOptionName(instanceID: "I")) \(record.encoded)")
        XCTAssertEqual(C.unsetRecord(sessionID: 2, instanceID: "I"),
                       "set -u -t $2 \(TmuxWorkgroupState.instanceOptionName(instanceID: "I"))")
    }

    // MARK: - Client identity

    func testIdentityParsing() {
        XCTAssertEqual(Identity(reported: "4242:1791320000"), me)
        for bad in ["", "4242", "4242:", ":1", "+4242:1", "-1:1", "4242:1791320000:1", "a:1", "4242: 1",
                    "99999999999999999999:1", "4242:1\n"] {
            XCTAssertNil(Identity(reported: bad), bad)
        }
    }

    func testClientList() {
        XCTAssertEqual(Identity.parseClientList("4242:1791320000\n99:1791310000\ngarbage\n"), [me, other])
        XCTAssertEqual(Identity.parseClientList(""), [])
    }

    func testLockValueRoundTrips() {
        let value = me.lockValue
        XCTAssertNotNil(value.range(of: "^l_[0-9a-f]+$", options: .regularExpression), value)
        XCTAssertEqual(Identity(lockValue: value), me)
        XCTAssertNil(Identity(lockValue: "l_zz"))
        XCTAssertNil(Identity(lockValue: "x_" + String(value.dropFirst(2))))
    }

    // MARK: - Lock commands

    func testLockCommands() {
        let mine = me.lockValue
        let theirs = other.lockValue
        XCTAssertEqual(C.identityQuery, "display -p '#{client_pid}:#{client_created}'")
        XCTAssertEqual(C.tryLock(sessionID: 3, identity: me), "set -o -t $3 @iterm2_wg_lock \(mine)")
        XCTAssertEqual(C.lockSnapshot(sessionID: 3),
                       ["show -v -q -t $3 @iterm2_wg_lock", "list-clients -F '#{client_pid}:#{client_created}'"])
        XCTAssertEqual(C.evictLock(sessionID: 3, heldValue: theirs, identity: me),
                       "if -F -t $3 '#{==:#{@iterm2_wg_lock},\(theirs)}' " +
                       "'set -t $3 @iterm2_wg_lock \(mine)' 'display -p iterm2_wg_guard_failed'")
        XCTAssertEqual(C.evictMalformedLock(sessionID: 3, identity: me),
                       "if -F -t $3 '#{!:#{m/r:^l_[0-9a-f]+$,#{@iterm2_wg_lock}}}' " +
                       "'set -t $3 @iterm2_wg_lock \(mine)' 'display -p iterm2_wg_guard_failed'")
        XCTAssertEqual(C.unlock(sessionID: 3, identity: me),
                       "if -F -t $3 '#{==:#{@iterm2_wg_lock},\(mine)}' " +
                       "'set -u -t $3 @iterm2_wg_lock' 'display -p iterm2_wg_guard_failed'")
    }

    // A held value read from tmux is echoed back only if it is our own prefix and lowercase hex.
    func testEvictRefusesToEchoAnythingElse() {
        for held in ["", "l_", "l_ABCD", "l_12' ; run-shell evil ; '", "x_1234", "l_12 34"] {
            XCTAssertNil(C.evictLock(sessionID: 3, heldValue: held, identity: me), held)
        }
    }

    // MARK: - Acquiring the lock

    private func clients(_ identities: Identity...) -> String {
        return identities.map { "\($0.pid):\($0.created)" }.joined(separator: "\n")
    }

    func testFreeLockIsTakenAtOnce() {
        var lock = Lock(sessionID: 3, identity: me)
        XCTAssertEqual(lock.start(), .send(.tryLock(C.tryLock(sessionID: 3, identity: me))))
        XCTAssertEqual(lock.didTryLock(succeeded: true), .acquired)
        XCTAssertEqual(lock.state, .acquired)
    }

    func testLiveHolderMeansWait() {
        var lock = Lock(sessionID: 3, identity: me)
        _ = lock.start()
        XCTAssertEqual(lock.didTryLock(succeeded: false), .send(.snapshot(C.lockSnapshot(sessionID: 3))))
        XCTAssertEqual(lock.didSnapshot(holder: other.lockValue, clients: clients(me, other)), .wait(holder: other))
        XCTAssertEqual(lock.state, .waiting(holder: other))
        // Woken (the lock changed, or a client detached): try again from the top.
        XCTAssertEqual(lock.wake(), .send(.tryLock(C.tryLock(sessionID: 3, identity: me))))
        XCTAssertEqual(lock.didTryLock(succeeded: true), .acquired)
    }

    func testDeadHolderIsEvicted() {
        var lock = Lock(sessionID: 3, identity: me)
        _ = lock.start()
        _ = lock.didTryLock(succeeded: false)
        let evict = C.evictLock(sessionID: 3, heldValue: other.lockValue, identity: me)!
        XCTAssertEqual(lock.didSnapshot(holder: other.lockValue, clients: clients(me)), .send(.evict(evict)))
        XCTAssertEqual(lock.didEvict(.applied), .acquired)
    }

    // Another client evicted (or took) it first: start over.
    func testLostEvictionStartsOver() {
        var lock = Lock(sessionID: 3, identity: me)
        _ = lock.start()
        _ = lock.didTryLock(succeeded: false)
        _ = lock.didSnapshot(holder: other.lockValue, clients: clients(me))
        XCTAssertEqual(lock.didEvict(.guardFailed), .send(.tryLock(C.tryLock(sessionID: 3, identity: me))))
        _ = lock.didTryLock(succeeded: false)
        XCTAssertEqual(lock.didEvict(.failed), nil, "not evicting now")
    }

    func testReleasedBetweenTryAndSnapshot() {
        var lock = Lock(sessionID: 3, identity: me)
        _ = lock.start()
        _ = lock.didTryLock(succeeded: false)
        XCTAssertEqual(lock.didSnapshot(holder: "", clients: clients(me)),
                       .send(.tryLock(C.tryLock(sessionID: 3, identity: me))))
    }

    func testMalformedHolderIsEvictedWithoutEchoingIt() {
        var lock = Lock(sessionID: 3, identity: me)
        _ = lock.start()
        _ = lock.didTryLock(succeeded: false)
        XCTAssertEqual(lock.didSnapshot(holder: "evil' ; run-shell x", clients: clients(me)),
                       .send(.evict(C.evictMalformedLock(sessionID: 3, identity: me))))
    }

    // If our own client is not in the list, the list cannot be trusted to show who is gone.
    func testUntrustworthyClientListMeansWait() {
        var lock = Lock(sessionID: 3, identity: me)
        _ = lock.start()
        _ = lock.didTryLock(succeeded: false)
        XCTAssertEqual(lock.didSnapshot(holder: other.lockValue, clients: "garbage"), .wait(holder: other))
    }

    // Our own value (e.g. a try whose success was not seen) means we hold it.
    func testOwnValueMeansAcquired() {
        var lock = Lock(sessionID: 3, identity: me)
        _ = lock.start()
        _ = lock.didTryLock(succeeded: false)
        XCTAssertEqual(lock.didSnapshot(holder: me.lockValue, clients: clients(me)), .acquired)
    }

    // A live holder that seems stuck: the user may cancel, or force (evict it anyway).
    func testCancelAndForce() {
        var lock = Lock(sessionID: 3, identity: me)
        _ = lock.start()
        _ = lock.didTryLock(succeeded: false)
        _ = lock.didSnapshot(holder: other.lockValue, clients: clients(me, other))
        XCTAssertEqual(lock.force(),
                       .send(.evict(C.evictLock(sessionID: 3, heldValue: other.lockValue, identity: me)!)))
        XCTAssertEqual(lock.didEvict(.applied), .acquired)

        var cancelled = Lock(sessionID: 3, identity: me)
        _ = cancelled.start()
        _ = cancelled.didTryLock(succeeded: false)
        _ = cancelled.didSnapshot(holder: other.lockValue, clients: clients(me, other))
        XCTAssertEqual(cancelled.cancel(), .cancelled)
        XCTAssertNil(cancelled.wake(), "a cancelled acquisition ignores late notifications")
    }

    // Cancelling while an attempt is in flight (the user clicked Cancel just as a wake retried):
    // if the attempt takes the lock anyway, it is released at once, or every other client would
    // wait on a lock nobody uses.
    func testALockTakenAfterCancelIsReleased() {
        let release = Lock.Action.send(.release(C.unlock(sessionID: 3, identity: me)))
        var trying = Lock(sessionID: 3, identity: me)
        _ = trying.start()
        XCTAssertEqual(trying.cancel(), .cancelled)
        XCTAssertEqual(trying.didTryLock(succeeded: true), release)

        var failed = Lock(sessionID: 3, identity: me)
        _ = failed.start()
        _ = failed.cancel()
        XCTAssertNil(failed.didTryLock(succeeded: false), "nothing was taken")

        // Forcing, then cancelling before the eviction lands.
        var evicting = Lock(sessionID: 3, identity: me)
        _ = evicting.start()
        _ = evicting.didTryLock(succeeded: false)
        _ = evicting.didSnapshot(holder: other.lockValue, clients: clients(me, other))
        _ = evicting.force()
        XCTAssertEqual(evicting.cancel(), .cancelled)
        XCTAssertEqual(evicting.didEvict(.applied), release)

        var lost = Lock(sessionID: 3, identity: me)
        _ = lost.start()
        _ = lost.didTryLock(succeeded: false)
        _ = lost.didSnapshot(holder: other.lockValue, clients: clients(me, other))
        _ = lost.force()
        _ = lost.cancel()
        XCTAssertNil(lost.didEvict(.guardFailed))

        // A snapshot that would have shown our own value.
        var snapshotting = Lock(sessionID: 3, identity: me)
        _ = snapshotting.start()
        _ = snapshotting.didTryLock(succeeded: false)
        _ = snapshotting.cancel()
        XCTAssertEqual(snapshotting.didSnapshot(holder: me.lockValue, clients: clients(me)), release)
    }

    // Notifications can arrive at any time; outside waiting they change nothing.
    func testEventsOutOfTurnAreIgnored() {
        var lock = Lock(sessionID: 3, identity: me)
        XCTAssertNil(lock.wake())
        XCTAssertNil(lock.force())
        _ = lock.start()
        XCTAssertNil(lock.wake())
        XCTAssertNil(lock.didSnapshot(holder: "", clients: ""))
        XCTAssertEqual(lock.didTryLock(succeeded: true), .acquired)
        XCTAssertNil(lock.didTryLock(succeeded: true))
        XCTAssertNil(lock.wake())
    }
}

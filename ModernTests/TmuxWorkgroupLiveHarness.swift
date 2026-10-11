//
//  TmuxWorkgroupLiveHarness.swift
//  iTerm2 ModernTests
//
//  Live harness for the commands workgroups use when several iTerm2s are attached to one tmux
//  session (TmuxWorkgroupCommands). NOT a unit test: it starts a private tmux server and attaches
//  two control-mode clients, each driven by a real TmuxGateway, then has them race. Run it with
//  tools/run_tmux_workgroup_live.sh, which sets ITERM2_TMUX_LIVE; the default ModernTests run
//  skips it. ITERM2_TMUX_PATH picks the tmux binary, so it can be run against the oldest
//  supported server (3.2) as well as a current one.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupLiveHarness: XCTestCase {
    private typealias C = TmuxWorkgroupCommands

    private var server: TmuxTestServer!
    private var clients = [TmuxTestClient]()

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["ITERM2_TMUX_LIVE"] == "1",
                          "Live harness; run tools/run_tmux_workgroup_live.sh")
        let path = environment["ITERM2_TMUX_PATH"] ?? "/opt/homebrew/bin/tmux"
        server = try TmuxTestServer(tmuxPath: path)
    }

    override func tearDown() {
        clients.forEach { $0.stop() }
        clients.removeAll()
        server?.kill()
        super.tearDown()
    }

    private func attach() throws -> TmuxTestClient {
        let client = try TmuxTestClient(server: server)
        clients.append(client)
        let ready = expectation(description: "attached")
        client.whenReady { ready.fulfill() }
        wait(for: [ready], timeout: 10)
        let identity = expectation(description: "identity")
        client.gateway.sendCommand(C.identityQuery, responseTarget: client.reply { reply in
            client.identity = reply.flatMap { C.ClientIdentity(reported: $0) }
            identity.fulfill()
        }, responseSelector: #selector(TmuxTestReply.handle(_:)))
        wait(for: [identity], timeout: 10)
        _ = try XCTUnwrap(client.identity)
        return client
    }

    private func guarded(_ client: TmuxTestClient, _ command: String) -> XCTestExpectation {
        let done = expectation(description: command)
        client.gateway.sendGuardedCommand(command,
                                          responseTarget: client.reply { reply in
                                              client.outcomes.append(C.GuardOutcome(branchReply: reply))
                                              done.fulfill()
                                          },
                                          responseSelector: #selector(TmuxTestReply.handle(_:)),
                                          responseObject: nil)
        return done
    }

    private func sendList(_ client: TmuxTestClient, _ commands: [String]) -> [String?] {
        var result = [String?]()
        let done = expectation(description: "\(commands)")
        client.gateway.sendList(commands) { replies in
            result = replies
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result
    }

    private let instance = "INSTANCE"

    /// The visible pane in window 0 and a peer parked in a window of its own. Returns (visible, parked).
    private func makePeerPair(_ client: TmuxTestClient) throws -> (Int, Int) {
        let visible = try server.int(["display", "-p", "-t", "s:0", "#{pane_id}"], prefix: "%")
        let slot = try server.lines(["display", "-p", "-t", "%\(visible)", "#{pane_width} #{pane_height}"])
        let size = try XCTUnwrap(slot.first).split(separator: " ").compactMap { Int($0) }
        let replies = sendList(client, C.createParkedPeer(sessionID: client.sessionID, instanceID: instance,
                                                          position: 1, width: size[0], height: size[1],
                                                          script: "exec sleep 86400"))
        let parked = try XCTUnwrap(C.paneID(fromReply: replies.first ?? nil))
        return (visible, parked)
    }

    // MARK: - Guarded switch

    // Both clients ask for the same switch at the same moment. Unguarded, the second swap would
    // undo the first. Guarded, exactly one applies, and the other sees its guard fail.
    func testRacingSwitchesSwapOnce() throws {
        let a = try attach()
        let b = try attach()
        let (visible, parked) = try makePeerPair(a)
        var current = (visible: visible, target: parked)
        for round in 0..<20 {
            let command = C.switchPeer(sessionID: a.sessionID, instanceID: instance,
                                       visiblePaneID: current.visible, targetPaneID: current.target)
            let waits = [guarded(a, command), guarded(b, command)]
            wait(for: waits, timeout: 10)
            let outcomes = [a.outcomes.removeLast(), b.outcomes.removeLast()]
            XCTAssertEqual(outcomes.filter { $0 == .applied }.count, 1, "round \(round): \(outcomes)")
            XCTAssertEqual(outcomes.filter { $0 == .guardFailed }.count, 1, "round \(round): \(outcomes)")
            XCTAssertEqual(try server.int(["display", "-p", "-t", "%\(current.target)", "#{window_id}"], prefix: "@"),
                           try server.int(["display", "-p", "-t", "s:0", "#{window_id}"], prefix: "@"),
                           "round \(round): the target is in view")
            current = (visible: current.target, target: current.visible)
        }
    }

    // Another instance's parked windows do not count: the guard does not hold, nothing moves, and
    // the gateway stays in step.
    func testGuardForAnotherInstanceDoesNotHold() throws {
        let a = try attach()
        let (visible, parked) = try makePeerPair(a)
        wait(for: [guarded(a, C.switchPeer(sessionID: a.sessionID, instanceID: "OTHER",
                                           visiblePaneID: visible, targetPaneID: parked))], timeout: 10)
        XCTAssertEqual(a.outcomes, [.guardFailed])
        XCTAssertNotEqual(try server.int(["display", "-p", "-t", "%\(parked)", "#{window_id}"], prefix: "@"),
                          try server.int(["display", "-p", "-t", "s:0", "#{window_id}"], prefix: "@"))
        let next = expectation(description: "next command")
        a.gateway.sendCommand("display -p next", responseTarget: a.reply { reply in
            XCTAssertEqual(reply, "next")
            next.fulfill()
        }, responseSelector: #selector(TmuxTestReply.handle(_:)))
        wait(for: [next], timeout: 10)
    }

    // A parked peer's window and pane carry their tags from the moment they exist, and pinning the
    // window to the visible slot's size means a switch resizes neither pane.
    func testParkedPeerIsTaggedAtOnceAndPinnedToItsSlot() throws {
        let a = try attach()
        let leader = try server.int(["display", "-p", "-t", "s:0", "#{pane_id}"], prefix: "%")
        _ = try server.lines(["split-window", "-d", "-h", "-t", "%\(leader)", "exec sleep 86400"])
        let (visible, parked) = try makePeerPair(a)
        XCTAssertEqual(visible, leader)
        XCTAssertEqual(try server.lines(["display", "-p", "-t", "%\(parked)", "#{@iterm2_wg_parked} #{@iterm2_wg}"]),
                       [TmuxWorkgroupState.ParkedTag(instanceID: instance).encoded + " " +
                        TmuxWorkgroupState.PaneTag(instanceID: instance, position: 1).encoded])
        let slot = try server.lines(["display", "-p", "-t", "%\(leader)", "#{pane_width} #{pane_height}"])
        let size = try XCTUnwrap(slot.first).split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(size.count, 2)
        XCTAssertNotNil(send(a, C.pinWindow(ofPaneID: parked, width: size[0], height: size[1])))
        func paneSize(_ pane: Int) throws -> [String] {
            return try server.lines(["display", "-p", "-t", "%\(pane)", "#{pane_width} #{pane_height}"])
        }
        XCTAssertEqual(try paneSize(parked), slot)
        wait(for: [guarded(a, C.switchPeer(sessionID: a.sessionID, instanceID: instance,
                                           visiblePaneID: leader, targetPaneID: parked))], timeout: 10)
        XCTAssertEqual(a.outcomes, [.applied])
        XCTAssertEqual(try paneSize(parked), slot, "the incoming peer keeps its size")
        XCTAssertEqual(try paneSize(leader), slot, "the outgoing leader keeps its size")
    }

    // MARK: - Running members' commands

    private func send(_ client: TmuxTestClient, _ command: String) -> String? {
        var result: String?
        let done = expectation(description: command)
        client.gateway.sendCommand(command,
                                   responseTarget: client.reply { reply in
                                       result = reply
                                       done.fulfill()
                                   },
                                   responseSelector: #selector(TmuxTestReply.handle(_:)),
                                   responseObject: nil,
                                   flags: 1)  // kTmuxGatewayCommandShouldTolerateErrors
        wait(for: [done], timeout: 10)
        return result
    }

    private func contents(_ url: URL) throws -> String {
        let written = expectation(for: NSPredicate { _, _ in
            (try? String(contentsOf: url, encoding: .utf8))?.hasSuffix("\n") == true
        }, evaluatedWith: nil)
        wait(for: [written], timeout: 10)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // A member's script runs with /bin/sh in its directory, for a split, a new window and a
    // respawn, whatever the directory's name holds; nothing in the name is executed. A split or
    // new window is tagged in the same list that creates it, and a split leaves focus where it was.
    func testMembersRunTheirScriptsInTheirDirectory() throws {
        let a = try attach()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("wg-live-\(UUID().uuidString)")
        let directory = base.appendingPathComponent(#"it's "$(touch pwned)" `touch pwned2` %d \dir"#)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        func script(writing name: String) -> String {
            let output = base.appendingPathComponent(name).path
            return C.memberScript(command: #"printf '%s\n' "$PWD" > '"# + output + #"'; exec sleep 86400"#,
                                  directory: directory.path)
        }
        let leader = try server.int(["display", "-p", "-t", "s:0", "#{pane_id}"], prefix: "%")

        let splitTag = TmuxWorkgroupState.PaneTag(instanceID: instance, position: 1)
        let split = try XCTUnwrap(C.paneID(fromReply: sendList(a, C.splitWindow(
            targetPaneID: leader,
            settings: SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.3),
            script: script(writing: "split"),
            tag: splitTag)).first ?? nil))
        XCTAssertEqual(try server.lines(["show", "-p", "-v", "-t", "%\(split)", "@iterm2_wg"]), [splitTag.encoded])
        XCTAssertEqual(try server.int(["display", "-p", "-t", "s:0", "#{pane_id}"], prefix: "%"), leader,
                       "focus is where it was")
        XCTAssertEqual(try contents(base.appendingPathComponent("split")), directory.path + "\n")
        XCTAssertEqual(try server.int(["display", "-p", "-t", "%\(split)", "#{window_id}"], prefix: "@"),
                       try server.int(["display", "-p", "-t", "%\(leader)", "#{window_id}"], prefix: "@"))

        let windowTag = TmuxWorkgroupState.PaneTag(instanceID: instance, position: 2)
        let window = try XCTUnwrap(C.paneID(fromReply: sendList(a, C.newWindow(sessionID: a.sessionID,
                                                                              script: script(writing: "window"),
                                                                              tag: windowTag)).first ?? nil))
        XCTAssertEqual(try server.lines(["show", "-p", "-v", "-t", "%\(window)", "@iterm2_wg"]), [windowTag.encoded])
        XCTAssertEqual(try contents(base.appendingPathComponent("window")), directory.path + "\n")
        XCTAssertNotEqual(try server.int(["display", "-p", "-t", "%\(window)", "#{window_id}"], prefix: "@"),
                          try server.int(["display", "-p", "-t", "%\(leader)", "#{window_id}"], prefix: "@"))

        XCTAssertNotNil(send(a, C.respawnPane(paneID: split, script: script(writing: "respawned"))))
        XCTAssertEqual(try contents(base.appendingPathComponent("respawned")), directory.path + "\n")


        let files = try FileManager.default.subpathsOfDirectory(atPath: base.path)
        XCTAssertFalse(files.contains { $0.hasSuffix("pwned") || $0.hasSuffix("pwned2") }, "\(files)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: "pwned"))
    }

    // MARK: - Lock

    private func lockDriver(_ client: TmuxTestClient) -> TmuxWorkgroupLockDriver {
        return TmuxWorkgroupLockDriver(gatewayProvider: { [weak client] in client?.gateway },
                                       sessionID: client.sessionID,
                                       identity: client.identity!)
    }

    private func acquire(_ client: TmuxTestClient) -> TmuxWorkgroupLockDriver {
        let driver = lockDriver(client)
        let settled = expectation(description: "lock settled")
        driver.onSettled = { _ in settled.fulfill() }
        driver.start()
        wait(for: [settled], timeout: 10)
        return driver
    }

    private func release(_ client: TmuxTestClient) {
        wait(for: [guarded(client, C.unlock(sessionID: client.sessionID, identity: client.identity!))], timeout: 10)
        XCTAssertEqual(client.outcomes.removeLast(), .applied)
    }

    func testLiveHolderMakesTheOtherWaitUntilReleased() throws {
        let a = try attach()
        let b = try attach()
        XCTAssertEqual(acquire(a).lastAction, .acquired)
        let waiting = acquire(b)
        XCTAssertEqual(waiting.lastAction, .wait(holder: a.identity!))
        release(a)
        // In the app a subscription to the lock option wakes the waiter; here the test does.
        let settled = expectation(description: "woken")
        waiting.onSettled = { _ in settled.fulfill() }
        waiting.wake()
        wait(for: [settled], timeout: 10)
        XCTAssertEqual(waiting.lastAction, .acquired)
        XCTAssertEqual(try server.option("@iterm2_wg_lock"), b.identity!.lockValue)
    }

    // The point of the lock: two clients that both see a member missing create it once.
    func testRacingCreationsCreateOnce() throws {
        let a = try attach()
        let b = try attach()
        let tag = TmuxWorkgroupState.ParkedTag(instanceID: "INSTANCE").encoded
        var drivers = [TmuxWorkgroupLockDriver]()
        let settled = [expectation(description: "a"), expectation(description: "b")]
        for (client, done) in zip([a, b], settled) {
            let driver = lockDriver(client)
            driver.onSettled = { _ in done.fulfill() }
            drivers.append(driver)
        }
        drivers.forEach { $0.start() }
        wait(for: settled, timeout: 10)
        let winnerIndex = try XCTUnwrap(drivers.firstIndex { $0.lastAction == .acquired })
        let (winner, loser) = (drivers[winnerIndex], drivers[1 - winnerIndex])
        let (winnerClient, loserClient) = ([a, b][winnerIndex], [a, b][1 - winnerIndex])
        _ = winner
        XCTAssertEqual(loser.lastAction, .wait(holder: winnerClient.identity!))

        // Each, once it holds the lock, creates the parked window only if no window has the tag.
        func createIfMissing(_ client: TmuxTestClient) throws {
            let windows = try server.lines(["list-windows", "-t", "s", "-F", "#{@iterm2_wg_parked}"])
            if !windows.contains(tag) {
                let window = try server.int(["new-window", "-d", "-P", "-F", "#{window_id}", "-t", "s",
                                             "exec sleep 86400"], prefix: "@")
                _ = try server.lines(["set", "-w", "-t", "@\(window)", "@iterm2_wg_parked", tag])
            }
            release(client)
        }
        try createIfMissing(winnerClient)
        let woken = expectation(description: "loser acquires")
        loser.onSettled = { _ in woken.fulfill() }
        loser.wake()
        wait(for: [woken], timeout: 10)
        XCTAssertEqual(loser.lastAction, .acquired)
        try createIfMissing(loserClient)

        let tagged = try server.lines(["list-windows", "-t", "s", "-F", "#{@iterm2_wg_parked}"]).filter { $0 == tag }
        XCTAssertEqual(tagged.count, 1)
    }

    // A holder whose client is gone (crashed, or its ssh dropped) is evicted.
    func testDisconnectedHolderIsEvicted() throws {
        let a = try attach()
        let b = try attach()
        XCTAssertEqual(acquire(a).lastAction, .acquired)
        let aIdentity = "\(a.identity!.pid):\(a.identity!.created)"
        a.stop()
        let gone = expectation(for: NSPredicate { _, _ in
            (try? self.server.lines(["list-clients", "-F", "#{client_pid}:#{client_created}"]))?.contains(aIdentity) == false
        }, evaluatedWith: nil)
        wait(for: [gone], timeout: 10)
        XCTAssertEqual(acquire(b).lastAction, .acquired)
        XCTAssertEqual(try server.option("@iterm2_wg_lock"), b.identity!.lockValue)
    }

    // A value no iTerm2 wrote (a hand edit, or a fake server) is replaced without being echoed.
    func testMalformedLockIsEvicted() throws {
        let b = try attach()
        _ = try server.lines(["set", "-t", "s", "@iterm2_wg_lock", "x' ; display hello ; '"])
        XCTAssertEqual(acquire(b).lastAction, .acquired)
        XCTAssertEqual(try server.option("@iterm2_wg_lock"), b.identity!.lockValue)
    }

    // MARK: - Crash recovery
    //
    // Client A runs the real sequence up to a point and vanishes there (its tmux client process is
    // killed, as when iTerm2 crashes or the connection drops). Client B then does the same job, and
    // a freshly attached client C checks what is on the server.

    /// Root (position 0) plus two peers (1 and 2).
    private var peersWorkgroup: iTermWorkgroup {
        func config(_ id: String, _ kind: iTermWorkgroupSessionConfig.Kind, parent: String?) -> iTermWorkgroupSessionConfig {
            return iTermWorkgroupSessionConfig(uniqueIdentifier: id, parentID: parent, kind: kind, profileGUID: nil,
                                               command: "", urlString: "", toolbarItems: [], displayName: id)
        }
        return iTermWorkgroup(uniqueIdentifier: "WG", name: "W", sessions: [
            config("ROOT", .root, parent: nil), config("P1", .peer, parent: "ROOT"), config("P2", .peer, parent: "ROOT"),
        ])
    }

    private let peerScripts = [1: "exec sleep 86400", 2: "exec sleep 86400"]
    private var creators = [TmuxWorkgroupPeerCreator]()

    /// Writes the record and tags the leader, as entry does.
    private func publish(_ client: TmuxTestClient) throws -> Int {
        let leader = try server.int(["display", "-p", "-t", "s:0", "#{pane_id}"], prefix: "%")
        let record = TmuxWorkgroupState.InstanceRecord(workgroupID: "WG", gitBase: "main",
                                                       skeleton: try XCTUnwrap(TmuxWorkgroupState.Skeleton(workgroup: peersWorkgroup)))
        _ = sendList(client, [C.setRecord(sessionID: client.sessionID, instanceID: instance, record: record),
                              C.tagPane(paneID: leader, tag: TmuxWorkgroupState.PaneTag(instanceID: instance, position: 0))])
        return leader
    }

    /// Runs the real creator for both peers, stopping before `stopAt` as if the client vanished there.
    /// Returns its outcome, or nil if it was stopped.
    private func createPeers(_ client: TmuxTestClient,
                             stopAt: TmuxWorkgroupPeerCreator.Step? = nil) -> TmuxWorkgroupPeerCreator.Outcome? {
        let creator = TmuxWorkgroupPeerCreator(gatewayProvider: { [weak client] in client?.gateway },
                                               sessionID: client.sessionID,
                                               instanceID: instance,
                                               identity: client.identity!,
                                               scriptsByPosition: peerScripts)
        creators.append(creator)
        let done = expectation(description: "creator \(String(describing: stopAt))")
        var outcome: TmuxWorkgroupPeerCreator.Outcome?
        creator.willPerform = { step in
            guard step != stopAt else {
                done.fulfill()
                return false
            }
            return true
        }
        creator.onWaiting = { holder in
            XCTFail("waited on a lock held by \(holder)")
            done.fulfill()
        }
        creator.run { result in
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: 20)
        return outcome
    }

    /// The client vanishes; returns once the server no longer lists it.
    private func crash(_ client: TmuxTestClient) {
        let identity = "\(client.identity!.pid):\(client.identity!.created)"
        client.stop()
        let gone = expectation(for: NSPredicate { _, _ in
            (try? self.server.lines(["list-clients", "-F", "#{client_pid}:#{client_created}"]))?.contains(identity) == false
        }, evaluatedWith: nil)
        wait(for: [gone], timeout: 10)
    }

    private func derivation(_ client: TmuxTestClient) -> TmuxWorkgroupState.Derivation {
        let replies = sendList(client, TmuxWorkgroupAdoption.queries(sessionID: client.sessionID))
        return TmuxWorkgroupState.derive(
            panes: TmuxWorkgroupAdoption.panes(listPanesReply: replies[1] ?? ""),
            windows: TmuxWorkgroupAdoption.windows(listWindowsReply: replies[2] ?? ""),
            instanceOptions: TmuxWorkgroupAdoption.instanceOptions(showReply: replies[0] ?? ""))
    }

    /// What a freshly attached client finds: the leader in view, both peers parked in windows of
    /// their own pinned to the leader's size, no problems, no orphans, and the lock free.
    private func assertCompleteInstance(leader: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let c = try attach()
        let d = derivation(c)
        let i = try XCTUnwrap(d.instances.first, file: file, line: line)
        XCTAssertEqual(d.instances.count, 1, file: file, line: line)
        XCTAssertEqual(i.paneForPosition[0], leader, file: file, line: line)
        XCTAssertEqual(i.peerGroups, [TmuxWorkgroupState.PeerGroup(host: 0, members: [0, 1, 2], visible: 0, hidden: [1, 2])],
                       file: file, line: line)
        XCTAssertEqual(i.problems, [], file: file, line: line)
        XCTAssertEqual(i.parkedWindowIDs.count, 2, "one window per parked peer", file: file, line: line)
        XCTAssertEqual(d.orphanMemberPaneIDs + d.orphanLeaderPaneIDs, [], file: file, line: line)
        XCTAssertNil(try server.option("@iterm2_wg_lock"), "the lock is free", file: file, line: line)
        let slot = try server.lines(["display", "-p", "-t", "%\(leader)", "#{pane_width}x#{pane_height}"])
        for position in [1, 2] {
            let pane = try XCTUnwrap(i.paneForPosition[position], file: file, line: line)
            XCTAssertEqual(try server.lines(["display", "-p", "-t", "%\(pane)", "#{window_width}x#{window_height}"]), slot,
                           "pinned to the leader's slot", file: file, line: line)
        }
    }

    func testNoCrash() throws {
        let a = try attach()
        let leader = try publish(a)
        guard case .finished(let created, let failed)? = createPeers(a) else {
            return XCTFail("did not finish")
        }
        XCTAssertEqual(Set(created.keys), [1, 2])
        XCTAssertEqual(failed, [])
        try assertCompleteInstance(leader: leader)
    }

    // A vanished after publishing, before taking the lock: the peers are simply missing.
    func testCrashAfterPublishing() throws {
        let a = try attach()
        let b = try attach()
        let leader = try publish(a)
        crash(a)
        guard case .finished(let created, _)? = createPeers(b) else {
            return XCTFail("did not finish")
        }
        XCTAssertEqual(Set(created.keys), [1, 2])
        try assertCompleteInstance(leader: leader)
    }

    // A vanished holding the lock: B evicts it.
    func testCrashHoldingTheLock() throws {
        let a = try attach()
        let b = try attach()
        let leader = try publish(a)
        XCTAssertNil(createPeers(a, stopAt: .snapshot))
        XCTAssertEqual(try server.option("@iterm2_wg_lock"), a.identity!.lockValue)
        crash(a)
        guard case .finished(let created, _)? = createPeers(b) else {
            return XCTFail("did not finish")
        }
        XCTAssertEqual(Set(created.keys), [1, 2])
        try assertCompleteInstance(leader: leader)
    }

    // A vanished after creating one peer: B creates only the other.
    func testCrashAfterOnePeer() throws {
        let a = try attach()
        let b = try attach()
        let leader = try publish(a)
        XCTAssertNil(createPeers(a, stopAt: .create(position: 2)))
        crash(a)
        guard case .finished(let created, _)? = createPeers(b) else {
            return XCTFail("did not finish")
        }
        XCTAssertEqual(Set(created.keys), [2])
        try assertCompleteInstance(leader: leader)
    }

    // A vanished after creating everything, before releasing the lock: B creates nothing.
    func testCrashBeforeUnlocking() throws {
        let a = try attach()
        let b = try attach()
        let leader = try publish(a)
        XCTAssertNil(createPeers(a, stopAt: .unlock))
        crash(a)
        XCTAssertEqual(createPeers(b), .finished(created: [:], failed: []))
        try assertCompleteInstance(leader: leader)
    }

    // A vanished partway through ending the instance: the record was unset and the leader untagged,
    // but the peers were not killed. Any client finds them as orphans and finishes the job, killing
    // the peers and leaving the leader's pane alone.
    func testCrashWhileEndingTheInstance() throws {
        let a = try attach()
        let b = try attach()
        let leader = try publish(a)
        guard case .finished(let created, _)? = createPeers(a) else {
            return XCTFail("did not finish")
        }
        _ = sendList(a, C.endInstance(sessionID: a.sessionID, instanceID: instance, leaderPaneID: leader))
        crash(a)
        let steps = TmuxWorkgroupAdoption.plan(derivation: derivation(b), localWorkgroups: [], adoptedHere: [])
        XCTAssertEqual(steps, [.cleanUpOrphans(killPaneIDs: created.values.sorted(), untagPaneIDs: [])])
        if case let .cleanUpOrphans(kill, _)? = steps.first {
            for paneID in kill {
                XCTAssertNotNil(send(b, C.killPane(paneID)))
            }
        }
        let after = derivation(b)
        XCTAssertEqual(after.instances, [])
        XCTAssertEqual(after.orphanMemberPaneIDs + after.orphanLeaderPaneIDs, [])
        XCTAssertEqual(try server.lines(["list-panes", "-s", "-t", "s", "-F", "#{pane_id}"]), ["%\(leader)"],
                       "only the leader's pane is left")
    }

    // A record and its leader's tag are written in one list, so a snapshot taken at the same time
    // by another client never sees a record without its leader (which it would remove as ended).
    func testSnapshotNeverSeesARecordWithoutItsLeader() throws {
        let a = try attach()
        let b = try attach()
        let leader = try server.int(["display", "-p", "-t", "s:0", "#{pane_id}"], prefix: "%")
        let record = TmuxWorkgroupState.InstanceRecord(workgroupID: "WG", gitBase: "main",
                                                       skeleton: try XCTUnwrap(TmuxWorkgroupState.Skeleton(workgroup: peersWorkgroup)))
        for round in 0..<30 {
            let id = "ROUND-\(round)"
            let published = expectation(description: "published \(round)")
            let snapshotted = expectation(description: "snapshot \(round)")
            var replies = [String?]()
            a.gateway.sendList([C.setRecord(sessionID: a.sessionID, instanceID: id, record: record),
                                C.tagPane(paneID: leader, tag: TmuxWorkgroupState.PaneTag(instanceID: id, position: 0))]) { _ in
                published.fulfill()
            }
            b.gateway.sendList(TmuxWorkgroupAdoption.queries(sessionID: b.sessionID)) {
                replies = $0
                snapshotted.fulfill()
            }
            wait(for: [published, snapshotted], timeout: 10)
            let d = TmuxWorkgroupState.derive(
                panes: TmuxWorkgroupAdoption.panes(listPanesReply: replies[1] ?? ""),
                windows: TmuxWorkgroupAdoption.windows(listWindowsReply: replies[2] ?? ""),
                instanceOptions: TmuxWorkgroupAdoption.instanceOptions(showReply: replies[0] ?? ""))
            for i in d.instances where i.instanceID == id {
                XCTAssertFalse(i.problems.contains(.leaderMissing), "round \(round)")
            }
            _ = sendList(a, [C.unsetRecord(sessionID: a.sessionID, instanceID: id), C.untagPane(paneID: leader)])
        }
    }

    // MARK: - Repairs
    //
    // A complete instance (leader in view, two peers parked) is broken the way a crash or someone
    // working in tmux directly would leave it, then repaired by the real repairer under the lock. A
    // freshly attached client then finds nothing to repair, and no pane anyone ran was killed.

    private var repairers = [TmuxWorkgroupRepairer]()

    private func completeInstance(_ client: TmuxTestClient) throws -> (leader: Int, peers: [Int]) {
        let leader = try publish(client)
        XCTAssertEqual(createPeers(client), .finished(created: [1: leader + 1, 2: leader + 2], failed: []))
        let i = try XCTUnwrap(derivation(client).instances.first)
        return (leader, [try XCTUnwrap(i.paneForPosition[1]), try XCTUnwrap(i.paneForPosition[2])])
    }

    private func repair(_ client: TmuxTestClient) -> TmuxWorkgroupRepairer.Outcome? {
        let repairer = TmuxWorkgroupRepairer(gatewayProvider: { [weak client] in client?.gateway },
                                             sessionID: client.sessionID,
                                             instanceID: instance,
                                             identity: client.identity!)
        repairers.append(repairer)
        let done = expectation(description: "repair")
        var outcome: TmuxWorkgroupRepairer.Outcome?
        repairer.run { result in
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: 20)
        return outcome
    }

    private func problems(_ client: TmuxTestClient) throws -> [TmuxWorkgroupState.Problem] {
        return try XCTUnwrap(derivation(client).instances.first).problems
    }

    private func paneIDs() throws -> Set<Int> {
        return Set(try server.lines(["list-panes", "-s", "-t", "s", "-F", "#{pane_id}"]).compactMap { C.paneID(fromReply: $0) })
    }

    private func windowOf(_ paneID: Int) throws -> Int {
        return try server.int(["display", "-p", "-t", "%\(paneID)", "#{window_id}"], prefix: "@")
    }

    private func isParkedWindow(of paneID: Int) throws -> Bool {
        let value = try server.lines(["display", "-p", "-t", "%\(paneID)", "#{@iterm2_wg_parked}"]).first ?? ""
        return value == TmuxWorkgroupState.ParkedTag(instanceID: instance).encoded
    }

    // A peer joined into the leader's window (a client died mid-switch, or someone joined it there).
    // It goes back to a parked window of its own, pinned to the leader's size.
    func testRepairParksAPeerSharingTheLeadersWindow() throws {
        let a = try attach()
        let (leader, peers) = try completeInstance(a)
        _ = try server.lines(["join-pane", "-d", "-s", "%\(peers[0])", "-t", "%\(leader)"])
        XCTAssertEqual(try problems(a), [.extraVisiblePeers(host: 0, positions: [1])])
        let before = try paneIDs()

        XCTAssertEqual(repair(a), .finished(repairs: 1))
        XCTAssertEqual(try problems(a), [])
        XCTAssertEqual(try paneIDs(), before, "no pane was killed")
        XCTAssertTrue(try isParkedWindow(of: peers[0]))
        XCTAssertNotEqual(try windowOf(peers[0]), try windowOf(leader))
        XCTAssertEqual(try server.lines(["display", "-p", "-t", "%\(leader)", "#{window_panes}"]), ["1"])
    }

    // A peer's window lost its parked tag, so the peer is in view in a window of its own. It moves
    // into a new parked window and the window it was in closes.
    func testRepairParksAPeerAloneInAnOrdinaryWindow() throws {
        let a = try attach()
        let (_, peers) = try completeInstance(a)
        _ = try server.lines(["set", "-w", "-u", "-t", "%\(peers[1])", "@iterm2_wg_parked"])
        let oldWindow = try windowOf(peers[1])
        XCTAssertEqual(try problems(a), [.extraVisiblePeers(host: 0, positions: [2])])
        let before = try paneIDs()

        XCTAssertEqual(repair(a), .finished(repairs: 1))
        XCTAssertEqual(try problems(a), [])
        XCTAssertEqual(try paneIDs().subtracting(before), [], "only the placeholder came and went")
        XCTAssertEqual(before.subtracting(try paneIDs()), [])
        XCTAssertTrue(try isParkedWindow(of: peers[1]))
        XCTAssertFalse(try server.lines(["list-windows", "-t", "s", "-F", "#{window_id}"]).contains("@\(oldWindow)"))
    }

    // The peer in view exited: its slot is gone and the leader is parked. The leader comes back in
    // an ordinary window.
    func testRepairBringsOutTheLeaderWhenNothingIsInView() throws {
        let a = try attach()
        let (leader, peers) = try completeInstance(a)
        wait(for: [guarded(a, C.switchPeer(sessionID: a.sessionID, instanceID: instance,
                                           visiblePaneID: leader, targetPaneID: peers[0]))], timeout: 10)
        XCTAssertEqual(a.outcomes.removeLast(), .applied)
        _ = try server.lines(["kill-pane", "-t", "%\(peers[0])"])
        XCTAssertEqual(try problems(a), [.noVisiblePeer(host: 0)])

        XCTAssertEqual(repair(a), .finished(repairs: 1))
        XCTAssertEqual(try problems(a), [])
        XCTAssertFalse(try isParkedWindow(of: leader))
        XCTAssertTrue(try isParkedWindow(of: peers[1]))
        XCTAssertTrue(try paneIDs().contains(leader))
    }

    // Someone split a parked window. The new pane is no member and would never be seen: it comes
    // out into an ordinary window, still running.
    func testRepairBringsOutAPaneStrandedInAParkedWindow() throws {
        let a = try attach()
        let (_, peers) = try completeInstance(a)
        let stranded = try server.int(["split-window", "-d", "-P", "-F", "#{pane_id}", "-t", "%\(peers[0])", "exec sleep 86400"],
                                      prefix: "%")
        XCTAssertEqual(try problems(a), [.strandedInParkedWindow(paneID: stranded)])

        XCTAssertEqual(repair(a), .finished(repairs: 1))
        XCTAssertEqual(try problems(a), [])
        XCTAssertTrue(try paneIDs().contains(stranded), "the user's pane still runs")
        XCTAssertFalse(try isParkedWindow(of: stranded))
        XCTAssertTrue(try isParkedWindow(of: peers[0]))
    }

    // Tags that name no member are removed; the panes keep running.
    func testRepairUntagsDuplicateAndUnknownMembers() throws {
        let a = try attach()
        _ = try completeInstance(a)
        let duplicate = try server.int(["new-window", "-d", "-P", "-F", "#{pane_id}", "-t", "s:", "exec sleep 86400"], prefix: "%")
        let unknown = try server.int(["new-window", "-d", "-P", "-F", "#{pane_id}", "-t", "s:", "exec sleep 86400"], prefix: "%")
        _ = sendList(a, [C.tagPane(paneID: duplicate, tag: TmuxWorkgroupState.PaneTag(instanceID: instance, position: 1)),
                         C.tagPane(paneID: unknown, tag: TmuxWorkgroupState.PaneTag(instanceID: instance, position: 9))])
        XCTAssertEqual(try problems(a), [.duplicateMember(position: 1, paneID: duplicate),
                                          .unknownPosition(paneID: unknown, position: 9)])

        XCTAssertEqual(repair(a), .finished(repairs: 2))
        XCTAssertEqual(try problems(a), [])
        XCTAssertTrue(try paneIDs().isSuperset(of: [duplicate, unknown]))
    }

    // Both clients see the problem and repair at once. The lock serializes them, and the second
    // finds nothing left to do, so the peer is parked once.
    func testTwoClientsRepairingAtOnceRepairOnce() throws {
        let a = try attach()
        let b = try attach()
        let (leader, peers) = try completeInstance(a)
        _ = try server.lines(["join-pane", "-d", "-s", "%\(peers[0])", "-t", "%\(leader)"])
        let windowsBefore = try server.lines(["list-windows", "-t", "s"]).count

        var outcomes = [TmuxWorkgroupRepairer.Outcome]()
        let done = expectation(description: "both")
        done.expectedFulfillmentCount = 2
        let pair = [a, b].map { client in
            TmuxWorkgroupRepairer(gatewayProvider: { [weak client] in client?.gateway },
                                  sessionID: client.sessionID, instanceID: instance,
                                  identity: client.identity!)
        }
        repairers += pair
        for repairer in pair {
            // The second waits on the first's lock. Its release wakes the waiter, as the
            // attacher's lock subscription does in the app.
            repairer.run { outcome in
                outcomes.append(outcome)
                done.fulfill()
                pair.forEach { $0.wake() }
            }
        }
        wait(for: [done], timeout: 30)
        XCTAssertEqual(outcomes.sorted { "\($0)" < "\($1)" }, [.finished(repairs: 0), .finished(repairs: 1)])
        XCTAssertEqual(try problems(a), [])
        XCTAssertEqual(try server.lines(["list-windows", "-t", "s"]).count, windowsBefore + 1, "parked once")
        XCTAssertNil(try server.option("@iterm2_wg_lock"))
    }

    // MARK: - Re-pinning

    private func size(ofPane paneID: Int) throws -> String? {
        return try server.lines(["display", "-p", "-t", "%\(paneID)", "#{pane_width}x#{pane_height}"]).first
    }

    // The slot grew: the parked peer is pinned to it. After a switch the same command, now stale,
    // does nothing, since that pane is in view.
    func testRepinOnlyResizesAParkedPeer() throws {
        let a = try attach()
        let (visible, parked) = try makePeerPair(a)
        _ = try server.lines(["resize-window", "-t", "s:0", "-x", "100", "-y", "30"])
        XCTAssertEqual(try size(ofPane: visible), "100x30")
        let repin = C.repinParkedPeer(sessionID: a.sessionID, instanceID: instance, paneID: parked, width: 100, height: 30)
        wait(for: [guarded(a, repin)], timeout: 10)
        XCTAssertEqual(a.outcomes.removeLast(), .applied)
        XCTAssertEqual(try size(ofPane: parked), "100x30")

        wait(for: [guarded(a, C.switchPeer(sessionID: a.sessionID, instanceID: instance,
                                           visiblePaneID: visible, targetPaneID: parked))], timeout: 10)
        XCTAssertEqual(a.outcomes.removeLast(), .applied)
        let stale = C.repinParkedPeer(sessionID: a.sessionID, instanceID: instance, paneID: parked, width: 50, height: 10)
        wait(for: [guarded(a, stale)], timeout: 10)
        XCTAssertEqual(a.outcomes.removeLast(), .guardFailed)
        XCTAssertEqual(try size(ofPane: parked), "100x30", "the pane in view is not resized")
    }

    // MARK: - Starting and relaunching members

    private func waitUntil(_ what: String, _ condition: () throws -> Bool) rethrows {
        let deadline = Date(timeIntervalSinceNow: 10)
        while try !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(what)")
                return
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private func temporaryDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iterm2wg-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        // tmux reports the real path (/private/var, not /var).
        guard let real = realpath(url.path, nil) else {
            return url.path
        }
        defer { free(real) }
        return String(cString: real)
    }

    /// A waiting peer, parked, running the placeholder in `directory`.
    private func makeWaitingPeer(_ client: TmuxTestClient, directory: String) throws -> Int {
        let replies = sendList(client, C.createParkedPeer(sessionID: client.sessionID, instanceID: instance,
                                                          position: 1, width: 80, height: 24,
                                                          script: C.memberScript(command: C.waitingScript,
                                                                                 directory: directory),
                                                          waiting: true))
        return try XCTUnwrap(C.paneID(fromReply: replies.first ?? nil))
    }

    private func query(_ client: TmuxTestClient, paneID: Int) -> (tag: TmuxWorkgroupState.PaneTag, directory: String?)? {
        return C.parseMemberQuery(sendList(client, [C.memberQuery(paneID: paneID)]).first ?? nil)
    }

    /// Relaunches a member the way this server needs (respawn-pane crashes servers before 3.8) and
    /// returns its pane, which is new when it was replaced.
    private func relaunch(_ client: TmuxTestClient, paneID: Int, script: String,
                          tag: TmuxWorkgroupState.PaneTag) throws -> Int {
        let method = C.RelaunchMethod(respawnIsSafe: try server.isAtLeast(C.RelaunchMethod.safeRespawnVersion),
                                      sessionID: client.sessionID, instanceID: instance)
        let replies = sendList(client, C.relaunchMember(paneID: paneID, script: script, tag: tag,
                                                        method: method, remainOnExit: true))
        guard case .replace = method else {
            return paneID
        }
        return try XCTUnwrap(C.paneID(fromReply: replies.first ?? nil))
    }

    private func panes() throws -> [String] {
        return try server.lines(["list-panes", "-s", "-t", "s", "-F", "#{pane_id} #{window_id} #{@iterm2_wg}"])
    }

    private func windowCount() throws -> Int {
        return try server.lines(["list-windows", "-t", "s"]).count
    }

    // Replacing (tmux before 3.8): a new pane takes the member's place in its window, with its tag,
    // and the old one is gone, as is the window the new one started in. For a parked peer and for a
    // member in view.
    func testReplacingKeepsTheMemberInPlace() throws {
        let a = try attach()
        let directory = try temporaryDirectory()
        let (visible, parked) = try makePeerPair(a)
        let visibleTag = TmuxWorkgroupState.PaneTag(instanceID: instance, position: 0)
        _ = sendList(a, [C.tagPane(paneID: visible, tag: visibleTag)])
        let parkedTag = TmuxWorkgroupState.PaneTag(instanceID: instance, position: 1)
        let replace = C.RelaunchMethod.replace(sessionID: a.sessionID, instanceID: instance)
        let windows = try windowCount()
        for (old, tag, name) in [(parked, parkedTag, "parked"), (visible, visibleTag, "visible")] {
            let window = try server.lines(["display", "-p", "-t", "%\(old)", "#{window_id}"]).first
            let replies = sendList(a, C.relaunchMember(paneID: old,
                                                       script: C.memberScript(command: "echo \(name) > \(name); exec sleep 86400",
                                                                              directory: directory),
                                                       tag: tag, method: replace, remainOnExit: false))
            XCTAssertFalse(replies.contains { $0 == nil }, "\(name): \(replies)")
            let new = try XCTUnwrap(C.paneID(fromReply: replies.first ?? nil))
            XCTAssertNotEqual(new, old)
            let rows = try panes()
            XCTAssertFalse(rows.contains { $0.hasPrefix("%\(old) ") }, "\(name): the old pane is gone")
            XCTAssertEqual(rows.filter { $0.hasSuffix(" " + tag.encoded) }, ["%\(new) \(window ?? "") \(tag.encoded)"],
                           "\(name): the new pane is the only one at the position, in the same window")
            XCTAssertEqual(try windowCount(), windows, "\(name): the window it started in is gone")
            waitUntil("the \(name) program") { FileManager.default.fileExists(atPath: directory + "/" + name) }
        }
    }

    // Both clients' pollers see changes at once and both would start the diff. Exactly one claims
    // the start; it then relaunches it in the directory the member was created in.
    func testStartingAWaitingMemberRacesToOneWinner() throws {
        let a = try attach()
        let b = try attach()
        let directory = try temporaryDirectory()
        let peer = try makeWaitingPeer(a, directory: directory)
        let waiting = TmuxWorkgroupState.PaneTag(instanceID: instance, position: 1, waiting: true)
        try waitUntil("the placeholder to run in its directory") {
            try server.lines(["display", "-p", "-t", "%\(peer)", "#{pane_current_path}"]).first == directory
        }
        let queried = try XCTUnwrap(query(b, paneID: peer))
        XCTAssertEqual(queried.tag, waiting)
        XCTAssertEqual(queried.directory, directory)

        let command = C.startWaitingMember(paneID: peer, tag: waiting)
        wait(for: [guarded(a, command), guarded(b, command)], timeout: 10)
        let outcomes = [a.outcomes.removeLast(), b.outcomes.removeLast()]
        XCTAssertEqual(outcomes.filter { $0 == .applied }.count, 1, "\(outcomes)")
        XCTAssertEqual(outcomes.filter { $0 == .guardFailed }.count, 1, "\(outcomes)")
        XCTAssertEqual(try XCTUnwrap(query(a, paneID: peer)).tag, waiting.started)

        let winner = outcomes[0] == .applied ? a : b
        _ = try relaunch(winner, paneID: peer,
                         script: C.memberScript(command: "pwd > ran; exec sleep 86400", directory: directory),
                         tag: waiting.started)
        let ran = directory + "/ran"
        waitUntil("the member's program to run") { FileManager.default.fileExists(atPath: ran) }
        XCTAssertEqual(try String(contentsOfFile: ran, encoding: .utf8), directory + "\n")
    }

    // A member whose program exits stays, as a local one does until Reload, and can be relaunched.
    // Relaunching one still waiting also starts it.
    func testRelaunchAfterTheProgramExits() throws {
        let a = try attach()
        let directory = try temporaryDirectory()
        let peer = try makeWaitingPeer(a, directory: directory)
        let waiting = TmuxWorkgroupState.PaneTag(instanceID: instance, position: 1, waiting: true)
        let exited = try relaunch(a, paneID: peer, script: C.memberScript(command: "exit 3", directory: directory),
                                  tag: waiting)
        try waitUntil("the program to exit") {
            try server.lines(["display", "-p", "-t", "%\(exited)", "#{pane_dead}"]).first == "1"
        }
        let dead = try XCTUnwrap(query(a, paneID: exited))
        XCTAssertEqual(dead.tag, waiting.started)
        XCTAssertNil(dead.directory, "a dead pane has no current directory")

        let again = try relaunch(a, paneID: exited,
                                 script: C.memberScript(command: "echo again > again; exec sleep 86400",
                                                        directory: directory),
                                 tag: dead.tag)
        waitUntil("the relaunched program") { FileManager.default.fileExists(atPath: directory + "/again") }
        XCTAssertEqual(try server.lines(["display", "-p", "-t", "%\(again)", "#{pane_dead}"]), ["0"])
    }

    // The code review's inputs are written by the script that runs it, byte for byte.
    func testWriteFilesScriptWritesExactContents() throws {
        let a = try attach()
        let directory = try temporaryDirectory()
        let peer = try makeWaitingPeer(a, directory: directory)
        let inputs = directory + "/home/.iterm2/code-review"
        let tricky = "it's 100% \"quoted\" $HOME `id` \\n\n\u{1F600} {{it2}}\n"
        let script = C.writeFilesScript(directory: inputs, files: [("a.txt", tricky), ("b.txt", "{}")]) +
            "\nexec sleep 86400"
        _ = try relaunch(a, paneID: peer, script: script,
                         tag: TmuxWorkgroupState.PaneTag(instanceID: instance, position: 1))
        waitUntil("the inputs") { FileManager.default.fileExists(atPath: inputs + "/b.txt") }
        XCTAssertEqual(try String(contentsOfFile: inputs + "/a.txt", encoding: .utf8), tricky)
        XCTAssertEqual(try String(contentsOfFile: inputs + "/b.txt", encoding: .utf8), "{}")
        let mode = try FileManager.default.attributesOfItem(atPath: inputs + "/a.txt")[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testServerHome() throws {
        let a = try attach()
        _ = try server.lines(["set-environment", "-g", "HOME", "/tmp/a home"])
        XCTAssertEqual(C.home(fromReply: sendList(a, [C.homeQuery]).first ?? nil), "/tmp/a home")
    }
}

// MARK: - Test infrastructure

/// A private tmux server: its own socket name and no configuration file.
final class TmuxTestServer {
    let tmuxPath: String
    let socketName = "iterm2wg\(getpid())\(UUID().uuidString.prefix(8))"

    init(tmuxPath: String) throws {
        self.tmuxPath = tmuxPath
        _ = try lines(["new-session", "-d", "-s", "s", "-x", "120", "-y", "40", "exec sleep 86400"])
    }

    var baseArguments: [String] {
        return ["-L", socketName, "-f", "/dev/null"]
    }

    func lines(_ arguments: [String]) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = baseArguments + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    func int(_ arguments: [String], prefix: String) throws -> Int {
        let line = try XCTUnwrap(try lines(arguments).first, "\(arguments)")
        return try XCTUnwrap(Int(line.dropFirst(prefix.count)), "\(arguments): \(line)")
    }

    /// From `tmux -V`, e.g. "tmux 3.2a" or "tmux next-3.9". The test clients' gateways do not ask.
    func isAtLeast(_ version: String) throws -> Bool {
        let reported = try XCTUnwrap(try lines(["-V"]).first)
        let number = reported.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
        return NSDecimalNumber(string: String(number)).compare(NSDecimalNumber(string: version)) != .orderedAscending
    }

    func option(_ name: String) throws -> String? {
        return try lines(["show", "-v", "-q", "-t", "s", name]).first
    }

    func kill() {
        _ = try? lines(["kill-server"])
    }
}

/// Calls a closure when the gateway replies.
final class TmuxTestReply: NSObject {
    private let block: (String?) -> Void

    init(_ block: @escaping (String?) -> Void) {
        self.block = block
    }

    @objc func handle(_ reply: String?) {
        block(reply)
    }
}

/// One `tmux -C attach` client driven by a real TmuxGateway.
final class TmuxTestClient: TmuxTestGatewayDelegate {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var readyBlocks = [() -> Void]()
    private var replies = [TmuxTestReply]()
    private var stopped = false
    private(set) var gateway: TmuxGateway!
    private(set) var sessionID = -1
    var identity: TmuxWorkgroupCommands.ClientIdentity?
    var outcomes = [TmuxWorkgroupCommands.GuardOutcome]()

    init(server: TmuxTestServer) throws {
        super.init()
        gateway = TmuxGateway(delegate: self, dcsID: "live")
        gateway.minimumServerVersion = NSDecimalNumber(string: "3.2")
        // A pty turns the gateway's \r into \n; a pipe does not, and tmux reads lines up to \n.
        gateway.newline = "\n"
        process.executableURL = URL(fileURLWithPath: server.tmuxPath)
        process.arguments = server.baseArguments + ["-C", "attach", "-t", "s"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                self?.didRead(data)
            }
        }
        try process.run()
    }

    func whenReady(_ block: @escaping () -> Void) {
        if sessionID >= 0 {
            block()
        } else {
            readyBlocks.append(block)
        }
    }

    /// A reply target kept alive until the client is torn down.
    func reply(_ block: @escaping (String?) -> Void) -> TmuxTestReply {
        let reply = TmuxTestReply(block)
        replies.append(reply)
        return reply
    }

    func stop() {
        guard !stopped else {
            return
        }
        stopped = true
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    private func didRead(_ data: Data) {
        guard !stopped, !data.isEmpty else {
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            let token = VT100Token()
            token.type = TMUX_LINE
            token.string = line
            token.savedData = Data(line.utf8)
            gateway.execute(token)
        }
    }

    // MARK: TmuxGatewayDelegate

    override func tmuxWrite(_ string: String!) {
        guard !stopped else {
            return
        }
        input.fileHandleForWriting.write(Data(string.utf8))
    }

    override func tmuxSessionChanged(_ sessionName: String!, sessionId: Int32) {
        sessionID = Int(sessionId)
        let blocks = readyBlocks
        readyBlocks.removeAll()
        blocks.forEach { $0() }
    }
}

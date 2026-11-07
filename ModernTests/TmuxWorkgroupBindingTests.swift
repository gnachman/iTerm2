//
//  TmuxWorkgroupBindingTests.swift
//  iTerm2 ModernTests
//
//  The commands an instance whose leader is a tmux Integration pane sends to publish itself and
//  to create its members, in order, against a real TmuxGateway with no tmux behind it.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupBindingTests: XCTestCase {
    private typealias C = TmuxWorkgroupCommands

    private var tmux: TmuxRecordingGateway!
    private var binding: TmuxWorkgroupBinding!

    private let splitSettings = SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)

    // Positions: 0 root, 1 split, 2 tab.
    private var workgroup: iTermWorkgroup {
        func config(_ id: String, _ kind: iTermWorkgroupSessionConfig.Kind, parent: String?) -> iTermWorkgroupSessionConfig {
            return iTermWorkgroupSessionConfig(uniqueIdentifier: id, parentID: parent, kind: kind, profileGUID: nil,
                                               command: "", urlString: "", toolbarItems: [], displayName: id)
        }
        return iTermWorkgroup(uniqueIdentifier: "WG", name: "W", sessions: [
            config("ROOT", .root, parent: nil),
            config("SPLIT", .split(splitSettings), parent: "ROOT"),
            config("TAB", .tab, parent: "ROOT"),
        ])
    }

    override func setUp() {
        super.setUp()
        tmux = TmuxRecordingGateway()
        let gateway = tmux.gateway
        binding = TmuxWorkgroupBinding(gatewayProvider: { gateway }, sessionID: 4, workgroup: workgroup,
                                       instanceID: "INSTANCE", gitBase: "main")
    }

    // The record and the leader's tag go in one command list, so no other client can read the state
    // in between and see a record with no leader.
    func testPublishWritesTheRecordAndTheLeadersTagTogether() throws {
        binding.publish(leaderPaneID: 0)
        let record = TmuxWorkgroupState.InstanceRecord(workgroupID: "WG", gitBase: "main",
                                                       skeleton: try XCTUnwrap(TmuxWorkgroupState.Skeleton(workgroup: workgroup)))
        XCTAssertEqual(tmux.written, [
            C.setRecord(sessionID: 4, instanceID: "INSTANCE", record: record) + "; " +
            C.tagPane(paneID: 0, tag: TmuxWorkgroupState.PaneTag(instanceID: "INSTANCE", position: 0)),
        ])
    }

    private func record(gitBase: String = "main", codeReviewModel: String? = nil,
                        workgroupID: String = "WG") throws -> TmuxWorkgroupState.InstanceRecord {
        return TmuxWorkgroupState.InstanceRecord(workgroupID: workgroupID, gitBase: gitBase,
                                                 skeleton: try XCTUnwrap(TmuxWorkgroupState.Skeleton(workgroup: workgroup)),
                                                 codeReviewModel: codeReviewModel)
    }

    private var showRecord: String {
        return C.showRecord(sessionID: 4, instanceID: "INSTANCE")
    }

    private func replaceRecord(expected: TmuxWorkgroupState.InstanceRecord,
                               with record: TmuxWorkgroupState.InstanceRecord) throws -> String {
        return try XCTUnwrap(C.replaceRecord(sessionID: 4, instanceID: "INSTANCE",
                                             expected: expected.encoded, record: record))
    }

    // Answers a guarded command: the `if`, then the branch that ran.
    private func replyToGuard(applied: Bool) {
        tmux.reply()
        tmux.reply(applied ? [] : [C.guardFailedMarker])
    }

    private func publish() {
        binding.publish(leaderPaneID: 0)
        tmux.reply()
        tmux.reply()
    }

    // A change once the record is on the server reads it back and writes it with the change, if
    // it still has the value that was read.
    func testUpdateRecordRewritesThePublishedRecord() throws {
        publish()
        let published = tmux.written.count
        binding.updateRecord { $0.codeReviewModel = "opus" }
        XCTAssertEqual(Array(tmux.written.dropFirst(published)), [showRecord])
        tmux.reply([try record().encoded])
        XCTAssertEqual(Array(tmux.written.dropFirst(published)), [
            showRecord,
            try replaceRecord(expected: try record(), with: try record(codeReviewModel: "opus")),
        ])
        replyToGuard(applied: true)
        XCTAssertEqual(tmux.written.count, published + 2)
    }

    // Another client changed a different field since this one last wrote. Only this client's
    // field changes; theirs stays.
    func testUpdateRecordKeepsAnotherClientsChange() throws {
        publish()
        binding.updateRecord { $0.codeReviewModel = "sonnet" }
        tmux.reply([try record().encoded])
        replyToGuard(applied: true)
        let before = tmux.written.count
        binding.updateRecord { $0.gitBase = "develop" }
        // Meanwhile another client set the model to opus.
        tmux.reply([try record(codeReviewModel: "opus").encoded])
        XCTAssertEqual(Array(tmux.written.dropFirst(before)), [
            showRecord,
            try replaceRecord(expected: try record(codeReviewModel: "opus"),
                              with: try record(gitBase: "develop", codeReviewModel: "opus")),
        ])
    }

    // Another client changed the record between this one's read and its write: the guard fails,
    // and the change is applied again to a fresh read.
    func testUpdateRecordKeepsANewerClientsField() throws {
        publish()
        binding.updateRecord { $0.gitBase = "develop" }
        // The record as a newer client wrote it, with a key this build doesn't know.
        let ours = try XCTUnwrap(TmuxWorkgroupState.hexDecoded(String(try record().encoded.dropFirst(2))))
        var newer = try XCTUnwrap(try JSONSerialization.jsonObject(with: ours) as? [String: Any])
        newer["future"] = "kept"
        let raw = "g_" + TmuxWorkgroupState.hexEncoded(try JSONSerialization.data(withJSONObject: newer, options: .sortedKeys))
        tmux.reply([raw])
        var expected = try XCTUnwrap(TmuxWorkgroupState.InstanceRecord(encoded: raw))
        expected.gitBase = "develop"
        XCTAssertEqual(tmux.written.last,
                       try XCTUnwrap(C.replaceRecord(sessionID: 4, instanceID: "INSTANCE", expected: raw, record: expected)))
        XCTAssertTrue(expected.encoded.contains(TmuxWorkgroupState.hexEncoded(Data(#""future":"kept""#.utf8))))
    }

    func testRecordChangedBetweenReadAndWriteIsReadAgain() throws {
        publish()
        binding.updateRecord { $0.gitBase = "develop" }
        tmux.reply([try record().encoded])
        let firstWrite = tmux.written.count
        replyToGuard(applied: false)
        XCTAssertEqual(Array(tmux.written.dropFirst(firstWrite)), [showRecord])
        tmux.reply([try record(codeReviewModel: "opus").encoded])
        XCTAssertEqual(tmux.written.last,
                       try replaceRecord(expected: try record(codeReviewModel: "opus"),
                                         with: try record(gitBase: "develop", codeReviewModel: "opus")))
    }

    // Another client ended the instance between this one's read and its write: the guard fails,
    // and the fresh read finds no record, so nothing brings it back.
    func testRecordRemovedBetweenReadAndWriteStaysRemoved() throws {
        publish()
        binding.updateRecord { $0.codeReviewModel = "opus" }
        tmux.reply([try record().encoded])
        replyToGuard(applied: false)
        tmux.reply([""])
        XCTAssertEqual(tmux.written.last, showRecord)
    }

    // Other clients keep winning: give up rather than retry forever.
    func testUpdateRecordGivesUpAfterRepeatedConflicts() throws {
        publish()
        binding.updateRecord { $0.codeReviewModel = "opus" }
        for _ in 0..<3 {
            tmux.reply([try record().encoded])
            replyToGuard(applied: false)
        }
        XCTAssertNotEqual(tmux.written.last, showRecord)
        let afterGivingUp = tmux.written.count
        // A later change starts afresh.
        binding.updateRecord { $0.gitBase = "develop" }
        XCTAssertEqual(Array(tmux.written.dropFirst(afterGivingUp)), [showRecord])
    }

    // A second change while the first is in flight waits for the first's write, so its read sees
    // it, and both changes land.
    func testUpdatesInQuickSuccessionBothLand() throws {
        publish()
        let published = tmux.written.count
        binding.updateRecord { $0.codeReviewModel = "opus" }
        binding.updateRecord { $0.gitBase = "develop" }
        XCTAssertEqual(Array(tmux.written.dropFirst(published)), [showRecord])
        tmux.reply([try record().encoded])
        replyToGuard(applied: true)
        XCTAssertEqual(Array(tmux.written.dropFirst(published)), [
            showRecord,
            try replaceRecord(expected: try record(), with: try record(codeReviewModel: "opus")),
            showRecord,
        ])
        tmux.reply([try record(codeReviewModel: "opus").encoded])
        XCTAssertEqual(tmux.written.last,
                       try replaceRecord(expected: try record(codeReviewModel: "opus"),
                                         with: try record(gitBase: "develop", codeReviewModel: "opus")))
    }

    // Already the server's value: nothing to write.
    func testUpdateRecordWithNoChangeWritesNothing() throws {
        publish()
        binding.updateRecord { $0.gitBase = "main" }
        let read = tmux.written.count
        tmux.reply([try record().encoded])
        XCTAssertEqual(tmux.written.count, read)
    }

    // A record that's gone ended elsewhere; writing would bring it back.
    func testUpdateRecordWritesNothingWhenTheRecordIsGone() {
        publish()
        binding.updateRecord { $0.codeReviewModel = "opus" }
        let read = tmux.written.count
        tmux.reply([""])
        XCTAssertEqual(tmux.written.count, read)
    }

    // Before publish, writing would leave a record with no tagged leader, which other clients
    // remove as ended. The change waits for publish instead.
    func testUpdateRecordBeforePublishWaitsForIt() throws {
        binding.updateRecord { $0.codeReviewModel = "opus" }
        XCTAssertEqual(tmux.written, [])
        binding.publish(leaderPaneID: 0)
        XCTAssertEqual(tmux.written, [
            C.setRecord(sessionID: 4, instanceID: "INSTANCE", record: try record(codeReviewModel: "opus")) + "; " +
            C.tagPane(paneID: 0, tag: TmuxWorkgroupState.PaneTag(instanceID: "INSTANCE", position: 0)),
        ])
    }

    // Once removal starts, a write would bring the record back.
    func testUpdateRecordAfterRemovalStartsWritesNothing() {
        binding.publish(leaderPaneID: 0)
        binding.removeFromServer()
        let removing = tmux.written.count
        binding.updateRecord { $0.codeReviewModel = "opus" }
        XCTAssertEqual(tmux.written.count, removing)
    }

    // Removal that starts while the record is being read stops the write.
    func testRemovalDuringTheReadWritesNothing() throws {
        publish()
        binding.updateRecord { $0.codeReviewModel = "opus" }
        binding.removeFromServer()
        let removing = tmux.written.count
        tmux.reply([try record().encoded])
        XCTAssertEqual(tmux.written.count, removing)
    }

    // An adopted binding rewrites the server's record, so the workgroup ID there, a hint other
    // clients rely on, stays as it was rather than becoming this client's workgroup's ID.
    func testAdoptedBindingKeepsTheRecordsWorkgroupID() throws {
        binding.adoptLeader(paneID: 0)
        binding.updateRecord { $0.codeReviewModel = "opus" }
        let theirs = try record(codeReviewModel: "sonnet", workgroupID: "THEIRS")
        tmux.reply([theirs.encoded])
        XCTAssertEqual(tmux.written, [
            showRecord,
            try replaceRecord(expected: theirs, with: try record(codeReviewModel: "opus", workgroupID: "THEIRS")),
        ])
    }

    // Ask for the parent's directory, then split there running the command and tag the new pane,
    // in one list.
    func testCreateSplit() {
        var created: Int?? = .none
        binding.createSplit(configID: "SPLIT", settings: splitSettings, command: "make test", parentPaneID: 3) {
            created = .some($0)
        }
        XCTAssertEqual(tmux.written, ["display -p -t %3 '#{pane_current_path}'"])
        tmux.reply(["/home/u/repo"])
        let split = C.splitWindow(targetPaneID: 3, settings: splitSettings,
                                  script: C.memberScript(command: "make test", directory: "/home/u/repo"),
                                  tag: TmuxWorkgroupState.PaneTag(instanceID: "INSTANCE", position: 1))
        XCTAssertEqual(tmux.written.last, split.joined(separator: "; "))
        tmux.reply(["%7"])
        tmux.reply()
        tmux.reply()
        tmux.reply()  // remain-on-exit
        XCTAssertEqual(created, .some(7))
        XCTAssertEqual(tmux.written.count, 2, "nothing more to send")
    }

    func testCreateWindow() {
        var created: Int?? = .none
        binding.createWindow(configID: "TAB", command: "top", parentPaneID: 3) { created = .some($0) }
        tmux.reply(["/home/u"])
        XCTAssertEqual(tmux.written.last,
                       C.newWindow(sessionID: 4, script: C.memberScript(command: "top", directory: "/home/u"),
                                   tag: TmuxWorkgroupState.PaneTag(instanceID: "INSTANCE", position: 2))
                        .joined(separator: "; "))
        tmux.reply(["%8"])
        tmux.reply()
        tmux.reply()  // remain-on-exit
        XCTAssertEqual(created, .some(8))
    }

    // The directory comes from tmux, which may be a fake server: it is sent back only encoded.
    func testDirectoryFromTmuxIsSentBackOnlyEncoded() throws {
        binding.createSplit(configID: "SPLIT", settings: splitSettings, command: "", parentPaneID: 3) { _ in }
        tmux.reply([#"/x'; touch pwned; '"#])
        let split = try XCTUnwrap(tmux.written.last)
        XCTAssertFalse(split.contains("pwned"), split)
        XCTAssertEqual(split.filter { $0 == "'" }.count, 4, "only the wrapper's own quotes: \(split)")
    }

    func testTmuxRefusingTheSplitCreatesNothing() {
        var created: Int?? = .none
        binding.createSplit(configID: "SPLIT", settings: splitSettings, command: "", parentPaneID: 3) {
            created = .some($0)
        }
        tmux.reply(["/home/u"])
        // The split fails, so tmux runs nothing after it in the list (no tag) and sends no more blocks.
        tmux.reply(["no space for new pane"], error: true)
        XCTAssertEqual(created, .some(nil))
    }

    func testUnknownMemberCreatesNothing() {
        var created: Int?? = .none
        binding.createSplit(configID: "NOPE", settings: splitSettings, command: "", parentPaneID: 3) {
            created = .some($0)
        }
        XCTAssertEqual(created, .some(nil))
        XCTAssertEqual(tmux.written, [])
    }

    // MARK: - Ending the instance

    private func tag(_ instance: String, _ position: Int) -> String {
        return TmuxWorkgroupState.PaneTag(instanceID: instance, position: position).encoded
    }

    // Untag the leader and unset the record in one list, then kill this instance's members (found
    // by tag, not by what this Mac knows) one at a time.
    private var removalQueries: String {
        return ["list-panes -s -t $4 -F '#{pane_id} #{@iterm2_wg}'",
                TmuxWorkgroupBinding.leaderWindowQuery(sessionID: 4)].joined(separator: "; ")
    }

    func testRemoveFromServer() {
        binding.publish(leaderPaneID: 0)
        let published = tmux.written.count
        tmux.reply()
        tmux.reply()
        binding.removeFromServer()
        XCTAssertEqual(tmux.written.dropFirst(published), [removalQueries])
        tmux.reply(["%0 " + tag("INSTANCE", 0), "%5 " + tag("INSTANCE", 1), "%6 ", "%7 " + tag("OTHER", 1),
                    "%9 " + tag("INSTANCE", 2), "%x " + tag("INSTANCE", 2), "%8 garbage"])
        tmux.reply(["%0 @1 1 ", "%5 @2 1 " + TmuxWorkgroupState.ParkedTag(instanceID: "INSTANCE").encoded])
        XCTAssertEqual(tmux.written.dropFirst(published + 1), [
            C.endInstance(sessionID: 4, instanceID: "INSTANCE", leaderPaneID: 0).joined(separator: "; "),
            "kill-pane -t %5",
            "kill-pane -t %9",
        ])
    }

    // The member in view was closed, taking the leader's tab with it: the leader is parked, and is
    // brought out before the members go, or it would stay hidden.
    func testRemovingBringsAParkedLeaderOut() {
        binding.publish(leaderPaneID: 0)
        tmux.reply()
        tmux.reply()
        let published = tmux.written.count
        binding.removeFromServer()
        tmux.reply(["%0 " + tag("INSTANCE", 0), "%5 " + tag("INSTANCE", 2)])
        tmux.reply(["%0 @3 1 " + TmuxWorkgroupState.ParkedTag(instanceID: "INSTANCE").encoded, "%5 @4 1 "])
        XCTAssertEqual(tmux.written.dropFirst(published + 1), [
            C.endInstance(sessionID: 4, instanceID: "INSTANCE", leaderPaneID: 0).joined(separator: "; "),
            C.bringOutPane(sessionID: 4, paneID: 0, windowID: 3, sharesWindow: false).joined(separator: "; "),
            "kill-pane -t %5",
        ])
    }

    // If tmux can't say where the leader is, it asks again before ending the instance, rather than
    // leaving a parked leader hidden. QA finding F-803.
    func testAFailedLeaderWindowQueryIsAskedAgain() {
        binding.publish(leaderPaneID: 0)
        tmux.reply()
        tmux.reply()
        let published = tmux.written.count
        binding.removeFromServer()
        tmux.reply(["%0 " + tag("INSTANCE", 0), "%5 " + tag("INSTANCE", 2)])
        tmux.reply(["no server running"], error: true)
        XCTAssertEqual(tmux.written.dropFirst(published + 1), [TmuxWorkgroupBinding.leaderWindowQuery(sessionID: 4)],
                       "nothing is ended until it is known whether the leader is parked")
        tmux.reply(["%0 @3 1 " + TmuxWorkgroupState.ParkedTag(instanceID: "INSTANCE").encoded, "%5 @4 1 "])
        XCTAssertEqual(tmux.written.dropFirst(published + 2), [
            C.endInstance(sessionID: 4, instanceID: "INSTANCE", leaderPaneID: 0).joined(separator: "; "),
            C.bringOutPane(sessionID: 4, paneID: 0, windowID: 3, sharesWindow: false).joined(separator: "; "),
            "kill-pane -t %5",
        ])
    }

    // Only this Mac's session went away (a hidden window): the instance stays on the server.
    func testPaneStillThereChangesNothing() {
        binding.removeFromServerIfPaneIsGone(5)
        XCTAssertEqual(tmux.written, ["display -p -t %5 '#{pane_id}'"])
        tmux.reply(["%5"])
        XCTAssertEqual(tmux.written.count, 1)
    }

    // The pane really ended: the instance ends on the server.
    func testPaneGoneRemovesTheInstance() {
        binding.removeFromServerIfPaneIsGone(5)
        tmux.reply(["can't find pane: %5"], error: true)
        XCTAssertEqual(tmux.written.last, removalQueries)
    }

    // The leader's program exited, so its instance ended here and released its binding before
    // tmux answered (seen 2026-10-09: the answer took a second). The answer still ends the instance
    // on the server. tmux answers an empty line, not an error, for a pane that is gone.
    func testPaneGoneRemovesTheInstanceAfterTheBindingIsReleased() {
        binding.publish(leaderPaneID: 4)
        tmux.reply()
        tmux.reply()
        binding.removeFromServerIfPaneIsGone(4)
        XCTAssertEqual(tmux.written.last, "display -p -t %4 '#{pane_id}'")
        weak var released = binding
        binding = nil
        XCTAssertNil(released, "nothing else holds the binding of an ended instance")
        tmux.reply([""])
        XCTAssertEqual(tmux.written.last, removalQueries)
        tmux.reply(["%5 " + tag("INSTANCE", 1)])
        tmux.reply(["%5 @2 1 "])
        // The leader's pane is gone, so it is not untagged: in a list, that failing command would
        // stop the record from being unset.
        XCTAssertEqual(tmux.written.suffix(2), [
            C.endInstance(sessionID: 4, instanceID: "INSTANCE", leaderPaneID: nil).joined(separator: "; "),
            "kill-pane -t %5",
        ])
    }

    // An unstorable shape (here, two roots) means no binding: the instance behaves as before.
    func testNoBindingForAnInvalidWorkgroup() {
        let broken = iTermWorkgroup(uniqueIdentifier: "B", name: "", sessions: workgroup.sessions + [
            iTermWorkgroupSessionConfig(uniqueIdentifier: "ROOT2", parentID: nil, kind: .root, profileGUID: nil,
                                        command: "", urlString: "", toolbarItems: [], displayName: ""),
        ])
        let gateway = tmux.gateway
        XCTAssertNil(TmuxWorkgroupBinding(gatewayProvider: { gateway }, sessionID: 4, workgroup: broken,
                                          instanceID: "I", gitBase: "main"))
    }
}

// Ending an instance whose leader is parked brings the leader out, or it would stay hidden with
// no workgroup left to switch back to it.
final class TmuxWorkgroupParkedLeaderTests: XCTestCase {
    private typealias B = TmuxWorkgroupBinding
    private let parked = TmuxWorkgroupState.ParkedTag(instanceID: "I").encoded

    func testAParkedLeaderAloneInItsWindowIsBroughtOut() {
        let reply = "%0 @3 1 \(parked)\n%2 @1 1 "
        XCTAssertEqual(B.bringOutParkedLeader(windowsReply: reply, leaderPaneID: 0, sessionID: 5),
                       TmuxWorkgroupCommands.bringOutPane(sessionID: 5, paneID: 0, windowID: 3, sharesWindow: false))
    }

    func testOneSharingItsWindowIsBrokenOut() {
        XCTAssertEqual(B.bringOutParkedLeader(windowsReply: "%0 @3 2 \(parked)", leaderPaneID: 0, sessionID: 5),
                       TmuxWorkgroupCommands.bringOutPane(sessionID: 5, paneID: 0, windowID: 3, sharesWindow: true))
    }

    // In view, gone, or reported in a way that can't be read: nothing to do.
    func testOtherwiseNothing() {
        XCTAssertNil(B.bringOutParkedLeader(windowsReply: "%0 @1 1 ", leaderPaneID: 0, sessionID: 5))
        XCTAssertNil(B.bringOutParkedLeader(windowsReply: "%0 @1 1", leaderPaneID: 0, sessionID: 5))
        XCTAssertNil(B.bringOutParkedLeader(windowsReply: "%7 @3 1 \(parked)", leaderPaneID: 0, sessionID: 5))
        XCTAssertNil(B.bringOutParkedLeader(windowsReply: "%0 x 1 \(parked)", leaderPaneID: 0, sessionID: 5))
        XCTAssertNil(B.bringOutParkedLeader(windowsReply: "%0 @3 1 p_garbage", leaderPaneID: 0, sessionID: 5))
        XCTAssertNil(B.bringOutParkedLeader(windowsReply: nil, leaderPaneID: 0, sessionID: 5))
    }

    func testTheQueryReadsWindowAndParkedTag() {
        XCTAssertEqual(B.leaderWindowQuery(sessionID: 5),
                       "list-panes -s -t $5 -F '#{pane_id} #{window_id} #{window_panes} #{@iterm2_wg_parked}'")
    }
}

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
    func testRemoveFromServer() {
        binding.publish(leaderPaneID: 0)
        let published = tmux.written.count
        tmux.reply()
        tmux.reply()
        binding.removeFromServer()
        XCTAssertEqual(tmux.written.dropFirst(published),
                       ["list-panes -s -t $4 -F '#{pane_id} #{@iterm2_wg}'"])
        tmux.reply(["%0 " + tag("INSTANCE", 0), "%5 " + tag("INSTANCE", 1), "%6 ", "%7 " + tag("OTHER", 1),
                    "%9 " + tag("INSTANCE", 2), "%x " + tag("INSTANCE", 2), "%8 garbage"])
        XCTAssertEqual(tmux.written.dropFirst(published + 1), [
            C.endInstance(sessionID: 4, instanceID: "INSTANCE", leaderPaneID: 0).joined(separator: "; "),
            "kill-pane -t %5",
            "kill-pane -t %9",
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
        XCTAssertEqual(tmux.written.last, "list-panes -s -t $4 -F '#{pane_id} #{@iterm2_wg}'")
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
        XCTAssertEqual(tmux.written.last, "list-panes -s -t $4 -F '#{pane_id} #{@iterm2_wg}'")
        tmux.reply(["%5 " + tag("INSTANCE", 1)])
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

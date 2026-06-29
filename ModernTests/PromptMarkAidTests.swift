//
//  PromptMarkAidTests.swift
//  iTerm2
//
//  OSC 133 `aid=<id>` plumbing for nested shell-integration sessions.
//  Covers: parser (aidFromArgs:, exitCodeFromArgs:hasCode:), receiver
//  stamping (mark.aid + mark.parentAid populated correctly), the layered-
//  cycle case (local-shell -> ssh -> remote-shell), cascade close (the
//  ssh-dies scenario where D;aid=outer closes outer AND every still-open
//  mark whose parentAid chain leads back to outer), backward compat
//  (aid-less streams behave bit-identical to today), and dict round-trip.
//

import XCTest
@testable import iTerm2SharedARC

final class PromptMarkAidTests: XCTestCase {

    // MARK: - Helpers

    private func osc133Bytes(command: String, args: [String]) -> [UInt8] {
        var s = "\u{1B}]133;\(command)"
        for a in args {
            s.append(";")
            s.append(a)
        }
        s.append("\u{07}")
        return Array(s.utf8)
    }

    private func sendOSC(_ bytes: [UInt8], on harness: TerminalTestHarness) {
        bytes.withUnsafeBufferPointer { ptr in
            let chars = UnsafeMutablePointer<CChar>(
                mutating: UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: CChar.self))
            harness.screen.threadedReadTask(chars, length: Int32(bytes.count))
        }
        harness.sync()
    }

    private func promptMarks(in harness: TerminalTestHarness) -> [VT100ScreenMark] {
        return harness.allScreenMarks().filter { $0.isPrompt }
    }

    // MARK: - Group N1: parser (drive via raw OSC bytes through executeFinalTermToken:)

    func test_parser_A_aid_stampsAidOnMark() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        sendOSC(osc133Bytes(command: "A", args: ["aid=x1"]), on: harness)
        // Some shell output between A and B
        harness.appendText("$ ")
        sendOSC(osc133Bytes(command: "B", args: []), on: harness)
        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].aid, "x1")
    }

    func test_parser_A_aid_emptyValue_treatedAsNil() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        sendOSC(osc133Bytes(command: "A", args: ["aid="]), on: harness)
        harness.appendText("$ ")
        sendOSC(osc133Bytes(command: "B", args: []), on: harness)
        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 1)
        XCTAssertNil(marks[0].aid, "Empty aid= must be treated as nil")
    }

    func test_parser_A_aidPlusKindCompose() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        // Primary prompt with aid.
        sendOSC(osc133Bytes(command: "A", args: ["aid=primary"]), on: harness)
        harness.appendText("$ ")
        sendOSC(osc133Bytes(command: "B", args: []), on: harness)
        // Then a non-initial A;k=s;aid=secondary — must dispatch as secondary
        // but the receiver should NOT create a new mark for the secondary.
        harness.appendText("echo \\")
        harness.newline()
        sendOSC(osc133Bytes(command: "A", args: ["aid=secondary", "k=s"]), on: harness)
        harness.appendText("> ")
        sendOSC(osc133Bytes(command: "B", args: []), on: harness)
        harness.appendText("hi")
        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 1,
                       "Non-initial (k=s) must not create a new mark even with aid=")
        XCTAssertEqual(marks[0].aid, "primary",
                       "Primary mark's aid must not be overwritten by the secondary's aid")
    }

    func test_parser_D_codeFirst_thenAid() {
        // D;0;aid=x1
        let harness = setupCommandWithAid("x1", into: TerminalTestHarness(width: 80, height: 24))
        sendOSC(osc133Bytes(command: "D", args: ["0", "aid=x1"]), on: harness)
        let mark = promptMarks(in: harness).first!
        XCTAssertNotNil(mark.endDate, "D must set endDate via close-by-aid path")
        XCTAssertEqual(mark.code, 0)
        XCTAssertTrue(mark.hasCode)
    }

    func test_parser_D_aidFirst_thenCode() {
        // D;aid=x1;0 (argument order swapped)
        let harness = setupCommandWithAid("x1", into: TerminalTestHarness(width: 80, height: 24))
        sendOSC(osc133Bytes(command: "D", args: ["aid=x1", "0"]), on: harness)
        let mark = promptMarks(in: harness).first!
        XCTAssertNotNil(mark.endDate)
        XCTAssertEqual(mark.code, 0)
    }

    func test_parser_D_aidWithoutCode_closesWithCodeSynthesizedToZero() {
        // D;aid=x1 (no exit code). Spec allows it; the receiver needs a
        // code for screenCommandDidExitWithCode + returnCodePromise
        // fulfilment, so we synthesize 0 here the same way bare `D;`
        // does. See test_D_aidWithoutCode_synthesizesZero for the
        // notification-level invariant.
        let harness = setupCommandWithAid("x1", into: TerminalTestHarness(width: 80, height: 24))
        sendOSC(osc133Bytes(command: "D", args: ["aid=x1"]), on: harness)
        harness.sync()
        let mark = promptMarks(in: harness).first!
        XCTAssertNotNil(mark.endDate, "D;aid=X with no code must still close the mark")
        XCTAssertEqual(mark.code, 0)
        XCTAssertTrue(mark.hasCode,
                      "D;aid=X without a code synthesizes 0 (matches bare-D; compat)")
    }

    // MARK: - Group N2: receiver — aid stamped onto mark, registry populated

    func test_receiver_aidLessStream_marksHaveNoAid() {
        // Regression baseline: a stream with no aid behaves as it always has.
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo hi")
        harness.sendCommandEnd()
        harness.sendReturnCode(0)
        harness.sync()
        let mark = promptMarks(in: harness).first!
        XCTAssertNil(mark.aid)
        XCTAssertNil(mark.parentAid)
    }

    func test_receiver_aidStamped_registryPopulatedAtA() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "outer-1")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.sync()
        let mark = promptMarks(in: harness).first!
        XCTAssertEqual(mark.aid, "outer-1")
        // Top-level command: no parent.
        XCTAssertNil(mark.parentAid)
    }

    // MARK: - Group N3: layered cycle (no cascade — clean inner D)

    func test_layered_innerD_closesInnerNotOuter() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        // Outer (local shell): A;B;C run ssh.
        harness.sendPromptStart(aid: "o1")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("ssh remote")
        harness.sendCommandEnd()
        harness.newline()
        // Inner (remote shell): A;B;C;D one full cycle.
        harness.sendPromptStart(aid: "r1")
        harness.appendText("remote$ ")
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.sendCommandEnd()
        harness.newline()
        harness.sendReturnCode(0, aid: "r1")
        harness.sync()

        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 2)
        let o1 = marks.first { $0.aid == "o1" }!
        let r1 = marks.first { $0.aid == "r1" }!
        // Note: o1.endDate gets set by `assignCurrentCommandEndDate` as a
        // pre-existing side effect of any new prompt arriving (including the
        // inner A;aid=r1). That's independent of aid. What we actually
        // care about is that the inner D didn't *claim* an exit code on the
        // outer mark — verify the outer's hasCode stays false.
        XCTAssertFalse(o1.hasCode, "Inner D must NOT claim a code on the outer mark")
        XCTAssertNotNil(r1.endDate, "Inner D must close the matching inner mark")
        XCTAssertTrue(r1.hasCode, "Inner D;aid=r1;0 must set r1's hasCode")
        XCTAssertEqual(r1.code, 0)
        XCTAssertEqual(r1.parentAid, "o1", "Inner mark's parentAid must point at the open outer")
    }

    func test_layered_innerThenOuter_bothCloseAtRightTime() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "o1")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.newline()
        harness.sendPromptStart(aid: "r1")
        harness.appendText("remote$ ")
        harness.sendCommandStart()
        harness.newline()
        harness.sendReturnCode(0, aid: "r1")
        harness.sendReturnCode(0, aid: "o1")
        harness.sync()

        let marks = promptMarks(in: harness)
        let o1 = marks.first { $0.aid == "o1" }!
        let r1 = marks.first { $0.aid == "r1" }!
        XCTAssertNotNil(o1.endDate, "Outer D must close outer")
        XCTAssertNotNil(r1.endDate)
        XCTAssertEqual(o1.code, 0)
        XCTAssertEqual(r1.code, 0)
    }

    func test_layered_dForUnknownAid_fallsThroughToTopmostOpen() {
        // D;aid=missing arrives but no mark has that aid. The receiver should
        // fall through to today's "close topmost open" path rather than no-op.
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "o1")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.sync()
        harness.sendReturnCode(0, aid: "missing")
        harness.sync()
        let mark = promptMarks(in: harness).first!
        XCTAssertEqual(mark.code, 0, "D with unknown aid should still close topmost")
    }

    // MARK: - Group N4: cascade close (the ssh-dies case)

    func test_cascade_outerDClosesInner() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        // Outer ssh + inner remote command, both still open.
        harness.sendPromptStart(aid: "o1")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.newline()
        harness.sendPromptStart(aid: "r1")
        harness.appendText("remote$ ")
        harness.sendCommandStart()
        harness.appendText("./long-build.sh")
        harness.sync()
        // Outer D arrives (ssh died with code 255). Cascade-close must fire
        // on r1 even though no D;aid=r1 ever arrived.
        harness.sendReturnCode(255, aid: "o1")
        harness.sync()

        let marks = promptMarks(in: harness)
        let o1 = marks.first { $0.aid == "o1" }!
        let r1 = marks.first { $0.aid == "r1" }!
        XCTAssertNotNil(o1.endDate, "Target mark must close")
        XCTAssertEqual(o1.code, 255)
        XCTAssertTrue(o1.hasCode)
        XCTAssertNotNil(r1.endDate, "Cascade-closed inner mark must have endDate set")
        XCTAssertFalse(r1.hasCode,
                       "Cascade-closed mark must NOT claim an exit code — none is known")
    }

    func test_cascade_threeDeepNest() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        // outer o1 -> middle m1 -> inner i1, all open.
        harness.sendPromptStart(aid: "o1")
        harness.sendCommandStart()
        harness.newline()
        harness.sendPromptStart(aid: "m1")
        harness.sendCommandStart()
        harness.newline()
        harness.sendPromptStart(aid: "i1")
        harness.sendCommandStart()
        harness.sync()
        // Outer dies. Cascade must reach m1 (parent=o1) and i1 (parent=m1).
        harness.sendReturnCode(1, aid: "o1")
        harness.sync()

        let marks = promptMarks(in: harness)
        for aid in ["o1", "m1", "i1"] {
            let m = marks.first { $0.aid == aid }!
            XCTAssertNotNil(m.endDate, "\(aid) must be closed by cascade")
        }
    }

    func test_cascade_doesNotCloseSiblings() {
        // u1 is unrelated to o1 (no parentAid relationship).
        // Closing o1 must NOT cascade to u1.
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "u1")
        harness.sendCommandStart()
        harness.newline()
        harness.sendPromptStart(aid: "o1")
        harness.sendCommandStart()
        harness.sync()
        harness.sendReturnCode(0, aid: "o1")
        harness.sync()

        let marks = promptMarks(in: harness)
        let u1 = marks.first { $0.aid == "u1" }!
        let o1 = marks.first { $0.aid == "o1" }!
        XCTAssertNotNil(o1.endDate)
        XCTAssertNil(u1.endDate, "Sibling u1 must remain open after o1 closes")
    }

    // MARK: - Group N5: backward compat / mixed

    func test_mixed_aidlessAndAided_coexist() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        // Aid-less cycle.
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo a")
        harness.sendCommandEnd()
        harness.newline()
        harness.sendReturnCode(0)
        harness.newline()
        // Then aid'd cycle.
        harness.sendPromptStart(aid: "x1")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo b")
        harness.sendCommandEnd()
        harness.newline()
        harness.sendReturnCode(0, aid: "x1")
        harness.sync()

        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 2)
        XCTAssertNil(marks[0].aid)
        XCTAssertEqual(marks[1].aid, "x1")
        XCTAssertNotNil(marks[0].endDate)
        XCTAssertNotNil(marks[1].endDate)
    }

    // MARK: - Group N6: dictionary round-trip

    func test_dict_roundTripsAidAndParentAid() {
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.aid = "x1"
        mark.parentAid = "outer-1"

        let dict = mark.dictionaryValue()
        let restored = VT100ScreenMark(dictionary: dict)!
        XCTAssertEqual(restored.aid, "x1")
        XCTAssertEqual(restored.parentAid, "outer-1")
    }

    func test_dict_aidlessMarkOmitsKeys() {
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        let dict = mark.dictionaryValue() as NSDictionary
        XCTAssertNil(dict["Aid"],
                     "Aid key must be absent (not nil) when mark has no aid — keeps dict small")
        XCTAssertNil(dict["Parent Aid"])
    }

    func test_dict_legacyDictWithoutAidKeys_loadsWithNil() {
        // Simulate a saved session from before this feature: the dict has
        // no Aid / Parent Aid keys at all.
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.aid = "should-not-survive"
        mark.parentAid = "should-not-survive"
        let dict = NSMutableDictionary(dictionary: mark.dictionaryValue())
        dict.removeObject(forKey: "Aid")
        dict.removeObject(forKey: "Parent Aid")
        let restored = VT100ScreenMark(dictionary: dict as! [AnyHashable: Any])!
        XCTAssertNil(restored.aid)
        XCTAssertNil(restored.parentAid)
    }

    func test_copy_doppelgangerPreservesAid() {
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.aid = "x1"
        mark.parentAid = "outer-1"
        let dop = mark.copy() as! VT100ScreenMark
        XCTAssertEqual(dop.aid, "x1")
        XCTAssertEqual(dop.parentAid, "outer-1")
    }

    // MARK: - Group N7: D must not fall through to E (long-standing bug)

    func test_parser_D_doesNotFallThroughToE() {
        // D;0 should close the command without also dispatching the E
        // (FinalTerm semantic text) handler. We assert this indirectly: a
        // D;0 immediately followed by no E-shaped args should not produce a
        // garbage semantic-text-of-type call that would otherwise have read
        // args[1] as a type code (it would land on type=0, which is below
        // the valid range, so today the E handler silently drops it — but
        // the fall-through was still a latent bug for `D;<bigType>`).
        // We can't observe the absence directly without a spy, so just
        // verify that the normal D path completes cleanly.
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo hi")
        harness.sendCommandEnd()
        sendOSC(osc133Bytes(command: "D", args: ["0"]), on: harness)
        let mark = promptMarks(in: harness).first!
        XCTAssertEqual(mark.code, 0)
        XCTAssertTrue(mark.hasCode)
    }

    // MARK: - Group N8: D-while-inCommand_ with aid (abort-by-aid)

    func test_abort_dWhileInCommand_withMatchingAid_abortsTargetedMark() {
        // Abort path (D arrived while inCommand_): the targeted mark gets
        // removed from the tree, mirroring the legacy commandWasAborted
        // semantics but routed by aid.
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "x1")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("partial-command")
        harness.sendAbort(aid: "x1")
        harness.sync()
        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 0,
                       "Abort-by-aid removed the targeted mark from the tree")
    }

    func test_abort_dWhileInCommand_cascadesInnerAids() {
        // Outer ssh open with an inner remote command that never reached C.
        // Then D-while-in-command;aid=o1 arrives at the outer level. Outer
        // gets removed (abort); inner gets cascade-closed (kept in tree
        // with endDate set, no exit-code claim).
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "o1")
        harness.sendCommandStart()
        harness.appendText("ssh remote")
        harness.sendCommandEnd()
        harness.newline()
        harness.sendPromptStart(aid: "r1")
        harness.sendCommandStart()
        harness.appendText("./build.sh")
        harness.sendAbort(aid: "o1")
        harness.sync()
        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 1, "Outer aborted out; inner remains as cascade-closed")
        XCTAssertEqual(marks[0].aid, "r1")
        XCTAssertNotNil(marks[0].endDate)
        XCTAssertFalse(marks[0].hasCode, "Cascade-closed inner must not claim an exit code")
    }

    // MARK: - Group N9a: registry stays clean after clear / abort paths

    /// `terminalAbortCommandWithAid:` removes the targeted mark from the
    /// interval tree. The centralized -didRemoveObjectFromIntervalTree:
    /// hook must drop the aid registry entry too, otherwise the registry
    /// holds a stale strong ref forever and parentAid computation for the
    /// next aid'd mark gets the wrong value.
    func test_abort_clearsRegistryAndStack() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "x1")
        harness.sendCommandStart()
        harness.sendAbort(aid: "x1")
        harness.sync()
        // No way to introspect marksByAid/openAidStack directly from Swift,
        // but a subsequent A;aid=y1 should record parentAid=nil — proving
        // x1 was popped from the stack.
        harness.sendPromptStart(aid: "y1")
        harness.sendCommandStart()
        harness.sync()
        let marks = promptMarks(in: harness)
        let y1 = marks.first { $0.aid == "y1" }!
        XCTAssertNil(y1.parentAid,
                     "After abort of x1, openAidStack must be empty so y1 has no parent")
    }

    /// Clearing the scrollback (Cmd-K-like flow) must purge aid entries
    /// for marks that get evicted. Otherwise the registry holds dead
    /// strong refs and parentAid for new marks is corrupted.
    func test_clearScrollbackBuffer_purgesEvictedAids() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "scroll-me-away")
        harness.sendCommandStart()
        harness.sendCommandEnd()
        harness.sendReturnCode(0, aid: "scroll-me-away")
        harness.sync()
        // Scroll the mark into scrollback by appending output.
        for _ in 0 ..< 30 {
            harness.appendText("padding\n")
        }
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.clearScrollbackBuffer()
        })
        harness.sync()
        // A new aid'd prompt should now compute parentAid=nil. (If
        // openAidStack still held "scroll-me-away", parentAid would be set.)
        harness.sendPromptStart(aid: "fresh")
        harness.sendCommandStart()
        harness.sync()
        let fresh = promptMarks(in: harness).first { $0.aid == "fresh" }!
        XCTAssertNil(fresh.parentAid,
                     "openAidStack must drop entries whose marks were evicted by Cmd-K")
    }

    // MARK: - Group N9b: aid abort path matches legacy abort cleanup (Issue 2)

    /// `commandWasAborted` resets `commandStartCoord` to (-1, -1) so
    /// downstream checks like clearBufferSavingPrompt:'s
    /// `commandStartCoord.x >= 0` gate read the post-abort state. The
    /// aid path must do the same, otherwise the single-level aid case
    /// (where the aborted mark IS the topmost-open one) leaves stale
    /// command-start coords pointing at the aborted command.
    func test_abortByAid_resetsCommandStartCoord() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "x1")
        harness.sendCommandStart()
        harness.appendText("partial")
        harness.sendAbort(aid: "x1")
        harness.sync()
        var startX: Int32 = 999
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            startX = mutableState.commandStartCoord.x
        })
        XCTAssertEqual(startX, -1,
                       "Abort-by-aid must reset commandStartCoord.x to -1, "
                       + "matching the legacy commandWasAborted cleanup")
    }

    // MARK: - Group N9c: D; → 0 legacy compatibility (Issue 4)

    /// A bare `D;` (trailing semicolon with nothing after) was treated as
    /// exit code 0 by the prior implementation. Preserve that for any
    /// shell integration script that may emit it.
    func test_parser_D_emptyArgIsCode0_legacyCompat() {
        let harness = setupCommandWithAid("compat", into: TerminalTestHarness(width: 80, height: 24))
        // Bare D; — args = ["D", ""], no aid.
        sendOSC(osc133Bytes(command: "D", args: [""]), on: harness)
        harness.sync()
        // The aid'd compat mark is still open (D; without aid goes through
        // topmost-open path which is the same compat mark).
        let mark = promptMarks(in: harness).first!
        XCTAssertEqual(mark.code, 0)
        XCTAssertTrue(mark.hasCode,
                      "Bare D; should record exit code 0 (legacy compat)")
    }

    // MARK: - Group N9d: openAidStack serialization (Issue 3)

    /// `kScreenStateOpenAidStackKey` is the authoritative source of "open
    /// aids" across save/restore. Reading it back must surface the same
    /// array, in the same order.
    func test_openAidStackKey_roundtrips() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "outer")
        harness.sendCommandStart()
        harness.newline()
        harness.sendPromptStart(aid: "inner")
        harness.sendCommandStart()
        harness.sync()
        var stack: [String] = []
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            stack = (mutableState.openAidStack as NSArray) as! [String]
        })
        XCTAssertEqual(stack, ["outer", "inner"],
                       "openAidStack must reflect the order aids were pushed")
    }

    // MARK: - Group N9d: registry stays in sync with the tree across every removal path

    /// Long-running command's mark gets evicted by
    /// `removeInaccessibleIntervalTreeObjects` (fires on every sync). The
    /// registry must drop its entry, or a later D;aid=X runs
    /// closeAidMark: on a mark whose entry == nil — coordRangeForInterval:
    /// on a nil interval, mutateObject: on a detached mark, and a phantom
    /// screenCommandDidExitWithCode.
    func test_markScrolledOff_aidRegistryPruned() {
        let harness = TerminalTestHarness(width: 80, height: 5)
        harness.sendPromptStart(aid: "scroll-victim")
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("long-cmd")
        harness.sendCommandEnd()
        harness.newline()
        for _ in 0 ..< 200 {
            harness.appendText("output line\n")
        }
        // Drive a sync first so the linebuffer settles.
        harness.sync()
        // Sanity: removeInaccessibleIntervalTreeObjects requires a
        // non-zero cumulativeScrollbackOverflow to evict anything.
        // The test harness's default config (unlimited scrollback) leaves
        // overflow=0, so the mark stays in scrollback rather than being
        // evicted. Force the overflow up to past the mark's line so the
        // eviction actually fires.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.incrementOverflow(by: 250)
            mutableState.removeInaccessibleIntervalTreeObjects()
        })
        harness.sync()
        // Issue a fresh A;aid=fresh: parentAid must be nil. If the registry
        // still held "scroll-victim" in openAidStack, the new mark would
        // get a phantom parentAid.
        harness.sendPromptStart(aid: "fresh")
        harness.sendCommandStart()
        harness.sync()
        let fresh = harness.allScreenMarks().first(where: { $0.aid == "fresh" })!
        XCTAssertNil(fresh.parentAid,
                     "scroll-victim must be pruned from openAidStack when its "
                     + "mark is evicted from scrollback")
    }

    // MARK: - Group N10: setPromptStartLine mark reuse drops old aid (Issue 1)

    /// When a same-line mark is reused with a different aid (or no aid),
    /// the OLD aid key must be dropped from marksByAid and openAidStack.
    /// Otherwise the registry retains a stale entry; a later D;aid=X
    /// closes the wrong mark and a phantom X corrupts parentAid for
    /// future nested marks.
    func test_promptMarkReuse_dropsOldAid_whenStampedWithDifferentAid() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        // First A;aid=X (no B yet, mark reuse-eligible on same line).
        harness.sendPromptStart(aid: "X")
        // Re-issue A on same line with different aid.
        harness.sendPromptStart(aid: "Y")
        harness.sendCommandStart()
        harness.sync()
        let mark = promptMarks(in: harness).first!
        XCTAssertEqual(mark.aid, "Y", "Reused mark adopts new aid")
        var stack: [String] = []
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            stack = (mutableState.openAidStack as NSArray) as! [String]
        })
        XCTAssertEqual(stack, ["Y"],
                       "openAidStack must drop the phantom X when mark is reused")
    }

    /// Reuse with aid=nil: the previously-stamped X must also clear.
    func test_promptMarkReuse_dropsOldAid_whenReusedWithNilAid() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "X")
        harness.sendPromptStart()  // aid=nil
        harness.sendCommandStart()
        harness.sync()
        let mark = promptMarks(in: harness).first!
        XCTAssertNil(mark.aid)
        var stack: [String] = []
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            stack = (mutableState.openAidStack as NSArray) as! [String]
        })
        XCTAssertEqual(stack, [], "Stack must drop X when mark is reused with no aid")
    }

    // MARK: - Group N11: D no-code paths (Issues 2 + 5)

    /// `D;aid=X` with no positional integer code: the receiver must still
    /// fire the command-end notification path so consumers
    /// (screenCommandDidExitWithCode, returnCodePromise) resolve. Match
    /// the bare-`D;` legacy compat by synthesizing exit code 0 at parser.
    func test_D_aidWithoutCode_synthesizesZero() {
        let harness = setupCommandWithAid("x1", into: TerminalTestHarness(width: 80, height: 24))
        sendOSC(osc133Bytes(command: "D", args: ["aid=x1"]), on: harness)
        harness.sync()
        let mark = promptMarks(in: harness).first!
        XCTAssertNotNil(mark.endDate, "D;aid=X must close the mark")
        XCTAssertEqual(mark.code, 0)
        XCTAssertTrue(mark.hasCode,
                      "D;aid=X with no code synthesizes 0, matching bare-D; legacy compat")
    }

    /// `D;abc` (non-numeric positional) used to dispatch with `[args[1]
    /// intValue]` = 0. The strict NSScanner parse regressed this to "no
    /// dispatch". Restore code 0 for legacy compat.
    func test_D_nonNumericArg_legacyDispatchesAsZero() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        // Drive A/B/C through OSC bytes so VT100Terminal's inCommand_ tracks
        // properly (the harness shortcuts only mutate receiver state). After
        // commandEnd, inCommand_ is false so the D handler takes the return-code
        // path rather than abort.
        sendOSC(osc133Bytes(command: "A", args: []), on: harness)
        harness.appendText("$ ")
        sendOSC(osc133Bytes(command: "B", args: []), on: harness)
        harness.appendText("echo hi")
        sendOSC(osc133Bytes(command: "C", args: []), on: harness)
        sendOSC(osc133Bytes(command: "D", args: ["abc"]), on: harness)
        harness.sync()
        let mark = promptMarks(in: harness).first!
        XCTAssertEqual(mark.code, 0,
                       "D;abc must dispatch with exit code 0 (legacy compat: "
                       + "[@\"abc\" intValue] = 0)")
        XCTAssertTrue(mark.hasCode)
    }

    // MARK: - Group N12: cascade resolves returnCodePromise (Issue 3)

    /// When the outer command dies (ssh tunnel drop, D;aid=outer fires)
    /// and cascade-closes the still-open inner, the inner's
    /// returnCodePromise must be settled at cascade time. Otherwise
    /// awaiters (CommandInfoViewController, PTYSession) wait until mark
    /// dealloc instead of resolving at command end.
    func test_cascadeClose_settlesReturnCodePromise() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "outer")
        harness.sendCommandStart()
        harness.newline()
        harness.sendPromptStart(aid: "inner")
        harness.sendCommandStart()
        harness.sync()

        let inner = promptMarks(in: harness).first { $0.aid == "inner" }!
        let promise = inner.returnCodePromise  // Creates the seal.

        // Outer D → cascade-closes inner with no code.
        harness.sendReturnCode(1, aid: "outer")
        harness.sync()

        // Cascade-closed marks have no exit code, so the promise rejects.
        XCTAssertNotNil(promise.maybeError,
                        "Cascade-closed inner's returnCodePromise must be settled (rejected)")
        XCTAssertFalse(inner.hasCode,
                       "Cascade-closed marks must not claim a code")
    }

    // MARK: - Group N13: lastCommandMark on close-by-aid (Issue 4)

    /// `setReturnCodeOfLastCommand:` operates on `self.lastCommandMark`,
    /// which auto-tracks the current command. The aid path resolves to
    /// any mark in the registry, so without explicit tracking
    /// `lastCommandMark` can lag behind the just-closed target. After
    /// close-by-aid, `lastCommandMark` must point at the closed target
    /// so consumers (last exit status, rerun last command, offscreen
    /// command line) see the right command.
    func test_closeByAid_updatesLastCommandMarkToTarget() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart(aid: "outer")
        harness.sendCommandStart()
        harness.newline()
        harness.sendPromptStart(aid: "inner")
        harness.sendCommandStart()
        harness.sync()
        // Before outer D: lastCommandMark points at inner (most recent A).
        // After outer D: the target outer just closed; lastCommandMark
        // should reflect that.
        harness.sendReturnCode(0, aid: "outer")
        harness.sync()
        let outer = promptMarks(in: harness).first { $0.aid == "outer" }!
        var lastGuid: String? = nil
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            lastGuid = mutableState.lastCommandMark?.guid
        })
        XCTAssertEqual(lastGuid, outer.guid,
                       "Close-by-aid must point lastCommandMark at the target")
    }

    // MARK: - Group N9: save / restore (marksByAid rebuilt via fixUpDeserializedIntervalTree:)

    func test_dict_savedAidMark_loadsWithAidIntact() {
        // After dict round-trip on a single mark, aid + parentAid survive.
        // The rebuild of marksByAid happens at fixUpDeserializedIntervalTree:
        // (driven by the full restoreFromDictionary: path); that's exercised
        // in higher-level integration tests. Here we just verify the
        // per-mark round-trip.
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.aid = "saved-o1"
        mark.parentAid = "saved-parent"
        mark.firstLineOfCommand = "ssh remote"
        let dict = mark.dictionaryValue()
        let restored = VT100ScreenMark(dictionary: dict)!
        XCTAssertEqual(restored.aid, "saved-o1")
        XCTAssertEqual(restored.parentAid, "saved-parent")
    }

    // MARK: - Internal helpers

    /// Drive a primary A;B with the given aid through the harness, leaving
    /// the harness ready for a subsequent D test.
    private func setupCommandWithAid(_ aid: String,
                                     into harness: TerminalTestHarness) -> TerminalTestHarness {
        harness.sendPromptStart(aid: aid)
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo hi")
        harness.sendCommandEnd()
        harness.newline()
        harness.sync()
        return harness
    }
}

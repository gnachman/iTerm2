//
//  CodeReviewPromptMigrationTests.swift
//  iTerm2 ModernTests
//
//  A customized code review system prompt keeps text derived from an older default, which runs
//  it2 by name and addresses the session with --session=$TERM_SESSION_ID. iTerm2 offers to bring
//  its it2 command lines up to date, and changes nothing else, nor anything without asking.
//

import XCTest
@testable import iTerm2SharedARC

final class CodeReviewPromptMigrationTests: XCTestCase {
    private typealias M = CodeReviewPromptMigration

    private static var fixtures: URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("CodeReviewPrompts")
    }

    /// The default 3.7.0 through 3.7.4 shipped, identical in each.
    private var shipped: String {
        return try! String(contentsOf: Self.fixtures.appendingPathComponent("shipped-3.7.0-3.7.4.txt"), encoding: .utf8)
    }

    /// The default now.
    private var current: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("code-review-system-prompt.txt")
        return try! String(contentsOf: url, encoding: .utf8)
    }

    private let addressing = #"--tmux "$TMUX" --tmux-pane "$TMUX_PANE" --session "${TERM_SESSION_ID#*:}""#

    // MARK: - The rewrite

    func testCommandLinesRunTheFilledInIt2AndUseTheThreeOptions() {
        XCTAssertEqual(M.migrated("it2 session archive-clippings --session=$TERM_SESSION_ID"),
                       "{{it2}} session archive-clippings \(addressing)")
        XCTAssertEqual(M.migrated("it2 session add-clipping --session=$TERM_SESSION_ID {TYPE} {TITLE} {DETAIL}"),
                       "{{it2}} session add-clipping \(addressing) {TYPE} {TITLE} {DETAIL}")
    }

    // The worked example names a made-up session.
    func testTheExamplesLiteralSessionIsReplacedToo() {
        XCTAssertEqual(M.migrated(#"it2 session add-clipping --session=1234-56789 "Code Review Comment" 'x'"#),
                       #"{{it2}} session add-clipping \#(addressing) "Code Review Comment" 'x'"#)
    }

    // Each change is made where it is needed, so a half-updated line is finished.
    func testEachChangeIsMadeOnItsOwn() {
        XCTAssertEqual(M.migrated("{{it2}} session add-clipping --session=$TERM_SESSION_ID a"),
                       "{{it2}} session add-clipping \(addressing) a")
        XCTAssertEqual(M.migrated("it2 session add-clipping \(addressing) a"),
                       "{{it2}} session add-clipping \(addressing) a")
    }

    // The ways a prompt might spell the old addressing.
    func testOtherSpellingsOfTheOldAddressing() {
        for old in [#"--session="$TERM_SESSION_ID""#, "--session=${TERM_SESSION_ID}", #"--session "$TERM_SESSION_ID""#,
                    "--session $TERM_SESSION_ID"] {
            XCTAssertEqual(M.migrated("it2 session add-clipping \(old) {TYPE}"),
                           "{{it2}} session add-clipping \(addressing) {TYPE}", old)
        }
        XCTAssertEqual(M.migrated("it2 session archive-clippings --session=$TERM_SESSION_ID;"),
                       "{{it2}} session archive-clippings --session=$TERM_SESSION_ID;",
                       "not a value it2 is given as is, so only it2 changes")
    }

    // Only the options before the arguments are read: a title or detail mentioning --session is
    // the user's text, and an ID that only looks like the example's is not it.
    func testArgumentsAreNotTouched() {
        XCTAssertEqual(M.migrated(#"it2 session add-clipping "Code Review Comment" 'use --session=$TERM_SESSION_ID' x"#),
                       #"{{it2}} session add-clipping "Code Review Comment" 'use --session=$TERM_SESSION_ID' x"#)
        XCTAssertEqual(M.migrated("{{it2}} session add-clipping --session=2024-10 x"), nil)
    }

    // A line that already passes the tmux pair gets only the session option, not a second pair.
    func testALineWithTheTmuxPairKeepsIt() {
        XCTAssertEqual(M.migrated(#"it2 session add-clipping --tmux "$TMUX" --tmux-pane "$TMUX_PANE" --session=$TERM_SESSION_ID x"#),
                       #"{{it2}} session add-clipping --tmux "$TMUX" --tmux-pane "$TMUX_PANE" --session "${TERM_SESSION_ID#*:}" x"#)
    }

    func testTabsAreKept() {
        XCTAssertEqual(M.migrated("\tit2\tsession add-clipping --session=$TERM_SESSION_ID x"),
                       "\t{{it2}}\tsession add-clipping \(addressing) x")
    }

    // Prose that mentions it2, and other commands, are the user's text and stay as they are.    // Prose that mentions it2, and other commands, are the user's text and stay as they are.
    func testProseAndOtherCommandsAreUntouched() {
        let text = """
        Submit findings using the it2 command as follows:
        it2 session list --session=$TERM_SESSION_ID
          it2 session add-clipping --session=$TERM_SESSION_ID a
        Run it2 session add-clipping once per finding.
        """
        XCTAssertEqual(M.migrated(text), """
        Submit findings using the it2 command as follows:
        it2 session list --session=$TERM_SESSION_ID
          {{it2}} session add-clipping \(addressing) a
        Run it2 session add-clipping once per finding.
        """)
    }

    func testTextWithNothingToChangeIsNotOffered() {
        XCTAssertNil(M.migrated("Review this carefully and report findings as plain text."))
        XCTAssertNil(M.migrated(current), "the current default is already up to date")
    }

    func testIdempotent() throws {
        let once = try XCTUnwrap(M.migrated(shipped))
        XCTAssertNil(M.migrated(once))
    }

    // Only the command lines change; every other byte, line endings included, stays.
    func testEverythingElseStaysByteForByte() throws {
        let customized = shipped.replacingOccurrences(of: "\n", with: "\r\n") + "Also check for typos.\r\n"
        let migrated = try XCTUnwrap(M.migrated(customized))
        let before = customized.components(separatedBy: "\r\n")
        let after = migrated.components(separatedBy: "\r\n")
        XCTAssertEqual(before.count, after.count)
        for (old, new) in zip(before, after) where old != new {
            XCTAssertTrue(old.hasPrefix("it2 session "), "changed: \(old)")
            XCTAssertTrue(new.hasPrefix("{{it2}} session "), new)
        }
        XCTAssertEqual(zip(before, after).filter { $0 != $1 }.count, 3)
    }

    // The command lines of a migrated old default read exactly as the current default's do.
    func testAMigratedShippedDefaultMatchesTheCurrentCommandLines() throws {
        let migrated = try XCTUnwrap(M.migrated(shipped))
        let commandLines = { (text: String) in
            text.components(separatedBy: "\n").filter { $0.hasPrefix("{{it2}} ") }
        }
        XCTAssertEqual(commandLines(migrated), commandLines(current))
    }

    // MARK: - What is offered

    // A stored prompt that is exactly a shipped default was never really customized: it is
    // offered the whole current default, and updating stops storing a copy.
    func testAStoredShippedDefaultIsOfferedTheCurrentDefault() {
        XCTAssertEqual(M.proposal(stored: shipped, currentDefault: current),
                       M.Proposal(text: current, resetsToDefault: true))
    }

    func testACustomizedPromptIsOfferedItsMigration() throws {
        let customized = shipped + "Also check for typos.\n"
        XCTAssertEqual(M.proposal(stored: customized, currentDefault: current),
                       M.Proposal(text: try XCTUnwrap(M.migrated(customized)), resetsToDefault: false))
    }

    func testNothingIsOfferedForTheDefaultOrUnrelatedText() {
        XCTAssertNil(M.proposal(stored: nil, currentDefault: current), "not customized")
        XCTAssertNil(M.proposal(stored: current, currentDefault: current))
        XCTAssertNil(M.proposal(stored: "Just plain text.", currentDefault: current))
    }

    // MARK: - Asking

    func testUpdatingStoresTheMigratedText() throws {
        let customized = shipped + "Also check for typos.\n"
        let outcome = M.decide(stored: customized, currentDefault: current, keptHash: nil) { _, _ in .update }
        XCTAssertEqual(outcome, M.Outcome(prompt: .some(try XCTUnwrap(M.migrated(customized))), keptHash: nil, asked: true))
    }

    // An old default's copy is dropped, so the default applies and stays current.
    func testUpdatingAnOldDefaultStoresNone() {
        let outcome = M.decide(stored: shipped, currentDefault: current, keptHash: nil) { _, _ in .update }
        XCTAssertEqual(outcome, M.Outcome(prompt: .some(nil), keptHash: nil, asked: true))
    }

    // Keep stores nothing but the choice; that text is not offered again.
    func testKeepingIsNotAskedAgain() {
        let customized = shipped + "Mine.\n"
        let kept = M.decide(stored: customized, currentDefault: current, keptHash: nil) { _, _ in .keep }
        XCTAssertEqual(kept.prompt, .none)
        XCTAssertTrue(kept.asked)
        let hash = kept.keptHash
        XCTAssertNotNil(hash)
        var askedAgain = false
        let later = M.decide(stored: customized, currentDefault: current, keptHash: hash) { _, _ in
            askedAgain = true
            return .update
        }
        XCTAssertFalse(askedAgain)
        XCTAssertEqual(later, M.Outcome(prompt: .none, keptHash: nil, asked: false))
        // Edited since: offered again.
        _ = M.decide(stored: customized + "More.\n", currentDefault: current, keptHash: hash) { _, _ in
            askedAgain = true
            return .undecided
        }
        XCTAssertTrue(askedAgain)
    }

    // Closing the offer decides nothing, so it is offered next time.
    func testClosingTheOfferChangesNothing() {
        let outcome = M.decide(stored: shipped + "x\n", currentDefault: current, keptHash: nil) { _, _ in .undecided }
        XCTAssertEqual(outcome, M.Outcome(prompt: .none, keptHash: nil, asked: true))
    }

    func testNothingToOfferMeansNoQuestion() {
        for stored in [nil, current, "Plain text."] as [String?] {
            var asked = false
            let outcome = M.decide(stored: stored, currentDefault: current, keptHash: nil) { _, _ in
                asked = true
                return .update
            }
            XCTAssertFalse(asked)
            XCTAssertEqual(outcome, M.Outcome(prompt: .none, keptHash: nil, asked: false))
        }
    }

    // MARK: - Keeping one's prompt

    // Kept is remembered for that text only: editing it later offers again.
    func testKeepingIsRememberedForThatTextOnly() {
        var memory = M.KeepMemory(storedHash: nil)
        XCTAssertFalse(memory.kept("mine"))
        memory.keep("mine")
        XCTAssertTrue(memory.kept("mine"))
        XCTAssertFalse(memory.kept("mine, edited"))
        XCTAssertNotEqual(memory.storedHash, "mine", "only a hash is stored")
        XCTAssertEqual(memory.storedHash?.count, 64)
    }

    // MARK: - Showing the change

    // Each removed line is followed by what replaces it, also when the texts differ in length.
    func testChangedLinesReadInOrder() {
        let lines = PTYSession.changedLines(from: "a\nold1\nb\nold2\nc", to: "a\nnew1\nb\nnew2\nextra\nc")
        XCTAssertEqual(lines.map { ($0.removed ? "-" : "+") + $0.line },
                       ["-old1", "+new1", "-old2", "+new2", "+extra"])
    }
}

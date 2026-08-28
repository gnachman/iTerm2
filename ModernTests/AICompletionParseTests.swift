//
//  AICompletionParseTests.swift
//  iTerm2 ModernTests
//
//  Pins AICompletion.completionItem(fromLine:prefix:), which classifies each
//  line of the model's command-suggestion response as either an `append`
//  completion (finishes what the user typed, only the remainder is shown as
//  ghost text) or a `replace` command (a full command that takes the place of
//  a natural-language request). Getting this wrong is the "holding it wrong"
//  bug: an English prompt whose command got appended instead of replacing the
//  line.
//

import XCTest
@testable import iTerm2SharedARC

final class AICompletionParseTests: XCTestCase {
    // MARK: - append

    func test_append_stripsTypedPrefix() throws {
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "append\tRewrite commit history\tgit rebase",
                                        prefix: "git re"))
        XCTAssertEqual(item.kind, .aiSuggestion)
        XCTAssertEqual(item.value, "base")
        XCTAssertEqual(item.detail, "Rewrite commit history")
    }

    func test_twoFieldLine_defaultsToAppend() throws {
        // Backward compatibility: a line with no mode field is an append.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "Show working tree\tgit status",
                                        prefix: "git "))
        XCTAssertEqual(item.kind, .aiSuggestion)
        XCTAssertEqual(item.value, "status")
    }

    func test_append_trimsOverlappingSuffixOfPrefix() throws {
        // When the suggestion does not begin with the full typed text but shares an
        // overlapping suffix ("re"), only the non-overlapping remainder is appended.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "append\tReset branch\treset",
                                        prefix: "git re"))
        XCTAssertEqual(item.kind, .aiSuggestion)
        XCTAssertEqual(item.value, "set")
    }

    func test_unknownMode_treatedAsAppend() throws {
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "complete\tShow status\tgit status",
                                        prefix: "git "))
        XCTAssertEqual(item.kind, .aiSuggestion)
        XCTAssertEqual(item.value, "status")
    }

    // MARK: - replace

    func test_replace_keepsFullCommandVerbatim() throws {
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "replace\tRemove log files\trm ./*.log",
                                        prefix: "delete every .log file here"))
        XCTAssertEqual(item.kind, .aiReplacement)
        // The whole command is preserved; the typed natural-language text is not a prefix.
        XCTAssertEqual(item.value, "rm ./*.log")
        XCTAssertEqual(item.detail, "Remove log files")
    }

    func test_replace_isCaseInsensitiveAndTrimsMode() throws {
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: " Replace \tRemove log files\trm ./*.log",
                                        prefix: "delete logs"))
        XCTAssertEqual(item.kind, .aiReplacement)
        XCTAssertEqual(item.value, "rm ./*.log")
    }

    func test_replace_emptyCommand_isDropped() {
        XCTAssertNil(
            AICompletion.completionItem(fromLine: "replace\tDo nothing\t   ",
                                        prefix: "whatever"))
    }

    // MARK: - reconciliation (declared mode disagrees with the prefix relationship)

    func test_appendThatDoesNotContinuePrefix_becomesReplacement() throws {
        // The model mislabeled a full command as `append`, but it shares nothing
        // with the natural-language text the user typed, so it must replace it
        // rather than be appended as garbage.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "append\tList containers\tdocker ps -a",
                                        prefix: "show running containers"))
        XCTAssertEqual(item.kind, .aiReplacement)
        XCTAssertEqual(item.value, "docker ps -a")
    }

    func test_replaceThatContinuesPrefix_becomesAppend() throws {
        // The model said `replace`, but the command begins with exactly what the
        // user typed, so the less-destructive completion is used instead.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "replace\tLong listing\tls -la",
                                        prefix: "ls"))
        XCTAssertEqual(item.kind, .aiSuggestion)
        XCTAssertEqual(item.value, " -la")
    }

    func test_missingModeThatDoesNotContinuePrefix_becomesReplacement() throws {
        // Two-field line (no mode) whose suggestion doesn't continue the typed text
        // is inferred to be a replacement.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "Remove log files\trm ./*.log",
                                        prefix: "delete every log file"))
        XCTAssertEqual(item.kind, .aiReplacement)
        XCTAssertEqual(item.value, "rm ./*.log")
    }

    func test_coincidentalSingleCharOverlap_noMode_becomesReplacement() throws {
        // The prefix ends in "e" and the command starts with "e", but that one-char
        // overlap is coincidental: the command must replace the English text, not be
        // appended after it.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "List as a table\texa -l",
                                        prefix: "list files as a table"))
        XCTAssertEqual(item.kind, .aiReplacement)
        XCTAssertEqual(item.value, "exa -l")
    }

    func test_coincidentalMidWordOverlap_noMode_becomesReplacement() throws {
        // Two-char overlap ("le") that lands inside the last word ("table") rather
        // than covering the whole trailing token is still coincidental.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "Page through it\tless bigfile.txt",
                                        prefix: "show me the table"))
        XCTAssertEqual(item.kind, .aiReplacement)
        XCTAssertEqual(item.value, "less bigfile.txt")
    }

    func test_midWordCompletion_noMode_stillCompletes() throws {
        // A genuine partial trailing command token is completed even with no mode:
        // the overlap ("reba") covers the whole trailing token.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "Rebase interactively\trebase",
                                        prefix: "git reba"))
        XCTAssertEqual(item.kind, .aiSuggestion)
        XCTAssertEqual(item.value, "se")
    }

    func test_explicitReplaceWins_overIncidentalSuffixOverlap() throws {
        // A short incidental suffix overlap must not turn an explicit `replace` into
        // a completion.
        let item = try XCTUnwrap(
            AICompletion.completionItem(fromLine: "replace\tReset the repo\treset --hard",
                                        prefix: "undo everything since re"))
        XCTAssertEqual(item.kind, .aiReplacement)
        XCTAssertEqual(item.value, "reset --hard")
    }

    // MARK: - issue 12969 (natural-language prompt must be replaced, not kept)

    func test_issue12969_naturalLanguagePrompt_replacesWithCommand() throws {
        // The exact example from the report: an English request whose generated
        // command shares nothing with the typed text must replace the whole line.
        let prefix = "list all jpg files modified today"
        let command = "find . -type f -name \"*.jpg\" -newermt \"today\""
        for line in ["replace\tFind today's JPGs\t\(command)",  // model labels it
                     "Find today's JPGs\t\(command)"] {          // model omits the mode
            let item = try XCTUnwrap(AICompletion.completionItem(fromLine: line, prefix: prefix))
            XCTAssertEqual(item.kind, .aiReplacement, "line=\(line)")
            XCTAssertEqual(item.value, command, "line=\(line)")
        }
    }

    // MARK: - malformed

    func test_lineWithoutTabs_isDropped() {
        XCTAssertNil(
            AICompletion.completionItem(fromLine: "git status",
                                        prefix: "git "))
    }
}

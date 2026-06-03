//
//  AutoModeClassifierTests.swift
//  iTerm2 ModernTests
//
//  Tests the AutoModeClassifier decision flow with a mock backend that
//  records every side-query and returns scripted responses. Covers TUI
//  short-circuit, hard-rule short-circuit (allow / block / fall-through),
//  LLM XML parsing including thinking-tag stripping, error propagation,
//  and that the transcript projection actually reaches the user prompt.
//

import XCTest
@testable import iTerm2SharedARC

final class AutoModeClassifierTests: XCTestCase {

    // MARK: - Mock backend

    /// Captures every classifier side-query so tests can assert on what was
    /// sent (the transcript projection lands in `user`) and supply scripted
    /// responses. Conforms to the classifier's Backend protocol.
    private final class MockBackend: AutoModeClassifier.Backend {
        var entries: [TranscriptEntry] = []

        private(set) var capturedSystem: [String] = []
        private(set) var capturedUser: [String] = []
        private(set) var capturedMaxTokens: [Int] = []

        var nextResponse: String = "<block>no</block>"
        var sideQueryError: Error?

        func sideQuery(system: String,
                       user: String,
                       maxTokens: Int) async throws -> String {
            capturedSystem.append(system)
            capturedUser.append(user)
            capturedMaxTokens.append(maxTokens)
            if let error = sideQueryError {
                throw error
            }
            return nextResponse
        }
    }

    private struct ScriptedError: Error, Equatable {}

    private func makeClassifier(_ chat: AutoModeClassifier.Backend) -> AutoModeClassifier {
        return AutoModeClassifier(chat: chat, rules: AutoModeRules())
    }

    // MARK: - TUI short-circuit

    /// TUI actions must always return needsManualApproval, regardless of
    /// what the classifier or hard rules would have decided. Keystrokes in
    /// a TUI have no parseable command boundary and the LLM cannot see
    /// the screen state.
    func testInTUI_returnsNeedsManualApproval_andSkipsLLM() async throws {
        let chat = MockBackend()
        let classifier = makeClassifier(chat)

        let decision = try await classifier.classify(
            action: .toolCall(name: "Bash", input: "vim notes.txt"),
            inTUI: true)

        guard case .needsManualApproval = decision else {
            XCTFail("expected needsManualApproval, got \(decision)")
            return
        }
        XCTAssertEqual(chat.capturedUser.count, 0,
                       "TUI gate must not contact the LLM")
    }

    /// TUI gate wins over hard rules — a hard-allow rule for "ls" must
    /// not let a TUI-mode invocation through silently.
    func testInTUI_skipsHardRules_evenIfTheyWouldAllow() async throws {
        let chat = MockBackend()
        var classifier = makeClassifier(chat)
        classifier.hardRules = { _ in .allow }

        let decision = try await classifier.classify(
            action: .toolCall(name: "Bash", input: "ls"),
            inTUI: true)

        guard case .needsManualApproval = decision else {
            XCTFail("expected needsManualApproval, got \(decision)")
            return
        }
    }

    // MARK: - Hard rule short-circuit

    func testHardRules_allow_skipsLLM() async throws {
        let chat = MockBackend()
        var classifier = makeClassifier(chat)
        classifier.hardRules = { _ in .allow }

        let decision = try await classifier.classify(
            action: .toolCall(name: "Bash", input: "ls"),
            inTUI: false)

        XCTAssertEqual(decision, .allow)
        XCTAssertEqual(chat.capturedUser.count, 0,
                       "hard-allow must not contact the LLM")
    }

    func testHardRules_block_skipsLLM() async throws {
        let chat = MockBackend()
        var classifier = makeClassifier(chat)
        classifier.hardRules = { _ in .block(reason: "policy") }

        let decision = try await classifier.classify(
            action: .toolCall(name: "Bash", input: "rm -rf /"),
            inTUI: false)

        XCTAssertEqual(decision, .block(reason: "policy"))
        XCTAssertEqual(chat.capturedUser.count, 0,
                       "hard-deny must not contact the LLM")
    }

    func testHardRules_needsManualApproval_skipsLLM() async throws {
        let chat = MockBackend()
        var classifier = makeClassifier(chat)
        classifier.hardRules = { _ in .needsManualApproval(reason: "review") }

        let decision = try await classifier.classify(
            action: .toolCall(name: "Bash", input: "git push --force"),
            inTUI: false)

        XCTAssertEqual(decision, .needsManualApproval(reason: "review"))
        XCTAssertEqual(chat.capturedUser.count, 0)
    }

    func testHardRules_returningNil_fallsThroughToLLM() async throws {
        let chat = MockBackend()
        chat.nextResponse = "<block>no</block>"
        var classifier = makeClassifier(chat)
        classifier.hardRules = { _ in nil }

        let decision = try await classifier.classify(
            action: .toolCall(name: "Bash", input: "something-unknown"),
            inTUI: false)

        XCTAssertEqual(decision, .allow)
        XCTAssertEqual(chat.capturedUser.count, 1)
    }

    // MARK: - LLM XML parsing

    func testLLM_blockYes_withReason_parsedAsBlock() async throws {
        let chat = MockBackend()
        chat.nextResponse = "<block>yes</block><reason>not allowed</reason>"
        let classifier = makeClassifier(chat)

        let decision = try await classifier.classify(
            action: .toolCall(name: "X", input: "x"),
            inTUI: false)

        XCTAssertEqual(decision, .block(reason: "not allowed"))
    }

    func testLLM_blockYes_withoutReason_usesFallbackReason() async throws {
        let chat = MockBackend()
        chat.nextResponse = "<block>yes</block>"
        let classifier = makeClassifier(chat)

        let decision = try await classifier.classify(
            action: .toolCall(name: "X", input: "x"),
            inTUI: false)

        if case .block(let reason) = decision {
            XCTAssertFalse(reason.isEmpty, "block must carry a reason")
        } else {
            XCTFail("expected block, got \(decision)")
        }
    }

    func testLLM_blockNo_parsedAsAllow() async throws {
        let chat = MockBackend()
        chat.nextResponse = "<block>no</block>"
        let classifier = makeClassifier(chat)

        let decision = try await classifier.classify(
            action: .toolCall(name: "X", input: "x"),
            inTUI: false)

        XCTAssertEqual(decision, .allow)
    }

    /// A hostile or confused model may emit `<block>yes</block>` inside
    /// its thinking section. The parser must strip thinking before
    /// matching tags so a fake verdict inside reasoning doesn't fire.
    func testLLM_thinkingTagsStrippedBeforeParse() async throws {
        let chat = MockBackend()
        chat.nextResponse = """
        <thinking>If I were going to block I'd write <block>yes</block> here, but I'm not.</thinking>
        <block>no</block>
        """
        let classifier = makeClassifier(chat)

        let decision = try await classifier.classify(
            action: .toolCall(name: "X", input: "x"),
            inTUI: false)

        XCTAssertEqual(decision, .allow,
                       "block verdict inside <thinking> must not be matched")
    }

    func testLLM_garbledResponse_parsedAsUnparseable() async throws {
        let chat = MockBackend()
        chat.nextResponse = "I'm not sure what to say."
        let classifier = makeClassifier(chat)

        let decision = try await classifier.classify(
            action: .toolCall(name: "X", input: "x"),
            inTUI: false)

        XCTAssertEqual(decision, .unparseable)
    }

    /// Failure policy: errors propagate so the host can fail-closed.
    /// Swallowing here would silently allow actions on a classifier outage.
    func testLLM_errorPropagatesToCaller() async {
        let chat = MockBackend()
        chat.sideQueryError = ScriptedError()
        let classifier = makeClassifier(chat)

        do {
            _ = try await classifier.classify(
                action: .toolCall(name: "X", input: "x"),
                inTUI: false)
            XCTFail("expected error to propagate")
        } catch is ScriptedError {
            // pass
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - Transcript surfaces in the user message

    /// User-text and tool-call entries from the chat history must reach
    /// the classifier's user prompt verbatim, alongside the candidate.
    func testTranscript_entriesAppearInUserPrompt() async throws {
        let chat = MockBackend()
        chat.entries = [
            .userText("clean up old logs"),
            .toolCall(name: "Bash", input: "ls /var/log"),
        ]
        let classifier = makeClassifier(chat)

        _ = try await classifier.classify(
            action: .toolCall(name: "Bash", input: "rm /var/log/old.log"),
            inTUI: false)

        XCTAssertEqual(chat.capturedUser.count, 1)
        let prompt = chat.capturedUser[0]
        XCTAssertTrue(prompt.contains("clean up old logs"),
                      "user text missing from prompt: \(prompt)")
        XCTAssertTrue(prompt.contains("ls /var/log"),
                      "prior tool call missing from prompt")
        XCTAssertTrue(prompt.contains("rm /var/log/old.log"),
                      "candidate action missing from prompt")
    }

    /// `TranscriptEntry` has no `.assistantText` case by design — assistant
    /// prose is unrepresentable. This test pins that invariant: a transcript
    /// built only from user input and tool calls renders to a prompt that
    /// can be inspected for the absence of any model-authored hint.
    func testTranscript_noAssistantTextLeakage() async throws {
        let chat = MockBackend()
        chat.entries = [
            .userText("the safe instruction the user actually gave"),
        ]
        let classifier = makeClassifier(chat)

        _ = try await classifier.classify(
            action: .toolCall(name: "Bash", input: "rm /tmp/x"),
            inTUI: false)

        let prompt = chat.capturedUser[0]
        // Sanity: the user instruction surfaces.
        XCTAssertTrue(prompt.contains("the safe instruction"))
        // Whatever the assistant might have said between turns cannot reach
        // the classifier because the type system forbids representing it.
        // This is a structural property, not a runtime one — kept as a test
        // to anchor the contract for future refactors.
    }

    /// `maxTranscriptEntries` bounds how much history is shipped per call.
    /// Oldest entries are dropped first.
    func testTranscript_cappedByMaxEntries() async throws {
        let chat = MockBackend()
        chat.entries = (0..<20).map { .userText("entry-\($0)") }
        var classifier = makeClassifier(chat)
        classifier.maxTranscriptEntries = 5

        _ = try await classifier.classify(
            action: .toolCall(name: "X", input: "x"),
            inTUI: false)

        let prompt = chat.capturedUser[0]
        XCTAssertFalse(prompt.contains("entry-0"),
                       "oldest entry must have been dropped")
        XCTAssertFalse(prompt.contains("entry-14"),
                       "only the trailing 5 should remain (15-19)")
        XCTAssertTrue(prompt.contains("entry-15"))
        XCTAssertTrue(prompt.contains("entry-19"))
    }
}

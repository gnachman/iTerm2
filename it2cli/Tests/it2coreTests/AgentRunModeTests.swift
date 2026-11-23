import XCTest
@testable import it2core

final class AgentRunModeTests: XCTestCase {
    func testClaudePrintModeIsHeadless() {
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["-p", "hi"]), .headless)
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["--model", "x", "--print"]), .headless)
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["--print=json"]), .headless)
        // Combined short flags: continue and print.
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["-cp", "summarize"]), .headless)
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["-pc", "summarize"]), .headless)
    }

    func testClaudeSessionsAreNotHeadless() {
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: []), .undetermined)
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["--resume", "abc"]), .undetermined)
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["-c"]), .undetermined)
        // A long option that happens to contain a p is not the print flag.
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["--permission-mode", "plan"]), .undetermined)
        // After "--" it is the prompt.
        XCTAssertEqual(AgentRunMode.classify(agent: .claude, arguments: ["--", "-p"]), .undetermined)
    }

    func testCodexExecIsHeadless() {
        XCTAssertEqual(AgentRunMode.classify(agent: .codex, arguments: ["exec", "fix it"]), .headless)
        XCTAssertEqual(AgentRunMode.classify(agent: .codex, arguments: ["e", "fix it"]), .headless)
        XCTAssertEqual(AgentRunMode.classify(agent: .codex, arguments: ["-m", "x", "exec"]), .headless)
        XCTAssertEqual(AgentRunMode.classify(agent: .codex, arguments: []), .undetermined)
        XCTAssertEqual(AgentRunMode.classify(agent: .codex, arguments: ["resume", "abc"]), .undetermined)
    }

    // The hook command runs through /bin/sh, so the agent may be the hook's grandparent.
    func testWalksPastTheShellToTheAgent() {
        let table: [pid_t: AgentRunMode.ProcessFacts] = [
            100: .init(parent: 90, argv: ["/bin/sh", "-c", "it2 handle-agent-hook"]),
            90: .init(parent: 80, argv: ["claude", "-p", "summarize"]),
            80: .init(parent: 1, argv: ["-zsh"]),
        ]
        XCTAssertEqual(AgentRunMode.ofAgent(.claude, startingAt: 100, facts: { table[$0] }), .headless)
        XCTAssertEqual(AgentRunMode.ofAgent(.claude, startingAt: 90, facts: { table[$0] }), .headless)
    }

    func testUnknownProcessesAreUndetermined() {
        XCTAssertEqual(AgentRunMode.ofAgent(.claude, startingAt: 100, facts: { _ in nil }), .undetermined)
    }

    func testReadsThisProcess() throws {
        let facts = try XCTUnwrap(AgentRunMode.processFacts(getpid()))
        XCTAssertEqual(facts.parent, getppid())
        XCTAssertFalse(facts.argv.isEmpty)
    }

    // A `claude -p` run from inside an interactive session must not replace its conversation.
    func testHeadlessRunsRecordNothing() throws {
        let backend = FakeAgentStatusBackend()
        backend.conversationID = "interactive"
        let url = try XCTUnwrap(Bundle.module.url(forResource: "SessionStart",
                                                  withExtension: "json",
                                                  subdirectory: "agent-hooks/claude"))
        try AgentHookHandler.handle(payload: try Data(contentsOf: url),
                                    agent: .claude,
                                    environment: ["TERM_SESSION_ID": "w0t0p0:TEST-SESSION", "IT2_SOCK": "/x"],
                                    backend: backend,
                                    report: { _ in },
                                    runMode: { .headless })
        XCTAssertEqual(backend.conversationID, "interactive")
        XCTAssertFalse(backend.calls.contains { $0.starts(with: ["session", "set-agent-conversation"]) })
        XCTAssertTrue(backend.calls.contains { $0.first == "set-status" }, "the status is still reported")
    }
}

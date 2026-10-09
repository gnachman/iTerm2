//
//  OpenQuicklyContentSearchTests.swift
//  iTerm2
//
//  Tests for Open Quickly's session contents search ("/g"): merging matches per
//  session, and finding text in Claude Code transcripts.
//

import XCTest
@testable import iTerm2SharedARC

final class OpenQuicklyContentMatchTallyTests: XCTestCase {
    func testCountsAccumulateWithinASource() {
        var tally = iTermContentMatchTally<String, String>()
        tally.add(["a1", "a2"], for: "A", source: .buffer)
        tally.add(["a3"], for: "A", source: .buffer)
        XCTAssertEqual(tally.entries["A"]?.count, 3)
        XCTAssertEqual(tally.entries["A"]?.first, "a1")
    }

    func testSourcesAreNotAddedTogether() {
        // The same text is usually in both the scrollback and the transcript.
        var tally = iTermContentMatchTally<String, String>()
        tally.add(["buffer"], count: 2, for: "A", source: .buffer)
        tally.add(["transcript"], count: 5, for: "A", source: .claudeCodeTranscript)
        XCTAssertEqual(tally.entries["A"]?.count, 5)
    }

    func testBufferMatchIsPreferredEvenWhenItArrivesLater() {
        var tally = iTermContentMatchTally<String, String>()
        tally.add(["transcript"], for: "A", source: .claudeCodeTranscript)
        tally.add(["buffer"], for: "A", source: .buffer)
        XCTAssertEqual(tally.entries["A"]?.first, "buffer")
    }

    func testOrdinalRecordsOrderOfFirstMatch() {
        var tally = iTermContentMatchTally<String, String>()
        tally.add(["b"], for: "B", source: .buffer)
        tally.add(["a"], for: "A", source: .buffer)
        tally.add(["b2"], for: "B", source: .claudeCodeTranscript)
        XCTAssertEqual(tally.entries["B"]?.ordinal, 0)
        XCTAssertEqual(tally.entries["A"]?.ordinal, 1)
    }

    func testEmptyResultsAreIgnored() {
        var tally = iTermContentMatchTally<String, String>()
        tally.add([], for: "A", source: .buffer)
        XCTAssertNil(tally.entries["A"])
    }
}

final class ClaudeCodeTranscriptParserTests: XCTestCase {
    private func jsonl(_ records: [[String: Any]]) -> Data {
        let lines = records.map { record in
            String(data: try! JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
        }
        return (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
    }

    func testExtractsUserAndAssistantText() {
        let data = jsonl([
            ["type": "user", "message": ["role": "user", "content": "fix the flaky login test"]],
            ["type": "assistant", "message": ["role": "assistant",
                                              "content": [["type": "thinking", "thinking": "secret"],
                                                          ["type": "text", "text": "The race is in setUp."]]]],
            ["type": "assistant", "message": ["role": "assistant",
                                              "content": [["type": "tool_use", "name": "Bash", "input": ["command": "ls"]]]]],
            ["type": "user", "message": ["role": "user",
                                         "content": [["type": "tool_result", "content": "file.txt"]]]],
            ["type": "attachment", "attachment": ["text": "ignored"]],
        ])
        XCTAssertEqual(iTermClaudeCodeTranscriptParser.messages(inJSONLines: data),
                       ["fix the flaky login test", "The race is in setUp."])
    }

    func testSkipsMalformedLines() {
        var data = "not json\n{\"type\":\"user\"}\n".data(using: .utf8)!
        data += jsonl([["type": "user", "message": ["content": "ok"]]])
        XCTAssertEqual(iTermClaudeCodeTranscriptParser.messages(inJSONLines: data), ["ok"])
    }
}

final class TextOccurrencesTests: XCTestCase {
    func testSmartCase() {
        let texts = ["Hello hello HELLO", "say hello"]
        XCTAssertEqual(iTermTextOccurrences(of: "hello", in: texts).count, 4)
        XCTAssertEqual(iTermTextOccurrences(of: "Hello", in: texts).count, 1)
    }

    func testNoMatch() {
        let occurrences = iTermTextOccurrences(of: "absent", in: ["present"])
        XCTAssertEqual(occurrences.count, 0)
        XCTAssertNil(occurrences.snippet())
    }

    func testSnippetIsOneLineWithMatchRange() {
        let text = "first line\nthe needle is here\nlast line"
        let snippet = iTermTextOccurrences(of: "needle", in: [text]).snippet(maximumPrefixLength: 4,
                                                                               maximumSuffixLength: 3)!
        XCTAssertEqual(snippet.text, "…the needle is")
        XCTAssertEqual((snippet.text as NSString).substring(with: snippet.matchRange), "needle")
    }

    func testSnippetAtStartHasNoEllipsis() {
        let snippet = iTermTextOccurrences(of: "needle", in: ["needle"]).snippet()!
        XCTAssertEqual(snippet.text, "needle")
        XCTAssertEqual(snippet.matchRange, NSRange(location: 0, length: 6))
    }
}

final class ClaudeCodeTranscriptLocationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("sessions"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func writeSessionFile(pid: pid_t, sessionID: String, cwd: String, startedAt: Date = Date()) throws {
        let json = try JSONSerialization.data(withJSONObject: ["pid": pid,
                                                               "sessionId": sessionID,
                                                               "cwd": cwd,
                                                               "startedAt": startedAt.timeIntervalSince1970 * 1000])
        try json.write(to: directory.appendingPathComponent("sessions/\(pid).json"))
    }

    private func writeTranscript(project: String, sessionID: String, contents: String = "") throws -> URL {
        let projectDirectory = directory.appendingPathComponent("projects/\(project)")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let url = projectDirectory.appendingPathComponent("\(sessionID).jsonl")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testFindsTranscriptFromWorkingDirectory() throws {
        try writeSessionFile(pid: 1234, sessionID: "abc", cwd: "/Users/me/src/my.app")
        let url = try writeTranscript(project: "-Users-me-src-my-app", sessionID: "abc")
        let transcripts = iTermClaudeCodeTranscripts(configDirectory: directory)
        XCTAssertEqual(transcripts.transcriptURL(forProcessID: 1234)?.standardizedFileURL,
                       url.standardizedFileURL)
    }

    func testFallsBackToSearchingProjects() throws {
        try writeSessionFile(pid: 1234, sessionID: "abc", cwd: "/somewhere/else")
        let url = try writeTranscript(project: "unexpected-name", sessionID: "abc")
        let transcripts = iTermClaudeCodeTranscripts(configDirectory: directory)
        XCTAssertEqual(transcripts.transcriptURL(forProcessID: 1234)?.standardizedFileURL,
                       url.standardizedFileURL)
    }

    func testIgnoresSessionFileOfAnEarlierProcessWithTheSamePID() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000_000)
        try writeSessionFile(pid: 1234, sessionID: "abc", cwd: "/p", startedAt: startedAt)
        _ = try writeTranscript(project: "-p", sessionID: "abc")
        let transcripts = iTermClaudeCodeTranscripts(configDirectory: directory)
        XCTAssertNotNil(transcripts.transcriptURL(forProcessID: 1234, startTime: startedAt.addingTimeInterval(-1)))
        XCTAssertNil(transcripts.transcriptURL(forProcessID: 1234, startTime: startedAt.addingTimeInterval(3600)))
    }

    func testNoSessionFile() {
        let transcripts = iTermClaudeCodeTranscripts(configDirectory: directory)
        XCTAssertNil(transcripts.transcriptURL(forProcessID: 999))
    }

    func testRejectsPathInSessionID() throws {
        try writeSessionFile(pid: 1234, sessionID: "../../etc/passwd", cwd: "/")
        let transcripts = iTermClaudeCodeTranscripts(configDirectory: directory)
        XCTAssertNil(transcripts.transcriptURL(forProcessID: 1234))
    }

    func testProjectDirectoryName() {
        XCTAssertEqual(iTermClaudeCodeTranscripts.projectDirectoryName(forWorkingDirectory: "/Users/me/src/my.app"),
                       "-Users-me-src-my-app")
        // One hyphen per UTF-16 code unit: “/”, “é”, and two for the emoji.
        XCTAssertEqual(iTermClaudeCodeTranscripts.projectDirectoryName(forWorkingDirectory: "/tmp/é😀"),
                       "-tmp----")
    }

    private func record(_ text: String) -> String {
        return "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"\(text)\"}}\n"
    }

    // Searches the transcript of the fake Claude Code process 1234.
    private func count(_ query: String, in transcripts: iTermClaudeCodeTranscripts) -> Int {
        let done = expectation(description: "search")
        var count = 0
        transcripts.search(for: query, candidates: ["session": [.init(pid: 1), .init(pid: 1234)]]) { results in
            count = results["session"]?.count ?? 0
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return count
    }

    func testSearchSeesAppendedMessages() throws {
        try writeSessionFile(pid: 1234, sessionID: "abc", cwd: "/p")
        let url = try writeTranscript(project: "-p", sessionID: "abc", contents: record("alpha"))
        let transcripts = iTermClaudeCodeTranscripts(configDirectory: directory)
        XCTAssertEqual(count("alpha", in: transcripts), 1)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        // A complete record followed by one that is still being written.
        try handle.write(contentsOf: (record("beta alpha") + "{\"type\":\"us").data(using: .utf8)!)
        try handle.close()
        XCTAssertEqual(count("alpha", in: transcripts), 2)
        XCTAssertEqual(count("beta", in: transcripts), 1)
    }

    func testRewrittenTranscriptIsReparsed() throws {
        try writeSessionFile(pid: 1234, sessionID: "abc", cwd: "/p")
        _ = try writeTranscript(project: "-p", sessionID: "abc", contents: record("alpha"))
        let transcripts = iTermClaudeCodeTranscripts(configDirectory: directory)
        XCTAssertEqual(count("alpha", in: transcripts), 1)

        // Replaced by a different, longer file.
        _ = try writeTranscript(project: "-p", sessionID: "abc", contents: record("gamma") + record("gamma"))
        XCTAssertEqual(count("alpha", in: transcripts), 0)
        XCTAssertEqual(count("gamma", in: transcripts), 2)
    }

    func testNewerSearchSupersedesOlder() throws {
        try writeSessionFile(pid: 1234, sessionID: "abc", cwd: "/p")
        _ = try writeTranscript(project: "-p", sessionID: "abc", contents: record("alpha"))
        let transcripts = iTermClaudeCodeTranscripts(configDirectory: directory)
        let older = expectation(description: "older")
        older.isInverted = true
        let newer = expectation(description: "newer")
        transcripts.search(for: "alpha", candidates: ["session": [.init(pid: 1234)]]) { _ in older.fulfill() }
        transcripts.search(for: "alpha", candidates: ["session": [.init(pid: 1234)]]) { _ in newer.fulfill() }
        wait(for: [newer], timeout: 10)
        wait(for: [older], timeout: 0.1)
    }
}

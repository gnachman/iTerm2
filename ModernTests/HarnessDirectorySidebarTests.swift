import XCTest
@testable import iTerm2SharedARC

final class HarnessDirectorySidebarTests: XCTestCase {
    func testDirectoryIdentity() {
        func key(_ host: String?, _ user: String?, _ path: String?, _ id: String = "a") -> SessionDirectoryKey {
            SessionDirectoryKey(host: host, user: user, path: path, sessionID: id)
        }
        XCTAssertEqual(key("host", "user", "/work/"), key("host", "user", "/work", "b"))
        XCTAssertNotEqual(key("host", "user", "/work"), key("other", "user", "/work"))
        XCTAssertNotEqual(key("host", "user", "/work"), key("host", "other", "/work"))
        XCTAssertNotEqual(key(nil, nil, nil), key(nil, nil, nil, "b"))
        XCTAssertNil(key(nil, nil, "~/work").path)
        XCTAssertEqual(key(nil, nil, "/").path, "/")
        XCTAssertEqual(key(nil, nil, "///").path, "/")
        XCTAssertEqual(key(nil, nil, "/work//").path, "/work")
    }

    func testHarnessExecutableDetectionRejectsTitlesAndArguments() {
        XCTAssertEqual(SessionDirectoryKey.harnessName(executable: "/opt/bin/codex"), "Codex")
        XCTAssertEqual(SessionDirectoryKey.harnessName(executable: "claude"), "Claude")
        XCTAssertEqual(SessionDirectoryKey.harnessName(executable: "agy"), "Antigravity")
        XCTAssertEqual(SessionDirectoryKey.harnessName(executable: "node", arguments: ["node", "/tools/node_modules/@openai/codex/bin/codex.js"]), "Codex")
        XCTAssertNil(SessionDirectoryKey.harnessName(executable: "node", arguments: ["node", "/app.js", "codex"]))
        for executable in ["vim", "tmux", "echo codex", "codex project", "not-claude", "zsh"] {
            XCTAssertNil(SessionDirectoryKey.harnessName(executable: executable))
        }
    }

    func testTmuxSocketArgumentsPreserveSpacesAndExcludeConfigAndCommands() {
        XCTAssertEqual(HarnessTmuxProbe.socketArguments([
            "tmux", "-S", "/tmp/server with spaces", "-f", "/tmp/config", "-u", "attach-session", "-t", "work"
        ]), ["-S", "/tmp/server with spaces"])
        XCTAssertEqual(HarnessTmuxProbe.socketArguments(["tmux", "-Lnamed", "attach"]), ["-L", "named"])
        XCTAssertEqual(HarnessTmuxProbe.socketArguments(["tmux", "attach"]), [])
        XCTAssertNil(HarnessTmuxProbe.socketArguments(["tmux", "-S"]))
    }

    func testTmuxSelectsOnlyMatchingClientMetadata() {
        let text = "10\u{1f}%1\u{1f}vim\u{1f}/elsewhere\u{1f}101\n20\u{1f}%3\u{1f}codex\u{1f}/work with spaces\u{1f}202\n"
        let pane = HarnessTmuxProbe.parse(text, clientPID: 20)
        XCTAssertEqual(pane?.command, "codex")
        XCTAssertEqual(pane?.path, "/work with spaces")
        XCTAssertEqual(pane?.id, "%3")
        XCTAssertEqual(pane?.pid, 202)
        XCTAssertNil(HarnessTmuxProbe.parse(text, clientPID: 99))
        XCTAssertNil(HarnessTmuxProbe.parse("broken", clientPID: 20))
    }
}

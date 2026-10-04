//
//  LocalFileCheckerTests.swift
//  ModernTests
//
//  The composer’s command validity check searches the shell’s PATH, which it reads once
//  through the slow-operation gateway. A shell that cannot be run must be treated as
//  “unknown, ask again later”, not as an empty PATH that marks every command invalid until
//  the checker is discarded, and not retried on every keystroke either. The fetch, stat and
//  clock are injected so no shell is spawned and no test waits on real time.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class LocalFileCheckerTests: XCTestCase {
    private final class FakeGateway {
        var pathCompletions: [(String?) -> Void] = []
        var statPaths: [String] = []

        func fetchPath(shell: String, completion: @escaping (String?) -> Void) {
            pathCompletions.append(completion)
        }

        func statFile(path: String, completion: @escaping (stat, Int32) -> Void) {
            statPaths.append(path)
        }
    }

    private var clock: TimeInterval = 1000

    private func makeChecker(_ gateway: FakeGateway) -> LocalFileChecker {
        return LocalFileChecker(shell: "/bin/zsh",
                                fetchPath: gateway.fetchPath,
                                statFile: gateway.statFile,
                                now: { [unowned self] in self.clock })
    }

    // Lets main-queue work the checker enqueued before this point run. Blocks on the main
    // queue are executed in order, so once this one has run, earlier ones have too.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 5)
    }

    func testNilPathReplyDoesNotStickAsEmptyPath() {
        let gateway = FakeGateway()
        let checker = makeChecker(gateway)

        XCTAssertNil(checker.commandIsValid("ls"), "Unknown while PATH is being fetched")
        XCTAssertEqual(gateway.pathCompletions.count, 1)

        gateway.pathCompletions[0](nil)
        drainMainQueue()

        // The composer checks on every edit; a broken shell must not be relaunched each time.
        for _ in 0..<5 {
            XCTAssertNil(checker.commandIsValid("ls"), "Still unknown after the shell failed")
        }
        XCTAssertEqual(gateway.pathCompletions.count, 1, "No retry inside the backoff interval")
        XCTAssertTrue(gateway.statPaths.isEmpty, "Nothing was searched against an empty PATH")

        // After the backoff the fetch is retried, and once the shell answers the search proceeds.
        clock += 61
        XCTAssertNil(checker.commandIsValid("ls"))
        XCTAssertEqual(gateway.pathCompletions.count, 2, "Retried after the backoff")
        gateway.pathCompletions[1]("/usr/bin")
        XCTAssertNil(checker.commandIsValid("ls"))
        XCTAssertEqual(gateway.statPaths, ["/usr/bin/ls"])
    }

    func testPathReplyIsFetchedOnceAndSearched() {
        let gateway = FakeGateway()
        let checker = makeChecker(gateway)

        XCTAssertNil(checker.commandIsValid("ls"))
        gateway.pathCompletions[0]("/usr/bin:/bin")

        XCTAssertNil(checker.commandIsValid("ls"), "Unknown until a stat answers")
        XCTAssertEqual(gateway.pathCompletions.count, 1, "PATH is not fetched again")
        XCTAssertEqual(gateway.statPaths, ["/usr/bin/ls", "/bin/ls"])
    }
}

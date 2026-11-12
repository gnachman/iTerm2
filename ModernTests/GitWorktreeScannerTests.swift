import Foundation
import XCTest
#if !GIT_WORKTREE_SCANNER_STANDALONE
@testable import iTerm2SharedARC
#endif

final class GitWorktreeScannerTests: XCTestCase {
    func testNulParserPreservesPathsAndFlags() throws {
        let data = Data(("worktree /tmp/main \n\0HEAD 123\0branch refs/heads/main\0\0" +
                         "worktree /tmp/工作 tree\nnext\0HEAD 456\0detached\0locked reason\0prunable reason\0\0").utf8)
        let rows = try iTermGitWorktreePorcelainParser.parse(data, nulDelimited: true)
        XCTAssertEqual(rows.count, 2)
        guard rows.count == 2 else { return }
        XCTAssertEqual(rows[0].path, "/tmp/main \n")
        XCTAssertTrue(rows[0].isMain)
        XCTAssertEqual(rows[0].branch, "refs/heads/main")
        XCTAssertEqual(rows[1].path, "/tmp/工作 tree\nnext")
        XCTAssertNil(rows[1].branch)
        XCTAssertEqual(rows[1].head, "456")
        XCTAssertTrue(rows[1].locked)
        XCTAssertTrue(rows[1].prunable)
    }

    func testOldParserDecodesGitCQuotedUTF8AndEscapes() throws {
        let text = "worktree /main \nHEAD abc\nbranch refs/heads/main\n\n" +
            "worktree \"/tmp/\\345\\267\\245\\344\\275\\234\\n\\t\\\\\\\"\"\nHEAD def\ndetached\nlocked\n\n"
        let rows = try iTermGitWorktreePorcelainParser.parse(Data(text.utf8), nulDelimited: false)
        XCTAssertEqual(rows.count, 2)
        guard rows.count == 2 else { return }
        XCTAssertEqual(rows[0].path, "/main ")
        XCTAssertEqual(rows[1].path, "/tmp/工作\n\t\\\"")
        XCTAssertTrue(rows[1].locked)
    }

    func testOldParserPreservesRawMultilinePaths() throws {
        let rows = try iTermGitWorktreePorcelainParser.parse(
            Data("worktree /main \n\nHEAD abc\nbranch refs/heads/main\n\nworktree /side\nnext\nHEAD def\ndetached\n\n".utf8),
            nulDelimited: false)
        XCTAssertEqual(rows.count, 2)
        guard rows.count == 2 else { return }
        XCTAssertEqual(rows[0].path, "/main \n")
        XCTAssertEqual(rows[1].path, "/side\nnext")
    }

    func testBareRecordDoesNotMakeLinkedCheckoutMain() throws {
        let rows = try iTermGitWorktreePorcelainParser.parse(
            Data("worktree /bare\0bare\0\0worktree /linked\0HEAD abc\0detached\0\0".utf8), nulDelimited: true)
        XCTAssertEqual(rows.count, 2)
        guard rows.count == 2 else { return }
        XCTAssertTrue(rows[0].bare)
        XCTAssertFalse(rows[1].isMain)
    }

    func testRealGitLinkedNestedSymlinkAndMissingRows() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let linked = fixture.base + "/ 工作 tree\n "
        let detached = fixture.base + "/detached"
        let missing = fixture.base + "/missing"
        try fixture.git(["worktree", "add", "-b", "feature/z", linked])
        try fixture.git(["worktree", "add", "--detach", detached])
        try fixture.git(["worktree", "lock", detached])
        try fixture.git(["worktree", "add", "-b", "feature/a", missing])
        try FileManager.default.removeItem(atPath: missing)
        let nested = linked + "/nested/deep"
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        let alias = fixture.base + "/alias"
        try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: nested)
        let result = scan(iTermGitWorktreeScanner(executor: ProcessGitExecutor()), directory: alias)
        XCTAssertNil(result.1)
        XCTAssertEqual(result.0?.rootDirectory, fixture.root)
        XCTAssertEqual(result.0?.commonDirectory, fixture.root + "/.git")
        XCTAssertEqual(result.0?.worktrees.count, 4)
        XCTAssertEqual(result.0?.worktrees.first?.rootDirectory, fixture.root)
        XCTAssertEqual(result.0?.worktrees.first?.branch, "main")
        let rows = result.0?.worktrees ?? []
        XCTAssertEqual(rows.first { $0.branch == "feature/z" }?.rootDirectory, linked)
        XCTAssertTrue(rows.first { $0.rootDirectory == detached }?.locked == true)
        XCTAssertNil(rows.first { $0.rootDirectory == detached }?.branch)
        XCTAssertTrue(rows.first { $0.branch == "feature/a" }?.prunable == true)
        XCTAssertFalse(rows.first { $0.branch == "feature/a" }?.available ?? true)
        XCTAssertEqual(rows.map { $0.branch }, ["main", nil, "feature/a", "feature/z"])
        XCTAssertTrue(rows.first { $0.branch == "feature/a" }?.rootDirectory.hasSuffix("/missing") == true)
    }

    func testSeparateGitDirectoryMainAndBareExclusion() throws {
        let fixture = try GitFixture(separate: true)
        defer { fixture.remove() }
        let scanner = iTermGitWorktreeScanner(executor: ProcessGitExecutor())
        let result = scan(scanner, directory: fixture.root)
        XCTAssertNil(result.1)
        XCTAssertEqual(result.0?.rootDirectory, fixture.root)
        XCTAssertEqual(result.0?.worktrees.first?.rootDirectory, fixture.root)
        XCTAssertEqual(result.0?.commonDirectory, fixture.base + "/admin")
        let bare = fixture.base + "/bare"
        try fixture.git(["init", "--bare", bare])
        let bareResult = scan(scanner, directory: bare)
        XCTAssertNil(bareResult.1)
        XCTAssertEqual(bareResult.0?.worktrees.count, 0)
    }

    func testUnsupportedZFallbackIsRememberedAndPreservesQuotedPath() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let linked = fixture.base + "/工作\n\"quoted\""
        try fixture.git(["worktree", "add", "-b", "side", linked])
        let executor = OldGitExecutor()
        for directory in [fixture.root, linked] {
            let result = scan(iTermGitWorktreeScanner(executor: executor), directory: directory)
            XCTAssertNil(result.1)
            XCTAssertEqual(result.0?.worktrees.last?.rootDirectory, linked)
        }
        XCTAssertEqual(executor.unsupportedCalls, 1)
    }

    func testNonGitVersusUnsafeFailureTimeoutAndOverflow() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let plain = fixture.base + "/plain"
        try FileManager.default.createDirectory(atPath: plain, withIntermediateDirectories: false)
        let nonGit = scan(iTermGitWorktreeScanner(executor: ProcessGitExecutor()), directory: plain)
        XCTAssertNil(nonGit.0)
        XCTAssertNil(nonGit.1)
        for response in [iTermGitWorktreeCommandResult(output: Data(), status: 128),
                         iTermGitWorktreeCommandResult(output: Data(), status: 9, timedOut: true),
                         iTermGitWorktreeCommandResult(output: Data(), status: 9, truncated: true)] {
            let failure = scan(iTermGitWorktreeScanner(executor: FixedGitExecutor(response)), directory: fixture.root)
            XCTAssertNil(failure.0)
            XCTAssertNotNil(failure.1)
        }
    }

    func testRequestsAreNonblockingAndDuplicatePathsCoalesce() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let started = expectation(description: "Git worker entered gate")
        let completed = expectation(description: "Both callers completed on main")
        completed.expectedFulfillmentCount = 2
        let executor = GatedGitExecutor(onStart: { started.fulfill() })
        let scanner = iTermGitWorktreeScanner(executor: executor)
        var snapshots = [iTermGitRepositorySnapshot]()
        for _ in 0..<2 {
            scanner.scan(directory: fixture.root) { result, error in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNil(error)
                if let result { snapshots.append(result) }
                completed.fulfill()
            }
        }
        wait(for: [started], timeout: 10)
        // The main thread reached this line while the executor was still gated.
        executor.release.signal()
        wait(for: [completed], timeout: 10)
        XCTAssertEqual(executor.commonCalls, 1)
        XCTAssertEqual(snapshots.count, 2)
        if snapshots.count == 2 { XCTAssertTrue(snapshots[0] === snapshots[1]) }
    }

    func testDistinctRepositoriesKeepAtMostTwoWorkersAlive() throws {
        let fixtures = try (0..<3).map { _ in try GitFixture() }
        defer { fixtures.forEach { $0.remove() } }
        let started = expectation(description: "Two workers reached gates")
        started.expectedFulfillmentCount = 2
        let completed = expectation(description: "Three repositories scanned")
        completed.expectedFulfillmentCount = 3
        let executor = LifetimeGitExecutor(onStart: { started.fulfill() })
        let scanner = iTermGitWorktreeScanner(executor: executor)
        for fixture in fixtures {
            scanner.scan(directory: fixture.root) { result, error in
                XCTAssertNotNil(result)
                XCTAssertNil(error)
                completed.fulfill()
            }
        }
        wait(for: [started], timeout: 10)
        for _ in 0..<3 { executor.release.signal() }
        wait(for: [completed], timeout: 10)
        XCTAssertEqual(executor.peakWorkers, 2)
        XCTAssertTrue(executor.timeouts.allSatisfy { $0 > 0 && $0 <= 5 })
    }

    func testLinkedAndMainCallersShareCommonDirectoryFlight() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let linked = fixture.base + "/side"
        try fixture.git(["worktree", "add", "-b", "side", linked])
        let located = expectation(description: "Both common directory queries returned")
        located.expectedFulfillmentCount = 2
        let listing = expectation(description: "Owner is listing")
        let completed = expectation(description: "Shared repository completed")
        completed.expectedFulfillmentCount = 2
        let executor = SharedGitExecutor(onCommon: { located.fulfill() }, onList: { listing.fulfill() })
        let scanner = iTermGitWorktreeScanner(executor: executor)
        var snapshots = [iTermGitRepositorySnapshot]()
        for directory in [fixture.root, linked] {
            scanner.scan(directory: directory) { result, error in
                XCTAssertNil(error)
                if let result { snapshots.append(result) }
                completed.fulfill()
            }
        }
        wait(for: [located, listing], timeout: 10)
        executor.release.signal()
        wait(for: [completed], timeout: 10)
        XCTAssertEqual(executor.listCalls, 1)
        XCTAssertEqual(snapshots.count, 2)
        if snapshots.count == 2 { XCTAssertTrue(snapshots[0] === snapshots[1]) }
    }

    func testDeadlineCompletesWhileWorkerIsGatedAndLateResultCannotReplaceNewFlight() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let started = expectation(description: "First worker is gated")
        let expired = expectation(description: "Deadline completion")
        expired.assertForOverFulfill = true
        let executor = FirstGatedGitExecutor(onStart: { started.fulfill() })
        let scanner = iTermGitWorktreeScanner(executor: executor)
        scanner.scan(directory: fixture.root) { snapshot, error in
            XCTAssertNil(snapshot)
            XCTAssertEqual(error?.code, 2)
            expired.fulfill()
        }
        wait(for: [started, expired], timeout: 10)
        let fresh = scan(scanner, directory: fixture.root)
        XCTAssertNil(fresh.1)
        XCTAssertEqual(fresh.0?.worktrees.first?.branch, "main")
        executor.release.signal()
        // A follow-up scan must still return fresh data, and the expired caller
        // must receive exactly one completion despite its command returning late.
        let final = scan(scanner, directory: fixture.root)
        XCTAssertNil(final.1)
        XCTAssertNotNil(final.0)
    }

    func testSeparateGitLinkedCallerNeverSelectsUnknownAdminRoot() throws {
        let fixture = try GitFixture(separate: true)
        defer { fixture.remove() }
        let linked = fixture.base + "/side"
        try fixture.git(["worktree", "add", "-b", "side", linked])
        let result = scan(iTermGitWorktreeScanner(executor: ProcessGitExecutor()), directory: linked)
        XCTAssertNil(result.1)
        XCTAssertTrue(result.0?.worktrees.first?.isMain == true)
        XCTAssertFalse(result.0?.worktrees.first?.available ?? true)
        XCTAssertEqual(result.0?.worktrees.last?.rootDirectory, linked)
        XCTAssertTrue(result.0?.worktrees.last?.available == true)
    }

    func testSeparateGitLinkedOwnerSharesMainCallerRootEnrichment() throws {
        let fixture = try GitFixture(separate: true)
        defer { fixture.remove() }
        let independent = try GitFixture()
        defer { independent.remove() }
        let linked = fixture.base + "/side"
        try fixture.git(["worktree", "add", "-b", "side", linked])
        let listing = expectation(description: "Linked caller owns listing")
        let mainLocated = expectation(description: "Main caller resolved its own toplevel")
        let completed = expectation(description: "Both callers received enriched snapshot")
        completed.expectedFulfillmentCount = 2
        let executor = MainEnrichmentGitExecutor(mainRoot: fixture.root, linkedRoot: linked,
                                                onList: { listing.fulfill() },
                                                onMainRoot: { mainLocated.fulfill() })
        let scanner = iTermGitWorktreeScanner(executor: executor)
        var snapshots = [iTermGitRepositorySnapshot]()
        let completion: (iTermGitRepositorySnapshot?, NSError?) -> Void = { snapshot, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(error)
            XCTAssertEqual(snapshot?.rootDirectory, fixture.root)
            XCTAssertEqual(snapshot?.worktrees.first?.rootDirectory, fixture.root)
            XCTAssertTrue(snapshot?.worktrees.first?.available == true)
            if let snapshot { snapshots.append(snapshot) }
            completed.fulfill()
        }
        scanner.scan(directory: linked, completion: completion)
        wait(for: [listing], timeout: 10)
        scanner.scan(directory: fixture.root, completion: completion)
        // The native metadata event orders the regression without sleeps or a
        // main-callback/state-queue race. Listing must stay shared while the
        // follower finishes interpreting its toplevel response on the worker.
        wait(for: [mainLocated], timeout: 10)
        executor.release.signal()
        // The joined main worker is still gated. The owner's completed listing
        // must release its worker slot so an unrelated repository can scan.
        let other = scan(scanner, directory: independent.root)
        XCTAssertNil(other.1)
        XCTAssertEqual(other.0?.rootDirectory, independent.root)
        executor.mainMetadataRelease.signal()
        wait(for: [completed], timeout: 10)
        XCTAssertEqual(executor.listCalls, 2)
        XCTAssertEqual(snapshots.count, 2)
        if snapshots.count == 2 { XCTAssertTrue(snapshots[0] === snapshots[1]) }
    }

    func testBareRepositoryWithoutOptionalConfigKeepsLinkedCheckout() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let bare = fixture.base + "/bare"
        let linked = fixture.base + "/bare-side"
        try fixture.git(["clone", "--bare", fixture.root, bare])
        let git = ProcessGitExecutor()
        let added = git.run(arguments: ["worktree", "add", "-b", "bare-side", linked], directory: bare, timeout: 10)
        XCTAssertEqual(added.status, 0)
        try FileManager.default.removeItem(atPath: bare + "/config")
        let result = scan(iTermGitWorktreeScanner(executor: git), directory: bare)
        XCTAssertNil(result.1)
        XCTAssertEqual(result.0?.commonDirectory, bare)
        XCTAssertEqual(result.0?.rootDirectory, bare)
        XCTAssertEqual(result.0?.worktrees.count, 1)
        XCTAssertEqual(result.0?.worktrees.first?.rootDirectory, linked)
        XCTAssertFalse(result.0?.worktrees.first?.isMain ?? true)
        XCTAssertTrue(result.0?.worktrees.first?.available == true)
    }

    func testMalformedParserOutputFailsInsteadOfReturningPartialData() {
        for data in [Data(), Data([0xff]), Data("worktree /root\0\0".utf8),
                     Data("worktree \"/bad\\777\"\nHEAD abc\n\n".utf8)] {
            XCTAssertThrowsError(try iTermGitWorktreePorcelainParser.parse(data, nulDelimited: data.contains(0)))
        }
    }

    private func scan(_ scanner: iTermGitWorktreeScanning, directory: String) -> (iTermGitRepositorySnapshot?, NSError?) {
        let done = expectation(description: "Scan completion")
        var result: iTermGitRepositorySnapshot?
        var failure: NSError?
        scanner.scan(directory: directory) { snapshot, error in
            XCTAssertTrue(Thread.isMainThread)
            result = snapshot
            failure = error
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return (result, failure)
    }

}

private final class GitFixture {
    let base: String
    let root: String
    init(separate: Bool = false) throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("git-scanner-" + UUID().uuidString).resolvingSymlinksInPath().path
        root = base + "/ main checkout \n"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try git(separate ? ["init", "-b", "main", "--separate-git-dir", base + "/admin"] : ["init", "-b", "main"])
        try git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "-m", "initial"])
    }
    @discardableResult
    func git(_ arguments: [String]) throws -> Data {
        let result = ProcessGitExecutor().run(arguments: arguments, directory: root, timeout: 10)
        guard result.status == 0 else {
            throw NSError(domain: "GitFixture", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: arguments.joined(separator: " ")])
        }
        return result.output
    }
    func remove() { try? FileManager.default.removeItem(atPath: base) }
}

private class ProcessGitExecutor: iTermGitWorktreeCommandExecuting {
    func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .init(output: Data(), status: -1) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return .init(output: data, status: process.terminationStatus)
    }
}

private final class OldGitExecutor: ProcessGitExecutor {
    var unsupportedCalls = 0
    override func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
        if arguments == ["worktree", "list", "--porcelain", "-z"] {
            unsupportedCalls += 1
            return .init(output: Data(), status: 129)
        }
        return super.run(arguments: arguments, directory: directory, timeout: timeout)
    }
}

private final class FixedGitExecutor: iTermGitWorktreeCommandExecuting {
    let response: iTermGitWorktreeCommandResult
    init(_ response: iTermGitWorktreeCommandResult) { self.response = response }
    func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult { response }
}

private final class GatedGitExecutor: ProcessGitExecutor {
    let release = DispatchSemaphore(value: 0)
    let onStart: () -> Void
    private(set) var commonCalls = 0
    init(onStart: @escaping () -> Void) { self.onStart = onStart }
    override func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
        XCTAssertFalse(Thread.isMainThread)
        if arguments == ["rev-parse", "--git-common-dir"] {
            commonCalls += 1
            DispatchQueue.main.async(execute: onStart)
            release.wait()
        }
        return super.run(arguments: arguments, directory: directory, timeout: timeout)
    }
}

private final class LifetimeGitExecutor: ProcessGitExecutor {
    let release = DispatchSemaphore(value: 0)
    let onStart: () -> Void
    let lock = NSLock()
    private var active = 0
    private var calls = 0
    private(set) var peakWorkers = 0
    private(set) var timeouts = [TimeInterval]()
    init(onStart: @escaping () -> Void) { self.onStart = onStart }
    override func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
        lock.lock()
        active += 1
        peakWorkers = max(peakWorkers, active)
        timeouts.append(timeout)
        var gated = false
        if arguments == ["rev-parse", "--git-common-dir"] {
            calls += 1
            gated = calls <= 2
        }
        lock.unlock()
        defer { lock.lock(); active -= 1; lock.unlock() }
        if gated {
            DispatchQueue.main.async(execute: onStart)
            release.wait()
        }
        return super.run(arguments: arguments, directory: directory, timeout: timeout)
    }
}

private final class SharedGitExecutor: ProcessGitExecutor {
    let release = DispatchSemaphore(value: 0)
    let onCommon: () -> Void
    let onList: () -> Void
    let lock = NSLock()
    private(set) var listCalls = 0
    init(onCommon: @escaping () -> Void, onList: @escaping () -> Void) {
        self.onCommon = onCommon
        self.onList = onList
    }
    override func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
        if arguments.first == "worktree" {
            lock.lock()
            listCalls += 1
            lock.unlock()
            DispatchQueue.main.async(execute: onList)
            release.wait()
        }
        let result = super.run(arguments: arguments, directory: directory, timeout: timeout)
        if arguments == ["rev-parse", "--git-common-dir"] { DispatchQueue.main.async(execute: onCommon) }
        return result
    }
}

private final class FirstGatedGitExecutor: ProcessGitExecutor {
    let release = DispatchSemaphore(value: 0)
    let onStart: () -> Void
    let lock = NSLock()
    private var first = true
    init(onStart: @escaping () -> Void) { self.onStart = onStart }
    override func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
        lock.lock()
        let gated = first
        first = false
        lock.unlock()
        let result = super.run(arguments: arguments, directory: directory, timeout: timeout)
        if gated {
            DispatchQueue.main.async(execute: onStart)
            release.wait()
        }
        return result
    }
}

private final class MainEnrichmentGitExecutor: ProcessGitExecutor {
    let release = DispatchSemaphore(value: 0)
    let mainMetadataRelease = DispatchSemaphore(value: 0)
    let mainRoot: String
    let linkedRoot: String
    let onList: () -> Void
    let onMainRoot: () -> Void
    let lock = NSLock()
    private(set) var listCalls = 0
    init(mainRoot: String, linkedRoot: String, onList: @escaping () -> Void, onMainRoot: @escaping () -> Void) {
        self.mainRoot = mainRoot
        self.linkedRoot = linkedRoot
        self.onList = onList
        self.onMainRoot = onMainRoot
    }
    override func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
        let result = super.run(arguments: arguments, directory: directory, timeout: timeout)
        if arguments.first == "worktree" {
            lock.lock()
            listCalls += 1
            lock.unlock()
            if directory == linkedRoot {
                DispatchQueue.main.async(execute: onList)
                release.wait()
            }
        } else if directory == mainRoot && arguments == ["rev-parse", "--show-toplevel"] {
            DispatchQueue.main.async(execute: onMainRoot)
            mainMetadataRelease.wait()
        }
        return result
    }
}

#if GIT_WORKTREE_SCANNER_STANDALONE
@main
struct GitWorktreeScannerTestMain {
    static func main() {
        let suite = XCTestSuite(forTestCaseClass: GitWorktreeScannerTests.self)
        suite.run()
        exit(suite.testRun?.totalFailureCount == 0 ? 0 : 1)
    }
}

#endif

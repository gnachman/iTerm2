import XCTest
@testable import iTerm2SharedARC

final class GitProjectIntegrationTests: XCTestCase {
    private final class GitExecutor: iTermGitWorktreeCommandExecuting {
        func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            task.arguments = arguments
            task.currentDirectoryURL = URL(fileURLWithPath: directory)
            task.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
            let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            do { try task.run() } catch { return .init(output: Data(), status: -1) }
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return .init(output: output, status: task.terminationStatus)
        }
    }
    private final class Scanner: iTermGitWorktreeScanning {
        var snapshot: iTermGitRepositorySnapshot?
        var error: NSError?
        var delayed = false
        var pending = [(iTermGitRepositorySnapshot?, NSError?) -> Void]()
        var entered: (() -> Void)?
        func scan(directory: String, completion: @escaping (iTermGitRepositorySnapshot?, NSError?) -> Void) {
            if delayed { pending.append(completion); entered?() }
            else { completion(snapshot, error) }
        }
        func deliver() {
            let callbacks = pending
            pending.removeAll()
            callbacks.forEach { $0(snapshot, error) }
        }
    }

    private final class Window: NSObject, iTermProjectWindowDelegate {
        var projectTabAssociations = [String: String]()
        var projectActiveTabIdentifier: String?
        var launches = 0
        var launchDirectory: String?
        var launchProject: iTermProjectDirectory?
        var launchCompletion: ((String?) -> Void)?
        var didLaunch: (() -> Void)?
        var workingDirectory: String?
        var errors = [NSError]()
        var stateChanged: (() -> Void)?
        func projectSelectTab(_ identifier: String) { projectActiveTabIdentifier = identifier }
        func projectAssign(_ project: String?, toTab identifier: String) { projectTabAssociations[identifier] = project ?? "" }
        func projectLaunch(_ project: iTermProjectDirectory, directory: String, completion: @escaping (String?) -> Void) {
            launches += 1
            launchDirectory = directory
            launchProject = project
            launchCompletion = completion
            didLaunch?()
        }
        func projectStateDidChange() { stateChanged?() }
        func projectReportError(_ error: NSError) { errors.append(error) }
        func projectWorkingDirectory(completion: @escaping (String?) -> Void) { completion(workingDirectory) }
    }

    private struct Fixture {
        let base: URL
        let main: String
        let linked: String
        let common: String
        let records: [[String: String]]
        let snapshot: iTermGitRepositorySnapshot
    }

    private func fixture() throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in ["repo/sub/one", "repo/sub/two", "linked/sub"] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        addTeardownBlock { try FileManager.default.removeItem(at: base) }
        func path(_ name: String) throws -> String {
            try iTermProjectCatalog.canonicalDirectory(base.appendingPathComponent(name).path).get()
        }
        let main = try path("repo")
        let linked = try path("linked")
        let common = main + "/.git"
        let records = [["identifier": UUID().uuidString, "rootDirectory": try path("repo/sub/one")],
                       ["identifier": UUID().uuidString, "rootDirectory": try path("repo/sub/two")],
                       ["identifier": UUID().uuidString, "rootDirectory": try path("linked/sub")]]
        let snapshot = iTermGitRepositorySnapshot(commonDirectory: common, rootDirectory: main,
            worktrees: [iTermGitWorktree(rootDirectory: main, branch: "main", head: "1111111", isMain: true),
                       iTermGitWorktree(rootDirectory: linked, branch: "feature", head: "2222222", isMain: false)])
        return Fixture(base: base, main: main, linked: linked, common: common, records: records, snapshot: snapshot)
    }

    private func catalog(_ fixture: Fixture, scanner: iTermGitWorktreeScanning, records: [[String: String]]? = nil) -> iTermProjectCatalog {
        let suite = "GitProjectIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(records ?? fixture.records, forKey: iTermProjectCatalog.defaultsKey)
        return iTermProjectCatalog(defaults: defaults, scanner: scanner)
    }

    private func ready(_ catalog: iTermProjectCatalog, predicate: @escaping () -> Bool) {
        let done = expectation(description: "catalog state published")
        var fulfilled = false
        let check = {
            if !fulfilled && predicate() { fulfilled = true; done.fulfill() }
        }
        let token = NotificationCenter.default.addObserver(forName: Notification.Name(iTermProjectCatalog.didChangeNotification),
                                                          object: catalog, queue: nil) { _ in check() }
        check()
        wait(for: [done], timeout: 5)
        NotificationCenter.default.removeObserver(token)
    }

    func testRepositoryDirectoryTargetsDisplayedRootRatherThanFirstBranch() throws {
        let main = iTermGitWorktree(rootDirectory: "/repo", branch: "main", head: "a", isMain: true, available: false)
        let linked = iTermGitWorktree(rootDirectory: "/linked", branch: "feature", head: "b", isMain: false)
        let repository = iTermGitRepositorySnapshot(commonDirectory: "/repo/.git", rootDirectory: "/repo", worktrees: [linked, main])
        XCTAssertEqual(repository.rootWorktree?.identifier, main.identifier)
        XCTAssertEqual(repository.rootWorktree?.available, false)
        let bare = iTermGitRepositorySnapshot(commonDirectory: "/bare", rootDirectory: "/bare", worktrees: [linked])
        XCTAssertNil(bare.rootWorktree)
    }
    func testNestedProjectsGroupByRepositoryAndKeepLegacyIdentifiers() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        XCTAssertEqual(catalog.projects.map(\.identifier), f.records.compactMap { $0["identifier"] })
        XCTAssertEqual(catalog.worktree(forProjectIdentifier: f.records[0]["identifier"]!)?.identifier, f.main)
        XCTAssertEqual(catalog.worktree(forProjectIdentifier: f.records[2]["identifier"]!)?.identifier, f.linked)
        let tree = iTermProjectSidebarTree(catalog: catalog)
        XCTAssertEqual(tree.roots.count, 1)
        XCTAssertEqual(tree.roots[0].kind, .repository)
        XCTAssertEqual(tree.roots[0].children.map { $0.worktree?.identifier }, [f.main, f.linked])
    }

    func testRealGitDiscoveryMatchesPhysicalCanonicalSubdirectory() throws {
        let f = try fixture()
        let executor = GitExecutor()
        for args in [["init", "-q", "-b", "main"], ["add", "fixture"],
                     ["-c", "user.name=iTerm Test", "-c", "user.email=iterm-test@example.invalid", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "fixture"]] {
            if args.first == "add" { try Data("fixture".utf8).write(to: URL(fileURLWithPath: f.main).appendingPathComponent("fixture")) }
            let result = executor.run(arguments: ["-c", "core.hooksPath=/dev/null"] + args, directory: f.main, timeout: 5)
            XCTAssertEqual(result.status, 0)
        }
        let physical = executor.run(arguments: ["rev-parse", "--show-toplevel"], directory: f.main, timeout: 5)
        let expectedRoot = String(decoding: physical.output.dropLast(), as: UTF8.self)
        let catalog = catalog(f, scanner: iTermGitWorktreeScanner(executor: executor), records: [f.records[0]])
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        XCTAssertEqual(catalog.worktree(forProjectIdentifier: f.records[0]["identifier"]!)?.rootDirectory, expectedRoot)
        XCTAssertEqual(catalog.projects.first?.identifier, f.records[0]["identifier"])
    }

    func testFailedRefreshKeepsPreviousWorktreesAndRecordsError() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        scanner.snapshot = nil
        scanner.error = NSError(domain: "fixture", code: 1)
        catalog.refreshRepositories([f.common])
        ready(catalog) { !catalog.isScanning && catalog.repositoryError(forIdentifier: f.common) != nil }
        XCTAssertEqual(catalog.repositories.first?.worktrees.map(\.identifier), [f.main, f.linked])
        XCTAssertEqual(catalog.worktree(forProjectIdentifier: f.records[2]["identifier"]!)?.rootDirectory, f.linked)
    }

    func testRemovedProjectCannotBeResurrectedByDelayedDiscovery() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot; scanner.delayed = true
        let catalog = catalog(f, scanner: scanner, records: [f.records[0]])
        let started = expectation(description: "scan pending")
        scanner.entered = { started.fulfill() }
        wait(for: [started], timeout: 5)
        catalog.removeProject(withIdentifier: f.records[0]["identifier"]!)
        scanner.deliver()
        XCTAssertTrue(catalog.projects.isEmpty)
        XCTAssertTrue(catalog.repositories.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.main))
    }

    func testMissingRememberedWorktreeKeepsOwnershipAndUnavailableRow() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        try FileManager.default.removeItem(atPath: f.linked)
        scanner.snapshot = iTermGitRepositorySnapshot(commonDirectory: f.common, rootDirectory: f.main,
                                                     worktrees: [f.snapshot.worktrees[0]])
        catalog.refreshRepositories([f.common])
        ready(catalog) { !catalog.isScanning && catalog.repositories.first?.worktrees.count == 1 }
        let remembered = catalog.worktree(forProjectIdentifier: f.records[2]["identifier"]!)
        XCTAssertEqual(remembered?.identifier, f.linked)
        XCTAssertEqual(remembered?.available, false)
        let tree = iTermProjectSidebarTree(catalog: catalog)
        XCTAssertEqual(tree.roots[0].children.count, 2)
        XCTAssertEqual(tree.roots[0].children.last?.worktree?.available, false)
    }

    func testWorktreeSwitchUsesRecentTabAcrossDifferentSubdirectoryProjects() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["old": f.records[0]["identifier"]!, "recent": f.records[1]["identifier"]!,
                                         "other": f.records[2]["identifier"]!]
        window.projectActiveTabIdentifier = "recent"
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        window.projectActiveTabIdentifier = "other"; controller.activeTabDidChange()
        controller.selectWorktree(f.snapshot.worktrees[0])
        XCTAssertEqual(window.projectActiveTabIdentifier, "recent")
        XCTAssertEqual(window.projectTabAssociations["recent"], f.records[1]["identifier"]!)
        XCTAssertEqual(controller.selectedRootDirectory, f.main)
        XCTAssertEqual(window.launches, 0)
    }

    func testFirstWorktreeActivationLaunchesExactlyOnceAtWorkspaceRoot() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner, records: [f.records[0]])
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["current": f.records[0]["identifier"]!]
        window.projectActiveTabIdentifier = "current"
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        let launched = expectation(description: "workspace shell requested")
        window.didLaunch = { launched.fulfill() }
        controller.selectWorktree(f.snapshot.worktrees[1])
        controller.selectWorktree(f.snapshot.worktrees[1])
        wait(for: [launched], timeout: 5)
        XCTAssertEqual(window.launches, 1)
        XCTAssertEqual(window.launchDirectory, f.linked)
        XCTAssertEqual(controller.selectedRootDirectory, f.linked)
        window.projectTabAssociations["new"] = try XCTUnwrap(window.launchProject).identifier
        window.launchCompletion?("new")
        XCTAssertEqual(window.projectActiveTabIdentifier, "new")
    }

    func testStaleWorktreeActivationDoesNotStealLaterSelection() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner, records: [f.records[0]])
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["current": f.records[0]["identifier"]!]
        window.projectActiveTabIdentifier = "current"
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        let launched = expectation(description: "new workspace launch pending")
        window.didLaunch = { launched.fulfill() }
        controller.selectWorktree(f.snapshot.worktrees[1])
        wait(for: [launched], timeout: 5)
        controller.selectWorktree(f.snapshot.worktrees[0])
        window.projectTabAssociations["new"] = try XCTUnwrap(window.launchProject).identifier
        window.launchCompletion?("new")
        XCTAssertEqual(window.projectActiveTabIdentifier, "current")
        XCTAssertEqual(controller.selectedRootDirectory, f.main)
    }

    func testAddCurrentDirectorySupersedesPendingWorkspaceWithoutNewTab() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner, records: [f.records[0]])
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["current": f.records[0]["identifier"]!]
        window.projectActiveTabIdentifier = "current"; window.workingDirectory = f.records[0]["rootDirectory"]
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        controller.selectWorktree(f.snapshot.worktrees[1])
        let done = expectation(description: "current cwd wins")
        controller.addCurrentDirectory { project, error in
            XCTAssertNil(error); XCTAssertEqual(project?.identifier, f.records[0]["identifier"]); done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(window.launches, 0)
        XCTAssertEqual(window.projectActiveTabIdentifier, "current")
        XCTAssertEqual(controller.selectedRootDirectory, f.main)
    }

    func testUnavailableWorkspaceDoesNotLaunchButExistingTerminalCanBeSelected() throws {
        let f = try fixture()
        let scanner = Scanner()
        scanner.snapshot = iTermGitRepositorySnapshot(commonDirectory: f.common, rootDirectory: f.main,
            worktrees: [f.snapshot.worktrees[0], iTermGitWorktree(rootDirectory: f.linked, branch: "feature", head: "2222222", isMain: false, available: false)])
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["current": f.records[0]["identifier"]!]
        window.projectActiveTabIdentifier = "current"
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        controller.selectWorktree(scanner.snapshot!.worktrees[1])
        XCTAssertEqual(window.launches, 0); XCTAssertEqual(window.errors.count, 1)
        window.projectTabAssociations["existing"] = f.records[2]["identifier"]!
        controller.selectWorktree(scanner.snapshot!.worktrees[1])
        XCTAssertEqual(window.projectActiveTabIdentifier, "existing")
        XCTAssertEqual(window.launches, 0)
        XCTAssertEqual(controller.selectedRootDirectory, f.linked)
    }

    func testBranchRefreshPreservesSelectionGenerationAndPublishedOldTree() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["current": f.records[0]["identifier"]!]; window.projectActiveTabIdentifier = "current"
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        let generation = controller.selectionGeneration
        let old = iTermProjectSidebarTree(catalog: catalog)
        scanner.snapshot = iTermGitRepositorySnapshot(commonDirectory: f.common, rootDirectory: f.main,
            worktrees: [iTermGitWorktree(rootDirectory: f.main, branch: "renamed", head: "3333333", isMain: true), f.snapshot.worktrees[1]])
        catalog.refreshRepositories([f.common])
        ready(catalog) { !catalog.isScanning && catalog.repositories.first?.worktrees.first?.branch == "renamed" }
        XCTAssertEqual(controller.selectionGeneration, generation)
        XCTAssertEqual(controller.selectedRootDirectory, f.main)
        XCTAssertEqual(window.projectActiveTabIdentifier, "current")
        XCTAssertTrue(old.roots[0].children[0].title.contains("main"))
        XCTAssertTrue(iTermProjectSidebarTree(catalog: catalog).roots[0].children[0].title.contains("renamed"))
    }

    func testWorktreeRecencyRestoresUsingOpaqueProjectKeys() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["old": f.records[0]["identifier"]!, "recent": f.records[1]["identifier"]!, "other": f.records[2]["identifier"]!]
        window.projectActiveTabIdentifier = "recent"
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        window.projectActiveTabIdentifier = "other"; controller.activeTabDidChange()
        let state = controller.restorableState()
        let remembered = try XCTUnwrap(state["worktreeRemembered"] as? [String: String])
        XCTAssertFalse(remembered.keys.contains(f.main))
        XCTAssertTrue(remembered.keys.allSatisfy { UUID(uuidString: $0) != nil })
        let restored = iTermProjectWindowController(catalog: catalog); restored.delegate = window
        restored.restore(from: state); restored.activeTabDidChange()
        restored.selectWorktree(f.snapshot.worktrees[0])
        XCTAssertEqual(window.projectActiveTabIdentifier, "recent")
        XCTAssertEqual(window.launches, 0)
    }

    func testRepositoryRemovalKeepsDirectoriesAndLiveTerminal() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["live": f.records[0]["identifier"]!]; window.projectActiveTabIdentifier = "live"
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        catalog.removeRepository(withIdentifier: f.common)
        XCTAssertTrue(catalog.projects.isEmpty); XCTAssertTrue(catalog.repositories.isEmpty)
        XCTAssertEqual(window.projectActiveTabIdentifier, "live")
        XCTAssertEqual(window.projectTabAssociations["live"], "")
        XCTAssertEqual(window.launches, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.main))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.linked))
    }

    func testInitialCwdInNestedWorktreeDoesNotReuseParentCheckoutProject() throws {
        let f = try fixture()
        let nested = f.main + "/.worktrees/feature"
        let cwd = nested + "/sub"
        try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        let mainIdentifier = UUID().uuidString
        let scanner = Scanner()
        scanner.snapshot = iTermGitRepositorySnapshot(commonDirectory: f.common, rootDirectory: f.main,
            worktrees: [f.snapshot.worktrees[0], iTermGitWorktree(rootDirectory: nested, branch: "nested", head: "2222222", isMain: false)])
        let catalog = catalog(f, scanner: scanner, records: [["identifier": mainIdentifier, "rootDirectory": f.main]])
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["fresh": ""]; window.projectActiveTabIdentifier = "fresh"; window.workingDirectory = cwd
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        let done = expectation(description: "initial cwd associated")
        var fulfilled = false
        window.stateChanged = {
            if !fulfilled && controller.selectedProjectIdentifier != nil { fulfilled = true; done.fulfill() }
        }
        controller.activeTabDidChange()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(controller.selectedWorktreeIdentifier, nested)
        XCTAssertEqual(controller.selectedRootDirectory, nested)
        XCTAssertNotEqual(window.projectTabAssociations["fresh"], mainIdentifier)
        XCTAssertEqual(window.workingDirectory, cwd)
        XCTAssertEqual(window.launches, 0)
    }

    func testLateAddFolderDiscoveryCannotOverrideNewerWorkspaceSelection() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner)
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        let window = Window()
        window.projectTabAssociations = ["main": f.records[0]["identifier"]!, "linked": f.records[2]["identifier"]!]
        window.projectActiveTabIdentifier = "main"
        let controller = iTermProjectWindowController(catalog: catalog); controller.delegate = window
        controller.activeTabDidChange()
        scanner.delayed = true
        let started = expectation(description: "folder discovery pending")
        scanner.entered = { started.fulfill() }
        let done = expectation(description: "superseded folder selection settled")
        controller.addDirectory(atPath: f.main + "/sub/two") { project, error in done.fulfill() }
        wait(for: [started], timeout: 5)
        controller.selectWorktree(f.snapshot.worktrees[1])
        scanner.deliver()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(window.projectActiveTabIdentifier, "linked")
        XCTAssertEqual(controller.selectedRootDirectory, f.linked)
        XCTAssertEqual(window.launches, 0)
    }

    func testRepositoryRemovalRejectsPendingUnclassifiedSubfolderDiscovery() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner, records: [f.records[0]])
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        scanner.delayed = true
        let started = expectation(description: "new input discovery pending")
        scanner.entered = { started.fulfill() }
        let added = expectation(description: "new directory registered")
        catalog.addDirectory(atPath: f.records[1]["rootDirectory"]!) { _, _ in added.fulfill() }
        wait(for: [added, started], timeout: 5)
        catalog.removeRepository(withIdentifier: f.common)
        scanner.deliver()
        XCTAssertTrue(catalog.repositories.isEmpty)
        XCTAssertTrue(catalog.projects.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.main))
    }

    func testConcurrentWorkingDirectoryAdmissionsReuseOneProjectIdentifier() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot; scanner.delayed = true
        let catalog = catalog(f, scanner: scanner, records: [])
        let entered = expectation(description: "both cwd scans pending"); entered.expectedFulfillmentCount = 2
        scanner.entered = { entered.fulfill() }
        let done = expectation(description: "both cwd admissions settled"); done.expectedFulfillmentCount = 2
        var identifiers = [String]()
        for _ in 0..<2 {
            catalog.addWorkingDirectory(atPath: f.records[0]["rootDirectory"]!, shouldAdd: { true }) { project, error in
                XCTAssertNil(error)
                if let project { identifiers.append(project.identifier) }
                done.fulfill()
            }
        }
        wait(for: [entered], timeout: 5)
        scanner.entered = nil; scanner.deliver()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(catalog.projects.count, 1)
        XCTAssertEqual(identifiers.count, 2)
        XCTAssertEqual(Set(identifiers).count, 1)
    }

    func testWorkingDirectoryCommitRechecksRepositoryRemovalAfterGitScan() throws {
        let f = try fixture()
        let scanner = Scanner(); scanner.snapshot = f.snapshot
        let catalog = catalog(f, scanner: scanner, records: [f.records[0]])
        ready(catalog) { !catalog.isScanning && catalog.repositories.count == 1 }
        scanner.delayed = true
        let entered = expectation(description: "cwd Git scan pending")
        scanner.entered = { entered.fulfill() }
        let done = expectation(description: "cwd registration cancelled")
        catalog.addWorkingDirectory(atPath: f.linked + "/sub", shouldAdd: { true }) { project, error in
            XCTAssertNil(project)
            XCTAssertEqual(error?.code, NSUserCancelledError)
            done.fulfill()
        }
        wait(for: [entered], timeout: 5)
        scanner.entered = nil; scanner.deliver()
        catalog.removeRepository(withIdentifier: f.common)
        wait(for: [done], timeout: 5)
        XCTAssertTrue(catalog.projects.isEmpty)
        XCTAssertTrue(catalog.repositories.isEmpty)
    }
}

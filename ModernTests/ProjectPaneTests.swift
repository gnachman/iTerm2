import XCTest
@testable import iTerm2SharedARC

final class ProjectPaneTests: XCTestCase {
    private final class Window: NSObject, iTermProjectWindowDelegate {
        var projectTabAssociations = [String: String]()
        var projectActiveTabIdentifier: String? = "mixed"
        var projectSessionContexts = [iTermProjectSessionContext]()
        var projectActiveSessionIdentifier: String? = "a"
        var selected = [String]()
        var legacyLaunches = 0
        var requests = [(project: String, directory: String, style: iTermOpenStyle, target: String?, completion: (iTermProjectTerminalLaunchResult?) -> Void)]()
        var didLaunch: (() -> Void)?
        var canLaunch = true
        var errors = [NSError]()
        var directory: String?
        var directoryCallbacks = [(String?) -> Void]()
        var delayDirectory = false
        var stateChanged: (() -> Void)?
        func projectSelectTab(_ identifier: String) { projectActiveTabIdentifier = identifier }
        func projectAssign(_ project: String?, toTab identifier: String) { projectTabAssociations[identifier] = project ?? "" }
        func projectSelectSession(_ identifier: String) {
            selected.append(identifier)
            projectActiveSessionIdentifier = identifier
            projectActiveTabIdentifier = projectSessionContexts.first { $0.sessionIdentifier == identifier }?.tabIdentifier
        }
        func projectAssignSession(_ project: String?, toSession identifier: String) {
            projectSessionContexts = projectSessionContexts.map {
                $0.sessionIdentifier == identifier ? iTermProjectSessionContext(sessionIdentifier: identifier, tabIdentifier: $0.tabIdentifier, projectIdentifier: project ?? "", exited: $0.exited) : $0
            }
        }
        func projectCanLaunch(style: iTermOpenStyle) -> Bool { canLaunch }
        func projectLaunch(_ project: iTermProjectDirectory, directory: String, completion: @escaping (String?) -> Void) { legacyLaunches += 1 }
        func projectLaunch(_ project: iTermProjectDirectory, directory: String, style: iTermOpenStyle, targetSessionIdentifier: String?, completion: @escaping (iTermProjectTerminalLaunchResult?) -> Void) {
            requests.append((project.identifier, directory, style, targetSessionIdentifier, completion))
            didLaunch?()
        }
        func projectStateDidChange() { stateChanged?() }
        func projectReportError(_ error: NSError) { errors.append(error) }
        func projectWorkingDirectory(completion: @escaping (String?) -> Void) {
            if delayDirectory { directoryCallbacks.append(completion) } else { completion(directory) }
        }
    }

    private func setup(unowned: Bool = false) -> (iTermProjectCatalog, Window, iTermProjectWindowController) {
        let name = "ProjectPaneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set([["identifier": "11111111-1111-1111-1111-111111111111", "rootDirectory": "/tmp"],
                      ["identifier": "22222222-2222-2222-2222-222222222222", "rootDirectory": "/var"]], forKey: iTermProjectCatalog.defaultsKey)
        let catalog = iTermProjectCatalog(defaults: defaults)
        let window = Window()
        window.projectTabAssociations = ["mixed": catalog.projects[0].identifier]
        window.projectSessionContexts = [context("a", unowned ? "" : catalog.projects[0].identifier), context("b", catalog.projects[1].identifier)]
        let controller = iTermProjectWindowController(catalog: catalog)
        controller.delegate = window
        controller.activeTabDidChange()
        return (catalog, window, controller)
    }
    private func context(_ id: String, _ owner: String?, tab: String = "mixed", exited: Bool = false) -> iTermProjectSessionContext {
        iTermProjectSessionContext(sessionIdentifier: id, tabIdentifier: tab, projectIdentifier: owner, exited: exited)
    }

    func testActivePaneOwnerWinsOverMixedTabAndPinsCorrectRoot() {
        let (catalog, window, controller) = setup()
        window.projectActiveSessionIdentifier = "b"
        controller.activeSessionDidChange()
        XCTAssertEqual(controller.selectedProjectIdentifier, catalog.projects[1].identifier)
        XCTAssertEqual(controller.selectedRootDirectory, "/var")
    }
    func testSelectingWorkspaceReusesPaneWithoutIncreasingTabs() {
        let (catalog, window, controller) = setup()
        controller.selectProject(catalog.projects[1])
        XCTAssertEqual(window.selected, ["b"])
        XCTAssertEqual(window.projectActiveTabIdentifier, "mixed")
        XCTAssertEqual(window.projectTabAssociations.count, 1)
        XCTAssertTrue(window.requests.isEmpty)
        XCTAssertEqual(window.legacyLaunches, 0)
    }
    func testExplicitModesAlwaysCreateAndPassPathAndTarget() {
        for style in [iTermOpenStyle.tab, .verticalSplit, .horizontalSplit, .window] {
            let (catalog, window, controller) = setup()
            controller.openProject(catalog.projects[1], style: style)
            XCTAssertEqual(window.requests.count, 1)
            guard let request = window.requests.first else { continue }
            XCTAssertEqual(request.style, style)
            XCTAssertEqual(request.directory, "/var")
            XCTAssertEqual(request.project, catalog.projects[1].identifier)
            XCTAssertEqual(request.target, "a")
            XCTAssertEqual(controller.selectedProjectIdentifier, catalog.projects[0].identifier)
            window.projectSessionContexts.append(context("created", catalog.projects[1].identifier, tab: "new"))
            request.completion(iTermProjectTerminalLaunchResult(sessionIdentifier: "created", tabIdentifier: "new", windowIdentifier: "destination"))
            XCTAssertEqual(window.selected, style == .window ? [] : ["created"])
        }
    }
    func testFileTreeExplicitCreationUsesSelectedWorkspaceAndRequestedDirectory() {
        let (catalog, window, controller) = setup()
        controller.openTerminal(inDirectory: "/tmp/sub", style: .horizontalSplit)
        XCTAssertEqual(window.requests.first?.directory, "/tmp/sub")
        XCTAssertEqual(window.requests.first?.project, catalog.projects[0].identifier)
        XCTAssertEqual(window.requests.first?.target, "a")
    }
    func testSingleSelectionOnlyReusesAndDoubleSelectionOpensUnopenedFolder() throws {
        let (catalog, window, controller) = setup()
        let project = catalog.projects[1]
        window.projectSessionContexts.removeLast()
        controller.selectProject(project, openIfNeeded: false)
        XCTAssertTrue(window.requests.isEmpty)
        XCTAssertEqual(controller.selectedProjectIdentifier, project.identifier)
        XCTAssertEqual(controller.selectedRootDirectory, project.rootDirectory)
        XCTAssertTrue(window.selected.isEmpty)
        XCTAssertEqual(window.projectActiveSessionIdentifier, "a")
        controller.selectProject(project, openIfNeeded: true)
        let request = try XCTUnwrap(window.requests.first)
        XCTAssertEqual(request.style, .tab)
        window.projectSessionContexts.append(context("opened", project.identifier))
        request.completion(.init(sessionIdentifier: "opened", tabIdentifier: "mixed", windowIdentifier: "w"))
        controller.selectProject(project, openIfNeeded: false)
        controller.selectProject(project, openIfNeeded: true)
        XCTAssertEqual(window.projectActiveSessionIdentifier, "opened")
        XCTAssertEqual(window.requests.count, 1)
    }
    func testSingleUnopenedSelectionCancelsEarlierPendingLaunch() {
        let (catalog, window, controller) = setup()
        window.projectSessionContexts.removeLast()
        controller.openProject(catalog.projects[0], style: .tab)
        let generation = controller.selectionGeneration
        controller.selectProject(catalog.projects[1], openIfNeeded: false)
        XCTAssertGreaterThan(controller.selectionGeneration, generation)
        window.projectSessionContexts.append(context("late", catalog.projects[0].identifier))
        window.requests[0].completion(.init(sessionIdentifier: "late", tabIdentifier: "mixed", windowIdentifier: "w"))
        XCTAssertTrue(window.selected.isEmpty)
        XCTAssertEqual(window.requests.count, 1)
    }
    func testUnavailableSplitReportsErrorWithoutLegacyFallback() {
        let (_, window, controller) = setup()
        window.canLaunch = false
        controller.openTerminal(inDirectory: "/tmp", style: .verticalSplit)
        XCTAssertTrue(window.requests.isEmpty)
        XCTAssertEqual(window.legacyLaunches, 0)
        XCTAssertEqual(window.errors.count, 1)
    }
    func testNewIntentCancelsEarlierCreationResult() {
        let (catalog, window, controller) = setup()
        controller.openProject(catalog.projects[0], style: .tab)
        controller.openProject(catalog.projects[1], style: .verticalSplit)
        window.projectSessionContexts += [context("old", catalog.projects[0].identifier), context("new", catalog.projects[1].identifier)]
        window.requests[0].completion(.init(sessionIdentifier: "old", tabIdentifier: "mixed", windowIdentifier: "w"))
        XCTAssertTrue(window.selected.isEmpty)
        window.requests[1].completion(.init(sessionIdentifier: "new", tabIdentifier: "mixed", windowIdentifier: "w"))
        XCTAssertEqual(window.selected, ["new"])
    }
    func testClosedMovedOrExitedTargetRejectsLateCreation() {
        for replacement in [[], [context("a", "11111111-1111-1111-1111-111111111111", tab: "moved")],
                            [context("a", "11111111-1111-1111-1111-111111111111", exited: true)]] {
            let (catalog, window, controller) = setup()
            controller.openProject(catalog.projects[1], style: .tab)
            let generation = controller.selectionGeneration
            window.projectSessionContexts = replacement
            controller.tabsDidChange()
            XCTAssertFalse(controller.isLaunchRequestCurrent(targetSessionIdentifier: "a", generation: generation))
            window.requests[0].completion(.init(sessionIdentifier: "late", tabIdentifier: "new", windowIdentifier: "w"))
            XCTAssertTrue(window.selected.isEmpty)
        }
    }
    func testPaneActivationCancelsPendingLaunchResult() {
        let (catalog, window, controller) = setup()
        controller.openProject(catalog.projects[0], style: .tab)
        window.projectActiveSessionIdentifier = "b"
        controller.activeSessionDidChange()
        window.requests[0].completion(.init(sessionIdentifier: "late", tabIdentifier: "new", windowIdentifier: "w"))
        XCTAssertTrue(window.selected.isEmpty)
        XCTAssertEqual(controller.selectedRootDirectory, "/var")
    }
    func testAddCurrentDirectoryOnlyReassignsActivePane() {
        let (catalog, window, controller) = setup()
        window.directory = "/var"
        let done = expectation(description: "assigned active pane")
        controller.addCurrentDirectory { project, error in
            XCTAssertNil(error)
            XCTAssertEqual(project?.identifier, catalog.projects[1].identifier)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(window.projectSessionContexts.first?.projectIdentifier, catalog.projects[1].identifier)
        XCTAssertEqual(window.projectTabAssociations["mixed"], catalog.projects[0].identifier)
        XCTAssertEqual(controller.selectedRootDirectory, "/var")
        XCTAssertTrue(window.selected.isEmpty)
        XCTAssertTrue(window.requests.isEmpty)
    }
    func testCwdActivationRaceCannotAssociateAnotherPane() {
        let (catalog, window, controller) = setup(unowned: true)
        window.delayDirectory = true
        controller.activeSessionDidChange()
        XCTAssertEqual(window.directoryCallbacks.count, 1)
        window.projectActiveSessionIdentifier = "b"
        controller.activeSessionDidChange()
        window.directoryCallbacks[0]("/tmp")
        XCTAssertEqual(window.projectSessionContexts.first?.projectIdentifier, "")
        XCTAssertEqual(controller.selectedProjectIdentifier, catalog.projects[1].identifier)
    }
    func testInitialCwdAssociatesUnownedPaneWithoutTouchingSiblingOrTab() {
        let (catalog, window, controller) = setup(unowned: true)
        window.directory = "/tmp"
        let done = expectation(description: "initial cwd")
        var fulfilled = false
        window.stateChanged = {
            if !fulfilled && controller.selectedProjectIdentifier == catalog.projects[0].identifier { fulfilled = true; done.fulfill() }
        }
        controller.activeSessionDidChange()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(window.projectSessionContexts.first?.projectIdentifier, catalog.projects[0].identifier)
        XCTAssertEqual(window.projectSessionContexts.last?.projectIdentifier, catalog.projects[1].identifier)
        XCTAssertTrue(window.selected.isEmpty)
    }
    func testRemovalClearsSessionOwnersAndMetadataRefreshKeepsSelectionGeneration() {
        let (catalog, window, controller) = setup()
        let generation = controller.selectionGeneration
        NotificationCenter.default.post(name: .init(iTermProjectCatalog.didChangeNotification), object: catalog)
        XCTAssertEqual(controller.selectionGeneration, generation)
        catalog.removeProject(withIdentifier: catalog.projects[0].identifier)
        XCTAssertEqual(window.projectSessionContexts.first?.projectIdentifier, "")
        XCTAssertNil(controller.selectedProjectIdentifier)
    }
    func testRememberedSessionMapIsDistinctAndPrunesClosedSessions() {
        let (catalog, window, controller) = setup()
        let state = controller.restorableState()
        XCTAssertEqual((state["sessionRemembered"] as? [String: String])?[catalog.projects[0].identifier], "a")
        XCTAssertEqual((state["remembered"] as? [String: String])?.count, 0)
        window.projectSessionContexts.removeFirst()
        controller.tabsDidChange()
        XCTAssertEqual((controller.restorableState()["sessionRemembered"] as? [String: String])?.count, 0)
    }
    func testRemovedProjectCannotBeOpenedFromCachedContext() {
        let (catalog, window, controller) = setup()
        let project = catalog.projects[0]
        catalog.removeProject(withIdentifier: project.identifier)
        controller.openProject(project, style: .tab)
        XCTAssertTrue(window.requests.isEmpty)
        XCTAssertEqual(catalog.projects.count, 1)
    }
    func testDuplicatePaneNotificationsKeepGenerationButOwnerChangesRefreshSelection() {
        let (catalog, window, controller) = setup()
        let generation = controller.selectionGeneration
        controller.activeSessionDidChange()
        controller.activeTabDidChange()
        XCTAssertEqual(controller.selectionGeneration, generation)
        window.projectAssignSession(catalog.projects[1].identifier, toSession: "a")
        controller.activeSessionDidChange()
        XCTAssertGreaterThan(controller.selectionGeneration, generation)
        XCTAssertEqual(controller.selectedRootDirectory, "/var")
    }
    func testNormalWorkspaceLaunchStillDeduplicatesAndRejectsMovedSourceAtNativeBoundary() {
        let (catalog, window, controller) = setup()
        window.projectSessionContexts.removeLast()
        controller.selectProject(catalog.projects[1])
        controller.selectProject(catalog.projects[1])
        XCTAssertEqual(window.requests.count, 1)
        let generation = controller.selectionGeneration
        window.projectSessionContexts = [context("a", catalog.projects[0].identifier, tab: "moved")]
        XCTAssertFalse(controller.isLaunchRequestCurrent(targetSessionIdentifier: "a", generation: generation))
    }
    func testOwnNativeCreationMayActivateResultBeforeCompletion() {
        let (catalog, window, controller) = setup()
        controller.openProject(catalog.projects[1], style: .tab)
        window.projectSessionContexts.append(context("created", catalog.projects[1].identifier, tab: "new"))
        // Native creation keeps controller activation notifications suspended until its completion.
        window.projectActiveSessionIdentifier = "created"
        window.projectActiveTabIdentifier = "new"
        window.requests[0].completion(.init(sessionIdentifier: "created", tabIdentifier: "new", windowIdentifier: "w"))
        XCTAssertEqual(controller.selectedProjectIdentifier, catalog.projects[1].identifier)
        XCTAssertEqual(window.selected, ["created"])
    }

    private final class Scanner: iTermGitWorktreeScanning {
        var snapshot: iTermGitRepositorySnapshot?
        func scan(directory: String, completion: @escaping (iTermGitRepositorySnapshot?, NSError?) -> Void) {
            completion(snapshot, nil)
        }
    }
    private func gitSetup() throws -> (iTermProjectCatalog, Window, iTermProjectWindowController, Scanner, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in ["main/one", "main/two", "linked/sub", "barrier"] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        addTeardownBlock { try FileManager.default.removeItem(at: base) }
        let canonical = URL(fileURLWithPath: try iTermProjectCatalog.canonicalDirectory(base.path).get())
        let main = canonical.appendingPathComponent("main").path
        let linked = canonical.appendingPathComponent("linked").path
        let scanner = Scanner()
        scanner.snapshot = .init(commonDirectory: main + "/.git", rootDirectory: main, worktrees: [
            .init(rootDirectory: main, branch: "main", head: "a", isMain: true),
            .init(rootDirectory: linked, branch: "feature", head: "b", isMain: false)])
        let name = "ProjectPaneGitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set(["main/one", "main/two", "linked/sub"].map {
            ["identifier": UUID().uuidString, "rootDirectory": canonical.appendingPathComponent($0).path,
             "gitCommonDirectory": main + "/.git", "gitRepositoryRoot": main,
             "gitWorktreeDirectory": $0.hasPrefix("main") ? main : linked]
        }, forKey: iTermProjectCatalog.defaultsKey)
        let catalog = iTermProjectCatalog(defaults: defaults, scanner: scanner)
        let ready = expectation(description: "worktree metadata ready")
        catalog.refreshProject(withIdentifier: catalog.projects[0].identifier) { _ in ready.fulfill() }
        wait(for: [ready], timeout: 5)
        let window = Window()
        window.projectSessionContexts = zip(["a", "b", "c"], catalog.projects).map { context($0.0, $0.1.identifier) }
        window.projectTabAssociations = ["mixed": catalog.projects[0].identifier]
        let controller = iTermProjectWindowController(catalog: catalog)
        controller.delegate = window
        controller.activeSessionDidChange()
        return (catalog, window, controller, scanner, canonical)
    }
    func testWorktreeClickUsesRecentPaneAcrossSubdirectoryProjectsAndRestoresOpaqueMap() throws {
        let (catalog, window, controller, _, _) = try gitSetup()
        let worktree = try XCTUnwrap(catalog.worktree(forProjectIdentifier: catalog.projects[0].identifier))
        window.projectActiveSessionIdentifier = "b"
        controller.activeSessionDidChange()
        window.projectActiveSessionIdentifier = "c"
        controller.activeSessionDidChange()
        controller.selectWorktree(worktree)
        XCTAssertEqual(window.selected, ["b"])
        XCTAssertEqual(controller.selectedRootDirectory, worktree.rootDirectory)
        XCTAssertEqual(window.projectTabAssociations.count, 1)
        XCTAssertTrue(window.requests.isEmpty)
        let state = controller.restorableState()
        let map = try XCTUnwrap(state["worktreeSessionRemembered"] as? [String: String])
        XCTAssertEqual(map[catalog.projects[0].identifier], "b")
        XCTAssertFalse(map.keys.contains { $0.hasPrefix("/") })
        let restored = iTermProjectWindowController(catalog: catalog)
        restored.delegate = window
        restored.restore(from: state)
        window.projectActiveSessionIdentifier = "a"
        restored.selectWorktree(worktree)
        XCTAssertEqual(window.projectActiveSessionIdentifier, "b")
    }
    func testWorktreeWithoutLivePaneLaunchesDefaultTabWithOwningRootProject() throws {
        let (catalog, window, controller, _, _) = try gitSetup()
        let worktree = try XCTUnwrap(catalog.worktree(forProjectIdentifier: catalog.projects[2].identifier))
        window.projectSessionContexts.removeLast()
        let launch = expectation(description: "default worktree launch")
        window.didLaunch = { launch.fulfill() }
        controller.selectWorktree(worktree)
        wait(for: [launch], timeout: 5)
        let request = try XCTUnwrap(window.requests.first)
        XCTAssertEqual(request.style, .tab)
        XCTAssertEqual(request.target, "a")
        XCTAssertEqual(request.directory, worktree.rootDirectory)
        XCTAssertEqual(catalog.project(withIdentifier: request.project)?.rootDirectory, worktree.rootDirectory)
        window.projectSessionContexts.append(context("linked", request.project, tab: "new"))
        request.completion(.init(sessionIdentifier: "linked", tabIdentifier: "new", windowIdentifier: "w"))
        XCTAssertEqual(window.selected, ["linked"])
    }
    func testUnopenedWorktreeRequiresDoubleSelectionAndReusesCreatedPane() throws {
        let (catalog, window, controller, _, _) = try gitSetup()
        let repository = try XCTUnwrap(catalog.repositories.first)
        let main = try XCTUnwrap(repository.rootWorktree)
        window.projectSessionContexts.removeFirst(2)
        window.projectActiveSessionIdentifier = "c"
        controller.activeSessionDidChange()
        let projectCount = catalog.projects.count
        controller.selectWorktree(main, openIfNeeded: false)
        XCTAssertTrue(window.requests.isEmpty)
        XCTAssertEqual(controller.selectedRootDirectory, main.rootDirectory)
        XCTAssertEqual(catalog.projects.count, projectCount)
        XCTAssertEqual(window.projectActiveSessionIdentifier, "c")
        let launch = expectation(description: "double-click worktree launch")
        window.didLaunch = { launch.fulfill() }
        controller.selectWorktree(main, openIfNeeded: true)
        controller.selectWorktree(main, openIfNeeded: true)
        wait(for: [launch], timeout: 5)
        let request = try XCTUnwrap(window.requests.first)
        XCTAssertEqual(request.directory, main.rootDirectory)
        XCTAssertEqual(request.style, .tab)
        window.projectSessionContexts.append(context("opened", request.project, tab: "new"))
        request.completion(.init(sessionIdentifier: "opened", tabIdentifier: "new", windowIdentifier: "w"))
        controller.selectWorktree(main, openIfNeeded: false)
        controller.selectWorktree(main, openIfNeeded: true)
        XCTAssertEqual(window.projectActiveSessionIdentifier, "opened")
        XCTAssertEqual(window.requests.count, 1)
    }
    func testRightTreeMenuOpensClickedDirectoryAfterSingleUnopenedWorktreeSelection() throws {
        let (catalog, window, controller, _, base) = try gitSetup()
        let main = try XCTUnwrap(catalog.repositories.first?.rootWorktree)
        window.projectSessionContexts.removeFirst(2)
        window.projectActiveSessionIdentifier = "c"
        controller.activeSessionDidChange()
        controller.selectWorktree(main, openIfNeeded: false)
        XCTAssertNil(controller.selectedProjectIdentifier)
        let directory = base.appendingPathComponent("main/two").path
        let launch = expectation(description: "right-tree launch from worktree preview")
        window.didLaunch = { launch.fulfill() }
        controller.openTerminal(inDirectory: directory, style: .verticalSplit)
        wait(for: [launch], timeout: 5)
        let request = try XCTUnwrap(window.requests.first)
        XCTAssertEqual(request.directory, directory)
        XCTAssertEqual(request.style, .verticalSplit)
        XCTAssertEqual(request.target, "c")
        XCTAssertEqual(catalog.project(withIdentifier: request.project)?.rootDirectory, main.rootDirectory)
        XCTAssertTrue(window.selected.isEmpty)
    }
    func testRepositoryDirectorySingleSelectionUsesRecentRootPane() throws {
        let (catalog, window, controller, _, _) = try gitSetup()
        let repository = try XCTUnwrap(catalog.repositories.first)
        window.projectActiveSessionIdentifier = "b"
        controller.activeSessionDidChange()
        window.projectActiveSessionIdentifier = "c"
        controller.activeSessionDidChange()
        controller.selectRepository(repository, openIfNeeded: false)
        XCTAssertEqual(window.projectActiveSessionIdentifier, "b")
        controller.selectRepository(repository, openIfNeeded: true)
        XCTAssertTrue(window.requests.isEmpty)
    }
    func testUnopenedRepositoryDirectorySingleSelectionDoesNotCreateTerminal() throws {
        let (catalog, window, controller, _, _) = try gitSetup()
        let repository = try XCTUnwrap(catalog.repositories.first)
        window.projectSessionContexts.removeFirst(2)
        window.projectActiveSessionIdentifier = "c"
        controller.activeSessionDidChange()
        controller.selectRepository(repository, openIfNeeded: false)
        XCTAssertTrue(window.requests.isEmpty)
        XCTAssertTrue(window.selected.isEmpty)
        let launch = expectation(description: "double-click repository launch")
        window.didLaunch = { launch.fulfill() }
        controller.selectRepository(repository, openIfNeeded: true)
        wait(for: [launch], timeout: 5)
        XCTAssertEqual(window.requests.first?.directory, repository.rootDirectory)
        XCTAssertEqual(window.requests.first?.style, .tab)
    }
    func testRepositoryDirectoryMenuLaunchesItsRootFromAnotherActiveWorktreeInEachMode() throws {
        for style in [iTermOpenStyle.tab, .verticalSplit, .horizontalSplit, .window] {
            let (catalog, window, controller, _, _) = try gitSetup()
            let repository = try XCTUnwrap(iTermProjectSidebarTree(catalog: catalog).roots.first?.repository)
            window.projectActiveSessionIdentifier = "c"
            controller.activeSessionDidChange()
            let source = controller.selectedProjectIdentifier
            let launch = expectation(description: "repository root launch")
            window.didLaunch = { launch.fulfill() }
            controller.openRepository(repository, style: style)
            wait(for: [launch], timeout: 5)
            let request = try XCTUnwrap(window.requests.first)
            XCTAssertEqual(request.directory, repository.rootDirectory)
            XCTAssertEqual(catalog.project(withIdentifier: request.project)?.rootDirectory, repository.rootDirectory)
            XCTAssertEqual(request.style, style)
            XCTAssertEqual(request.target, "c")
            XCTAssertEqual(controller.selectedProjectIdentifier, source)
            XCTAssertTrue(window.selected.isEmpty)
        }
    }
    func testRepositoryDirectoryWithoutRootWorktreeStillOpensDisplayedDirectory() throws {
        let (catalog, window, controller, scanner, _) = try gitSetup()
        let old = try XCTUnwrap(scanner.snapshot)
        scanner.snapshot = .init(commonDirectory: old.commonDirectory, rootDirectory: old.rootDirectory,
                                 worktrees: old.worktrees.filter { !$0.isMain })
        let refreshed = expectation(description: "rootless repository refreshed")
        catalog.refreshProject(withIdentifier: catalog.projects[2].identifier) { _ in refreshed.fulfill() }
        wait(for: [refreshed], timeout: 5)
        let repository = try XCTUnwrap(catalog.repositories.first)
        XCTAssertNil(repository.rootWorktree)
        window.projectActiveSessionIdentifier = "c"
        controller.activeSessionDidChange()
        let launch = expectation(description: "repository directory launch")
        window.didLaunch = { launch.fulfill() }
        controller.openRepository(repository, style: .tab)
        wait(for: [launch], timeout: 5)
        XCTAssertEqual(window.requests.first?.directory, repository.rootDirectory)
        XCTAssertEqual(window.requests.first?.target, "c")
    }
    func testRepositoryDirectoryPreparationCancelsOnPaneChangeOrRepositoryRemoval() throws {
        for remove in [false, true] {
            let (catalog, window, controller, _, base) = try gitSetup()
            let repository = try XCTUnwrap(catalog.repositories.first)
            controller.openRepository(repository, style: .horizontalSplit)
            if remove { catalog.removeRepository(withIdentifier: repository.identifier) }
            else {
                window.projectActiveSessionIdentifier = "c"
                controller.activeSessionDidChange()
            }
            let drained = expectation(description: "repository validation drained")
            catalog.addDirectory(atPath: base.appendingPathComponent("barrier").path) { _, _ in drained.fulfill() }
            wait(for: [drained], timeout: 5)
            XCTAssertTrue(window.requests.isEmpty)
            XCTAssertNil(catalog.projects.first { $0.rootDirectory == repository.rootDirectory })
        }
    }
    func testRemovedRepositoryCannotBeReopenedFromDirectoryMenu() throws {
        let (catalog, window, controller, _, _) = try gitSetup()
        let repository = try XCTUnwrap(catalog.repositories.first)
        catalog.removeRepository(withIdentifier: repository.identifier)
        for style in [iTermOpenStyle.tab, .verticalSplit, .horizontalSplit, .window] {
            controller.openRepository(repository, style: style)
        }
        XCTAssertTrue(window.requests.isEmpty)
        XCTAssertTrue(catalog.projects.isEmpty)
    }
    func testExplicitWorktreeLaunchKeepsSourceSelectionAndPassesEachMode() throws {
        for style in [iTermOpenStyle.tab, .verticalSplit, .horizontalSplit, .window] {
            let (catalog, window, controller, _, _) = try gitSetup()
            let source = catalog.projects[0].identifier
            let worktree = try XCTUnwrap(catalog.worktree(forProjectIdentifier: catalog.projects[2].identifier))
            let launch = expectation(description: "explicit worktree launch")
            window.didLaunch = { launch.fulfill() }
            controller.openWorktree(worktree, style: style)
            XCTAssertEqual(controller.selectedProjectIdentifier, source)
            wait(for: [launch], timeout: 5)
            XCTAssertEqual(window.requests.first?.style, style)
            XCTAssertEqual(window.requests.first?.target, "a")
            XCTAssertEqual(window.requests.first?.directory, worktree.rootDirectory)
            XCTAssertEqual(controller.selectedProjectIdentifier, source)
            XCTAssertTrue(window.selected.isEmpty)
        }
    }
    func testWorktreePreparationCancelsBeforeCreationOnNewIntentClosedTargetOrRemoval() throws {
        for action in ["new-intent", "closed-target", "removed-repository", "moved-target"] {
            let (catalog, window, controller, _, base) = try gitSetup()
            let worktree = try XCTUnwrap(catalog.worktree(forProjectIdentifier: catalog.projects[2].identifier))
            controller.openWorktree(worktree, style: .horizontalSplit)
            switch action {
            case "new-intent": controller.selectProject(catalog.projects[0])
            case "closed-target": window.projectSessionContexts.removeFirst(); controller.tabsDidChange()
            case "moved-target": window.projectSessionContexts[0] = context("a", catalog.projects[0].identifier, tab: "moved")
            default: catalog.removeRepository(withIdentifier: catalog.projects[0].gitCommonDirectory!)
            }
            // Both operations use the catalog's serial validation queue. This completion fences the
            // earlier worktree validation without relying on timing or sleeps.
            let drained = expectation(description: "validation queue drained")
            catalog.addDirectory(atPath: base.appendingPathComponent("barrier").path) { _, _ in drained.fulfill() }
            wait(for: [drained], timeout: 5)
            XCTAssertTrue(window.requests.isEmpty, action)
            XCTAssertNil(catalog.projects.first { $0.rootDirectory == worktree.rootDirectory }, action)
        }
    }
    func testUnavailableAndRemovedCachedWorktreesNeverCreateTerminals() throws {
        let (catalog, window, controller, scanner, _) = try gitSetup()
        let worktree = try XCTUnwrap(catalog.worktree(forProjectIdentifier: catalog.projects[2].identifier))
        let snapshot = try XCTUnwrap(scanner.snapshot)
        scanner.snapshot = .init(commonDirectory: snapshot.commonDirectory, rootDirectory: snapshot.rootDirectory,
            worktrees: [.init(rootDirectory: worktree.rootDirectory, branch: "feature", head: "b", isMain: false, available: false)])
        let refreshed = expectation(description: "unavailable metadata")
        catalog.refreshProject(withIdentifier: catalog.projects[2].identifier) { _ in refreshed.fulfill() }
        wait(for: [refreshed], timeout: 5)
        controller.openWorktree(worktree, style: .tab)
        XCTAssertEqual(window.errors.last?.code, NSFileReadNoSuchFileError)
        XCTAssertTrue(window.requests.isEmpty)
        catalog.removeRepository(withIdentifier: snapshot.commonDirectory)
        controller.openWorktree(worktree, style: .tab)
        XCTAssertTrue(window.requests.isEmpty)
        XCTAssertTrue(catalog.projects.isEmpty)
    }

    func testRemovingPendingWorkspaceSelectionReturnsToLivePaneOwner() {
        let (catalog, window, controller) = setup()
        let source = catalog.projects[0].identifier
        let removed = catalog.projects[1].identifier
        window.projectSessionContexts.removeLast()
        controller.selectProject(catalog.projects[1])
        catalog.removeProject(withIdentifier: removed)
        XCTAssertEqual(controller.selectedProjectIdentifier, source)
        window.requests[0].completion(nil)
        XCTAssertEqual(controller.selectedProjectIdentifier, source)
    }
    func testUnavailableNewIntentStillCancelsEarlierCreationResult() {
        let (catalog, window, controller) = setup()
        controller.openProject(catalog.projects[0], style: .tab)
        window.canLaunch = false
        controller.openProject(catalog.projects[1], style: .verticalSplit)
        window.projectSessionContexts.append(context("late", catalog.projects[0].identifier))
        window.requests[0].completion(.init(sessionIdentifier: "late", tabIdentifier: "mixed", windowIdentifier: "w"))
        XCTAssertTrue(window.selected.isEmpty)
    }
    func testInitialCwdReturningToSamePaneUsesReplacementNonce() {
        let (catalog, window, controller) = setup(unowned: true)
        window.projectSessionContexts[1] = context("b", "")
        window.delayDirectory = true
        for identifier in ["a", "b", "a"] {
            window.projectActiveSessionIdentifier = identifier
            controller.activeSessionDidChange()
        }
        XCTAssertEqual(window.directoryCallbacks.count, 3)
        guard window.directoryCallbacks.count == 3 else { return }
        window.directoryCallbacks[0]("/var")
        window.directoryCallbacks[1]("/var")
        let done = expectation(description: "replacement pane cwd associated")
        var fulfilled = false
        window.stateChanged = {
            if !fulfilled && controller.selectedProjectIdentifier == catalog.projects[0].identifier { fulfilled = true; done.fulfill() }
        }
        window.directoryCallbacks[2]("/tmp")
        wait(for: [done], timeout: 5)
        XCTAssertEqual(window.projectSessionContexts.first?.projectIdentifier, catalog.projects[0].identifier)
        XCTAssertEqual(window.projectSessionContexts.last?.projectIdentifier, "")
    }

    func testWindowWithoutSourcePaneAcceptsItsFirstCreatedTab() {
        let (catalog, window, controller) = setup()
        window.projectSessionContexts = []
        window.projectActiveSessionIdentifier = nil
        window.projectActiveTabIdentifier = nil
        controller.activeSessionDidChange()
        controller.openProject(catalog.projects[0], style: .tab)
        XCTAssertNil(window.requests.first?.target)
        window.projectSessionContexts = [context("first", catalog.projects[0].identifier, tab: "first-tab")]
        window.projectActiveSessionIdentifier = "first"
        window.requests[0].completion(.init(sessionIdentifier: "first", tabIdentifier: "first-tab", windowIdentifier: "w"))
        XCTAssertEqual(window.selected, ["first"])
        XCTAssertEqual(controller.selectedProjectIdentifier, catalog.projects[0].identifier)
    }
    func testCopiedOwnershipUsesNewStableIdentityAndPrunesOriginalRecency() {
        let (catalog, window, controller) = setup()
        let owner = iTermProjectSessionOwnership.identifier(fromArrangement:
            iTermProjectSessionOwnership.arrangementFields(projectIdentifier: catalog.projects[0].identifier))
        window.projectSessionContexts = [context("copied-new-id", owner)]
        window.projectActiveSessionIdentifier = "copied-new-id"
        controller.activeSessionDidChange()
        controller.selectProject(catalog.projects[0])
        XCTAssertEqual(window.selected, ["copied-new-id"])
        XCTAssertEqual((controller.restorableState()["sessionRemembered"] as? [String: String])?[catalog.projects[0].identifier], "copied-new-id")
        XCTAssertTrue(window.requests.isEmpty)
    }

    func testInvalidNonWindowResultCannotStealSelectionWhileSourceRemainsActive() {
        for style in [iTermOpenStyle.tab, .verticalSplit, .horizontalSplit] {
            for invalidResult in ["missing", "exited", "moved-tab", "wrong-owner"] {
                let (catalog, window, controller) = setup()
                let source = catalog.projects[0].identifier
                let requested = catalog.projects[1].identifier
                controller.openProject(catalog.projects[1], style: style)
                switch invalidResult {
                case "exited": window.projectSessionContexts.append(context("created", requested, tab: "new", exited: true))
                case "moved-tab": window.projectSessionContexts.append(context("created", requested, tab: "moved"))
                case "wrong-owner": window.projectSessionContexts.append(context("created", source, tab: "new"))
                default: break
                }
                window.requests[0].completion(.init(sessionIdentifier: "created", tabIdentifier: "new", windowIdentifier: "w"))
                XCTAssertTrue(window.selected.isEmpty, "\(style): \(invalidResult)")
                XCTAssertEqual(controller.selectedProjectIdentifier, source, "\(style): \(invalidResult)")
                XCTAssertEqual(window.projectActiveSessionIdentifier, "a")
                XCTAssertNil((controller.restorableState()["sessionRemembered"] as? [String: String])?[requested])
            }
        }
    }
    func testWindowResultOutsideSourceContextsStillLeavesSourceSelectionUntouched() {
        let (catalog, window, controller) = setup()
        controller.openProject(catalog.projects[1], style: .window)
        window.requests[0].completion(.init(sessionIdentifier: "outside", tabIdentifier: "outside-tab", windowIdentifier: "outside-window"))
        XCTAssertTrue(window.selected.isEmpty)
        XCTAssertEqual(window.projectActiveSessionIdentifier, "a")
        XCTAssertEqual(controller.selectedProjectIdentifier, catalog.projects[0].identifier)
    }

    func testOwnershipCodecPreservesLegacyInheritanceAndExplicitEmptyOverride() {
        XCTAssertNil(iTermProjectSessionOwnership.identifier(fromArrangement: [:]))
        XCTAssertNil(iTermProjectSessionOwnership.identifier(fromArrangement: ["Session Project Identifier": 3]))
        XCTAssertEqual(iTermProjectSessionOwnership.effectiveIdentifier(nil, inheriting: "old-owner"), "old-owner")
        XCTAssertEqual(iTermProjectSessionOwnership.effectiveIdentifier("", inheriting: "old-owner"), "")
        XCTAssertEqual(iTermProjectSessionOwnership.arrangementFields(projectIdentifier: nil), [:])
        for owner in ["", "opaque-owner"] {
            let fields = iTermProjectSessionOwnership.arrangementFields(projectIdentifier: owner)
            XCTAssertEqual(fields, ["Session Project Identifier": owner])
            XCTAssertEqual(iTermProjectSessionOwnership.identifier(fromArrangement: fields), owner)
        }
        let copied = context("new-stable-id", iTermProjectSessionOwnership.identifier(fromArrangement: ["Session Project Identifier": "opaque-owner"]))
        XCTAssertEqual(copied.sessionIdentifier, "new-stable-id")
        XCTAssertEqual(copied.projectIdentifier, "opaque-owner")
    }
}

import XCTest
@testable import iTerm2SharedARC

final class ProjectWindowTests: XCTestCase {
    private final class Window: NSObject, iTermProjectWindowDelegate {
        var projectTabAssociations: [String: String] = [:]
        var projectActiveTabIdentifier: String?
        var launches = 0
        var selectedTabs = [String]()
        var directories = [String]()
        var completion: ((String?) -> Void)?
        var completions = [(String?) -> Void]()
        var workingDirectory: String?
        var directoryReads = 0
        var directoryCompletion: ((String?) -> Void)?
        var directoryCompletions = [(String?) -> Void]()
        var delaysDirectoryRead = false
        var stateChanged: (() -> Void)?
        func projectSelectTab(_ identifier: String) { selectedTabs.append(identifier); projectActiveTabIdentifier = identifier }
        func projectAssign(_ project: String?, toTab identifier: String) { projectTabAssociations[identifier] = project ?? "" }
        func projectLaunch(_ project: iTermProjectDirectory, directory: String, completion: @escaping (String?) -> Void) {
            launches += 1
            directories.append(directory)
            self.completion = completion
            completions.append(completion)
        }
        func projectStateDidChange() { stateChanged?() }
        func projectWorkingDirectory(completion: @escaping (String?) -> Void) {
            directoryReads += 1
            if delaysDirectoryRead { directoryCompletion = completion; directoryCompletions.append(completion) }
            else { completion(workingDirectory) }
        }
    }

    func testReturningToUnownedTabSupersedesItsPendingDirectoryRead() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["a": "", "b": ""]
        window.delaysDirectoryRead = true
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        for tab in ["a", "b", "a"] {
            window.projectActiveTabIdentifier = tab
            coordinator.activeTabDidChange()
        }
        XCTAssertEqual(window.directoryReads, 3)
        guard window.directoryCompletions.count == 3 else { return }
        window.directoryCompletions[0]("/tmp")
        window.directoryCompletions[1]("/var")
        let selected = expectation(description: "replacement cwd associated")
        window.stateChanged = { if coordinator.selectedProjectIdentifier == catalog.projects[0].identifier { selected.fulfill() } }
        window.directoryCompletions[2]("/tmp")
        wait(for: [selected], timeout: 5)
        XCTAssertEqual(window.projectTabAssociations["a"], catalog.projects[0].identifier)
        XCTAssertEqual(window.projectTabAssociations["b"], "")
        XCTAssertEqual(window.projectActiveTabIdentifier, "a")
    }

    func testAddCurrentDirectoryAssociatesCurrentTabInsteadOfSelectingAnotherProjectTab() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["current": catalog.projects[0].identifier,
                                         "other": catalog.projects[1].identifier]
        window.projectActiveTabIdentifier = "current"
        window.workingDirectory = "/var"
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        let done = expectation(description: "current directory associated")
        coordinator.addCurrentDirectory { project, error in
            XCTAssertNil(error)
            XCTAssertEqual(project?.identifier, catalog.projects[1].identifier)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(window.projectActiveTabIdentifier, "current")
        XCTAssertEqual(window.projectTabAssociations["current"], catalog.projects[1].identifier)
        XCTAssertEqual(coordinator.selectedProjectIdentifier, catalog.projects[1].identifier)
        XCTAssertTrue(window.selectedTabs.isEmpty)
        XCTAssertEqual(window.launches, 0)
        XCTAssertEqual(catalog.projects.count, 2)
    }

    func testAddUnknownCurrentDirectoryAddsAndAssociatesWithoutLaunchingTerminal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["current": catalog.projects[0].identifier]
        window.projectActiveTabIdentifier = "current"
        window.workingDirectory = root.path
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        let done = expectation(description: "unknown directory associated")
        coordinator.addCurrentDirectory { project, error in
            XCTAssertNil(error)
            XCTAssertNotNil(project)
            XCTAssertEqual(window.projectTabAssociations["current"], project?.identifier)
            XCTAssertEqual(coordinator.selectedProjectIdentifier, project?.identifier)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(catalog.projects.count, 3)
        XCTAssertEqual(window.projectActiveTabIdentifier, "current")
        XCTAssertTrue(window.selectedTabs.isEmpty)
        XCTAssertEqual(window.launches, 0)
    }

    func testLateAddCurrentDirectoryCannotOverrideLaterProjectSelection() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["current": catalog.projects[0].identifier,
                                         "other": catalog.projects[1].identifier]
        window.projectActiveTabIdentifier = "current"
        window.delaysDirectoryRead = true
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        let done = expectation(description: "obsolete directory action discarded")
        coordinator.addCurrentDirectory { project, error in
            XCTAssertNil(project)
            XCTAssertNil(error)
            done.fulfill()
        }
        coordinator.selectProject(catalog.projects[1])
        window.directoryCompletion?("/tmp")
        wait(for: [done], timeout: 5)
        XCTAssertEqual(window.projectActiveTabIdentifier, "other")
        XCTAssertEqual(window.projectTabAssociations["current"], catalog.projects[0].identifier)
        XCTAssertEqual(coordinator.selectedProjectIdentifier, catalog.projects[1].identifier)
        XCTAssertEqual(window.launches, 0)
        XCTAssertEqual(catalog.projects.count, 2)
    }

    func testReSelectingSameProjectSupersedesPendingAddCurrentDirectory() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["current": catalog.projects[0].identifier]
        window.projectActiveTabIdentifier = "current"
        window.delaysDirectoryRead = true
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        let done = expectation(description: "same-project click supersedes add")
        coordinator.addCurrentDirectory { project, error in
            XCTAssertNil(project)
            XCTAssertNil(error)
            done.fulfill()
        }
        coordinator.selectProject(catalog.projects[0])
        window.directoryCompletion?("/var")
        wait(for: [done], timeout: 5)
        XCTAssertEqual(window.projectTabAssociations["current"], catalog.projects[0].identifier)
        XCTAssertEqual(coordinator.selectedProjectIdentifier, catalog.projects[0].identifier)
        XCTAssertEqual(window.projectActiveTabIdentifier, "current")
        XCTAssertEqual(window.launches, 0)
    }

    func testSymlinkSpelledWorkingDirectoryReusesCanonicalParentProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("repo")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: repo)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let name = "ProjectWindowAliasTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let identifier = UUID().uuidString
        defaults.set([["identifier": identifier, "rootDirectory": repo.standardizedFileURL.resolvingSymlinksInPath().path]], forKey: iTermProjectCatalog.defaultsKey)
        let catalog = iTermProjectCatalog(defaults: defaults)
        let window = Window()
        window.projectTabAssociations = ["opened": ""]
        window.projectActiveTabIdentifier = "opened"
        window.workingDirectory = alias.appendingPathComponent("sub").path
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let selected = expectation(description: "canonical parent selected")
        window.stateChanged = { if coordinator.selectedProjectIdentifier != nil { selected.fulfill() } }
        coordinator.activeTabDidChange()
        wait(for: [selected], timeout: 5)
        XCTAssertEqual(coordinator.selectedProjectIdentifier, identifier)
        XCTAssertEqual(catalog.projects.count, 1)
        XCTAssertEqual(window.projectTabAssociations["opened"], identifier)
    }

    func testUnownedTerminalSelectsExistingWorkingDirectoryWithoutSwitchingTabs() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["plain": ""]
        window.projectActiveTabIdentifier = "plain"
        window.workingDirectory = "/tmp"
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let selected = expectation(description: "cwd associated")
        window.stateChanged = { if coordinator.selectedProjectIdentifier == catalog.projects[0].identifier { selected.fulfill() } }
        coordinator.activeTabDidChange()
        wait(for: [selected], timeout: 5)
        XCTAssertEqual(coordinator.selectedProjectIdentifier, catalog.projects[0].identifier)
        XCTAssertEqual(window.projectTabAssociations["plain"], catalog.projects[0].identifier)
        XCTAssertEqual(window.projectActiveTabIdentifier, "plain")
        XCTAssertEqual(window.launches, 0)
    }

    func testCanonicalAliasProjectWinsOverShallowerLiteralAncestor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("repo")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: repo)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let name = "ProjectWindowAliasAncestorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let identifier = UUID().uuidString
        defaults.set([["identifier": UUID().uuidString, "rootDirectory": "/"],
                      ["identifier": identifier, "rootDirectory": alias.standardizedFileURL.path]],
                     forKey: iTermProjectCatalog.defaultsKey)
        let catalog = iTermProjectCatalog(defaults: defaults)
        let window = Window()
        window.projectTabAssociations = ["opened": ""]
        window.projectActiveTabIdentifier = "opened"
        window.workingDirectory = repo.appendingPathComponent("sub").path
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let selected = expectation(description: "deepest canonical project selected")
        window.stateChanged = { if coordinator.selectedProjectIdentifier != nil { selected.fulfill() } }
        coordinator.activeTabDidChange()
        wait(for: [selected], timeout: 5)
        XCTAssertEqual(coordinator.selectedProjectIdentifier, identifier)
        XCTAssertEqual(window.projectTabAssociations["opened"], identifier)
        XCTAssertEqual(catalog.projects.count, 2)
    }

    func testUnknownWorkingDirectoryIsAddedAndAssignedToTheOpenedTerminal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let name = "ProjectWindowCwdTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let catalog = iTermProjectCatalog(defaults: defaults)
        let window = Window()
        window.projectTabAssociations = ["opened": ""]
        window.projectActiveTabIdentifier = "opened"
        window.workingDirectory = root.path
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        let drained = expectation(description: "cwd directory added")
        catalog.addDirectory(atPath: root.path) { _, _ in drained.fulfill() }
        wait(for: [drained], timeout: 5)
        let project = try XCTUnwrap(catalog.projects.first)
        XCTAssertEqual(coordinator.selectedProjectIdentifier, project.identifier)
        XCTAssertEqual(window.projectTabAssociations["opened"], project.identifier)
        XCTAssertEqual(window.projectActiveTabIdentifier, "opened")
        XCTAssertEqual(window.launches, 0)
        XCTAssertEqual(catalog.projects.count, 1)
    }

    func testLateWorkingDirectoryDoesNotOverrideUserProjectSelection() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["plain": "", "owned": catalog.projects[1].identifier]
        window.projectActiveTabIdentifier = "plain"
        window.delaysDirectoryRead = true
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        coordinator.selectProject(catalog.projects[1])
        window.directoryCompletion?("/tmp")
        XCTAssertEqual(coordinator.selectedProjectIdentifier, catalog.projects[1].identifier)
        XCTAssertEqual(window.projectActiveTabIdentifier, "owned")
        XCTAssertEqual(window.projectTabAssociations["plain"], "")
    }

    func testOwnedTerminalKeepsItsProjectAndDoesNotReadWorkingDirectory() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["owned": catalog.projects[0].identifier]
        window.projectActiveTabIdentifier = "owned"
        window.workingDirectory = "/var"
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        coordinator.selectInitialWorkingDirectoryIfNeeded()
        XCTAssertEqual(coordinator.selectedProjectIdentifier, catalog.projects[0].identifier)
        XCTAssertEqual(window.directoryReads, 0)
        XCTAssertEqual(window.launches, 0)
    }

    func testMissingWorkingDirectoryCanRetryWhenShellTrackingBecomesAvailable() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["plain": ""]
        window.projectActiveTabIdentifier = "plain"
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        XCTAssertNil(coordinator.selectedProjectIdentifier)
        window.workingDirectory = "/tmp"
        let selected = expectation(description: "available cwd selected")
        window.stateChanged = { if coordinator.selectedProjectIdentifier == catalog.projects[0].identifier { selected.fulfill() } }
        coordinator.selectInitialWorkingDirectoryIfNeeded()
        wait(for: [selected], timeout: 5)
        XCTAssertEqual(coordinator.selectedProjectIdentifier, catalog.projects[0].identifier)
        XCTAssertEqual(window.projectTabAssociations["plain"], catalog.projects[0].identifier)
        XCTAssertEqual(window.launches, 0)
    }

    func testDirectoryReadCannotAssociateClosedOrMovedTab() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        window.projectTabAssociations = ["closing": ""]
        window.projectActiveTabIdentifier = "closing"
        window.delaysDirectoryRead = true
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        coordinator.activeTabDidChange()
        window.projectTabAssociations.removeValue(forKey: "closing")
        window.projectActiveTabIdentifier = nil
        coordinator.tabsDidChange()
        window.directoryCompletion?("/tmp")
        XCTAssertNil(coordinator.selectedProjectIdentifier)
        XCTAssertNil(window.projectTabAssociations["closing"])
    }

    func testCatalogAdditionDoesNotCancelPendingUserProjectSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let (catalog, _) = makeCatalog()
        let window = Window()
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let project = catalog.projects[0]
        coordinator.selectProject(project)
        let generation = coordinator.selectionGeneration
        let done = expectation(description: "other directory added")
        catalog.addDirectory(atPath: root.path) { _, _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(coordinator.selectionGeneration, generation)
        window.projectTabAssociations["launched"] = project.identifier
        window.completion?("launched")
        XCTAssertEqual(window.projectActiveTabIdentifier, "launched")
        XCTAssertEqual(coordinator.selectedProjectIdentifier, project.identifier)
    }

    func testAbandonedDirectoryValidationDoesNotAddAProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let (catalog, _) = makeCatalog()
        let done = expectation(description: "abandoned directory resolved")
        catalog.addDirectoryIfCurrent(atPath: root.path, shouldAdd: { false }) { project, error in
            XCTAssertNil(project)
            XCTAssertEqual(error?.code, NSUserCancelledError)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(catalog.projects.map(\.rootDirectory), ["/tmp", "/var"])
    }

    func testRememberedTabFallbackMoveAndUnownedSelection() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let project = catalog.projects[0]
        window.projectTabAssociations = ["a": project.identifier, "b": project.identifier, "plain": ""]
        window.projectActiveTabIdentifier = "b"
        coordinator.activeTabDidChange()
        coordinator.selectProject(project)
        XCTAssertEqual(window.projectActiveTabIdentifier, "b")
        window.projectTabAssociations.removeValue(forKey: "b") // closed or moved away
        coordinator.tabsDidChange()
        XCTAssertEqual((coordinator.restorableState()["remembered"] as? [String: String])?.count, 0)
        coordinator.selectProject(project)
        XCTAssertEqual(window.projectActiveTabIdentifier, "a")
        let destination = Window()
        destination.projectTabAssociations = ["b": project.identifier]
        let other = iTermProjectWindowController(catalog: catalog)
        other.delegate = destination
        other.selectProject(project)
        XCTAssertEqual(destination.projectActiveTabIdentifier, "b")
        XCTAssertEqual(destination.launches, 0)
        window.projectActiveTabIdentifier = "plain"
        coordinator.activeTabDidChange()
        XCTAssertNil(coordinator.selectedProject)
    }

    func testLaunchDedupAndRemovalUnbindsEveryWindow() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let project = catalog.projects[0]
        coordinator.selectProject(project)
        coordinator.selectProject(project)
        XCTAssertEqual(window.launches, 1)
        window.projectTabAssociations["new"] = project.identifier
        window.completion?("new")
        coordinator.selectProject(project)
        XCTAssertEqual(window.launches, 1)
        let other = Window()
        other.projectTabAssociations["moved"] = project.identifier
        let second = iTermProjectWindowController(catalog: catalog)
        second.delegate = other
        catalog.removeProject(withIdentifier: project.identifier)
        XCTAssertEqual(window.projectTabAssociations["new"], "")
        XCTAssertEqual(other.projectTabAssociations["moved"], "")
        XCTAssertNil(coordinator.selectedProject)
    }

    func testReturningToProjectSupersedesStalePreflightInEitherCompletionOrder() {
        for oldCompletesFirst in [true, false] {
            let (catalog, _) = makeCatalog()
            let window = Window()
            let coordinator = iTermProjectWindowController(catalog: catalog)
            coordinator.delegate = window
            let projectA = catalog.projects[0]
            let projectB = catalog.projects[1]
            coordinator.selectProject(projectA)
            coordinator.selectProject(projectB)
            coordinator.selectProject(projectA)
            XCTAssertEqual(window.directories, [projectA.rootDirectory, projectB.rootDirectory, projectA.rootDirectory])
            guard window.completions.count == 3 else { continue }
            if oldCompletesFirst {
                window.completions[0](nil) // Original A rejects its stale preflight generation.
                window.completions[1](nil)
                coordinator.selectProject(projectA)
                XCTAssertEqual(window.launches, 3) // Old completion must not clear replacement A.
            }
            window.projectTabAssociations["final-a"] = projectA.identifier
            window.completions[2]("final-a")
            if !oldCompletesFirst {
                window.completions[0](nil)
                window.completions[1](nil)
            }
            XCTAssertEqual(window.projectActiveTabIdentifier, "final-a")
            XCTAssertEqual(coordinator.selectedProjectIdentifier, projectA.identifier)
            XCTAssertEqual((coordinator.restorableState()["remembered"] as? [String: String])?[projectA.identifier], "final-a")
            coordinator.selectProject(projectA)
            XCTAssertEqual(window.launches, 3)
        }
    }

    func testSameProjectTabSelectionWinsOverLateLaunch() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let project = catalog.projects[0]
        coordinator.selectProject(project)
        window.projectTabAssociations["chosen"] = project.identifier
        window.projectActiveTabIdentifier = "chosen"
        coordinator.activeTabDidChange()
        window.projectTabAssociations["late"] = project.identifier
        window.completion?("late")
        XCTAssertEqual(window.projectActiveTabIdentifier, "chosen")
        XCTAssertEqual((coordinator.restorableState()["remembered"] as? [String: String])?[project.identifier], "chosen")
        coordinator.openTerminal(inDirectory: "/tmp/subdirectory")
        window.projectActiveTabIdentifier = "chosen"
        coordinator.activeTabDidChange()
        window.completion?("late")
        XCTAssertEqual(window.projectActiveTabIdentifier, "chosen")
    }

    func testFileTreeLaunchUsesRequestedDirectoryAndKeepsRootPinned() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let project = catalog.projects[0]
        coordinator.selectProject(project)
        XCTAssertEqual(window.directories, [project.rootDirectory])
        window.projectTabAssociations["root"] = project.identifier
        window.completion?("root")
        coordinator.openTerminal(inDirectory: "/tmp/subdirectory")
        XCTAssertEqual(window.directories, [project.rootDirectory, "/tmp/subdirectory"])
        XCTAssertEqual(coordinator.selectedProject?.rootDirectory, project.rootDirectory)
    }

    func testFailedLaunchCanRetryAndLateCompletionDoesNotStealSelection() {
        let (catalog, _) = makeCatalog()
        let window = Window()
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.delegate = window
        let project = catalog.projects[0]
        coordinator.selectProject(project)
        window.completion?(nil)
        coordinator.selectProject(project)
        XCTAssertEqual(window.launches, 2)
        window.projectTabAssociations["plain"] = ""
        window.projectActiveTabIdentifier = "plain"
        coordinator.activeTabDidChange()
        window.projectTabAssociations["late"] = project.identifier
        window.completion?("late")
        XCTAssertEqual(window.projectActiveTabIdentifier, "plain")
        XCTAssertNil(coordinator.selectedProject)
        coordinator.selectProject(project)
        XCTAssertEqual(window.projectActiveTabIdentifier, "late")
        XCTAssertEqual(window.launches, 2)
    }

    func testLegacyAndInvalidWindowState() {
        let (catalog, _) = makeCatalog()
        let coordinator = iTermProjectWindowController(catalog: catalog)
        coordinator.restore(from: [:])
        XCTAssertFalse(coordinator.sidebarVisible)
        XCTAssertEqual(coordinator.sidebarWidth, 220)
        coordinator.restore(from: ["visible": true, "width": 999, "selected": "missing"])
        XCTAssertTrue(coordinator.sidebarVisible)
        XCTAssertEqual(coordinator.sidebarWidth, 360)
        XCTAssertNil(coordinator.selectedProject)
        let restored = iTermProjectWindowController(catalog: catalog)
        restored.restore(from: coordinator.restorableState())
        XCTAssertEqual(restored.sidebarWidth, 360)
        XCTAssertTrue(restored.sidebarVisible)
    }

    private func makeCatalog() -> (iTermProjectCatalog, UserDefaults) {
        let name = "ProjectWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set([["identifier": UUID().uuidString, "rootDirectory": "/tmp"],
                      ["identifier": UUID().uuidString, "rootDirectory": "/var"]], forKey: iTermProjectCatalog.defaultsKey)
        return (iTermProjectCatalog(defaults: defaults), defaults)
    }
}

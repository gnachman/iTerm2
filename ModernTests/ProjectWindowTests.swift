import XCTest
@testable import iTerm2SharedARC

final class ProjectWindowTests: XCTestCase {
    private final class Window: NSObject, iTermProjectWindowDelegate {
        var projectTabAssociations: [String: String] = [:]
        var projectActiveTabIdentifier: String?
        var launches = 0
        var directories = [String]()
        var completion: ((String?) -> Void)?
        func projectSelectTab(_ identifier: String) { projectActiveTabIdentifier = identifier }
        func projectAssign(_ project: String?, toTab identifier: String) { projectTabAssociations[identifier] = project ?? "" }
        func projectLaunch(_ project: iTermProjectDirectory, directory: String, completion: @escaping (String?) -> Void) {
            launches += 1
            directories.append(directory)
            self.completion = completion
        }
        func projectStateDidChange() {}
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
        defaults.set([["identifier": UUID().uuidString, "rootDirectory": "/tmp"]], forKey: iTermProjectCatalog.defaultsKey)
        return (iTermProjectCatalog(defaults: defaults), defaults)
    }
}

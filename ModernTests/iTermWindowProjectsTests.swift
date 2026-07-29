//
//  iTermWindowProjectsTests.swift
//  iTerm2
//
//  Created by Gemini CLI on 6/17/26.
//

import XCTest
@testable import iTerm2SharedARC

class iTermWindowProjectsTests: XCTestCase {
    private var savedProjects: [iTermWindowProject] = []
    private var savedAssociations: [String: UUID] = [:]
    private var savedIsTerminating = false

    override func setUp() {
        super.setUp()
        let model = iTermWindowProjectsModel.shared
        // 1. Back up any existing in-memory projects and associations
        savedProjects = model.rootProjects
        savedAssociations = model.testOnlyAssociations
        savedIsTerminating = model.testOnlyIsTerminating

        // 2. Clear rootProjects for a clean test environment by deleting them via the public API
        while !model.rootProjects.isEmpty {
            model.deleteProject(model.rootProjects[0])
        }
        model.testOnlyAssociations = [:]
        model.testOnlyIsTerminating = false
    }

    override func tearDown() {
        // Restore user's original projects and associations back to the singleton
        let model = iTermWindowProjectsModel.shared
        model.testOnlySetRootProjects(savedProjects)
        model.testOnlyAssociations = savedAssociations
        model.testOnlyIsTerminating = savedIsTerminating
        super.tearDown()
    }
    
    func testProjectCRUD() {
        let model = iTermWindowProjectsModel.shared
        
        // 1. Verify initial clean slate
        XCTAssertEqual(model.rootProjects.count, 0)
        
        // 2. Create a root project
        let projectA = model.createProject(named: "Project-A")
        XCTAssertEqual(model.rootProjects.count, 1)
        XCTAssertEqual(model.rootProjects[0].name, "Project-A")
        XCTAssertEqual(model.rootProjects[0].id, projectA.id)
        
        // 3. Create a nested child project
        let subProject = model.createProject(named: "Sub-Project-B", parent: projectA)
        XCTAssertEqual(projectA.children.count, 1)
        XCTAssertEqual(projectA.children[0].name, "Sub-Project-B")
        XCTAssertEqual(projectA.children[0].id, subProject.id)
        
        // 4. Lookups
        let foundProject = model.project(id: subProject.id)
        XCTAssertNotNil(foundProject)
        XCTAssertEqual(foundProject?.name, "Sub-Project-B")
        
        // 5. Rename project
        model.renameProject(subProject, to: "Sub-Project-B-Renamed")
        XCTAssertEqual(projectA.children[0].name, "Sub-Project-B-Renamed")
        
        // 6. Delete project
        let deleted = model.deleteProject(projectA)
        XCTAssertTrue(deleted)
        XCTAssertEqual(model.rootProjects.count, 0)
        XCTAssertNil(model.project(id: subProject.id))
    }
    
    func testArchivedWindowSerializationAndDeserialization() {
        let dummyArrangement: [AnyHashable: Any] = [
            "Columns": 120,
            "Rows": 45,
            "WorkingDirectory": "/tmp"
        ]
        
        // Create an archived window
        let archived = iTermArchivedWindow(name: "Window-A", arrangement: dummyArrangement)
        XCTAssertEqual(archived.name, "Window-A")
        XCTAssertNotNil(archived.arrangement)
        
        // Verify arrangement values survive base64 plist encoding/decoding cycle
        let recoveredArrangement = archived.arrangement
        XCTAssertNotNil(recoveredArrangement)
        XCTAssertEqual(recoveredArrangement?["Columns"] as? Int, 120)
        XCTAssertEqual(recoveredArrangement?["Rows"] as? Int, 45)
        XCTAssertEqual(recoveredArrangement?["WorkingDirectory"] as? String, "/tmp")
    }
    
    func testProjectHierarchyWindowCascading() {
        let model = iTermWindowProjectsModel.shared
        let root = model.createProject(named: "Project-C")
        let dummyArrangement: [AnyHashable: Any] = ["Columns": 80]
        
        let archivedWin = iTermArchivedWindow(name: "Window-B", arrangement: dummyArrangement)
        root.windows.append(archivedWin)
        
        // Verify we can find the archived window inside the tree
        let found = model.archivedWindow(id: archivedWin.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.0.name, "Window-B")
        XCTAssertEqual(found?.1.id, root.id)
        
        // Verify we find parent project of the window
        let parent = model.parentProject(of: archivedWin)
        XCTAssertEqual(parent?.id, root.id)
        
        // Remove archived window
        model.removeWindow(archivedWin, from: root)
        XCTAssertEqual(root.windows.count, 0)
        XCTAssertNil(model.archivedWindow(id: archivedWin.id))
    }
    
    func testUnlimitedHistoryFlag() {
        XCTAssertFalse(PseudoTerminal.useUnlimitedHistoryForArrangement())
        
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
        XCTAssertTrue(PseudoTerminal.useUnlimitedHistoryForArrangement())
        
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
        XCTAssertFalse(PseudoTerminal.useUnlimitedHistoryForArrangement())
    }

    func testIsOrphanedAndRunning() {
        // 1. Test with a dead/non-existent PID (e.g. 999999)
        let deadArrangement: [AnyHashable: Any] = [
            "Tabs": [
                [
                    "Navigation": [
                        "Server PID": 999999
                    ]
                ]
            ]
        ]
        let archivedDead = iTermArchivedWindow(name: "DeadWindow", arrangement: deadArrangement)
        XCTAssertFalse(archivedDead.isOrphanedAndRunning, "Window with a non-existent PID should not be detected as running")
        
        // 2. Test with a live PID (our own running test process PID is guaranteed to be alive!)
        let livePID = Int(ProcessInfo.processInfo.processIdentifier)
        let liveArrangement: [AnyHashable: Any] = [
            "Tabs": [
                [
                    "Navigation": [
                        "Server PID": livePID
                    ]
                ]
            ]
        ]
        let archivedLive = iTermArchivedWindow(name: "LiveWindow", arrangement: liveArrangement)
        XCTAssertTrue(archivedLive.isOrphanedAndRunning, "Window with our own running process PID should be detected as active")
    }

    func testArchiveAndReattachmentMetadata() {
        let livePID = Int(ProcessInfo.processInfo.processIdentifier)
        let arrangementWithArchive: [AnyHashable: Any] = [
            "Tabs": [
                [
                    "Navigation": [
                        "Server PID": livePID
                    ]
                ]
            ],
            "Archive": [
                "columns": 80,
                "rows": 24
            ]
        ]
        
        let archived = iTermArchivedWindow(name: "TestArchiveWindow", arrangement: arrangementWithArchive)
        
        // Assert the arrangement has the archive key with columns and rows
        let retrieved = archived.arrangement
        XCTAssertNotNil(retrieved)
        let archiveDict = retrieved?["Archive"] as? [String: Int]
        XCTAssertNotNil(archiveDict)
        XCTAssertEqual(archiveDict?["columns"], 80)
        XCTAssertEqual(archiveDict?["rows"], 24)
        
        // Assert it is detected as running/active since PID matches our live process
        XCTAssertTrue(archived.isOrphanedAndRunning)
    }

    func testProjectRecursiveCRUD() {
        let model = iTermWindowProjectsModel.shared
        
        // 1. Create 3 levels of nesting
        let level1 = model.createProject(named: "Level-1")
        let level2 = model.createProject(named: "Level-2", parent: level1)
        let level3 = model.createProject(named: "Level-3", parent: level2)
        
        XCTAssertEqual(model.rootProjects.count, 1)
        XCTAssertEqual(level1.children.count, 1)
        XCTAssertEqual(level2.children.count, 1)
        
        // 2. Lookup deeply nested descendants
        let foundL3 = model.project(id: level3.id)
        XCTAssertNotNil(foundL3)
        XCTAssertEqual(foundL3?.name, "Level-3")
        
        // 3. Delete the parent project (Level-1) and check that recursive cascading occurs
        let deleted = model.deleteProject(level1)
        XCTAssertTrue(deleted)
        XCTAssertEqual(model.rootProjects.count, 0)
        
        // Grandchild should be recursively deleted and unsearchable
        XCTAssertNil(model.project(id: level3.id))
        XCTAssertNil(model.project(id: level2.id))
    }

    func testModelPersistence() {
        let model = iTermWindowProjectsModel.shared
        
        // Create an unique setup to serialize
        let persistentProject = model.createProject(named: "Persistence-Test-Project")
        let sub = model.createProject(named: "Persistence-Sub-Project", parent: persistentProject)
        
        // Add a dummy window arrangement to verify full nested tree serialization
        let dummyArrangement: [AnyHashable: Any] = ["Columns": 100, "Rows": 30]
        let dummyArchivedWindow = iTermArchivedWindow(name: "PersistWindow", arrangement: dummyArrangement)
        sub.windows.append(dummyArchivedWindow)
        
        // Trigger save explicitly
        model.save()
        
        // Locate the save JSON file URL
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let saveURL = support.appendingPathComponent("iTerm2").appendingPathComponent("WindowProjects_test.json")
        
        // Assert the file was actually written to disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveURL.path))
        
        // Decode file directly to prove model schema integrity and file format consistency
        guard let data = try? Data(contentsOf: saveURL) else {
            XCTFail("Failed to read persistent JSON data from disk")
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let loadedProjects = try decoder.decode([iTermWindowProject].self, from: data)
            XCTAssertEqual(loadedProjects.count, 1)
            XCTAssertEqual(loadedProjects[0].name, "Persistence-Test-Project")
            
            let loadedSub = loadedProjects[0].children[0]
            XCTAssertEqual(loadedSub.name, "Persistence-Sub-Project")
            XCTAssertEqual(loadedSub.windows.count, 1)
            XCTAssertEqual(loadedSub.windows[0].name, "PersistWindow")
            
            let recoveredArr = loadedSub.windows[0].arrangement
            XCTAssertEqual(recoveredArr?["Columns"] as? Int, 100)
            XCTAssertEqual(recoveredArr?["Rows"] as? Int, 30)
        } catch {
            XCTFail("Failed decoding saved window projects JSON structure: \(error)")
        }
        
        // Clean up the project after testing
        model.deleteProject(persistentProject)
    }

    func testProjectsOutlineControllerDataSource() {
        let model = iTermWindowProjectsModel.shared
        
        // Setup mock projects hierarchy
        let p1 = model.createProject(named: "TestUI-P1")
        let sub1 = model.createProject(named: "TestUI-Sub1", parent: p1)
        
        let dummyArrangement: [AnyHashable: Any] = ["Columns": 80]
        let arch1 = iTermArchivedWindow(name: "TestUI-ArchivedWindow", arrangement: dummyArrangement)
        sub1.windows.append(arch1)
        
        // Instantiate the controller
        let controller = iTermProjectsOutlineController()
        controller.loadView()
        controller.viewDidLoad()
        
        // 1. Verify root level count (item is nil)
        let rootCount = controller.outlineView(controller.outlineView, numberOfChildrenOfItem: nil)
        XCTAssertEqual(rootCount, 1)
        
        // 2. Verify root child is project p1
        let rootChild = controller.outlineView(controller.outlineView, child: 0, ofItem: nil) as? iTermWindowProject
        XCTAssertNotNil(rootChild)
        XCTAssertEqual(rootChild?.name, "TestUI-P1")
        
        // 3. Verify subproject children under p1
        let subCount = controller.outlineView(controller.outlineView, numberOfChildrenOfItem: p1)
        XCTAssertEqual(subCount, 1)
        
        let subChild = controller.outlineView(controller.outlineView, child: 0, ofItem: p1) as? iTermWindowProject
        XCTAssertNotNil(subChild)
        XCTAssertEqual(subChild?.name, "TestUI-Sub1")
        
        // 4. Verify archived window box under sub1
        let windowCount = controller.outlineView(controller.outlineView, numberOfChildrenOfItem: sub1)
        XCTAssertEqual(windowCount, 1)
        
        let windowChild = controller.outlineView(controller.outlineView, child: 0, ofItem: sub1) as? iTermArchivedWindowBox
        XCTAssertNotNil(windowChild)
        XCTAssertEqual(windowChild?.window.name, "TestUI-ArchivedWindow")
        XCTAssertEqual(windowChild?.project.id, sub1.id)
        
        // Cleanup
        model.deleteProject(p1)
    }

    func testProjectsOutlineControllerButtonStates() {
        let model = iTermWindowProjectsModel.shared
        
        let p1 = model.createProject(named: "TestUI-P2")
        let arch1 = iTermArchivedWindow(name: "TestUI-ArchivedWindow-2", arrangement: ["Columns": 80])
        p1.windows.append(arch1)
        
        let controller = iTermProjectsOutlineController()
        controller.loadView()
        controller.viewDidLoad()
        
        // Let's reload outlineView and force its selectedRow or selection.
        controller.outlineView.reloadData()
        
        // Select row 0 (which is p1)
        controller.outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        
        // Verify selection computes correctly
        XCTAssertEqual(controller.selectedProject?.id, p1.id)
        XCTAssertNil(controller.selectedArchivedBox)
        
        // Trigger outlineViewSelectionDidChange to update buttons
        controller.outlineViewSelectionDidChange(Notification(name: NSOutlineView.selectionDidChangeNotification))
        
        // Assert project buttons are active. The single Restore button acts on the
        // selection, so selecting a project that has a saved window enables it and its
        // label reflects the count (1 saved window → “Restore”).
        XCTAssertTrue(controller.addSubprojectButton.isEnabled)
        XCTAssertTrue(controller.deleteButton.isEnabled) // Can delete project
        XCTAssertTrue(controller.restoreButton.isEnabled) // Project has 1 saved window
        XCTAssertEqual(controller.restoreButton.title, "Restore")

        // Cleanup
        model.deleteProject(p1)
    }

    func testLiveReattachmentClearsArchiveState() {
        print("--- STARTING SWIZZLE TEST ---")
        // 1. Swizzle tryToAttachToServerWithProcessId:tty: on PTYSession
        let originalSelector = Selector("tryToAttachToServerWithProcessId:tty:")
        let swizzledSelector = Selector("mock_tryToAttachToServerWithProcessId:tty:")
        
        guard let originalMethod = class_getInstanceMethod(PTYSession.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(PTYSession.self, swizzledSelector) else {
            XCTFail("Failed to find selectors for PTYSession swizzling")
            return
        }
        
        // 2. Swizzle runJobsInServers on iTermAdvancedSettingsModel class
        let settingsSelector = Selector("runJobsInServers")
        let swizzledSettingsSelector = Selector("mock_runJobsInServers")
        
        guard let originalSettingsMethod = class_getClassMethod(iTermAdvancedSettingsModel.self, settingsSelector),
              let swizzledSettingsMethod = class_getClassMethod(iTermAdvancedSettingsModel.self, swizzledSettingsSelector) else {
            XCTFail("Failed to find selectors for iTermAdvancedSettingsModel swizzling")
            return
        }
        
        print("Swizzling PTYSession & iTermAdvancedSettingsModel...")
        method_exchangeImplementations(originalMethod, swizzledMethod)
        method_exchangeImplementations(originalSettingsMethod, swizzledSettingsMethod)
        
        // Swap back at the end of the test to keep state clean!
        defer {
            print("Unswizzling...")
            method_exchangeImplementations(originalMethod, swizzledMethod)
            method_exchangeImplementations(originalSettingsMethod, swizzledSettingsMethod)
        }
        
        // Setup mock arrangement with a server PID and TTY
        let arrangement: [AnyHashable: Any] = [
            "Columns": 80,
            "Rows": 24,
            "Bookmark": [
                "GUID": "default-guid"
            ],
            "Server PID": NSNumber(value: 12345),
            "TTY": "/dev/ttyp0" as NSString
        ]
        
        // Setup options with the Archive flag
        let view = SessionView(frame: .zero)
        let options: [AnyHashable: Any] = [
            PTYSessionArrangementOptionsArchive: true
        ]
        
        print("Restoring session...")
        // Restore session from arrangement
        let session = PTYSession(
            fromArrangement: arrangement,
            named: "TestSession",
            in: view,
            with: nil,
            for: .paneObject,
            partialAttachments: nil,
            options: options)
        
        XCTAssertNotNil(session)
        print("Session isArchive after restore: \(session?.isArchive ?? false)")
        // This assertion will FAIL under the reverted bug state (isArchive will be true)
        // but will PASS once we re-apply our fix (isArchive will be false)!
        XCTAssertFalse(session?.isArchive ?? true, "Restored session with live attached process must NOT be marked as an archive (which freezes output/input)")
        XCTAssertTrue(session?.screen.terminalEnabled ?? false, "Restored session screen must be explicitly enabled to receive keyboard inputs and process output characters")
    }

    // MARK: - Multiserver arrangement parsing (headless data layer)

    /// Builds a session arrangement node containing a multiserver "Server Dict"
    /// with the given socket and child PID, mirroring what iTerm2 captures.
    private func arrangement(socket: Int, childPID: Int) -> [AnyHashable: Any] {
        return [
            "Tabs": [
                [
                    "Root": [
                        "Subviews": [
                            [
                                "Session": [
                                    "Server Dict": [
                                        "Socket": socket,
                                        "Child PID": childPID
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    func testServerDictExtraction() {
        let arr = arrangement(socket: 7, childPID: 4242)
        let result = iTermWindowProjectsModel.serverDict(in: arr)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.socket, 7)
        XCTAssertEqual(result?.childPid, 4242)
    }

    func testServerDictExtractionWithNSNumberValues() {
        // iTerm2's decoded plists frequently surface integers as NSNumber.
        let arr: [AnyHashable: Any] = [
            "Session": [
                "Server Dict": [
                    "Socket": NSNumber(value: 3),
                    "Child PID": NSNumber(value: 9001)
                ]
            ]
        ]
        let result = iTermWindowProjectsModel.serverDict(in: arr)
        XCTAssertEqual(result?.socket, 3)
        XCTAssertEqual(result?.childPid, 9001)
    }

    func testServerDictExtractionReturnsNilWhenAbsent() {
        let arr: [AnyHashable: Any] = ["Columns": 80, "Rows": 24]
        XCTAssertNil(iTermWindowProjectsModel.serverDict(in: arr))
    }

    func testAllServerChildPIDsCollectsEverySession() {
        // A multi-pane window: two sessions, each with its own Server Dict.
        let arr: [AnyHashable: Any] = [
            "Tabs": [
                ["Session": ["Server Dict": ["Socket": 2, "Child PID": 100]]],
                ["Session": ["Server Dict": ["Socket": 2, "Child PID": 200]]]
            ]
        ]
        let pids = iTermWindowProjectsModel.allServerChildPIDs(in: arr).sorted()
        XCTAssertEqual(pids, [100, 200])
    }

    func testAllServerChildPIDsEmptyWhenNoServerDict() {
        let arr: [AnyHashable: Any] = ["Columns": 80, "Rows": 24]
        XCTAssertTrue(iTermWindowProjectsModel.allServerChildPIDs(in: arr).isEmpty)
    }

    func testClaimedMultiserverChildPIDsAcrossProjectTree() {
        let model = iTermWindowProjectsModel.shared

        // Two projects, one nested, each with an archived window holding a live
        // (parked) child PID. claimedMultiserverChildPIDs walks the whole tree.
        let root = model.createProject(named: "Claim-Root")
        let child = model.createProject(named: "Claim-Child", parent: root)

        root.windows.append(iTermArchivedWindow(name: "W1", arrangement: arrangement(socket: 2, childPID: 111)))
        child.windows.append(iTermArchivedWindow(name: "W2", arrangement: arrangement(socket: 2, childPID: 222)))

        let claimed = model.claimedMultiserverChildPIDs()
        XCTAssertTrue(claimed.contains(111))
        XCTAssertTrue(claimed.contains(222))

        model.deleteProject(root)
    }

    func testClaimedMultiserverChildPIDsEmptyWithNoArchives() {
        let model = iTermWindowProjectsModel.shared
        model.createProject(named: "Empty-Project")
        XCTAssertTrue(model.claimedMultiserverChildPIDs().isEmpty)
    }

    func testTotalWindowCountIsRecursive() {
        let model = iTermWindowProjectsModel.shared
        let root = model.createProject(named: "Count-Root")
        let sub = model.createProject(named: "Count-Sub", parent: root)

        root.windows.append(iTermArchivedWindow(name: "A", arrangement: ["Columns": 80]))
        sub.windows.append(iTermArchivedWindow(name: "B", arrangement: ["Columns": 80]))
        sub.windows.append(iTermArchivedWindow(name: "C", arrangement: ["Columns": 80]))

        XCTAssertEqual(sub.totalWindowCount, 2)
        XCTAssertEqual(root.totalWindowCount, 3)

        model.deleteProject(root)
    }

    // MARK: - Empty-arrangement guard (DesignNotes #10)

    func testIsArchivableRejectsEmptyAndNilArrangements() {
        XCTAssertFalse(iTermWindowProjectsModel.isArchivable(nil))
        XCTAssertFalse(iTermWindowProjectsModel.isArchivable([:]))
        // A capture with no Tabs (the ~42-byte empty plist) must be rejected.
        XCTAssertFalse(iTermWindowProjectsModel.isArchivable(["Columns": 80, "Rows": 24]))
        // A present-but-empty Tabs array is still not restorable.
        XCTAssertFalse(iTermWindowProjectsModel.isArchivable(["Tabs": [Any]()]))
    }

    func testIsArchivableAcceptsArrangementWithTabs() {
        let arr = arrangement(socket: 2, childPID: 555)
        XCTAssertTrue(iTermWindowProjectsModel.isArchivable(arr))
        XCTAssertTrue(iTermWindowProjectsModel.isArchivable(["Tabs": [["Root": [:]]]]))
    }

    // MARK: - Association persistence (Option A: guid → project, round-trip)

    func testAssociationPersistenceRoundTrip() {
        let model = iTermWindowProjectsModel.shared
        let project = model.createProject(named: "Assoc-Project")
        let guid = "TERMINAL-GUID-ABC123"

        // Associate by guid and persist to the (isolated test) associations file.
        model.testOnlyAssociations = [guid: project.id]

        // Drop the in-memory map and reload from disk, exercising the real
        // save/load serialization (guid → UUID-string and back).
        model.testOnlyReloadAssociationsFromDisk()

        let reloaded = model.testOnlyAssociations
        XCTAssertEqual(reloaded[guid], project.id)

        model.deleteProject(project)
    }

    func testAssociationPersistenceSurvivesMultipleEntries() {
        let model = iTermWindowProjectsModel.shared
        let p1 = model.createProject(named: "Assoc-P1")
        let p2 = model.createProject(named: "Assoc-P2")

        model.testOnlyAssociations = [
            "guid-1": p1.id,
            "guid-2": p2.id,
            "guid-3": p1.id
        ]
        model.testOnlyReloadAssociationsFromDisk()

        let reloaded = model.testOnlyAssociations
        XCTAssertEqual(reloaded.count, 3)
        XCTAssertEqual(reloaded["guid-1"], p1.id)
        XCTAssertEqual(reloaded["guid-2"], p2.id)
        XCTAssertEqual(reloaded["guid-3"], p1.id)

        model.deleteProject(p1)
        model.deleteProject(p2)
    }

    /// A dangling association (project deleted, guid entry not pruned) must not
    /// resolve to a project — lookup tolerates it. See DesignNotes §9 (low-priority
    /// pruning) and the project(id:) guard.
    func testDanglingAssociationResolvesToNil() {
        let model = iTermWindowProjectsModel.shared
        let project = model.createProject(named: "Dangling-Project")
        let danglingID = project.id

        model.testOnlyAssociations = ["ghost-guid": danglingID]
        model.deleteProject(project)

        // The association entry still exists, but the project is gone.
        XCTAssertEqual(model.testOnlyAssociations["ghost-guid"], danglingID)
        XCTAssertNil(model.project(id: danglingID))
    }
}

extension PTYSession {
    @objc(mock_tryToAttachToServerWithProcessId:tty:)
    func mock_tryToAttachToServerWithProcessId(_ serverPid: Int32, tty: NSString?) -> Bool {
        print("MOCK ATTACH TO SERVER CALLED successfully for pid \(serverPid)!")
        return true
    }
}

extension iTermAdvancedSettingsModel {
    @objc(mock_runJobsInServers)
    class func mock_runJobsInServers() -> Bool {
        print("MOCK RUN JOBS IN SERVERS CALLED successfully!")
        return true
    }
}

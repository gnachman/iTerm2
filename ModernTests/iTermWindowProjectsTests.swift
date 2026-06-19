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
    
    override func setUp() {
        super.setUp()
        let model = iTermWindowProjectsModel.shared
        // 1. Back up any existing in-memory projects
        savedProjects = model.rootProjects
        
        // 2. Clear rootProjects for a clean test environment by deleting them via the public API
        while !model.rootProjects.isEmpty {
            model.deleteProject(model.rootProjects[0])
        }
    }
    
    override func tearDown() {
        // Restore user's original projects back to the singleton
        iTermWindowProjectsModel.shared.testOnlySetRootProjects(savedProjects)
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
}

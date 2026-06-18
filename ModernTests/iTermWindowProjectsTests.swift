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
        
        // 2. Clear rootProjects for a clean test environment (loads from WindowProjects_test.json)
        model.rootProjects = []
    }
    
    override func tearDown() {
        // Restore user's original projects back to the singleton
        iTermWindowProjectsModel.shared.rootProjects = savedProjects
        super.tearDown()
    }
    
    func testProjectCRUD() {
        let model = iTermWindowProjectsModel.shared
        
        // 1. Verify initial clean slate
        XCTAssertEqual(model.rootProjects.count, 0)
        
        // 2. Create a root project
        let projectA = model.createProject(named: "Client-A")
        XCTAssertEqual(model.rootProjects.count, 1)
        XCTAssertEqual(model.rootProjects[0].name, "Client-A")
        XCTAssertEqual(model.rootProjects[0].id, projectA.id)
        
        // 3. Create a nested child project
        let subProject = model.createProject(named: "External-Pentest", parent: projectA)
        XCTAssertEqual(projectA.children.count, 1)
        XCTAssertEqual(projectA.children[0].name, "External-Pentest")
        XCTAssertEqual(projectA.children[0].id, subProject.id)
        
        // 4. Lookups
        let foundProject = model.project(id: subProject.id)
        XCTAssertNotNil(foundProject)
        XCTAssertEqual(foundProject?.name, "External-Pentest")
        
        // 5. Rename project
        model.renameProject(subProject, to: "Internal-Adversary")
        XCTAssertEqual(projectA.children[0].name, "Internal-Adversary")
        
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
        let archived = iTermArchivedWindow(name: "Scope-Scan", arrangement: dummyArrangement)
        XCTAssertEqual(archived.name, "Scope-Scan")
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
        let root = model.createProject(named: "RedTeam")
        let dummyArrangement: [AnyHashable: Any] = ["Columns": 80]
        
        let archivedWin = iTermArchivedWindow(name: "Hydra-Brute", arrangement: dummyArrangement)
        root.windows.append(archivedWin)
        
        // Verify we can find the archived window inside the tree
        let found = model.archivedWindow(id: archivedWin.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.0.name, "Hydra-Brute")
        XCTAssertEqual(found?.1.id, root.id)
        
        // Verify we find parent project of the window
        let parent = model.parentProject(of: archivedWin)
        XCTAssertEqual(parent?.id, root.id)
        
        // Remove archived window
        model.removeWindow(archivedWin, from: root)
        XCTAssertEqual(root.windows.count, 0)
        XCTAssertNil(model.archivedWindow(id: archivedWin.id))
    }
}

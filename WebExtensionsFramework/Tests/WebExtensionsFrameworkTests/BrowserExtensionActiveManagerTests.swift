import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionActiveManagerTests: XCTestCase {
    
    var manager: BrowserExtensionActiveManager!
    var testExtension: BrowserExtension!
    
    override func setUp() {
        super.setUp()
        manager = BrowserExtensionActiveManager()
        
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0"
        )
        
        let extensionURL = URL(fileURLWithPath: "/test/extension")
        testExtension = BrowserExtension(manifest: manifest, baseURL: extensionURL)
    }
    
    override func tearDown() {
        manager = nil
        testExtension = nil
        super.tearDown()
    }
    
    /// Test basic manager initialization
    func testManagerInitialization() {
        XCTAssertNotNil(manager)
    }
    
    /// Test activating an extension
    func testActivateExtension() async throws {
        try manager.activate(testExtension)
        
        let extensionId = testExtension.id
        let isActive = manager.isActive(extensionId)
        XCTAssertTrue(isActive)
    }
    
    /// Test getting an active extension
    func testGetActiveExtension() async throws {
        try manager.activate(testExtension)
        
        let extensionId = testExtension.id
        let activeExtension = manager.activeExtension(for: extensionId)
        XCTAssertNotNil(activeExtension)
        
        let browserExtensionId = activeExtension?.browserExtension.id
        let browserExtensionName = activeExtension?.browserExtension.manifest.name
        XCTAssertEqual(browserExtensionId, extensionId)
        XCTAssertEqual(browserExtensionName, "Test Extension")
    }
    
    /// Test that content world is created for extension
    func testContentWorldCreation() async throws {
        try manager.activate(testExtension)
        
        let extensionId = testExtension.id
        let activeExtension = manager.activeExtension(for: extensionId)
        XCTAssertNotNil(activeExtension)
        XCTAssertEqual(activeExtension?.contentWorld.name, "Extension-\(extensionId)")
    }
    
    /// Test activation timestamp
    func testActivationTimestamp() async throws {
        let beforeActivation = Date()
        try manager.activate(testExtension)
        let afterActivation = Date()
        
        let extensionId = testExtension.id
        let activeExtension = manager.activeExtension(for: extensionId)
        let activatedAt = activeExtension?.activatedAt
        
        XCTAssertNotNil(activatedAt)
        XCTAssertGreaterThanOrEqual(activatedAt!, beforeActivation)
        XCTAssertLessThanOrEqual(activatedAt!, afterActivation)
    }
    
    /// Test that activating the same extension twice throws an error
    func testActivateSameExtensionTwice() async throws {
        try manager.activate(testExtension)
        
        let expectedId = testExtension.id
        XCTAssertThrowsError(try manager.activate(testExtension)) { error in
            if case BrowserExtensionRegistryError.extensionAlreadyExists(let id) = error {
                XCTAssertEqual(id, expectedId)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    /// Test deactivating an extension
    func testDeactivateExtension() async throws {
        try manager.activate(testExtension)
        
        let extensionId = testExtension.id
        var isActive = manager.isActive(extensionId)
        XCTAssertTrue(isActive)
        
        manager.deactivate(extensionId)
        
        isActive = manager.isActive(extensionId)
        XCTAssertFalse(isActive)
        
        let activeExtension = manager.activeExtension(for: extensionId)
        XCTAssertNil(activeExtension)
    }
    
    /// Test getting all active extensions
    func testGetAllActiveExtensions() async throws {
        let manifest2 = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension 2",
            version: "1.0.0"
        )
        
        let extensionURL2 = URL(fileURLWithPath: "/test/extension2")
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: extensionURL2)
        
        try manager.activate(testExtension)
        try manager.activate(testExtension2)
        
        let allActive = manager.allActiveExtensions()
        XCTAssertEqual(allActive.count, 2)
        
        let extensionId1 = testExtension.id
        let extensionId2 = testExtension2.id
        XCTAssertNotNil(allActive[extensionId1])
        XCTAssertNotNil(allActive[extensionId2])
    }
    
    /// Test deactivating all extensions
    func testDeactivateAllExtensions() async throws {
        let manifest2 = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension 2",
            version: "1.0.0"
        )
        
        let extensionURL2 = URL(fileURLWithPath: "/test/extension2")
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: extensionURL2)
        
        try manager.activate(testExtension)
        try manager.activate(testExtension2)
        
        var allActive = manager.allActiveExtensions()
        XCTAssertEqual(allActive.count, 2)
        
        manager.deactivateAll()
        
        allActive = manager.allActiveExtensions()
        XCTAssertEqual(allActive.count, 0)
        
        let extensionId1 = testExtension.id
        let extensionId2 = testExtension2.id
        let isActive1 = manager.isActive(extensionId1)
        let isActive2 = manager.isActive(extensionId2)
        XCTAssertFalse(isActive1)
        XCTAssertFalse(isActive2)
    }
    
    /// Test checking if non-existent extension is active
    func testIsActiveForNonExistentExtension() {
        let isActive = manager.isActive("non-existent-extension")
        XCTAssertFalse(isActive)
    }
    
    /// Test getting non-existent active extension
    func testGetNonExistentActiveExtension() {
        let activeExtension = manager.activeExtension(for: "non-existent-extension")
        XCTAssertNil(activeExtension)
    }
}

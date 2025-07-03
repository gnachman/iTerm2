import XCTest
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionRegistryTests: XCTestCase {
    
    func testAddExtensionSuccess() async {
        // Create a temporary extension directory
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        // Create manifest.json
        let manifestJSON = """
        {
          "manifest_version": 3,
          "name": "Test Extension",
          "version": "1.0",
          "description": "Test extension"
        }
        """
        let manifestURL = tempURL.appendingPathComponent("manifest.json")
        try! manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)
        
        let registry = BrowserExtensionRegistry()
        
        // Add extension
        try! registry.add(extensionPath: tempURL.path)
        
        // Verify it was added
        let extensions = registry.extensions
        XCTAssertEqual(extensions.count, 1)
        
        let browserExtension = extensions.first!
        let manifest = browserExtension.manifest
        XCTAssertEqual(manifest.name, "Test Extension")
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testAddExtensionDuplicatePath() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        let manifestJSON = """
        {
          "manifest_version": 3,
          "name": "Test Extension",
          "version": "1.0"
        }
        """
        let manifestURL = tempURL.appendingPathComponent("manifest.json")
        try! manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)
        
        let registry = BrowserExtensionRegistry()
        
        // Add extension first time
        try! registry.add(extensionPath: tempURL.path)
        
        // Try to add same path again
        do {
            try registry.add(extensionPath: tempURL.path)
            XCTFail("Expected error to be thrown")
        } catch BrowserExtensionRegistryError.extensionAlreadyExists(let path) {
            XCTAssertEqual(path, tempURL.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Verify only one extension exists
        let extensions = registry.extensions
        XCTAssertEqual(extensions.count, 1)
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testAddExtensionMissingManifest() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        let registry = BrowserExtensionRegistry()
        
        do {
            try registry.add(extensionPath: tempURL.path)
            XCTFail("Expected error to be thrown")
        } catch {
            // Should throw some error for missing manifest
            XCTAssertTrue(true)
        }
        
        // Verify no extensions were added
        let extensions = registry.extensions
        XCTAssertEqual(extensions.count, 0)
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testExtensionsCollection() async {
        let registry = BrowserExtensionRegistry()
        
        // Initially empty
        let initialExtensions = registry.extensions
        XCTAssertEqual(initialExtensions.count, 0)
        
        // Create and add two extensions
        let tempURL1 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tempURL2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(at: tempURL1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: tempURL2, withIntermediateDirectories: true)
        
        let manifest1 = """
        {
          "manifest_version": 3,
          "name": "Extension 1",
          "version": "1.0"
        }
        """
        let manifest2 = """
        {
          "manifest_version": 3,
          "name": "Extension 2",
          "version": "2.0"
        }
        """
        
        try! manifest1.write(to: tempURL1.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try! manifest2.write(to: tempURL2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        
        try! registry.add(extensionPath: tempURL1.path)
        try! registry.add(extensionPath: tempURL2.path)
        
        let extensions = registry.extensions
        XCTAssertEqual(extensions.count, 2)
        
        // Verify both extensions are present
        let names = extensions.map { $0.manifest.name }.sorted()
        
        XCTAssertEqual(names, ["Extension 1", "Extension 2"])
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL1)
        try! FileManager.default.removeItem(at: tempURL2)
    }
    
    func testNotificationPosting() async {
        let registry = BrowserExtensionRegistry()
        
        // Set up notification expectation
        let expectation = XCTestExpectation(description: "Registry changed notification")
        let observer = NotificationCenter.default.addObserver(
            forName: BrowserExtensionRegistry.registryDidChangeNotification,
            object: registry,
            queue: .main
        ) { notification in
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Create extension
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        let manifestJSON = """
        {
          "manifest_version": 3,
          "name": "Test Extension",
          "version": "1.0"
        }
        """
        try! manifestJSON.write(to: tempURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        
        // Add extension (should post notification)
        try! registry.add(extensionPath: tempURL.path)
        
        // Wait for notification
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testAddRedBoxExtension() async {
        // Create a temporary red-box extension
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        // Copy the actual red-box manifest
        let manifestJSON = """
        {
          "manifest_version": 3,
          "name": "Red Box",
          "version": "1.0",
          "description": "Adds a red box to the top of every page",
          
          "content_scripts": [{
            "matches": ["<all_urls>"],
            "js": ["content.js"],
            "run_at": "document_end"
          }]
        }
        """
        try! manifestJSON.write(to: tempURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        
        // Create content.js file
        let contentJS = """
        // Red box content script
        const redBox = document.createElement('div');
        redBox.style.position = 'fixed';
        redBox.style.top = '10px';
        redBox.style.left = '10px';
        redBox.style.width = '100px';
        redBox.style.height = '100px';
        redBox.style.backgroundColor = 'red';
        redBox.style.zIndex = '9999';
        document.body.appendChild(redBox);
        """
        try! contentJS.write(to: tempURL.appendingPathComponent("content.js"), atomically: true, encoding: .utf8)
        
        let registry = BrowserExtensionRegistry()
        
        // Add the red-box extension
        try! registry.add(extensionPath: tempURL.path)
        
        // Verify it was added and has correct properties
        let extensions = registry.extensions
        XCTAssertEqual(extensions.count, 1)
        
        let browserExtension = extensions.first!
        let manifest = browserExtension.manifest
        XCTAssertEqual(manifest.name, "Red Box")
        XCTAssertEqual(manifest.version, "1.0")
        XCTAssertEqual(manifest.description, "Adds a red box to the top of every page")
        XCTAssertEqual(manifest.contentScripts?.count, 1)
        
        let contentScript = manifest.contentScripts![0]
        XCTAssertEqual(contentScript.matches, ["<all_urls>"])
        XCTAssertEqual(contentScript.js, ["content.js"])
        XCTAssertEqual(contentScript.runAt, .documentEnd)
        
        // Verify content scripts were automatically loaded
        let resources = browserExtension.contentScriptResources
        XCTAssertEqual(resources.count, 1)
        
        let resource = resources[0]
        XCTAssertEqual(resource.jsContent.count, 1)
        XCTAssertTrue(resource.jsContent[0].contains("redBox"))
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testRemoveExtensionSuccess() async {
        // Create a temporary extension directory
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        // Create manifest.json
        let manifestJSON = """
        {
          "manifest_version": 3,
          "name": "Test Extension",
          "version": "1.0",
          "description": "Test extension"
        }
        """
        let manifestURL = tempURL.appendingPathComponent("manifest.json")
        try! manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)
        
        let registry = BrowserExtensionRegistry()
        
        // Add extension
        try! registry.add(extensionPath: tempURL.path)
        
        // Verify it was added
        let extensionsBeforeRemove = registry.extensions
        XCTAssertEqual(extensionsBeforeRemove.count, 1)
        
        // Remove extension
        try! registry.remove(extensionPath: tempURL.path)
        
        // Verify it was removed
        let extensionsAfterRemove = registry.extensions
        XCTAssertEqual(extensionsAfterRemove.count, 0)
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testRemoveExtensionNotFound() async {
        let registry = BrowserExtensionRegistry()
        
        // Try to remove extension that doesn't exist
        do {
            try registry.remove(extensionPath: "/nonexistent/path")
            XCTFail("Expected error to be thrown")
        } catch BrowserExtensionRegistryError.extensionNotFound(let path) {
            XCTAssertEqual(path, "/nonexistent/path")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Verify no extensions exist
        let extensions = registry.extensions
        XCTAssertEqual(extensions.count, 0)
    }
    
    func testRemoveExtensionPostsNotification() async {
        let registry = BrowserExtensionRegistry()
        
        // Create extension
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        let manifestJSON = """
        {
          "manifest_version": 3,
          "name": "Test Extension",
          "version": "1.0"
        }
        """
        try! manifestJSON.write(to: tempURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        
        // Add extension first
        try! registry.add(extensionPath: tempURL.path)
        
        // Set up notification expectation for removal
        let expectation = XCTestExpectation(description: "Registry changed notification on removal")
        let observer = NotificationCenter.default.addObserver(
            forName: BrowserExtensionRegistry.registryDidChangeNotification,
            object: registry,
            queue: .main
        ) { notification in
            expectation.fulfill()
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Remove extension (should post notification)
        try! registry.remove(extensionPath: tempURL.path)
        
        // Wait for notification
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testRemoveOneOfMultipleExtensions() async {
        let registry = BrowserExtensionRegistry()
        
        // Create two extensions
        let tempURL1 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tempURL2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(at: tempURL1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: tempURL2, withIntermediateDirectories: true)
        
        let manifest1 = """
        {
          "manifest_version": 3,
          "name": "Extension 1",
          "version": "1.0"
        }
        """
        let manifest2 = """
        {
          "manifest_version": 3,
          "name": "Extension 2",
          "version": "2.0"
        }
        """
        
        try! manifest1.write(to: tempURL1.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try! manifest2.write(to: tempURL2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        
        // Add both extensions
        try! registry.add(extensionPath: tempURL1.path)
        try! registry.add(extensionPath: tempURL2.path)
        
        // Verify both are added
        let extensionsBeforeRemove = registry.extensions
        XCTAssertEqual(extensionsBeforeRemove.count, 2)
        
        // Remove one extension
        try! registry.remove(extensionPath: tempURL1.path)
        
        // Verify only one remains
        let extensionsAfterRemove = registry.extensions
        XCTAssertEqual(extensionsAfterRemove.count, 1)
        
        // Verify the remaining extension is the correct one
        let remainingExtension = extensionsAfterRemove.first!
        let remainingManifest = remainingExtension.manifest
        XCTAssertEqual(remainingManifest.name, "Extension 2")
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL1)
        try! FileManager.default.removeItem(at: tempURL2)
    }
}
import XCTest
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionTests: XCTestCase {
    
    func testExtensionInitialization() async {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0"
        )
        let extensionURL = URL(fileURLWithPath: "/test/path")
        
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: extensionURL)
        
        let actualManifest = browserExtension.manifest
        let actualBaseURL = browserExtension.baseURL
        let actualID = browserExtension.id
        
        XCTAssertEqual(actualManifest.name, "Test Extension")
        XCTAssertEqual(actualBaseURL, extensionURL)
        XCTAssertFalse(actualID.isEmpty)
    }
    
    func testExtensionUniqueIDs() async {
        let manifest1 = ExtensionManifest(
            manifestVersion: 3,
            name: "Extension 1",
            version: "1.0"
        )
        let manifest2 = ExtensionManifest(
            manifestVersion: 3,
            name: "Extension 2",
            version: "1.0"
        )
        
        let extension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/path1"))
        let extension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/path2"))
        
        let id1 = extension1.id
        let id2 = extension2.id
        
        XCTAssertNotEqual(id1, id2)
    }
    
    func testContentScriptLoadingSuccess() async {
        // Create a temporary directory with a content script
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        // Create content.js file
        let contentJSURL = tempURL.appendingPathComponent("content.js")
        let jsContent = "console.log('Red box extension loaded');"
        try! jsContent.write(to: contentJSURL, atomically: true, encoding: .utf8)
        
        // Create manifest with content script
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0",
            description: nil,
            contentScripts: [ContentScript(
                matches: ["<all_urls>"],
                js: ["content.js"],
                css: nil,
                runAt: .documentEnd,
                allFrames: nil,
                world: nil,
                excludeMatches: nil,
                includeGlobs: nil,
                excludeGlobs: nil,
                matchAboutBlank: nil,
                matchOriginAsFallback: nil
            )]
        )
        
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: tempURL)
        
        // Load content scripts
        try! browserExtension.loadContentScripts()
        
        // Verify content was loaded
        let resources = browserExtension.contentScriptResources
        XCTAssertEqual(resources.count, 1)
        
        let resource = resources[0]
        XCTAssertEqual(resource.jsContent.count, 1)
        XCTAssertEqual(resource.jsContent[0], jsContent)
        XCTAssertEqual(resource.config.matches, ["<all_urls>"])
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testContentScriptLoadingFileNotFound() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0",
            description: nil,
            contentScripts: [ContentScript(
                matches: ["<all_urls>"],
                js: ["missing.js"],
                css: nil,
                runAt: nil,
                allFrames: nil,
                world: nil,
                excludeMatches: nil,
                includeGlobs: nil,
                excludeGlobs: nil,
                matchAboutBlank: nil,
                matchOriginAsFallback: nil
            )]
        )
        
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: tempURL)
        
        do {
            try browserExtension.loadContentScripts()
            XCTFail("Expected error to be thrown")
        } catch ContentScriptLoadingError.fileNotFound(let path) {
            XCTAssertEqual(path, "missing.js")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testContentScriptLoadingNoScripts() async {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0"
        )
        
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: URL(fileURLWithPath: "/tmp"))
        
        try! browserExtension.loadContentScripts()
        
        let resources = browserExtension.contentScriptResources
        XCTAssertEqual(resources.count, 0)
    }
}

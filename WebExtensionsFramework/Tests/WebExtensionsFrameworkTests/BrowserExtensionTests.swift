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
    
    // MARK: - Background Script Loading Tests
    
    func testBackgroundScriptLoadingServiceWorker() async {
        // Create a temporary directory with a background script
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        // Create background.js file
        let backgroundJSURL = tempURL.appendingPathComponent("background.js")
        let jsContent = "console.log('Background service worker loaded');"
        try! jsContent.write(to: backgroundJSURL, atomically: true, encoding: .utf8)
        
        // Create manifest with service worker
        let backgroundScript = BackgroundScript(
            serviceWorker: "background.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0",
            description: nil,
            contentScripts: nil,
            background: backgroundScript
        )
        
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: tempURL)
        
        // Load background script
        try! browserExtension.loadBackgroundScript()
        
        // Verify background script was loaded
        let resource = browserExtension.backgroundScriptResource
        XCTAssertNotNil(resource)
        XCTAssertEqual(resource?.jsContent, jsContent)
        XCTAssertTrue(resource?.isServiceWorker ?? false)
        XCTAssertEqual(resource?.config.serviceWorker, "background.js")
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testBackgroundScriptLoadingLegacyScripts() async {
        // Create a temporary directory with background scripts
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        // Create background script files
        let bg1URL = tempURL.appendingPathComponent("background1.js")
        let bg1Content = "console.log('Background script 1');"
        try! bg1Content.write(to: bg1URL, atomically: true, encoding: .utf8)
        
        let bg2URL = tempURL.appendingPathComponent("background2.js")
        let bg2Content = "console.log('Background script 2');"
        try! bg2Content.write(to: bg2URL, atomically: true, encoding: .utf8)
        
        // Create manifest with legacy scripts array
        let backgroundScript = BackgroundScript(
            serviceWorker: nil,
            scripts: ["background1.js", "background2.js"],
            persistent: false,
            type: nil
        )
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0",
            description: nil,
            contentScripts: nil,
            background: backgroundScript
        )
        
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: tempURL)
        
        // Load background script
        try! browserExtension.loadBackgroundScript()
        
        // Verify background scripts were loaded and concatenated
        let resource = browserExtension.backgroundScriptResource
        XCTAssertNotNil(resource)
        XCTAssertFalse(resource?.isServiceWorker ?? true)
        XCTAssertEqual(resource?.config.scripts, ["background1.js", "background2.js"])
        
        let expectedContent = bg1Content + "\n\n" + bg2Content
        XCTAssertEqual(resource?.jsContent, expectedContent)
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
    
    func testBackgroundScriptLoadingNoBackground() async {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0"
        )
        
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: URL(fileURLWithPath: "/tmp"))
        
        try! browserExtension.loadBackgroundScript()
        
        XCTAssertNil(browserExtension.backgroundScriptResource)
    }
    
    func testBackgroundScriptLoadingFileNotFound() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        let backgroundScript = BackgroundScript(
            serviceWorker: "missing.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0",
            description: nil,
            contentScripts: nil,
            background: backgroundScript
        )
        
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: tempURL)
        
        do {
            try browserExtension.loadBackgroundScript()
            XCTFail("Expected error to be thrown")
        } catch ContentScriptLoadingError.fileNotFound(let path) {
            XCTAssertEqual(path, "missing.js")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Cleanup
        try! FileManager.default.removeItem(at: tempURL)
    }
}

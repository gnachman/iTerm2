import XCTest
@testable import WebExtensionsFramework

final class RedBoxExtensionTests: XCTestCase {
    
    func testRedBoxExtensionManifestParsing() {
        let json = """
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
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        // Verify all fields are parsed correctly
        XCTAssertEqual(manifest.manifestVersion, 3)
        XCTAssertEqual(manifest.name, "Red Box")
        XCTAssertEqual(manifest.version, "1.0")
        XCTAssertEqual(manifest.description, "Adds a red box to the top of every page")
        
        // Verify content scripts
        XCTAssertEqual(manifest.contentScripts?.count, 1)
        let contentScript = manifest.contentScripts![0]
        XCTAssertEqual(contentScript.matches, ["<all_urls>"])
        XCTAssertEqual(contentScript.js, ["content.js"])
        XCTAssertEqual(contentScript.runAt, .documentEnd)
        
        // Verify validation passes
        let validator = ManifestValidator(logger: createTestLogger())
        XCTAssertNoThrow(try validator.validate(manifest))
    }
    
    func testActualRedBoxManifestFile() {
        // This is the exact content from test-extensions/red-box/manifest.json
        let actualManifestJSON = """
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
        
        let data = actualManifestJSON.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        // Verify our parser handles the real manifest correctly
        XCTAssertEqual(manifest.manifestVersion, 3)
        XCTAssertEqual(manifest.name, "Red Box")
        XCTAssertEqual(manifest.version, "1.0")
        XCTAssertEqual(manifest.description, "Adds a red box to the top of every page")
        
        XCTAssertEqual(manifest.contentScripts?.count, 1)
        let contentScript = manifest.contentScripts![0]
        XCTAssertEqual(contentScript.matches, ["<all_urls>"])
        XCTAssertEqual(contentScript.js, ["content.js"])
        XCTAssertEqual(contentScript.runAt, .documentEnd)
        
        // Verify the real manifest validates successfully
        let validator = ManifestValidator(logger: createTestLogger())
        XCTAssertNoThrow(try validator.validate(manifest))
    }
}
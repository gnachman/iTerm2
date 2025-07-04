import XCTest
@testable import WebExtensionsFramework

final class ExtensionManifestTests: XCTestCase {
    
    // MARK: - manifest_version tests (manifest_version.md)
    
    func testManifestVersionDecoding() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertEqual(manifest.manifestVersion, 3)
    }
    
    
    func testManifestVersionRequired() {
        let json = """
        {
        }
        """
        
        let data = json.data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(ExtensionManifest.self, from: data))
    }
    
    // MARK: - name tests (name.md)
    
    func testNameDecoding() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Red Box",
            "version": "1.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertEqual(manifest.name, "Red Box")
    }
    
    func testNameRequired() {
        let json = """
        {
            "manifest_version": 3
        }
        """
        
        let data = json.data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(ExtensionManifest.self, from: data))
    }
    
    // MARK: - version tests (version.md)
    
    func testVersionDecoding() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Red Box",
            "version": "1.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertEqual(manifest.version, "1.0")
    }
    
    func testVersionRequired() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension"
        }
        """
        
        let data = json.data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(ExtensionManifest.self, from: data))
    }
    
    // MARK: - description tests (description.md)
    
    func testDescriptionDecoding() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Red Box",
            "version": "1.0",
            "description": "Adds a red box to the top of every page"
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertEqual(manifest.description, "Adds a red box to the top of every page")
    }
    
    func testDescriptionOptional() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertNil(manifest.description)
    }
    
    // MARK: - content_scripts tests (content_scripts.md)
    
    func testContentScriptsDecoding() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Red Box",
            "version": "1.0",
            "content_scripts": [{
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_end"
            }]
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertEqual(manifest.contentScripts?.count, 1)
        let contentScript = manifest.contentScripts![0]
        XCTAssertEqual(contentScript.matches, ["<all_urls>"])
        XCTAssertEqual(contentScript.js, ["content.js"])
        XCTAssertEqual(contentScript.runAt, .documentEnd)
    }
    
    func testContentScriptsOptional() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertNil(manifest.contentScripts)
    }
    
    func testContentScriptsMinimalRequired() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0",
            "content_scripts": [{
                "matches": ["https://example.com/*"]
            }]
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertEqual(manifest.contentScripts?.count, 1)
        let contentScript = manifest.contentScripts![0]
        XCTAssertEqual(contentScript.matches, ["https://example.com/*"])
        XCTAssertNil(contentScript.js)
        XCTAssertNil(contentScript.css)
        XCTAssertNil(contentScript.runAt)
    }
    
    // MARK: - background tests (background.md)
    
    func testBackgroundServiceWorkerDecoding() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0",
            "background": {
                "service_worker": "background.js"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertNotNil(manifest.background)
        XCTAssertEqual(manifest.background?.serviceWorker, "background.js")
        XCTAssertNil(manifest.background?.scripts)
        XCTAssertNil(manifest.background?.persistent)
        XCTAssertNil(manifest.background?.type)
    }
    
    func testBackgroundLegacyScriptsDecoding() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0",
            "background": {
                "scripts": ["background.js", "utils.js"],
                "persistent": false
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertNotNil(manifest.background)
        XCTAssertNil(manifest.background?.serviceWorker)
        XCTAssertEqual(manifest.background?.scripts, ["background.js", "utils.js"])
        XCTAssertEqual(manifest.background?.persistent, false)
        XCTAssertNil(manifest.background?.type)
    }
    
    func testBackgroundWithTypeDecoding() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0",
            "background": {
                "service_worker": "background.js",
                "type": "module"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertNotNil(manifest.background)
        XCTAssertEqual(manifest.background?.serviceWorker, "background.js")
        XCTAssertEqual(manifest.background?.type, "module")
    }
    
    func testBackgroundOptional() {
        let json = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let manifest = try! JSONDecoder().decode(ExtensionManifest.self, from: data)
        
        XCTAssertNil(manifest.background)
    }
}
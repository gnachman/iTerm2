import XCTest
@testable import WebExtensionsFramework

final class ManifestValidatorTests: XCTestCase {
    
    func testValidManifestVersion() {
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0")
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertNoThrow(try validator.validate(manifest))
    }
    
    func testInvalidManifestVersionTooLow() {
        let manifest = ExtensionManifest(manifestVersion: 2, name: "Test Extension", version: "1.0")
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if let validationError = error as? ManifestValidationError {
                XCTAssertEqual(validationError, .invalidManifestVersion(2))
            }
        }
    }
    
    func testInvalidManifestVersionTooHigh() {
        let manifest = ExtensionManifest(manifestVersion: 4, name: "Test Extension", version: "1.0")
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if let validationError = error as? ManifestValidationError {
                XCTAssertEqual(validationError, .invalidManifestVersion(4))
            }
        }
    }
    
    // MARK: - Background Script Validation Tests
    
    func testValidBackgroundServiceWorker() {
        let backgroundScript = BackgroundScript(serviceWorker: "background.js", scripts: nil, persistent: nil, type: nil)
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertNoThrow(try validator.validate(manifest))
    }
    
    func testValidBackgroundScripts() {
        let backgroundScript = BackgroundScript(serviceWorker: nil, scripts: ["background.js", "utils.js"], persistent: false, type: nil)
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertNoThrow(try validator.validate(manifest))
    }
    
    func testValidBackgroundWithModuleType() {
        let backgroundScript = BackgroundScript(serviceWorker: "background.js", scripts: nil, persistent: nil, type: "module")
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertNoThrow(try validator.validate(manifest))
    }
    
    func testBackgroundOptional() {
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0")
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertNoThrow(try validator.validate(manifest))
    }
    
    func testInvalidBackgroundNeitherServiceWorkerNorScripts() {
        let backgroundScript = BackgroundScript(serviceWorker: nil, scripts: nil, persistent: nil, type: nil)
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if case .invalidBackgroundScript(let message) = error as? ManifestValidationError {
                XCTAssertEqual(message, "Either 'service_worker' or 'scripts' must be specified")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testInvalidBackgroundBothServiceWorkerAndScripts() {
        let backgroundScript = BackgroundScript(serviceWorker: "background.js", scripts: ["background.js"], persistent: nil, type: nil)
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if case .backgroundScriptConflict(let message) = error as? ManifestValidationError {
                XCTAssertEqual(message, "Cannot specify both 'service_worker' and 'scripts' fields")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testInvalidBackgroundServiceWorkerNotJsFile() {
        let backgroundScript = BackgroundScript(serviceWorker: "background.ts", scripts: nil, persistent: nil, type: nil)
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if case .invalidBackgroundScript(let message) = error as? ManifestValidationError {
                XCTAssertEqual(message, "Service worker must be a .js file: background.ts")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testInvalidBackgroundScriptNotJsFile() {
        let backgroundScript = BackgroundScript(serviceWorker: nil, scripts: ["background.js", "utils.ts"], persistent: nil, type: nil)
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if case .invalidBackgroundScript(let message) = error as? ManifestValidationError {
                XCTAssertEqual(message, "Background script must be a .js file: utils.ts")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testInvalidBackgroundType() {
        let backgroundScript = BackgroundScript(serviceWorker: "background.js", scripts: nil, persistent: nil, type: "invalid")
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if case .invalidBackgroundScript(let message) = error as? ManifestValidationError {
                XCTAssertEqual(message, "Invalid background script type: invalid. Must be 'classic' or 'module'")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testValidBackgroundEmptyScriptsArray() {
        let backgroundScript = BackgroundScript(serviceWorker: nil, scripts: [], persistent: nil, type: nil)
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0", description: nil, contentScripts: nil, background: backgroundScript)
        let validator = ManifestValidator(logger: createTestLogger())
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if case .invalidBackgroundScript(let message) = error as? ManifestValidationError {
                XCTAssertEqual(message, "Either 'service_worker' or 'scripts' must be specified")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
}
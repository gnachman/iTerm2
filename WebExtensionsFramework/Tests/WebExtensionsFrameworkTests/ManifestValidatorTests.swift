import XCTest
@testable import WebExtensionsFramework

final class ManifestValidatorTests: XCTestCase {
    
    func testValidManifestVersion() {
        let manifest = ExtensionManifest(manifestVersion: 3, name: "Test Extension", version: "1.0")
        let validator = ManifestValidator()
        
        XCTAssertNoThrow(try validator.validate(manifest))
    }
    
    func testInvalidManifestVersionTooLow() {
        let manifest = ExtensionManifest(manifestVersion: 2, name: "Test Extension", version: "1.0")
        let validator = ManifestValidator()
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if let validationError = error as? ManifestValidationError {
                XCTAssertEqual(validationError, .invalidManifestVersion(2))
            }
        }
    }
    
    func testInvalidManifestVersionTooHigh() {
        let manifest = ExtensionManifest(manifestVersion: 4, name: "Test Extension", version: "1.0")
        let validator = ManifestValidator()
        
        XCTAssertThrowsError(try validator.validate(manifest)) { error in
            XCTAssertTrue(error is ManifestValidationError)
            if let validationError = error as? ManifestValidationError {
                XCTAssertEqual(validationError, .invalidManifestVersion(4))
            }
        }
    }
}
import XCTest
@testable import WebExtensionsFramework

final class BrowserExtensionPermissionTests: XCTestCase {
    
    // MARK: - Parsing Tests
    
    func testParseKnownAPIPermission() {
        let permission = BrowserExtensionPermissionParser.parse("storage")
        XCTAssertEqual(permission, .api(.storage))
    }
    
    func testParseKnownAPIPermissionWithDot() {
        let permission = BrowserExtensionPermissionParser.parse("system.cpu")
        XCTAssertEqual(permission, .api(.system_cpu))
    }
    
    func testParseUnknownPermission() {
        let permission = BrowserExtensionPermissionParser.parse("futureApiPermission")
        XCTAssertEqual(permission, .unknown("futureApiPermission"))
    }
    
    func testParseMultiplePermissions() {
        let permissions = BrowserExtensionPermissionParser.parse([
            "storage",
            "tabs",
            "unknownPermission",
            "system.memory"
        ])
        
        XCTAssertEqual(permissions, [
            .api(.storage),
            .api(.tabs),
            .unknown("unknownPermission"),
            .api(.system_memory)
        ])
    }
    
    func testIsKnownPermission() {
        XCTAssertTrue(BrowserExtensionPermissionParser.isKnownPermission("storage"))
        XCTAssertTrue(BrowserExtensionPermissionParser.isKnownPermission("tabs"))
        XCTAssertTrue(BrowserExtensionPermissionParser.isKnownPermission("system.cpu"))
        XCTAssertFalse(BrowserExtensionPermissionParser.isKnownPermission("unknownApi"))
    }
    
    func testAllKnownPermissions() {
        let allPermissions = BrowserExtensionPermissionParser.allKnownPermissions
        XCTAssertTrue(allPermissions.contains("storage"))
        XCTAssertTrue(allPermissions.contains("tabs"))
        XCTAssertTrue(allPermissions.contains("system.cpu"))
        XCTAssertTrue(allPermissions.contains("downloads.beta"))
    }
    
    // MARK: - ExtensionManifest Integration Tests
    
    func testManifestParsedPermissions() {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test",
            version: "1.0",
            description: nil,
            contentScripts: nil,
            background: nil,
            permissions: ["storage", "tabs", "futureApi"],
            hostPermissions: nil,
            optionalPermissions: nil,
            optionalHostPermissions: nil
        )
        
        let parsed = manifest.parsedPermissions
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed, [
            .api(.storage),
            .api(.tabs),
            .unknown("futureApi")
        ])
    }
    
    func testManifestHasPermission() {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test",
            version: "1.0",
            description: nil,
            contentScripts: nil,
            background: nil,
            permissions: ["storage", "tabs"],
            hostPermissions: nil,
            optionalPermissions: nil,
            optionalHostPermissions: nil
        )
        
        XCTAssertTrue(manifest.hasPermission(.storage))
        XCTAssertTrue(manifest.hasPermission(.tabs))
        XCTAssertFalse(manifest.hasPermission(.cookies))
    }
    
    func testManifestUnknownPermissions() {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test",
            version: "1.0",
            description: nil,
            contentScripts: nil,
            background: nil,
            permissions: ["storage", "futureApi1", "tabs", "futureApi2"],
            hostPermissions: nil,
            optionalPermissions: nil,
            optionalHostPermissions: nil
        )
        
        let unknown = manifest.unknownPermissions
        XCTAssertNotNil(unknown)
        XCTAssertEqual(unknown, ["futureApi1", "futureApi2"])
    }
    
    func testManifestNoPermissions() {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test",
            version: "1.0"
        )
        
        XCTAssertNil(manifest.parsedPermissions)
        XCTAssertFalse(manifest.hasPermission(.storage))
        XCTAssertNil(manifest.unknownPermissions)
    }
    
    // MARK: - Special Permission Cases
    
    func testPermissionsWithSpecialCharacters() {
        let testCases = [
            ("downloads.beta", BrowserExtensionAPIPermission.downloadsBeta),
            ("identity.email", .identityEmail),
            ("enterprise.deviceAttributes", .enterprise_deviceAttributes),
            ("webRequestFilterResponse.extraHeaders", .webRequestFilterResponse_extraHeaders)
        ]
        
        for (permissionString, expectedEnum) in testCases {
            let parsed = BrowserExtensionPermissionParser.parse(permissionString)
            XCTAssertEqual(parsed, .api(expectedEnum))
        }
    }
}
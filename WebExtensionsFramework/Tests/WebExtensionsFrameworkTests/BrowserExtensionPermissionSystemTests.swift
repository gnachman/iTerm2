import XCTest
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionPermissionSystemTests: XCTestCase {
    
    func testPermissionCheckingInfrastructure() throws {
        // Test the basic permission checking infrastructure
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0",
            description: nil,
            contentScripts: nil,
            background: nil,
            permissions: ["storage", "tabs"],
            hostPermissions: nil,
            optionalPermissions: nil,
            optionalHostPermissions: nil
        )
        
        let logger = createTestLogger()
        let browserExtension = BrowserExtension(
            manifest: manifest,
            baseDirectory: URL(fileURLWithPath: "/test"),
            extensionLocation: "extension",
            logger: logger
        )
        let context = BrowserExtensionContext(
            logger: logger,
            router: createMockRouter(),
            webView: nil,
            browserExtension: browserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(browserExtension.id)
        )
        
        // Should succeed for permissions the extension has
        XCTAssertNoThrow(try context.requirePermissions([BrowserExtensionAPIPermission.storage]))
        XCTAssertNoThrow(try context.requirePermissions([BrowserExtensionAPIPermission.tabs]))
        XCTAssertNoThrow(try context.requirePermissions([BrowserExtensionAPIPermission.storage, BrowserExtensionAPIPermission.tabs]))
        XCTAssertNoThrow(try context.requirePermissions([])) // No permissions required
        
        // Should fail for permissions the extension doesn't have
        XCTAssertThrowsError(try context.requirePermissions([BrowserExtensionAPIPermission.cookies])) { error in
            XCTAssertEqual(error as? BrowserExtensionError, .insufficientPermissions("cookies"))
        }
        
        XCTAssertThrowsError(try context.requirePermissions([BrowserExtensionAPIPermission.storage, BrowserExtensionAPIPermission.cookies])) { error in
            XCTAssertEqual(error as? BrowserExtensionError, .insufficientPermissions("cookies"))
        }
    }
    
    func testHasPermissionMethod() throws {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0",
            description: nil,
            contentScripts: nil,
            background: nil,
            permissions: ["storage"],
            hostPermissions: nil,
            optionalPermissions: nil,
            optionalHostPermissions: nil
        )
        
        let logger = createTestLogger()
        let browserExtension = BrowserExtension(
            manifest: manifest,
            baseDirectory: URL(fileURLWithPath: "/test"),
            extensionLocation: "extension",
            logger: logger
        )
        let context = BrowserExtensionContext(
            logger: logger,
            router: createMockRouter(),
            webView: nil,
            browserExtension: browserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(browserExtension.id)
        )
        
        XCTAssertTrue(context.hasPermission(BrowserExtensionAPIPermission.storage))
        XCTAssertFalse(context.hasPermission(BrowserExtensionAPIPermission.tabs))
        XCTAssertFalse(context.hasPermission(BrowserExtensionAPIPermission.cookies))
    }
    
    func testNoPermissionsRequired() throws {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0"
        ) // No permissions
        
        let logger = createTestLogger()
        let browserExtension = BrowserExtension(
            manifest: manifest,
            baseDirectory: URL(fileURLWithPath: "/test"),
            extensionLocation: "extension",
            logger: logger
        )
        let context = BrowserExtensionContext(
            logger: logger,
            router: createMockRouter(),
            webView: nil,
            browserExtension: browserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(browserExtension.id)
        )
        
        // Should succeed for empty permissions array
        XCTAssertNoThrow(try context.requirePermissions([]))
        
        // Should fail for any actual permission
        XCTAssertThrowsError(try context.requirePermissions([BrowserExtensionAPIPermission.storage])) { error in
            XCTAssertEqual(error as? BrowserExtensionError, .insufficientPermissions("storage"))
        }
    }
    
    func testCurrentAPIHandlersRequireNoPermissions() {
        // Test that our current handlers properly implement the permission system
        let sendMessageHandler = RuntimeSendMessageHandler()
        let getPlatformInfoHandler = RuntimeGetPlatformInfoHandler()
        
        // Both current handlers should require no permissions
        XCTAssertEqual(sendMessageHandler.requiredPermissions, [])
        XCTAssertEqual(getPlatformInfoHandler.requiredPermissions, [])
    }
    
    func testPermissionErrorMessage() {
        let error = BrowserExtensionError.insufficientPermissions("storage")
        XCTAssertEqual(
            error.errorDescription,
            "This extension does not have permission to use storage. Add \"storage\" to the \"permissions\" array in the manifest."
        )
    }
}

// MARK: - Helper functions

@MainActor
private func createMockRouter() -> BrowserExtensionRouter {
    // Create a minimal mock router for testing
    let mockNetwork = BrowserExtensionNetwork()
    return BrowserExtensionRouter(network: mockNetwork, logger: createTestLogger())
}
import XCTest
@testable import WebExtensionsFramework
@testable import BrowserExtensionShared

@MainActor
final class StorageHandlerTests: XCTestCase {
    
    var mockStorageProvider: MockBrowserExtensionStorageProvider!
    var storageManager: BrowserExtensionStorageManager!
    var mockLogger: BrowserExtensionLogger!
    var mockBrowserExtension: BrowserExtension!
    var context: BrowserExtensionContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockLogger = createTestLogger()
        mockStorageProvider = MockBrowserExtensionStorageProvider()
        storageManager = BrowserExtensionStorageManager(logger: mockLogger)
        storageManager.storageProvider = mockStorageProvider
        
        // Create extension with storage permission
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0",
            description: "Test extension for storage",
            permissions: ["storage"]
        )
        
        mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseDirectory: URL(fileURLWithPath: "/tmp"),
            extensionLocation: "test-extension",
            logger: mockLogger
        )
        
        // Create context as trusted (background script)
        context = BrowserExtensionContext(
            logger: mockLogger,
            router: createMockRouter(),
            webView: nil,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(mockBrowserExtension.id)
        )
    }
    
    override func tearDown() async throws {
        mockStorageProvider.reset()
        mockStorageProvider = nil
        storageManager = nil
        mockLogger = nil
        mockBrowserExtension = nil
        context = nil
        try await super.tearDown()
    }
    
    // MARK: - Storage Local Get Tests
    
    func testStorageLocalGetWithKeys() async throws {
        // Given: Some data in storage
        mockStorageProvider.setStorageData([
            "key1": "{\"value\":\"hello\"}",
            "key2": "{\"value\":42}",
            "key3": "{\"value\":true}"
        ], area: .local, extensionId: mockBrowserExtension.id)
        
        let handler = StorageLocalGetHandler(storageManager: storageManager)
        
        let request = StorageLocalGetRequestImpl(
            requestId: "test-1",
            keys: AnyJSONCodable("[\"key1\",\"key2\"]")  // JSON-encoded array as done by JS
        )
        
        // When: Getting specific keys
        let result = try await handler.handle(request: request, context: context, namespace: "storage.local")
        
        // Then: Should return only requested keys as JSON strings
        let resultDict = result.value
        XCTAssertEqual(resultDict.count, 2)
        XCTAssertEqual(resultDict["key1"], "{\"value\":\"hello\"}")
        XCTAssertEqual(resultDict["key2"], "{\"value\":42}")
        XCTAssertNil(resultDict["key3"])
        
        // Verify provider was called correctly
        XCTAssertEqual(mockStorageProvider.getCallCount, 1)
        XCTAssertEqual(mockStorageProvider.lastGetKeys, ["key1", "key2"])
        XCTAssertEqual(mockStorageProvider.lastGetArea, .local)
        XCTAssertEqual(mockStorageProvider.lastGetExtensionId, mockBrowserExtension.id)
    }
    
    func testStorageLocalGetWithoutKeys() async throws {
        // Given: Some data in storage
        mockStorageProvider.setStorageData([
            "key1": "{\"value\":\"hello\"}",
            "key2": "{\"value\":42}"
        ], area: .local, extensionId: mockBrowserExtension.id)
        
        let handler = StorageLocalGetHandler(storageManager: storageManager)
        
        let request = StorageLocalGetRequestImpl(
            requestId: "test-2",
            keys: nil
        )
        
        // When: Getting all keys
        let result = try await handler.handle(request: request, context: context, namespace: "storage.local")
        
        // Then: Should return all keys as JSON strings
        let resultDict = result.value
        XCTAssertEqual(resultDict.count, 2)
        XCTAssertEqual(resultDict["key1"], "{\"value\":\"hello\"}")
        XCTAssertEqual(resultDict["key2"], "{\"value\":42}")
        
        // Verify provider was called with nil keys
        XCTAssertEqual(mockStorageProvider.getCallCount, 1)
        XCTAssertNil(mockStorageProvider.lastGetKeys)
    }
    
    func testStorageLocalGetWithSingleStringKey() async throws {
        // Given: Data in storage
        mockStorageProvider.setStorageData([
            "singleKey": "{\"data\":\"test\"}"
        ], area: .local, extensionId: mockBrowserExtension.id)
        
        let handler = StorageLocalGetHandler(storageManager: storageManager)
        
        let request = StorageLocalGetRequestImpl(
            requestId: "test-3",
            keys: AnyJSONCodable("\"singleKey\"")  // JSON-encoded string as done by JS
        )
        
        // When: Getting single key as string
        let result = try await handler.handle(request: request, context: context, namespace: "storage.local")
        
        // Then: Should convert string key to array and return result
        let resultDict = result.value
        XCTAssertEqual(resultDict.count, 1)
        XCTAssertEqual(resultDict["singleKey"], "{\"data\":\"test\"}")
        
        // Verify provider was called with array containing single key
        XCTAssertEqual(mockStorageProvider.lastGetKeys, ["singleKey"])
    }
    
    // MARK: - Storage Local Set Tests
    
    func testStorageLocalSetMultipleItems() async throws {
        let handler = StorageLocalSetHandler(storageManager: storageManager)
        
        let items = [
            "key1": "{\"value\":\"hello\"}",
            "key2": "{\"number\":42}",
            "key3": "{\"boolean\":true}"
        ]
        
        let request = StorageLocalSetRequestImpl(
            requestId: "test-4",
            items: items
        )
        
        // When: Setting multiple items
        try await handler.handle(request: request, context: context, namespace: "storage.local")

        // Verify provider was called correctly
        XCTAssertEqual(mockStorageProvider.setCallCount, 1)
        XCTAssertEqual(mockStorageProvider.lastSetItems, items)
        XCTAssertEqual(mockStorageProvider.lastSetArea, .local)
        XCTAssertEqual(mockStorageProvider.lastSetExtensionId, mockBrowserExtension.id)
        XCTAssertEqual(mockStorageProvider.lastSetHasUnlimitedStorage, false)
    }
    
    func testStorageLocalSetWithUnlimitedStoragePermission() async throws {
        // Given: Extension with unlimitedStorage permission
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0",
            description: "Test extension",
            permissions: ["storage", "unlimitedStorage"]
        )
        
        let extensionWithUnlimitedStorage = BrowserExtension(
            manifest: manifest,
            baseDirectory: URL(fileURLWithPath: "/tmp"),
            extensionLocation: "test",
            logger: mockLogger
        )
        
        let contextWithUnlimited = BrowserExtensionContext(
            logger: mockLogger,
            router: createMockRouter(),
            webView: nil,
            browserExtension: extensionWithUnlimitedStorage,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        let handler = StorageLocalSetHandler(storageManager: storageManager)
        
        let request = StorageLocalSetRequestImpl(
            requestId: "test-5",
            items: ["key": "{\"value\":\"test\"}"]
        )
        
        // When: Setting with unlimited storage context
        _ = try await handler.handle(request: request, context: contextWithUnlimited, namespace: "storage.local")
        
        // Then: Should pass unlimited storage flag
        XCTAssertEqual(mockStorageProvider.lastSetHasUnlimitedStorage, true)
    }
    
    // MARK: - Storage Local Remove Tests
    
    func testStorageLocalRemoveMultipleKeys() async throws {
        let handler = StorageLocalRemoveHandler(storageManager: storageManager)
        
        let request = StorageLocalRemoveRequestImpl(
            requestId: "test-6",
            keys: AnyJSONCodable(["key1", "key2", "key3"])
        )
        
        // When: Removing multiple keys
        try await handler.handle(request: request, context: context, namespace: "storage.local")

        // Verify provider was called correctly
        XCTAssertEqual(mockStorageProvider.removeCallCount, 1)
    }
    
    func testStorageLocalRemoveSingleKey() async throws {
        let handler = StorageLocalRemoveHandler(storageManager: storageManager)
        
        let request = StorageLocalRemoveRequestImpl(
            requestId: "test-7",
            keys: AnyJSONCodable("singleKey")  // Single string
        )
        
        try await handler.handle(request: request, context: context, namespace: "storage.local")
    }
    
    // MARK: - Storage Local Clear Tests
    
    func testStorageLocalClear() async throws {
        let handler = StorageLocalClearHandler(storageManager: storageManager)
        
        let request = StorageLocalClearRequestImpl(requestId: "test-8")
        
        try await handler.handle(request: request, context: context, namespace: "storage.local")

        // Verify provider was called correctly
        XCTAssertEqual(mockStorageProvider.clearCallCount, 1)
    }
    
    // MARK: - Session Storage Access Control Tests
    
    func testStorageSessionFromUntrustedContextWithDefaultAccess() async throws {
        // Given: Untrusted context (content script)
        let untrustedContext = BrowserExtensionContext(
            logger: mockLogger,
            router: createMockRouter(),
            webView: nil,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil,
            contextType: .untrusted,
            role: .userFacing
        )
        
        let handler = StorageSessionGetHandler(storageManager: storageManager)
        
        // Configure mock to throw for untrusted session access
        mockStorageProvider.shouldThrowOnGet = true
        mockStorageProvider.throwError = BrowserExtensionStorageProviderError(type: .permissionDenied)
        
        let request = StorageSessionGetRequestImpl(
            requestId: "test-9",
            keys: nil
        )
        
        // When: Trying to access session storage from untrusted context
        // Then: Should throw storage unavailable error
        do {
            _ = try await handler.handle(request: request, context: untrustedContext, namespace: "storage.session")
            XCTFail("Should have thrown error for untrusted session access")
        } catch let error as BrowserExtensionStorageError {
            XCTAssertEqual(error, .storageAreaNotAvailable(.session))
        }
    }
    
    // MARK: - Managed Storage Read-Only Tests
    
    func testStorageManagedSet() async throws {
        let handler = StorageManagedSetHandler(storageManager: storageManager)
        
        let request = StorageManagedSetRequestImpl(
            requestId: "test-10",
            items: ["key": "{\"value\":\"test\"}"]
        )
        
        // When: Trying to set in managed storage
        // Then: Should throw read-only error
        do {
            _ = try await handler.handle(request: request, context: context, namespace: "storage.managed")
            XCTFail("Should have thrown read-only error")
        } catch let error as BrowserExtensionStorageError {
            XCTAssertEqual(error, .managedStorageReadOnly)
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testStorageProviderNotConfigured() async throws {
        // Given: No storage provider
        let handlerWithoutProvider = StorageLocalGetHandler(storageManager: nil)
        // storageManager is explicitly nil
        
        let request = StorageLocalGetRequestImpl(
            requestId: "test-11",
            keys: nil
        )
        
        // When: Calling handler without provider
        // Then: Should throw internal error
        do {
            _ = try await handlerWithoutProvider.handle(request: request, context: context, namespace: "storage.local")
            XCTFail("Should have thrown error for missing provider")
        } catch let error as BrowserExtensionError {
            if case .internalError(let message) = error {
                XCTAssertTrue(message.lowercased().contains("storage"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}

// MARK: - Helper Functions

@MainActor
private func createMockRouter() -> BrowserExtensionRouter {
    let mockNetwork = BrowserExtensionNetwork()
    return BrowserExtensionRouter(network: mockNetwork, logger: createTestLogger())
}

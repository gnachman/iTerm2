import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionUserContentManagerTests: XCTestCase {
    
    var mockWebView: MockUserContentWebView!
    var mockUserScriptFactory: MockUserScriptFactory!
    var userContentManager: BrowserExtensionUserContentManager!
    
    override func setUp() {
        super.setUp()
        mockWebView = MockUserContentWebView()
        mockUserScriptFactory = MockUserScriptFactory()
        userContentManager = BrowserExtensionUserContentManager(
            webView: mockWebView,
            userScriptFactory: mockUserScriptFactory
        )
    }
    
    override func tearDown() {
        userContentManager = nil
        mockUserScriptFactory = nil
        mockWebView = nil
        super.tearDown()
    }
    
    // MARK: - Add User Script Tests
    
    func testAddUserScriptCallsUpdate() {
        let userScript = createTestUserScript()
        
        userContentManager.add(userScript: userScript)
        
        XCTAssertEqual(mockUserScriptFactory.createUserScriptCalls.count, 1)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 1)
        
        let call = mockUserScriptFactory.createUserScriptCalls[0]
        XCTAssertEqual(call.source, userScript.code)
        XCTAssertEqual(call.injectionTime, userScript.injectionTime)
        XCTAssertEqual(call.forMainFrameOnly, userScript.forMainFrameOnly)
        XCTAssertEqual(call.contentWorld, userScript.worlds[0])
    }
    
    func testAddUserScriptWithMultipleWorlds() {
        let pageWorld = WKContentWorld.page
        let defaultWorld = WKContentWorld.defaultClient
        let userScript = BrowserExtensionUserContentManager.UserScript(
            code: "console.log('test');",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            worlds: [pageWorld, defaultWorld],
            identifier: "test-script"
        )
        
        userContentManager.add(userScript: userScript)
        
        XCTAssertEqual(mockUserScriptFactory.createUserScriptCalls.count, 2)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 2)
        
        let worlds = mockUserScriptFactory.createUserScriptCalls.map { $0.contentWorld }
        XCTAssertTrue(worlds.contains(pageWorld))
        XCTAssertTrue(worlds.contains(defaultWorld))
    }
    
    func testAddUserScriptWithDuplicateWorlds() {
        let pageWorld = WKContentWorld.page
        let userScript = BrowserExtensionUserContentManager.UserScript(
            code: "console.log('test');",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            worlds: [pageWorld, pageWorld], // Duplicate world
            identifier: "test-script"
        )
        
        userContentManager.add(userScript: userScript)
        
        // Should only create one user script despite duplicate worlds
        XCTAssertEqual(mockUserScriptFactory.createUserScriptCalls.count, 1)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 1)
    }
    
    func testAddSameUserScriptTwiceUpdatesExisting() {
        let userScript = createTestUserScript()
        
        // Add first time
        userContentManager.add(userScript: userScript)
        XCTAssertEqual(mockUserScriptFactory.createUserScriptCalls.count, 1)
        
        // Add again with same identifier
        userContentManager.add(userScript: userScript)
        
        // Should only add the new world, not duplicate existing
        XCTAssertEqual(mockUserScriptFactory.createUserScriptCalls.count, 1)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 1)
    }
    
    func testAddUserScriptWithNewWorldToExisting() {
        let pageWorld = WKContentWorld.page
        let defaultWorld = WKContentWorld.defaultClient
        
        let userScript1 = BrowserExtensionUserContentManager.UserScript(
            code: "console.log('test');",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            worlds: [pageWorld],
            identifier: "test-script"
        )
        
        let userScript2 = BrowserExtensionUserContentManager.UserScript(
            code: "console.log('test');",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            worlds: [defaultWorld],
            identifier: "test-script"
        )
        
        userContentManager.add(userScript: userScript1)
        userContentManager.add(userScript: userScript2)
        
        // Should add both worlds
        XCTAssertEqual(mockUserScriptFactory.createUserScriptCalls.count, 2)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 2)
    }
    
    // MARK: - Remove User Script Tests
    
    func testRemoveUserScript() {
        let userScript = createTestUserScript()
        
        // Add first
        userContentManager.add(userScript: userScript)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 1)
        
        // Remove
        userContentManager.remove(userScriptIdentifier: userScript.identifier)
        
        // Should remove all scripts and re-add remaining ones
        XCTAssertEqual(mockWebView.mockUserContentController.removeAllUserScriptsCalls, 1)
        // No re-adding since we removed the only script
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 1)
    }
    
    func testRemoveUserScriptWithMultipleScripts() {
        let userScript1 = createTestUserScript(identifier: "script1")
        let userScript2 = createTestUserScript(identifier: "script2")
        
        // Add both
        userContentManager.add(userScript: userScript1)
        userContentManager.add(userScript: userScript2)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 2)
        
        // Remove one
        userContentManager.remove(userScriptIdentifier: "script1")
        
        // Should remove all and re-add remaining
        XCTAssertEqual(mockWebView.mockUserContentController.removeAllUserScriptsCalls, 1)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 3) // 2 initial + 1 re-add
    }
    
    func testRemoveNonExistentUserScript() {
        let userScript = createTestUserScript()
        
        // Add one script
        userContentManager.add(userScript: userScript)
        let initialAddCount = mockWebView.mockUserContentController.addUserScriptCalls.count
        
        // Try to remove non-existent script
        userContentManager.remove(userScriptIdentifier: "non-existent")
        
        // Should not change anything
        XCTAssertEqual(mockWebView.mockUserContentController.removeAllUserScriptsCalls, 0)
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, initialAddCount)
    }
    
    // MARK: - Atomic Update Tests
    
    func testPerformAtomicUpdateSynchronous() {
        let userScript1 = createTestUserScript(identifier: "script1")
        let userScript2 = createTestUserScript(identifier: "script2")
        
        let result = userContentManager.performAtomicUpdate {
            userContentManager.add(userScript: userScript1)
            userContentManager.add(userScript: userScript2)
            return "success"
        }
        
        XCTAssertEqual(result, "success")
        // Both scripts should be added in one batch after atomic update completes
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 2)
    }
    
    func testPerformAtomicUpdateAsynchronous() async {
        let userScript1 = createTestUserScript(identifier: "script1")
        let userScript2 = createTestUserScript(identifier: "script2")
        
        let result = await userContentManager.performAtomicUpdate { () async -> String in
            userContentManager.add(userScript: userScript1)
            userContentManager.add(userScript: userScript2)
            return "async success"
        }
        
        XCTAssertEqual(result, "async success")
        // Both scripts should be added in one batch after atomic update completes
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 2)
    }
    
    func testPerformAtomicUpdateWithThrow() {
        let userScript = createTestUserScript()
        
        enum TestError: Error {
            case testFailure
        }
        
        XCTAssertThrowsError(try userContentManager.performAtomicUpdate {
            userContentManager.add(userScript: userScript)
            throw TestError.testFailure
        }) { error in
            XCTAssertTrue(error is TestError)
        }
        
        // Script should still be added even though closure threw
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 1)
    }
    
    func testAtomicUpdatePreventsIntermediateUpdates() {
        let userScript1 = createTestUserScript(identifier: "script1")
        let userScript2 = createTestUserScript(identifier: "script2")
        
        userContentManager.performAtomicUpdate {
            userContentManager.add(userScript: userScript1)
            // At this point, no user scripts should be added yet
            XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 0)
            
            userContentManager.add(userScript: userScript2)
            // Still no user scripts added
            XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 0)
        }
        
        // Now both should be added
        XCTAssertEqual(mockWebView.mockUserContentController.addUserScriptCalls.count, 2)
    }
    
    // MARK: - Nil WebView Tests
    
    func testAddUserScriptWithNilWebView() {
        // Create a temporary webView that will be deallocated
        var tempWebView: MockUserContentWebView? = MockUserContentWebView()
        let nilManager = BrowserExtensionUserContentManager(
            webView: tempWebView!,
            userScriptFactory: mockUserScriptFactory
        )
        
        // Deallocate the webView to simulate it being nil
        tempWebView = nil
        
        let userScript = createTestUserScript()
        
        // Should not crash
        nilManager.add(userScript: userScript)
        
        // Factory should not be called since webView is nil
        XCTAssertEqual(mockUserScriptFactory.createUserScriptCalls.count, 0)
    }
    
    func testRemoveUserScriptWithNilWebView() {
        // Create a temporary webView that will be deallocated
        var tempWebView: MockUserContentWebView? = MockUserContentWebView()
        let nilManager = BrowserExtensionUserContentManager(
            webView: tempWebView!,
            userScriptFactory: mockUserScriptFactory
        )
        
        // Deallocate the webView to simulate it being nil
        tempWebView = nil
        
        // Should not crash
        nilManager.remove(userScriptIdentifier: "test")
        
        // Factory should not be called since webView is nil
        XCTAssertEqual(mockUserScriptFactory.createUserScriptCalls.count, 0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestUserScript(identifier: String = "test-script") -> BrowserExtensionUserContentManager.UserScript {
        return BrowserExtensionUserContentManager.UserScript(
            code: "console.log('test');",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            worlds: [WKContentWorld.page],
            identifier: identifier
        )
    }
}

// MARK: - Mock Classes

@MainActor
class MockUserContentWebView: BrowserExtensionWKWebView {
    var be_url: URL?
    var be_configuration: BrowserExtensionWKWebViewConfiguration
    var mockUserContentController: MockUserContentManagerController
    
    init() {
        mockUserContentController = MockUserContentManagerController()
        be_configuration = MockUserContentWebViewConfiguration(userContentController: mockUserContentController)
    }
    
    func be_evaluateJavaScript(_ javaScriptString: String, in frame: WKFrameInfo?, in contentWorld: WKContentWorld) async throws -> Any? {
        return nil
    }
}

@MainActor
class MockUserContentWebViewConfiguration: BrowserExtensionWKWebViewConfiguration {
    var be_userContentController: BrowserExtensionWKUserContentController
    
    init(userContentController: BrowserExtensionWKUserContentController) {
        self.be_userContentController = userContentController
    }
}

@MainActor
class MockUserContentManagerController: BrowserExtensionWKUserContentController {
    var addUserScriptCalls: [WKUserScript] = []
    var removeAllUserScriptsCalls: Int = 0
    var addScriptMessageHandlerCalls: [(WKScriptMessageHandler, String, WKContentWorld)] = []
    var removeScriptMessageHandlerCalls: [(String, WKContentWorld)] = []
    
    func be_addUserScript(_ userScript: WKUserScript) {
        addUserScriptCalls.append(userScript)
    }
    
    func be_removeAllUserScripts() {
        removeAllUserScriptsCalls += 1
    }
    
    func be_add(_ scriptMessageHandler: WKScriptMessageHandler, name: String, contentWorld: WKContentWorld) {
        addScriptMessageHandlerCalls.append((scriptMessageHandler, name, contentWorld))
    }
    
    func be_removeScriptMessageHandler(forName name: String, contentWorld: WKContentWorld) {
        removeScriptMessageHandlerCalls.append((name, contentWorld))
    }
}
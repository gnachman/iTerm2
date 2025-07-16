import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class BrowserExtensionRouterTests: XCTestCase {
    
    var mockLogger: BrowserExtensionLogger!
    var router: BrowserExtensionRouter!
    var mockBrowserExtension: BrowserExtension!
    var webView: AsyncWKWebView!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockLogger = createTestLogger()
        webView = AsyncWKWebView()
        
        // Create mock browser extension first
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0"
        )
        mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseDirectory: URL(fileURLWithPath: "/tmp"),
            extensionLocation: "test-extension",
            logger: mockLogger
        )
        
        // Now create network and add webview
        let network = BrowserExtensionNetwork()
        network.add(webView: webView,
                    world: .page,
                    browserExtension: mockBrowserExtension,
                    trusted: true,
                    role: .backgroundScript(mockBrowserExtension.id),
                    setAccessLevelToken: "")
        router = BrowserExtensionRouter(network: network, logger: mockLogger)
    }
    
    override func tearDown() async throws {
        webView = nil
        mockBrowserExtension = nil
        router = nil
        mockLogger = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func encodeMessage(_ message: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: message)
        return String(data: data, encoding: .utf8)!
    }
    
    // MARK: - Basic Routing Tests
    
    func testPublishMessageToSameExtension() async throws {
        // Load a page first to avoid crash when evaluating JavaScript
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Create a message sender
        let sender = await BrowserExtensionContext.MessageSender(
            sender: mockBrowserExtension,
            senderWebview: webView,
            tab: nil,
            frameId: nil,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test publishing a message to the same extension (extensionId is nil)
        do {
            let messageString = try encodeMessage(["type": "greeting", "data": "hello"])
            _ = try await router.publish(
                message: messageString,
                requestId: "test-request-1",
                extensionId: nil,
                sender: sender,
                sendingWebView: webView,
                options: [:]
            )
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    func testPublishMessageToSpecificExtension() async throws {
        // Load a page first to avoid crash when evaluating JavaScript
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Create a message sender
        let sender = await BrowserExtensionContext.MessageSender(
            sender: mockBrowserExtension,
            senderWebview: webView,
            tab: nil,
            frameId: nil,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test publishing a message to a specific extension
        do {
            let messageString = try encodeMessage(["type": "greeting", "data": "hello"])
            _ = try await router.publish(
                message: messageString,
                requestId: "test-request-2",
                extensionId: "other-extension-id",
                sender: sender,
                sendingWebView: webView,
                options: [:]
            )
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    func testPublishMessageWithOptions() async throws {
        // Load a page first to avoid crash when evaluating JavaScript
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Create a message sender
        let sender = await BrowserExtensionContext.MessageSender(
            sender: mockBrowserExtension,
            senderWebview: webView,
            tab: nil,
            frameId: nil,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test publishing a message with options
        do {
            let messageString = try encodeMessage(["type": "greeting", "data": "hello"])
            _ = try await router.publish(
                message: messageString,
                requestId: "test-request-3",
                extensionId: nil,
                sender: sender,
                sendingWebView: webView,
                options: ["includeTlsChannelId": true]
            )
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    // MARK: - Message Sender Tests
    
    func testMessageSenderInitialization() async throws {
        // Load a page first to avoid crash when evaluating JavaScript
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Test creating a message sender with tab info
        let tabInfo = BrowserExtensionContext.MessageSender.Tab(
            id: 123,
            url: "https://example.com"
        )
        
        let sender = await BrowserExtensionContext.MessageSender(
            sender: mockBrowserExtension,
            senderWebview: webView,
            tab: tabInfo,
            frameId: 0,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        XCTAssertEqual(sender.id, mockBrowserExtension.id.stringValue)
        XCTAssertEqual(sender.tab?.id, 123)
        XCTAssertEqual(sender.tab?.url, "https://example.com")
        XCTAssertEqual(sender.frameId, 0)
        XCTAssertNil(sender.tlsChannelId) // Not supported
    }
    
    func testMessageSenderWithoutTab() async throws {
        // Load a page first to avoid crash when evaluating JavaScript
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Test creating a message sender without tab info (e.g., from background script)
        let sender = await BrowserExtensionContext.MessageSender(
            sender: mockBrowserExtension,
            senderWebview: webView,
            tab: nil,
            frameId: nil,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        XCTAssertEqual(sender.id, mockBrowserExtension.id.stringValue)
        XCTAssertNil(sender.tab)
        XCTAssertNil(sender.frameId)
    }
    
    // MARK: - Edge Cases
    
    func testPublishEmptyMessage() async throws {
        // Load a page first to avoid crash when evaluating JavaScript
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        let sender = await BrowserExtensionContext.MessageSender(
            sender: mockBrowserExtension,
            senderWebview: webView,
            tab: nil,
            frameId: nil,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test publishing an empty message
        do {
            let messageString = try encodeMessage([:])
            _ = try await router.publish(
                message: messageString,
                requestId: "test-request-4",
                extensionId: nil,
                sender: sender,
                sendingWebView: webView,
                options: [:]
            )
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    func testPublishComplexMessage() async throws {
        // Load a page first to avoid crash when evaluating JavaScript
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        let sender = await BrowserExtensionContext.MessageSender(
            sender: mockBrowserExtension,
            senderWebview: webView,
            tab: nil,
            frameId: nil,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test publishing a complex nested message
        let complexMessage: [String: Any] = [
            "action": "update",
            "data": [
                "items": [1, 2, 3],
                "metadata": [
                    "timestamp": Date().timeIntervalSince1970,
                    "version": "1.0"
                ]
            ],
            "nested": [
                "deep": [
                    "value": true
                ]
            ]
        ]
        
        do {
            let messageString = try encodeMessage(complexMessage)
            _ = try await router.publish(
                message: messageString,
                requestId: "test-request-5",
                extensionId: nil,
                sender: sender,
                sendingWebView: webView,
                options: [:]
            )
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
}

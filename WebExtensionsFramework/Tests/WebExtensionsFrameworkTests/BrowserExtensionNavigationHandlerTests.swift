import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionNavigationHandlerTests: XCTestCase {
    
    var handler: BrowserExtensionNavigationHandler!
    
    override func setUp() {
        super.setUp()
        handler = BrowserExtensionNavigationHandler(logger: createTestLogger())
    }
    
    override func tearDown() {
        handler = nil
        super.tearDown()
    }
    
    func testHandlerInitialization() {
        XCTAssertNotNil(handler)
    }
    
    func testNavigationActionPolicyAllows() {
        let expectation = XCTestExpectation(description: "Decision handler called")
        
        let mockWebView = MockWebView()
        let mockNavigationAction = MockNavigationAction()
        
        handler.webView(mockWebView, decidePolicyFor: mockNavigationAction) { policy in
            XCTAssertEqual(policy, .allow)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testNavigationResponsePolicyAllows() {
        let expectation = XCTestExpectation(description: "Decision handler called")
        
        let mockWebView = MockWebView()
        let mockNavigationResponse = MockNavigationResponse()
        
        handler.webView(mockWebView, decidePolicyFor: mockNavigationResponse) { policy in
            XCTAssertEqual(policy, .allow)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testAuthenticationChallengeUsesDefaultHandling() {
        let expectation = XCTestExpectation(description: "Completion handler called")
        
        let protectionSpace = URLProtectionSpace(
            host: "example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodDefault
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockAuthenticationChallengeSender()
        )
        
        let mockWebView = MockWebView()
        handler.webView(mockWebView, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testOtherNavigationMethods() {
        let mockWebView = MockWebView()
        let mockNavigation = MockNavigation()
        
        // These methods don't have return values or callbacks, just ensure they don't crash
        XCTAssertNoThrow(handler.webView(mockWebView, didStartProvisionalNavigation: mockNavigation))
        XCTAssertNoThrow(handler.webView(mockWebView, didReceiveServerRedirectForProvisionalNavigation: mockNavigation))
        XCTAssertNoThrow(handler.webView(mockWebView, didFailProvisionalNavigation: mockNavigation, withError: TestError.test))
        XCTAssertNoThrow(handler.webView(mockWebView, didCommit: mockNavigation))
        XCTAssertNoThrow(handler.webView(mockWebView, didFinish: mockNavigation))
        XCTAssertNoThrow(handler.webView(mockWebView, didFail: mockNavigation, withError: TestError.test))
        XCTAssertNoThrow(handler.webView(mockWebView, webContentProcessDidTerminate: mockNavigation))
    }
}

// MARK: - Mock Objects

private class MockWebView: @preconcurrency BrowserExtensionWKWebView {
    var be_url: URL? = URL(string: "https://example.com")
    var be_configuration: BrowserExtensionWKWebViewConfiguration = MockWebViewConfiguration()
    
    var evaluatedScripts: [String] = []
    
    func be_evaluateJavaScript(_ javaScriptString: String, in frame: WKFrameInfo?, in contentWorld: WKContentWorld) async throws -> Any? {
        evaluatedScripts.append(javaScriptString)
        return nil
    }
    
    @MainActor
    func be_evaluateJavaScript(_ javaScriptString: String, in frame: WKFrameInfo?, in contentWorld: WKContentWorld, completionHandler: @escaping @MainActor @Sendable (Result<Any, Error>) -> Void) {
        evaluatedScripts.append(javaScriptString)
        completionHandler(.success(NSNull()))
    }
}

private class MockWebViewConfiguration: BrowserExtensionWKWebViewConfiguration {
    var be_userContentController: BrowserExtensionWKUserContentController = MockUserContentController()
}

private class MockUserContentController: BrowserExtensionWKUserContentController {
    var addedUserScripts: [WKUserScript] = []
    var addedMessageHandlers: [(WKScriptMessageHandler, String)] = []
    
    func be_addUserScript(_ userScript: WKUserScript) {
        addedUserScripts.append(userScript)
    }
    
    func be_removeAllUserScripts() {
        addedUserScripts.removeAll()
    }
    
    func be_add(_ scriptMessageHandler: WKScriptMessageHandler, name: String, contentWorld: WKContentWorld) {
        addedMessageHandlers.append((scriptMessageHandler, name))
    }
}

private class MockNavigation: BrowserExtensionWKNavigation {
}

private class MockNavigationAction: BrowserExtensionWKNavigationAction {
    var be_request: URLRequest = URLRequest(url: URL(string: "https://example.com")!)
    var be_targetFrame: BrowserExtensionWKFrameInfo? = nil
    var be_sourceFrame: BrowserExtensionWKFrameInfo? = nil
    var be_navigationType: WKNavigationType = .linkActivated
}

private class MockNavigationResponse: BrowserExtensionWKNavigationResponse {
    var be_response: URLResponse = URLResponse(url: URL(string: "https://example.com")!, 
                                             mimeType: "text/html", 
                                             expectedContentLength: 0, 
                                             textEncodingName: nil)
    var be_isForMainFrame: Bool = true
    var be_canShowMIMEType: Bool = true
}

private class MockAuthenticationChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

private enum TestError: Error {
    case test
}

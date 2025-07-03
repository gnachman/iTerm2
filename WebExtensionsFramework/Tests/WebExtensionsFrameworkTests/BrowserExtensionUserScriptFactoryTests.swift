import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionUserScriptFactoryTests: XCTestCase {
    
    var factory: BrowserExtensionUserScriptFactory!
    
    override func setUp() {
        super.setUp()
        factory = BrowserExtensionUserScriptFactory()
    }
    
    override func tearDown() {
        factory = nil
        super.tearDown()
    }
    
    func testCreateUserScriptWithDocumentStart() {
        let source = "console.log('test');"
        let userScript = factory.createUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        
        XCTAssertEqual(userScript.source, source)
        XCTAssertEqual(userScript.injectionTime, .atDocumentStart)
        XCTAssertTrue(userScript.isForMainFrameOnly)
    }
    
    func testCreateUserScriptWithDocumentEnd() {
        let source = "document.body.style.backgroundColor = 'red';"
        let userScript = factory.createUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
            in: .defaultClient
        )
        
        XCTAssertEqual(userScript.source, source)
        XCTAssertEqual(userScript.injectionTime, .atDocumentEnd)
        XCTAssertFalse(userScript.isForMainFrameOnly)
    }
    
    func testCreateUserScriptWithIsolatedWorld() {
        let source = "window.extensionAPI = {};"
        let isolatedWorld = WKContentWorld.world(name: "ExtensionWorld")
        let userScript = factory.createUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: isolatedWorld
        )
        
        XCTAssertEqual(userScript.source, source)
        XCTAssertEqual(userScript.injectionTime, .atDocumentStart)
        XCTAssertTrue(userScript.isForMainFrameOnly)
    }
}

// MARK: - Mock Factory for Testing

@MainActor
class MockUserScriptFactory: BrowserExtensionUserScriptFactoryProtocol {
    var createUserScriptCalls: [(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool, contentWorld: WKContentWorld)] = []
    var mockUserScript: WKUserScript?
    
    func createUserScript(
        source: String,
        injectionTime: WKUserScriptInjectionTime,
        forMainFrameOnly: Bool,
        in contentWorld: WKContentWorld
    ) -> WKUserScript {
        createUserScriptCalls.append((source, injectionTime, forMainFrameOnly, contentWorld))
        return mockUserScript ?? WKUserScript(
            source: source,
            injectionTime: injectionTime,
            forMainFrameOnly: forMainFrameOnly,
            in: contentWorld
        )
    }
}
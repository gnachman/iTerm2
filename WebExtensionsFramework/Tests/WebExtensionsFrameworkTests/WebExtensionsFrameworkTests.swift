import XCTest
@testable import WebExtensionsFramework

final class WebExtensionsFrameworkTests: XCTestCase {
    
    func testFrameworkInitialization() {
        let framework = WebExtensionsFramework()
        XCTAssertNotNil(framework)
    }
    
    func testFrameworkVersion() {
        XCTAssertEqual(WebExtensionsFramework.version, "1.0.0")
    }
}
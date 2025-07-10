import XCTest
@testable import WebExtensionsFramework

final class BrowserExtensionMatchPatternTests: XCTestCase {
    
    // MARK: - Basic Match Pattern Parsing Tests
    // Based on Documentation/manifest-fields/host_permissions.md examples
    
    func testParseBasicHTTPSPattern() throws {
        // From docs: "https://example.com/*" - All paths on example.com over HTTPS
        let pattern = try BrowserExtensionMatchPattern("https://example.com/*")
        
        XCTAssertEqual(pattern.scheme, .https)
        XCTAssertEqual(pattern.host, "example.com")
        XCTAssertEqual(pattern.path, "/*")
    }
    
    func testParseWildcardSchemePattern() throws {
        // From docs: "*://*.example.com/*" - All subdomains of example.com over any protocol
        let pattern = try BrowserExtensionMatchPattern("*://*.example.com/*")
        
        XCTAssertEqual(pattern.scheme, .any)
        XCTAssertEqual(pattern.host, "*.example.com")
        XCTAssertEqual(pattern.path, "/*")
    }
    
    func testParseAllURLsPattern() throws {
        // From docs: "<all_urls>" - Special pattern matching all URLs
        let pattern = try BrowserExtensionMatchPattern("<all_urls>")
        
        XCTAssertEqual(pattern.scheme, .allURLs)
        XCTAssertEqual(pattern.host, "*")
        XCTAssertEqual(pattern.path, "/*")
    }
    
    // MARK: - URL Matching Tests
    
    func testMatchExactDomain() throws {
        let pattern = try BrowserExtensionMatchPattern("https://example.com/*")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/path")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/path/subpath")!))
        
        XCTAssertFalse(pattern.matches(URL(string: "http://example.com/")!)) // Wrong scheme
        XCTAssertFalse(pattern.matches(URL(string: "https://sub.example.com/")!)) // Wrong host
        XCTAssertFalse(pattern.matches(URL(string: "https://example.org/")!)) // Wrong host
    }
    
    func testMatchWildcardSubdomain() throws {
        let pattern = try BrowserExtensionMatchPattern("https://*.example.com/*")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://sub.example.com/")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://deep.sub.example.com/")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://api.example.com/v1/users")!))
        
        XCTAssertFalse(pattern.matches(URL(string: "https://example.com/")!)) // No subdomain
        XCTAssertFalse(pattern.matches(URL(string: "http://sub.example.com/")!)) // Wrong scheme
        XCTAssertFalse(pattern.matches(URL(string: "https://example.org/")!)) // Wrong domain
    }
    
    func testMatchAnyScheme() throws {
        let pattern = try BrowserExtensionMatchPattern("*://example.com/*")
        
        XCTAssertTrue(pattern.matches(URL(string: "http://example.com/")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/")!))
        
        XCTAssertFalse(pattern.matches(URL(string: "ftp://example.com/")!)) // * only matches http/https
        XCTAssertFalse(pattern.matches(URL(string: "file://example.com/")!))
    }
    
    func testMatchAllURLs() throws {
        let pattern = try BrowserExtensionMatchPattern("<all_urls>")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/")!))
        XCTAssertTrue(pattern.matches(URL(string: "http://localhost:8080/api")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://sub.domain.com/path?query=1")!))
        XCTAssertTrue(pattern.matches(URL(string: "file:///Users/test/file.txt")!))
        XCTAssertTrue(pattern.matches(URL(string: "ftp://ftp.example.com/")!))
    }
    
    func testMatchSpecificPath() throws {
        let pattern = try BrowserExtensionMatchPattern("https://api.example.com/v1/*")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://api.example.com/v1/users")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://api.example.com/v1/posts/123")!))
        
        XCTAssertFalse(pattern.matches(URL(string: "https://api.example.com/v2/users")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://api.example.com/")!))
    }
    
    func testMatchFileURL() throws {
        let pattern = try BrowserExtensionMatchPattern("file:///*")
        
        XCTAssertTrue(pattern.matches(URL(string: "file:///Users/test/file.txt")!))
        XCTAssertTrue(pattern.matches(URL(string: "file:///C:/Windows/file.txt")!))
        
        XCTAssertFalse(pattern.matches(URL(string: "https://example.com/file.txt")!))
    }
    
    func testMatchLocalhost() throws {
        // From docs example: "*://localhost/*"
        let pattern = try BrowserExtensionMatchPattern("*://localhost/*")
        
        XCTAssertTrue(pattern.matches(URL(string: "http://localhost/")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://localhost/api")!))
        XCTAssertTrue(pattern.matches(URL(string: "http://localhost:3000/")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://localhost:8443/secure")!))
        
        XCTAssertFalse(pattern.matches(URL(string: "http://example.com/")!))
    }
    
    // MARK: - Invalid Pattern Tests
    
    func testInvalidPatternNoScheme() {
        XCTAssertThrowsError(try BrowserExtensionMatchPattern("example.com/*")) { error in
            XCTAssertEqual(error as? BrowserExtensionMatchPattern.ParseError, .invalidFormat)
        }
    }
    
    func testInvalidPatternNoDelimiter() {
        XCTAssertThrowsError(try BrowserExtensionMatchPattern("https:example.com")) { error in
            XCTAssertEqual(error as? BrowserExtensionMatchPattern.ParseError, .invalidFormat)
        }
    }
    
    func testInvalidPatternEmpty() {
        XCTAssertThrowsError(try BrowserExtensionMatchPattern("")) { error in
            XCTAssertEqual(error as? BrowserExtensionMatchPattern.ParseError, .invalidFormat)
        }
    }
    
    func testInvalidPatternInvalidScheme() {
        XCTAssertThrowsError(try BrowserExtensionMatchPattern("invalid://example.com/*")) { error in
            XCTAssertEqual(error as? BrowserExtensionMatchPattern.ParseError, .invalidScheme("invalid"))
        }
    }
    
    // MARK: - Port Handling Tests
    
    func testMatchWithPort() throws {
        let pattern = try BrowserExtensionMatchPattern("http://localhost:8080/*")
        
        XCTAssertTrue(pattern.matches(URL(string: "http://localhost:8080/")!))
        XCTAssertTrue(pattern.matches(URL(string: "http://localhost:8080/api")!))
        
        XCTAssertFalse(pattern.matches(URL(string: "http://localhost/")!)) // No port
        XCTAssertFalse(pattern.matches(URL(string: "http://localhost:3000/")!)) // Wrong port
    }
    
    func testMatchWildcardPort() throws {
        let pattern = try BrowserExtensionMatchPattern("http://localhost:*/*")
        
        XCTAssertTrue(pattern.matches(URL(string: "http://localhost/")!)) // Default port
        XCTAssertTrue(pattern.matches(URL(string: "http://localhost:8080/")!))
        XCTAssertTrue(pattern.matches(URL(string: "http://localhost:3000/")!))
        
        XCTAssertFalse(pattern.matches(URL(string: "http://example.com/")!))
    }
    
    // MARK: - Static Helper Tests
    
    func testIsValidMatchPattern() {
        XCTAssertTrue(BrowserExtensionMatchPattern.isValid("<all_urls>"))
        XCTAssertTrue(BrowserExtensionMatchPattern.isValid("https://example.com/*"))
        XCTAssertTrue(BrowserExtensionMatchPattern.isValid("*://*.example.com/*"))
        XCTAssertTrue(BrowserExtensionMatchPattern.isValid("file:///*"))
        
        XCTAssertFalse(BrowserExtensionMatchPattern.isValid("storage"))
        XCTAssertFalse(BrowserExtensionMatchPattern.isValid("tabs"))
        XCTAssertFalse(BrowserExtensionMatchPattern.isValid("example.com"))
        XCTAssertFalse(BrowserExtensionMatchPattern.isValid(""))
    }
    
    // MARK: - Permission Parser Integration Tests
    
    func testPermissionParserDetectsHostPatterns() {
        // These should be detected as host patterns
        XCTAssertTrue(BrowserExtensionPermissionParser.isHostPattern("https://example.com/*"))
        XCTAssertTrue(BrowserExtensionPermissionParser.isHostPattern("*://*.example.com/*"))
        XCTAssertTrue(BrowserExtensionPermissionParser.isHostPattern("<all_urls>"))
        
        // These should NOT be detected as host patterns
        XCTAssertFalse(BrowserExtensionPermissionParser.isHostPattern("storage"))
        XCTAssertFalse(BrowserExtensionPermissionParser.isHostPattern("tabs"))
        XCTAssertFalse(BrowserExtensionPermissionParser.isHostPattern("system.cpu"))
    }
}
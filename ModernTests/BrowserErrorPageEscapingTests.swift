//
//  BrowserErrorPageEscapingTests.swift
//  ModernTests
//
//  The browser’s internal error page (iterm2-about:error) inserted the failed
//  URL and the error text without HTML escaping, and put the URL raw inside a
//  single-quoted JavaScript string, so a crafted failing URL could run script
//  in the internal page. Found while fixing QA finding F-402.
//

import XCTest
@testable import iTerm2SharedARC

final class BrowserErrorPageEscapingTests: XCTestCase {
    private func scripts(_ html: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "(?s)<script[^>]*>(.*?)</script>")
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap {
            Range($0.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    @MainActor
    private func errorPage(error: Error, failedURL: URL?) -> String {
        return iTermBrowserErrorHandler().generateErrorPageHTML(for: error, failedURL: failedURL)
    }

    // A quote in the failed URL must not break out of the retry script.
    @MainActor
    func testQuoteInFailedURLDoesNotReachScript() throws {
        let url = try XCTUnwrap(URL(string: "http://example.invalid/');alert(1);//"))
        XCTAssertTrue(url.absoluteString.contains("'"))
        let html = errorPage(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost),
                             failedURL: url)
        XCTAssertFalse(html.contains("');alert(1)"), html)
        for script in scripts(html) {
            XCTAssertFalse(script.contains("alert(1)"), script)
            XCTAssertFalse(script.contains("example.invalid"), script)
        }
        XCTAssertTrue(html.contains("data-original-url=\"http://example.invalid/&#39;);alert(1);//\""), html)
        XCTAssertTrue(html.contains("<div class=\"error-url\">http://example.invalid/&#39;);alert(1);//</div>"), html)
    }

    // Markup in the error text (which can contain a user-supplied path or URL) is shown as text.
    @MainActor
    func testMarkupInErrorDescriptionIsEscaped() {
        let payload = "<img src=x onerror=alert(1)>"
        let error = NSError(domain: NSURLErrorDomain,
                            code: NSURLErrorUnknown,
                            userInfo: [NSLocalizedDescriptionKey: payload])
        let html = errorPage(error: error, failedURL: nil)
        XCTAssertFalse(html.contains(payload), html)
        XCTAssertTrue(html.contains("&lt;img src=x onerror=alert(1)&gt;"), html)
        // The intended formatting survives.
        XCTAssertTrue(html.contains("<strong>"), html)
        XCTAssertTrue(html.contains("<br/><br/>"), html)
    }

    // The same applies when the error text is the second line of the message.
    @MainActor
    func testMarkupInKnownErrorDescriptionIsEscaped() {
        let payload = "<script>alert(1)</script>"
        let error = NSError(domain: NSURLErrorDomain,
                            code: NSURLErrorCannotConnectToHost,
                            userInfo: [NSLocalizedDescriptionKey: payload])
        let html = errorPage(error: error, failedURL: nil)
        XCTAssertFalse(html.contains(payload), html)
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"), html)
        XCTAssertEqual(scripts(html).filter { $0.contains("alert(1)") }, [])
    }

    // A placeholder in untrusted text must not be expanded by a later substitution pass.
    @MainActor
    func testPlaceholderInErrorDescriptionIsNotExpanded() throws {
        let error = NSError(domain: NSURLErrorDomain,
                            code: NSURLErrorCannotConnectToHost,
                            userInfo: [NSLocalizedDescriptionKey: "{{URL_DISPLAY}}{{ORIGINAL_URL}}"])
        let html = errorPage(error: error, failedURL: try XCTUnwrap(URL(string: "http://example.invalid/")))
        XCTAssertTrue(html.contains("<br/><br/>{{URL_DISPLAY}}{{ORIGINAL_URL}}</p>"), html)
        XCTAssertEqual(html.components(separatedBy: "class=\"error-url\"").count, 2, html)
    }

    // With no failed URL the retry button reloads.
    @MainActor
    func testNoFailedURL() {
        let html = errorPage(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
                             failedURL: nil)
        XCTAssertFalse(html.contains("{{"), html)
        XCTAssertTrue(html.contains("data-original-url=\"\""), html)
        XCTAssertFalse(html.contains("class=\"error-url\""), html)
    }
}

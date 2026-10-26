//
//  BrowserTemplateLoaderTests.swift
//  ModernTests
//
//  iTermBrowserTemplateLoader substituted placeholders one key at a time in
//  dictionary order, so a value containing {{OTHER_KEY}} could be expanded by a
//  later pass. The view-source page also put an HTML-escaped URL inside a
//  JavaScript string. Found while fixing QA finding F-402.
//

import XCTest
@testable import iTerm2SharedARC

final class BrowserTemplateLoaderTests: XCTestCase {
    private func scripts(_ html: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "(?s)<script[^>]*>(.*?)</script>")
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap {
            Range($0.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    // Every key is tried both before and after the others, since dictionary order is random.
    func testValuesAreNotReexpanded() {
        let substitutions = ["A": "{{B}}", "B": "{{A}}", "C": "c"]
        let result = iTermBrowserTemplateLoader.substitutePlaceholders(
            in: "a={{A}} b={{B}} c={{C}} c2={{C}}",
            substitutions: substitutions)
        XCTAssertEqual(result, "a={{B}} b={{A}} c=c c2=c")
    }

    func testUnknownPlaceholdersAndOtherBracesAreLeftAlone() {
        let result = iTermBrowserTemplateLoader.substitutePlaceholders(
            in: "{{UNKNOWN}} {{a-b}} { {X} } {{X}} {{{X}}}",
            substitutions: ["X": "x"])
        XCTAssertEqual(result, "{{UNKNOWN}} {{a-b}} { {X} } x {x}")
    }

    func testNonASCIIIsPreserved() {
        let result = iTermBrowserTemplateLoader.substitutePlaceholders(
            in: "“😀{{X}}é”",
            substitutions: ["X": "👍{{X}}"])
        XCTAssertEqual(result, "“😀👍{{X}}é”")
    }

    @MainActor
    func testViewSourceURLIsNotInScriptAndSourceIsNotExpanded() throws {
        let url = try XCTUnwrap(URL(string: "http://example.invalid/p?a=1&b=');alert(1);//"))
        let html = iTermBrowserSourceHandler().generateSourcePageHTML(
            for: "<p>{{URL}}</p>",
            url: url)
        for script in scripts(html) {
            XCTAssertFalse(script.contains("example.invalid"), script)
            XCTAssertFalse(script.contains("alert(1)"), script)
        }
        XCTAssertTrue(html.contains("data-url=\"http://example.invalid/p?a=1&amp;b=&#39;);alert(1);//\""), html)
        // The page’s own source is shown verbatim, not expanded.
        XCTAssertTrue(html.contains("&lt;p&gt;{{URL}}&lt;/p&gt;"), html)
    }
}

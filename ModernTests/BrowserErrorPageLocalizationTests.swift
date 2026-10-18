//
//  BrowserErrorPageLocalizationTests.swift
//  ModernTests
//
//  The browser’s page-load error page had a translated heading and message
//  but English “Try Again” and footer literals in its HTML template, and the
//  ssh page for a host without an ssh integration connection was all English
//  (QA F-402).
//

import XCTest
@testable import iTerm2SharedARC

final class BrowserErrorPageLocalizationTests: XCTestCase {
    private let languages = ["de", "ja", "pt-BR", "ru", "zh-Hans"]

    private var repoRoot: URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func visibleText(_ html: String) -> String {
        var text = html
        for pattern in ["(?s)<style.*?</style>", "(?s)<script.*?</script>", "<[^>]*>"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return text
    }

    // Every word a user sees in these templates comes from a {{PLACEHOLDER}} filled with a
    // localized string.
    func testTemplatesHaveNoEnglishLiterals() throws {
        for path in ["sources/Browser/LocalPages/error-page.html",
                     "sources/Browser/sshPageManager/ssh-page-no-conductor.html"] {
            let html = try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
            let leftover = visibleText(html)
                .replacingOccurrences(of: "\\{\\{[A-Z_]+\\}\\}", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(leftover, "", path)
        }
    }

    @MainActor
    func testErrorPageFillsEveryPlaceholder() {
        let html = iTermBrowserErrorHandler().generateErrorPageHTML(
            for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost),
            failedURL: URL(string: "http://127.0.0.1:9/"))
        XCTAssertFalse(html.contains("{{"), html)
        XCTAssertTrue(html.contains(">Try Again</button>"), html)
        XCTAssertTrue(html.contains("Check your internet connection and try reloading the page."), html)
    }

    func testSSHPageFillsEveryPlaceholderAndEscapesTheHost() {
        let html = iTermBrowserSSHPageManager.noConductorPageHTML(host: "a<b>")
        XCTAssertFalse(html.contains("{{"), html)
        XCTAssertTrue(html.contains("<title>Problem viewing file</title>"), html)
        XCTAssertTrue(html.contains("Could not display file"), html)
        XCTAssertTrue(html.contains("No connection to <strong>a&lt;b&gt;</strong> using ssh integration could be found."), html)
        XCTAssertTrue(html.contains(">Try Again</button>"), html)
    }

    func testStringsAreTranslated() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        let keys = ["BrowserErrorPage.TryAgain",
                    "BrowserErrorPage.Details",
                    "BrowserSSHPage.PageTitle",
                    "BrowserSSHPage.Heading",
                    "BrowserSSHPage.NoConnectionMessage",
                    "BrowserSSHPage.TryAgain"]
        for key in keys {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            for language in languages {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) \(language)")
                let value = unit?["value"] as? String ?? ""
                if key == "BrowserSSHPage.NoConnectionMessage" {
                    XCTAssertEqual(value.components(separatedBy: "%@").count, 2, "\(key) \(language)")
                }
            }
        }
    }
}

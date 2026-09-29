//
//  URLForUserSuppliedStringTests.swift
//  ModernTests
//
//  Tests for +[iTermURLActionFactory urlForUserSuppliedString:guessingScheme:], which backs the
//  “Open Selection as URL” context menu items. Issue 13092.
//

import XCTest
@testable import iTerm2SharedARC

final class URLForUserSuppliedStringTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Don't depend on which apps this machine has registered for which schemes.
        setOpenableSchemes(["http", "https", "file"])
        // Nor on the advanced settings of whoever runs the tests.
        pinAdvancedSetting("DefaultURLScheme", to: "https")
        pinAdvancedSetting("RequireSlashInURLGuess", to: true)
        pinAdvancedSetting("ConservativeURLGuessing", to: false)
    }

    /// Makes exactly these schemes openable; nil makes every scheme openable, as when the
    /// urlHandlerCommand advanced setting routes every URL to a script.
    private func setOpenableSchemes(_ schemes: [String]?) {
        iTermURLActionFactory.setURLOpenabilityOverrideForTesting { url in
            guard let schemes else { return true }
            return schemes.contains(url.scheme ?? "")
        }
    }

    override func tearDown() {
        iTermURLActionFactory.setURLOpenabilityOverrideForTesting(nil)
        super.tearDown()
    }

    private func url(_ string: String, guess: Bool = true) -> String? {
        return iTermURLActionFactory.url(forUserSuppliedString: string, guessingScheme: guess)?.absoluteString
    }

    func testKeepsExplicitScheme() {
        XCTAssertEqual(url("https://example.com/path?q=1"), "https://example.com/path?q=1")
        XCTAssertEqual(url("file:///tmp"), "file:///tmp")
        XCTAssertEqual(url("https://example.com/path", guess: false), "https://example.com/path")
    }

    func testTrimsSurroundingPunctuationAndWhitespace() {
        XCTAssertEqual(url("  (https://example.com/path)  "), "https://example.com/path")
        XCTAssertEqual(url("https://example.com/path."), "https://example.com/path")
        XCTAssertEqual(url("(example.com/path)"), "https://example.com/path")
    }

    func testAppliesDefaultSchemeToSchemelessHost() {
        // The reporter's selection in issue 13092.
        XCTAssertEqual(url("code.claude.com/docs/en/changelog"),
                       "https://code.claude.com/docs/en/changelog")
        XCTAssertEqual(url("example.com/"), "https://example.com/")
    }

    func testBareTwoPartHostIsNotAURLByDefault() {
        // requireSlashInURLGuess defaults to YES, matching what ⌘-click does.
        XCTAssertNil(url("example.com"))
    }

    func testUsesHTTPForLocalhostOnly() {
        // Only a single-word host gets http; everything else, including an IP address, gets the
        // defaultURLScheme advanced setting (https), the same as ⌘-click.
        XCTAssertEqual(url("localhost/foo"), "http://localhost/foo")
        XCTAssertEqual(url("127.0.0.1:8080/x"), "https://127.0.0.1:8080/x")
    }

    func testSchemelessHostWithPortIsNotMistakenForAScheme() {
        XCTAssertEqual(url("localhost:8080/foo"), "http://localhost:8080/foo")
        XCTAssertEqual(url("example.com:8080/path"), "https://example.com:8080/path")
    }

    func testColonInPathIsAllowed() {
        XCTAssertEqual(url("en.wikipedia.org/wiki/Category:Physics"),
                       "https://en.wikipedia.org/wiki/Category:Physics")
        XCTAssertEqual(url("github.com/org/repo/blob/main/file.c:12"),
                       "https://github.com/org/repo/blob/main/file.c:12")
        XCTAssertEqual(url("localhost:8080/a:b"), "http://localhost:8080/a:b")
    }

    func testWebURLGuessBeatsASchemeNameInsideThePath() {
        setOpenableSchemes(["http", "https", "mailto"])
        XCTAssertEqual(url("example.com/contact/mailto:alice"),
                       "https://example.com/contact/mailto:alice")
        XCTAssertEqual(url("mailto:alice"), "mailto:alice")
        XCTAssertEqual(url("mailto:alice@example.com/x"), "mailto:alice@example.com/x")
    }

    func testWebURLGuessBeatsHandlerCommandTakingEveryScheme() {
        setOpenableSchemes(nil)
        XCTAssertEqual(url("example.com:8080/path"), "https://example.com:8080/path")
        XCTAssertEqual(url("localhost:8080/foo"), "http://localhost:8080/foo")
        // Nothing to guess here, so the handler gets the text as is.
        XCTAssertEqual(url("foo:bar"), "foo:bar")
        // An explicit scheme is used as is whether or not guessing is on.
        XCTAssertEqual(url("gemini://host/path"), "gemini://host/path")
        XCTAssertEqual(url("gemini://host/path", guess: false), "gemini://host/path")
    }

    func testInternationalizedHostname() {
        let result = url("例子.测试/path")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("https://") ?? false, String(describing: result))
        XCTAssertEqual(iTermURLActionFactory.url(forUserSuppliedString: "例え.jp/path", guessingScheme: true)?.host,
                       "xn--r8jz45g.jp")
    }

    func testDefaultURLSchemeSettingIsHonored() {
        withAdvancedSetting("DefaultURLScheme", "http") {
            XCTAssertEqual(url("example.com/path"), "http://example.com/path")
        }
    }

    func testDoesNotGuessASchemeForTextThatAlreadyHasOne() {
        // The scheme has no handler here; guessing http on top of it would make garbage.
        XCTAssertNil(url("gemini://host/path"))
        XCTAssertNil(url("git@github.com:user/repo.git"))
    }

    func testColonInTextWithoutAHandlerIsNotAURL() {
        XCTAssertNil(url("foo:bar"))
        XCTAssertNil(url("note:this"))
        XCTAssertNil(url("C:\\temp"))
    }

    func testRelativePathsAreNotWebURLs() {
        // Unlike ⌘-click, the selection has not been checked against the filesystem, so a
        // single-word host other than localhost is not enough to guess a web URL.
        XCTAssertNil(url("sources/Foo.m"))
        XCTAssertNil(url("a/b"))
    }

    func testReturnsNilWhenNoURLCanBeMade() {
        XCTAssertNil(url(""))
        XCTAssertNil(url("   "))
        XCTAssertNil(url("hello world"))
        XCTAssertNil(url("/usr/local/bin"))
    }

    func testDoesNotGuessWhenGuessingIsOff() {
        // The ⌘-click fallback for a file that failed to open must not turn a path into a website.
        XCTAssertNil(url("src/main.c", guess: false))
        XCTAssertNil(url("localhost:8080/foo", guess: false))
    }

    func testDoesNotGuessWhenConservativeURLGuessingIsOn() {
        withAdvancedSetting("ConservativeURLGuessing", true) {
            XCTAssertNil(url("code.claude.com/docs/en/changelog"))
            XCTAssertEqual(url("https://example.com/path"), "https://example.com/path")
        }
        withAdvancedSetting("ConservativeURLGuessing", false) {
            XCTAssertEqual(url("code.claude.com/docs/en/changelog"),
                           "https://code.claude.com/docs/en/changelog")
        }
    }

    // MARK: - The real openability check

    func testRealOpenabilityCheck() {
        iTermURLActionFactory.setURLOpenabilityOverrideForTesting(nil)
        // No app could plausibly be registered for a random scheme.
        let unknownScheme = "zz" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let unknown = URL(string: "\(unknownScheme):this")!

        XCTAssertTrue(iTermURLActionFactory.urlHasOpenableScheme(URL(string: "https://example.com/")!))
        XCTAssertTrue(iTermURLActionFactory.urlHasOpenableScheme(URL(string: "file:///nonexistent/missing.c#12")!))
        XCTAssertTrue(iTermURLActionFactory.urlHasOpenableScheme(URL(string: "iterm2:///foo")!))
        XCTAssertFalse(iTermURLActionFactory.urlHasOpenableScheme(URL(string: "nonexistent")!))

        withAdvancedSetting("UrlHandlerCommand", "") {
            XCTAssertFalse(iTermURLActionFactory.urlHasOpenableScheme(unknown))
        }
        // A URL handler command takes every URL, so any scheme is openable.
        withAdvancedSetting("UrlHandlerCommand", "open \\(url)") {
            XCTAssertTrue(iTermURLActionFactory.urlHasOpenableScheme(unknown))
        }
    }
}

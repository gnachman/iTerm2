//
//  WorkgroupBrowserURLBindingTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupBrowserURLBindingTests: XCTestCase {
    private typealias Template = WorkgroupBrowserURLBinding.Template

    private func template(_ string: String) -> Template? {
        if case .template(let template) = Template.parse(string) {
            return template
        }
        return nil
    }

    func testPlainURLIsNotATemplate() {
        XCTAssertEqual(Template.parse("https://github.com/"), .plain)
        XCTAssertEqual(Template.parse(""), .plain)
    }

    func testParsesUserVariables() {
        let parsed = template("https://github.com/\\(user.owner)/\\( user.repo )/pull")
        XCTAssertEqual(parsed?.pieces, [.literal("https://github.com/"),
                                        .variable("user.owner"),
                                        .literal("/"),
                                        .variable("user.repo"),
                                        .literal("/pull")])
    }

    func testWholeURLVariable() {
        XCTAssertEqual(template("\\(user.reviewURL)")?.pieces, [.variable("user.reviewURL")])
    }

    func testRejectsOtherNamespaces() {
        XCTAssertEqual(Template.parse("https://example.com/?d=\\(path)"), .invalid)
        XCTAssertEqual(Template.parse("https://example.com/?d=\\(session.hostname)"), .invalid)
        XCTAssertEqual(Template.parse("https://example.com/\\(user.a)\\(path)"), .invalid)
    }

    func testRejectsFunctionCallsAndExpressions() {
        XCTAssertEqual(Template.parse("\\(user.a + user.b)"), .invalid)
        XCTAssertEqual(Template.parse("\\(iterm2.focus())"), .invalid)
        XCTAssertEqual(Template.parse("\\(user.a.b)"), .invalid)
    }

    func testEvaluateSubstitutes() {
        let parsed = template("https://github.com/\\(user.path)")!
        let url = parsed.evaluate { $0 == "user.path" ? "gnachman/iTerm2/pull/1" : nil }
        XCTAssertEqual(url?.absoluteString, "https://github.com/gnachman/iTerm2/pull/1")
    }

    func testEvaluateIsNilWhenAVariableIsUnsetOrEmpty() {
        let parsed = template("https://github.com/\\(user.path)")!
        XCTAssertNil(parsed.evaluate { _ in nil })
        XCTAssertNil(parsed.evaluate { _ in "" })
    }

    func testEvaluateAllowsOnlyHTTPAndHTTPS() {
        let parsed = template("\\(user.url)")!
        func evaluate(_ value: String) -> String? {
            return parsed.evaluate { _ in value }?.absoluteString
        }
        XCTAssertEqual(evaluate("https://gitlab.com/x/-/issues/1"), "https://gitlab.com/x/-/issues/1")
        XCTAssertEqual(evaluate("http://localhost:8080/"), "http://localhost:8080/")
        XCTAssertEqual(evaluate("HTTPS://example.com/"), "HTTPS://example.com/")
        XCTAssertNil(evaluate("javascript:alert(1)"))
        XCTAssertNil(evaluate("file:///etc/passwd"))
        XCTAssertNil(evaluate("iterm2-about:welcome"))
        XCTAssertNil(evaluate("data:text/html,hi"))
        XCTAssertNil(evaluate("example.com"))
        XCTAssertNil(evaluate("https://"))
    }

    func testValueIsNotReevaluated() {
        let parsed = template("https://example.com/\\(user.a)")!
        let url = parsed.evaluate { $0 == "user.a" ? "\\(user.b)" : "secret" }
        XCTAssertNotEqual(url?.absoluteString, "https://example.com/secret")
    }

    func testInitialURLStringOmitsTemplates() {
        var config = iTermWorkgroupSessionConfig(
            uniqueIdentifier: "x",
            parentID: nil,
            kind: .tab,
            profileGUID: nil,
            command: "",
            urlString: "https://example.com/",
            toolbarItems: [],
            displayName: "Browser")
        XCTAssertEqual(config.initialURLString, "https://example.com/")
        config.urlString = "https://github.com/\\(user.path)"
        XCTAssertEqual(config.initialURLString, "about:blank")
        // Not a template iTerm2 binds, so it loads as typed.
        config.urlString = "https://example.com/\\(foo)"
        XCTAssertEqual(config.initialURLString, "https://example.com/\\(foo)")
    }
}

//
//  iTermAdblockTests.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import XCTest
@testable import iTerm2SharedARC

// Test structures for JSON decoding
private struct TestWebKitContentRule: Codable, Equatable {
    let trigger: TestWebKitTrigger
    let action: TestWebKitAction
}

private struct TestWebKitTrigger: Codable, Equatable {
    let urlFilter: String
    let resourceType: [String]?
    let ifDomain: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case urlFilter = "url-filter"
        case resourceType = "resource-type"
        case ifDomain = "if-domain"
    }
}

private struct TestWebKitAction: Codable, Equatable {
    let type: String
    let selector: String?
}

@available(macOS 11.0, *)
class iTermAdblockTests: XCTestCase {

    func testDebugParser() {
        let input = "||googleads.g.doubleclick.net^"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result, "Parser should return something")
    }

    func testBasicNetworkBlocking() {
        let input = "||googleads.g.doubleclick.net^"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: "^[^:/?#]*://(([^./]+\\.)*)googleads\\.g\\.doubleclick\\.net[/?#]?$",
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")

        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testDomainAnchorMatching() {
        // Test that ||example.com only matches example.com and subdomains
        let input = "||example.com^"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)example\.com[/?#]?$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testWildcardPatterns() {
        let input = "*ads*"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #".*ads.*"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testSeparatorCharacter() {
        let input = "ads^"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        guard let jsonData = result!.data(using: .utf8),
              let rules = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        XCTAssertEqual(rules.count, 1)

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"ads[/?#]?$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(rules, expected)
        XCTAssertNoThrow(try NSRegularExpression(pattern: rules[0].trigger.urlFilter))
    }

    func testElementHiding() {
        let input = "##.advertisement"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actualRules = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: ".*",
                resourceType: nil,
                ifDomain: nil
            ),
            action: TestWebKitAction(
                type: "css-display-none",
                selector: ".advertisement"
            )
        )]

        XCTAssertEqual(actualRules, expected)
    }

    func testDomainSpecificElementHiding() {
        let input = "example.com##.banner"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: ".*",
                resourceType: nil,
                ifDomain: ["example.com"]
            ),
            action: TestWebKitAction(
                type: "css-display-none",
                selector: ".banner"
            )
        )]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
    }

    func testExceptionRules() {
        let input = "@@||example.com^"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)example\.com[/?#]?$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "ignore-previous-rules", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testStartAnchor() {
        let input = "|https://example.com/"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^https:\/\/example\.com\/"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testEndAnchor() {
        let input = ".jpg|"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"\.jpg$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testResourceTypeOptions() {
        let input = "||example.com^$script,image"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)example\.com[/?#]?$"#,
                resourceType: ["script", "image"],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testCommentsAreIgnored() {
        let input = """
        ! This is a comment
        [Adblock Plus 2.0]
        ||googleads.g.doubleclick.net^
        ! Another comment
        ##.advertisement
        """
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("googleads"))
        XCTAssertTrue(result!.contains(".advertisement"))
        XCTAssertFalse(result!.contains("comment"))
    }

    func testNonASCIIRulesAreSkipped() {
        let input = "##.sponsorisé"
        let result = iTermAdblockParser.parseAdblockList(input)

        // Should return nil because the only rule contains non-ASCII characters
        XCTAssertNil(result, "Should return nil when all rules are filtered out")
    }

    func testEmptyInput() {
        let result = iTermAdblockParser.parseAdblockList("")
        XCTAssertNil(result)
    }

    func testOnlyCommentsAndHeaders() {
        let input = """
        ! Comment
        [Adblock Plus 2.0]
        ! Another comment
        """
        let result = iTermAdblockParser.parseAdblockList(input)
        XCTAssertNil(result)
    }

    func testComplexDomainAnchor() {
        // Test ||googleads.g.doubleclick.net specifically
        let input = "||googleads.g.doubleclick.net^"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Parse the JSON to verify structure
        guard let jsonData = result!.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
              let firstRule = jsonArray.first,
              let trigger = firstRule["trigger"] as? [String: Any],
              let urlFilter = trigger["url-filter"] as? String else {
            XCTFail("Could not parse generated JSON")
            return
        }

        // Verify the regex pattern
        XCTAssertTrue(urlFilter.contains("googleads"))
        XCTAssertTrue(urlFilter.contains("doubleclick"))
        XCTAssertTrue(urlFilter.hasPrefix("^"))
    }

    func testMultipleRuleTypes() {
        let input = """
        ||ads.example.com^
        ##.advertisement
        @@||allowedads.com^
        *tracking*
        """
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actualRules = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        // Verify we have multiple rules and they contain expected types
        XCTAssertGreaterThan(actualRules.count, 1)

        let actionTypes = Set(actualRules.map { $0.action.type })
        XCTAssertTrue(actionTypes.contains("block"))
        XCTAssertTrue(actionTypes.contains("css-display-none"))
        XCTAssertTrue(actionTypes.contains("ignore-previous-rules"))

        // Verify all URL filters are valid regex
        for rule in actualRules {
            XCTAssertNoThrow(try NSRegularExpression(pattern: rule.trigger.urlFilter))
        }
    }

    func testInvalidSelectors() {
        let input = """
        ##"invalid'selector
        ##.valid-selector
        ##
        """
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains(".valid-selector"))
        XCTAssertFalse(result!.contains("invalid"))
    }

    func testRegexEscaping() {
        let input = "||example.com/[special].js^"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)example\.com\/\[special]\.js[/?#]?$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testDomainOption() {
        let input = "||ads.example.com^$domain=site1.com|site2.com"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)ads\.example\.com[/?#]?$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: ["site1.com", "site2.com"]),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testThirdPartyOption() {
        let input = "||ads.example.com^$third-party"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)ads\.example\.com[/?#]?$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testNotThirdPartyOption() {
        let input = "||ads.example.com^$~third-party"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)ads\.example\.com[/?#]?$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testElementHidingException() {
        let input = "#@#.advertisement"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: ".*",
                resourceType: nil,
                ifDomain: nil
            ),
            action: TestWebKitAction(
                type: "ignore-previous-rules",
                selector: nil
            )
        )]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
    }

    func testRegexRule() {
        let input = "/ads\\.(gif|jpg)$/"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNil(result)
    }

    func testCombinedOptions() {
        let input = "||ads.example.com^$script,third-party,domain=site1.com|site2.com"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)ads\.example\.com[/?#]?$"#,
                resourceType: ["script"],
                ifDomain: ["site1.com", "site2.com"]),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    // MARK: - Additional uBO Syntax Coverage

    func testElementHidingWithStylesheetOption() {
        let input = "##.foo$stylesheet"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: ".*",
                resourceType: nil,
                ifDomain: nil
            ),
            action: TestWebKitAction(
                type: "css-display-none",
                selector: ".foo"
            )
        )]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
    }

    func testNetworkRuleWithMatchCaseOption() {
        let input = "||Example.COM^$match-case"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)Example\.COM[/?#]?$"#,
                resourceType: [
                    "document",
                    "image",
                    "style-sheet",
                    "script",
                    "font",
                    "raw",
                    "svg-document",
                ],
                ifDomain: nil),
            action: TestWebKitAction(type: "block", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testRegexFilterWithOptions() {
        let input = "/ad[sS]$/$third-party,domain=foo.com"
        let result = iTermAdblockParser.parseAdblockList(input)
        // [sS] not supported
        XCTAssertNil(result)
    }

    func testNetworkExceptionWithOptions() {
        let input = "@@||example.com^$script,third-party"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [TestWebKitContentRule(
            trigger: TestWebKitTrigger(
                urlFilter: #"^[^:/?#]*://(([^./]+\.)*)example\.com[/?#]?$"#,
                resourceType: ["script"],
                ifDomain: nil),
            action: TestWebKitAction(type: "ignore-previous-rules", selector: nil))]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testMixedASCIIAndNonASCIIInput() {
        let input = "##.foo\n##.sponsorisé\n||bar.com^"
        let result = iTermAdblockParser.parseAdblockList(input)

        XCTAssertNotNil(result)

        // Decode JSON
        guard let jsonData = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: jsonData) else {
            XCTFail("Failed to decode JSON")
            return
        }

        // Should have 2 rules (ASCII ones), non-ASCII dropped
        XCTAssertEqual(actual.count, 2)

        // Check that we have the CSS rule for .foo
        let cssRules = actual.filter { $0.action.type == "css-display-none" }
        XCTAssertEqual(cssRules.count, 1)
        XCTAssertEqual(cssRules[0].action.selector, ".foo")

        // Check that we have the network rule for bar.com
        let networkRules = actual.filter { $0.action.type == "block" }
        XCTAssertEqual(networkRules.count, 1)
        XCTAssertTrue(networkRules[0].trigger.urlFilter.contains("bar\\.com"))

        // Verify no rules contain the non-ASCII content
        for rule in actual {
            if let selector = rule.action.selector {
                XCTAssertFalse(selector.contains("sponsorisé"))
            }
            XCTAssertFalse(rule.trigger.urlFilter.contains("sponsorisé"))
        }
    }

    func testMissingDomain() {
        let input = "|https://$image,script,stylesheet,subdocument,third-party,xmlhttprequest,domain=canyoublockit.com"
        let result = iTermAdblockParser.parseAdblockList(input)
        XCTAssertNotNil(result)

        // Decode JSON
        guard let data = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: data) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [
            TestWebKitContentRule(
                trigger: TestWebKitTrigger(
                    urlFilter: #"^https:\/\/"#,
                    resourceType: ["image", "script", "style-sheet", "raw"],
                    ifDomain: ["canyoublockit.com"]
                ),
                action: TestWebKitAction(type: "block", selector: nil)
            )
        ]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testEscapeParen() {
        let input = #"/waWQiOjE*=eyJ.js^$third-party"#
        let result = iTermAdblockParser.parseAdblockList(input)
        XCTAssertNotNil(result)

        // Decode JSON
        guard let data = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: data) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [
            TestWebKitContentRule(
                trigger: TestWebKitTrigger(
                    // No trailing '$'—the '^' becomes '[/?#]?'
                    urlFilter: #"\/waWQiOjE.*=eyJ\.js[/?#]?$"#,
                    resourceType: [
                        "document",
                        "image",
                        "style-sheet",
                        "script",
                        "font",
                        "raw",
                        "svg-document",
                    ],
                    ifDomain: nil
                ),
                action: TestWebKitAction(type: "block", selector: nil)
            )
        ]

        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testCaretInMiddle() {
        let input = #"||net.geo.opera.com^*utm_source=OFT$document"#

        let result = iTermAdblockParser.parseAdblockList(input)
        XCTAssertNotNil(result)

        // Decode JSON
        guard let data = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: data) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [
            TestWebKitContentRule(
                trigger: TestWebKitTrigger(
                    urlFilter: #"^[^:/?#]*://(([^./]+\.)*)net\.geo\.opera\.com[/?#]?.*utm_source=OFT"#,
                    resourceType: [
                        "document",
                    ],
                    ifDomain: nil),
                action: TestWebKitAction(type: "block", selector: nil))]
        XCTAssertEqual(actual, expected, "For input:\n\(input)\nActual:\n\(actual)\nExpected:\n\(expected)\n")
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }

    func testTwoCarets() {
        let input = #"||dev.to^*/bb/post_body_bottom^"#
        let result = iTermAdblockParser.parseAdblockList(input)
        XCTAssertNotNil(result)

        // Decode JSON
        guard let data = result!.data(using: .utf8),
              let actual = try? JSONDecoder().decode([TestWebKitContentRule].self, from: data) else {
            XCTFail("Failed to decode JSON")
            return
        }

        let expected = [
            TestWebKitContentRule(
                trigger: TestWebKitTrigger(
                    urlFilter: #"^[^:/?#]*://(([^./]+\.)*)dev\.to[/?#]?.*\/bb\/post_body_bottom[/?#]?$"#,
                    resourceType: [
                        "document",
                        "image",
                        "style-sheet",
                        "script",
                        "font",
                        "raw",
                        "svg-document",
                    ],
                    ifDomain: nil
                ),
                action: TestWebKitAction(type: "block", selector: nil)
            )
        ]

        XCTAssertEqual(actual, expected, """
            For input:
            \(input)
            Actual:
            \(actual)
            Expected:
            \(expected)
            """)
        XCTAssertNoThrow(try NSRegularExpression(pattern: actual[0].trigger.urlFilter))
    }
}


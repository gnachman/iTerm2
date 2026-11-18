//
//  SSHConfigPrimitivesTests.swift
//  ModernTests
//
//  Ports of OpenSSH's unit tests for the pieces of its config parser that NMSSH ports to
//  Swift: regress/unittests/match/tests.c (match_pattern, match_pattern_list) and
//  regress/unittests/misc/test_strdelim.c, test_argv.c, and test_expand.c. Tests for
//  functions NMSSH doesn't port (addr_match_list, match_filter_denylist and friends) are
//  omitted. Each test names the upstream TEST_START block it follows.
//

import XCTest
@_spi(Testing) import NMSSH

final class SSHConfigPatternTests: XCTestCase {
    private func assertMatch(_ string: String, _ pattern: String, _ expected: Bool,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(SSHConfigPattern.matches(string, pattern: pattern), expected,
                       "match_pattern(“\(string)”, “\(pattern)”)", file: file, line: line)
    }

    /// "match_pattern"
    func testMatchPattern() {
        assertMatch("", "", true)
        assertMatch("", "aaa", false)
        assertMatch("aaa", "", false)
        assertMatch("aaa", "aaaa", false)
        assertMatch("aaaa", "aaa", false)
        assertMatch("abc", "abc", true)
        assertMatch("abc", "abd", false)
        assertMatch("abc", "abcd", false)
        assertMatch("abcd", "abc", false)
    }

    /// "match_pattern wildcard"
    func testMatchPatternWildcard() {
        assertMatch("", "*", true)
        assertMatch("", "**", true)
        assertMatch("", "***", true)
        assertMatch("", "?", false)
        assertMatch("", "*?", false)
        assertMatch("", "?*", false)
        assertMatch("", "**a*", false)
        assertMatch("a", "?", true)
        assertMatch("aa", "a?", true)
        assertMatch("a", "*", true)
        assertMatch("aa", "a*", true)
        assertMatch("aa", "?*", true)
        assertMatch("aa", "?a", true)
        assertMatch("aa", "*a", true)
        assertMatch("ba", "a?", false)
        assertMatch("ba", "a*", false)
        assertMatch("ab", "?a", false)
        assertMatch("ab", "*a", false)
        assertMatch("aa", "**", true)
        assertMatch("ab", "a***b", true)
        assertMatch("axb", "a***b", true)
        assertMatch("axxb", "a***b", true)
        assertMatch("ax", "a***b", false)
        assertMatch("abbb", "a*b*b", true)
        assertMatch("abbb", "a*b*c", false)
        assertMatch("aaaaaaaaac", "a*a*a*a*b", false)
        assertMatch("aaaaaaaaab", "a*a*a*a*b", true)
        assertMatch("ab", "*b", true)
        assertMatch("ab", "*a*", true)
        assertMatch("ab", "*a*b", true)
        assertMatch("ab", "*a*c", false)
        assertMatch("abc", "a?c", true)
        assertMatch("abc", "??c", true)
        assertMatch("abc", "???", true)
        assertMatch("abc", "a?d", false)
        assertMatch("ab", "???", false)
        assertMatch("abc", "ab*", true)
        assertMatch("ab", "ab*", true)
        assertMatch("a", "ab*", false)
        assertMatch("abc", "ab?", true)
        assertMatch("ab", "ab?", false)
        assertMatch("abcd", "ab?", false)
        assertMatch("abc", "?bc", true)
        assertMatch("abc", "?b*", true)
        assertMatch("abc", "?c", false)
        assertMatch("abc", "a*?c", true)
        assertMatch("ac", "a*?c", false)
        assertMatch("abbc", "a*?c", true)
        assertMatch("abc", "a?*c", true)
        assertMatch("ac", "a?*c", false)
        assertMatch("abbc", "a?*c", true)
        assertMatch("abc", "a*?*c", true)
        assertMatch("ac", "a*?*c", false)
        assertMatch("abc", "?*c", true)
        assertMatch("ac", "?*c", true)
        assertMatch("c", "?*c", false)
        assertMatch("abc", "*?c", true)
        assertMatch("ac", "*?c", true)
        assertMatch("c", "*?c", false)
        assertMatch("abc", "a?*", true)
        assertMatch("ab", "a?*", true)
        assertMatch("a", "a?*", false)
        assertMatch("abc", "a*?", true)
        assertMatch("ab", "a*?", true)
        assertMatch("a", "a*?", false)
        assertMatch("abb", "a*b", true)
        assertMatch("abbc", "a*b", false)
    }

    /// "match_pattern_list"
    func testMatchPatternList() {
        func list(_ string: String, _ pattern: String) -> SSHConfigPattern.ListMatch {
            return SSHConfigPattern.matchesList(string, patternList: pattern, lowercasePattern: false)
        }
        XCTAssertEqual(list("", ""), .none)  // no patterns
        XCTAssertEqual(list("", "*"), .positive)
        XCTAssertEqual(list("", "!*"), .negative)
        XCTAssertEqual(list("", "!a,*"), .positive)
        XCTAssertEqual(list("", "*,!a"), .positive)
        XCTAssertEqual(list("", "a,!*"), .negative)
        XCTAssertEqual(list("", "!*,a"), .negative)
        XCTAssertEqual(list("a", ""), .none)
        XCTAssertEqual(list("a", "*"), .positive)
        XCTAssertEqual(list("a", "!*"), .negative)
        XCTAssertEqual(list("a", "!a"), .negative)
        XCTAssertEqual(list("a", "!a,*"), .negative)
        XCTAssertEqual(list("b", "!a,*"), .positive)
        XCTAssertEqual(list("a", "*,!a"), .negative)
        XCTAssertEqual(list("b", "*,!a"), .positive)
        XCTAssertEqual(list("a", "a,!*"), .negative)
        XCTAssertEqual(list("b", "a,!*"), .negative)
        XCTAssertEqual(list("a", "a,!a"), .negative)
        XCTAssertEqual(list("a", "!*,a"), .negative)
        XCTAssertEqual(list("b", "!*,a"), .negative)
    }

    /// "match_pattern_list lowercase"
    func testMatchPatternListLowercase() {
        XCTAssertEqual(SSHConfigPattern.matchesList("abc", patternList: "ABC", lowercasePattern: false), .none)
        XCTAssertEqual(SSHConfigPattern.matchesList("ABC", patternList: "abc", lowercasePattern: false), .none)
        XCTAssertEqual(SSHConfigPattern.matchesList("abc", patternList: "ABC", lowercasePattern: true), .positive)
        XCTAssertEqual(SSHConfigPattern.matchesList("ABC", patternList: "abc", lowercasePattern: true), .none)
    }

    // MARK: - Beyond upstream

    /// match_hostname lowercases the host as well as the pattern.
    func testMatchHostnameIgnoresCaseOnBothSides() {
        XCTAssertEqual(SSHConfigPattern.matchesHostname("Web.Example.COM", patternList: "*.example.com"), .positive)
        XCTAssertEqual(SSHConfigPattern.matchesHostname("web.example.com", patternList: "*.EXAMPLE.com"), .positive)
        XCTAssertEqual(SSHConfigPattern.matchesHostname("WEB", patternList: "!web,*"), .negative)
    }

    /// match_pattern_list's buffer holds 1023 bytes, so a subpattern that long never matches.
    func testOverlongSubpatternNeverMatches() {
        let ok = String(repeating: "a", count: 1022)
        let tooLong = String(repeating: "a", count: 1023)
        XCTAssertEqual(SSHConfigPattern.matchesList(ok, patternList: ok, lowercasePattern: false), .positive)
        XCTAssertEqual(SSHConfigPattern.matchesList(tooLong, patternList: tooLong, lowercasePattern: false), .none)
        XCTAssertEqual(SSHConfigPattern.matchesList(tooLong, patternList: "*," + tooLong, lowercasePattern: false), .none)
    }

    /// Case folding is ASCII-only, as with tolower() in the C locale.
    func testNonASCIIIsNotCaseFolded() {
        XCTAssertEqual(SSHConfigPattern.matchesHostname("ÉCOLE", patternList: "école"), .none)
        XCTAssertEqual(SSHConfigPattern.matchesHostname("école", patternList: "école"), .positive)
    }
}

final class SSHConfigTokenizerTests: XCTestCase {
    private func split(_ s: String, _ terminateOnComment: Bool = false) -> [String]? {
        return SSHConfigTokenizer.splitArguments(s, terminateOnComment: terminateOnComment)
    }

    private func remainder(_ cursor: SSHConfigTokenizer.Cursor) -> String? {
        return cursor.remainder.map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - test_strdelim.c

    /// "empty"
    func testStrdelimEmpty() {
        var c = SSHConfigTokenizer.Cursor("")
        XCTAssertEqual(c.nextString(), "")
        XCTAssertNil(c.nextString())
    }

    /// "whitespace"
    func testStrdelimWhitespace() {
        var c = SSHConfigTokenizer.Cursor("\t")
        XCTAssertEqual(c.nextString(), "")
        XCTAssertEqual(remainder(c), "")
    }

    /// "trivial"
    func testStrdelimTrivial() {
        var c = SSHConfigTokenizer.Cursor("blob")
        XCTAssertEqual(c.nextString(), "blob")
        XCTAssertNil(c.nextString())
        XCTAssertNil(remainder(c))
    }

    /// "trivial whitespace"
    func testStrdelimTrivialWhitespace() {
        var c = SSHConfigTokenizer.Cursor("blob   ")
        XCTAssertEqual(c.nextString(), "blob")
        XCTAssertEqual(remainder(c), "")
        XCTAssertEqual(c.nextString(), "")
        XCTAssertNil(remainder(c))
    }

    /// "multi"
    func testStrdelimMulti() {
        var c = SSHConfigTokenizer.Cursor("blob1 blob2")
        XCTAssertEqual(c.nextString(), "blob1")
        XCTAssertEqual(remainder(c), "blob2")
        XCTAssertEqual(c.nextString(), "blob2")
        XCTAssertNil(remainder(c))
        XCTAssertNil(c.nextString())
    }

    /// "multi whitespace"
    func testStrdelimMultiWhitespace() {
        var c = SSHConfigTokenizer.Cursor("blob1\t \tblob2  \t \t")
        XCTAssertEqual(c.nextString(), "blob1")
        XCTAssertEqual(remainder(c), "blob2  \t \t")
        XCTAssertEqual(c.nextString(), "blob2")
        XCTAssertEqual(c.nextString(), "")
        XCTAssertNil(remainder(c))
    }

    /// "multi equals"
    func testStrdelimMultiEquals() {
        var c = SSHConfigTokenizer.Cursor("blob1=blob2")
        XCTAssertEqual(c.nextString(), "blob1")
        XCTAssertEqual(remainder(c), "blob2")
        XCTAssertEqual(c.nextString(), "blob2")
        XCTAssertNil(remainder(c))
        XCTAssertNil(c.nextString())
    }

    /// "multi too many equals"
    func testStrdelimMultiTooManyEquals() {
        var c = SSHConfigTokenizer.Cursor("blob1==blob2")
        XCTAssertEqual(c.nextString(), "blob1")
        XCTAssertEqual(remainder(c), "=blob2")
        XCTAssertEqual(c.nextString(), "")
        XCTAssertEqual(remainder(c), "blob2")
        XCTAssertEqual(c.nextString(), "blob2")
        XCTAssertNil(remainder(c))
    }

    /// "multi equals strdelimw"
    func testStrdelimwMultiEquals() {
        var c = SSHConfigTokenizer.Cursor("blob1=blob2")
        XCTAssertEqual(c.nextString(splitEquals: false), "blob1=blob2")
        XCTAssertNil(remainder(c))
        XCTAssertNil(c.nextString(splitEquals: false))
    }

    /// "quoted"
    func testStrdelimQuoted() {
        var c = SSHConfigTokenizer.Cursor("\"blob\"")
        XCTAssertEqual(c.nextString(), "blob")
        XCTAssertEqual(c.nextString(), "")
        XCTAssertNil(remainder(c))
    }

    /// "quoted multi"
    func testStrdelimQuotedMulti() {
        var c = SSHConfigTokenizer.Cursor("\"blob1\" blob2")
        XCTAssertEqual(c.nextString(), "blob1")
        XCTAssertEqual(remainder(c), "blob2")
        XCTAssertEqual(c.nextString(), "blob2")
        XCTAssertNil(remainder(c))
        XCTAssertNil(c.nextString())
    }

    /// "quoted multi reverse"
    func testStrdelimQuotedMultiReverse() {
        var c = SSHConfigTokenizer.Cursor("blob1 \"blob2\"")
        XCTAssertEqual(c.nextString(), "blob1")
        XCTAssertEqual(remainder(c), "\"blob2\"")
        XCTAssertEqual(c.nextString(), "blob2")
        XCTAssertEqual(remainder(c), "")
        XCTAssertEqual(c.nextString(), "")
        XCTAssertNil(remainder(c))
    }

    /// "quoted multi middle"
    func testStrdelimQuotedMultiMiddle() {
        var c = SSHConfigTokenizer.Cursor("blob1 \"blob2\" blob3")
        XCTAssertEqual(c.nextString(), "blob1")
        XCTAssertEqual(c.nextString(), "blob2")
        XCTAssertEqual(c.nextString(), "blob3")
        XCTAssertNil(c.nextString())
    }

    /// "badquote"
    func testStrdelimBadQuote() {
        var c = SSHConfigTokenizer.Cursor("\"blob")
        XCTAssertNil(c.nextString())
    }

    /// "oops quote"
    func testStrdelimOopsQuote() {
        var c = SSHConfigTokenizer.Cursor("\"blob\\\"")
        XCTAssertEqual(c.nextString(), "blob\\")
        XCTAssertEqual(c.nextString(), "")
    }

    // MARK: - test_argv.c

    /// "empty args"
    func testArgvEmpty() {
        XCTAssertEqual(split(""), [])
        XCTAssertEqual(split("    "), [])
    }

    /// "trivial args"
    func testArgvTrivial() {
        XCTAssertEqual(split("leamas"), ["leamas"])
        XCTAssertEqual(split("smiley leamas"), ["smiley", "leamas"])
    }

    /// "quoted"
    func testArgvQuoted() {
        XCTAssertEqual(split("\"smiley\""), ["smiley"])
        XCTAssertEqual(split("leamas \" smiley \""), ["leamas", " smiley "])
        XCTAssertEqual(split("\"smiley leamas\""), ["smiley leamas"])
        XCTAssertEqual(split("smiley\" leamas\" liz"), ["smiley leamas", "liz"])
    }

    /// "escaped"
    func testArgvEscaped() {
        XCTAssertEqual(split("\\\"smiley\\'"), ["\"smiley'"])
        XCTAssertEqual(split("'\\'smiley\\\"'"), ["'smiley\""])
        XCTAssertEqual(split("smiley\\'s leamas\\'"), ["smiley's", "leamas'"])
        XCTAssertEqual(split("leamas\\\\smiley"), ["leamas\\smiley"])
        XCTAssertEqual(split("leamas\\\\ \\\\smiley"), ["leamas\\", "\\smiley"])
        XCTAssertEqual(split("smiley\\ leamas"), ["smiley leamas"])
    }

    /// "quoted escaped"
    func testArgvQuotedEscaped() {
        XCTAssertEqual(split("'smiley\\ leamas'"), ["smiley\\ leamas"])
        XCTAssertEqual(split("\"smiley\\ leamas\""), ["smiley\\ leamas"])
    }

    /// "comments"
    func testArgvComments() {
        XCTAssertEqual(split("# gold"), ["#", "gold"])
        XCTAssertEqual(split("# gold", true), [])
        XCTAssertEqual(split("leamas#gold", true), ["leamas#gold"])
        XCTAssertEqual(split("\"leamas # gold\"", true), ["leamas # gold"])
        XCTAssertEqual(split("\"leamas\"#gold", true), ["leamas#gold"])
    }

    // MARK: - Beyond upstream

    func testArgvUnterminatedQuoteFails() {
        XCTAssertNil(split("leamas \"smiley"))
        XCTAssertNil(split("'smiley"))
    }

    func testArgvTrailingBackslashIsKept() {
        XCTAssertEqual(split("smiley\\"), ["smiley\\"])
    }

    func testArgvCommentAfterArguments() {
        XCTAssertEqual(split("web prod # comment", true), ["web", "prod"])
    }
}

final class SSHConfigExpansionTests: XCTestCase {
    private let environment = ["FOO": "bar", "BAR": "baz"]

    private func dollar(_ s: String) -> Result<String, SSHConfigExpansion.Failure> {
        return SSHConfigExpansion.expand(s, environment: environment)
    }

    /// "dollar_expand"
    func testDollarExpand() {
        XCTAssertEqual(dollar("${FOO}"), .success("bar"))
        XCTAssertEqual(dollar(" ${FOO}"), .success(" bar"))
        XCTAssertEqual(dollar("${FOO} "), .success("bar "))
        XCTAssertEqual(dollar(" ${FOO} "), .success(" bar "))
        XCTAssertEqual(dollar("${FOO}${BAR}"), .success("barbaz"))
        XCTAssertEqual(dollar(" ${FOO} ${BAR}"), .success(" bar baz"))
        XCTAssertEqual(dollar("${FOO}${BAR} "), .success("barbaz "))
        XCTAssertEqual(dollar(" ${FOO} ${BAR} "), .success(" bar baz "))
        XCTAssertEqual(dollar("$"), .success("$"))
        XCTAssertEqual(dollar(" $"), .success(" $"))
        XCTAssertEqual(dollar("$ "), .success("$ "))

        // A variable that isn't set is not a parse error.
        for s in ["a${BAZ}", "${BAZ}b", "a${BAZ}b"] {
            let result = dollar(s)
            XCTAssertEqual(result, .failure(.missingVariable("BAZ")), s)
            if case .failure(let failure) = result {
                XCTAssertFalse(failure.isParseError, s)
            }
        }
        // Invalid format.
        XCTAssertEqual(dollar("${"), .failure(.unclosedVariable))
        XCTAssertEqual(dollar("${F"), .failure(.unclosedVariable))
        XCTAssertEqual(dollar("${FO"), .failure(.unclosedVariable))
        // Empty variable name.
        XCTAssertEqual(dollar("${}"), .failure(.emptyVariableName))
    }

    /// "percent_expand"
    func testPercentExpand() {
        XCTAssertEqual(SSHConfigExpansion.expand("%%", percentTokens: ["%h": "foo"]), .success("%"))
        XCTAssertEqual(SSHConfigExpansion.expand("%h", percentTokens: ["h": "foo"]), .success("foo"))
        XCTAssertEqual(SSHConfigExpansion.expand("%h ", percentTokens: ["h": "foo"]), .success("foo "))
        XCTAssertEqual(SSHConfigExpansion.expand(" %h", percentTokens: ["h": "foo"]), .success(" foo"))
        XCTAssertEqual(SSHConfigExpansion.expand(" %h ", percentTokens: ["h": "foo"]), .success(" foo "))
        XCTAssertEqual(SSHConfigExpansion.expand(" %a%b ", percentTokens: ["a": "foo", "b": "bar"]),
                       .success(" foobar "))
    }

    /// "percent_dollar_expand"
    func testPercentDollarExpand() {
        XCTAssertEqual(SSHConfigExpansion.expand("%h${FOO}", percentTokens: ["h": "foo"], environment: environment),
                       .success("foobar"))
    }

    // MARK: - Beyond upstream

    func testPercentErrors() {
        XCTAssertEqual(SSHConfigExpansion.expand("abc%", percentTokens: ["h": "foo"]), .failure(.trailingPercent))
        XCTAssertEqual(SSHConfigExpansion.expand("%z", percentTokens: ["h": "foo"]), .failure(.unknownToken("z")))
    }

    /// Without tokens, % is literal; without an environment, $ is literal.
    func testExpansionKindsAreIndependent() {
        XCTAssertEqual(SSHConfigExpansion.expand("%h${FOO}"), .success("%h${FOO}"))
        XCTAssertEqual(SSHConfigExpansion.expand("%h${FOO}", environment: environment), .success("%hbar"))
        XCTAssertEqual(SSHConfigExpansion.expand("%h${FOO}", percentTokens: ["h": "x"]), .success("x${FOO}"))
    }

    /// As in OpenSSH, a parse error later in the string wins over an earlier missing variable.
    func testParseErrorWinsOverMissingVariable() {
        XCTAssertEqual(SSHConfigExpansion.expand("${BAZ}%z", percentTokens: ["h": "x"], environment: environment),
                       .failure(.unknownToken("z")))
    }
}

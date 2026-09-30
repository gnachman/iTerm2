//
//  NSURLITermCategoryTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermNSURLCategoryTest.m. Covers the NSURL (iTerm) category:
//  urlByReplacingFormatSpecifier:inString:withValue:, URLWithUserSuppliedString:,
//  URLByRemovingFragment and URLByAppendingQueryParameter:.
//
//  The legacy tests also called the private +URLWithUserSuppliedStringImpl: directly. It is not
//  declared in NSURL+iTerm.h so those calls are not ported; the public entry point is exercised
//  instead. Issue 12914 style inputs (mixed percent-encoding) live in NSURLUserSuppliedStringTests.m.
//

import XCTest
@testable import iTerm2SharedARC

final class NSURLITermCategoryTests: XCTestCase {

    // MARK: - Helpers

    private func replacing(_ string: String, with value: String = "value") -> String? {
        return NSURL(byReplacingFormatSpecifier: "%@", in: string, withValue: value)?.absoluteString
    }

    private func userSupplied(_ string: String) -> String? {
        return NSURL(userSuppliedString: string)?.absoluteString
    }

    private func removingFragment(_ string: String) throws -> String? {
        let url = try XCTUnwrap(NSURL(string: string))
        return url.removingFragment().absoluteString
    }

    private func appendingQuery(_ string: String, _ parameter: String = "x=y") throws -> String? {
        let url = try XCTUnwrap(NSURL(string: string))
        return url.appendingQueryParameter(parameter).absoluteString
    }

    // MARK: - urlByReplacingFormatSpecifier:inString:withValue:

    func testURLByReplacingFormatSpecifier_QueryValue() {
        XCTAssertEqual(replacing("https://example.com/?a=1&b=%@&c=3"),
                       "https://example.com/?a=1&b=value&c=3")
    }

    func testURLByReplacingFormatSpecifier_QueryName() {
        XCTAssertEqual(replacing("https://example.com/?a=1&%@=2&c=3"),
                       "https://example.com/?a=1&value=2&c=3")
    }

    func testURLByReplacingFormatSpecifier_Fragment() {
        XCTAssertEqual(replacing("https://example.com/?a=1&b=2&c=3#fragment%@"),
                       "https://example.com/?a=1&b=2&c=3#fragmentvalue")
    }

    func testURLByReplacingFormatSpecifier_Path() {
        XCTAssertEqual(replacing("https://example.com/a/%@/b?a=1&b=2&c=3#fragment"),
                       "https://example.com/a/value/b?a=1&b=2&c=3#fragment")
    }

    func testURLByReplacingFormatSpecifier_Host() {
        XCTAssertEqual(replacing("https://%@.example.com/a/c/b?a=1&b=2&c=3#fragment"),
                       "https://value.example.com/a/c/b?a=1&b=2&c=3#fragment")
    }

    func testURLByReplacingFormatSpecifier_User() {
        XCTAssertEqual(replacing("https://%@:password@example.com/a/c/b?a=1&b=2&c=3#fragment"),
                       "https://value:password@example.com/a/c/b?a=1&b=2&c=3#fragment")
    }

    func testURLByReplacingFormatSpecifier_Password() {
        XCTAssertEqual(replacing("https://user:%@@example.com/a/c/b?a=1&b=2&c=3#fragment"),
                       "https://user:value@example.com/a/c/b?a=1&b=2&c=3#fragment")
    }

    // MARK: - URLWithUserSuppliedString:

    func testURLWithUserSuppliedString_NonAsciiPath() {
        let string = "http://wiki.teamliquid.net/commons/images/thumb/a/af/Torbjörn-Barbarossa.jpg/580px-Torbjörn-Barbarossa.jpg"
        XCTAssertEqual(userSupplied(string),
                       "http://wiki.teamliquid.net/commons/images/thumb/a/af/Torbj%C3%B6rn-Barbarossa.jpg/580px-Torbj%C3%B6rn-Barbarossa.jpg")
    }

    func testURLWithUserSuppliedString_NonAsciiFragment() {
        XCTAssertEqual(userSupplied("http://example.com/path?a=b&c=d#Torbjörn"),
                       "http://example.com/path?a=b&c=d#Torbj%C3%B6rn")
    }

    func testURLWithUserSuppliedString_IDN() {
        XCTAssertEqual(userSupplied("http://中国.icom.museum/"), "http://xn--fiqs8s.icom.museum/")
    }

    func testURLWithUserSuppliedString_Acid() {
        let scheme = "a1+-."
        let user = "%20;"
        let port = "1"
        let input = "\(scheme)://\(user):&=+$,é%20;&=+$,@á中国.icom.museum:\(port)/%20Torbjörn?%20国=%20中&ö#%20é./?:~ñ"
        let expected = "\(scheme)://\(user):&=+$,%C3%A9%20;&=+$,@xn--1ca0960bnsf.icom.museum:\(port)/%20Torbj%C3%B6rn?%20%E5%9B%BD=%20%E4%B8%AD&%C3%B6#%20%C3%A9./?:~%C3%B1"
        XCTAssertEqual(userSupplied(input), expected)
    }

    func testURLWithUserSuppliedString_ManyParts() {
        let string = "https://example.com:6088/projects/repos/applications/pull-requests?create&sourceBranch=refs/heads/feature/myfeature"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_Fragment() {
        let string = "http://www.wikiwand.com/en/URL#/Internationalized_URL"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_TrailingPercentIsEscaped() {
        XCTAssertEqual(userSupplied("Georges-Mac-Pro:/Users/gnachman%"),
                       "Georges-Mac-Pro:/Users/gnachman%25")
    }

    func testURLWithUserSuppliedString_UrlInQuery() {
        let string = "https://google.com/search?q=http://google.com/"
        XCTAssertEqual(userSupplied(string), string)
    }

    // Issue 9507: don't rewrite %2B in query param to +
    func testURLWithUserSuppliedString_PreservePercentEncodingInQuery() {
        let string = "https://example.com/comm-smart-app/services/tracking/clickTracker?redirectTo=mB%2BJRRrvxRgcA3BQdTZqeVc3kNSQabbmxDhMJWX2U8PPEyOy4T8YWs0/mIZXn3tmmXaqznkrNHDf/40zBB1C9PZHO8EE7LlbT/yUHb0XvJ3FbeOuh667HLHspSZQD1wUCukq36iPRB4p7HdSYGAgsI9VnSt2Trynpzx64NPwe3UV3hnyeyJpYF9R07kH8T3puAMcP6JMYyKoOcZK8wEJ08Nli65jC4qvRbEexv5aHix%2B5JsGBUmX4PPkf0gtc4CEiGu9hhFjjWikGm57cCqD09TH4Ag5/nyXnsllpRlrmTOifCuRrcD/ETLLd2WvNaTHDRIXQDbuhmf%2BeC/ojMpybrmRZzg7iDW8om1elIdGLt%2BKMr6b5FLKjT6AMJ4qczdUBSlkjCnNPSYJovQpe5Pm%2B3F4LgcFLD7diQCoC5zFogwZKQZUJHVtYy%2BIfBsQRsWqjlo1evykxHLkVUVqMnOcpEePXOqTGzM6wiwxojf6PrwzAEGN8Qq7zwiURKEJcr8/kfjxZoA%2BuwuuiJibILpwHNovYSuOKrkepPWVenmB15u5OWHjPqZ4fulkLY%2Bv3xCbutX8UwbMkAUfaZIIGxOEGt9QWFid58hYganfe5WRCw%2Bn3EPxkNKvG6bvqt4hhS9rdI0/IlBdNy8gXFVCdfrJJ0aEmyVc6CRbuLIs/KCsOitaq%2BnCC1OlN3lCGBtE8alOB9ZxXiZOKPuXX8cyE%2By/FihNwxURQtnj4qowz9ZrnMOy1A%2BM8%2BQb0kNjSv3Vr%2B1ppG9P5YSHz6bdSNBOUkCJKknxREZA5r6Gwu6x53emuic%3D&meta=Ioe%2BWzf9FSPYt%2B9%2Ftf%2Bu7IE9bCUGf5FGiRWJBCZQQh1rVILL5VMY3FtyU5flA4FQNzwiL3lL4MlSXwrNWLpEgl4G6IzTGbzOeg%2BzIa6vhAK%2BMWxcosPQBTiTSlVUbNQJ1csgZjCXA19KUhxfTQ22JhfoAQDRlHiabxzrqfb1eDtO8fSFyMrt4G6eVeFBX5ZSjRz8RZV%2B6W%2Bwyo61Usd01oSCYCpRspmeGwlsQ6zoFbw%3D&iv=uiWo5jAQor%2BBep2ZbdgK1w%3D%3D"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_PreservePercentEncodingInPath() {
        let string = "https://www.jenkins.io/test-url/parentProject%2FchildProject/detail/childProject/24/pipeline"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_EscapesQueryParamsIfNeeded() {
        XCTAssertEqual(userSupplied("https://google.com/search?q=résumé+help%2B"),
                       "https://google.com/search?q=r%C3%A9sum%C3%A9+help%2B")
    }

    func testURLWithUserSuppliedString_IPv6NoPort() {
        let string = "http://[2607:f8b0:4005:807::200e]/"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_IPv6Port() {
        let string = "http://[2607:f8b0:4005:807::200e]:8080/"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_Port() {
        let string = "http://example.com:8080/"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_User() {
        let string = "http://user@example.com:8080/"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_UserAndPassword() {
        let string = "http://user:password@example.com:8080/"
        XCTAssertEqual(userSupplied(string), string)
    }

    func testURLWithUserSuppliedString_IDNWithPortAndPath() {
        XCTAssertEqual(userSupplied("http://á中国.icom.museum:1/path"),
                       "http://xn--1ca0960bnsf.icom.museum:1/path")
    }

    // https://gitlab.com/gnachman/iterm2/-/issues/9598
    func testURLWithUserSuppliedString_PreserveSemicolonsInPath() {
        let string = "https://source.chromium.org/chromium/chromium/src/+/73104b9724fbd9aed8510807cb62e6a55e43b018:v8/test/unittests/compiler/x64/instruction-selector-x64-unittest.cc;l=2247-2249"
        XCTAssertEqual(userSupplied(string), string)
    }

    // MARK: - URLByRemovingFragment

    func testURLByRemovingFragment_NoFragment() throws {
        XCTAssertEqual(try removingFragment("http://user:pass@iterm2.com/foo"),
                       "http://user:pass@iterm2.com/foo")
    }

    func testURLByRemovingFragment_EmptyFragment() throws {
        XCTAssertEqual(try removingFragment("http://user:pass@iterm2.com/foo#"),
                       "http://user:pass@iterm2.com/foo")
    }

    func testURLByRemovingFragment_HasFragment() throws {
        XCTAssertEqual(try removingFragment("http://user:pass@iterm2.com/foo#bar"),
                       "http://user:pass@iterm2.com/foo")
    }

    // MARK: - URLByAppendingQueryParameter:

    func testURLByAppendingQueryParameter_NoQueryNoFragment() throws {
        XCTAssertEqual(try appendingQuery("http://user:pass@iterm2.com/foo"),
                       "http://user:pass@iterm2.com/foo?x=y")
    }

    func testURLByAppendingQueryParameter_HasQueryNoFragment() throws {
        XCTAssertEqual(try appendingQuery("http://user:pass@iterm2.com/foo?a=b"),
                       "http://user:pass@iterm2.com/foo?a=b&x=y")
    }

    func testURLByAppendingQueryParameter_NoQueryHasFragment() throws {
        XCTAssertEqual(try appendingQuery("http://user:pass@iterm2.com/foo#f"),
                       "http://user:pass@iterm2.com/foo?x=y#f")
    }

    func testURLByAppendingQueryParameter_NoQueryHasEmptyFragment() throws {
        XCTAssertEqual(try appendingQuery("http://user:pass@iterm2.com/foo#"),
                       "http://user:pass@iterm2.com/foo?x=y#")
    }

    func testURLByAppendingQueryParameter_HasQueryHasFragment() throws {
        XCTAssertEqual(try appendingQuery("http://user:pass@iterm2.com/foo?a=b#f"),
                       "http://user:pass@iterm2.com/foo?a=b&x=y#f")
    }

    func testURLByAppendingQueryParameter_EmptyQueryNoFragment() throws {
        XCTAssertEqual(try appendingQuery("http://user:pass@iterm2.com/foo?"),
                       "http://user:pass@iterm2.com/foo?x=y")
    }

    func testURLByAppendingQueryParameter_EmptyQueryHasFragment() throws {
        XCTAssertEqual(try appendingQuery("http://user:pass@iterm2.com/foo?#f"),
                       "http://user:pass@iterm2.com/foo?x=y#f")
    }
}

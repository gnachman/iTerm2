//
//  HTMLTabTitleEntityTests.swift
//  iTerm2
//
//  With HTML tab titles on, the &lt; and &amp; entities must be decoded
//  whether or not the title also contains a formatting tag.
//

import XCTest
@testable import iTerm2SharedARC

final class HTMLTabTitleEntityTests: XCTestCase {
    private var saved: Any?

    override func setUp() {
        super.setUp()
        saved = iTermPreferences.object(forKey: kPreferenceKeyHTMLTabTitles)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyHTMLTabTitles)
    }

    override func tearDown() {
        iTermPreferences.setObject(saved, forKey: kPreferenceKeyHTMLTabTitles)
        super.tearDown()
    }

    func testEntitiesDecodedWithTag() {
        XCTAssertEqual(("<b>bold</b> &amp; x" as NSString).removingHTMLFromTabTitleIfNeeded(),
                       "bold & x")
    }

    func testAmpersandEntityDecodedWithoutTag() {
        XCTAssertEqual(("bold &amp; x" as NSString).removingHTMLFromTabTitleIfNeeded(),
                       "bold & x")
    }

    func testLessThanEntityDecodedWithoutTag() {
        XCTAssertEqual(("&lt;b>" as NSString).removingHTMLFromTabTitleIfNeeded(),
                       "<b>")
    }

    func testPlainTitleUnchanged() {
        XCTAssertEqual(("a < b & c" as NSString).removingHTMLFromTabTitleIfNeeded(),
                       "a < b & c")
    }
}

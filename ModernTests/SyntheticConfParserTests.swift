//
//  SyntheticConfParserTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermSyntheticConfParserTests.m.
//
//  The legacy tests fed fake file contents to iTermSyntheticConfParser by overriding its private
//  +contents class method, which is not declared in iTermSyntheticConfParser+Private.h, so the
//  parsing tests (empty, valid and malformed synthetic.conf contents) are not ported. The path
//  substitution tests are ported against iTermSyntheticDirectory, the per-entry mapping object
//  that the parser consults in order, using the entries from the synthetic.conf man page example:
//
//      bar   System/Volumes/Data/bar
//      baz   Users/me/baz
//

import XCTest
@testable import iTerm2SharedARC

final class SyntheticConfParserTests: XCTestCase {
    private var directories: [iTermSyntheticDirectory] = []

    override func setUp() {
        super.setUp()
        directories = [iTermSyntheticDirectory(root: "bar", target: "System/Volumes/Data/bar"),
                       iTermSyntheticDirectory(root: "baz", target: "Users/me/baz")]
    }

    // Mirrors -[iTermSyntheticConfParser pathByReplacingPrefixWithSyntheticRoot:]: the first
    // matching entry wins and a path that matches none is returned unchanged.
    private func substitute(_ path: String) -> String {
        for directory in directories {
            if let result = directory.pathByReplacingPrefix(withSyntheticRoot: path) {
                return result
            }
        }
        return path
    }

    func testDirectoryEntriesGetLeadingSlashes() {
        XCTAssertEqual(directories[0].root, "/bar")
        XCTAssertEqual(directories[0].target, "/System/Volumes/Data/bar")
        XCTAssertEqual(directories[1].root, "/baz")
        XCTAssertEqual(directories[1].target, "/Users/me/baz")
    }

    func testDirectoryEntriesKeepExistingLeadingSlashes() throws {
        let directory = try XCTUnwrap(iTermSyntheticDirectory(root: "/foo", target: "/Users/me/foo"))
        XCTAssertEqual(directory.root, "/foo")
        XCTAssertEqual(directory.target, "/Users/me/foo")
    }

    func testSubstituteExactRoot() {
        XCTAssertEqual(substitute("/Users/me/baz"), "/baz")
        XCTAssertEqual(substitute("/System/Volumes/Data/bar"), "/bar")
    }

    func testSubstituteRootWithTrailingSlash() {
        XCTAssertEqual(substitute("/Users/me/baz/"), "/baz/")
    }

    func testSubstitutePathPrefix() {
        XCTAssertEqual(substitute("/Users/me/baz/foo"), "/baz/foo")
    }

    func testDoNotSubstituteNonPathPrefix() {
        XCTAssertEqual(substitute("/bazX"), "/bazX")
    }

    func testDirectoryReturnsNilForNonMatchingPath() {
        XCTAssertNil(directories[1].pathByReplacingPrefix(withSyntheticRoot: "/Users/me/bazX"))
        XCTAssertNil(directories[1].pathByReplacingPrefix(withSyntheticRoot: "/Users/me"))
    }
}

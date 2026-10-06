//
//  CodeReviewIt2PathTests.swift
//  iTerm2 ModernTests
//
//  The code review prompt tells Claude Code to run it2. By name, that needs it2 on PATH, which an
//  old shell integration install on a remote host does not provide. So the prompt says {{it2}},
//  and iTerm2 fills in the one to run when it writes the prompt file at launch: the app's own it2
//  on this Mac, the uploaded wrapper on a host reached through SSH Integration.
//

import XCTest
@testable import iTerm2SharedARC

final class CodeReviewIt2PathTests: XCTestCase {
    func testRemoteUsesTheUploadedWrapper() {
        XCTAssertEqual(CodeReviewIt2.command(onRemoteHost: true, bundlePath: "/Applications/iTerm.app"),
                       #""$HOME/.iterm2/bin/it2""#)
    }

    // A bundle path can hold spaces or an apostrophe; it is one shell word either way.
    func testLocalUsesTheAppsOwnIt2Quoted() {
        XCTAssertEqual(CodeReviewIt2.command(onRemoteHost: false, bundlePath: "/Applications/iTerm.app"),
                       "'/Applications/iTerm.app/Contents/Resources/utilities/it2'")
        XCTAssertEqual(CodeReviewIt2.command(onRemoteHost: false, bundlePath: "/Users/me/George's iTerm2 Beta.app"),
                       #"'/Users/me/George'\''s iTerm2 Beta.app/Contents/Resources/utilities/it2'"#)
    }

    func testEveryPlaceholderIsFilledIn() {
        XCTAssertEqual(CodeReviewIt2.substitute("{{it2}} a\n{{it2}} b", command: "X"), "X a\nX b")
    }

    // The settings file is JSON: the command goes inside a JSON string, quotes and all, and the
    // result must still parse to the command.
    func testJSONSubstitutionStaysValid() throws {
        let template = Data(#"{"autoMode":{"allow":["Running `{{it2}} session add-clipping` is allowed."]}}"#.utf8)
        for command in [#""$HOME/.iterm2/bin/it2""#, #"'/a/b'\''c.app/Contents/Resources/utilities/it2'"#] {
            let data = CodeReviewIt2.substituteInJSON(template, command: command)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let allow = try XCTUnwrap((object["autoMode"] as? [String: Any])?["allow"] as? [String])
            XCTAssertEqual(allow, ["Running `\(command) session add-clipping` is allowed."])
        }
    }

    // A prompt someone customized without the placeholder is theirs; it runs it2 by name.
    func testTextWithoutThePlaceholderIsUnchanged() {
        XCTAssertEqual(CodeReviewIt2.substitute("it2 session list", command: "X"), "it2 session list")
    }

    // The defaults use it, so nobody who kept them depends on PATH.
    func testBundledFilesUseThePlaceholder() throws {
        for name in ["code-review-system-prompt", "code-review-settings"] {
            let url = try XCTUnwrap(Bundle(for: PTYSession.self).url(forResource: name, withExtension: "txt"), name)
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains("{{it2}} session"), name)
            XCTAssertFalse(text.contains("`it2 session") || text.range(of: #"(^|\n)it2 session"#, options: .regularExpression) != nil,
                           "\(name) still runs it2 by name")
        }
    }

    // The local path names a real program in the app.
    func testLocalPathExists() {
        let bundle = Bundle(for: PTYSession.self).bundlePath
        XCTAssertTrue(FileManager.default.isExecutableFile(
            atPath: bundle + "/Contents/Resources/utilities/it2"), bundle)
    }
}

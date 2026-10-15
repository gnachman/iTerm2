//
//  OrchestrationGrantNoticeMarkdownTests.swift
//  iTerm2
//
//  The notice shown when an @-mention grants control of a session must show
//  the session's name as is: underscores were read as emphasis markup, so
//  “my_dev_box (-zsh)” appeared as “mydevbox (-zsh)”. QA finding F-113.
//

import XCTest
@testable import iTerm2SharedARC

final class OrchestrationGrantNoticeMarkdownTests: XCTestCase {
    func testUnderscoresInSessionNameSurvive() {
        for name in ["my_dev_box (-zsh)", "a_b_c (-zsh)", "*star* [x]"] {
            let markdown = Message.orchestrationPermissionGrantedMarkdown(name: name)
            let rendered = AttributedStringForSystemMessageMarkdown(markdown) {}.string
            XCTAssertTrue(rendered.contains("\u{201C}\(name)\u{201D}"), "\(name) rendered as: \(rendered)")
        }
    }
}

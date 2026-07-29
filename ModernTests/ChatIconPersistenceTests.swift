//
//  ChatIconPersistenceTests.swift
//  ModernTests
//
//  Created by George Nachman on 6/10/25.
//
//  Covers the SQLite plumbing for Chat.icon, the generated chat-list
//  icon. Mirrors the agentReasoning column tests in
//  AIChatMessagePersistenceTests: schema, both migration directions, and
//  parameter binding in the insert and update paths.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatIconPersistenceTests: XCTestCase {
    private static let preIconColumns = [
        "uuid", "title", "creationDate", "lastModifiedDate",
        "orchestrationEnabled", "sessionGuid", "browserSessionGuid",
        "permissions", "vectorStore", "claimedScopes", "watchers"
    ]

    func testChatSchema_declaresIconColumn() {
        let schema = Chat.schema()
        XCTAssertTrue(schema.contains("icon"),
                      "schema must declare icon column; got: \(schema)")
    }

    /// Existing databases (without an icon column) must get a migration
    /// step that adds it; otherwise upgrades from builds predating the
    /// chat icons feature would fail every icon write.
    func testChatMigrations_addsIcon_whenColumnMissing() {
        let migrations = Chat.migrations(existingColumns: Self.preIconColumns)
        XCTAssertTrue(migrations.contains { $0.query.contains("icon") },
                      "migrations must add icon when missing; got: \(migrations.map { $0.query })")
    }

    /// And the migration must NOT re-add the column on databases that
    /// already have it (otherwise SQLite throws "duplicate column name").
    func testChatMigrations_skipsIcon_whenColumnPresent() {
        let migrations = Chat.migrations(existingColumns: Self.preIconColumns + ["icon"])
        XCTAssertFalse(migrations.contains { $0.query.contains("icon") },
                       "migrations must not re-add icon when already present")
    }

    func testChatAppendQuery_bindsIcon() {
        var chat = Chat(title: "Test chat", permissions: "")
        let payload = Data([0x89, 0x50, 0x4e, 0x47])
        chat.icon = payload
        let (sql, args) = chat.appendQuery()
        XCTAssertTrue(sql.contains("icon"),
                      "appendQuery must reference the icon column; got: \(sql)")
        XCTAssertTrue(args.contains { ($0 as? Data) == payload },
                      "appendQuery args must include the icon data; got: \(args)")
    }

    /// updateQuery() must also bind icon so subsequent UPDATEs (renames,
    /// session binding changes, etc.) don't silently drop a saved icon
    /// back to NULL.
    func testChatUpdateQuery_bindsIcon() {
        var chat = Chat(title: "Test chat", permissions: "")
        let payload = Data([0x89, 0x50, 0x4e, 0x47])
        chat.icon = payload
        let (sql, args) = chat.updateQuery()
        XCTAssertTrue(sql.contains("icon"),
                      "updateQuery must reference the icon column; got: \(sql)")
        XCTAssertTrue(args.contains { ($0 as? Data) == payload },
                      "updateQuery args must include the icon data; got: \(args)")
    }

    /// The shipped default Chat List Icon prompt template (Settings >
    /// General > AI > Prompts) must interpolate the chat title via
    /// \(ai.subject). This guards the ObjC string escaping in
    /// iTermPreferences.m: if the backslash gets mangled, the literal
    /// text "ai.subject" would be sent to the model instead of the title.
    /// Evaluates the shipped constant, not the preference, so a
    /// customized prompt on the host machine cannot affect the result.
    func testChatIconPromptTemplate_substitutesSubject() {
        let subject = "Woodchuck Tongue Twister"
        let evaluated = expectation(description: "template evaluated")
        var resolved = ""
        ChatIconGenerator.evaluatePromptTemplate(iTermDefaultAIPromptChatIcon,
                                                 subject: subject) { value in
            resolved = value
            evaluated.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertTrue(resolved.contains(subject),
                      "evaluated template must contain the subject; got: \(resolved)")
        XCTAssertFalse(resolved.contains("ai.subject"),
                       "evaluated template must not contain the unsubstituted variable; got: \(resolved)")
    }

    // MARK: - SVG extraction

    private let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\"/></svg>"

    func testExtractSVG_bareDocument() {
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: svg), svg)
    }

    func testExtractSVG_stripsFencesAndProse() {
        let reply = "Here you go:\n```svg\n\(svg)\n```\nEnjoy!"
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: reply), svg)
    }

    /// Prose after the document that mentions the closing tag must not
    /// extend the span: a backwards search for the last "</svg>" would
    /// capture the junk in between and CoreSVG would reject the bytes.
    func testExtractSVG_ignoresClosingTagInTrailingProse() {
        let reply = "\(svg)\nNote that the document ends with </svg> as required."
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: reply), svg)
    }

    func testExtractSVG_handlesNestedSVGElements() {
        let nested = "<svg viewBox=\"0 0 10 10\"><svg x=\"1\"><rect/></svg></svg>"
        let reply = "```\n\(nested)\n```"
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: reply), nested)
    }

    func testExtractSVG_unbalancedReturnsNil() {
        XCTAssertNil(ChatIconGenerator.extractSVG(from: "<svg viewBox=\"0 0 10 10\"><rect/>"))
        XCTAssertNil(ChatIconGenerator.extractSVG(from: "no svg here"))
    }

    /// Prose before the document that mentions the bare tag must not
    /// become the extraction start: scanning from it never balances, so
    /// extraction must retry from the real document.
    func testExtractSVG_skipsUnbalancedTagMentionBeforeDocument() {
        let reply = "Here is an <svg> document: \(svg)"
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: reply), svg)
    }

    /// A self-closing nested <svg .../> is legal SVG and must not be
    /// counted as an unclosed open tag.
    func testExtractSVG_handlesSelfClosingNestedElement() {
        let doc = "<svg viewBox=\"0 0 10 10\"><svg x=\"1\"/><rect/></svg>"
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: doc), doc)
    }

    /// Tokens that merely start with "<svg", like <svgfoo>, are not
    /// opening tags and must not poison extraction.
    func testExtractSVG_ignoresTokensThatMerelyStartWithSVG() {
        let reply = "<svgfoo> is not a tag. \(svg)"
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: reply), svg)
    }

    /// A self-closing <svg/> mentioned in prose must not preempt a real
    /// document later in the reply; it can only win as a last resort.
    func testExtractSVG_selfClosingMentionDoesNotPreemptRealDocument() {
        let reply = "A minimal SVG is just <svg/>. Here is your icon: \(svg)"
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: reply), svg)
    }

    func testExtractSVG_selfClosingRootIsLastResort() {
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: "Trivial: <svg/> only."), "<svg/>")
    }

    /// Closing tags that merely start with "</svg", like </svgText>, are
    /// not our close and must not end the span mid-document.
    func testExtractSVG_ignoresCloseTagsThatMerelyStartWithSVG() {
        let doc = "<svg viewBox=\"0 0 10 10\"><svgText>x</svgText><rect/></svg>"
        XCTAssertEqual(ChatIconGenerator.extractSVG(from: doc), doc)
    }

    /// A balanced bare <svg>...</svg> pair in prose before the document
    /// extracts first, but the real document must still be offered as a
    /// later candidate so rasterization can fall through to it.
    func testExtractSVGCandidates_offersDocumentAfterBalancedProsePair() {
        let reply = "Output is wrapped in <svg>...</svg> tags: \(svg)"
        let candidates = ChatIconGenerator.extractSVGCandidates(from: reply)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.last, svg)
    }
}

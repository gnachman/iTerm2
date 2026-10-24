//
//  ChatMentionChipIconTests.swift
//  iTerm2 ModernTests
//
//  The chip inserted for an @-mention shows an icon for the kind of thing it
//  names. A browser session must get the browser (globe) icon rather than the
//  terminal icon (QA finding F-480).
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ChatMentionChipIconTests: XCTestCase {
    private func sessionNode(_ session: PTYSession) -> ChatMentionPickerController.Node {
        return ChatMentionPickerController.Node(kind: .session,
                                                title: "Session",
                                                session: session,
                                                children: [])
    }

    func testBrowserSessionChipUsesGlobe() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        session.profile = [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeBrowserValue]
        XCTAssertTrue(session.isBrowserSession())
        let choice = try XCTUnwrap(ChatMentionPickerController.choice(for: sessionNode(session),
                                                                      allowsContainerSelection: false))
        XCTAssertEqual(choice.symbolName, SFSymbol.globe.rawValue)
    }

    func testTerminalSessionChipUsesTerminal() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        session.profile = [:]
        XCTAssertFalse(session.isBrowserSession())
        let choice = try XCTUnwrap(ChatMentionPickerController.choice(for: sessionNode(session),
                                                                      allowsContainerSelection: false))
        XCTAssertEqual(choice.symbolName, SFSymbol.terminal.rawValue)
    }

    // The Cockpit rebuilds chips from bare tokens (after a send or a row
    // selection change), so a session token must resolve to its session's
    // icon too.
    func testSessionTokenResolvesToBrowserIcon() throws {
        let browser = try XCTUnwrap(PTYSession(synthetic: false))
        browser.profile = [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeBrowserValue]
        let terminal = try XCTUnwrap(PTYSession(synthetic: false))
        terminal.profile = [:]
        let sessions = ["browserID": browser, "terminalID": terminal]
        XCTAssertEqual(ChatMentionDisplay.symbolName(forToken: "browserID", resolve: { sessions[$0] }),
                       SFSymbol.globe.rawValue)
        XCTAssertEqual(ChatMentionDisplay.symbolName(forToken: "terminalID", resolve: { sessions[$0] }),
                       SFSymbol.terminal.rawValue)
        XCTAssertEqual(ChatMentionDisplay.symbolName(forToken: "goneID", resolve: { sessions[$0] }),
                       SFSymbol.terminal.rawValue)
    }

    func testContainerChipsUseWindowAndTabIcons() throws {
        let window = ChatMentionPickerController.Node(kind: .window,
                                                      title: "W",
                                                      session: nil,
                                                      children: [],
                                                      containerToken: "win:W")
        let tab = ChatMentionPickerController.Node(kind: .tab,
                                                   title: "T",
                                                   session: nil,
                                                   children: [],
                                                   containerToken: "tab:1")
        let windowChoice = try XCTUnwrap(ChatMentionPickerController.choice(for: window,
                                                                            allowsContainerSelection: true))
        let tabChoice = try XCTUnwrap(ChatMentionPickerController.choice(for: tab,
                                                                         allowsContainerSelection: true))
        XCTAssertEqual(windowChoice.symbolName, SFSymbol.macwindow.rawValue)
        XCTAssertEqual(tabChoice.symbolName, SFSymbol.folder.rawValue)
    }
}

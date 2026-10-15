//
//  CockpitComposerEngageAITests.swift
//  iTerm2 ModernTests
//
//  The Cockpit's docked composer belongs to no session, so it has no
//  variable scope, and it force-hides its AI controls. Edit > Engage
//  Artificial Intelligence (Cmd-Y) still reached its
//  performNaturalLanguageQuery:, which handed the nil scope to
//  AIPromptTemplateEvaluator, whose force-cast of the copy crashed.
//  The menu item must be disabled there, the action must do nothing, and
//  the evaluator must tolerate a missing scope.
//

import XCTest
@testable import iTerm2SharedARC

final class CockpitComposerEngageAITests: XCTestCase, iTermWarningHandler {
    private var shownAlerts = [String]()
    private var window: NSWindow?
    private let engageAI = NSSelectorFromString("performNaturalLanguageQuery:")

    override func setUp() {
        super.setUp()
        shownAlerts = []
        iTermWarning.setWarningHandler(self)
    }

    override func tearDown() {
        // nil is the documented way to go back to real alerts, though the
        // setter is declared nonnull.
        _ = (iTermWarning.self as AnyObject).perform(#selector(iTermWarning.setWarningHandler(_:)), with: nil)
        window?.close()
        window = nil
        super.tearDown()
    }

    func warningWouldShow(_ alert: NSAlert, identifier: String?) -> NSApplication.ModalResponse {
        shownAlerts.append(alert.messageText)
        return .alertFirstButtonReturn
    }

    // The composer's header is not visible to Swift, so drive it through
    // the Objective-C runtime. Like the Cockpit's, its scope is never set.
    private func makeComposer(text: String, forceHideAI: Bool) throws -> NSViewController {
        let composerClass = try XCTUnwrap(
            NSClassFromString("iTermStatusBarLargeComposerViewController") as? NSViewController.Type)
        let composer = composerClass.init(nibName: "iTermStatusBarLargeComposerViewController",
                                          bundle: Bundle(for: composerClass))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = composer.view
        self.window = window
        XCTAssertNil(composer.value(forKey: "scope"))
        composer.setValue(forceHideAI, forKey: "forceHideAIAccessories")
        try XCTUnwrap(composer.value(forKey: "textView") as? NSTextView).string = text
        return composer
    }

    // Validates the way AppKit does for Edit > Engage Artificial
    // Intelligence and its key equivalent: an auto-enabling menu whose item
    // targets the composer. A target without validateMenuItem: is enabled.
    private func engageAIMenuItemIsEnabled(for composer: NSViewController) -> Bool {
        let menu = NSMenu()
        menu.autoenablesItems = true
        let item = NSMenuItem(title: "Engage Artificial Intelligence", action: engageAI, keyEquivalent: "y")
        item.target = composer
        menu.addItem(item)
        menu.update()
        return item.isEnabled
    }

    func testEngageAIMenuItemIsDisabledInCockpitComposer() throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: true)
        let composer = try makeComposer(text: "list files here", forceHideAI: true)
        XCTAssertFalse(engageAIMenuItemIsEnabled(for: composer))
    }

    // F-115: elsewhere the item stays enabled even under the AI lockout so
    // the action can explain why nothing happens.
    func testEngageAIMenuItemStaysEnabledInOrdinaryComposer() throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        let composer = try makeComposer(text: "list files here", forceHideAI: false)
        XCTAssertTrue(engageAIMenuItemIsEnabled(for: composer))
    }

    func testEngageAIInCockpitComposerDoesNothing() throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: true)
        let composer = try makeComposer(text: "list files here", forceHideAI: true)

        composer.perform(engageAI, with: nil)

        XCTAssertNil(composer.value(forKey: "aitermController"),
                     "No AI request may be started from the Cockpit composer")
        XCTAssertEqual(shownAlerts, [])
        XCTAssertEqual(try XCTUnwrap(composer.value(forKey: "textView") as? NSTextView).string,
                       "list files here")
    }

    func testEvaluatorWithoutScopeSubstitutesAIVariables() {
        var result: String?
        AIPromptTemplateEvaluator.evaluate("Request: \\(ai.prompt)",
                                           variables: ["prompt": "list files here"],
                                           scope: nil,
                                           synchronous: true) { value in
            result = value
        }
        XCTAssertEqual(result, "Request: list files here")
    }

    // The default Engage AI prompt refers to session variables (\(shell),
    // \(uname)), which have nothing to resolve against without a scope.
    // It must still produce a prompt carrying the user's request.
    func testEvaluatorWithoutScopeEvaluatesDefaultEngageAIPrompt() throws {
        var result: String?
        AIPromptTemplateEvaluator.evaluate(iTermDefaultAIPrompt,
                                           variables: [iTermAIPromptVariablePrompt: "list files here"],
                                           scope: nil,
                                           synchronous: true) { value in
            result = value
        }
        let prompt = try XCTUnwrap(result)
        XCTAssertTrue(prompt.contains("list files here"), prompt)
    }
}

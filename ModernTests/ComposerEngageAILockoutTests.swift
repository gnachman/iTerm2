//
//  ComposerEngageAILockoutTests.swift
//  iTerm2 ModernTests
//
//  With generative AI disallowed by the administrator (GenerativeAIAllowed),
//  the Composer hides its Engage AI button, but Edit > Engage Artificial
//  Intelligence (and its key equivalent) still reaches the composer's
//  performNaturalLanguageQuery: action. That action must refuse up front with
//  the gatekeeper's “Feature Unavailable” warning and start no AI request.
//

import XCTest
@testable import iTerm2SharedARC

final class ComposerEngageAILockoutTests: XCTestCase, iTermWarningHandler {
    private var shownAlerts = [(heading: String, text: String)]()
    private var window: NSWindow?

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
        shownAlerts.append((heading: alert.messageText, text: alert.informativeText))
        return .alertFirstButtonReturn
    }

    // The composer's header is not visible to Swift, so drive it through the
    // Objective-C runtime: its nib, its scope and textView properties, and the
    // action that Edit > Engage Artificial Intelligence sends.
    private func makeComposer(text: String) throws -> NSViewController {
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
        composer.setValue(iTermVariableScope(), forKey: "scope")
        try textView(of: composer).string = text
        return composer
    }

    private func textView(of composer: NSViewController) throws -> NSTextView {
        return try XCTUnwrap(composer.value(forKey: "textView") as? NSTextView)
    }

    // The ivar holding the in-flight AI request. Nil means no request was started.
    private func aitermController(of composer: NSViewController) -> Any? {
        return composer.value(forKey: "aitermController")
    }

    func testEngageAIUnderLockoutShowsFeatureUnavailableAndStartsNoRequest() throws {
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        let composer = try makeComposer(text: "delete every log file")

        composer.perform(NSSelectorFromString("performNaturalLanguageQuery:"), with: nil)

        XCTAssertNil(aitermController(of: composer),
                     "No AI request may be started while generative AI is disallowed")
        XCTAssertEqual(shownAlerts.count, 1)
        let alert = try XCTUnwrap(shownAlerts.first)
        XCTAssertEqual(alert.heading, "Feature Unavailable")
        XCTAssertTrue(alert.text.contains("Generative AI features have been disabled"),
                      "Unexpected warning text: \(alert.text)")
        XCTAssertEqual(try textView(of: composer).string, "delete every log file",
                       "The composer text must be left alone")
    }
}

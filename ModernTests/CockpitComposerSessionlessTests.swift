//
//  CockpitComposerSessionlessTests.swift
//  ModernTests
//
//  QA finding F-377: in the Cockpit's composer, which has no terminal
//  session behind it, Advanced Paste (⌥⌘V) did nothing and Open Command
//  History (⇧⌘;) opened an empty popup outside the composer, yet both were
//  enabled and the composer's help popover advertised them (and AI lookup).
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CockpitComposerSessionlessTests: XCTestCase {
    private struct NotFound: Error {}
    private let pasteOptions = NSSelectorFromString("pasteOptions:")
    private let openCommandHistory = NSSelectorFromString("openCommandHistory:")

    private func findComposer(in view: NSView) -> ComposerTextView? {
        if let composer = view as? ComposerTextView {
            return composer
        }
        for subview in view.subviews {
            if let composer = findComposer(in: subview) {
                return composer
            }
        }
        return nil
    }

    // The large composer controller (not visible to Swift tests) is the
    // responder that handles these menu actions, found from the text view
    // up the responder chain the way the menu finds it.
    private func largeComposer(sessionless: Bool) throws -> (iTermMinimalComposerViewController, NSResponder & NSMenuItemValidation) {
        let composer = iTermMinimalComposerViewController()
        _ = composer.view
        if sessionless {
            composer.setSessionless(true)
        }
        let textView = try XCTUnwrap(findComposer(in: composer.view))
        var responder: NSResponder? = textView
        while let current = responder {
            if current.responds(to: pasteOptions), let validator = current as? NSResponder & NSMenuItemValidation {
                return (composer, validator)
            }
            responder = current.nextResponder
        }
        XCTFail("Large composer not in the text view’s responder chain")
        throw NotFound()
    }

    private func menuItem(_ action: Selector) -> NSMenuItem {
        return NSMenuItem(title: "", action: action, keyEquivalent: "")
    }

    private func helpLines(_ controller: NSResponder) throws -> [String] {
        let selector = NSSelectorFromString("helpLines")
        XCTAssertTrue(controller.responds(to: selector))
        return try XCTUnwrap(controller.perform(selector)?.takeUnretainedValue() as? [String])
    }

    func testSessionlessComposerDisablesAdvancedPasteAndCommandHistory() throws {
        let (composer, controller) = try largeComposer(sessionless: true)
        withExtendedLifetime(composer) {
            XCTAssertFalse(controller.validateMenuItem(menuItem(pasteOptions)))
            XCTAssertFalse(controller.validateMenuItem(menuItem(openCommandHistory)))
            XCTAssertTrue(controller.validateMenuItem(menuItem(NSSelectorFromString("help:"))))
        }
    }

    func testOrdinaryComposerKeepsAdvancedPasteAndCommandHistory() throws {
        let (composer, controller) = try largeComposer(sessionless: false)
        withExtendedLifetime(composer) {
            XCTAssertTrue(controller.validateMenuItem(menuItem(pasteOptions)))
            XCTAssertTrue(controller.validateMenuItem(menuItem(openCommandHistory)))
        }
    }

    func testSessionlessHelpOmitsUnavailableShortcuts() throws {
        let (composer, controller) = try largeComposer(sessionless: true)
        let lines = try withExtendedLifetime(composer) { try helpLines(controller) }
        XCTAssertFalse(lines.contains { $0.hasPrefix("⌥⌘V\t") }, "\(lines)")
        XCTAssertFalse(lines.contains { $0.hasPrefix("⇧⌘;\t") }, "\(lines)")
        XCTAssertFalse(lines.contains { $0.hasPrefix("⌘Y\t") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("⇧↩\t") }, "\(lines)")
    }

    func testOrdinaryHelpListsShortcuts() throws {
        let (composer, controller) = try largeComposer(sessionless: false)
        let lines = try withExtendedLifetime(composer) { try helpLines(controller) }
        XCTAssertTrue(lines.contains { $0.hasPrefix("⌥⌘V\t") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("⇧⌘;\t") }, "\(lines)")
    }
}

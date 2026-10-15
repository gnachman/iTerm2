//
//  CockpitComposerPlaceholderTests.swift
//  ModernTests
//
//  QA finding F-263: the Cockpit composer's placeholder was drawn twice
//  when it didn't fit on one line. The composer's own placeholder
//  property was named placeholderString, which overrides NSTextView's
//  private placeholder property, so AppKit drew a second (wrapped) copy
//  under the composer's own whenever the field was empty.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CockpitComposerPlaceholderTests: XCTestCase {
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

    func testComposerPlaceholderDoesNotSetAppKitsPlaceholder() throws {
        let composer = iTermMinimalComposerViewController()
        _ = composer.view
        let textView = try XCTUnwrap(findComposer(in: composer.view))
        let placeholder = "Digite aqui para escrever nas sessões selecionadas…"
        composer.setComposerPlaceholder(placeholder)

        XCTAssertEqual(textView.composerPlaceholderString, placeholder)
        // NSTextView draws its own placeholder from this private property
        // when empty. If AppKit drops it, there's nothing to collide with.
        let getter = NSSelectorFromString("placeholderString")
        guard textView.responds(to: getter) else {
            return
        }
        let appKitPlaceholder = textView.perform(getter)?.takeUnretainedValue() as? String
        XCTAssertNil(appKitPlaceholder)
    }
}

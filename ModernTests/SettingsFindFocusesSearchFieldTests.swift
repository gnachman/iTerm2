//
//  SettingsFindFocusesSearchFieldTests.swift
//  ModernTests
//
//  With the Settings window key over a terminal window, Edit > Find > Find…
//  (⌘F) opened the find bar in the terminal behind Settings (QA F-418).
//  Settings is a panel, so the terminal stays the main window, and nothing in
//  Settings’ responder chain handled performFindPanelAction:, so AppKit fell
//  through to the main window’s chain. Settings must handle Find… itself by
//  focusing its own search field.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class SettingsFindFocusesSearchFieldTests: XCTestCase {
    private let action = #selector(NSTextView.performFindPanelAction(_:))

    private func findMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Find…", action: action, keyEquivalent: "f")
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        return item
    }

    // Mirrors the key-window half of NSApplication's target search: the
    // responder chain from the first responder, then the window's delegate.
    // If this finds nothing, AppKit moves on to the main window (the
    // terminal), which is the bug.
    private func keyWindowTarget(in window: NSWindow) -> AnyObject? {
        var responder: NSResponder? = window.firstResponder
        while let current = responder {
            if current.responds(to: action) {
                return current
            }
            responder = current.nextResponder
        }
        if let delegate = window.delegate, delegate.responds(to: action) {
            return delegate
        }
        return nil
    }

    private func isEnabled(_ target: AnyObject, item: NSMenuItem) -> Bool {
        if let validator = target as? NSMenuItemValidation {
            return validator.validateMenuItem(item)
        }
        if let validator = target as? NSUserInterfaceValidations {
            return validator.validateUserInterfaceItem(item)
        }
        return true
    }

    private func searchField(of panel: PreferencePanel) throws -> NSSearchField {
        return try XCTUnwrap(panel.value(forKey: "searchField") as? NSSearchField)
    }

    private func searchFieldIsFocused(_ field: NSSearchField, in window: NSWindow) -> Bool {
        if window.firstResponder === field {
            return true
        }
        if let editor = window.firstResponder as? NSText,
           editor.delegate as AnyObject? === field {
            return true
        }
        return false
    }

    private func preparedPanel() throws -> (PreferencePanel, NSWindow) {
        let panel = PreferencePanel.sharedInstance()
        let window = try XCTUnwrap(panel.window)
        window.makeFirstResponder(nil)
        return (panel, window)
    }

    func testFindIsHandledBySettingsAndFocusesSearchField() throws {
        let (panel, window) = try preparedPanel()
        defer {
            window.makeFirstResponder(nil)
        }
        let field = try searchField(of: panel)
        XCTAssertTrue(field.window === window)

        let item = findMenuItem()
        let target = try XCTUnwrap(keyWindowTarget(in: window),
                                   "Nothing in Settings handles Find…, so it goes to the terminal behind it")
        XCTAssertTrue(isEnabled(target, item: item))

        _ = target.perform(action, with: item)
        XCTAssertTrue(searchFieldIsFocused(field, in: window))

        // Find… again while the search field is being edited keeps it focused.
        let editingTarget = try XCTUnwrap(keyWindowTarget(in: window))
        XCTAssertTrue(isEnabled(editingTarget, item: item))
        _ = editingTarget.perform(action, with: item)
        XCTAssertTrue(searchFieldIsFocused(field, in: window))
    }

    // Other find panel actions (e.g. Use Selection for Find) have nothing to
    // do in Settings and must not reach the terminal behind it either.
    func testOtherFindPanelActionsAreDisabledInSettings() throws {
        let (_, window) = try preparedPanel()
        let item = NSMenuItem(title: "Use Selection for Find", action: action, keyEquivalent: "e")
        item.tag = Int(NSFindPanelAction.setFindString.rawValue)
        let target = try XCTUnwrap(keyWindowTarget(in: window))
        XCTAssertFalse(isEnabled(target, item: item))
    }

    func testFindWhileEditingATextFieldFocusesSearchField() throws {
        let (panel, window) = try preparedPanel()
        let field = try searchField(of: panel)
        let contentView = try XCTUnwrap(window.contentView)
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        textField.isEditable = true
        contentView.addSubview(textField)
        defer {
            window.makeFirstResponder(nil)
            textField.removeFromSuperview()
        }
        XCTAssertTrue(window.makeFirstResponder(textField))
        XCTAssertFalse(searchFieldIsFocused(field, in: window))

        let item = findMenuItem()
        let target = try XCTUnwrap(keyWindowTarget(in: window))
        XCTAssertTrue(isEnabled(target, item: item))

        _ = target.perform(action, with: item)
        XCTAssertTrue(searchFieldIsFocused(field, in: window))
    }
}

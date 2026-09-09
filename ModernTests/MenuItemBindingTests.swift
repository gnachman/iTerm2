//
//  MenuItemBindingTests.swift
//  iTerm2 ModernTests
//
//  Regression tests for the "Select Menu Item" binding resolver. These cover the
//  data-destroying bug where opening a legacy binding in the editor and clicking OK
//  could clobber a working binding (writing nil / "(null)\n(null)") because the stored
//  identifier or title failed to resolve against a localized menu.
//

import XCTest
@testable import iTerm2SharedARC

final class MenuItemBindingTests: XCTestCase {
    // Builds a menu whose visible titles are localized (pt-BR here) but whose
    // accessibility identifiers hold the English titles, exactly as MainMenu.xib does.
    private func makeLocalizedMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        editItem.title = "Editar"  // localized "Edit"
        let editMenu = NSMenu()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // "Copy": visible title localized, accessibility identifier is the English title,
        // and it has NO real identifier (only AppKit's synthetic one at runtime).
        let copy = NSMenuItem()
        copy.title = "Copiar"
        copy.setAccessibilityIdentifier("Copy")
        editMenu.addItem(copy)

        editMenu.addItem(NSMenuItem.separator())

        // "Clear Buffer": legacy title-only bindings stored just "Clear Buffer".
        let clearBuffer = NSMenuItem()
        clearBuffer.title = "Limpar buffer"
        clearBuffer.setAccessibilityIdentifier("Clear Buffer")
        editMenu.addItem(clearBuffer)

        // An item carrying a real, stable identifier.
        let paste = NSMenuItem()
        paste.title = "Colar"
        paste.setAccessibilityIdentifier("Paste")
        paste.identifier = NSUserInterfaceItemIdentifier("menu.paste")
        editMenu.addItem(paste)

        return mainMenu
    }

    // MARK: - Resolution

    // Stored as PointerPrefs "identifier\ntitle" with a synthetic "_NS:191" identifier.
    // The synthetic identifier is untrustworthy, so resolution must fall back to matching
    // the title "Copy" against the English accessibility identifier.
    func testResolvesSyntheticIdentifierByTitleFallback() {
        let menu = makeLocalizedMenu()
        let item = MenuItemBinding.item(in: menu, matchingIdentifier: "_NS:191", title: "Copy")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.title, "Copiar")
    }

    // Legacy title-only binding: identifier is nil and the stored English title must match
    // against the accessibility identifier even though the visible title is translated.
    func testResolvesLegacyTitleOnlyBinding() {
        let menu = makeLocalizedMenu()
        let item = MenuItemBinding.item(in: menu, matchingIdentifier: nil, title: "Clear Buffer")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.title, "Limpar buffer")
    }

    // A title stored in the user's own locale still resolves against the localized title.
    func testResolvesLocalizedTitle() {
        let menu = makeLocalizedMenu()
        let item = MenuItemBinding.item(in: menu, matchingIdentifier: nil, title: "Limpar buffer")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.title, "Limpar buffer")
    }

    // A real, stable identifier resolves directly.
    func testResolvesRealIdentifier() {
        let menu = makeLocalizedMenu()
        let item = MenuItemBinding.item(in: menu, matchingIdentifier: "menu.paste", title: "Paste")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.title, "Colar")
    }

    // Nothing matches: resolver returns nil so callers know not to overwrite the binding.
    func testUnresolvableReturnsNil() {
        let menu = makeLocalizedMenu()
        XCTAssertNil(MenuItemBinding.item(in: menu, matchingIdentifier: "_NS:999", title: "Nonexistent"))
    }

    // MARK: - Preserve on no selection

    // The crux of the data-loss bug: confirming the editor with NO selection must return
    // the original stored parameter unchanged, never nil and never "(null)\n(null)".
    func testStoredParameterPreservesOriginalWhenNothingSelected_pointerPrefsOrder() {
        let result = MenuItemBinding.storedParameter(identifier: nil,
                                                     title: nil,
                                                     hasSelection: false,
                                                     original: "_NS:191\nCopy",
                                                     identifierFirst: true)
        XCTAssertEqual(result, "_NS:191\nCopy")
        XCTAssertNotEqual(result, "(null)\n(null)")
    }

    func testStoredParameterPreservesOriginalWhenNothingSelected_keyActionOrder() {
        let result = MenuItemBinding.storedParameter(identifier: nil,
                                                     title: nil,
                                                     hasSelection: false,
                                                     original: "Clear Buffer",
                                                     identifierFirst: false)
        XCTAssertEqual(result, "Clear Buffer")
    }

    // A selection writes the new value in the expected per-editor order.
    func testStoredParameterPointerPrefsOrder() {
        let result = MenuItemBinding.storedParameter(identifier: "menu.paste",
                                                     title: "Colar",
                                                     hasSelection: true,
                                                     original: "old\nvalue",
                                                     identifierFirst: true)
        XCTAssertEqual(result, "menu.paste\nColar")
    }

    func testStoredParameterKeyActionOrderWithIdentifier() {
        let result = MenuItemBinding.storedParameter(identifier: "menu.paste",
                                                     title: "Colar",
                                                     hasSelection: true,
                                                     original: "old\nvalue",
                                                     identifierFirst: false)
        XCTAssertEqual(result, "Colar\nmenu.paste")
    }

    // Key-action editor with a selection that lacks a stable identifier stores title only.
    func testStoredParameterKeyActionOrderTitleOnly() {
        let result = MenuItemBinding.storedParameter(identifier: nil,
                                                     title: "Copiar",
                                                     hasSelection: true,
                                                     original: nil,
                                                     identifierFirst: false)
        XCTAssertEqual(result, "Copiar")
    }

    // Never fabricates a "(null)" argument even when there is nothing to store at all.
    func testStoredParameterNeverProducesNullLiteral() {
        let result = MenuItemBinding.storedParameter(identifier: nil,
                                                     title: nil,
                                                     hasSelection: true,
                                                     original: nil,
                                                     identifierFirst: true)
        XCTAssertEqual(result, "\n")
        XCTAssertNotEqual(result, "(null)\n(null)")
    }
}

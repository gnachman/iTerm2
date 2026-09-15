//
//  MenuItemBindingDivergenceTests.swift
//  iTerm2 ModernTests
//
//  Validation tests for three related defects in the "Select Menu Item" key/pointer
//  binding resolvers. These assert the CORRECT behavior and are expected to FAIL against
//  the current implementation. They complement MenuItemBindingTests.swift.
//
//  There are two resolvers that must agree:
//    * Editor side:  MenuItemBinding.item(in:matchingIdentifier:title:) in
//                    sources/Settings/MenuItemPopupView.swift
//    * Runtime side: +[ITAddressBookMgr shortcutIdentifier:title:matchesItem:] in
//                    sources/Settings/Profiles/ITAddressBookMgr.m, walked by
//                    -[NSMenu it_selectMenuItemWithTitle:identifier:] and reached from
//                    PointerController.m (which splits the stored parameter on "\n").
//

import XCTest
@testable import iTerm2SharedARC

final class MenuItemBindingDivergenceTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(title: String,
                          identifier: String? = nil,
                          accessibilityIdentifier: String? = nil) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = title
        if let identifier {
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        if let accessibilityIdentifier {
            item.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        return item
    }

    // Wraps items in a top-level main-menu bar (top item -> submenu) the way the resolvers
    // walk NSApp.mainMenu.
    private func makeMainMenu(topTitle: String, items: [NSMenuItem]) -> NSMenu {
        let mainMenu = NSMenu()
        let top = NSMenuItem()
        top.title = topTitle
        let submenu = NSMenu()
        for item in items {
            submenu.addItem(item)
        }
        top.submenu = submenu
        mainMenu.addItem(top)
        return mainMenu
    }

    // MARK: - FINDING A: legacy bindings to Toolbelt tools / Profiles "Open All" die when localized
    //
    // sources/Toolbelt/iTermToolbeltView.m +addToolsToMenu: (~line 242) gives each tool item a
    // localized title and identifier "Toolbelt.<name>" but sets NO accessibilityIdentifier.
    // sources/Settings/Profiles/iTermProfilesMenuController.m +addOpenAllToMenu: (~line 99) does the
    // same for "Open All". The runtime matcher's title branch (ITAddressBookMgr.m:1086-1090) only
    // compares item.title and item.accessibilityIdentifier, never item.identifier. Once the title is
    // translated and the accessibility identifier is empty, a legacy title-only binding matches
    // nothing.

    // Legacy title-only binding for the Command History toolbelt tool. Runtime side.
    func testFindingA_runtimeMatcher_toolbeltLegacyTitleResolves() {
        let item = makeItem(title: "Histórico de comandos",           // localized "Command History"
                            identifier: "Toolbelt.Command History",   // English key, "Toolbelt." prefixed
                            accessibilityIdentifier: nil)              // no English anchor
        // Stored legacy binding is just the English title.
        let matched = ITAddressBookMgr.shortcutIdentifier(nil,
                                                          title: "Command History",
                                                          matchesItem: item)
        // Expected: YES. Actual: NO (title localized, axid empty, item.identifier ignored). FAILS.
        XCTAssertTrue(matched)
    }

    // Same item, but resolved through the exact call form named in the finding.
    func testFindingA_runtimeMatcher_toolbeltEnglishIdentifierAndTitleResolves() {
        let item = makeItem(title: "Histórico de comandos",
                            identifier: "Toolbelt.Command History",
                            accessibilityIdentifier: nil)
        let matched = ITAddressBookMgr.shortcutIdentifier("Command History",
                                                          title: "Command History",
                                                          matchesItem: item)
        // identifier branch: "Command History" != "Toolbelt.Command History"; title branch skipped
        // because the identifier is non-nil. Expected YES, actual NO. FAILS.
        XCTAssertTrue(matched)
    }

    // Editor side of the same legacy toolbelt binding.
    func testFindingA_editor_toolbeltLegacyTitleResolves() {
        let menu = makeMainMenu(topTitle: "Toolbelt",
                                items: [makeItem(title: "Histórico de comandos",
                                                 identifier: "Toolbelt.Command History",
                                                 accessibilityIdentifier: nil)])
        let item = MenuItemBinding.item(in: menu, matchingIdentifier: nil, title: "Command History")
        // Expected: resolves to the tool item. Actual: nil. FAILS.
        XCTAssertNotNil(item)
    }

    // Legacy title-only binding for Profiles "Open All". Runtime side.
    func testFindingA_runtimeMatcher_openAllLegacyTitleResolves() {
        // The identifier is a menu path (not the title), and the visible title is translated,
        // so the only English anchor is the accessibility identifier the fix now sets on the
        // programmatically-created Open All item (iTermProfilesMenuController.addOpenAllToMenu:).
        let item = makeItem(title: "Abrir todos",       // localized "Open All"
                            identifier: "Bookmarks",     // identifier keeps a menu path, not the title
                            accessibilityIdentifier: "Open All")
        let matched = ITAddressBookMgr.shortcutIdentifier(nil,
                                                          title: "Open All",
                                                          matchesItem: item)
        XCTAssertTrue(matched)
    }

    // MARK: - FINDING B: discarding an "_NS" identifier fires the WRONG duplicate-titled item
    //
    // ITAddressBookMgr.m:1078-1080 now nulls any stored "_NS:<n>" identifier, so resolution falls
    // through to the title branch. The main menu has duplicate titles (e.g. Session>Reset and
    // Session>Terminal State>Reset), and the depth-first walk fires the FIRST title match. A binding
    // captured for the second item now invokes the first. On master, strict identifier equality made
    // an unresolved "_NS:<n>" fail closed (match nothing) instead of firing the wrong item.

    // Two items titled "Reset"; the binding was captured for the SECOND (nested) one.
    private func makeDuplicateResetMenu() -> (menu: NSMenu, first: NSMenuItem, second: NSMenuItem) {
        // Top-level Session>Reset (unintended first match).
        let first = makeItem(title: "Redefinir", accessibilityIdentifier: "Reset")

        // Session>Terminal State>Reset (the intended second match).
        let second = makeItem(title: "Redefinir", accessibilityIdentifier: "Reset")
        let terminalState = NSMenuItem()
        terminalState.title = "Estado do terminal"
        let terminalStateSubmenu = NSMenu()
        terminalStateSubmenu.addItem(second)
        terminalState.submenu = terminalStateSubmenu

        let menu = makeMainMenu(topTitle: "Sessão", items: [first, terminalState])
        return (menu, first, second)
    }

    // Editor side: an "_NS" identifier meant for the second Reset must not resolve to the first.
    func testFindingB_editor_syntheticIdentifierDoesNotFireFirstDuplicate() {
        let (menu, first, _) = makeDuplicateResetMenu()
        let resolved = MenuItemBinding.item(in: menu, matchingIdentifier: "_NS:2", title: "Reset")
        // Correct behavior: pick the intended second item, or fail closed (nil). Never the first.
        // Actual: returns the first (top-level) Reset. FAILS.
        XCTAssertFalse(resolved === first, "Resolver fired the first duplicate-titled item")
    }

    // Runtime side: the first item must NOT be considered a match for an "_NS" id captured elsewhere.
    func testFindingB_runtimeMatcher_syntheticIdentifierDoesNotMatchWrongItem() {
        let (_, first, _) = makeDuplicateResetMenu()
        let matched = ITAddressBookMgr.shortcutIdentifier("_NS:2",
                                                          title: "Reset",
                                                          matchesItem: first)
        // The stored "_NS:2" identifies the second item positionally. After nulling it, the title
        // branch matches the first item's accessibility identifier ("Reset") -> YES (wrong).
        // On master this returned NO (failed closed). Expected NO, actual YES. FAILS.
        XCTAssertFalse(matched, "Runtime matcher matched the wrong duplicate-titled item")
    }

    // MARK: - FINDING C: editor and runtime diverge on an EMPTY identifier
    //
    // Editor MenuItemBinding.item(...) normalizes ""/"_NS*" to nil and falls back to title
    // (MenuItemPopupView.swift:335-345). The runtime matcher gates its title branch on
    // `if (!identifier)` (ITAddressBookMgr.m:1086): a non-nil but EMPTY identifier ("") takes the
    // identifier branch, matches nothing, and never tries the title. PointerController.m:106 splits
    // the stored parameter on "\n", so a value like "\nSome Title" (items with no stable id, e.g.
    // snippet menu items, are saved this way) yields identifier == "" and never fires, while the
    // editor shows the same binding resolving.

    // The two resolvers must agree for an empty-identifier binding. They do not.
    func testFindingC_emptyIdentifierEditorAndRuntimeAgree() {
        let item = makeItem(title: "Some Title")   // no stable identifier, no accessibility identifier
        let menu = makeMainMenu(topTitle: "Snippets", items: [item])

        // Stored parameter "\nSome Title" -> identifier "", title "Some Title".
        let editorResolves = MenuItemBinding.item(in: menu,
                                                  matchingIdentifier: "",
                                                  title: "Some Title") != nil
        let runtimeMatches = ITAddressBookMgr.shortcutIdentifier("",
                                                                title: "Some Title",
                                                                matchesItem: item)

        // Editor resolves by title; runtime skips the title branch. They must agree. FAILS.
        XCTAssertEqual(editorResolves, runtimeMatches,
                       "Editor and runtime disagree on an empty-identifier binding")
        // And the correct behavior is that both resolve.
        XCTAssertTrue(runtimeMatches, "Runtime matcher never tried the title fallback")
        XCTAssertTrue(editorResolves)
    }

    // Contrast: for a stored "_NS:1\nSome Title" both resolvers DO agree (both null the _NS id and
    // fall back to title). This test should PASS and documents that the divergence is specific to
    // the empty-string identifier, not the "_NS" case.
    func testFindingC_syntheticIdentifierEditorAndRuntimeAgree() {
        let item = makeItem(title: "Some Title")
        let menu = makeMainMenu(topTitle: "Snippets", items: [item])

        let editorResolves = MenuItemBinding.item(in: menu,
                                                  matchingIdentifier: "_NS:1",
                                                  title: "Some Title") != nil
        let runtimeMatches = ITAddressBookMgr.shortcutIdentifier("_NS:1",
                                                                title: "Some Title",
                                                                matchesItem: item)
        XCTAssertEqual(editorResolves, runtimeMatches)
        XCTAssertTrue(runtimeMatches)
        XCTAssertTrue(editorResolves)
    }


    // MARK: - FINDING 2: legacy "_NS" bindings resolve in the editor but never fire at runtime (pt-BR)
    //
    // Editor MenuItemBinding.item(...) has an exact-match fallback for synthetic identifiers
    // (MenuItemPopupView.swift:296-302): after normalizing "_NS:<n>" to absent it still tries a
    // literal item.identifier == "_NS:<n>" hit, so the binding shows as resolved in the editor.
    // The runtime matcher (ITAddressBookMgr.m:1093-1099) reaches
    // `if ([identifier hasPrefix:@"_NS"]) return NO;` BEFORE the accessibility-identifier/title
    // fallback at :1102 and never compares item.identifier against the stored "_NS" value at all.
    // So once the visible title is localized (pt-BR) the runtime returns NO while the editor says
    // the binding is fine. English UIs are unaffected because :1090 matches the visible title.

    // Item identified positionally by "_NS:5"; visible title is localized; no English axid anchor.
    func testFinding2_syntheticIdentifierLocalizedTitle_editorAndRuntimeAgree() {
        let englishTitle = "Toggle Broadcast Input"
        let localizedTitle = "Alternar entrada de transmissão"     // pt-BR
        let item = makeItem(title: localizedTitle, identifier: "_NS:5")
        let menu = makeMainMenu(topTitle: "Session", items: [item])

        // Stored parameter "Toggle Broadcast Input\n_NS:5" -> title English, identifier "_NS:5".
        let editorResolves = MenuItemBinding.item(in: menu,
                                                  matchingIdentifier: "_NS:5",
                                                  title: englishTitle) != nil
        let runtimeMatches = ITAddressBookMgr.shortcutIdentifier("_NS:5",
                                                                title: englishTitle,
                                                                matchesItem: item)
        // Editor resolves via its exact "_NS" fallback; runtime bails at the "_NS" prefix. FAILS.
        XCTAssertEqual(editorResolves, runtimeMatches,
                       "Editor and runtime disagree on a localized synthetic-identifier binding")
        XCTAssertTrue(runtimeMatches,
                      "Runtime returned NO on the _NS bailout before any identifier/axid comparison")
        XCTAssertTrue(editorResolves)
    }

    // Even a real XIB item, whose accessibility identifier holds the English title, cannot be
    // rescued at runtime: the "_NS" return NO at :1097 precedes the axid==title fallback at :1102.
    func testFinding2_syntheticIdentifierLocalizedTitleWithEnglishAxid_runtimeStillFails() {
        let englishTitle = "Toggle Broadcast Input"
        let localizedTitle = "Alternar entrada de transmissão"     // pt-BR
        let item = makeItem(title: localizedTitle,
                            identifier: "_NS:5",
                            accessibilityIdentifier: englishTitle)  // XIB-style English anchor
        let menu = makeMainMenu(topTitle: "Session", items: [item])

        let editorResolves = MenuItemBinding.item(in: menu,
                                                  matchingIdentifier: "_NS:5",
                                                  title: englishTitle) != nil
        let runtimeMatches = ITAddressBookMgr.shortcutIdentifier("_NS:5",
                                                                title: englishTitle,
                                                                matchesItem: item)
        XCTAssertEqual(editorResolves, runtimeMatches,
                       "Editor and runtime disagree even when the English axid anchor is present")
        XCTAssertTrue(runtimeMatches,
                      "The _NS bailout at :1097 defeats the axid==title fallback at :1102")
        XCTAssertTrue(editorResolves)
    }
}

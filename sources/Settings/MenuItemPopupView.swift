//
//  MenuItemPopupView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/29/21.
//

import Foundation
import SearchableComboListView

private extension SearchableComboViewGroup {
    static func fromMainMenu() -> [SearchableComboViewGroup] {
        guard let mainMenu = NSApp.mainMenu else {
            return []
        }
        var nextTag = 1
        let tagProvider = { () -> Int in
            defer {
                nextTag += 1
            }
            return nextTag
        }
        return groupsFromMenuItems(mainMenu, ancestors: [], tagProvider: tagProvider)
    }

    private static func groupsFromMenuItems(_ menu: NSMenu,
                                            ancestors: [NSMenuItem],
                                            tagProvider: () -> (Int)) -> [SearchableComboViewGroup] {
        return menu.items.flatMap { item -> [SearchableComboViewGroup] in
            guard let submenu = item.submenu else {
                return []
            }
            guard submenu != NSApp.servicesMenu else {
                return []
            }
            let items = SearchableComboViewItem.itemsFromMenu(submenu,
                                                              ancestors: ancestors + [item],
                                                              tagProvider: tagProvider)
            let path = ancestors.map { $0.title }
            let topGroup = SearchableComboViewGroup((path + [item.title]).joined(separator: " > "),
                                                    items: items)
            let innerGroups = groupsFromMenuItems(submenu,
                                                  ancestors: ancestors + [item],
                                                  tagProvider: tagProvider)
            if items.isEmpty {
                return innerGroups
            }
            return [topGroup] + innerGroups
        }
    }
}

private extension NSMenuItem {
    func  isWindowMenuItem(parent: NSMenu) -> Bool {
        guard parent == NSApp.windowsMenu else {
            return false
        }
        if let action = action, NSStringFromSelector(action) == "_toggleIPad:" {
            // SideCar "move to ipad" item.
            return true
        }
        guard target as? NSWindow != nil else {
            return false
        }
        return action == #selector(NSWindow.makeKeyAndOrderFront(_:))
    }

    func isMoveToDisplayItem(parent: NSMenu) -> Bool {
        guard parent == NSApp.windowsMenu else {
            return false
        }
        guard let selector = action else {
            return false
        }
        return NSStringFromSelector(selector) == "_moveToDisplay:"
    }

    private enum ItemType {
        case newWindow
        case newTab
        case other
    }

    private func itemType(descendsFromProfiles: Bool) -> ItemType {
        guard descendsFromProfiles else {
            return .other
        }
        guard !self.hasSubmenu else {
            return .other
        }
        guard let identifier = self.identifier.map({ String($0 as NSString) }) else {
            return .other
        }
        if identifier.hasPrefix(iTermProfileModelNewTabMenuItemIdentifierPrefix) {
            return .newTab
        }
        if identifier.hasPrefix(iTermProfileModelNewWindowMenuItemIdentifierPrefix) {
            return .newWindow
        }
        return .other
    }

    func title(descendsFromProfiles: Bool) -> String {
        switch itemType(descendsFromProfiles: descendsFromProfiles) {
        case .newWindow:
            return "\(self.title) — New Window"
        case .newTab:
            return "\(self.title) — New Tab"
        case .other:
            return self.title
        }
    }

    // The stable, non-localized key we store for this item: prefer the real identifier,
    // fall back to the accessibility identifier (which holds the English title, set in
    // MainMenu.xib). AppKit assigns synthetic "_NS:<n>" identifiers to items lacking one
    // in the xib; those are positional and unstable, so treat them as absent.
    var stableBindingIdentifier: String? {
        let ax = accessibilityIdentifier()
        let axIdentifier = ax.isEmpty ? nil : ax
        let realIdentifier = MenuItemBinding.normalizedStoredIdentifier(identifier.map { $0 as NSString as String })
        return realIdentifier ?? axIdentifier
    }
}

private extension SearchableComboViewItem {
    static func itemsFromMenu(_ menu: NSMenu,
                              ancestors: [NSMenuItem],
                              tagProvider: () -> (Int)) -> [SearchableComboViewItem] {
        let standardItems = menu.items.compactMap { menuItem -> SearchableComboViewItem? in
            if menuItem.hasSubmenu {
                return nil
            }
            if menuItem.isHidden {
                return nil
            }
            if menuItem.isSeparatorItem {
                return nil
            }
            if menuItem.action == nil {
                return nil
            }
            return SearchableComboViewItem.fromMenuItem(menuItem,
                                                        parent: menu,
                                                        ancestors: ancestors,
                                                        tagProvider: tagProvider)
        }
        if menu == NSApp.windowsMenu {
            return standardItems + moveToScreenItems(tagProvider: tagProvider)
        }
        return standardItems
    }

    static private func moveToScreenItems(tagProvider: () -> (Int)) -> [SearchableComboViewItem] {
        return NSScreen.screens.map { screen in
            return SearchableComboViewItem("Move to \(screen.it_uniqueName())",
                                           tag: tagProvider(),
                                           identifier: screen.it_uniqueKey())
        }
    }
    private static func fromMenuItem(_ item: NSMenuItem,
                                     parent: NSMenu,
                                     ancestors: [NSMenuItem],
                                     tagProvider: () -> (Int)) -> SearchableComboViewItem? {
        guard !item.isSeparatorItem else {
            return nil
        }
        guard !item.isWindowMenuItem(parent: parent) else {
            return nil
        }
        guard !item.isMoveToDisplayItem(parent: parent) else {
            return nil
        }
        let profilesIdentifier = NSUserInterfaceItemIdentifier(".Profiles")
        let descendsFromProfiles = ancestors.contains { $0.identifier == profilesIdentifier }
        return SearchableComboViewItem(item.title(descendsFromProfiles: descendsFromProfiles),
                                       tag: tagProvider(),
                                       identifier: item.stableBindingIdentifier)
    }
}

@objc(iTermMenuItemPopupView)
class MenuItemPopupView: NSView {
    @objc private(set) var comboView: SearchableComboView? = nil
    @IBOutlet var delegate: SearchableComboViewDelegate? {
        set {
            comboView?.delegate = newValue
        }
        get {
            return comboView?.delegate
        }
    }

    init() {
        super.init(frame: NSRect.zero)
        reloadData()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        reloadData()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        reloadData()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        comboView?.frame = self.bounds
    }

    @objc func reloadData() {
        let identifier = selectedIdentifier
        comboView?.removeFromSuperview()
        let defaultTitle = String(localized: "MenuItemPopup.DefaultTitle",
                                  defaultValue: "Select Menu Item…",
                                  comment: "Placeholder shown in the menu-item picker when no item is selected")
        let newComboView = SearchableComboView(SearchableComboViewGroup.fromMainMenu(),
                                               defaultTitle: defaultTitle)
        newComboView.frame = self.bounds
        newComboView.delegate = comboView?.delegate
        addSubview(newComboView)
        comboView = newComboView
        if let identifier = identifier {
            _ = select(identifier: identifier)
        }
    }

    @objc var selectedTitle: String? {
        return comboView?.selectedItem?.title
    }

    @objc var selectedIdentifier: String? {
        return comboView?.selectedItem?.identifier.map { $0 as NSString as String }
    }

    @objc var hasSelection: Bool {
        return comboView?.selectedItem != nil
    }

    @objc(selectItemWithTitle:) func select(title: String) {
        _ = comboView?.selectItem(withTitle: title)
    }

    @discardableResult
    @objc(selectItemWithIdentifier:) func select(identifier: String) -> Bool {
        return comboView?.selectItem(withIdentifier: NSUserInterfaceItemIdentifier(identifier)) ?? false
    }

    // Resolve a stored "Select Menu Item" binding to a live menu item and select it.
    // A binding may reference an item by a stable identifier, an accessibility identifier
    // (English title), or, for legacy title-only bindings, a title. Resolution falls back
    // in order identifier -> accessibility identifier -> title so a translated UI never
    // fails to find the original item. Returns whether an item was selected; callers use
    // the result to avoid clobbering a binding whose menu item could not be resolved.
    @discardableResult
    @objc(selectItemWithIdentifier:title:) func selectItem(identifier: String?, title: String?) -> Bool {
        guard let menu = NSApp.mainMenu,
              let item = MenuItemBinding.item(in: menu, matchingIdentifier: identifier, title: title) else {
            return false
        }
        if let stable = item.stableBindingIdentifier, select(identifier: stable) {
            return true
        }
        // The item has no stable identifier (only a synthetic one), so fall back to its
        // displayed (localized) title, which is the label used to build the combo item.
        comboView?.selectItem(withTitle: item.title)
        return hasSelection
    }
}

@objc(iTermMenuItemBinding)
class MenuItemBinding: NSObject {
    // Ordered resolution used by the "Select Menu Item" editors. The identifier component
    // is tried first (against both the real identifier and the accessibility identifier),
    // then the title (against both the localized title and the English accessibility
    // identifier), so a stored binding keeps resolving after the visible title has been
    // translated.
    @objc(itemInMenu:matchingIdentifier:title:)
    static func item(in menu: NSMenu, matchingIdentifier identifier: String?, title: String?) -> NSMenuItem? {
        let storedIdentifier = normalizedStoredIdentifier(identifier)
        if let storedIdentifier {
            if let hit = firstItem(in: menu, where: { item in
                if keyMatchesItemIdentifier(storedIdentifier, item.identifier.map({ $0 as NSString as String })) {
                    return true
                }
                let ax = item.accessibilityIdentifier()
                return !ax.isEmpty && ax == storedIdentifier
            }) {
                return hit
            }
        }
        // A synthetic "_NS:<n>" identifier is positional and normalizes to absent above, but
        // in the rare case one still names a live item try an exact hit before title fallback.
        if let identifier, identifier.hasPrefix("_NS") {
            if let hit = firstItem(in: menu, where: { item in
                (item.identifier.map { $0 as NSString as String }) == identifier
            }) {
                return hit
            }
        }
        guard let title, !title.isEmpty else {
            return nil
        }
        // Fall back to the stored title. If more than one item matches, the reference is
        // ambiguous (e.g. Session > Reset vs Terminal State > Reset), so fail closed rather
        // than fire an arbitrary duplicate.
        let titleMatches = allItems(in: menu) { item in
            if item.title == title {
                return true
            }
            let ax = item.accessibilityIdentifier()
            if !ax.isEmpty && ax == title {
                return true
            }
            return keyMatchesItemIdentifier(title, item.identifier.map { $0 as NSString as String })
        }
        if titleMatches.count == 1 {
            return titleMatches[0]
        }
        return nil
    }

    // Format the stored parameter for a "Select Menu Item" binding. When nothing is
    // selected we return the original parameter unchanged so opening the editor and
    // clicking OK can never destroy a binding whose menu item we failed to resolve.
    // PointerPrefs stores "identifier\ntitle" (identifierFirst: true); the key-action
    // editor stores "title\nidentifier" (identifierFirst: false).
    @objc(storedParameterForIdentifier:title:hasSelection:original:identifierFirst:)
    static func storedParameter(identifier: String?,
                                title: String?,
                                hasSelection: Bool,
                                original: String?,
                                identifierFirst: Bool) -> String? {
        guard hasSelection else {
            return original
        }
        let identifier = identifier ?? ""
        let title = title ?? ""
        if identifierFirst {
            return "\(identifier)\n\(title)"
        }
        if !identifier.isEmpty {
            return "\(title)\n\(identifier)"
        }
        return title
    }

    // Normalize a stored menu-item identifier to the single value both the editor and the
    // runtime matcher (ITAddressBookMgr) key off. An empty string is not a real identifier,
    // and AppKit's synthetic "_NS:<n>" identifiers are positional and unstable, so both are
    // treated as absent (nil): callers then fall back to title matching. This is the one
    // place the "_NS"/empty rule lives so the two matchers cannot diverge.
    @objc(normalizedStoredIdentifier:)
    static func normalizedStoredIdentifier(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else {
            return nil
        }
        if identifier.hasPrefix("_NS") {
            return nil
        }
        return identifier
    }

    // Whether a stored key resolves to an item's real identifier. Programmatically-built
    // menus namespace the English key in the identifier (e.g. "Toolbelt.Command History"),
    // so a stored key of "Command History" matches by a dot-delimited suffix as well as
    // exactly.
    @objc(key:matchesItemIdentifier:)
    static func keyMatchesItemIdentifier(_ key: String?, _ itemIdentifier: String?) -> Bool {
        guard let key, !key.isEmpty, let itemIdentifier, !itemIdentifier.isEmpty else {
            return false
        }
        if itemIdentifier == key {
            return true
        }
        return itemIdentifier.hasSuffix("." + key)
    }

    private static func firstItem(in menu: NSMenu, where predicate: (NSMenuItem) -> Bool) -> NSMenuItem? {
        for item in menu.items {
            if item.isSeparatorItem {
                continue
            }
            if predicate(item) {
                return item
            }
            if let submenu = item.submenu, let hit = firstItem(in: submenu, where: predicate) {
                return hit
            }
        }
        return nil
    }

    private static func allItems(in menu: NSMenu, where predicate: (NSMenuItem) -> Bool) -> [NSMenuItem] {
        var result: [NSMenuItem] = []
        for item in menu.items {
            if item.isSeparatorItem {
                continue
            }
            if predicate(item) {
                result.append(item)
            }
            if let submenu = item.submenu {
                result.append(contentsOf: allItems(in: submenu, where: predicate))
            }
        }
        return result
    }
}


//
//  TabBarSearchController.swift
//  iTerm2SharedARC
//
//  The search field and order button at the top of a vertical tab bar. It
//  reports what's typed, the keys that end a search, and the order picked;
//  the window does the filtering and ordering (see TabBarSearch and
//  TabBarOrder).
//

import AppKit

@objc(iTermTabBarSearchController)
final class TabBarSearchController: NSObject, NSSearchFieldDelegate {
    private static let spacing: CGFloat = 4
    private static let orderButtonWidth: CGFloat = 22

    /// Height of the band the field and order button sit in. The window adds
    /// it to the tab bar's top inset.
    @objc static let bandHeight: CGFloat = accessoryHeight + 10

    // Measured once: the tab bar asks for the band on every layout.
    private static let accessoryHeight: CGFloat = {
        let field = NSSearchField()
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.sizeToFit()
        return field.frame.height
    }()

    /// Holds the field and the order button. The tab bar shows this.
    @objc let accessoryView: NSView
    @objc let searchField: NSSearchField
    /// Opens orderMenu.
    @objc let orderButton: NSButton
    /// Manual, Status, or Directory. Each item's tag is a TabBarOrderMode
    /// raw value.
    @objc let orderMenu: NSMenu
    /// The user picked an order.
    @objc var orderDidChange: ((TabBarOrderMode) -> Void)?

    @objc var order: TabBarOrderMode = .manual {
        didSet {
            updateOrderAppearance()
        }
    }
    /// The query changed.
    @objc var queryDidChange: ((String) -> Void)?
    /// Return: go to the first match.
    @objc var commit: (() -> Void)?
    /// Esc: stop searching.
    @objc var cancel: (() -> Void)?

    @objc var query: String {
        return searchField.stringValue
    }
    // Typing sends both the action and controlTextDidChange; the clear button
    // sends only the action. Report each value once.
    private var reported = ""

    override init() {
        searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        orderButton = NSButton(frame: NSRect(x: 0, y: 0, width: Self.orderButtonWidth, height: 22))
        orderMenu = NSMenu()
        accessoryView = AccessoryView(frame: NSRect(x: 0, y: 0, width: 100, height: Self.accessoryHeight))
        super.init()
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.sizeToFit()
        searchField.placeholderString = String(localized: "TabBarSearch.Placeholder",
                                               defaultValue: "Search Tabs",
                                               comment: "Placeholder in the search field at the top of a vertical tab bar. Typing in it hides tabs that don't match.")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldDidChange(_:))

        let items: [(TabBarOrderMode, String, String)] = [
            (.manual,
             String(localized: "TabBarOrder.ManualMenuItem",
                    defaultValue: "Ungrouped",
                    comment: "Menu item in the menu that orders a vertical tab bar. Shows tabs in the order the user arranged them, with their groups."),
             String(localized: "TabBarOrder.ManualToolTip",
                    defaultValue: "Show tabs in the order you arranged them, with their groups",
                    comment: "Tooltip for the menu item that shows a vertical tab bar in the order the user arranged it")),
            (.status,
             String(localized: "TabBarOrder.StatusMenuItem",
                    defaultValue: "By Status",
                    comment: "Menu item in the menu that orders a vertical tab bar. Sorts tabs by their status, most urgent first."),
             String(localized: "TabBarOrder.StatusToolTip",
                    defaultValue: "Sort tabs by status, most urgent first. Snoozed tabs go last.",
                    comment: "Tooltip for the menu item that sorts a vertical tab bar by status")),
            (.workingDirectory,
             String(localized: "TabBarOrder.DirectoryMenuItem",
                    defaultValue: "By Directory",
                    comment: "Menu item in the menu that orders a vertical tab bar. Shows tabs in a section for each working directory."),
             String(localized: "TabBarOrder.DirectoryToolTip",
                    defaultValue: "Show tabs in a section for each working directory",
                    comment: "Tooltip for the menu item that orders a vertical tab bar by working directory"))
        ]
        for (mode, title, toolTip) in items {
            let item = NSMenuItem(title: title, action: #selector(orderMenuItemPicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.toolTip = toolTip
            orderMenu.addItem(item)
        }

        orderButton.isBordered = false
        orderButton.bezelStyle = .regularSquare
        orderButton.imagePosition = .imageOnly
        orderButton.image = NSImage(systemSymbolName: SFSymbol.arrowUpArrowDown.rawValue,
                                    accessibilityDescription: String(localized: "TabBarOrder.ButtonAccessibility",
                                                                     defaultValue: "Order Tabs",
                                                                     comment: "Accessibility description of the button beside a vertical tab bar's search field that opens a menu of orders for the tabs"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        orderButton.target = self
        orderButton.action = #selector(showOrderMenu(_:))
        // As a menu button does, so press, drag, and release picks an item.
        orderButton.sendAction(on: [.leftMouseDown])

        // The field, then the button, laid out from the view's bounds. The
        // tab bar sets the view's width whenever its own changes.
        accessoryView.autoresizingMask = []
        if let accessoryView = accessoryView as? AccessoryView {
            accessoryView.layoutSubviewsInBounds = { [weak self] bounds in
                self?.layOut(in: bounds)
            }
        }
        accessoryView.addSubview(searchField)
        accessoryView.addSubview(orderButton)
        layOut(in: accessoryView.bounds)
        updateOrderAppearance()
    }

    private func layOut(in bounds: NSRect) {
        let buttonWidth = min(Self.orderButtonWidth, bounds.width)
        orderButton.frame = NSRect(x: bounds.maxX - buttonWidth,
                                   y: bounds.minY,
                                   width: buttonWidth,
                                   height: bounds.height)
        searchField.frame = NSRect(x: bounds.minX,
                                   y: bounds.minY,
                                   width: max(0, bounds.width - buttonWidth - Self.spacing),
                                   height: searchField.frame.height)
    }

    // The button is tinted while the bar is sorted, so it's clear the order
    // isn't the usual one.
    private func updateOrderAppearance() {
        for item in orderMenu.items {
            item.state = (item.tag == order.rawValue) ? .on : .off
        }
        orderButton.contentTintColor = (order == .manual) ? .secondaryLabelColor : .controlAccentColor
        switch order {
        case .manual:
            orderButton.toolTip = String(localized: "TabBarOrder.ButtonToolTip.Manual",
                                         defaultValue: "Order tabs. Tabs are in the order you arranged them.",
                                         comment: "Tooltip for the button beside a vertical tab bar's search field that opens a menu of orders, while the tabs are in the user's order")
        case .status:
            orderButton.toolTip = String(localized: "TabBarOrder.ButtonToolTip.Status",
                                         defaultValue: "Order tabs. Tabs are sorted by status.",
                                         comment: "Tooltip for the button beside a vertical tab bar's search field that opens a menu of orders, while the tabs are sorted by status")
        case .workingDirectory:
            orderButton.toolTip = String(localized: "TabBarOrder.ButtonToolTip.Directory",
                                         defaultValue: "Order tabs. Tabs are in a section for each directory.",
                                         comment: "Tooltip for the button beside a vertical tab bar's search field that opens a menu of orders, while the tabs are in sections by working directory")
        }
    }

    @objc private func showOrderMenu(_ sender: NSButton) {
        orderMenu.popUp(positioning: nil,
                        at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                        in: sender)
    }

    @objc private func orderMenuItemPicked(_ sender: NSMenuItem) {
        guard let mode = TabBarOrderMode(rawValue: sender.tag), mode != order else {
            return
        }
        DLog("Tab bar order picked: \(mode.rawValue)")
        order = mode
        orderDidChange?(mode)
    }

    /// Clears the field without reporting a change.
    @objc func clear() {
        searchField.stringValue = ""
        reported = ""
    }

    @objc private func searchFieldDidChange(_ sender: NSSearchField) {
        guard sender.stringValue != reported else {
            return
        }
        reported = sender.stringValue
        DLog("Tab bar search query is now \(reported)")
        queryDidChange?(reported)
    }

    func controlTextDidChange(_ obj: Notification) {
        searchFieldDidChange(searchField)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            commit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel?()
            return true
        default:
            return false
        }
    }
}

/// Lays its subviews out from its bounds whenever they change, so they never
/// drift the way autoresizing can after a very narrow size.
private final class AccessoryView: NSView {
    var layoutSubviewsInBounds: ((NSRect) -> Void)?

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviewsInBounds?(bounds)
    }
}

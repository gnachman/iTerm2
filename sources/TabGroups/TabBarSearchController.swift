//
//  TabBarSearchController.swift
//  iTerm2SharedARC
//
//  The search field and order control at the top of a vertical tab bar. It
//  reports what's typed, the keys that end a search, and the order picked;
//  the window does the filtering and ordering (see TabBarSearch and
//  TabBarOrder).
//

import AppKit

@objc(iTermTabBarSearchController)
final class TabBarSearchController: NSObject, NSSearchFieldDelegate {
    private static let spacing: CGFloat = 6

    /// Height of the band the field and order control sit in. The window adds
    /// it to the tab bar's top inset.
    @objc static let bandHeight: CGFloat = accessoryHeight + 10

    // Measured once: the tab bar asks for the band on every layout.
    private static let accessoryHeight: CGFloat = {
        let field = NSSearchField()
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.sizeToFit()
        return field.frame.height + spacing + orderControlHeight
    }()

    private static let orderControlHeight: CGFloat = {
        let control = NSSegmentedControl(labels: ["X"], trackingMode: .selectOne, target: nil, action: nil)
        control.controlSize = .small
        control.sizeToFit()
        return control.frame.height
    }()

    /// Holds the field and the order control. The tab bar shows this.
    @objc let accessoryView: NSView
    @objc let searchField: NSSearchField
    /// Manual, Status, or Working Directory, by TabBarOrderMode raw value.
    @objc let orderControl: NSSegmentedControl
    /// The user picked an order.
    @objc var orderDidChange: ((TabBarOrderMode) -> Void)?

    @objc var order: TabBarOrderMode {
        get {
            return TabBarOrderMode(rawValue: orderControl.selectedSegment) ?? .manual
        }
        set {
            orderControl.selectedSegment = newValue.rawValue
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
        let labels = [
            String(localized: "TabBarOrder.Manual",
                   defaultValue: "Manual",
                   comment: "Segment in a control at the top of a vertical tab bar. Shows tabs in the order the user arranged them."),
            String(localized: "TabBarOrder.Status",
                   defaultValue: "Status",
                   comment: "Segment in a control at the top of a vertical tab bar. Shows tabs sorted by their status, most urgent first."),
            String(localized: "TabBarOrder.Directory",
                   defaultValue: "Directory",
                   comment: "Segment in a control at the top of a vertical tab bar. Shows tabs in sections by working directory. Kept short because the bar is narrow.")
        ]
        orderControl = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
        accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: Self.accessoryHeight))
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

        orderControl.controlSize = .small
        orderControl.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        orderControl.segmentDistribution = .fillEqually
        orderControl.sizeToFit()
        orderControl.selectedSegment = TabBarOrderMode.manual.rawValue
        orderControl.target = self
        orderControl.action = #selector(orderControlDidChange(_:))
        orderControl.setToolTip(String(localized: "TabBarOrder.ManualToolTip",
                                       defaultValue: "Show tabs in the order you arranged them, with their groups",
                                       comment: "Tooltip for the Manual segment of the control that orders a vertical tab bar"),
                                forSegment: TabBarOrderMode.manual.rawValue)
        orderControl.setToolTip(String(localized: "TabBarOrder.StatusToolTip",
                                       defaultValue: "Sort tabs by status, most urgent first. Snoozed tabs go last.",
                                       comment: "Tooltip for the Status segment of the control that orders a vertical tab bar"),
                                forSegment: TabBarOrderMode.status.rawValue)
        orderControl.setToolTip(String(localized: "TabBarOrder.DirectoryToolTip",
                                       defaultValue: "Show tabs in a section for each working directory. Tabs waiting at a shell prompt go last.",
                                       comment: "Tooltip for the Directory segment of the control that orders a vertical tab bar"),
                                forSegment: TabBarOrderMode.workingDirectory.rawValue)

        // The field above the order control, both as wide as the view. The
        // tab bar sets the view's width whenever its own changes.
        accessoryView.autoresizingMask = []
        accessoryView.autoresizesSubviews = true
        let width = accessoryView.frame.width
        let controlHeight = Self.orderControlHeight
        orderControl.frame = NSRect(x: 0, y: 0, width: width, height: controlHeight)
        orderControl.autoresizingMask = [.width]
        searchField.frame = NSRect(x: 0,
                                   y: controlHeight + Self.spacing,
                                   width: width,
                                   height: searchField.frame.height)
        searchField.autoresizingMask = [.width]
        accessoryView.addSubview(searchField)
        accessoryView.addSubview(orderControl)
    }

    @objc private func orderControlDidChange(_ sender: NSSegmentedControl) {
        DLog("Tab bar order picked: \(order.rawValue)")
        orderDidChange?(order)
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

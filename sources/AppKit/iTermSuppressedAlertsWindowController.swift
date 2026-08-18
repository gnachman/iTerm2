//
//  iTermSuppressedAlertsWindowController.swift
//  iTerm2
//
//  A panel that lists alerts currently being auto-answered (suppressed) and lets
//  the user un-suppress them so they will be shown again.
//

import AppKit

@objc(iTermSuppressedAlertsWindowController)
class iTermSuppressedAlertsWindowController: NSWindowController {
    private enum Column {
        static let alert = NSUserInterfaceItemIdentifier("alert")
        static let response = NSUserInterfaceItemIdentifier("response")
        static let when = NSUserInterfaceItemIdentifier("when")
    }

    @objc(sharedInstance) static let shared = iTermSuppressedAlertsWindowController()

    private var tableView: NSTableView!
    private var unsuppressButton: NSButton!
    private var unsuppressAllButton: NSButton!
    private var showRememberedCheckbox: NSButton!
    private var emptyLabel: NSTextField!
    private var alerts: [iTermSuppressedAlert] = []

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered,
                            defer: true)
        panel.title = "Suppressed Alerts"
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 480, height: 260)
        // This is a reused singleton window; without this, a programmatic NSWindow
        // is released on close and the next open would be a use-after-free.
        panel.isReleasedWhenClosed = false
        panel.center()

        super.init(window: panel)

        panel.delegate = self
        buildContentView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(suppressedAlertsDidChange(_:)),
            name: .iTermSuppressedAlertsDidChange,
            object: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Content

    private func buildContentView() {
        guard let content = window?.contentView else {
            return
        }
        let margin: CGFloat = 20
        let buttonHeight: CGFloat = 32
        let checkboxHeight: CGFloat = 18
        let checkboxGap: CGFloat = 10
        // Buttons on the bottom row, the "always show" checkbox on a row above them.
        let bottomBarHeight = margin * 2 + buttonHeight + checkboxGap + checkboxHeight
        let bounds = content.bounds

        // Explanatory text at the top.
        let explanation = label(withText: "These alerts are being answered automatically because you " +
                                          "chose to remember your response. Select one and click " +
                                          "Un-suppress to be asked again.")
        explanation.frame = NSRect(x: margin,
                                   y: bounds.maxY - margin - 40,
                                   width: bounds.width - margin * 2,
                                   height: 40)
        explanation.autoresizingMask = [.width, .minYMargin]
        content.addSubview(explanation)

        // Scroll view + table filling the middle.
        let tableTop = explanation.frame.minY - 10
        let tableBottom = bottomBarHeight
        let scrollView = NSScrollView(frame: NSRect(x: margin,
                                                    y: tableBottom,
                                                    width: bounds.width - margin * 2,
                                                    height: tableTop - tableBottom))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        let table = NSTableView(frame: scrollView.bounds)
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        // We size the Alert column ourselves in resizeColumns so it fills the
        // available width and its text wraps onto as many lines as needed.
        table.columnAutoresizingStyle = .noColumnAutoresizing

        let whenColumn = NSTableColumn(identifier: Column.when)
        whenColumn.title = "Last Suppressed"
        whenColumn.width = 130
        whenColumn.minWidth = 100

        let responseColumn = NSTableColumn(identifier: Column.response)
        responseColumn.title = "Automatic Response"
        responseColumn.width = 150
        responseColumn.minWidth = 100

        let alertColumn = NSTableColumn(identifier: Column.alert)
        alertColumn.title = "Alert"
        alertColumn.width = 260
        // Kept small enough that alertMin + the two fixed columns + intercell gaps
        // fit within the panel's minimum content width, so no column is ever clipped.
        alertColumn.minWidth = 120
        // Let the message text wrap onto multiple lines.
        if let alertCell = alertColumn.dataCell as? NSTextFieldCell {
            alertCell.wraps = true
            alertCell.lineBreakMode = .byWordWrapping
            alertCell.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }

        table.addTableColumn(alertColumn)
        table.addTableColumn(responseColumn)
        table.addTableColumn(whenColumn)
        table.doubleAction = #selector(tableDoubleClicked(_:))
        table.target = self

        scrollView.documentView = table
        content.addSubview(scrollView)
        tableView = table

        // Empty-state label centered over the table area.
        let empty = label(withText: "No alerts are currently being suppressed.")
        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        empty.frame = NSRect(x: margin,
                             y: tableBottom + (tableTop - tableBottom) / 2 - 10,
                             width: bounds.width - margin * 2,
                             height: 20)
        empty.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        empty.isHidden = true
        content.addSubview(empty)
        emptyLabel = empty

        // Bottom buttons.
        let doneButton = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.sizeToFit()
        var doneFrame = doneButton.frame
        doneFrame.size.width = max(90, doneFrame.size.width)
        doneFrame.size.height = buttonHeight
        doneFrame.origin.x = bounds.maxX - margin - doneFrame.size.width
        doneFrame.origin.y = margin
        doneButton.frame = doneFrame
        doneButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(doneButton)

        let unsuppress = NSButton(title: "Un-suppress", target: self, action: #selector(unsuppress(_:)))
        unsuppress.bezelStyle = .rounded
        unsuppress.sizeToFit()
        var unsuppressFrame = unsuppress.frame
        unsuppressFrame.size.width = max(110, unsuppressFrame.size.width)
        unsuppressFrame.size.height = buttonHeight
        unsuppressFrame.origin.x = doneFrame.minX - 8 - unsuppressFrame.size.width
        unsuppressFrame.origin.y = margin
        unsuppress.frame = unsuppressFrame
        unsuppress.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(unsuppress)
        unsuppressButton = unsuppress

        let unsuppressAll = NSButton(title: "Un-suppress All", target: self, action: #selector(unsuppressAll(_:)))
        unsuppressAll.bezelStyle = .rounded
        unsuppressAll.sizeToFit()
        var allFrame = unsuppressAll.frame
        allFrame.size.width = max(120, allFrame.size.width)
        allFrame.size.height = buttonHeight
        allFrame.origin.x = margin
        allFrame.origin.y = margin
        unsuppressAll.frame = allFrame
        unsuppressAll.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(unsuppressAll)
        unsuppressAllButton = unsuppressAll

        // "Always show alerts with remembered selections" checkbox, on a row above
        // the buttons. This is the transient mode that used to live in the View
        // menu: when on, remembered alerts are shown again so you can change your
        // response.
        let checkbox = NSButton(checkboxWithTitle: "Always show alerts with remembered selections",
                                target: self,
                                action: #selector(toggleShowRemembered(_:)))
        checkbox.sizeToFit()
        var checkFrame = checkbox.frame
        checkFrame.size.height = checkboxHeight
        checkFrame.origin.x = margin
        checkFrame.origin.y = margin + buttonHeight + checkboxGap
        checkbox.frame = checkFrame
        checkbox.autoresizingMask = [.maxXMargin, .maxYMargin]
        checkbox.toolTip = "When you check “Remember my choice” or “Suppress this message " +
                           "permanently” in an alert, iTerm2 stops showing it and reuses your " +
                           "saved response. Turn this on to show those alerts again so you can " +
                           "see them or choose differently. It stays on until you turn it off."
        content.addSubview(checkbox)
        showRememberedCheckbox = checkbox
    }

    private func label(withText text: String) -> NSTextField {
        let label = NSTextField(frame: .zero)
        label.stringValue = text
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        return label
    }

    // MARK: - API

    override func showWindow(_ sender: Any?) {
        showRememberedCheckbox.state = iTermWarning.showRememberedAlerts ? .on : .off
        reload()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    // MARK: - Actions

    @objc private func done(_ sender: Any?) {
        close()
    }

    @objc private func unsuppress(_ sender: Any?) {
        unsuppress(rows: tableView.selectedRowIndexes)
    }

    // Double-click. Act only on the clicked row; a double-click in the empty area
    // below the last row (clickedRow == -1) is a no-op even if a row is selected.
    @objc private func tableDoubleClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        if row < 0 {
            return
        }
        unsuppress(rows: IndexSet(integer: row))
    }

    private func unsuppress(rows: IndexSet) {
        let identifiers = rows.compactMap { $0 < alerts.count ? alerts[$0].identifier : nil }
        for identifier in identifiers {
            iTermSuppressedAlerts.sharedInstance.unsuppressIdentifier(identifier)
        }
        // reload happens via the change notification.
    }

    @objc private func unsuppressAll(_ sender: Any?) {
        iTermSuppressedAlerts.sharedInstance.unsuppressAll()
    }

    @objc private func toggleShowRemembered(_ sender: Any?) {
        iTermWarning.showRememberedAlerts = (showRememberedCheckbox.state == .on)
    }

    // MARK: - Data

    @objc private func suppressedAlertsDidChange(_ notification: Notification) {
        reload()
    }

    private func reload() {
        // Preserve the selection by identity: reload can fire asynchronously (a
        // background suppression, or menu validation pruning a lapsed entry) and
        // reorder rows, so keeping the raw selected index would point at a
        // different alert.
        let selectedIdentifiers = Set(tableView.selectedRowIndexes.compactMap {
            $0 < alerts.count ? alerts[$0].identifier : nil
        })

        alerts = iTermSuppressedAlerts.sharedInstance.currentlySuppressedAlerts()
        // Size columns first so reloadData computes each variable row height at the
        // correct Alert-column width. reloadData must run before any
        // noteHeightOfRows(withIndexes:) so we never reference rows the table does
        // not yet know about.
        resizeColumns()
        tableView.reloadData()

        var rowsToSelect = IndexSet()
        for (i, alert) in alerts.enumerated() where selectedIdentifiers.contains(alert.identifier) {
            rowsToSelect.insert(i)
        }
        tableView.selectRowIndexes(rowsToSelect, byExtendingSelection: false)

        emptyLabel.isHidden = !alerts.isEmpty
        updateButtonsEnabled()
    }

    // Size the Alert column to fill the remaining width so its text wraps to fit.
    // Does not touch row heights (see reload / windowDidResize for that).
    private func resizeColumns() {
        guard let alertColumn = tableView.tableColumn(withIdentifier: Column.alert),
              let responseColumn = tableView.tableColumn(withIdentifier: Column.response),
              let whenColumn = tableView.tableColumn(withIdentifier: Column.when),
              let scrollView = tableView.enclosingScrollView else {
            return
        }
        let available = scrollView.contentView.bounds.width
        // A three-column table has three intercell gaps.
        let spacing = tableView.intercellSpacing.width * CGFloat(tableView.numberOfColumns)
        let alertWidth = max(alertColumn.minWidth,
                             available - responseColumn.width - whenColumn.width - spacing)
        alertColumn.width = alertWidth
        let total = alertWidth + responseColumn.width + whenColumn.width + spacing
        var tableFrame = tableView.frame
        tableFrame.size.width = total
        tableView.frame = tableFrame
        // The columns fit within the panel's minimum size, so normally there is no
        // horizontal scrolling. Enable a scroller only as a safety net if the
        // columns somehow exceed the visible width, so the last column can't become
        // unreachable.
        scrollView.hasHorizontalScroller = (total > available + 0.5)
    }

    private func noteAllRowHeights() {
        let n = tableView.numberOfRows
        if n > 0 {
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<n))
        }
    }

    // The text shown in the Alert column: the heading (if any) on its own line
    // followed by the full message so it can wrap freely.
    private func alertColumnString(for alert: iTermSuppressedAlert) -> String {
        let heading = alert.heading ?? ""
        if !heading.isEmpty && !alert.title.isEmpty {
            return "\(heading)\n\(alert.title)"
        }
        return heading.isEmpty ? alert.title : heading
    }

    private func updateButtonsEnabled() {
        unsuppressButton.isEnabled = tableView.numberOfSelectedRows > 0
        unsuppressAllButton.isEnabled = !alerts.isEmpty
    }
}

// MARK: - NSWindowDelegate

extension iTermSuppressedAlertsWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        resizeColumns()
        // Rows already exist here, so it is safe to invalidate their heights for
        // the new Alert-column width.
        noteAllRowHeights()
    }
}

// MARK: - NSTableViewDataSource

extension iTermSuppressedAlertsWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return alerts.count
    }

    func tableView(_ tableView: NSTableView,
                   objectValueFor tableColumn: NSTableColumn?,
                   row: Int) -> Any? {
        guard row >= 0 && row < alerts.count else {
            return nil
        }
        let alert = alerts[row]
        switch tableColumn?.identifier {
        case Column.when:
            return DateFormatter.dateDifferenceString(from: alert.lastSuppressed, options: .lowercase)
        case Column.response:
            return alert.selectionLabel
        default:
            return alertColumnString(for: alert)
        }
    }
}

// MARK: - NSTableViewDelegate

extension iTermSuppressedAlertsWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0 && row < alerts.count,
              let alertColumn = tableView.tableColumn(withIdentifier: Column.alert) else {
            return tableView.rowHeight
        }
        // Leave a little room for the cell's built-in horizontal inset.
        let width = max(20, alertColumn.width - 4)
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = alertColumnString(for: alerts[row]) as NSString
        let rect = text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                     attributes: [.font: font])
        return max(tableView.rowHeight, ceil(rect.height) + 6)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonsEnabled()
    }

    func tableView(_ tableView: NSTableView,
                   toolTipFor cell: NSCell,
                   rect: NSRectPointer,
                   tableColumn: NSTableColumn?,
                   row: Int,
                   mouseLocation: NSPoint) -> String {
        guard row >= 0 && row < alerts.count else {
            return ""
        }
        return alerts[row].title
    }
}

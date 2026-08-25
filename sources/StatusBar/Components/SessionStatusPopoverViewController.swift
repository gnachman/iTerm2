//
//  SessionStatusPopoverViewController.swift
//  iTerm2SharedARC
//

import Foundation

/// The list behind the Session Status status bar component. Rows are
/// `ToolStatusCellView` — the same cell the Session Status toolbelt tool
/// uses — so a session reads identically in both places: dot, optional peer
/// label, name, shortcut, status text, and wrapped detail.
class SessionStatusPopoverViewController: NSViewController {
    /// Called with the session ID of a clicked row.
    var onSelect: ((String) -> Void)?

    private let entries: [SessionStatusEntry]
    /// The session whose status bar opened this popover. Shortcut labels are
    /// relative to it, the way the toolbelt's are relative to its window's
    /// current session.
    private let activeSessionGUID: String?
    private var tableView: NSTableView?
    private var measuringCell: ToolStatusCellView?

    private static let width: CGFloat = 320
    private static let maxHeight: CGFloat = 400
    private static let minHeight: CGFloat = 24

    init(entries: [SessionStatusEntry], activeSessionGUID: String?) {
        self.entries = entries
        self.activeSessionGUID = activeSessionGUID
        super.init(nibName: nil, bundle: nil)
        // Provisional so a caller that reads preferredContentSize before the
        // view loads gets a sane value. loadView() replaces it with the exact
        // size once the table has tiled its frame (which includes the styled
        // table's own row insets, unlike a hand-summed row total).
        preferredContentSize = NSSize(width: Self.width, height: contentHeight())
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))

        let scrollView = NSScrollView(frame: container.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SessionStatus"))
        column.width = Self.width
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        self.tableView = tableView
        self.view = container

        // Size to the table's real height. As the scroll view's document view
        // the table tiles its own frame to fit all rows *plus* the styled
        // NSTableView's built-in vertical inset, which a hand-summed row total
        // omits; reading that frame height is what keeps the last row from
        // being clipped (and avoids intrinsicContentSize / auto layout).
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        let height = min(Self.maxHeight, max(Self.minHeight, tableView.frame.height))
        preferredContentSize = NSSize(width: Self.width, height: height)
        container.setFrameSize(preferredContentSize)
    }

    // MARK: - Layout

    /// A provisional height for before the table exists; loadView() supersedes
    /// it with the table's tiled frame height. Undersizes by the table's inset,
    /// so it is only a floor, never the final popover height.
    private func contentHeight() -> CGFloat {
        let total = entries.reduce(CGFloat(0)) { partial, entry in
            partial + height(of: entry)
        }
        return min(Self.maxHeight, max(Self.minHeight, total))
    }

    /// Measures a row the way ToolStatus does: configure one reusable
    /// offscreen cell and ask for its fitting size, since detail text wraps
    /// to a variable number of lines.
    private func height(of entry: SessionStatusEntry) -> CGFloat {
        let cell = measuringCell ?? ToolStatusCellView(frame: .zero)
        measuringCell = cell
        configure(cell, with: entry)
        cell.frame = NSRect(x: 0, y: 0, width: Self.width, height: 0)
        cell.needsLayout = true
        cell.layoutSubtreeIfNeeded()
        return cell.fittingSize.height
    }

    // MARK: - Cell configuration

    private func configure(_ cell: ToolStatusCellView, with entry: SessionStatusEntry) {
        guard let session = iTermController.sharedInstance()?.anySession(withGUID: entry.sessionID) else {
            // The session went away between the popover being built and this
            // row being drawn. configure() is self-clearing but is skipped
            // here, so blank the recycled cell explicitly.
            cell.clear()
            return
        }
        let tabStatus = entry.tabStatus

        var dotImage: NSImage?
        if tabStatus.hasIndicator {
            let c = tabStatus.indicatorColor
            let color = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
            dotImage = iTermSessionTabStatus.dotImage(color: color, size: 10, dotDiameter: 6)
        }

        var statusColor: NSColor?
        if tabStatus.hasStatusTextColor {
            let c = tabStatus.statusTextColor
            statusColor = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }

        cell.configure(scope: session.genericScope,
                       dotImage: dotImage,
                       peerLabel: session.peerDisplayLabel,
                       shortcut: SessionStatusShortcut.shortcutString(for: entry.sessionID,
                                                                      activeSessionGUID: activeSessionGUID),
                       statusText: tabStatus.statusText,
                       statusColor: statusColor,
                       detail: tabStatus.detailText,
                       armed: NotifyOnStatusChangeController.instance.isSessionArmed(
                        forGuid: entry.sessionID))
    }
}

extension SessionStatusPopoverViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }
}

extension SessionStatusPopoverViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row >= 0, row < entries.count else {
            return nil
        }
        let identifier = NSUserInterfaceItemIdentifier("SessionStatusPopoverCell")
        let cell: ToolStatusCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? ToolStatusCellView {
            cell = reused
        } else {
            cell = ToolStatusCellView(frame: .zero)
            cell.identifier = identifier
        }
        configure(cell, with: entries[row])
        return cell
    }

    // @objc is required: this is an optional NSTableViewDelegate method, and
    // without the explicit selector the table never calls it and falls back to
    // its default row height, clipping the multi-line rows.
    @objc(tableView:heightOfRow:)
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < entries.count else {
            return Self.minHeight
        }
        return height(of: entries[row])
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let row = tableView?.selectedRow, row >= 0, row < entries.count else {
            return
        }
        onSelect?(entries[row].sessionID)
    }
}
